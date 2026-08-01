# Chapter 7 — Database Architecture

> *Section file for `GenericProjectGuidlines_V1.10_20260323.md`*
>
> **⚠️ Sync rule — agent instruction:** This is a section file. Any change made here **must be mirrored in the corresponding chapter** of `GenericProjectGuidlines_V1.10_20260323.md`. Any change made in the parent document's corresponding chapter must be mirrored back here. Both files must remain identical in content for their shared sections.
>
> **TOC Maintenance:** If this section is renamed or deleted, update both the parent document's Contents list AND the `GenericProjectGuidlines_TOC.md` file. See the TOC file for detailed maintenance instructions.
>
> **⚠️ Append-only — agent instruction:** This document is an append-only architecture record. Do not delete or reword existing content. New or revised guidance must be added below the content it supersedes. Strikethrough (`~~text~~`) is a valid edit technique — it visually marks content as superseded while retaining it for audit purposes. Use strikethrough to mark the old text, then place the replacement immediately after on a new line.

---

Every table in the database follows the same foundational column set. Consistency here pays dividends in auditing, soft-delete patterns, UI sorting, and API response contracts. A table that omits common columns must have written justification in the schema documentation.

## Common Columns — Required in Every Table

| SQL Column | SQL Type | C# Property | Default | Purpose |
|------------|----------|-------------|---------|---------|
| `{Entity}ID` | INT IDENTITY(1,1) PK | `int Id` | — | Surrogate integer primary key. Named after the entity (e.g., `CoinID`). |
| `{Entity}GUID` | UNIQUEIDENTIFIER NOT NULL | `Guid Guid` | NEWID() | Public-facing identifier. Use this in all API responses and URLs — never the integer ID. |
| `Name` | NVARCHAR(255) | `string? Name` | NULL | Human-readable label. |
| `Description` | NVARCHAR(2000) | `string? Description` | NULL | Optional longer text description. |
| `CreatedDate` | DATETIME2 NOT NULL | `DateTime? CreatedDate` | GETUTCDATE() | UTC insert timestamp. Set by database default only — never by application code. |
| `CreatedUser` | NVARCHAR(150) | `string? CreatedUser` | NULL | Username or system identifier that created the record. |
| `LastUpdatedDate` | DATETIME2(7) | `DateTime? LastUpdatedDate` | NULL | UTC timestamp of last update. Set by application code on every save. |
| `LastUpdatedUser` | NVARCHAR(150) | `string? LastUpdatedUser` | NULL | Username that last modified the record. |
| `IsActive` | BIT | `bool? IsActive` | 1 (True) | Soft on/off toggle. Stored procedures default to filtering `WHERE IsActive = 1`. |
| `SortOrder` | INT | `int? SortOrder` | 100 | Display sequence for UI lists. Default 100. Lower values appear first. Never used for chronological ordering. See **SortOrder Convention** below. |
| `IsDeleted` | BIT | `bool? IsDeleted` | 0 (False) | Soft-delete flag. Records are never physically deleted. |
| `DeletedDate` | DATETIME2 | `DateTime? DeletedDate` | NULL | UTC timestamp when the soft-delete was applied. |
| `DeletedUser` | NVARCHAR(150) | `string? DeletedUser` | NULL | Username that performed the soft-delete. |

> **ℹ️ ID and GUID columns are not part of `CommonColumns`.** Each entity class declares its own `(TableName)ID` (INT IDENTITY PK) and `(TableName)GUID` (UNIQUEIDENTIFIER DEFAULT newid()) properties individually. The base class provides only the shared audit, lifecycle, and metadata columns. SQL column names and C# property names are identical throughout — no `[Column]` mapping attributes are required.

## CommonColumns Base Class

```csharp
// {AppName}.Domain/Common/CommonColumns.cs
// (TableName)ID and (TableName)GUID are NOT declared here.
// Each entity class adds those two columns individually.
namespace {AppName}.Domain.Common;

public class CommonColumns : ICommonColumns
{
    [StringLength(255)]
    public string? Name { get; set; }

    [StringLength(2000)]
    public string? Description { get; set; }

    [DatabaseGenerated(DatabaseGeneratedOption.Computed)]
    public DateTime? CreatedDate { get; set; }
    [StringLength(150)]
    public string? CreatedUser { get; set; }

    public DateTime? LastUpdatedDate { get; set; }
    [StringLength(150)]
    public string? LastUpdatedUser { get; set; }

    [DefaultValue(true)]
    public bool? IsActive  { get; set; }
    [DefaultValue(100)]
    public int?  SortOrder  { get; set; }
    [DefaultValue(false)]
    public bool? IsDeleted { get; set; }
    public DateTime? DeletedDate { get; set; }
    [StringLength(150)]
    public string? DeletedUser { get; set; }
}
```

### SortOrder Convention

`SortOrder` controls display ordering only — it is never used for chronological sequencing.
Datetime columns (`CreatedDate`, `LastUpdatedDate`) serve that purpose.

**Default and bands**

All seeded and inserted rows default to `SortOrder = 100`. This creates three natural display
bands with no additional configuration:

| Band | Meaning |
|------|---------|
| `< 100` | Promoted — appears above the normal set |
| `= 100` | Normal — tie-broken by secondary sort (typically `Name ASC`) |
| `> 100` | Demoted — appears below the normal set |

New rows land in the normal band automatically. Promoting one item (e.g. a preferred country
in a country list) requires a single value change to any number below 100. No other rows need
to be renumbered.

**Sort pattern**

Always pair `SortOrder` with a secondary column to resolve ties deterministically:

```sql
ORDER BY SortOrder ASC, Name ASC
```

**Grouping extension**

`SortOrder` can define implicit display groups using multiples of 10 (10, 20, 30, 40, …).
Items sharing the same tens-band are peers within that group. The rendering layer detects
group breaks by watching for band changes as it walks the ordered result set — no separate
group column, join, or foreign key is required.

Integer division extracts the group key in SQL:

```sql
SELECT SortOrder / 10 AS GroupBand, Name, ...
FROM SomeTable
WHERE IsActive = 1
ORDER BY SortOrder ASC, Name ASC
```

New groups slot between existing ones without renumbering (e.g. band 25 between 20 and 30).
Items within a band can still be individually promoted or demoted by using non-round values
(e.g. 19 or 21 within the 20s band).

---

## Database Object Naming Conventions

All database object names use PascalCase. Underscores serve only as classification prefixes — they are not used as general word separators within a name body.

| Object Type | Prefix | Example |
|-------------|--------|---------|
| Internal / system table | `_` | `_LogAudit`, `_DataAccessTracking` |
| View | `v_` | `v_CoinSummary`, `v_CustomerActive` |
| Function – select | `fn_s_` | `fn_s_GetActiveCoinsByUser` |
| Function – insert | `fn_i_` | `fn_i_InsertCoinHolding` |
| Function – update | `fn_u_` | `fn_u_UpdateCoinPrice` |
| Stored procedure – select | `sps_` | `sps_Coin_GetByGuid`, `sps_Coin_GetAll` |
| Stored procedure – insert | `spi_` | `spi_Coin_Create` |
| Stored procedure – update | `spu_` | `spu_Coin_UpdatePrice` |
| Stored procedure – delete / soft-delete | `spd_` | `spd_Coin_SoftDelete` |
| Stored procedure – mixed operations | Combined prefix | `spiu_Coin_UpsertHolding`, `spud_Coin_UpdateOrDelete` |

> **ℹ️ Read path:** `sps_` → `v_` → table (or `sps_` → `fn_s_` → `v_` → table). The stored procedure always reads through a view; never directly from a table. Every view must return all `CommonColumns` for its primary table.
>
> **Write path:** `spi_` / `spu_` / `spd_` → table (or via `fn_i_` / `fn_u_`). Writes always target the table; views are never write targets.

## Database Rules

- **MUST** Every table includes all 13 common columns. No exceptions without written justification.
- **MUST** Use the GUID — not the integer ID — in all public-facing URLs, API responses, and mobile client references.
- **MUST** Records are never physically deleted. Use the `IsDeleted` / `DeletedDate` / `DeletedUser` columns.
- **MUST** `CreatedDate` and the GUID are set by database defaults, never by application code.
- **MUST** Maintain exactly two *runtime* `DbContext` classes: `AppDbContext` for the application domain and `AppIdentityDbContext` for the identity database. These must point to **separate physical databases** — they are never the same database. A third `DbContext` class for migrations is not required; instead, pass a `--connection` override to `dotnet ef database update` pointing to the elevated migration login. For Vega Discoveries projects the Identity database may be shared across multiple solutions; each solution always maintains its own independent application domain database. **The `Email` column (normalised to lowercase, unique-constrained) is the logical cross-database key linking the identity database to the app database.** Cross-database foreign key constraints are not used; joins across databases are performed on `Email` in services that require them.
- **MUST** Use at least three SQL logins for each solution: (1) a **migrations login** (`db_owner` on both databases) used only during deployments and never by the running application; (2) a **runtime app login** with no direct table permissions — `EXECUTE` is granted only on individual stored procedures as they are created, channelled through an application database role — see **SQL Login and Database Role Pattern** below; (3) a **runtime identity login** with `db_datareader`, `db_datawriter`, and `EXECUTE` on the identity database. Apply this permission model from the first day of development, not only when deploying to production.
- **MUST** The running application must never hold or read migration login credentials. Migration connection strings (`ConnectionStrings:MigrationsDb`, `ConnectionStrings:MigrationsIdentityDb`) are stored in User Secrets locally and in CI/CD secrets at deploy time. They must not appear in any runtime configuration path — `appsettings.json`, `appsettings.*.json`, or environment variables injected to a running process.
- **SHOULD** Apply a global EF Core query filter on `IsDeleted`: `modelBuilder.Entity<T>().HasQueryFilter(e => !e.IsDeleted.GetValueOrDefault())`
- **SHOULD** Use `DATETIME2` (not `DATETIME`) for all date columns. Store all timestamps in UTC.
- **SHOULD** Use SQL authentication (username + password) rather than Windows authentication for cross-environment portability.

---

## SQL Login and Database Role Pattern

Applies to all non-EF Core database activity. EF Core's built-in processes — migrations,
`UserManager<T>`, and other framework-managed Identity table operations — are out of scope
and use their own access model.

### Principle

Logins are never granted direct object permissions. All access to stored procedures flows
through a database role:

```
SQL Server Login
    └─ mapped to Database User
            └─ member of Database Role (Role_[loginName] or Role-[processName])
                    └─ EXECUTE granted on individual stored procedures
```

### Role Naming Convention

| Pattern | Use When | Example |
|---------|----------|---------|
| `Role-[processName]` | Role represents a logical function shared by multiple logins | `Role-Runtime`, `Role-Reporting`, `Role-ETL` |
| `Role_[loginName]` | Role maps one-to-one with a specific login | `Role_VegaIdentity`, `Role_VegaAppVegaDrop` |

### Setup Sequence

**Step 1 — Create the database role (once, at DB setup time):**
```sql
CREATE ROLE [Role_VegaAppVegaDrop];
```

**Step 2 — Add the database user to the role (once, at login/user setup time):**
```sql
ALTER ROLE [Role_VegaAppVegaDrop] ADD MEMBER [VegaAppVegaDrop];
```

The login now holds no direct object permissions. All access is controlled through the role.

**Step 3 — Grant EXECUTE to the role at SP creation time:**
```sql
-- In the migration or SSDT script that creates the SP:
GRANT EXECUTE ON [dbo].[sps_User_GetByEmail] TO [Role_VegaAppVegaDrop];
GRANT EXECUTE ON [dbo].[spi_UserProfile_Create] TO [Role_VegaAppVegaDrop];
```

> **Updated 2026-05-23 — `.Database` project changed from SSDT to DbUp:** The comment above (`-- In the migration or SSDT script...`) is superseded. Use `-- In the DbUp migration script that creates the SP:` instead.

~~This step belongs in the same deployment artifact (migration `Up()` or SSDT `.sql` file)
that creates the SP — not in a separate permissions script applied later.~~
This step belongs in the same DbUp migration script that creates the SP — not in a separate permissions script applied later.

### Rules

- **MUST** Logins are never granted EXECUTE directly on any stored procedure. All SP access is granted to a role.
- **MUST** Each runtime login is a member of exactly one database role unless multiple access tiers are explicitly documented and justified.
- **MUST** Role names follow the `Role-[processName]` or `Role_[loginName]` convention. No other naming is permitted.
- **MUST** EXECUTE permissions are added to the role in the same deployment artifact that creates the SP — never deferred to a separate permissions pass.
- **MUST** This pattern applies only to non-EF Core SP access. EF Core's built-in Identity table operations are out of scope.
- **SHOULD** Where a process role (`Role-[processName]`) is used, document which logins are members and why the shared role is appropriate rather than per-login roles.

---

## VegaDrop ERD Reference

The following Mermaid `.mermaid` ERD files in `database/docs/` provide the authoritative schema for the VegaDrop solution. These must be kept in sync with any table changes.

| ERD File | Database | Topic Area | Key Tables |
|---|---|---|---|
| [`VegaDrop-IdentityDB_ERD_V1.00_20260323.mermaid`](../../database/docs/VegaDrop-IdentityDB_ERD_V1.00_20260323.mermaid) | `VegaDiscoveriesIdentity` | ASP.NET Identity & Auth | `AspNetUsers`, `AspNetUserClaims`, `AspNetUserLogins`, `AspNetUserTokens`, `RegisteredSolutions`, `UserSolutionCredential`, `RefreshToken`, `ConsumedResetToken` |
| [`VegaDrop-AppDB-CoreUser_ERD_V1.00_20260323.mermaid`](../../database/docs/VegaDrop-AppDB-CoreUser_ERD_V1.00_20260323.mermaid) | `VegaAppVegaDrop` | Core User & Identity | `User`, `UserProfile`, `Role`, `UserRole` |
| [`VegaDrop-AppDB-GamePlay_ERD_V1.00_20260323.mermaid`](../../database/docs/VegaDrop-AppDB-GamePlay_ERD_V1.00_20260323.mermaid) | `VegaAppVegaDrop` | Gameplay | `GameSession`, `LeaderboardEntry` |
| [`VegaDrop-AppDB-Commerce_ERD_V1.00_20260323.mermaid`](../../database/docs/VegaDrop-AppDB-Commerce_ERD_V1.00_20260323.mermaid) | `VegaAppVegaDrop` | Commerce | `Purchase`, `Entitlement` |
| [`VegaDrop-AppDB-Social_ERD_V1.00_20260323.mermaid`](../../database/docs/VegaDrop-AppDB-Social_ERD_V1.00_20260323.mermaid) | `VegaAppVegaDrop` | Social & Sync | `Referral`, `ReferralClick`, `ReferralRedemption`, `FriendRequest`, `LocalStorageSyncRecord` |
| [`VegaDrop-AppDB-SystemAdmin_ERD_V1.00_20260323.mermaid`](../../database/docs/VegaDrop-AppDB-SystemAdmin_ERD_V1.00_20260323.mermaid) | `VegaAppVegaDrop` | System & Administration | `FeatureFlag`, `SystemAnnouncement`, `ContentReport`, `DisplayNameModerationItem`, `_LogEmailAudit` |

## Solution Configuration Columns

Beyond the standard identity schema, the `RegisteredSolutions` table includes optional configuration columns for multi-tenant email customization and timezone handling. These enable solutions to customize sender addresses and account for geographic distribution without code changes.

### Email Configuration

| Column | Type | Purpose | Example |
|--------|------|---------|---------|
| `FromAddress` | NVARCHAR(200) NULL | Solution-specific email sender address | `noreply@vegadrop.vegadiscoveries.com` |
| `FromDisplayName` | NVARCHAR(200) NULL | Display name in email headers | `VegaDrop Notifications` |

**Implementation:**
- Defaults: NULL values use the VDC_Emailer platform default (`fn_EmailProperties()`)
- Configuration: Set by ops during solution onboarding via admin panel
- Override: Per-template overrides via `RegisteredSolutionEmailTemplate` table for fine-grained control

**Rules:**

- **MUST** Both `FromAddress` and `FromDisplayName` are NULL together or NOT NULL together (no partial values)
- **MUST** NULL `FromAddress` defaults to VDC_Emailer `fn_EmailProperties()` platform default; no manual fallback required in code
- **MUST** Each solution-to-template override is stored in `RegisteredSolutionEmailTemplate` (FK to both `RegisteredSolutions` and `EmailTemplate`)
- **SHOULD** Each solution configures its own sender address at onboarding for branding consistency
- **SHOULD** Display names follow the pattern: `{SolutionName} Notifications` or similar
- **SHOULD** Ops can override sender per-email-type using `RegisteredSolutionEmailTemplate` table (e.g., support@solution for support emails, billing@solution for billing emails)

### Timezone Configuration

| Column | Type | Purpose | Example |
|--------|------|---------|---------|
| `TimeZoneIdentifier` | NVARCHAR(50) NULL | IANA timezone identifier for the solution's primary location | `"America/New_York"` |
| `UtcOffsetMinutes` | INT NULL | UTC offset in minutes (informational; do not rely as source of truth) | `-300` (EST = UTC-5) |

**Purpose:**

Clock skew tolerance in token validation depends on the app's local time zone. When a solution's instances are distributed across multiple time zones (e.g., VegaDrop with app servers in New York and Los Angeles), storing the primary timezone helps:
- Apply appropriate clock skew tolerance during token expiry checks
- Troubleshoot validation failures caused by server clock drift
- Calculate local time for logs and audit trails

**Implementation Pattern:**

```csharp
public class AppTokenValidator
{
    public bool IsTokenExpired(AppToken token, RegisteredSolution solution)
    {
        var nowUtc = DateTime.UtcNow;
        
        // Adjust to app's local time if timezone known
        var effectiveNow = nowUtc;
        if (solution.TimeZoneIdentifier != null)
        {
            var tz = TimeZoneInfo.FindSystemTimeZoneById(solution.TimeZoneIdentifier);
            effectiveNow = TimeZoneInfo.ConvertTime(nowUtc, tz);
        }
        
        // Token expired with 5-minute clock skew tolerance
        var tolerance = TimeSpan.FromMinutes(5);
        return token.ExpiresAtUtc < (nowUtc - tolerance);
    }
}
```

**Rules:**

- **MUST** Use IANA timezone database identifiers (e.g., `"America/Chicago"`, `"Europe/London"`, `"Asia/Tokyo"`), never abbreviations (`"CST"`, `"GMT"`)
- **MUST NOT** rely solely on `UtcOffsetMinutes` as the authoritative source — daylight saving time changes are not reflected; use `TimeZoneIdentifier` for reliable conversions
- **SHOULD** Populate `TimeZoneIdentifier` for solutions with geographically distributed app instances
- **SHOULD** Leave NULL if solution is centrally located or timezone awareness is not required

---

## App DB User Table

Every application database **must** contain a `User` table that mirrors the minimal identity footprint of a registered user. This table is the app DB's local reference point for all other app-domain tables that need to associate data with a user. It does **not** replicate the full identity record — only the fields required for app-domain queries.

```
User
├── UserID               INT IDENTITY(1,1) PK
├── UserGUID             UNIQUEIDENTIFIER NOT NULL   DEFAULT newid()
├── Email                NVARCHAR(255)    NOT NULL   — normalised to lowercase
├── + CommonColumns
UNIQUE constraint on Email
```

### Cross-Database Link Rules

- `Email` in the app DB `User` table **must** exactly match `AspNetUsers.NormalizedEmail` (lowercased) in the identity database. This is the logical key linking the two databases.
- The `User` row is created in the app DB **at the same time** the `AspNetUsers` row is created in the identity DB, within the same registration request (committed as separate transactions against their respective databases, with compensating rollback logic on failure).
- If the user changes their email, they must first review and confirm the scope of the change — see **Email Change Flow** below. After confirmation, both databases are updated within the same request: the identity DB is updated first; if that succeeds, the app DB `User.Email` is updated. If the app DB update fails, the identity DB change is rolled back.
- App-domain tables that associate data with a user use `UserID` (FK → `User.UserID`) as the local foreign key — never a direct reference to the identity DB. Cross-database lookups by email are performed only in the application service layer when bridging identity and app data.
- `User.Name` and `User.Description` (inherited from `CommonColumns`) are optional display fields and are not relied upon as unique identifiers.

### Email Change Flow

Email is the logical key linking the identity DB and every app DB where the user has an account. An email change propagates across all registered solutions — users must see and confirm this scope before any change is committed.

**Step 1 — Preview (no state change)**

Before presenting the email edit form, the client calls a read-only endpoint to retrieve the list of affected applications:

```
GET /account/change-email/impact
Authorization: Bearer {accessToken}

Response 200 OK:
{
  "affectedCount": 2,
  "applications": [
    { "solutionId": "vega-drop", "displayName": "VegaDrop" },
    { "solutionId": "vega-arena", "displayName": "Vega Arena" }
  ]
}
```

The server populates this by querying `UserSolutionCredential JOIN RegisteredSolutions` in the identity DB to find every solution where the user holds an active credential record.

**Step 2 — Confirmation UI**

The dialog must display all affected application names before the user can proceed:

> "Changing your email will update your login across **N applications**: VegaDrop, Vega Arena. This cannot be selectively applied. Do you want to continue?"

The user must click an affirmative **"Change Email"** button to proceed. Closing or dismissing the dialog cancels without state change.

**Step 3 — Execute the Change**

After confirmation, the client submits the change request:

```
POST /account/change-email
Authorization: Bearer {accessToken}

{
  "resetPin": "...",
  "newEmail": "user@new.com"
}
```

Execution sequence (within the same request):

1. Validate the new email is not already in use in the identity DB
2. Update `AspNetUsers.Email` and `NormalizedEmail` in the identity DB
3. For each affected solution, update the corresponding `User.Email` in the app DB
4. If any app DB update fails, roll back all changes — identity DB and any app DB rows already updated

**MUST rules:**

- **MUST** The preview endpoint must be called before the email change form is shown; the returned application names are used to populate the confirmation message.
- **MUST** The confirmation UI must name every affected application — a generic count alone is not sufficient.
- **MUST** No email change is executed without explicit user confirmation.
- **MUST** A Reset PIN re-authentication step is required for this account-level operation.
- **MUST** All database updates (identity + all app DBs) are treated as a distributed saga: any failure triggers compensating rollback across all already-updated stores.

## App DB Role Tables

Roles and role assignments are stored in the application database, not the identity database. This keeps role management scoped to the solution and allows roles to differ across Vega Discoveries solutions. Role names are the authoritative source used to populate the `RoleDefs` constants class and the JWT `role` claims.

### Role Table

```
Role
├── RoleID               INT IDENTITY(1,1) PK
├── RoleGUID             UNIQUEIDENTIFIER NOT NULL   DEFAULT newid()
├── + CommonColumns      — Name (NVARCHAR 255) holds the role label; SortOrder controls display hierarchy
UNIQUE constraint on Name
```

Generic roles seeded at table creation (present in every solution):

| Name | SortOrder | Purpose |
|------|-----------|--------|
| `User` | 10 | Standard authenticated user — baseline role present in every solution |
| `Admin` | 20 | Full solution administration — activates Admin Panel in the UI for user management, audit, and system configuration. |
| `Dev` | 30 | Internal developer and debug access. Users with this role see the Dev Toolbar in the UI: raw error details, request/response inspector, JWT inspector, feature flag overrides, session info, log stream, performance alerts, state snapshot, and network latency overlay. |

These three roles are seeded by the shared framework migration. App-specific roles are defined in the project documentation and seeded in addition to these at application startup. The `IsActive` flag (from `CommonColumns`) disables a role without removing existing assignments.

### UserRole Table

```
UserRole
├── UserRoleID           INT IDENTITY(1,1) PK
├── UserRoleGUID         UNIQUEIDENTIFIER NOT NULL   DEFAULT newid()
├── UserID               FK → User.UserID    NOT NULL
├── RoleID               FK → Role.RoleID    NOT NULL
├── + CommonColumns
UNIQUE constraint on (UserID, RoleID)
```

### Role Rules

- **MUST** Every new `User` row is assigned the project-defined default role in `UserRole` immediately after the `User` insert, within the same registration transaction. The specific default role is defined in the project documentation.
- **MUST** The project documentation must explicitly list all app-specific roles to be seeded at application startup, their `SortOrder` values, and which role is the registration default.
- **MUST** Role names in the app DB `Role` table are the single source of truth. The `RoleDefs` constants class (in `{AppName}.Domain` or `{AppName}.Contracts`) must mirror these values exactly — no magic strings anywhere in application code.
- **MUST** At JWT generation, the server queries the app DB `UserRole` table to retrieve all active roles for the user and stamps them as `role` claims. The identity DB does not hold or manage solution roles.
- **MUST** For sensitive or destructive operations, re-validate the user's roles against the app DB at request time — do not rely solely on the JWT `role` claims, which reflect roles at the time the token was issued.
- **SHOULD** A user may hold multiple roles simultaneously (e.g., `User` + `Admin`). Authorization policies should evaluate the full role set.
- **SHOULD** Role assignment and revocation are audit-logged via `CreatedUser` / `LastUpdatedUser` / `IsDeleted` on the `UserRole` row. Removing a role sets `IsDeleted = true` — rows are never physically deleted.

## Authentication-Critical Index Strategy

Authentication tables are on the hot request path — every login, token refresh, and replay-detection check hits these indexes. Missing or incorrect indexes on auth tables cause latency spikes under load that are difficult to diagnose after deployment. Define these indexes at schema creation time, not after observing production slowness.

### Standard Auth Index Set

| Table | Index Name | Columns | Type | Purpose |
|-------|-----------|---------|------|---------|
| `AspNetUsers` | `IX_AspNetUsers_NormalizedEmail` | `NormalizedEmail` | UNIQUE | Email lookup on every login and registration |
| `UserSolutionCredential` | `IX_UserSolutionCredential_UserIdSolutionId` | `(UserId, RegisteredSolutionId)` | COMPOSITE | Per-solution credential lookup on every login |
| `UserSolutionCredential` | `IX_UserSolutionCredential_LockoutEnd` | `LockoutEndDateUtc` WHERE `LockoutEndDateUtc IS NOT NULL` | FILTERED | Lockout check on login (only rows in active lockout) |
| `RefreshToken` | `IX_RefreshToken_UserIdIsRevokedIsUsed` | `(UserId, IsRevoked, IsUsed)` | COMPOSITE | Active token lookup on logout and revocation |
| `RefreshToken` | `IX_RefreshToken_JwtId` | `JwtId` | UNIQUE | Token pairing: link access token to refresh token |
| `RefreshToken` | `IX_RefreshToken_DeviceFingerprintUserId` | `(DeviceFingerprint, UserId)` | COMPOSITE | Per-device revocation |
| `EmailVerificationToken` | `IX_EmailVerificationToken_Token` | `Token` | UNIQUE | Token validation on email link click |
| `EmailVerificationToken` | `IX_EmailVerificationToken_UserId` | `UserId` | SIMPLE | User-scoped token lookup |
| `EmailVerificationToken` | `IX_EmailVerificationToken_ExpiryDateUtc` | `ExpiryDateUtc` WHERE `IsConsumed = 0` | FILTERED | Nightly cleanup job (unconsumed, expired tokens) |
| `ConsumedAccessToken` | `IX_ConsumedAccessToken_TokenHash` | `TokenHash` | UNIQUE | Replay detection on every authenticated request |
| `ConsumedAccessToken` | `IX_ConsumedAccessToken_ConsumedDateUtc` | `ConsumedDateUtc` | SIMPLE | Nightly cleanup job (expired consumed tokens) |
| `API_SigningKey` | `IX_API_SigningKey_IsCurrent` | `IsCurrent` WHERE `IsActive = 1` | FILTERED | Current signing key lookup at token generation |
| `API_SigningKey` | `IX_API_SigningKey_DeprecatedAfterUtc` | `DeprecatedAfterUtc` WHERE `IsActive = 1` | FILTERED | JWKS endpoint: active keys served to consumers |
| `API_RateLimitPolicy` | `IX_API_RateLimitPolicy_SolutionEndpoint` | `(RegisteredSolutionId, EndpointName)` WHERE `IsActive = 1` | FILTERED COMPOSITE | Policy cache load at startup and refresh |

### Rules

- **MUST** All indexes in the table above are created in the initial database migration for any project using VegaIdentity. None are optional.
- **MUST** Filtered indexes (WHERE clause) are used where the query always filters on a predictable condition (e.g., `IsConsumed = 0`, `IsActive = 1`). Never index the full table when a filtered index is sufficient.
- **MUST** Composite indexes are ordered with the highest-selectivity column first (e.g., `UserId` before `IsRevoked`).
- **SHOULD** Index creation is included in the migration script and verified in a post-migration check, not deferred to a DBA.
- **SHOULD** New auth tables introduced in later phases follow the same pattern: identify every query on the hot path, ensure each has a supporting index, and document the rationale in the schema notes.

## Custom Token-Table Patterns

When implementing any token-based security mechanism, the first decision is whether the token belongs in an ASP.NET Identity framework table or a custom dedicated table.

### Decision Tree

```
Is this token managed natively by ASP.NET Core Identity
(via UserManager<T> / IUserTwoFactorTokenProvider)?
    │
    ├─ YES → Use framework tables (AspNetUserTokens, AspNetUserLogins, etc.)
    │         UserManager<T> is permitted for these tables.
    │         Do NOT wrap these calls in custom SPs.
    │
    └─ NO → Use a custom dedicated table.
              Apply the SP-only data access rule.
              Design the table with CommonColumns inheritance.
```

### When to Use a Custom Table

Use a custom table when any of the following apply:
- The token has business-level expiry, replay tracking, or multi-token-per-user requirements.
- The token requires a cleanup/retention policy (nightly job, batch purge).
- The token is specific to a custom flow not native to ASP.NET Identity (e.g., email verification, replay detection, solution-scoped password reset).
- The token must support filtered indexes for performance on the hot path.

### Examples by Category

| Token Type | Table | Rationale |
|------------|-------|-----------|
| Refresh token | `RefreshToken` (custom) | Needs per-device revocation, rotation tracking, `DeviceIdentifier` |
| Email verification token | `EmailVerificationToken` (custom) | Multiple pending tokens per user; explicit expiry and cleanup |
| Access token replay tracking | `ConsumedAccessToken` (custom) | Single-use enforcement, replay alerting, nightly purge |
| Password reset token | `ConsumedResetTokens` (custom) | Single-use via `jti`; short-lived signed JWT; replay check |
| 2FA tokens | `AspNetUserTokens` (framework) | Native Identity flow via UserManager |
| External login tokens | `AspNetUserLogins` (framework) | Native Identity flow via UserManager |

### Rules

- **MUST** Custom token tables inherit `CommonColumns`.
- **MUST** Custom token tables store only hashed or encrypted values — never plaintext tokens.
- **MUST** All data access on custom token tables goes through stored procedures (SP-only rule). `UserManager<T>` is not used for custom tables.
- **MUST** The decision (framework table vs. custom table) is documented in the schema notes for each token type.
- **SHOULD** Custom token tables include an explicit expiry column (`ExpiryDateUtc`) and a nightly cleanup job targeting that column.

## Phone Number Data Management

Phone numbers are stored in a dedicated table when the application requires phone-based verification or SMS delivery (e.g., MFA, password reset, SMS notifications). This section specifies schema, indexes, and verification lifecycle.

### When to Use This Pattern

Implement phone number storage when the application requires:
- SMS-based MFA or password reset
- SMS notifications or alerts
- Account recovery via SMS
- Phone-based identity verification

Do NOT implement this section if the application has no phone-based features.

### Required Tables

**UserPhoneNumber** — User-registered phone numbers with verification and MFA settings

```sql
CREATE TABLE [UserPhoneNumber] (
    [UserPhoneNumberId] INT PRIMARY KEY IDENTITY(1,1),
    [UserPhoneNumberGuid] UNIQUEIDENTIFIER NOT NULL UNIQUE DEFAULT newid(),
    [UserId] NVARCHAR(128) NOT NULL FOREIGN KEY REFERENCES [AspNetUsers]([Id]),
    [PhoneNumber] NVARCHAR(20) NOT NULL,    -- Normalized: digits only (no formatting)
    [Carrier] NVARCHAR(50) NOT NULL,        -- Carrier code (e.g., "verizon", "att")
    [CarrierCountry] NVARCHAR(2) NOT NULL DEFAULT 'US',  -- ISO 3166-1 alpha-2
    [IsVerified] BIT NOT NULL DEFAULT 0,    -- User verified this phone via code
    [VerifiedDateUtc] DATETIME2 NULL,       -- UTC timestamp of verification
    [IsPreferred] BIT NOT NULL DEFAULT 0,   -- Primary phone for MFA
    [IsSmsEnabled] BIT NOT NULL DEFAULT 1,  -- User can disable SMS to this number
    -- CommonColumns (Name, Description, CreatedDate, CreatedUser, LastUpdatedDate,
    -- LastUpdatedUser, IsActive, SortOrder, IsDeleted, DeletedDate, DeletedUser)
);

-- INDEXES
-- Query pattern: "Find user's preferred verified phone for SMS delivery"
CREATE INDEX [IX_UserPhoneNumber_UserId_IsPreferred] 
    ON [UserPhoneNumber]([UserId], [IsPreferred]) 
    WHERE [IsVerified] = 1 AND [IsSmsEnabled] = 1;

-- Query pattern: "List all verified phones for a user (MFA enrollment)"
CREATE INDEX [IX_UserPhoneNumber_UserId_IsVerified] 
    ON [UserPhoneNumber]([UserId], [IsVerified]);

-- Query pattern: "Active phone numbers only"
CREATE INDEX [IX_UserPhoneNumber_IsActive] 
    ON [UserPhoneNumber]([IsActive]) 
    WHERE [IsActive] = 1;
```

**SmsCarrier** — Carrier reference data for SMS gateway mapping

```sql
CREATE TABLE [SmsCarrier] (
    [SmsCarrierId] INT PRIMARY KEY IDENTITY(1,1),
    [CarrierCode] NVARCHAR(50) NOT NULL UNIQUE,  -- "verizon", "att", "tmobile", etc.
    [CarrierName] NVARCHAR(255) NOT NULL,        -- "Verizon Wireless"
    [CountryCode] NVARCHAR(2) NOT NULL,          -- ISO 3166-1 alpha-2
    [EmailGateway] NVARCHAR(100) NOT NULL,       -- Email-to-SMS gateway (e.g., "vtext.com")
    [CharacterLimit] INT DEFAULT 160,            -- SMS character limit (usually 160)
    [IsActive] BIT NOT NULL DEFAULT 1,
    -- CommonColumns (Name, Description, CreatedDate, CreatedUser, LastUpdatedDate,
    -- LastUpdatedUser, SortOrder, IsDeleted, DeletedDate, DeletedUser)
);

-- Seed data: Carriers by country (extensible for future additions)
INSERT INTO [SmsCarrier] ([CarrierCode], [CarrierName], [CountryCode], [EmailGateway], 
                          [CharacterLimit], [Name], [SortOrder])
VALUES 
  ('verizon', 'Verizon Wireless', 'US', 'vtext.com', 160, 'Verizon', 10),
  ('att', 'AT&T Wireless', 'US', 'txt.att.net', 160, 'AT&T', 20),
  ('tmobile', 'T-Mobile US', 'US', 'tmomail.net', 160, 'T-Mobile', 30),
  ('uscc', 'US Cellular', 'US', 'mms.uscc.net', 160, 'US Cellular', 40),
  ('rogers', 'Rogers Wireless', 'CA', 'pcs.rogers.com', 160, 'Rogers', 50),
  ('bell', 'Bell Wireless', 'CA', 'txt.bell.ca', 160, 'Bell', 60),
  ('telstra', 'Telstra Wireless', 'AU', 'telstra.com.au', 160, 'Telstra', 70);
```

### Phone Number Normalization & Storage

Phone numbers are stored in normalized form (digits only, no formatting):
- Input: `(202) 555-1234` or `+1-202-555-1234` or `2025551234`
- Stored: `2025551234`
- Validation: Per-country format rules (US=10 digits, Canada=10, Australia=9–10, etc.)
- Lookup: Always normalize before querying the index

### Phone Number Verification Lifecycle

**Step 1 — User Registers Phone**

```
POST /api/v1/accounts/add-phone
{
  "phoneNumber": "2025551234",
  "carrier": "verizon",
  "carrierCountry": "US"
}
```

Server-side:
1. Validate phone format per country rules
2. Create `UserPhoneNumber` row with `IsVerified = 0`
3. Generate 6-digit verification code
4. Send code via SMS using email-to-SMS carrier gateway
5. Return response with `userPhoneNumberGuid` and confirmation that code was sent

**Step 2 — User Verifies Phone**

```
POST /api/v1/accounts/verify-phone
{
  "userPhoneNumberGuid": "550e8400-e29b-41d4-a716-446655440000",
  "verificationCode": "654321"
}
```

Server-side:
1. Look up `UserPhoneNumber` by GUID and confirm it belongs to the authenticated user
2. Validate code:
   - Code matches the code sent in Step 1
   - Code has not expired (5–10 minute window, project-specific)
   - Code has not been used yet (single-use)
3. On match:
   - Set `IsVerified = 1`, `VerifiedDateUtc = GETUTCDATE()`
   - If this is the user's first verified phone, set `IsPreferred = 1`
   - Return response with `isVerified: true` and `isPreferred` status
4. On mismatch: Return generic error; do not disclose which check failed

**Step 3 — Use for MFA**

Once verified, the phone number becomes available for MFA. On login, if MFA is enabled and the user has at least one verified phone with `IsSmsEnabled = 1`, the login flow prompts the user to select SMS or email as the MFA channel (see Chapter 5 — **## Multi-Factor Authentication (MFA) Strategy**).

### Phone List & Management Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/accounts/phones` | GET | List all registered phones (verified + unverified) for the user |
| `/accounts/add-phone` | POST | Register a new phone number |
| `/accounts/verify-phone` | POST | Verify a phone number with a code |
| `/accounts/phones/{guid}` | DELETE | Remove (soft-delete) a registered phone |
| `/accounts/phones/{guid}/prefer` | PATCH | Mark a phone as preferred for MFA |
| `/accounts/phones/{guid}` | PATCH | Update phone settings (e.g., disable SMS to this number) |

### Disabling SMS to a Phone

A user can disable SMS delivery to a phone without deleting it:
```
PATCH /accounts/phones/{userPhoneNumberGuid}
{ "isSmsEnabled": false }
```

This sets `IsSmsEnabled = 0` but retains the phone record for future re-enabling. The phone remains verified and can be reactivated by setting `IsSmsEnabled = 1` without requiring code re-verification.

### Preferred Phone Selection

A user may register multiple phones but can have only one preferred phone for MFA. Setting a phone as preferred automatically clears the preferred flag on all other phones:

```
PATCH /accounts/phones/{userPhoneNumberGuid}/prefer
{ "isPreferred": true }
```

Server-side:
1. Set `IsPreferred = 1` on the target phone
2. Set `IsPreferred = 0` on all other phones for this user
3. Return the updated phone record

### Index Strategy

Three indexes optimize the hot-path query patterns:

| Index | Columns | Filter | Rationale |
|-------|---------|--------|-----------|
| `IX_UserPhoneNumber_UserId_IsPreferred` | `(UserId, IsPreferred)` | `IsVerified = 1 AND IsSmsEnabled = 1` | Most common query: "Find user's preferred phone for MFA SMS delivery" |
| `IX_UserPhoneNumber_UserId_IsVerified` | `(UserId, IsVerified)` | None | List all verified phones for enrollment UI |
| `IX_UserPhoneNumber_IsActive` | `(IsActive)` | `IsActive = 1` | Administrative queries and cleanup jobs |

### Verification Code Lifecycle

Verification codes are typically stored in `EmailVerificationToken` (reused from email verification flow) or in a custom `SmsVerificationCode` table. Requirements:

- Code lifetime: 5–10 minutes (project-specific)
- Code format: 6 digits (numeric; shorter codes acceptable for SMS)
- Single-use: A code is consumed on first successful match; subsequent attempts fail
- Resend: Issuing a new code invalidates the prior code immediately
- Cleanup: Nightly job soft-deletes unconsumed, expired codes

See **## Cleanup and Retention Patterns** for cleanup job design.

### Rules

- **MUST** Phone numbers are stored normalized (digits only; no formatting or special characters)
- **MUST** `IsVerified` is set only after successful code validation. Never trust user-submitted "verified" flags
- **MUST** A user can register multiple phones, but only one can be marked `IsPreferred = 1` at any time
- **MUST** Unverified phones (`IsVerified = 0`) cannot be used for MFA or SMS delivery
- **MUST** Verification codes are single-use and time-limited (5–10 minutes, project-specific)
- **MUST** All phone data access goes through stored procedures (SP-only rule); direct table queries are not permitted
- **MUST** Soft-delete phones via `IsDeleted` flag; never physically delete
- **SHOULD** Allow users to disable SMS to a specific phone (`IsSmsEnabled = 0`) without losing the phone record
- **SHOULD** Auto-mark the first verified phone as preferred; clear preferred status if a user deletes their preferred phone
- **SHOULD** Track metrics: % of users with registered phones, % of phones verified, preferred SMS vs. email MFA adoption

## Cleanup and Retention Patterns

Token tables grow unboundedly without a retention policy. Every custom token table must have an explicit cleanup strategy defined at design time.

### Cleanup Categories

| Category | Strategy | Timing |
|----------|----------|--------|
| Expired unconsumed tokens | Soft-delete (`IsDeleted = 1`) — preserve for audit | Nightly background job |
| Expired consumed tokens | Soft-delete or hard-delete depending on retention policy | Nightly or weekly |
| Replay-tracking records | Hard-delete after configurable retention window (default 7 days) | Nightly background job |
| Rate limit hit records | Aggregate and archive; delete raw rows after 30 days | Weekly job |

### Soft Delete vs Hard Delete

Use **soft delete** when the record has audit value (e.g., a consumed email verification token proves a user confirmed their address at a specific time).

Use **hard delete** when the record is purely operational with no audit value after expiry (e.g., an expired unconsumed `ConsumedAccessToken` entry from a token that was never replayed).

Document the choice for each table in the schema notes.

### Cleanup Job Design

- Run as a background service (Hangfire or `IHostedService`) on a fixed schedule.
- Target the `ExpiryDateUtc` index — never do full table scans for cleanup.
- Delete in batches (e.g., 1,000 rows per execution) to avoid long-running transactions under load.
- Log the count of deleted rows per run for monitoring.
- Alert if a cleanup job fails to run for more than 24 hours — unbounded growth is a risk.

### Standard Cleanup Schedule

| Table | Job Frequency | Target Condition |
|-------|--------------|-----------------|
| `EmailVerificationToken` | Nightly | `ExpiryDateUtc < GETUTCDATE()` AND `IsConsumed = 0` |
| `ConsumedAccessToken` | Nightly | `ExpiryDateUtc < GETUTCDATE()` |
| `RefreshToken` | Nightly | `ExpiryDate < GETUTCDATE()` AND (`IsRevoked = 1` OR `IsUsed = 1`) |
| `ConsumedResetTokens` | Nightly | `CreatedDate < GETUTCDATE() - 7 days` |

### Rules

- **MUST** Every custom token table has a defined cleanup strategy in the schema documentation before the table is created.
- **MUST** Cleanup jobs target indexed columns — never full table scans.
- **MUST** Cleanup jobs are monitored. A failing or missing cleanup job must trigger an alert.
- **SHOULD** Batch delete size is configurable (default 1,000 rows). Adjust based on table growth rate and maintenance window constraints.
- **SHOULD** Soft-deleted records are excluded from all application queries via `WHERE IsDeleted = 0` in stored procedures. Hard-deleted records do not need this filter.

## Composite Index Rationale

Composite indexes are non-obvious — the column order matters, and a wrong order produces an index that is unused or only partially useful. Document the rationale for every composite index in the schema notes.

### Column Order Principle

Place columns in this order, left to right:

1. **Equality predicates first** — columns used in `WHERE col = value` (highest selectivity goes first within this group).
2. **Range predicates second** — columns used in `WHERE col > value` or `WHERE col BETWEEN`.
3. **Include columns last** — columns returned by the query but not filtered on (use the `INCLUDE` clause, not key columns, for these).

### Auth-Table Composite Index Rationale

| Index | Column Order | Rationale |
|-------|-------------|-----------|
| `IX_UserSolutionCredential_UserIdSolutionId` | `UserId`, `RegisteredSolutionId` | `UserId` has higher selectivity than `SolutionId` (one user, many solutions is rare in practice; but the user filter eliminates the most rows). Both are equality predicates. |
| `IX_RefreshToken_UserIdIsRevokedIsUsed` | `UserId`, `IsRevoked`, `IsUsed` | User filter first (equality, high selectivity); bit-flag filters follow to narrow within the user's token set. |
| `IX_RefreshToken_DeviceFingerprintUserId` | `DeviceFingerprint`, `UserId` | Device fingerprint first — the query pattern is "find all tokens for this device" not "find all tokens for this user on this device". |
| `IX_API_RateLimitPolicy_SolutionEndpoint` | `RegisteredSolutionId`, `EndpointName` | Solution first — the lookup pattern is always "for this solution, what is the policy for this endpoint?" |

### When to Use a Filtered Index Instead

Prefer a filtered index (`WHERE` clause) over a composite index when:
- The query always filters on a fixed boolean condition (e.g., `IsActive = 1`, `IsConsumed = 0`).
- The qualifying subset is a small fraction of the total rows.
- The base table is large and the unfiltered rows would pollute the index with rarely-queried data.

A filtered index is smaller, faster to maintain, and often produces better query plans than a composite index on the same columns without the filter.

### Rules

- **MUST** Every composite index includes a comment in the migration script explaining the column order and the query it supports.
- **MUST** Composite indexes are verified against the actual query patterns in stored procedures after implementation — not assumed to be correct from the design.
- **SHOULD** Prefer a filtered index over a full-table composite index when the qualifying condition is a fixed boolean and the qualifying row fraction is small (< 20%).

---

## CHANGELOG

| Version | Date | Change | Source |
|---------|------|--------|--------|
| 1.11 | 2026-05-19 | Added `## Authentication-Critical Index Strategy` — standard auth index set, filtered indexes, composite indexes for VegaIdentity-class projects | Migrated from VegaIdentity RF, Critical Gap 6 |
| 1.11 | 2026-05-19 | Added `## Custom Token-Table Patterns` — decision tree for framework vs. custom tables, examples by category | Migrated from VegaIdentity RF, Blocking Decision OQ-8 |
| 1.11 | 2026-05-19 | Added `## Cleanup and Retention Patterns` — nightly job design, soft vs. hard delete guidance, standard cleanup schedule | Migrated from VegaIdentity RF, Critical Gap 1 + Architecture |
| 1.11 | 2026-05-19 | Added `## Composite Index Rationale` — column order principle, auth-table examples, filtered index preference guidance | Migrated from VegaIdentity RF, Critical Gap 6 |
| 1.13 | 2026-05-23 | Added `## SQL Login and Database Role Pattern` — role naming conventions (`Role-[processName]` / `Role_[loginName]`), login-to-role-to-SP EXECUTE chain, setup sequence, and rules; scope limited to non-EF Core activity. Updated three-login MUST rule to reference this section. | User direction |
| 1.12 | 2026-05-21 | Added `## Phone Number Data Management` — schema, verification lifecycle, MFA integration, endpoint patterns, index strategy | Migrated from VegaIdentity Review Findings, Section 2.85 (SMS Integration) |
