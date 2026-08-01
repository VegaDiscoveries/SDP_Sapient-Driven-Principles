# Chapter 8 — Data Access Patterns

> *Section file for `GenericProjectGuidlines_V1.10_20260323.md`*
>
> **⚠️ Sync rule — agent instruction:** This is a section file. Any change made here **must be mirrored in the corresponding chapter** of `GenericProjectGuidlines_V1.10_20260323.md`. Any change made in the parent document's corresponding chapter must be mirrored back here. Both files must remain identical in content for their shared sections.
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
- **SHOULD** Wrap multi-step stored-procedure calls in a single `DbContext` transaction when all steps must succeed or all must fail.
- **MUST** The stored-procedure mandate applies to **all** database tables without exception, including tables managed by third-party frameworks (e.g., ASP.NET Core Identity's `AspNetUsers`, `AspNetRoles`, and related tables). No framework default or convenience API overrides this rule. Any conflict between a framework's built-in data access mechanism and this mandate must be resolved before implementation begins — the resolution must be documented and approved; it cannot be assumed.
- **MUST** Cross-database stored procedure calls must be proxied through a local wrapper SP in the calling database (naming convention: `_sp_` prefix). Application code and composition SPs in the calling DB invoke the local wrapper — never the remote SP directly by three-part name. This confines knowledge of the remote database's SP signatures to the wrapper layer only, reducing structural exposure across DB boundaries.

## ASP.NET Core Identity Integration Policy

**Decision recorded: 2026-05-18 (OQ-8). Documented: 2026-05-25 (P10-DOC-04).**

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
