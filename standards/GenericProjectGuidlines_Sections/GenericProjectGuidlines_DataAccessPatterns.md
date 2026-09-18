# Chapter 8 — Data Access Patterns

> *Section file for `GenericProjectGuidlines_V1.11_20260904.md`*
>
> **⚠️ Sync rule — agent instruction:** This is a section file. Any change made here **must be mirrored in the corresponding chapter** of `GenericProjectGuidlines_V1.11_20260904.md`. Any change made in the parent document's corresponding chapter must be mirrored back here. Both files must remain identical in content for their shared sections.
>
> **TOC Maintenance:** If this section is renamed or deleted, update both the parent document's Contents list AND the `GenericProjectGuidlines_TOC.md` file. See the TOC file for detailed maintenance instructions.

---

All database access follows one consistent pattern. Ad-hoc queries scattered across controllers, Blazor components, or service classes are not acceptable. Every data operation flows through a defined data access class or repository.

## Central DataAccess Class (Blazor-Direct Pattern)

```csharp
// {AppName}.Website/Models/DataAccess.cs
// All queries call stored procedures. Direct LINQ against DbSet is not permitted.
public class DataAccess(AppDbContext dbContext, ILogger<DataAccess> logger)
{
    private readonly AppDbContext _dbContext = dbContext;
    private readonly ILogger<DataAccess> _logger = logger;

    // Read: sps_Coin_GetByGuid → v_Coin → Coin table
    public async Task<Coin?> GetCoinByGuidAsync(Guid coinGuid)
    {
        var param = new SqlParameter("@CoinGuid", coinGuid);
        return await _dbContext.Coins
            .FromSqlRaw("EXEC sps_Coin_GetByGuid @CoinGuid", param)
            .AsNoTracking()
            .FirstOrDefaultAsync();
    }

    // Write: spi_Coin_Create → Coin table
    public async Task CreateCoinAsync(Coin coin)
        => await _dbContext.Database.ExecuteSqlRawAsync(
            "EXEC spi_Coin_Create @Name, @CoinGuid, @CreatedUser",
            new SqlParameter("@Name", coin.Name ?? ""),
            new SqlParameter("@CoinGuid", coin.CoinGUID),
            new SqlParameter("@CreatedUser", coin.CreatedUser ?? ""));
}
```

## Repository Interface (API Pattern)

```csharp
// {AppName}.Domain/Interfaces/ICoinRepository.cs
public interface ICoinRepository
{
    Task<Coin?>              GetByGuidAsync(Guid guid);
    Task<IEnumerable<Coin>> GetAllAsync();
    Task<Coin>              AddAsync(Coin newCoin);
    Task                   UpdateAsync(Coin coin);
    Task                   SoftDeleteAsync(Guid guid, string deletedByUser);
}
```

### Repository Implementation — Stored Procedure Calls

```csharp
// {AppName}.Infrastructure/Repositories/CoinRepository.cs
// Read path:  sps_ → v_ → table
// Write path: spi_/spu_/spd_ → table
public class CoinRepository(AppDbContext dbContext) : ICoinRepository
{
    public async Task<Coin?> GetByGuidAsync(Guid guid)
    {
        var param = new SqlParameter("@CoinGuid", guid);
        return await dbContext.Coins
            .FromSqlRaw("EXEC sps_Coin_GetByGuid @CoinGuid", param)
            .AsNoTracking()
            .FirstOrDefaultAsync();
    }

    public async Task<IEnumerable<Coin>> GetAllAsync()
        => await dbContext.Coins
            .FromSqlRaw("EXEC sps_Coin_GetAll")
            .AsNoTracking()
            .ToListAsync();

    public async Task SoftDeleteAsync(Guid guid, string deletedByUser)
        => await dbContext.Database.ExecuteSqlRawAsync(
            "EXEC spd_Coin_SoftDelete @CoinGuid, @DeletedUser",
            new SqlParameter("@CoinGuid", guid),
            new SqlParameter("@DeletedUser", deletedByUser));
}
```

## Data Access Rules

- **MUST** All application database access must go through stored procedures. Direct LINQ queries against `DbSet<T>` without a stored procedure are never permitted in any tier.
- **MUST** Read operations must call a `sps_` stored procedure, which in turn queries a `v_` view. Application code must never read directly from a table, even via EF Core `FromSqlRaw` targeting the table name.
- **MUST** Write operations must call the appropriate `spi_`, `spu_`, or `spd_` stored procedure. Application code must never write directly to a table.
- **MUST** All database methods are `async`/`await`. Never use `.Result`, `.Wait()`, or synchronous EF Core methods.
- **MUST** Never access `DbContext` directly from a Blazor component or an API controller. Always go through `DataAccess` or a repository.
- **MUST** On every insert, pass `CreatedUser` and `LastUpdatedUser` to the stored procedure. On every update, pass `LastUpdatedDate` and `LastUpdatedUser`.
- **MUST** Soft-delete calls the `spd_` procedure passing `IsDeleted = true`, `DeletedDate`, and `DeletedUser`. Never call `dbContext.Remove()` on a domain entity.
- **MUST** Wrap multi-step stored-procedure calls in a single `DbContext` transaction when all steps must succeed or all must fail.
- **MUST** The stored-procedure mandate applies to **all** database tables without exception, including tables managed by third-party frameworks (e.g., ASP.NET Core Identity's `AspNetUsers`, `AspNetRoles`, and related tables). No framework default or convenience API overrides this rule. Any conflict between a framework's built-in data access mechanism and this mandate must be resolved before implementation begins — the resolution must be documented and approved; it cannot be assumed.
- **MUST** Cross-database stored procedure calls must be proxied through a local wrapper SP in the calling database (naming convention: `_sp_` prefix). Application code and composition SPs in the calling DB invoke the local wrapper — never the remote SP directly by three-part name. This confines knowledge of the remote database's SP signatures to the wrapper layer only, reducing structural exposure across DB boundaries.

> **Addition — 2026-09-04:** Every `sps_` procedure's `@IsActive`/`@IsDeleted` filter parameters
> (Chapter 7 — Database Architecture) carry SQL-side defaults (`= 1` / `= 0`), so this does not
> change the call signatures shown above — a caller wanting the default active/non-deleted result
> set omits them entirely, exactly as `EXEC sps_Coin_GetByGuid @CoinGuid` already does.

- **MUST** A caller overrides `@IsActive`/`@IsDeleted` only for a documented reason (e.g., an admin/audit screen that must see inactive or soft-deleted rows), and must never filter Active/Deleted rows itself after the SP returns — the SP is the sole enforcement point, per Chapter 7's rule.

## ASP.NET Core Identity Integration Policy

### The Conflict

ASP.NET Core Identity ships with `UserManager<T>` and `SignInManager<T>`, which execute LINQ queries directly against `DbSet<T>`. These convenience APIs bypass stored procedures entirely, violating the SP-only mandate above.

### Resolution — No Exemptions

The SP mandate applies to **all** tables without exception, including the five ASP.NET Identity tables (`AspNetUsers`, `AspNetRoles`, `AspNetUserRoles`, `AspNetUserClaims`, `AspNetUserLogins`). `UserManager<T>` and `SignInManager<T>` are **not permitted** in production service code. They are not exempt.

ASP.NET Identity tables remain part of the schema and are managed by Identity's migrations — but all **runtime reads and writes** go through stored procedures called via raw SQL on `DbContext.Database`, following the same pattern as all other tables.

### Implementation Pattern

```csharp
// Direct SP call — no UserManager; no LINQ against AspNetUsers
public async Task<ApplicationUser?> FindUserByEmailAsync(string normalizedEmail, CancellationToken ct)
{
    var param = new SqlParameter("@NormalizedEmail", normalizedEmail);
    return await _dbContext.Users
        .FromSqlRaw("EXEC sps_User_GetByNormalizedEmail @NormalizedEmail", param)
        .AsNoTracking()
        .FirstOrDefaultAsync(ct);
}

public async Task CreateUserAsync(ApplicationUser user, string passwordHash, CancellationToken ct)
    => await _dbContext.Database.ExecuteSqlRawAsync(
        "EXEC spi_User_Create @Id, @UserName, @NormalizedUserName, @Email, @NormalizedEmail, @PasswordHash, @SecurityStamp, @ConcurrencyStamp, @CreatedUser",
        new SqlParameter("@Id",                 user.Id),
        new SqlParameter("@UserName",           user.UserName ?? ""),
        new SqlParameter("@NormalizedUserName", user.NormalizedUserName ?? ""),
        new SqlParameter("@Email",              user.Email ?? ""),
        new SqlParameter("@NormalizedEmail",    user.NormalizedEmail ?? ""),
        new SqlParameter("@PasswordHash",       passwordHash),
        new SqlParameter("@SecurityStamp",      user.SecurityStamp ?? ""),
        new SqlParameter("@ConcurrencyStamp",   user.ConcurrencyStamp ?? ""),
        new SqlParameter("@CreatedUser",        user.Email ?? ""),
        ct);
```

### Scaffold Retention

ASP.NET Identity scaffolding (`AddIdentityCore<T>`, `AddEntityFrameworkStores<T>`) is retained for:
- Password hashing via `IPasswordHasher<T>` — called in service code, not via UserManager
- Schema management — Identity's `EnsureCreated` / `Migrate` creates `AspNetUsers` and the four supporting tables

Scaffolding is **not** retained for runtime data access. No call to `UserManager.CreateAsync`, `FindByEmailAsync`, `CheckPasswordSignInAsync`, or any equivalent may appear in service implementation code.

### Per-Operation SP Surface

Each Identity operation that would normally go through `UserManager` or `SignInManager` must have a corresponding stored procedure:

| Operation | SP Prefix | Notes |
|-----------|-----------|-------|
| Find user by email | `sps_` | Must query via `NormalizedEmail` index |
| Find user by ID | `sps_` | |
| Create user | `spi_` | Caller must pre-hash password via `IPasswordHasher<T>` |
| Update password hash | `spu_` | |
| Update security stamp | `spu_` | Required after password/email change |
| Update lockout end | `spu_` | Lockout logic managed by AuthService |
| Increment access failed count | `spu_` | |
| Reset access failed count | `spu_` | |
| Update email / normalized email | `spu_` | |
| Soft-delete user | `spd_` | Sets `IsDeleted`, `IsActive = 0`; never hard-delete |

## Data Access Tracking (DAT)

> **Addition — 2026-09-04:** Some industries (medical among them) require demonstrating who
> accessed what data and when — a requirement the SP-only access model above enables but does not
> by itself satisfy, since `CreatedUser`/`LastUpdatedUser` account for writes only, not reads. Data
> Access Tracking (DAT) is the framework pattern that addresses this.

### Schema

`DataAccessTracking` is the live log table. Unlike `ConsentLog` (Chapter 11), it inherits
`CommonColumns` in full — DAT rows are framework-standard records, not the deliberately-bare
immutable event shape `ConsentLog` uses.

```sql
CREATE TABLE [dbo].[DataAccessTracking](
    [DataAccessTrackingID] [int] IDENTITY(1,1) NOT NULL,
    [DataAccessTrackingGUID] [uniqueidentifier] NOT NULL,
    [ProcedureName] [nvarchar](255) NOT NULL,
    [RecordID] [int] NULL,
    [RecordGUID] [uniqueidentifier] NULL,
    [ParameterName1] [nvarchar](255) NULL,
    [ParameterValue1] [nvarchar](255) NULL,
    [ParameterName2] [nvarchar](255) NULL,
    [ParameterValue2] [nvarchar](255) NULL,
    [ParameterName3] [nvarchar](255) NULL,
    [ParameterValue3] [nvarchar](255) NULL,
    [ParameterName4] [nvarchar](255) NULL,
    [ParameterValue4] [nvarchar](255) NULL,
    [ParameterName5] [nvarchar](255) NULL,
    [ParameterValue5] [nvarchar](255) NULL,
    [Name] [nvarchar](255) NULL,
    [Description] [nvarchar](2000) NULL,
    [CreatedDate] [datetime2](7) NOT NULL,
    [CreatedUser] [nvarchar](150) NULL,
    [LastUpdatedDate] [datetime2](7) NULL,
    [LastUpdatedUser] [nvarchar](150) NULL,
    [IsActive] [bit] NULL,
    [SortOrder] [int] NULL,
    [IsDeleted] [bit] NULL,
    [DeletedDate] [datetime2](7) NULL,
    [DeletedUser] [nvarchar](150) NULL,
 CONSTRAINT [PK_DataAccessTracking] PRIMARY KEY CLUSTERED 
(
    [DataAccessTrackingID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[DataAccessTracking] ADD  DEFAULT (newsequentialid()) FOR [DataAccessTrackingGUID]
GO

ALTER TABLE [dbo].[DataAccessTracking] ADD  DEFAULT (getutcdate()) FOR [CreatedDate]
GO

ALTER TABLE [dbo].[DataAccessTracking] ADD  DEFAULT ((1)) FOR [IsActive]
GO

ALTER TABLE [dbo].[DataAccessTracking] ADD  DEFAULT ((100)) FOR [SortOrder]
GO

ALTER TABLE [dbo].[DataAccessTracking] ADD  DEFAULT ((0)) FOR [IsDeleted]
GO
```

`RequestingUser` is not a separate column — `CreatedUser` holds it. `ProcedureName` records the
caller; `RecordID`/`RecordGUID` identify the specific row touched (both `NULL` for a multi-row
read, e.g. a `GetAll`); the five `ParameterName{n}`/`ParameterValue{n}` pairs are a discretionary
log of the parameters that materially describe what was accessed or changed — not every SP
parameter needs to be logged, and an SP with more than five meaningful parameters picks which five
matter most.

**Write-scale retention — `DataAccessTrackingArchive`:** at multi-million-row volume, keeping every
DAT row in the live table degrades insert latency on `DataAccessTracking` — and every tracked write
already pays that latency, since it happens inline inside the write transaction.
`DataAccessTrackingArchive` is a structurally identical sibling table that periodically absorbs
older rows so the live table stays small and writes stay fast. See **Retention —
`dat_DataAccessTracking_ArchiveData`** below, and Chapter 7's Cleanup and Retention Patterns for
this pattern's place among the framework's other retention strategies.

```sql
CREATE TABLE [dbo].[DataAccessTrackingArchive](
    [DataAccessTrackingArchiveID] [int] IDENTITY(1,1) NOT NULL,
    [DataAccessTrackingArchiveGUID] [uniqueidentifier] NOT NULL,
    [DataAccessTrackingID] [int] NOT NULL,
    [DataAccessTrackingGUID] [uniqueidentifier] NOT NULL,
    [ProcedureName] [nvarchar](255) NOT NULL,
    [RecordID] [int] NULL,
    [RecordGUID] [uniqueidentifier] NULL,
    [ParameterName1] [nvarchar](255) NULL,
    [ParameterValue1] [nvarchar](255) NULL,
    [ParameterName2] [nvarchar](255) NULL,
    [ParameterValue2] [nvarchar](255) NULL,
    [ParameterName3] [nvarchar](255) NULL,
    [ParameterValue3] [nvarchar](255) NULL,
    [ParameterName4] [nvarchar](255) NULL,
    [ParameterValue4] [nvarchar](255) NULL,
    [ParameterName5] [nvarchar](255) NULL,
    [ParameterValue5] [nvarchar](255) NULL,
    [Name] [nvarchar](255) NULL,
    [Description] [nvarchar](2000) NULL,
    [CreatedDate] [datetime2](7) NOT NULL,
    [CreatedUser] [nvarchar](150) NULL,
    [LastUpdatedDate] [datetime2](7) NULL,
    [LastUpdatedUser] [nvarchar](150) NULL,
    [IsActive] [bit] NULL,
    [SortOrder] [int] NULL,
    [IsDeleted] [bit] NULL,
    [DeletedDate] [datetime2](7) NULL,
    [DeletedUser] [nvarchar](150) NULL,
 CONSTRAINT [PK_DataAccessTrackingArchive] PRIMARY KEY CLUSTERED 
(
    [DataAccessTrackingArchiveID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[DataAccessTrackingArchive] ADD  DEFAULT (newsequentialid()) FOR [DataAccessTrackingArchiveGUID]
GO

ALTER TABLE [dbo].[DataAccessTrackingArchive] ADD  DEFAULT (getutcdate()) FOR [CreatedDate]
GO

ALTER TABLE [dbo].[DataAccessTrackingArchive] ADD  DEFAULT ((1)) FOR [IsActive]
GO

ALTER TABLE [dbo].[DataAccessTrackingArchive] ADD  DEFAULT ((100)) FOR [SortOrder]
GO

ALTER TABLE [dbo].[DataAccessTrackingArchive] ADD  DEFAULT ((0)) FOR [IsDeleted]
GO

ALTER TABLE [dbo].[DataAccessTrackingArchive]
    ADD CONSTRAINT [UQ_DataAccessTrackingArchive_DataAccessTrackingID] UNIQUE ([DataAccessTrackingID])
GO
```

`DataAccessTrackingArchive` preserves the original `DataAccessTrackingID`/`DataAccessTrackingGUID`
alongside its own identity — every column and value from the source row is carried over on
archive, not a subset, so the combined view (below) is a true, gapless history rather than a
partial one.

### View — `v_DataAccessTracking`

The read path (Chapter 7) always goes through a view; DAT is no exception, and here the view also
does real work: it `UNION ALL`s the live and archived tables into one gapless timeline, and resolves
`CreatedUser` (the requesting user's identity-DB `Id`) to a display-friendly name and the end
user's local time zone.

```sql
-- ============================================================
-- Alter view: v_DataAccessTracking
-- CreatedDate is the UTC instant the tracked action occurred, performed by
-- the end user identified in CreatedUser/RequestingUserName. The end user
-- and the ops admin viewing this data may be in different time zones, so
-- neither UTC nor the viewing admin's own local time answers "what time
-- was it for the end user." Adds EndUserTimezoneIana: CreatedUser ->
-- AspNetUsers.Id -> UserDemographics.StoredTimezoneId ->
-- StoredTimezones.IanaTimezoneId, via LEFT JOINs at every hop so a user
-- with no UserDemographics row, or a StoredTimezoneId not set, or a
-- non-user CreatedUser value (SYSTEM/ANONYMOUS/etc.) all resolve to NULL
-- rather than being dropped or defaulted — the API/UI leave the "end user
-- local time" column blank in that case, per design. Appended at the true
-- end, after every existing column, per the ordinal-safety rule.
-- ============================================================

CREATE VIEW [dbo].[v_DataAccessTracking]
AS
SELECT
    [DataAccessTracking].[DataAccessTrackingID],
    [DataAccessTracking].[DataAccessTrackingGUID],
    [DataAccessTracking].[ProcedureName],
    [DataAccessTracking].[RecordID],
    [DataAccessTracking].[RecordGUID],
    [DataAccessTracking].[ParameterName1], [DataAccessTracking].[ParameterValue1],
    [DataAccessTracking].[ParameterName2], [DataAccessTracking].[ParameterValue2],
    [DataAccessTracking].[ParameterName3], [DataAccessTracking].[ParameterValue3],
    [DataAccessTracking].[ParameterName4], [DataAccessTracking].[ParameterValue4],
    [DataAccessTracking].[ParameterName5], [DataAccessTracking].[ParameterValue5],
    [DataAccessTracking].[CreatedDate],
    [DataAccessTracking].[CreatedUser],
    [DataAccessTracking].[LastUpdatedDate],
    [DataAccessTracking].[LastUpdatedUser],
    [DataAccessTracking].[Name],
    [DataAccessTracking].[Description],
    [DataAccessTracking].[IsActive],
    [DataAccessTracking].[SortOrder],
    [DataAccessTracking].[IsDeleted],
    [DataAccessTracking].[DeletedDate],
    [DataAccessTracking].[DeletedUser],
    CAST(NULL AS INT)              AS [DataAccessTrackingArchiveID],
    CAST(NULL AS UNIQUEIDENTIFIER) AS [DataAccessTrackingArchiveGUID],
    COALESCE(au1.[UserName], [DataAccessTracking].[CreatedUser]) AS [RequestingUserName],
    st1.[IanaTimezoneId] AS [EndUserTimezoneIana]
FROM [dbo].[DataAccessTracking]
LEFT JOIN [dbo].[AspNetUsers] AS au1 ON au1.[Id] = [DataAccessTracking].[CreatedUser]
LEFT JOIN [dbo].[UserDemographics] AS ud1 ON ud1.[UserId] = au1.[Id]
LEFT JOIN [dbo].[StoredTimezones] AS st1 ON st1.[StoredTimezoneId] = ud1.[StoredTimezoneId]
UNION ALL
SELECT
    [DataAccessTrackingArchive].[DataAccessTrackingID],
    [DataAccessTrackingArchive].[DataAccessTrackingGUID],
    [DataAccessTrackingArchive].[ProcedureName],
    [DataAccessTrackingArchive].[RecordID],
    [DataAccessTrackingArchive].[RecordGUID],
    [DataAccessTrackingArchive].[ParameterName1], [DataAccessTrackingArchive].[ParameterValue1],
    [DataAccessTrackingArchive].[ParameterName2], [DataAccessTrackingArchive].[ParameterValue2],
    [DataAccessTrackingArchive].[ParameterName3], [DataAccessTrackingArchive].[ParameterValue3],
    [DataAccessTrackingArchive].[ParameterName4], [DataAccessTrackingArchive].[ParameterValue4],
    [DataAccessTrackingArchive].[ParameterName5], [DataAccessTrackingArchive].[ParameterValue5],
    [DataAccessTrackingArchive].[CreatedDate],
    [DataAccessTrackingArchive].[CreatedUser],
    [DataAccessTrackingArchive].[LastUpdatedDate],
    [DataAccessTrackingArchive].[LastUpdatedUser],
    [DataAccessTrackingArchive].[Name],
    [DataAccessTrackingArchive].[Description],
    [DataAccessTrackingArchive].[IsActive],
    [DataAccessTrackingArchive].[SortOrder],
    [DataAccessTrackingArchive].[IsDeleted],
    [DataAccessTrackingArchive].[DeletedDate],
    [DataAccessTrackingArchive].[DeletedUser],
    [DataAccessTrackingArchive].[DataAccessTrackingArchiveID],
    [DataAccessTrackingArchive].[DataAccessTrackingArchiveGUID],
    COALESCE(au2.[UserName], [DataAccessTrackingArchive].[CreatedUser]) AS [RequestingUserName],
    st2.[IanaTimezoneId] AS [EndUserTimezoneIana]
FROM [dbo].[DataAccessTrackingArchive]
LEFT JOIN [dbo].[AspNetUsers] AS au2 ON au2.[Id] = [DataAccessTrackingArchive].[CreatedUser]
LEFT JOIN [dbo].[UserDemographics] AS ud2 ON ud2.[UserId] = au2.[Id]
LEFT JOIN [dbo].[StoredTimezones] AS st2 ON st2.[StoredTimezoneId] = ud2.[StoredTimezoneId]
GO
```

> **⚠️ Solution-specific dependency:** `UserDemographics` and `StoredTimezones` are not part of the
> baseline GPG schema — they exist to resolve the end user's local time zone for display purposes.
> A consuming solution without those tables adapts this view accordingly: drop the
> `EndUserTimezoneIana` column and its two `LEFT JOIN`s (to `UserDemographics` and
> `StoredTimezones`) rather than deploying a view that references tables the solution doesn't have.
> `AspNetUsers` and the `RequestingUserName` resolution are baseline (every GPG solution has
> Identity) and are not part of this exception.

### Stored Procedures

Naming: the `dat_` prefix (Chapter 7's naming table) is reserved for this pattern — DAT procedures
serve a cross-cutting concern invoked *from inside* other SPs, not single-entity CRUD, so they sit
outside the `sps_`/`spi_`/`spu_`/`spd_`/`spiu_` scheme.

**`dat_DataAccessTracking_Record`** is the only write entry point. Every tracked SP calls it —
directly, never through another wrapper — with the caller's identity and what was touched:

```sql
-- =============================================
-- Description: Record a data-access event. Adapted from VirtualCoinFolio's
-- dat_DataAccessTracking_Validate — drops the SecurityLevel gate and allow/deny
-- return (authorization already happened via [Authorize]/policy before this SP is
-- ever called); every caller just logs and proceeds. Mirrors the source's inline
-- archive trigger: checks the oldest active row's age on every call and archives
-- once the 1-hour threshold is passed.
--
-- How to use (called once per distinct action branch of a mutating SP, matching the
-- source's pattern — see spiu_PersonEmail in VirtualCoinFolio for the model):
--
--  EXEC dat_DataAccessTracking_Record
--      @RequestingUser = @RequestingUser,
--      @ProcedureName  = 'spiu_ExampleTable',
--      @RecordID       = @ExampleTableID,
--      @RecordGUID     = @GUIDTemp,
--      @ParameterName1 = '@SomeParam', @ParameterValue1 = @SomeParam
-- =============================================
CREATE PROCEDURE [dbo].[dat_DataAccessTracking_Record]
    @RequestingUser   NVARCHAR(450),
    @ProcedureName    NVARCHAR(255),
    @RecordID         INT              = NULL,
    @RecordGUID       UNIQUEIDENTIFIER = NULL,
    @ParameterName1   NVARCHAR(255)    = NULL, @ParameterValue1 NVARCHAR(255) = NULL,
    @ParameterName2   NVARCHAR(255)    = NULL, @ParameterValue2 NVARCHAR(255) = NULL,
    @ParameterName3   NVARCHAR(255)    = NULL, @ParameterValue3 NVARCHAR(255) = NULL,
    @ParameterName4   NVARCHAR(255)    = NULL, @ParameterValue4 NVARCHAR(255) = NULL,
    @ParameterName5   NVARCHAR(255)    = NULL, @ParameterValue5 NVARCHAR(255) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO [DataAccessTracking]
        ([ProcedureName], [RecordID], [RecordGUID],
         [ParameterName1], [ParameterValue1], [ParameterName2], [ParameterValue2],
         [ParameterName3], [ParameterValue3], [ParameterName4], [ParameterValue4],
         [ParameterName5], [ParameterValue5], [CreatedUser])
    VALUES
        (@ProcedureName, @RecordID, @RecordGUID,
         @ParameterName1, @ParameterValue1, @ParameterName2, @ParameterValue2,
         @ParameterName3, @ParameterValue3, @ParameterName4, @ParameterValue4,
         @ParameterName5, @ParameterValue5, @RequestingUser);

    DECLARE @OldestDate DATETIME2;
    SELECT @OldestDate = MIN([CreatedDate]) FROM [DataAccessTracking];
    IF @OldestDate IS NOT NULL AND DATEDIFF(HOUR, @OldestDate, GETUTCDATE()) > 1
    BEGIN
        EXEC [dbo].[dat_DataAccessTracking_ArchiveData];
    END
END
GO
```

**Retention — `dat_DataAccessTracking_ArchiveData`.** Called inline from `Record` above (not a
nightly job like Chapter 7's other cleanup patterns) — every insert checks the oldest live row's
age and archives once it exceeds one hour. This is a framework default baseline; a solution may
tighten or relax the threshold, documenting the override in the project documentation, the same as
Chapter 5's token-lifetime and lockout baselines.

```sql
-- =============================================
-- Description: Alter dat_DataAccessTracking_ArchiveData to also copy
-- DataAccessTrackingGUID — every column and data value from
-- the source row must be carried over on archive, not just DataAccessTrackingID, so
-- v_DataAccessTracking's union of active + archive is a true single subset rather
-- than a partial one.
-- =============================================
CREATE PROCEDURE [dbo].[dat_DataAccessTracking_ArchiveData]
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRANSACTION;

    DECLARE @LockResult INT;
    EXEC @LockResult = sp_getapplock
        @Resource    = 'dat_DataAccessTracking_ArchiveData',
        @LockMode    = 'Exclusive',
        @LockOwner   = 'Transaction',
        @LockTimeout = 0;

    IF @LockResult >= 0
    BEGIN
        DECLARE @ArchiveThroughID INT;
        SELECT @ArchiveThroughID = MAX([DataAccessTrackingID]) FROM [DataAccessTracking];

        IF @ArchiveThroughID IS NOT NULL
        BEGIN
            INSERT INTO [DataAccessTrackingArchive]
                ([DataAccessTrackingID], [DataAccessTrackingGUID], [ProcedureName], [RecordID], [RecordGUID],
                 [ParameterName1], [ParameterValue1], [ParameterName2], [ParameterValue2],
                 [ParameterName3], [ParameterValue3], [ParameterName4], [ParameterValue4],
                 [ParameterName5], [ParameterValue5],
                 [CreatedDate], [CreatedUser], [LastUpdatedDate], [LastUpdatedUser],
                 [IsActive], [SortOrder], [IsDeleted], [DeletedDate], [DeletedUser])
            SELECT
                [DataAccessTrackingID], [DataAccessTrackingGUID], [ProcedureName], [RecordID], [RecordGUID],
                [ParameterName1], [ParameterValue1], [ParameterName2], [ParameterValue2],
                [ParameterName3], [ParameterValue3], [ParameterName4], [ParameterValue4],
                [ParameterName5], [ParameterValue5],
                [CreatedDate], [CreatedUser], [LastUpdatedDate], [LastUpdatedUser],
                [IsActive], [SortOrder], [IsDeleted], [DeletedDate], [DeletedUser]
            FROM [DataAccessTracking]
            WHERE [DataAccessTrackingID] > (SELECT COALESCE(MAX([DataAccessTrackingID]), 0) FROM [DataAccessTrackingArchive])
              AND [DataAccessTrackingID] <= @ArchiveThroughID;

            DELETE FROM [DataAccessTracking]
            WHERE [DataAccessTrackingID] <= @ArchiveThroughID;
        END
    END
    -- @LockResult < 0 (timeout or deadlock victim): another session is already
    -- archiving this cycle — skip rather than block the caller's own write.

    COMMIT TRANSACTION;
END
GO
```

**Query surface — admin viewer support.** These read `v_DataAccessTracking` (live + archive as one
set) and back the Data Access Tracking admin page (Chapter 5's Admin Panel). They do **not** take
`@IsActive`/`@IsDeleted` filter parameters — DAT rows are an append-only event log, never
soft-deleted or deactivated in normal operation, so Chapter 7's Active/Deleted filtering rule does
not apply to them.

```sql
-- =============================================
-- Description: Look up data-access log entries by procedure name, searching across
-- both the active table and the archive (v_DataAccessTracking is a UNION of both) —
-- a deliberate improvement over the source system, whose equivalent read procedure
-- only ever saw the active table. Drops the source's self-referential SecurityLevel
-- read-check; that access control now lives at the API layer ([Authorize] on whichever
-- endpoint exposes this).
-- =============================================
CREATE PROCEDURE [dbo].[dat_DataAccessTracking_GetDataByProcedureName]
    @ProcedureName NVARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT *
    FROM [v_DataAccessTracking]
    WHERE [ProcedureName] = @ProcedureName
    ORDER BY [CreatedDate] DESC;
END
GO


-- =============================================
-- Description: Look up data-access log entries by requesting user, searching across
-- both the active table and the archive. Renamed from the source's
-- dat_DataAccessTracking_GetDataByUserName to match VegaIdentity's own @RequestingUser
-- terminology (CreatedUser holds the requesting user on this table — see
-- dat_DataAccessTracking_Record).
-- =============================================
CREATE PROCEDURE [dbo].[dat_DataAccessTracking_GetDataByRequestingUser]
    @RequestingUser NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT *
    FROM [v_DataAccessTracking]
    WHERE [CreatedUser] = @RequestingUser
    ORDER BY [CreatedDate] DESC;
END
GO


-- =============================================
-- Description: Distinct list of procedure names present in the data-access log,
-- across both the active table and the archive (for building an admin filter list).
-- =============================================
CREATE PROCEDURE [dbo].[dat_DataAccessTracking_ProcedureNameList]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT [ProcedureName]
    FROM [v_DataAccessTracking]
    WHERE [ProcedureName] IS NOT NULL
    GROUP BY [ProcedureName]
    ORDER BY [ProcedureName];
END
GO


-- =============================================
-- Description: Distinct list of RecordID values present in the data-access
-- log, across both the active table and the archive (for building an admin
-- filter dropdown). Sibling to dat_DataAccessTracking_ProcedureNameList/
-- RequestingUserList.
-- =============================================
CREATE PROCEDURE [dbo].[dat_DataAccessTracking_RecordIDList]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT [RecordID]
    FROM [v_DataAccessTracking]
    WHERE [RecordID] IS NOT NULL
    GROUP BY [RecordID]
    ORDER BY [RecordID];
END
GO


-- =============================================
-- Description: v_DataAccessTracking now exposes RequestingUserName,
-- resolving CreatedUser to the matching AspNetUsers.UserName (falling back
-- to the raw CreatedUser value for SYSTEM/ANONYMOUS/unmatched rows). This
-- lookup switches from the raw CreatedUser value to the resolved name so
-- the Data Access Tracking page's Requesting User filter dropdown (built
-- from this list) offers the same values the grid actually displays.
-- =============================================
CREATE PROCEDURE [dbo].[dat_DataAccessTracking_RequestingUserList]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT [RequestingUserName] AS [RequestingUser]
    FROM [v_DataAccessTracking]
    WHERE [RequestingUserName] IS NOT NULL
    GROUP BY [RequestingUserName]
    ORDER BY [RequestingUserName];
END
GO
```

### Calling Convention — Every SP Logs Its Caller

The DAT gap this section closes was that `RequestingUser` was not applied consistently. The rule
going forward:

- **MUST** Every `sps_`, `spi_`, `spu_`, `spd_`, and `spiu_`/`spud_` procedure accepts a parameter
  identifying the requesting user and passes its value to `dat_DataAccessTracking_Record`'s
  `@RequestingUser`. The parameter is canonically named `@RequestingUser`; a business-appropriate
  alternate name is acceptable (e.g. `spu_ContactInquiry_MarkRead`'s `@ReadByUser` below) provided
  its value is what gets passed through. This applies without exception, including procedures
  against ASP.NET Identity tables (Chapter 8's "No Exemptions" policy above).
- **MUST** A mutating SP (`spi_`/`spu_`/`spd_`/`spiu_`) calls `dat_DataAccessTracking_Record` once
  per distinct action branch actually taken (insert, update, soft-delete are separate calls) — and
  only when that branch actually affected a row (guard on `@@ROWCOUNT`/`SELECT COUNT(*)` first for
  update/delete branches; an insert branch that reached `dat_DataAccessTracking_Record` at all has,
  by definition, just inserted, so no guard is needed there).
- **MUST** A read SP (`sps_`) calls `dat_DataAccessTracking_Record` once per invocation, before
  returning its result set. `@RecordID`/`@RecordGUID` are the specific row identified when the SP
  reads a single record; both are `NULL` for a multi-row read (e.g. `GetAll`).
- **MUST** `dat_` procedures themselves never call `dat_DataAccessTracking_Record` — logging DAT's
  own reads/writes would recurse and add pure noise, not signal.
- **MUST** A procedure that may legitimately run without an authenticated caller (a background
  job, a migration, a public/anonymous read) defaults `@RequestingUser` to `NULL` and substitutes a
  sentinel before logging: `DECLARE @ActualRequestingUser NVARCHAR(450) = ISNULL(@RequestingUser, 'SYSTEM')`.
  A procedure only ever invoked within an authenticated request context gives `@RequestingUser` no
  default — the caller must supply a real value.
- **MUST** Via the `dat_DataAccessTracking_Record` call, log the `ParameterName{n}`/`ParameterValue{n}`
  pairs that materially describe what was accessed or changed, not necessarily every parameter the
  SP takes.

### Worked Examples

**Read (`sps_`), multi-row, system-tolerant default:**

```sql
CREATE PROCEDURE [dbo].[sps_State_GetAll]
    @RequestingUser NVARCHAR(450) = NULL,
    @IsActive       BIT = 1,
    @IsDeleted      BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ActualRequestingUser NVARCHAR(450) = ISNULL(@RequestingUser, 'SYSTEM');

    EXEC [dbo].[dat_DataAccessTracking_Record]
        @RequestingUser  = @ActualRequestingUser,
        @ProcedureName   = 'sps_State_GetAll',
        @RecordID        = NULL,
        @RecordGUID      = NULL;

    SELECT  [StateProvinceAbbrev],
            [StateProvince],
            [CountryID],
            [CountryName]
    FROM    [dbo].[v_State]
    WHERE   [IsActive]  = @IsActive
      AND   [IsDeleted] = @IsDeleted
    ORDER BY [CountryName], [StateProvince];
END
GO
```

**Update (`spu_`), single branch, idempotent, alternate parameter name:**

```sql
CREATE PROCEDURE [dbo].[spu_ContactInquiry_MarkRead]
    @InquiryGUID uniqueidentifier,
    @ReadByUser  nvarchar(150)
AS
BEGIN
    SET NOCOUNT ON;

    -- Idempotent: only set ReadDate when currently unread
    UPDATE [ContactInquiries]
    SET    [ReadDate]        = GETUTCDATE(),
           [ReadByUser]      = @ReadByUser,
           [LastUpdatedDate] = GETUTCDATE(),
           [LastUpdatedUser] = @ReadByUser
    WHERE  [InquiryGUID] = @InquiryGUID
      AND  [ReadDate]    IS NULL
      AND  [IsDeleted]   = 0;

    DECLARE @RowsAffected INT = @@ROWCOUNT;

    IF @RowsAffected > 0
    BEGIN
        DECLARE @RecordID INT;

        SELECT @RecordID = [InquiryID]
        FROM   [ContactInquiries]
        WHERE  [InquiryGUID] = @InquiryGUID;

        EXEC [dbo].[dat_DataAccessTracking_Record]
            @RequestingUser = @ReadByUser,
            @ProcedureName  = 'spu_ContactInquiry_MarkRead',
            @RecordID       = @RecordID,
            @RecordGUID     = @InquiryGUID;
    END
END
GO
```

**Insert/Update/Soft-delete (`spiu_`), three branches, one call per branch:**

> **Correction — 2026-09-04:** the update and soft-delete branches below log `@RecordID` using the
> input `@UserAddressID` parameter directly. An earlier version of this procedure referenced
> `@newid`/`@newguid` in those branches — variables assigned only in the insert branch above them —
> which would have logged `NULL` for `RecordID`/`RecordGUID` on every update and soft-delete. Fixed
> here; `@RecordGUID` is omitted (`NULL`) on those two branches since no GUID variable is available
> without an extra lookup, matching `spd_SolutionContact_Delete`'s pattern below.

```sql
CREATE PROCEDURE [dbo].[spiu_UserAddress]
    @UserAddressID INT = -1,
    @UserId NVARCHAR(450) = '',
    @AddressID INT = -1,
    @IsActive BIT = 1,
    @Deleted BIT = 0,
    @RequestingUser NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @rowcount INT
    IF @UserAddressID > -1
        SELECT @rowcount = COUNT(*) FROM [UserAddress] WHERE UserAddressID = @UserAddressID
    ELSE
        SELECT @rowcount = 0

    IF @rowcount = 0
    BEGIN
        -- INSERT
        INSERT INTO [UserAddress]
            (UserId, AddressID, IsActive, IsDeleted, CreatedUser)
        VALUES
            (@UserId, @AddressID, @IsActive, @Deleted, @RequestingUser)

        DECLARE @newid INT = @@IDENTITY
        DECLARE @newguid UNIQUEIDENTIFIER = (SELECT [UserAddressGUID] FROM [UserAddress] WHERE [UserAddressID] = @newid)

        EXEC [dbo].[dat_DataAccessTracking_Record]
            @RequestingUser = @RequestingUser,
            @ProcedureName  = 'spiu_UserAddress',
            @RecordID       = @newid,
            @RecordGUID     = @newguid,
            @ParameterName1 = 'UserAddressID', @ParameterValue1 = @UserAddressID,
            @ParameterName2 = 'UserID', @ParameterValue2 = @UserId,
            @ParameterName3 = 'AddressID', @ParameterValue3 = @AddressID,
            @ParameterName4 = 'IsActive', @ParameterValue4 = @IsActive,
            @ParameterName5 = 'Deleted', @ParameterValue5 = @Deleted;

        SELECT * FROM v_UserAddress WHERE UserAddressID = @newid AND IsDeleted = 0
    END
    ELSE
    BEGIN
        IF @Deleted = 1
        BEGIN
            -- SOFT DELETE
            UPDATE [UserAddress]
            SET IsActive = 0,
                IsDeleted = 1,
                DeletedDate = GETUTCDATE(),
                DeletedUser = @RequestingUser,
                LastUpdatedDate = GETUTCDATE(),
                LastUpdatedUser = @RequestingUser
            WHERE UserAddressID = @UserAddressID

            DECLARE @DeleteRowsAffected INT = @@ROWCOUNT
            IF @DeleteRowsAffected > 0
            BEGIN
                EXEC [dbo].[dat_DataAccessTracking_Record]
                    @RequestingUser = @RequestingUser,
                    @ProcedureName  = 'spiu_UserAddress',
                    @RecordID       = @UserAddressID,
                    @RecordGUID     = NULL,
                    @ParameterName1 = 'UserAddressID', @ParameterValue1 = @UserAddressID,
                    @ParameterName2 = 'UserID', @ParameterValue2 = @UserId,
                    @ParameterName3 = 'AddressID', @ParameterValue3 = @AddressID,
                    @ParameterName4 = 'IsActive', @ParameterValue4 = @IsActive,
                    @ParameterName5 = 'Deleted', @ParameterValue5 = @Deleted;
            END
        END
        ELSE
        BEGIN
            -- UPDATE
            UPDATE [UserAddress]
            SET UserId = @UserId,
                AddressID = @AddressID,
                IsActive = @IsActive,
                IsDeleted = @Deleted,
                LastUpdatedDate = GETUTCDATE(),
                LastUpdatedUser = @RequestingUser
            WHERE UserAddressID = @UserAddressID

            DECLARE @UpdateRowsAffected INT = @@ROWCOUNT
            IF @UpdateRowsAffected > 0
            BEGIN
                EXEC [dbo].[dat_DataAccessTracking_Record]
                    @RequestingUser = @RequestingUser,
                    @ProcedureName  = 'spiu_UserAddress',
                    @RecordID       = @UserAddressID,
                    @RecordGUID     = NULL,
                    @ParameterName1 = 'UserAddressID', @ParameterValue1 = @UserAddressID,
                    @ParameterName2 = 'UserID', @ParameterValue2 = @UserId,
                    @ParameterName3 = 'AddressID', @ParameterValue3 = @AddressID,
                    @ParameterName4 = 'IsActive', @ParameterValue4 = @IsActive,
                    @ParameterName5 = 'Deleted', @ParameterValue5 = @Deleted;
            END
        END

        SELECT * FROM v_UserAddress WHERE UserAddressID = @UserAddressID AND IsDeleted = 0
    END
END
GO
```

**Soft-delete only (`spd_`), single branch:**

```sql
CREATE PROCEDURE [dbo].[spd_SolutionContact_Delete]
    @SolutionContactID INT,
    @RequestingUser    NVARCHAR(150) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE [SolutionContacts]
    SET    [IsDeleted]       = 1,
           [IsActive]        = 0,
           [DeletedDate]     = GETUTCDATE(),
           [DeletedUser]     = @RequestingUser,
           [LastUpdatedDate] = GETUTCDATE(),
           [LastUpdatedUser] = @RequestingUser
    WHERE  [SolutionContactID] = @SolutionContactID;

    DECLARE @RowsAffected INT = @@ROWCOUNT;

    IF @RowsAffected > 0
    BEGIN
        EXEC [dbo].[dat_DataAccessTracking_Record]
            @RequestingUser = @RequestingUser,
            @ProcedureName  = 'spd_SolutionContact_Delete',
            @RecordID       = @SolutionContactID;
    END
END;
GO
```

**Insert only (`spi_`):**

```sql
CREATE PROCEDURE [dbo].[spi_HelpItemTarget_Add]
    @HelpItemID       INT,
    @TargetKey        NVARCHAR(200),
    @TargetType       NVARCHAR(50),
    @RequestingUser   NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO [dbo].[HelpItemTarget]
        (HelpItemID, TargetKey, TargetType, CreatedUser)
    VALUES
        (@HelpItemID, @TargetKey, @TargetType, @RequestingUser)

    DECLARE @newid INT = @@IDENTITY
    DECLARE @newguid UNIQUEIDENTIFIER
    SELECT @newguid = [HelpItemTargetGUID] FROM [dbo].[HelpItemTarget] WHERE [HelpItemTargetID] = @newid

    EXEC [dbo].[dat_DataAccessTracking_Record]
        @RequestingUser = @RequestingUser,
        @ProcedureName  = 'spi_HelpItemTarget_Add',
        @RecordID       = @newid,
        @RecordGUID     = @newguid,
        @ParameterName1 = 'HelpItemID', @ParameterValue1 = @HelpItemID,
        @ParameterName2 = 'TargetKey', @ParameterValue2 = @TargetKey,
        @ParameterName3 = 'TargetType', @ParameterValue3 = @TargetType;

    SELECT * FROM [dbo].[v_HelpItemTarget] WHERE [HelpItemTargetID] = @newid AND [IsDeleted] = 0
END
GO
```
