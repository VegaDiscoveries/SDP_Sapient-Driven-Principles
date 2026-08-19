# Generic Project Guidelines & Architecture Specification

A reusable template for multi-tier .NET solutions — web-first with planned mobile expansion

**Version:** 1.10 | **Created:** 2026-03-13 | **Derived from:** DewFromHeavenWebsite & VirtualCoinFolio reviews | **Target Framework:** .NET 10 LTS

> **⚠️ Sync rule — agent instruction:** This is the parent document. Each chapter has a corresponding section file in `docs/GenericProjectGuidlines_Sections/`. Any change made to a chapter here **must be mirrored in the corresponding section file**. Any change made in a section file must be mirrored in the corresponding chapter here. Both must remain identical in content for their shared sections.
> 
> **TOC Maintenance:** The section folder contains a `GenericProjectGuidlines_TOC.md` file that must stay in sync with the Contents list below. When you add, rename, or delete a chapter/section, update both the Contents list here AND the TOC file. See `GenericProjectGuidlines_TOC.md` for detailed maintenance instructions.

> **⚠️ Append-only — agent instruction:** This document is an append-only architecture record. Do not delete or reword existing content. New or revised guidance must be added below the content it supersedes. Strikethrough (`~~text~~`) is a valid edit technique — it visually marks content as superseded while retaining it for audit purposes. Use strikethrough to mark the old text, then place the replacement immediately after on a new line.

---

## Contents

1. [Solution Structure](#chapter-1--solution-structure)
2. [Project Roles & Responsibilities](#chapter-2--project-roles--responsibilities)
3. [Folder & File Organization](#chapter-3--folder--file-organization)
4. [Versioning Strategy](#chapter-4--versioning-strategy)
5. [Authentication & Security](#chapter-5--authentication--security)
6. [Logging](#chapter-6--logging)
7. [Database Architecture](#chapter-7--database-architecture)
8. [Data Access Patterns](#chapter-8--data-access-patterns)
9. [DTO & Contract Library](#chapter-9--dto--contract-library)
10. [API Design & Response Envelope](#chapter-10--api-design--response-envelope)
11. [Website — Blazor](#chapter-11--website--blazor)
12. [Mobile Readiness](#chapter-12--mobile-readiness)
13. [Coding Standards](#chapter-13--coding-standards)
14. [Configuration & Secrets](#chapter-14--configuration--secrets)
15. [Error Handling](#chapter-15--error-handling)
16. [Source Control & Commit Rules](#chapter-16--source-control--commit-rules)
17. [Database Seed Data Patterns](#chapter-17--database-seed-data-patterns)

---

## Chapter 1 — Solution Structure

Every new solution must be laid out with all future consumers — website, API, mobile apps, and shared libraries — accounted for from day one, even if only the website is built first. Retrofitting clean separation later is significantly more expensive than building the seams upfront.

### Required Projects

| Project | SDK | Role | Built When |
|---------|-----|------|------------|
| `{AppName}.Domain` | Microsoft.NET.Sdk | Internal domain entities, EF Core mapping types for query/projection (the database schema is owned by `.Database`), interfaces. No web dependencies. | Phase 1 |
| `{AppName}.Contracts` | Microsoft.NET.Sdk | DTOs, API request/response shapes, shared enums. Zero web dependencies. | Phase 1 |
| `{AppName}.API` | Microsoft.NET.Sdk.Web | REST API — JWT auth, versioned controllers, Swagger, EF Core via DbContext for query/projection only (no migrations; schema deploys from `.Database`). | Phase 1 |
| `{AppName}.Website` | Microsoft.NET.Sdk.Web | Blazor Web App — consumes the API or DbContext directly (see Chapter 11). | Phase 1 |
| `{AppName}.MAUI` | Microsoft.NET.Sdk.Maui | Cross-platform mobile/desktop app — references Contracts only, consumes API via HTTP. | Phase 2 |
| `{AppName}.UnitTests` | Microsoft.NET.Sdk | Pure-logic unit tests (services, mappers, validators). No DB access, no HTTP. | Phase 1 |
| `{AppName}.IntegrationTests` | Microsoft.NET.Sdk | Integration tests against a real SQL Server instance. Fires production stored procedures and verifies state via direct table/view reads with elevated DB privileges; setup writes directly to tables. | Phase 1 (when solution has DB or external-integration surface) |

> **ℹ️ Naming:** Replace `{AppName}` with the solution's PascalCase product name throughout all project names, namespaces, and folder paths. Example: `VirtualCoinFolio.API`, `VirtualCoinFolio.Contracts`.

### Dependency Graph

```
  {AppName}.Database         <— SSDT .sqlproj, no project references
                             produces: .dacpac (deployed to SQL Server)

  {AppName}.Domain           <— no external project references
        ^
        |  (entity types, interfaces)
  {AppName}.API              references: Domain, Contracts
        ^
        |  (HTTP / REST)
  {AppName}.Website          references: Contracts  [or Domain if Blazor-direct pattern]
        ^
        |  (HTTP / REST)
  {AppName}.MAUI             references: Contracts only

  {AppName}.Contracts        referenced by: API, Website, MAUI
                             NEVER references: Domain, API, Website, MAUI

  {AppName}.UnitTests        references: Domain, Contracts, project(s) under test
                             NEVER hits: DB, HTTP, external services

  {AppName}.IntegrationTests references: Domain, Contracts, project under test (typically API)
                             deployment dependency: {AppName}.Database (.dacpac)
                             uses: elevated DB privileges per test access model
```

> **Updated 2026-05-23 — `.Database` project changed from SSDT to DbUp class library:**  
> ~~`{AppName}.Database  <— SSDT .sqlproj, no project references`~~  
> ~~`                    produces: .dacpac (deployed to SQL Server)`~~  
> `{AppName}.Database  <— DbUp class library (.csproj), no project references`  
> `                    runs: DatabaseMigrator.Migrate() (deployed to SQL Server)`  
>  
> ~~`deployment dependency: {AppName}.Database (.dacpac)`~~  
> `deployment dependency: {AppName}.Database (DbUp migration runner)`

> **⚠️ Rule:** The `Contracts` library must never reference `Domain` or any web framework package. This single rule is what makes mobile adoption possible without rework.

> **⚠️ Rule:** `.IntegrationTests` is a separate project from `.UnitTests`. The access regime (elevated DB privileges), dependencies (real DB instance), and run cost differ materially; merging them produces a slow, brittle test surface.

### Target Framework Rules

- **MUST** All projects target `net10.0` or the then-current LTS release. Never target an out-of-support TFM (e.g., net5.0, net6.0).
- **MUST** All projects in the same solution must target the same major .NET version.
- **SHOULD** Plan to upgrade to the next LTS within 6 months of its release to stay ahead of support windows.
- **SHOULD** Run `dotnet list package --vulnerable` as part of every CI build and treat any high-severity CVE as a blocking issue.

---

## Chapter 2 — Project Roles & Responsibilities

Each project in the solution has a clearly defined scope of responsibility. Code placed in the wrong project creates coupling that is expensive to undo. When in doubt, apply the question: *"Does this code need to know about HTTP, the database, or the UI?"* and place it in the outermost project that actually needs that knowledge.

### {AppName}.Domain

Owns the ground truth of what data looks like at rest. Has no knowledge of HTTP, the API surface, or any UI framework.

- Entity classes that map directly to database tables
- The `CommonColumns` base class and `ICommonColumns` interface (see Chapter 7)
- EF Core `DbContext` classes — one for Identity, one for the application domain
- Repository interfaces (`IUserRepository`, `ICoinRepository`, etc.)
- Domain-level enums that describe entity states or types
- EF Core migration files (`Migrations/` subfolder)

> **📋 Not allowed in Domain:** Any reference to `Microsoft.AspNetCore.*`, MVC versioning packages, Swagger, JWT bearer, or any UI framework package.

### {AppName}.Contracts

The shared vocabulary between all consumers of the API. This is the **only** project that both the API and all clients (website, mobile) reference for data shapes. It must be portable to any .NET runtime including MAUI.

- Request DTOs (`LoginRequestDto`, `CreateCoinRequestDto`)
- Response DTOs (`UserProfileResponseDto`, `CoinSummaryDto`)
- Enums that appear in API request or response bodies
- Shared configuration model classes (`JwtConfig`, `PaginationOptions`)
- Data annotation validation attributes on DTO properties

> **📋 Not allowed in Contracts:** EF Core attributes (`[DatabaseGenerated]`, `[ForeignKey]`, `[InverseProperty]`), navigation properties, `DbContext` references, or any `Microsoft.AspNetCore.*` dependency.

### {AppName}.API

The sole gatekeeper between the database and all external consumers. Enforces authentication, authorization, input validation, and business rules before any data is read or written.

- Versioned controllers under `Controllers/V{n}/`
- Service classes that implement repository interfaces from Domain
- JWT token issuance, validation, and refresh token management
- Swagger / OpenAPI configuration and post-build spec file generation
- Localization and culture routing middleware
- Structured logging setup (NLog or Serilog)
- Mapping between Domain entities and Contracts DTOs
- Environment-specific `appsettings.{Environment}.json` files

### {AppName}.Website

A Blazor Web App. Depending on project complexity, it either calls the API over HTTP (full separation) or accesses the database directly via `DbContext` (simpler single-deployment pattern). The choice must be made at project start and recorded in the solution's README.

- Blazor components organized under `Components/`
- `PageBase` and `SecurePageBase` classes for shared lifecycle logic and auth checks
- ASP.NET Core Identity UI for registration, login, and account management
- Role constants, session extensions, and string extensions under `Support/`
- Static assets (CSS, JS, fonts, images) under `wwwroot/`

> **ℹ️ Pattern decision:** Use the API-backed pattern when mobile clients exist or are planned. Use the Blazor-direct-EF pattern only for internal tools or single-deployment sites with no mobile roadmap.

### {AppName}.MAUI

A pure API consumer. References only the `Contracts` library. Contains no business logic and performs no direct database access.

- HTTP client generated from the OpenAPI spec (via Kiota or NSwag) or hand-written typed client
- Platform-specific secure token storage (iOS Keychain, Android Keystore, Windows DPAPI)
- MVVM viewmodels bound to MAUI pages and shell navigation
- Platform-specific code under `Platforms/{iOS|Android|Windows|MacCatalyst}/`
- App version number tracked separately from the API version (see Chapter 4)
- Dynamic, structured screen content sourced per target — mobile always via the API, desktop via
  an API-synced local cache by default (see Chapter 12's Dynamic Content Delivery)

---

## Chapter 3 — Folder & File Organization

A consistent folder structure across all projects reduces the time needed to navigate unfamiliar code and makes onboarding new team members faster. Create a folder only when there are two or more files that share a common scope. Never create empty folders as placeholders in source control.

### Domain Project

```
  {AppName}.Domain/
  ├── Common/
  │   ├── CommonColumns.cs            // base class, inherited by every entity
  │   └── ICommonColumns.cs           // interface enforcing common column contract
  ├── Entities/                       // one file per database table / entity
  │   ├── User.cs
  │   ├── RefreshToken.cs
  │   └── {EntityName}.cs
  ├── Enums/                          // domain-level enums (never shared in Contracts)
  ├── Interfaces/                     // IRepository and IService interfaces
  │   ├── IUserRepository.cs
  │   └── I{Name}Repository.cs
  └── Data/
      ├── AppDbContext.cs             // all non-identity entities
      └── AppIdentityDbContext.cs     // ASP.NET Core Identity tables only
```

### Contracts Project

```
  {AppName}.Contracts/
  ├── Requests/                       // inbound DTOs, grouped by feature area
  │   ├── Auth/
  │   │   ├── LoginRequestDto.cs
  │   │   └── RegisterRequestDto.cs
  │   └── {Feature}/
  │       └── Create{Feature}RequestDto.cs
  ├── Responses/                      // outbound DTOs, mirrors Requests structure
  │   ├── Auth/
  │   │   └── AuthResponseDto.cs
  │   └── {Feature}/
  │       └── {Feature}SummaryDto.cs
  ├── Enums/                          // enums shared between API and all clients
  └── Configuration/                  // config model classes (JwtConfig, etc.)
```

### API Project

```
  {AppName}.API/
  ├── Controllers/
  │   └── V{n}/                       // one subfolder per API major version
  │       ├── AuthController.cs
  │       └── {Feature}Controller.cs
  ├── Services/                       // business logic; implements Domain interfaces
  │   ├── AuthService.cs
  │   └── {Feature}Service.cs
  ├── Middleware/                     // custom pipeline components
  │   ├── ExceptionHandlingMiddleware.cs
  │   └── CultureRoutingMiddleware.cs
  ├── Extensions/                     // IServiceCollection and IApplicationBuilder helpers
  │   ├── ServiceCollectionExtensions.cs
  │   └── ApplicationBuilderExtensions.cs
  ├── Mapping/                        // entity <-> DTO mapping (manual or AutoMapper)
  ├── Migrations/                     // EF Core generated migrations — never hand-edit
  ├── appsettings.json
  ├── appsettings.Development.json
  ├── appsettings.Staging.json
  ├── appsettings.Production.json
  ├── nlog.config                     // or serilog config (see Chapter 6)
  └── Program.cs
```

### Website Project

```
  {AppName}.Website/
  ├── Components/
  │   ├── Account/                    // Identity scaffolded pages and email sender
  │   ├── Layout/                     // MainLayout.razor, NavMenu.razor
  │   ├── Pages/
  │   │   ├── Public/                 // pages accessible without authentication
  │   │   └── Secure/                 // pages requiring authentication
  │   └── Support/                    // PageBase.cs, SecurePageBase.cs
  ├── Content/                        // JSON data files backing structured page content (Ch. 11)
  ├── Data/                           // WebsiteContext, WebsiteUser, WebsiteRole
  ├── Support/
  │   ├── Extensions/                 // StringExtensions.cs, SessionExtensions.cs
  │   ├── Exceptions/                 // custom exception types
  │   ├── Globals/                    // Globals.cs, RoleInfoConfig.cs, PasswordRequirements.cs
  │   └── Identity/                   // IdentityHelper.cs, async utilities
  ├── wwwroot/
  │   ├── css/
  │   ├── js/
  │   ├── images/
  │   └── fonts/
  ├── appsettings.json
  ├── appsettings.Development.json
  └── Program.cs
```

### File Naming Rules

- **MUST** File names match the primary class they contain exactly (PascalCase). One primary class per file.
- **MUST** DTO files end with the suffix `Dto`. Example: `LoginRequestDto.cs`, `UserSummaryDto.cs`.
- **MUST** Interface files are prefixed with `I` and named identically to their implementation. Example: `IUserRepository.cs` / `UserRepository.cs`.
- **MUST** Controller files end with `Controller`. Service files end with `Service`. DbContext files end with `DbContext`.
- **MUST** Namespaces mirror the folder path from the project root. File at `{AppName}.API/Controllers/V1/AuthController.cs` → namespace `{AppName}.API.Controllers.V1`.
- **SHOULD** Use file-scoped namespace declarations (`namespace Foo.Bar;`) to reduce indentation depth.
- **SHOULD** Extension method files end with `Extensions`. Example: `StringExtensions.cs`, `SessionExtensions.cs`.
- **MAY** Group tightly related small classes (e.g., a set of custom exception types) in a single file when each class is under 30 lines.

---

## Chapter 4 — Versioning Strategy

Versioning must be planned independently for three separate concerns: the API, the website, and the mobile apps. Conflating these leads to forced lock-step releases and breaks consumer independence.

### API Versioning

The API is versioned by URL path segment. This is the most explicit and debuggable form of versioning, visible in logs, browser history, and mobile network traces without any special tooling.

```csharp
// Route prefix on every versioned controller
[ApiController]
[Route("api/v{version:apiVersion}/[controller]")]
[ApiVersion("1.0")]
public class CoinController : ControllerBase { }
```

- **MUST** All controller routes include the version segment: `/api/v1/coins`, `/api/v2/coins`.
- **MUST** A new version folder `Controllers/V{n}/` is created for each major API version. Never edit existing versioned controllers — only add new ones alongside them.
- **MUST** Breaking changes (field removals, type changes, behavior changes) require a new major version. Additive changes (new optional fields) may be made in-place.
- **SHOULD** Keep at least one prior major version live for a minimum of 90 days after a new major ships, to allow mobile clients time to update through app stores.
- **SHOULD** Auto-generate the OpenAPI spec after each build and commit it to `docs/openapi.json` so mobile developers always have the current contract.

```xml
<!-- {AppName}.API.csproj — post-build OpenAPI spec generation -->
<Target Name="GenerateOpenApiSpec" AfterTargets="Build">
  <Exec Command="dotnet swagger tofile --output docs/openapi.json $(OutputPath)$(AssemblyName).dll v1"
        ContinueOnError="true"/>
</Target>
```

### Website Versioning

The website version is independent of the API version. It follows semantic versioning (`MAJOR.MINOR.PATCH`) and is stored in the `.csproj` file, never hardcoded in source files.

```xml
<PropertyGroup>
  <Version>1.3.0</Version>
  <AssemblyVersion>1.3.0.0</AssemblyVersion>
</PropertyGroup>
```

> **Addition — 2026-07-23 — "source files" scope:** "Never hardcoded in source files" above refers
> to executable code files (`.cs`, `.razor`, etc.) only. `.resx`, JSON, XML, and other
> configuration/data files are **not source code files**, even when they live inside a project
> folder or participate in the build (e.g., `.resx` generating a `*.Designer.cs`). Storing an
> application version value in `appsettings.json` for runtime display or telemetry is not a
> violation of this rule — see Chapter 14's Configuration File Hierarchy, which explicitly lists
> "app name/version" as valid `appsettings.json` content, and Chapter 13's code-vs-data-file
> distinction for the general test.

### Mobile App Versioning

Mobile apps carry two independent version numbers: the user-visible *display version* and the monotonically incrementing *build number* required by app store pipelines.

```xml
<PropertyGroup>
  <ApplicationVersion>42</ApplicationVersion>
  <ApplicationDisplayVersion>1.2.0</ApplicationDisplayVersion>
</PropertyGroup>
```

- **MUST** `ApplicationVersion` (build number) increments with every store submission, even hotfixes.
- **MUST** The app declares the minimum API version it requires and gracefully degrades or prompts for update when that version is unavailable.
- **MUST** All NuGet package versions are pinned explicitly. Never use floating versions (`*`).
- **SHOULD** Run `dotnet list package --outdated` and `dotnet list package --vulnerable` before every release.

---

## Chapter 5 — Authentication & Security

Authentication is implemented once, in the API, using JWT bearer tokens. This single implementation serves the website (via stored tokens or a thin cookie wrapper), the mobile app (via secure OS storage), and any future third-party integrations without redesign.

### JWT Bearer Tokens

**Signing Algorithm:** RS256 (asymmetric, RSA-based). VegaIdentity.API is the sole issuer and holds the private key; all consumer APIs validate tokens using the public key via the JWKS endpoint. See [JWKS Endpoint & Key Rotation](#jwks-endpoint--key-rotation) for key management, discovery, and rotation strategy.

#### Token Validation Example

```csharp
// Program.cs — token validation with RS256 public keys (consumer API pattern)
// All active public keys are fetched from the issuer's JWKS endpoint and cached locally.
// IssuerSigningKeys (plural) accepts all keys in the JWKS set; the JWT middleware selects
// the correct key by matching the token's `kid` header claim. During a rotation's 30-day
// overlap window both the old and new keys are present in the JWKS — tokens signed by
// either key validate without any code change or restart.
var jwksJson = /* serialized JWKS JSON fetched from /.well-known/jwks.json */;
var signingKeys = new JsonWebKeySet(jwksJson).Keys;
var tokenValidationParameters = new TokenValidationParameters
{
    ValidateIssuerSigningKey = true,
    IssuerSigningKeys        = signingKeys,  // plural — supports rotation overlap window
    ValidateIssuer           = true,
    ValidIssuer              = "https://identity.vegadiscoveries.com",
    ValidateAudience         = true,
    ValidAudience            = "vegadiscoveries.solutionname",  // solution-specific audience identifier
    ValidateLifetime         = true,
    RequireExpirationTime    = true,
    ClockSkew                = TimeSpan.Zero  // no grace period on expiry
};
```

#### Private Key Generation & Storage (Issuer)

1. **Generate RSA Key Pair:** Use OpenSSL or equivalent tooling to generate a 2048-bit or 4096-bit RSA key pair.
   ```bash
   openssl genrsa -out private_key.pem 2048
   openssl rsa -in private_key.pem -pubout -out public_key.pem
   ```

2. **Store Private Key:** Encrypt the private key using a master key and store in a secure vault (e.g., Azure Key Vault, AWS Secrets Manager, or environment-backed encrypted storage). **Private keys must never be committed to source control or stored in plaintext.**

3. **Key Vault Secret Naming:** For VegaIdentity.API, use a naming convention like:
   - Secret name: `vega-identity-jwt-key-{keyId}`
   - Example: `vega-identity-jwt-key-rsa_2026_q2`
   - Store both the private key (PEM format) and the key ID for reference

4. **Application Startup:** Load the private key from the secure vault at startup. The application initializes the JWT signing service with the current private key (marked `IsCurrent = 1` in the `API_SigningKey` table).

#### Token Validation Strategy

Every solution validates tokens against its own `AudienceIdentifier`, ensuring a token issued for one Vega Discoveries solution is rejected by all others and that an explicit login is required per solution.

All consumer APIs validate using the **public key only**. The issuer (VegaIdentity.API) holds and guards the private key. See [Key Rotation Lifecycle](#key-rotation-lifecycle) for quarterly rotation and emergency rotation procedures.

### Shared Identity Database & Solution Registry

For Vega Discoveries projects the Identity database is shared across all solutions. Each solution is registered in the `RegisteredSolutions` table, which is the authority for valid audience identifiers and enables per-solution credential and token scoping.

```
RegisteredSolutions
├── SolutionID            INT IDENTITY PK
├── SolutionGUID          UNIQUEIDENTIFIER DEFAULT newid()
├── Name                  NVARCHAR(255)   e.g. "BookVault"
├── AudienceIdentifier    NVARCHAR(255)   e.g. "vegadiscoveries.bookvault"
│                                         stamped into the JWT aud claim on login
└── + CommonColumns
```

The `AudienceIdentifier` is stored in each solution's `appsettings.json` (non-sensitive) and bound via `IOptions<JwtConfig>`. The JWT secret remains in User Secrets / environment variables only.

### Per-Solution Passwords

Each user has a single `AspNetUsers` record as their identity anchor. Login passwords are stored per solution in `UserSolutionCredential`. The standard `AspNetUsers.PasswordHash` column is repurposed to store the **Reset PIN hash** — a global recovery credential set once at first registration, never used during any login flow.

#### UserSolutionCredential Table

```
UserSolutionCredential         one row per user per solution
├── UserSolutionCredentialID   INT IDENTITY PK
├── UserSolutionCredentialGUID UNIQUEIDENTIFIER DEFAULT newid()
├── UserID                     FK → AspNetUsers
├── SolutionID                 FK → RegisteredSolutions
├── PasswordHash               solution-specific login password hash
├── FailedAttemptCount         lockout tracked independently per solution
├── LockoutEnd                 solution-scoped lockout expiry (UTC)
├── LastPasswordChangedDate    UTC timestamp of last password change
└── + CommonColumns
UNIQUE constraint on (UserID, SolutionID)
```

#### AspNetUsers.PasswordHash — Repurposed as Reset PIN

The Reset PIN is:
- Set once by the user at first registration on any Vega Discoveries solution
- Stored as a bcrypt hash in `AspNetUsers.PasswordHash`
- Never read during a login attempt on any solution
- Used exclusively as a second validation factor during the password reset flow
- Changeable only by providing the current Reset PIN — never via an email link alone

Users must be clearly instructed not to reuse a solution password as their Reset PIN.

### Registration Flow

**First registration (user's first Vega Discoveries solution):**
1. User registers on Solution A — provides email, solution password, and Reset PIN
2. `AspNetUsers` row created in the identity DB — `PasswordHash` stores the hashed Reset PIN; `NormalizedEmail` stored as lowercase
3. `UserSolutionCredential` row created for Solution A — stores the solution password hash
4. `User` row created in the **app DB** — `Email` set to lowercase email (matching `AspNetUsers.NormalizedEmail`). Immediately after, a `UserRole` row is inserted assigning the project-defined default role (defined in the project documentation). Steps 2–4 are committed as separate transactions with compensating rollback: if any app DB insert fails, the identity DB rows created in steps 2–3 are rolled back.

**Subsequent registration (user joins a second solution later):**
1. Email lookup finds the existing `AspNetUsers` row
2. User sets a solution password for Solution B
3. New `UserSolutionCredential` row created for Solution B
4. `AspNetUsers.PasswordHash` (Reset PIN) is not changed

### Password Reset Flow

Password resets use a short-lived **signed JWT reset token** embedded in the reset URL. The built-in `exp` claim prevents reset links from living indefinitely. The token is signed with the server's existing JWT secret — no additional key infrastructure is required.

```
1.  User requests password reset for Solution A

2.  User is challenged for their Reset PIN
    2a. PIN valid:
        — Server generates a signed JWT reset token:
              { "sub":          "<userId>",
                "resetPinHash": "<current AspNetUsers.PasswordHash>",
                "solutionId":   "<SolutionGUID>",
                "purpose":      "password-reset",
                "jti":          "<unique token id>",
                "exp":          <now + 20 minutes> }
              Signed with the server JWT secret
        — Token embedded in the reset URL
        — Reset link sent to the user's registered email address
        — User shown confirmation screen with options:
              [ Resend Email ]  [ Contact Support ]  [ Back to Login ]

    2b. PIN invalid:
        — User notified that the Reset PIN was not recognised
        — Prompted to contact support
        — No email sent

3.  User clicks the reset link — reset form requests new solution password only

4.  Server validates the JWT reset token:
        i.   Signature valid
        ii.  exp claim not expired (≤ 20 minutes)
        iii. purpose claim == "password-reset"
        iv.  resetPinHash claim matches current AspNetUsers.PasswordHash
             (mismatch: Reset PIN changed after link was issued — link rejected)
        v.   jti not in ConsumedResetTokens (single-use check)
        — Any failed check rejects with a generic error; no reason given to caller

5.  All checks pass:
        — UserSolutionCredential.PasswordHash updated for Solution A only
        — jti recorded in ConsumedResetTokens to prevent replay

6.  All other solution credentials untouched
```


### Refresh Tokens

Access tokens are short-lived (15–60 minutes). Refresh tokens allow clients to obtain new access tokens silently. Each refresh token is stored in the database, tied to a device fingerprint, and rotated on every use.

- Refresh token entity lives in `Domain/Entities/RefreshToken.cs` and inherits `CommonColumns`
- Fields: `UserId`, `JwtId`, `Token` (hashed), `ExpiryDate`, `IsUsed`, `IsRevoked`, `IpAddress`, `DeviceIdentifier`
- On use: mark old token `IsUsed = true`, issue a new refresh token (rotation)
- On logout: set `IsRevoked = true` for all tokens belonging to that user on that device

### Token Lifetime Defaults

Framework-level baselines for all solutions. Solutions may tighten (shorten) these values by documenting the override in the project documentation. Relaxing a default beyond these baselines requires architectural review.

| Token Type | Default Lifetime | Notes |
|------------|-----------------|-------|
| Access token | 15 minutes | Short-lived; renewed via refresh token |
| Refresh token | 30 days | Rotated on every use; revocable per-device |

- **MUST** `ClockSkew = TimeSpan.Zero` on all `TokenValidationParameters` — no grace period is applied on top of the configured lifetime.
- **SHOULD** Access token lifetime is chosen to minimize the stolen-token exposure window without forcing excessive refresh requests.
- **SHOULD** Refresh token lifetime balances session usability against the risk window of a long-lived stolen token.
- **SHOULD** Where regulatory compliance mandates shorter lifetimes, the stricter value always takes precedence and must be documented.

### Account Lockout Baselines

Framework-level defaults for brute-force protection. Solutions may tighten these values by documenting the override in the project documentation. Relaxing a default requires architectural review.

| Parameter | Default | Notes |
|-----------|---------|-------|
| Failed attempt threshold | 5 attempts | Counted within the rolling window below |
| Rolling window | 30 minutes | Attempts older than 30 min are not counted toward the threshold |
| Lockout duration | 30 minutes | Fixed; non-escalating |
| Counter reset | 24 hours | Nightly job resets `FailedLoginAttempts` for records with no failure in the past 24 hours |

**Scope:** Lockout is per-solution. A lockout on Solution A does not affect the user's access to Solution B.

**Override support:** Per-solution limits are stored in `RegisteredSolutions` or equivalent configuration, enabling ops to tighten thresholds without code deployment.

- **MUST** Lockout state is tracked in `UserSolutionCredential` (`FailedLoginAttempts`, `LastFailedLoginDateUtc`, `LockoutEndDateUtc`).
- **MUST** On successful login: reset `FailedLoginAttempts = 0` and `LockoutEndDateUtc = NULL`.
- **MUST** The locked-out user receives a generic message: "Account is temporarily locked due to multiple failed login attempts. Please try again later." No threshold values are disclosed to the caller.
- **MUST** Manual lockout unlock via the Admin Panel clears `LockoutEndDateUtc` and `FailedLoginAttempts` for the specific user/solution pair.
- **SHOULD** Alert on more than 10 lockout events for the same account within 24 hours — this pattern indicates a credential-stuffing attack.

### Rate Limiting Architecture

Use `SlidingWindowRateLimiter` (ASP.NET Core built-in) for all auth endpoints. Sliding window is preferred over fixed window for bursty traffic because it prevents bunching at window boundaries.

#### Default Policies

| Endpoint | Permit Limit | Window | Segmented by |
|----------|-------------|--------|--------------|
| `POST /auth/login` | 5 attempts | 15 minutes | Per IP |
| `POST /auth/register` | 10 attempts | 60 minutes | Per IP |
| `POST /auth/refresh` | 30 attempts | 60 minutes | Per token |
| `POST /auth/forgot-password` | 3 attempts | 60 minutes | Per email |

#### Per-Solution Override Pattern

Policies are stored in the `API_RateLimitPolicy` table. A `NULL` `RegisteredSolutionId` is the system default; a non-null `RegisteredSolutionId` is a solution-specific override. At request time, the solution-specific policy is used if present; otherwise the system default is applied.

This enables ops to tighten or adjust limits per-solution without code changes or redeployment.

#### Cache Strategy

- Load all active policies into memory at startup.
- Background job refreshes the cache every 5 minutes.
- No database query on the per-request hot path.
- Changes take effect within the next cache refresh cycle.

#### Rules

- **MUST** Rate-limited responses return `429 Too Many Requests` with a `Retry-After` header. Never return `200 OK` for a rate-limited request.
- **MUST** All rate limit policies are stored in `API_RateLimitPolicy` and loaded via the cache. Hard-coded limits in middleware are not permitted.
- **SHOULD** Alert on more than 100 rate-limit hits from a single IP within 1 hour — this pattern indicates credential-stuffing or DDoS.
- **SHOULD** Correlate rate-limit hit events with account lockout events in security monitoring.

### JWKS Endpoint & Key Rotation

VegaIdentity.API is the sole JWT issuer. All consumer APIs (solution APIs) validate tokens using RS256 public keys discovered via the JWKS endpoint — they never hold private keys.

#### JWKS Endpoint

| Property | Value |
|----------|-------|
| Path | `/.well-known/jwks.json` |
| Cache-Control | `public, max-age=300` (5-minute TTL) |
| Algorithm | RS256 |
| Key ID format | `rsa_YYYY_qN` (e.g., `rsa_2026_q2`) |

The `kid` claim is stamped into every JWT header and matched against the JWKS at validation time, allowing consumer APIs to select the correct public key without iterating the full set.

#### Key Rotation Process

1. Generate a new RSA key pair.
2. Insert the new public key into `API_SigningKey` with `IsCurrent = 1`; set the old key to `IsCurrent = 0`.
3. The JWKS endpoint immediately serves both keys — the overlap window begins.
4. After 30 days: set `DeprecatedAfterUtc` on the old key. It is automatically excluded from the JWKS on the next query.
5. No app restart required. Consumer APIs pick up the new key within their next cache refresh (≤ 5 minutes).

**Overlap window: 30 days.** This ensures all in-flight tokens signed with the old key remain valid throughout their lifetime before the old key is retired.

#### Consumer API Discovery Strategy

1. Fetch JWKS on startup; cache in memory.
2. Refresh cache every 5 minutes via background timer.
3. On JWT validation failure where `kid` is not in the cached set: refetch JWKS immediately, then retry. This handles the race condition during rotation where a new token arrives before the cache has refreshed.

#### Rules

- **MUST** The JWKS endpoint exposes public keys only. Private keys must never appear in any API response.
- **MUST** Every issued JWT includes a `kid` header claim matching the signing key's `KeyId`.
- **MUST** Consumer APIs use the `kid` claim to select the correct key from the cached JWKS — never iterate-and-try-all.
- **MUST** Alert if `API_SigningKey` has no row with `IsCurrent = 1` — this indicates a failed rotation that must be resolved immediately.
- **SHOULD** Rotate signing keys at least quarterly. Document rotation events in the audit log.

### Client-Side Token Storage Strategies

Token storage strategy must be chosen deliberately before web client implementation. The wrong choice trades security for convenience in ways that are difficult to retrofit.

#### Storage Options Summary

| Method | XSS Risk | CSRF Risk | Survives Refresh | Notes |
|--------|----------|-----------|-----------------|-------|
| `localStorage` (plain) | **High** | None | Yes | Plaintext token accessible to any JS |
| `sessionStorage` (plain) | **High** | None | No | Lost on tab close or page refresh |
| In-memory only | None | None | **No** | Lost on every page refresh |
| HttpOnly cookie | None | Moderate | Yes | CSRF-protected by `SameSite=Strict`; limits external link UX |
| `localStorage` (encrypted) | Mitigated | None | Yes | **Recommended for web clients** |

#### Recommended Strategy — Encrypted localStorage with Replay Detection

Issue encrypted (non-deterministic AES-GCM) access tokens from the API. The web client stores the encrypted blob in `localStorage`; the plaintext never touches the client. The server decrypts, validates, and marks each token as consumed on first use.

**Why this works:**
- A stolen encrypted token cannot be decrypted by the attacker (server-only decryption key).
- Non-deterministic encryption means the same plaintext produces different ciphertext each time — the attacker cannot re-create or verify the token.
- First use consumes the token. Any replay triggers a security alert and rejection. Damage from a single XSS theft is limited to one request.

**Client storage call:**
```js
localStorage.setItem('accessToken', encryptedToken);
// Authorization header on each request:
Authorization: Bearer {encryptedToken}
```

#### Mobile Clients

MAUI and other mobile clients use secure OS storage (Keychain on iOS, Keystore on Android). The HttpOnly cookie and localStorage strategies do not apply. Never use `localStorage` patterns in mobile client code.

#### Rules

- **MUST** Web clients store only the encrypted token blob — never the plaintext JWT.
- **MUST** Each encrypted token is single-use. Server marks it consumed on first validation; any subsequent use is a replay and is rejected.
- **MUST** Replay attempts are logged and trigger a security alert.
- **MUST NOT** Store plaintext JWTs in `localStorage` or `sessionStorage`.
- **SHOULD** On replay detection, revoke the user's active refresh tokens and force re-authentication.

### SMS Verification via Email-to-SMS Gateways

SMS verification codes are used for Multi-Factor Authentication (MFA) and password reset flows. This section specifies how to integrate SMS delivery without third-party providers.

#### When to Use This Pattern

Use email-to-SMS carrier gateways to deliver SMS codes when:
- Cost control is important (zero API fees, reuses existing email infrastructure)
- International scope is limited to known carriers
- Marketing or high-volume SMS is not needed (security codes only)
- Existing SMTP infrastructure is already operational

**Do NOT use this pattern for:** Marketing campaigns, two-way SMS, high-volume notifications, or custom sender IDs.

#### How It Works

Major cellular carriers provide email-to-SMS gateways that automatically convert email to SMS:
- Verizon: `[10-digit-number]@vtext.com` → SMS
- AT&T: `[10-digit-number]@txt.att.net` → SMS
- T-Mobile: `[10-digit-number]@tmomail.net` → SMS
- US Cellular: `[10-digit-number]@mms.uscc.net` → SMS
- (Additional carriers: Rogers, Bell, Telstra, etc. per country)

The system constructs a carrier gateway email address from the user's phone number and carrier selection, then sends it via the existing `IEmailService`. The carrier gateway transparently converts the email to an SMS message. No API integration or rate limits apply.

#### Required Schema

**UserPhoneNumber** — Stores verified and unverified phone numbers per user

```sql
CREATE TABLE [UserPhoneNumber] (
    [UserPhoneNumberId] INT PRIMARY KEY IDENTITY(1,1),
    [UserPhoneNumberGuid] UNIQUEIDENTIFIER NOT NULL UNIQUE DEFAULT newid(),
    [UserId] NVARCHAR(128) NOT NULL FOREIGN KEY REFERENCES [AspNetUsers]([Id]),
    [PhoneNumber] NVARCHAR(20) NOT NULL,  -- Normalized: digits only
    [Carrier] NVARCHAR(50) NOT NULL,      -- "verizon", "att", "tmobile", etc.
    [CarrierCountry] NVARCHAR(2) NOT NULL DEFAULT 'US',  -- ISO 3166-1 alpha-2
    [IsVerified] BIT NOT NULL DEFAULT 0,  -- Code verification completed
    [VerifiedDateUtc] DATETIME2 NULL,
    [IsPreferred] BIT NOT NULL DEFAULT 0, -- Primary number for MFA
    [IsSmsEnabled] BIT NOT NULL DEFAULT 1,-- User can disable SMS to this number
    -- CommonColumns (Name, Description, CreatedDate, CreatedUser, LastUpdatedDate, 
    -- LastUpdatedUser, IsActive, SortOrder, IsDeleted, DeletedDate, DeletedUser)
);

CREATE INDEX [IX_UserPhoneNumber_UserId_IsPreferred] 
    ON [UserPhoneNumber]([UserId], [IsPreferred]) 
    WHERE [IsVerified] = 1 AND [IsSmsEnabled] = 1;
CREATE INDEX [IX_UserPhoneNumber_UserId_IsVerified] 
    ON [UserPhoneNumber]([UserId], [IsVerified]);
```

**SmsCarrier** — Reference table for carrier-to-gateway mapping

```sql
CREATE TABLE [SmsCarrier] (
    [SmsCarrierId] INT PRIMARY KEY IDENTITY(1,1),
    [CarrierCode] NVARCHAR(50) NOT NULL UNIQUE,  -- "verizon", "att", "tmobile"
    [CarrierName] NVARCHAR(255) NOT NULL,        -- "Verizon Wireless"
    [CountryCode] NVARCHAR(2) NOT NULL,          -- "US"
    [EmailGateway] NVARCHAR(100) NOT NULL,       -- "vtext.com"
    [CharacterLimit] INT DEFAULT 160,            -- SMS character limit
    [IsActive] BIT NOT NULL DEFAULT 1,
    -- CommonColumns
);

-- Seed data: US, CA, AU carriers (extensible for others)
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

#### Service Implementation Pattern

```csharp
public interface ISmsService
{
    Task<SmsResult> SendVerificationCodeAsync(string userId, string code, string codeType);
    Task<SmsResult> SendToPhoneAsync(string phoneNumber, string carrier, string countryCode, 
                                      string body, Guid? solutionId = null);
}

public class SmsService : ISmsService
{
    private readonly IEmailService _emailService;
    
    public async Task<SmsResult> SendVerificationCodeAsync(string userId, string code, 
                                                           string codeType)
    {
        // 1. Look up user's preferred phone from UserPhoneNumber table
        // 2. Validate phone is verified and SMS is enabled
        // 3. Look up carrier gateway email from SmsCarrier table
        // 4. Construct SMS recipient: "[phonenumber]@[carrier-gateway]"
        // 5. Delegate to IEmailService.SendAsync() with carrier gateway email
        // 6. Return SmsResult with success status and the email address used
    }
}
```

#### Phone Number Registration & Verification Flow

**Step 1 — Register Phone**
```
POST /api/v1/accounts/add-phone
{ "phoneNumber": "2025551234", "carrier": "verizon", "carrierCountry": "US" }

Response: { "userPhoneNumberGuid": "...", "verificationCodeSent": true }
```

Server generates a 6-digit verification code and sends it as SMS to the carrier gateway email.

**Step 2 — Verify Phone**
```
POST /api/v1/accounts/verify-phone
{ "userPhoneNumberGuid": "...", "verificationCode": "654321" }

Response: { "isVerified": true, "isPreferred": true }
```

Server validates the code and marks the UserPhoneNumber row as verified. If this is the user's first verified phone, it is automatically marked as preferred.

**Step 3 — Use for MFA**

On login, if MFA is enabled and the user has a verified phone, they are prompted to select the MFA channel (SMS or Email). See **### Multi-Factor Authentication (MFA) Strategy** below.

#### Tradeoffs

**Advantages:**
- ✅ Zero cost — leverages existing email infrastructure; no Twilio/AWS fees
- ✅ No new dependencies — no API credentials to manage
- ✅ Instant delivery — same SMTP latency as email
- ✅ Carrier SLAs — Verizon, AT&T, T-Mobile provide 24/7 infrastructure

**Disadvantages:**
- ❌ User must know their carrier (or auto-detect by area code)
- ❌ 160-character limit (adequate for 6-digit codes, limiting for longer messages)
- ❌ Sender ID is the email address, not customizable
- ❌ No delivery receipts or two-way messaging
- ❌ International complexity — different gateways per country

#### Rules

- **MUST** SMS is used for security codes only (MFA, password reset). Not for marketing, alerts, or notifications.
- **MUST** Phone numbers are normalized to digits only; no formatting stored.
- **MUST** Carrier gateways are one-way; do not rely on delivery receipts.
- **MUST** Code lifetime is 5–10 minutes (project-specific, documented in project guidelines).
- **MUST** Codes are single-use; a second attempt generates a new code and re-sends it.
- **MUST** If SMS delivery fails (invalid phone, carrier gateway down, etc.), offer email fallback immediately.
- **SHOULD** Start with US, CA, AU carriers; extend via the extensible `SmsCarrier` seed table for other countries.
- **SHOULD** A user can disable SMS to a specific phone without deleting the record (`IsSmsEnabled = 0`).

### Multi-Factor Authentication (MFA) Strategy

MFA adds a second verification factor for sensitive operations. Two channels are supported: email (primary) and SMS (optional). This section specifies MFA strategy, flow, and channel selection.

#### MFA Scope

MFA is required for:
- Login (if MFA is enabled for the account)
- Password reset (always, as second factor after PIN validation)
- Email change (always, as account-level operation)
- Sensitive admin actions (admin-configurable)

#### Email MFA — Primary Channel

- **Default:** All users have email MFA enabled by default
- **Mechanism:** One-time code or signed link sent to registered email
- **Infrastructure:** Reuses existing email service and email verification token pattern
- **Enrollment:** Automatic; no user action required beyond email address registration
- **Recovery:** Always available if SMS fails or is unavailable

See **### Email Verification Token Lifecycle** for email token design and lifecycle.

#### SMS MFA — Secondary Channel

- **Enrollment:** Requires phone number registration and code-based verification
- **Availability:** Only available if user has at least one verified phone number marked as enabled
- **Mechanism:** SMS sent via email-to-SMS carrier gateway (see **### SMS Verification via Email-to-SMS Gateways**)
- **User Choice:** If user has both email and verified phone, they select the channel at login time

#### MFA Login Flow

```
1. User submits credentials (email + password)
2. Validation:
   a. Email and password match a UserSolutionCredential row
   b. Account is not locked out
   c. Account is active and not suspended
3. If MFA is enabled for this account:
   a. Server checks: does user have verified phone AND is SMS enabled on preferred phone?
   b. If YES: prompt user to select channel:
      [ Send SMS to preferred phone ]  [ Send email instead ]
   c. User selects channel
   d. Send code to selected channel
   e. Return { status: "MfaChallengeRequired", mfaSessionId: "..." }
4. Client presents code entry form
5. User enters code: POST /auth/verify-mfa [MfaSessionId] { code }
6. Server validates:
   a. Code matches the sent code
   b. Code has not expired (5–10 minute window)
   c. Code has not been used yet (single-use)
   d. mfaSessionId is valid and not expired
7. On success: Issue access token + refresh token
8. On failure: Return error; user can resend code or retry
```

#### Code Delivery Rules

- **MUST** SMS code is 6 digits (easier for users; adequate entropy for short lifetime)
- **MUST** Email code is alphanumeric (7+ characters; higher entropy for longer validity windows)
- **MUST** Code lifetime is 5–10 minutes; project documentation specifies the value
- **MUST** Codes are single-use. A second submission attempt generates and sends a new code, invalidating the prior code
- **MUST** If SMS delivery fails (carrier down, invalid phone, etc.), immediately retry as email
- **MUST** A code sent via one channel cannot be verified via the other channel

#### Resend Strategy

- First resend: Immediate (no delay)
- Second resend: 30-second delay (prevents brute-force code enumeration)
- Third resend: Requires support contact (prevents abuse; user is directed to support)

#### Rules

- **MUST** MFA is always channel-optional. A user with both email and phone chooses the channel at each login
- **MUST** SMS channel is not available unless the user has at least one verified, enabled phone number
- **MUST** If a user's only MFA phone becomes unverified or disabled mid-session, email channel is offered as fallback
- **MUST** MFA challenge sessions are tied to a `mfaSessionId`. Once verified, the session is consumed and cannot be reused
- **MUST** MFA challenge sessions expire after 15 minutes of inactivity
- **MUST** Administrators can disable MFA for an account from the Admin Panel. The user must re-enable it by re-registering their phone or verifying email
- **SHOULD** Projects should track MFA adoption and engagement metrics (% of users with MFA enabled, SMS vs. email channel preference)
- **SHOULD** Email MFA codes can be single-use or multi-use (project-specific). SMS codes are always single-use

### Email Verification Token Lifecycle

Email verification tokens must be stored in a dedicated table — not in `AspNetUsers` or framework-managed identity tables. This gives explicit control over expiry, cleanup, and multi-token scenarios (e.g., resend without invalidating a prior link).

#### Token Table

```
EmailVerificationToken
├── EmailVerificationTokenId    INT IDENTITY PK
├── EmailVerificationTokenGuid  UNIQUEIDENTIFIER NOT NULL UNIQUE
├── UserId                      FK → AspNetUsers.Id
├── Token                       NVARCHAR(512) — bcrypt hash of the token sent in the email
├── EmailAddress                NVARCHAR(256) — the address being verified
├── ExpiryDateUtc               DATETIME2 — default +24 hours from creation
├── IsConsumed                  BIT DEFAULT 0
├── ConsumedDateUtc             DATETIME2 NULL
└── + CommonColumns
```

The plaintext token is sent in the email URL. Only the bcrypt hash is stored. Validation bcrypt-hashes the inbound token and matches against stored hashes — the plaintext is never persisted.

#### Verification Flow

1. User clicks the email link; client extracts the plaintext token from the URL.
2. Server bcrypt-hashes the input token and looks it up in `EmailVerificationToken`.
3. Validate: token exists, `IsConsumed = 0`, `ExpiryDateUtc > GETUTCDATE()`, `UserId` matches.
4. On success: set `IsConsumed = 1`, `ConsumedDateUtc = GETUTCDATE()`, set `AspNetUsers.EmailConfirmed = 1`.
5. On any failure: return a generic error — do not disclose which check failed.

#### Cleanup Strategy

- Nightly background job soft-deletes (`IsDeleted = 1`) all rows where `ExpiryDateUtc < GETUTCDATE()` AND `IsConsumed = 0`.
- Consumed tokens are retained for audit trail; soft-deleted rather than hard-deleted.

#### Rules

- **MUST** Store only the bcrypt hash of the verification token. Never store or log the plaintext.
- **MUST** Default token expiry is 24 hours. Projects must document any override.
- **MUST** A resend issues a new token row — it does not invalidate the prior token. If the user clicks an older link it still validates (unless expired or already consumed).
- **MUST** Nightly cleanup runs to prevent unbounded table growth from abandoned tokens.
- **SHOULD** Verification failure responses are generic and do not indicate which validation check failed, to prevent token enumeration.

### Security Questions Architecture

Security questions provide an additional account verification factor for account recovery, high-risk operations, and multi-factor authentication. This section specifies the design, answer storage, and verification flow.

#### Question Library & Assignment

Security questions are **predefined and curated** — users do not create custom questions. A framework-level question library is maintained by the Vega Discoveries ops team via the DevOps dashboard (VegaIdentity.Website). Each solution independently selects which questions are available to its users.

**Question Library Table**

```sql
CREATE TABLE [PredefinedSecurityQuestion] (
    [PredefinedSecurityQuestionId] INT PRIMARY KEY IDENTITY(1,1),
    [QuestionText] NVARCHAR(500) NOT NULL UNIQUE,
    [Category] NVARCHAR(50),              -- e.g., "personal", "security", "childhood"
    [Difficulty] NVARCHAR(50),            -- e.g., "easy", "medium", "hard"
    [IsAssignedToAnySolution] BIT NOT NULL DEFAULT 0,  -- Prevents editing once assigned
    [IsActive] BIT NOT NULL DEFAULT 1,
    -- CommonColumns
);

CREATE INDEX [IX_PredefinedSecurityQuestion_Category] 
    ON [PredefinedSecurityQuestion]([Category]);
CREATE INDEX [IX_PredefinedSecurityQuestion_IsAssignedToAnySolution] 
    ON [PredefinedSecurityQuestion]([IsAssignedToAnySolution]);
```

**Solution-Specific Question Selection**

```sql
CREATE TABLE [SolutionPredefinedSecurityQuestion] (
    [SolutionPredefinedSecurityQuestionId] INT PRIMARY KEY IDENTITY(1,1),
    [SolutionId] INT NOT NULL FOREIGN KEY REFERENCES [RegisteredSolutions]([SolutionId]),
    [PredefinedSecurityQuestionId] INT NOT NULL FOREIGN KEY,
    [SortOrder] INT NOT NULL DEFAULT 100,  -- Per-solution reordering via DevOps dashboard
    -- CommonColumns
    UNIQUE ([SolutionId], [PredefinedSecurityQuestionId])
);

CREATE INDEX [IX_SolutionPredefinedSecurityQuestion_SolutionId_SortOrder] 
    ON [SolutionPredefinedSecurityQuestion]([SolutionId], [SortOrder]);
```

#### Answer Storage & Normalization

User-provided answers are **normalized and bcrypt-hashed** before storage. This ensures consistency across variations of the same answer (spacing, capitalization) while preventing plaintext recovery of answers.

**Answer Normalization Strategy**

Apply the following normalization before hashing:
1. Convert to lowercase: `answer.ToLowerInvariant()`
2. Trim leading/trailing whitespace: `.Trim()`
3. Collapse multiple spaces to single spaces: `.Replace("  ", " ")`

Example: `"John  Smith"` → `"john smith"` (normalized and hashed)

**User Security Questions Table**

```sql
CREATE TABLE [UserSecurityQuestion] (
    [UserSecurityQuestionId] INT PRIMARY KEY IDENTITY(1,1),
    [UserSecurityQuestionGuid] UNIQUEIDENTIFIER NOT NULL UNIQUE DEFAULT newid(),
    [UserId] NVARCHAR(128) NOT NULL FOREIGN KEY REFERENCES [AspNetUsers]([Id]),
    [PredefinedSecurityQuestionId] INT NOT NULL FOREIGN KEY,
    [AnswerHash] NVARCHAR(MAX) NOT NULL,  -- bcrypt(normalized_answer, cost >= 12)
    [DisplayOrder] INT NOT NULL,           -- User-facing question order: 1, 2, 3...
    -- CommonColumns
);

CREATE INDEX [IX_UserSecurityQuestion_UserId_DisplayOrder] 
    ON [UserSecurityQuestion]([UserId], [DisplayOrder]);
CREATE INDEX [IX_UserSecurityQuestion_PredefinedSecurityQuestionId] 
    ON [UserSecurityQuestion]([PredefinedSecurityQuestionId]);
```

#### Question & Answer Setup Flow

**Step 1 — Get Available Questions (During Registration)**

```csharp
// Client calls endpoint to discover questions for the current solution
GET /api/v1/auth/security-questions?solutionId={guid}

// Response: list of predefined questions ordered by SortOrder
[
    { "questionId": "...", "questionText": "What is your mother's maiden name?" },
    { "questionId": "...", "questionText": "In what city were you born?" },
    { "questionId": "...", "questionText": "What was your first pet's name?" },
    ...
]
```

The server queries `SolutionPredefinedSecurityQuestion` filtered by SolutionId, ordered by SortOrder, and joins to `PredefinedSecurityQuestion` to return question text. **Never expose answer hashes or difficulty ratings.**

**Step 2 — Register User with Security Answers**

```csharp
POST /api/v1/auth/register
{
    "email": "user@example.com",
    "password": "...",
    "resetPin": "...",
    "birthMonth": 3,
    "birthYear": 1990,
    "country": "US",
    "securityQuestions": [
        { "questionId": "question-1-guid", "answer": "Jane" },
        { "questionId": "question-2-guid", "answer": "Boston" }
    ]
}
```

The server:
1. Validates the number of answers matches the solution's requirement (configurable; typically 2–5 questions).
2. For each answer:
   - Apply `NormalizeAnswer(answer)` helper
   - Bcrypt-hash the normalized answer (cost ≥ 12)
   - Insert into `UserSecurityQuestion` with DisplayOrder matching input order
   - Validate that each `questionId` is assigned to the current solution via `SolutionPredefinedSecurityQuestion`

#### Answer Verification Flow

**Verification Endpoint**

```csharp
POST /api/v1/accounts/verify-security-answers
{
    "answers": [
        { "questionId": "question-1-guid", "answer": "jane" },
        { "questionId": "question-2-guid", "answer": "boston" }
    ]
}

// Response on success
{ "verified": true }

// Response on failure
{ "verified": false, "message": "One or more answers are incorrect." }
```

**Server Verification Logic**

1. Query `UserSecurityQuestion` rows for the authenticated user, ordered by DisplayOrder.
2. For each provided answer:
   - Apply `NormalizeAnswer(answer)` helper using the same normalization strategy
   - Lookup the bcrypt hash from `UserSecurityQuestion` for the provided `questionId`
   - Use bcrypt.Verify(normalized_input, stored_hash) to compare
   - Do **not** short-circuit on first mismatch — validate all answers silently to prevent answer enumeration
3. Return generic failure message if any answer mismatches; never indicate which answer was wrong.
4. Return success only if all provided answers match.

#### Rules

- **MUST** Security questions are predefined and curated by the ops team. Users do not create custom questions.
- **MUST** Only the Vega Discoveries ops team can add or edit PredefinedSecurityQuestion records via the DevOps dashboard (VegaIdentity.Website). No programmatic mutation by the API.
- **MUST** Once a question is assigned to any solution (`SolutionPredefinedSecurityQuestion` row exists), set `IsAssignedToAnySolution = 1` to prevent accidental edits to the question text.
- **MUST** Answers are normalized (lowercase, trimmed, single spaces) and bcrypt-hashed before storage. Apply the same normalization during verification.
- **MUST** Bcrypt cost is ≥ 12. This provides adequate protection for short security question answers without excessive latency.
- **MUST** On verification failure, return a generic message: "One or more answers are incorrect." Never disclose which answer failed or provide a count of correct answers.
- **MUST** Do not short-circuit answer verification. Validate all provided answers against the hash before returning success or failure to prevent answer enumeration via timing.
- **MUST** Each user can set a distinct answer per question. Reusing the same answer across multiple questions is allowed but not recommended in UI guidance.
- **SHOULD** At registration, require at least 2 security questions (configurable per-solution via `SolutionAccountFieldRequirement`). 2–5 questions is typical.
- **SHOULD** Security questions are re-verified as a second factor during sensitive operations: email change, password reset completion, or admin actions.
- **SHOULD** Users can update their security answers in the account settings panel. The update flow is identical to initial setup (normalize, hash, replace prior answers).

### Key Rotation Lifecycle

This section covers the operational calendar and triggers for RS256 signing key rotation. The technical rotation mechanics (JWKS endpoint, `API_SigningKey` table, consumer cache refresh) are covered in [JWKS Endpoint & Key Rotation](#jwks-endpoint--key-rotation).

#### Rotation Schedule

| Trigger | Action |
|---------|--------|
| Quarterly (routine) | Generate new key pair; begin 30-day overlap; retire old key after overlap |
| Suspected private key compromise | Emergency rotation — immediate; do not wait for overlap expiry |
| Master key rotation | Re-encrypt all private keys stored in `Furniture` table; no JWKS change required |

#### Rotation Checklist

1. Generate a new RSA key pair using approved tooling.
2. Store the new private key in the `Furniture` table (encrypted with the current master key).
3. Insert the new public key into `API_SigningKey` (`IsCurrent = 1`; old key `IsCurrent = 0`).
4. Verify: JWKS endpoint now serves both keys.
5. Monitor: Confirm consumer APIs pick up the new key within 5 minutes (first cache refresh cycle).
6. After 30-day overlap: set `DeprecatedAfterUtc` on the old key.
7. Verify: JWKS no longer includes the old key.
8. Log the rotation event (actor, timestamp, old key ID, new key ID) in the audit log.

#### Emergency Rotation

If a private key is suspected compromised:
1. Perform steps 1–4 above immediately.
2. Set `DeprecatedAfterUtc = GETUTCDATE()` on the old key — remove it from JWKS immediately (no 30-day overlap).
3. All tokens signed with the old key become unvalidatable within minutes. Users must re-authenticate.
4. Revoke all active refresh tokens to force clean re-authentication.
5. File a security incident report.

#### Rules

- **MUST** All key rotation events are audit-logged: actor, timestamp, old `KeyId`, new `KeyId`.
- **MUST** Emergency rotation bypasses the 30-day overlap and immediately removes the compromised key from JWKS.
- **MUST NOT** Delete a key from `API_SigningKey` during normal rotation — use `DeprecatedAfterUtc` to expire it gracefully.
- **SHOULD** Rotation is performed at least quarterly. If a solution's compliance posture requires shorter intervals, document the override in the project documentation.

### Roles & Authorization

Roles are stored in the app DB (see `## App DB Role Tables` in Chapter 7 — Database Architecture) and stamped into the JWT as `role` claims at login time. Each solution maintains its own role assignments; a user may hold different roles across solutions.

#### Standard Roles

The following three roles are seeded by the framework and are present in every solution:

| Role | Default | Purpose |
|------|---------|--------|
| `User` | Yes — generic framework default | Standard authenticated user |
| `Admin` | No | Full solution administration — activates Admin Panel in the UI |
| `Dev` | No | Internal developer and debug access — activates Dev Toolbar in the UI |

The project documentation defines any additional app-specific roles. The project may also override the registration default (e.g., VegaDrop assigns `Player` instead of `User` as the default role).

#### Role Rules

- **MUST** Role names are `public const string` fields in a static `RoleDefs` class in `{AppName}.Domain` or `{AppName}.Contracts`. Never use magic strings for role names anywhere in application code.
- **MUST** At JWT generation, query the app DB `UserRole` table for the user's active roles and include them as `role` claims in the token.
- **MUST** For sensitive or destructive operations, re-validate roles against the app DB at request time — do not rely solely on JWT claims, which reflect roles at token issuance.
- **MUST** Pages requiring authentication inherit from `SecurePageBase`. Public pages inherit from `PageBase`.
- **MUST** `app.UseHttpsRedirection()` appears in the pipeline before any auth middleware. iOS ATS and Android NSC reject plain HTTP in production.
- **MUST** JWT secrets are stored in User Secrets locally and in environment variables or Key Vault in production. Never in `appsettings.json`.
- **SHOULD** Use policy-based authorization over direct role checks for fine-grained permissions.
- **SHOULD** A user may hold multiple roles simultaneously. Authorization policies should evaluate the full role set.

### Admin Panel

When the authenticated user holds the `Admin` role, the UI must expose an Admin Panel (or equivalent admin navigation section). This panel is invisible to all other roles and is never rendered unless the current user's active JWT claims include `Admin`.

**Framework-level admin features (required in every solution):**

| Feature | Description |
|---------|-------------|
| User List | Paginated, searchable, filterable list of all registered accounts. Shows email, registration date, last login, active roles, and account status. |
| User Detail | Full account view — login history, active sessions, role assignments, credential records per solution, lockout status. |
| Role Management | Assign or revoke roles for any user. Role changes take effect at next login (JWT not retroactively invalidated unless refresh token is revoked). |
| Account Activate / Deactivate | Soft-disable an account without deleting it. Invalidates active refresh tokens for that account. |
| Manual Lockout Unlock | Clear a `UserSolutionCredential` lockout state for a specific user and solution without requiring a password reset. |
| Active Sessions | List of accounts with a currently valid refresh token, showing solution, issued-at, and expiry. |
| Failed Login Audit | Recent failed login attempts — account, solution, timestamp, IP. Useful for detecting brute-force patterns. |
| Error Log Viewer | Query recent server-side errors by date range or TraceId. Links to structured log store or surfaces the structured log summary inline. |
| System Announcements | Create, update, or remove global banners or notices displayed to all users in the UI. |
| Maintenance Mode | Toggle maintenance mode for the solution. While active, non-admin users receive a maintenance page rather than the app. |
| Feature Flags | Enable or disable named feature flags at runtime. Applied immediately without redeployment. |

**Project-specific admin features** (e.g., game stats, IAP/purchase history, leaderboard management, content moderation queues) must be defined in the project documentation.

**Rules:**

- **MUST** The Admin Panel is only rendered when the JWT `role` claims include `Admin`. Never infer admin access from any other signal.
- **MUST** All destructive admin actions (deactivate account, revoke role, unlock lockout) require re-validation of the acting admin's `Admin` role against the app DB at request time — do not rely solely on the JWT.
- **MUST** All admin actions are audit-logged: actor account ID, target account ID (if applicable), action name, timestamp, and before/after values where relevant.
- **SHOULD** The Admin Panel uses the same auth token as the main application. No separate admin login is required.
- **SHOULD** Admin list views are paginated server-side. Never load all user records in a single query.

### Required Middleware Order

```csharp
app.UseHttpsRedirection();       // 1
app.UseStaticFiles();            // 2 (website only)
app.UseRouting();                // 3
app.UseRequestLocalization();    // 4
app.UseAuthentication();         // 5 — who are you?
app.UseAuthorization();          // 6 — are you allowed?
app.MapControllers();            // 7 — execute endpoint
```

### Authentication Rules

- **MUST** `ValidateAudience = true` on every solution API. Each solution's `AudienceIdentifier` is loaded from `appsettings.json` via `IOptions<JwtConfig>`.
- **MUST** All login endpoints validate credentials against `UserSolutionCredential` for the requesting solution. `AspNetUsers.PasswordHash` is never read during login.
- **MUST** `AspNetUsers.PasswordHash` stores the Reset PIN hash only. Document this explicitly in the Identity database schema notes.
- **MUST** Password reset tokens are short-lived signed JWTs (recommended: 20 minutes). Never embed unsigned or plain values in reset URLs.
- **MUST** Reset tokens are single-use. The `jti` claim is recorded in `ConsumedResetTokens` on first use and rejected on any replay attempt.
- **MUST** Account lockout is tracked per `UserSolutionCredential` row. A lockout on Solution A does not affect the user's access to Solution B.
- **MUST** The Reset PIN can only be changed by providing the current Reset PIN. It must never be changeable via an email link alone.
- **SHOULD** The "email sent" confirmation screen always displays regardless of internal PIN validation outcome, to prevent user enumeration via timing differences.
- **SHOULD** Clearly label the Reset PIN in all UI as a distinct credential from solution passwords, with explicit guidance not to reuse a solution password as the Reset PIN.

### CHANGELOG — Chapter 5

| Version | Date | Change | Source |
|---------|------|--------|--------|
| 1.11 | 2026-05-19 | Added `### Token Lifetime Defaults` — 15-min access token, 30-day refresh token baselines | Migrated from VegaIdentity RF, Critical Gap 3 |
| 1.11 | 2026-05-19 | Added `### Account Lockout Baselines` — 5 attempts / 30-min window / 30-min lockout with override support | Migrated from VegaIdentity RF, Critical Gap 2 |
| 1.11 | 2026-05-19 | Added `### Rate Limiting Architecture` — SlidingWindowRateLimiter, default policies, per-solution override pattern | Migrated from VegaIdentity RF, Critical Gap 5 |
| 1.11 | 2026-05-19 | Added `### JWKS Endpoint & Key Rotation` — RS256 JWKS endpoint, kid format, 30-day overlap, consumer cache strategy | Migrated from VegaIdentity RF, Critical Gap 4 |
| 1.11 | 2026-05-19 | Added `### Client-Side Token Storage Strategies` — encrypted localStorage with replay detection | Migrated from VegaIdentity RF, Blocking Decision OQ-7 |
| 1.11 | 2026-05-19 | Added `### Email Verification Token Lifecycle` — dedicated table, bcrypt hash, 24h expiry, nightly cleanup | Migrated from VegaIdentity RF, Critical Gap 1 |
| 1.11 | 2026-05-19 | Added `### Key Rotation Lifecycle` — quarterly cadence, emergency rotation checklist, audit log requirements | Migrated from VegaIdentity RF, Critical Gaps 4 + Blocking Decisions OQ-11/OQ-12 |
| 1.12 | 2026-05-21 | Added `### SMS Verification via Email-to-SMS Gateways` — carrier gateway pattern, schema, service implementation, phone registration flow | Migrated from VegaIdentity Review Findings, Section 2.85 (SMS Integration) |
| 1.12 | 2026-05-21 | Added `### Multi-Factor Authentication (MFA) Strategy` — email + SMS channels, login flow, code delivery rules, resend strategy | Migrated from VegaIdentity Review Findings, Section 2.85 (SMS Integration) + MFA design decisions |
| 1.13 | 2026-05-21 | Added `### Security Questions Architecture` — predefined question library, answer normalization + bcrypt hashing, per-solution assignment, verification flow, DevOps dashboard management | User requirements: per-solution demographic fields (birthYear, birthMonth, country, timezone) + security questions for account recovery |

---

## Chapter 6 — Logging

Structured logging must be configured from day one. `Console.WriteLine` is not acceptable in any project tier. Every log entry must carry enough context to reconstruct what happened without a debugger.

### Logging Provider

Use **NLog** or **Serilog** wired into `Microsoft.Extensions.Logging`. All application code uses `ILogger<T>` exclusively — never a static logger reference.

```csharp
// Program.cs — NLog setup
builder.Logging.ClearProviders();
builder.Logging.SetMinimumLevel(LogLevel.Information);
builder.Host.UseNLog();
```

### Log Level Guide

| Level | Use For | Enabled In |
|-------|---------|------------|
| `Trace` | Raw HTTP bodies, SQL parameters | Development only |
| `Debug` | Method flow, variable values | Development only |
| `Information` | Normal milestones: user logged in, record saved | All environments |
| `Warning` | Unexpected but recoverable: deprecated version called, retry | All environments |
| `Error` | Single-operation failures: DB save failed, API timeout | All environments |
| `Critical` | Application-threatening failures: cannot connect to DB on startup | All environments |

### Logging Rules

- **MUST** Use structured templates with named placeholders: `_logger.LogInformation("User {UserId} logged in from {IpAddress}", userId, ip)`
- **MUST** Never use string interpolation in log calls. It defeats structured log indexing.
- **MUST** Never log passwords, JWT secrets, connection strings, or refresh token values at any log level.
- **MUST** Log at `Error` level (not `Warning`) whenever an exception is caught and not re-thrown.
- **SHOULD** Include a correlation / request trace ID in every entry so that all log lines for a single HTTP request can be grouped.
- **SHOULD** Log application name, version, and environment at `Information` on startup.
- **SHOULD** Configure at minimum two targets: rolling file (persistence) and console (development).

> **⚠️ Never do this:** `_logger.LogDebug($"Connection: {connectionString}")` — connection strings contain credentials.

> **Addition — 2026-07-24 — Log file rotation and retention:**
>
> - **MUST** The rolling file target writes one log file per calendar day, named with an
>   embedded `yyyyMMdd` date segment (e.g. `log-20260724.log`). All entries for that day append
>   to the same file.
> - **MUST** Retention is a configured number of days, never hardcoded. Read it from
>   `appsettings.json` via strongly-typed configuration (see Chapter 14) — e.g.
>   `Logging:RetentionDays`. Files older than the configured window are removed automatically by
>   the provider's own archival mechanism: NLog's `archiveEvery="Day"` + `archiveNumbering="Date"`
>   + `maxArchiveFiles` bound to the config value, or Serilog's
>   `rollingInterval: RollingInterval.Day` + `retainedFileCountLimit` bound to the config value.
> - **SHOULD** Default `RetentionDays` to a conservative value (e.g. `30`) in `appsettings.json`,
>   overridable per environment via `appsettings.{Environment}.json`.

---

## Chapter 7 — Database Architecture

Every table in the database follows the same foundational column set. Consistency here pays dividends in auditing, soft-delete patterns, UI sorting, and API response contracts. A table that omits common columns must have written justification in the schema documentation.

### Common Columns — Required in Every Table

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

### CommonColumns Base Class

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

### Database Object Naming Conventions

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

### Database Rules

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
| [`VegaDrop-IdentityDB_ERD_V1.00_20260323.mermaid`](../database/docs/VegaDrop-IdentityDB_ERD_V1.00_20260323.mermaid) | `VegaDiscoveriesIdentity` | ASP.NET Identity & Auth | `AspNetUsers`, `AspNetUserClaims`, `AspNetUserLogins`, `AspNetUserTokens`, `RegisteredSolutions`, `UserSolutionCredential`, `RefreshToken`, `ConsumedResetToken` |
| [`VegaDrop-AppDB-CoreUser_ERD_V1.00_20260323.mermaid`](../database/docs/VegaDrop-AppDB-CoreUser_ERD_V1.00_20260323.mermaid) | `VegaAppVegaDrop` | Core User & Identity | `User`, `UserProfile`, `Role`, `UserRole` |
| [`VegaDrop-AppDB-GamePlay_ERD_V1.00_20260323.mermaid`](../database/docs/VegaDrop-AppDB-GamePlay_ERD_V1.00_20260323.mermaid) | `VegaAppVegaDrop` | Gameplay | `GameSession`, `LeaderboardEntry` |
| [`VegaDrop-AppDB-Commerce_ERD_V1.00_20260323.mermaid`](../database/docs/VegaDrop-AppDB-Commerce_ERD_V1.00_20260323.mermaid) | `VegaAppVegaDrop` | Commerce | `Purchase`, `Entitlement` |
| [`VegaDrop-AppDB-Social_ERD_V1.00_20260323.mermaid`](../database/docs/VegaDrop-AppDB-Social_ERD_V1.00_20260323.mermaid) | `VegaAppVegaDrop` | Social & Sync | `Referral`, `ReferralClick`, `ReferralRedemption`, `FriendRequest`, `LocalStorageSyncRecord` |
| [`VegaDrop-AppDB-SystemAdmin_ERD_V1.00_20260323.mermaid`](../database/docs/VegaDrop-AppDB-SystemAdmin_ERD_V1.00_20260323.mermaid) | `VegaAppVegaDrop` | System & Administration | `FeatureFlag`, `SystemAnnouncement`, `ContentReport`, `DisplayNameModerationItem`, `_LogEmailAudit` |

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

### Authentication-Critical Index Strategy

Authentication tables are on the hot request path — every login, token refresh, and replay-detection check hits these indexes. Missing or incorrect indexes on auth tables cause latency spikes under load that are difficult to diagnose after deployment. Define these indexes at schema creation time, not after observing production slowness.

#### Standard Auth Index Set

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

#### Rules

- **MUST** All indexes in the table above are created in the initial database migration for any project using VegaIdentity. None are optional.
- **MUST** Filtered indexes (WHERE clause) are used where the query always filters on a predictable condition (e.g., `IsConsumed = 0`, `IsActive = 1`). Never index the full table when a filtered index is sufficient.
- **MUST** Composite indexes are ordered with the highest-selectivity column first (e.g., `UserId` before `IsRevoked`).
- **SHOULD** Index creation is included in the migration script and verified in a post-migration check, not deferred to a DBA.
- **SHOULD** New auth tables introduced in later phases follow the same pattern: identify every query on the hot path, ensure each has a supporting index, and document the rationale in the schema notes.

### Custom Token-Table Patterns

When implementing any token-based security mechanism, the first decision is whether the token belongs in an ASP.NET Identity framework table or a custom dedicated table.

#### Decision Tree

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

#### When to Use a Custom Table

Use a custom table when any of the following apply:
- The token has business-level expiry, replay tracking, or multi-token-per-user requirements.
- The token requires a cleanup/retention policy (nightly job, batch purge).
- The token is specific to a custom flow not native to ASP.NET Identity (e.g., email verification, replay detection, solution-scoped password reset).
- The token must support filtered indexes for performance on the hot path.

#### Examples by Category

| Token Type | Table | Rationale |
|------------|-------|-----------|
| Refresh token | `RefreshToken` (custom) | Needs per-device revocation, rotation tracking, `DeviceIdentifier` |
| Email verification token | `EmailVerificationToken` (custom) | Multiple pending tokens per user; explicit expiry and cleanup |
| Access token replay tracking | `ConsumedAccessToken` (custom) | Single-use enforcement, replay alerting, nightly purge |
| Password reset token | `ConsumedResetTokens` (custom) | Single-use via `jti`; short-lived signed JWT; replay check |
| 2FA tokens | `AspNetUserTokens` (framework) | Native Identity flow via UserManager |
| External login tokens | `AspNetUserLogins` (framework) | Native Identity flow via UserManager |

#### Rules

- **MUST** Custom token tables inherit `CommonColumns`.
- **MUST** Custom token tables store only hashed or encrypted values — never plaintext tokens.
- **MUST** All data access on custom token tables goes through stored procedures (SP-only rule). `UserManager<T>` is not used for custom tables.
- **MUST** The decision (framework table vs. custom table) is documented in the schema notes for each token type.
- **SHOULD** Custom token tables include an explicit expiry column (`ExpiryDateUtc`) and a nightly cleanup job targeting that column.

### Phone Number Data Management

Phone numbers are stored in a dedicated table when the application requires phone-based verification or SMS delivery (e.g., MFA, password reset, SMS notifications). This section specifies schema, indexes, and verification lifecycle.

#### When to Use This Pattern

Implement phone number storage when the application requires:
- SMS-based MFA or password reset
- SMS notifications or alerts
- Account recovery via SMS
- Phone-based identity verification

Do NOT implement this section if the application has no phone-based features.

#### Required Tables

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

#### Phone Number Normalization & Storage

Phone numbers are stored in normalized form (digits only, no formatting):
- Input: `(202) 555-1234` or `+1-202-555-1234` or `2025551234`
- Stored: `2025551234`
- Validation: Per-country format rules (US=10 digits, Canada=10, Australia=9–10, etc.)
- Lookup: Always normalize before querying the index

#### Phone Number Verification Lifecycle

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

Once verified, the phone number becomes available for MFA. On login, if MFA is enabled and the user has at least one verified phone with `IsSmsEnabled = 1`, the login flow prompts the user to select SMS or email as the MFA channel (see Chapter 5 — **### Multi-Factor Authentication (MFA) Strategy**).

#### Phone List & Management Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/accounts/phones` | GET | List all registered phones (verified + unverified) for the user |
| `/accounts/add-phone` | POST | Register a new phone number |
| `/accounts/verify-phone` | POST | Verify a phone number with a code |
| `/accounts/phones/{guid}` | DELETE | Remove (soft-delete) a registered phone |
| `/accounts/phones/{guid}/prefer` | PATCH | Mark a phone as preferred for MFA |
| `/accounts/phones/{guid}` | PATCH | Update phone settings (e.g., disable SMS to this number) |

#### Disabling SMS to a Phone

A user can disable SMS delivery to a phone without deleting it:
```
PATCH /accounts/phones/{userPhoneNumberGuid}
{ "isSmsEnabled": false }
```

This sets `IsSmsEnabled = 0` but retains the phone record for future re-enabling. The phone remains verified and can be reactivated by setting `IsSmsEnabled = 1` without requiring code re-verification.

#### Preferred Phone Selection

A user may register multiple phones but can have only one preferred phone for MFA. Setting a phone as preferred automatically clears the preferred flag on all other phones:

```
PATCH /accounts/phones/{userPhoneNumberGuid}/prefer
{ "isPreferred": true }
```

Server-side:
1. Set `IsPreferred = 1` on the target phone
2. Set `IsPreferred = 0` on all other phones for this user
3. Return the updated phone record

#### Index Strategy

Three indexes optimize the hot-path query patterns:

| Index | Columns | Filter | Rationale |
|-------|---------|--------|-----------|
| `IX_UserPhoneNumber_UserId_IsPreferred` | `(UserId, IsPreferred)` | `IsVerified = 1 AND IsSmsEnabled = 1` | Most common query: "Find user's preferred phone for MFA SMS delivery" |
| `IX_UserPhoneNumber_UserId_IsVerified` | `(UserId, IsVerified)` | None | List all verified phones for enrollment UI |
| `IX_UserPhoneNumber_IsActive` | `(IsActive)` | `IsActive = 1` | Administrative queries and cleanup jobs |

#### Verification Code Lifecycle

Verification codes are typically stored in `EmailVerificationToken` (reused from email verification flow) or in a custom `SmsVerificationCode` table. Requirements:

- Code lifetime: 5–10 minutes (project-specific)
- Code format: 6 digits (numeric; shorter codes acceptable for SMS)
- Single-use: A code is consumed on first successful match; subsequent attempts fail
- Resend: Issuing a new code invalidates the prior code immediately
- Cleanup: Nightly job soft-deletes unconsumed, expired codes

See **### Cleanup and Retention Patterns** for cleanup job design.

#### Rules

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

### Cleanup and Retention Patterns

Token tables grow unboundedly without a retention policy. Every custom token table must have an explicit cleanup strategy defined at design time.

#### Cleanup Categories

| Category | Strategy | Timing |
|----------|----------|--------|
| Expired unconsumed tokens | Soft-delete (`IsDeleted = 1`) — preserve for audit | Nightly background job |
| Expired consumed tokens | Soft-delete or hard-delete depending on retention policy | Nightly or weekly |
| Replay-tracking records | Hard-delete after configurable retention window (default 7 days) | Nightly background job |
| Rate limit hit records | Aggregate and archive; delete raw rows after 30 days | Weekly job |

#### Soft Delete vs Hard Delete

Use **soft delete** when the record has audit value (e.g., a consumed email verification token proves a user confirmed their address at a specific time).

Use **hard delete** when the record is purely operational with no audit value after expiry (e.g., an expired unconsumed `ConsumedAccessToken` entry from a token that was never replayed).

Document the choice for each table in the schema notes.

#### Cleanup Job Design

- Run as a background service (Hangfire or `IHostedService`) on a fixed schedule.
- Target the `ExpiryDateUtc` index — never do full table scans for cleanup.
- Delete in batches (e.g., 1,000 rows per execution) to avoid long-running transactions under load.
- Log the count of deleted rows per run for monitoring.
- Alert if a cleanup job fails to run for more than 24 hours — unbounded growth is a risk.

#### Standard Cleanup Schedule

| Table | Job Frequency | Target Condition |
|-------|--------------|-----------------|
| `EmailVerificationToken` | Nightly | `ExpiryDateUtc < GETUTCDATE()` AND `IsConsumed = 0` |
| `ConsumedAccessToken` | Nightly | `ExpiryDateUtc < GETUTCDATE()` |
| `RefreshToken` | Nightly | `ExpiryDate < GETUTCDATE()` AND (`IsRevoked = 1` OR `IsUsed = 1`) |
| `ConsumedResetTokens` | Nightly | `CreatedDate < GETUTCDATE() - 7 days` |

#### Rules

- **MUST** Every custom token table has a defined cleanup strategy in the schema documentation before the table is created.
- **MUST** Cleanup jobs target indexed columns — never full table scans.
- **MUST** Cleanup jobs are monitored. A failing or missing cleanup job must trigger an alert.
- **SHOULD** Batch delete size is configurable (default 1,000 rows). Adjust based on table growth rate and maintenance window constraints.
- **SHOULD** Soft-deleted records are excluded from all application queries via `WHERE IsDeleted = 0` in stored procedures. Hard-deleted records do not need this filter.

### Composite Index Rationale

Composite indexes are non-obvious — the column order matters, and a wrong order produces an index that is unused or only partially useful. Document the rationale for every composite index in the schema notes.

#### Column Order Principle

Place columns in this order, left to right:

1. **Equality predicates first** — columns used in `WHERE col = value` (highest selectivity goes first within this group).
2. **Range predicates second** — columns used in `WHERE col > value` or `WHERE col BETWEEN`.
3. **Include columns last** — columns returned by the query but not filtered on (use the `INCLUDE` clause, not key columns, for these).

#### Auth-Table Composite Index Rationale

| Index | Column Order | Rationale |
|-------|-------------|-----------|
| `IX_UserSolutionCredential_UserIdSolutionId` | `UserId`, `RegisteredSolutionId` | `UserId` has higher selectivity than `SolutionId` (one user, many solutions is rare in practice; but the user filter eliminates the most rows). Both are equality predicates. |
| `IX_RefreshToken_UserIdIsRevokedIsUsed` | `UserId`, `IsRevoked`, `IsUsed` | User filter first (equality, high selectivity); bit-flag filters follow to narrow within the user's token set. |
| `IX_RefreshToken_DeviceFingerprintUserId` | `DeviceFingerprint`, `UserId` | Device fingerprint first — the query pattern is "find all tokens for this device" not "find all tokens for this user on this device". |
| `IX_API_RateLimitPolicy_SolutionEndpoint` | `RegisteredSolutionId`, `EndpointName` | Solution first — the lookup pattern is always "for this solution, what is the policy for this endpoint?" |

#### When to Use a Filtered Index Instead

Prefer a filtered index (`WHERE` clause) over a composite index when:
- The query always filters on a fixed boolean condition (e.g., `IsActive = 1`, `IsConsumed = 0`).
- The qualifying subset is a small fraction of the total rows.
- The base table is large and the unfiltered rows would pollute the index with rarely-queried data.

A filtered index is smaller, faster to maintain, and often produces better query plans than a composite index on the same columns without the filter.

#### Rules

- **MUST** Every composite index includes a comment in the migration script explaining the column order and the query it supports.
- **MUST** Composite indexes are verified against the actual query patterns in stored procedures after implementation — not assumed to be correct from the design.
- **SHOULD** Prefer a filtered index over a full-table composite index when the qualifying condition is a fixed boolean and the qualifying row fraction is small (< 20%).

### CHANGELOG — Chapter 7

| Version | Date | Change | Source |
|---------|------|--------|--------|
| 1.11 | 2026-05-19 | Added `### Authentication-Critical Index Strategy` — standard auth index set, filtered indexes, composite indexes | Migrated from VegaIdentity RF, Critical Gap 6 |
| 1.11 | 2026-05-19 | Added `### Custom Token-Table Patterns` — decision tree for framework vs. custom tables, examples by category | Migrated from VegaIdentity RF, Blocking Decision OQ-8 |
| 1.11 | 2026-05-19 | Added `### Cleanup and Retention Patterns` — nightly job design, soft vs. hard delete guidance, standard cleanup schedule | Migrated from VegaIdentity RF, Critical Gap 1 + Architecture |
| 1.11 | 2026-05-19 | Added `### Composite Index Rationale` — column order principle, auth-table examples, filtered index preference guidance | Migrated from VegaIdentity RF, Critical Gap 6 |
| 1.12 | 2026-05-21 | Added `### Phone Number Data Management` — schema, verification lifecycle, MFA integration, endpoint patterns, index strategy | Migrated from VegaIdentity Review Findings, Section 2.85 (SMS Integration) |

---

## Chapter 8 — Data Access Patterns

All database access follows one consistent pattern. Ad-hoc queries scattered across controllers, Blazor components, or service classes are not acceptable. Every data operation flows through a defined data access class or repository.

### Central DataAccess Class (Blazor-Direct Pattern)

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

### Repository Interface (API Pattern)

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

#### Repository Implementation — Stored Procedure Calls

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

### Data Access Rules

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

---

## Chapter 9 — DTO & Contract Library

The `{AppName}.Contracts` library is the formal boundary between the API and all consumers. Domain entities never cross the HTTP boundary; they are always mapped to and from DTOs before leaving or entering the API.

### Why a Separate Contracts Library

| Without Contracts Library | With Contracts Library |
|---------------------------|------------------------|
| Domain changes break website and mobile simultaneously | Domain can change internally without affecting consumers until DTOs are explicitly updated |
| EF Core navigation properties serialize as circular JSON | DTOs contain only the fields needed; no accidental over-serialization |
| MAUI cannot reference Domain due to web framework dependencies | MAUI references only Contracts — pure .NET, no web packages required |
| Swagger schema polluted with EF Core internal attributes | Clean OpenAPI schema generated from DTO shapes only |

### DTO Rules

- **MUST** Every endpoint has a dedicated request DTO and response DTO. Do not reuse the same DTO for both reads and writes.
- **MUST** Response DTOs expose the entity `Guid`, never the integer `Id`. Integer PKs must not appear in any API response or client-facing URL.
- **MUST** Request DTOs carry all validation attributes so validation can be applied identically on the API server and in a MAUI client.
- **MUST** DTOs never contain EF Core attributes, navigation properties, or `DbContext` references.
- **SHOULD** Name patterns: `Create{Entity}RequestDto`, `Update{Entity}RequestDto`, `{Entity}ResponseDto`, `{Entity}SummaryDto` (for list items).
- **SHOULD** Flatten nested data into response DTOs rather than nesting DTOs. Simplifies mobile data binding.
- **MAY** Use a generic `PagedResultDto<T>` wrapper for paginated list endpoints: `{ Items, TotalCount, PageNumber, PageSize }`.

### Example DTO Pair

```csharp
// Contracts/Requests/Coins/CreateCoinRequestDto.cs
public class CreateCoinRequestDto
{
    [Required][MaxLength(255)]
    public string Name { get; set; } = string.Empty;
    [Required]
    public CurrencyCode Currency { get; set; }
    [Range(1800, 2100)]
    public int YearMinted { get; set; }
}

// Contracts/Responses/Coins/CoinResponseDto.cs
public class CoinResponseDto
{
    public Guid      CoinGuid     { get; set; }   // GUID, never the int Id
    public string    Name         { get; set; } = string.Empty;
    public string    CurrencyCode { get; set; } = string.Empty;
    public int       YearMinted   { get; set; }
    public DateTime? CreatedDate  { get; set; }
}
```

### Mapping (Entity ↔ DTO)

All mapping lives in `{AppName}.API/Mapping/`. Use extension methods for small projects, AutoMapper profiles for large ones.

```csharp
// API/Mapping/CoinMappingExtensions.cs
public static class CoinMappingExtensions
{
    public static CoinResponseDto ToResponseDto(this Coin coin) => new()
    {
        CoinGuid     = coin.Guid,
        Name         = coin.Name ?? string.Empty,
        CurrencyCode = coin.Currency.ToString(),
        YearMinted   = coin.YearMinted,
        CreatedDate  = coin.CreatedDate
    };
}
```

---

## Chapter 10 — API Design & Response Envelope

The API is the single point of truth for all data operations. Its design must be consistent, predictable, and stable enough that a mobile developer building against it does not need to ask questions about what a response will contain.

The foundational design decision for this API is a **standard response envelope**. Every endpoint — without exception — returns the same outer shape. The HTTP status code communicates only the infrastructure-level outcome (auth failure, server crash, bad request shape). The *business* outcome — success, not found, validation failure, no data — is communicated entirely through the envelope. This means a `404 Not Found` HTTP response is never returned by any application endpoint. A missing resource is a *business outcome*, not an HTTP error.

### Standard Response Envelope

The `ApiResponse<T>` class and its companion enum live in the `{AppName}.Contracts` library so that the API, the Blazor website, and the MAUI app all share the exact same wrapper type — just as a typed client generated from the OpenAPI spec would expect.

> **ℹ️ Design origin:** This pattern is a modern, generic C# evolution of the typed service-result wrappers used in earlier Vega Discoveries projects. The core idea — a metadata envelope carrying request context, response metadata, an outcome status, and a single typed data property — is preserved and refined here for REST/JSON APIs.

#### ApiResultStatus Enum

```csharp
// {AppName}.Contracts/Responses/ApiResultStatus.cs
namespace {AppName}.Contracts.Responses;

public enum ApiResultStatus
{
    Unknown          = 0,  // default / uninitialised — should never be returned
    Success          = 1,  // data was found and is in Data
    Failure          = 2,  // a server-side operation failed
    ValidationFailed = 3,  // the request was structurally valid but failed business rules
    NoDataFound      = 4,  // request was valid; resource simply does not exist
    Unauthorized     = 5   // access denied by a role check performed inside the service or
                           // repository layer — not by middleware. The caller was fully
                           // authenticated and reached the controller, but their application
                           // role does not permit access to this specific record or operation.
                           // This acts as a defence-in-depth guard for cases where the
                           // calling application did not pre-check roles before requesting.
}
```

#### ApiResponse\<T\> Wrapper Class

```csharp
// {AppName}.Contracts/Responses/ApiResponse.cs
namespace {AppName}.Contracts.Responses;

public class ApiResponse<T>
{
    // ── Outcome ───────────────────────────────────────────────────────────────

    /// Status of the operation. Callers must check this, not the HTTP code,
    /// to determine whether usable data was returned.
    public ApiResultStatus Status { get; init; } = ApiResultStatus.Unknown;

    /// True when Status == Success and Data is not null.
    public bool IsSuccess => Status == ApiResultStatus.Success;

    /// True when data was returned. Callers may check this before accessing Data.
    public bool HasData => Data is not null;

    // ── The payload — exactly ONE typed property ──────────────────────────────

    /// The response payload. Null when Status is NoDataFound, Failure, or
    /// ValidationFailed. Always check HasData or Status before accessing.
    public T? Data { get; init; }

    // ── Request context — what was asked ──────────────────────────────────────

    /// The endpoint that produced this response, e.g. "GET /api/v1/coins/{coinGuid}".
    public string Endpoint { get; init; } = string.Empty;

    /// The key parameters that were passed with the request.
    /// Allows the consumer to confirm which record was queried without re-parsing the URL.
    public IReadOnlyDictionary<string, string> RequestKeys { get; init; }
        = new Dictionary<string, string>();

    // ── Response metadata — what happened ─────────────────────────────────────

    /// UTC timestamp of when this response was generated.
    public DateTime ResponseUtc { get; init; } = DateTime.UtcNow;

    /// Correlates this response to the server-side log entry. Include in support tickets.
    public string TraceId { get; init; } = string.Empty;

    /// Human-readable summary of the outcome, safe to display to end users.
    public string? Message { get; init; }

    /// Additional detail about a failure or validation error.
    /// Populated only when Status is Failure or ValidationFailed.
    public string? ErrorDetail { get; init; }

    /// Number of records in Data. 0 when no data was returned.
    /// For single-item responses this is 1 on success and 0 otherwise.
    public int RecordCount { get; init; }
}
```

#### ApiResponse Factory (Static Helper)

All controllers create envelope instances through the factory. This prevents inconsistent field population and ensures `Endpoint`, `TraceId`, and `ResponseUtc` are never accidentally omitted.

```csharp
// {AppName}.API/Mapping/ApiResponseFactory.cs
namespace {AppName}.API.Mapping;

public static class ApiResponseFactory
{
    public static ApiResponse<T> Success<T>(T data, string endpoint,
        IReadOnlyDictionary<string, string> requestKeys, string traceId,
        int recordCount = 1) => new()
    {
        Status      = ApiResultStatus.Success,
        Data        = data,
        Endpoint    = endpoint,
        RequestKeys = requestKeys,
        TraceId     = traceId,
        RecordCount = recordCount,
        Message     = "Success"
    };

    public static ApiResponse<T> NoDataFound<T>(string endpoint,
        IReadOnlyDictionary<string, string> requestKeys, string traceId) => new()
    {
        Status      = ApiResultStatus.NoDataFound,
        Data        = default,
        Endpoint    = endpoint,
        RequestKeys = requestKeys,
        TraceId     = traceId,
        RecordCount = 0,
        Message     = "The requested resource was not found."
    };

    public static ApiResponse<T> Failure<T>(string message, string errorDetail,
        string endpoint, IReadOnlyDictionary<string, string> requestKeys,
        string traceId) => new()
    {
        Status      = ApiResultStatus.Failure,
        Endpoint    = endpoint,
        RequestKeys = requestKeys,
        TraceId     = traceId,
        RecordCount = 0,
        Message     = message,
        ErrorDetail = errorDetail
    };

    public static ApiResponse<T> ValidationFailed<T>(string detail, string endpoint,
        IReadOnlyDictionary<string, string> requestKeys, string traceId) => new()
    {
        Status      = ApiResultStatus.ValidationFailed,
        Endpoint    = endpoint,
        RequestKeys = requestKeys,
        TraceId     = traceId,
        RecordCount = 0,
        Message     = "The request could not be completed due to a validation error.",
        ErrorDetail = detail
    };

    // Raised when the service or repository layer determines that the authenticated
    // caller's application role does not permit access to the requested data.
    // This is never the result of a middleware decision; HTTP always returns 200.
    public static ApiResponse<T> Unauthorized<T>(string message, string endpoint,
        IReadOnlyDictionary<string, string> requestKeys, string traceId) => new()
    {
        Status      = ApiResultStatus.Unauthorized,
        Endpoint    = endpoint,
        RequestKeys = requestKeys,
        TraceId     = traceId,
        RecordCount = 0,
        Message     = message,
        ErrorDetail = "Your application role does not permit access to this resource."
    };
}
```

### Controller Structure

Every action method returns `Ok(ApiResponseFactory.{Method}(...))`. The HTTP status code is always `200 OK` for every business outcome. Non-200 codes are reserved exclusively for infrastructure failures that occur *before* the controller body executes.

```csharp
[ApiController]
[Route("api/v{version:apiVersion}/[controller]")]
[ApiVersion("1.0")]
[Authorize]
public class CoinsController(ICoinRepository coinRepository,
                              ILogger<CoinsController> logger) : ControllerBase
{
    private const string EndpointGetCoin = "GET /api/v1/coins/{coinGuid}";

    [HttpGet("{coinGuid:guid}")]
    public async Task<IActionResult> GetCoinAsync(Guid coinGuid)
    {
        var requestKeys = new Dictionary<string, string>
            { ["coinGuid"] = coinGuid.ToString() };

        var requestedCoin = await coinRepository.GetByGuidAsync(coinGuid);

        if (requestedCoin is null)
            return Ok(ApiResponseFactory.NoDataFound<CoinResponseDto>(
                EndpointGetCoin, requestKeys, HttpContext.TraceIdentifier));

        return Ok(ApiResponseFactory.Success(
            requestedCoin.ToResponseDto(),
            EndpointGetCoin, requestKeys, HttpContext.TraceIdentifier));
    }
}
```

#### What the Consumer Receives (Example JSON)

```json
// Coin found — Status: Success
{
  "status":       "Success",
  "isSuccess":    true,
  "hasData":      true,
  "data":         { "coinGuid": "3fa85f64...", "name": "1921 Morgan Dollar", ... },
  "endpoint":     "GET /api/v1/coins/{coinGuid}",
  "requestKeys":  { "coinGuid": "3fa85f64..." },
  "responseUtc":  "2026-03-13T14:22:01Z",
  "traceId":      "0HN8K2V5VQE4G:00000001",
  "message":      "Success",
  "errorDetail":  null,
  "recordCount":  1
}

// Coin not found — Status: NoDataFound  (HTTP is still 200 OK)
{
  "status":       "NoDataFound",
  "isSuccess":    false,
  "hasData":      false,
  "data":         null,
  "endpoint":     "GET /api/v1/coins/{coinGuid}",
  "requestKeys":  { "coinGuid": "3fa85f64..." },
  "responseUtc":  "2026-03-13T14:22:01Z",
  "traceId":      "0HN8K2V5VQE4G:00000002",
  "message":      "The requested resource was not found.",
  "errorDetail":  null,
  "recordCount":  0
}
```

### HTTP Status Code Conventions

With the response envelope in place, HTTP status codes revert to their original purpose: describing the *transport and infrastructure* outcome, not the business outcome.

| Scenario | HTTP Code | Envelope `Status` | Notes |
|----------|-----------|-------------------|-------|
| Resource found | 200 OK | `Success` | Data payload is populated, RecordCount ≥ 1 |
| Resource not found | 200 OK | `NoDataFound` | Data is null, RecordCount = 0. **Never 404.** |
| Collection, results exist | 200 OK | `Success` | Data is the list, RecordCount = N |
| Collection, no results | 200 OK | `NoDataFound` | Data is null or empty list, RecordCount = 0. **Never 404.** |
| Create succeeded | 201 Created | `Success` | Include `Location` header with the new resource GUID URL |
| Update / delete succeeded | 200 OK | `Success` | Data contains the updated resource or confirmation |
| Business rule violated | 200 OK | `ValidationFailed` | ErrorDetail describes the rule. Distinct from HTTP 400 (model binding). |
| Data-level access denied | 200 OK | `Unauthorized` | The caller's application role was checked inside the service or repository layer — not by middleware — and does not permit this record or operation. HTTP remains 200. Distinct from HTTP 403, which fires before the controller body runs. |
| Server-side error | 200 OK | `Failure` | Message is user-safe. ErrorDetail contains the TraceId for log lookup. |
| Model binding / bad JSON | 400 Bad Request | N/A — envelope not reached | ASP.NET Core model validation fires before the controller body runs |
| Not authenticated | 401 Unauthorized | N/A — envelope not reached | JWT middleware fires before the controller body runs |
| Not authorised | 403 Forbidden | N/A — envelope not reached | Authorisation policy fires before the controller body runs |
| Unhandled exception | 500 | N/A — envelope not reached | Global exception middleware returns generic message + TraceId (see Chapter 15) |

> **⚠️ Two kinds of "not authorised" — they are not the same thing:** HTTP `401` and `403` are emitted by ASP.NET Core middleware *before* the controller body executes and therefore never produce an envelope. `ApiResultStatus.Unauthorized` is produced *inside* the controller body, by the service or repository layer, when a data-level role check fails; it always travels inside a `200 OK` envelope. Consumers must handle both shapes: envelope-based outcomes for all `200` responses and raw HTTP error codes for infrastructure failures. Document this distinction explicitly in the OpenAPI spec description for every endpoint.

### HTTP Response Code Rules — Auth Endpoints

The following table specifies the exact HTTP codes for all identity and account management endpoints (e.g., `/auth/*`, `/accounts/*`). This follows the envelope pattern where HTTP codes communicate transport-level outcomes; business outcomes are communicated entirely via the envelope.

| Outcome | HTTP Code | Envelope Status | Scenario | Notes |
|---------|-----------|-----------------|----------|-------|
| ✅ Success | **200 OK** | `Success` | Register, login, refresh, logout, password reset, email change, account query | Envelope contains response data (tokens, account details, etc.) |
| ❌ Business rule violation | **200 OK** | `ValidationFailed` | Age < 16, email already registered, password too weak, lockout active | Not a request format error; HTTP 400 is not used |
| ❌ Resource not found | **200 OK** | `NoDataFound` | Account lookup returns no results | Resource missing is a business outcome, not HTTP error |
| ❌ Server operation failed | **200 OK** | `Failure` | Database write error, email service unavailable (non-critical), unexpected condition | Recoverable error; full details logged server-side; user-safe message in envelope |
| ❌ Access denied (data-level) | **200 OK** | `Unauthorized` | User's role checked inside service layer and lacks permission for this record/operation | Distinct from middleware 403; authenticated but not authorized for this data |
| 🚫 Bad request format | **400 Bad Request** | N/A — envelope not reached | Invalid JSON, missing required field, type mismatch | ASP.NET Core model binding validates before controller body executes |
| 🚫 Not authenticated | **401 Unauthorized** | N/A — envelope not reached | Missing or invalid JWT bearer token | JWT middleware validates before controller body executes |
| 🚫 Not authorised (middleware) | **403 Forbidden** | N/A — envelope not reached | `[Authorize(Policy="...")]` policy fails before controller body executes | Distinct from data-level `Unauthorized` in envelope |
| 🚫 Rate limit exceeded | **429 Too Many Requests** | N/A — envelope not reached | Login, register, or refresh attempts exceed per-endpoint threshold | Include `Retry-After` header with seconds until next attempt |
| 🚫 Server error | **500 Internal Server Error** | N/A — envelope not reached | Unhandled exception in middleware or controller | Global exception middleware catches and logs with TraceId |

**Key Rule:** All authentication and account endpoints return **200 OK for all business outcomes** (success, validation failure, access denied at data level, resource not found). The envelope status field communicates the outcome to the caller. HTTP codes communicate *infrastructure* outcomes only (request format, authentication, authorization policy, rate limit, server crash).

### API Design Rules

- **MUST** Every controller action returns `Ok(ApiResponseFactory.{Method}(...))`. Never return `NotFound()`, `NoContent()`, or a raw DTO directly from a controller action. The envelope is the contract.
- **MUST** `ApiResponse<T>` and `ApiResultStatus` live in `{AppName}.Contracts/Responses/`. They must have zero dependencies on `Microsoft.AspNetCore.*` so that MAUI can consume them without a web framework reference.
- **MUST** `ApiResponseFactory` lives in `{AppName}.API/Mapping/` and is the only permitted way to construct `ApiResponse<T>` instances in controller code.
- **MUST** `RequestKeys` must include every route parameter and significant query parameter so that the consumer can confirm exactly which resource was queried without re-parsing the URL.
- **MUST** Route parameters use the GUID: `/api/v1/coins/{coinGuid}`. Never expose integer IDs in routes or in `RequestKeys`.
- **MUST** Never return the domain entity directly. Always map to a response DTO, then wrap in the envelope.
- **MUST** Service and repository methods that return role-restricted data must evaluate the caller's application role internally. When access is denied at the data level, they must surface this so the controller calls `ApiResponseFactory.Unauthorized`. The data layer must never assume the calling application pre-checked roles — this is a required defence-in-depth guard.
- **SHOULD** For paginated list endpoints, wrap results in `PagedResultDto<T>`.
- **SHOULD** Mark public endpoints with `[AllowAnonymous]` explicitly rather than relying on the absence of `[Authorize]`.
- **SHOULD** Enable CORS explicitly with named origins. Never use wildcard (`*`) origins in production.
- **SHOULD** Include the endpoint string constant (e.g., `private const string EndpointGetCoin = "GET /api/v1/coins/{coinGuid}"`) as a `private const` at the top of each controller class to avoid magic strings in every action method.

---

## Chapter 11 — Website — Blazor

The website is a **Blazor Web App** targeting .NET 10. All new projects use Blazor for the frontend. MVC controller patterns are reserved for the API project only.

### Page Base Classes

```csharp
// Components/Support/PageBase.cs — all public pages inherit this
public class PageBase : ComponentBase
{
    protected Exception? Error { get; set; }
    protected bool ShowStackTrace { get; set; }
    [Inject] public UserManager<AppUser>? UserManager { get; set; }
    [Inject] public NavigationManager? NavigationManager { get; set; }
}

// Components/Support/SecurePageBase.cs — all authenticated pages inherit this
public class SecurePageBase : ComponentBase
{
    [Inject] public NavigationManager? NavigationManager { get; set; }
    protected Exception? Error { get; set; }
    protected bool ShowStackTrace { get; set; }
}
```

### Blazor Rules

- **MUST** All authenticated pages declare `@attribute [Authorize]` and inherit from `SecurePageBase`.
- **MUST** Role names are referenced via `RoleDefs` constants. No inline role string literals.
- **MUST** Never place data access logic directly in a `.razor` file. Use the `DataAccess` class or an injected service.
- **SHOULD** If a component's `@code` block exceeds ~60 lines, extract a code-behind `.razor.cs` partial class.
- **SHOULD** Use `StringExtensions` and `SessionExtensions` from `Support/Extensions/` rather than duplicating logic inline.
- **SHOULD** Group pages by access level: `Pages/Public/` and `Pages/Secure/`.

### Responsive Layout

> **Addition — 2026-08-11:** Added after a review of an existing SDP-built site found no
> requirement anywhere in this document that customer-facing pages render correctly across
> device sizes.

Every customer-facing page — public marketing/portfolio pages as much as authenticated app
pages — must render correctly across desktop, tablet, and phone viewports.

- **MUST** Every page includes the standard responsive viewport meta tag
  (`<meta name="viewport" content="width=device-width, initial-scale=1" />`) in the shared
  page layout's `<head>` (this stack's Blazor Web App: `App.razor`) — never overridden
  per-page.
- **MUST** Layout and navigation use CSS Flexbox/Grid with relative units (`%`, `rem`, `fr`,
  `vw`/`vh`) and at minimum a mobile breakpoint (~≤480px) and a tablet breakpoint
  (~481–1024px) in addition to the desktop layout. Fixed pixel-width containers that do not
  reflow below desktop width are not acceptable for customer-facing pages.
- **MUST** Primary navigation collapses to a mobile-appropriate pattern (hamburger/off-canvas
  menu or equivalent) below the tablet breakpoint rather than truncating or overflowing.
- **SHOULD** Verify each new or changed customer-facing page at three reference widths — phone
  (~375px), tablet (~768px), desktop (~1440px) — before marking the task complete; for
  `[VERIFY DURING IMPLEMENTATION]`-flagged UI tasks, note the widths checked in the Completed
  blockquote.
- **SHOULD** Prefer CSS-only responsive behavior (media queries, container queries) over
  JavaScript-driven layout switching, to keep behavior predictable and testable.
- **MAY** Use a component library's built-in responsive grid (e.g. Bootstrap, MudBlazor) in
  place of hand-rolled Flexbox/Grid, provided its breakpoints are not overridden in a way that
  defeats the MUST rules above.

### Dynamic Content Collections

> **Addition — 2026-08-13:** Concrete Website instantiation of Chapter 13's "Data-Driven Content —
> Preferred Default" rule. Added after a real incident where a version-history page's milestone
> list had no data source separate from the page markup rendering it.

Any structured, repeating content collection rendered on a page — version-history/changelog
entries, FAQ items, testimonials, portfolio or pricing entries — is sourced from a typed content
file under `Content/` (see Chapter 3), not hand-authored in the `.razor` markup.

```csharp
// Content/VersionHistoryEntry.cs
public record VersionHistoryEntry(string Version, DateOnly Date, string Description);

// Support/ContentService.cs
public class ContentService(IWebHostEnvironment env)
{
    public async Task<IReadOnlyList<T>> LoadAsync<T>(string contentFileName)
    {
        var path = Path.Combine(env.ContentRootPath, "Content", contentFileName);
        await using var stream = File.OpenRead(path);
        return await JsonSerializer.DeserializeAsync<List<T>>(stream) ?? [];
    }
}
```

```json
// Content/version-history.json
[
  { "version": "1.1.0", "date": "2026-08-11", "description": "..." }
]
```

- **MUST** Structured content collections live under `Content/` at the project root, one JSON file
  per collection, deserialized into a strongly-typed record via an injected content-loading
  service.
- **MUST** Pages consume content through the content-loading service — never by reading the file
  directly or embedding the values inline.
- **SHOULD** Name the content file after the collection it backs (`version-history.json`,
  `faq.json`) so a content update can be located without a codebase search.
- **MAY** Cache a loaded content file's deserialized result for the process lifetime when the
  backing page is read frequently and the file only changes on deploy.

---

## Chapter 12 — Mobile Readiness

Every Phase 1 decision either helps or hinders the Phase 2 mobile rollout. The rules here ensure adding a MAUI app later requires only new code — not changed architecture.

### Phase 1 Actions That Enable Mobile

| Action | Why It Matters for Mobile |
|--------|--------------------------|
| JWT bearer tokens (not cookies) | Mobile apps cannot use browser cookies. JWT works identically on iOS, Android, and web. |
| `Contracts` free of web dependencies | MAUI must reference `Contracts` directly. One `AspNetCore` package reference blocks this entirely. |
| Expose GUID not integer ID in API responses | Integer IDs leak DB implementation details. GUIDs are safe in mobile deep links and push notification payloads. |
| OpenAPI spec generated on every build | Enables Kiota/NSwag to generate a typed C# HTTP client for MAUI with one command. |
| `app.UseHttpsRedirection()` | iOS ATS and Android NSC block plain HTTP in production by default. |
| Localization via route culture provider | Mobile device locale maps directly to the API route culture segment. |

### Phase 2 — Generating the Mobile API Client

```bash
kiota generate -l CSharp -d docs/openapi.json \
  -o {AppName}.MAUI/ApiClient \
  -n {AppName}.MAUI.ApiClient
```

### Secure Token Storage (MAUI)

```csharp
// Uses iOS Keychain / Android Keystore / Windows DPAPI automatically
await SecureStorage.Default.SetAsync("refresh_token", newRefreshToken);
var storedRefreshToken = await SecureStorage.Default.GetAsync("refresh_token");
```

- **MUST** Never store JWT tokens in `Preferences` or plain text files. Use `SecureStorage` exclusively.
- **MUST** MAUI references only `{AppName}.Contracts`. Never `Domain` or `API`.
- **SHOULD** Handle `401 Unauthorized` globally in the HTTP client by attempting a silent token refresh before showing a login prompt.
- **SHOULD** Test localization using device locale settings on both iOS Simulator and Android Virtual Device before release.

### Adaptive Layout (MAUI UI)

> **Addition — 2026-08-11:** The rest of this chapter prepares the API/contracts layer for a
> future MAUI app; it does not address whether the MAUI app's own UI adapts across phone,
> tablet, and orientation. This subsection closes that gap.

Every MAUI page must render correctly on phone and tablet form factors, in both portrait and
landscape.

- **MUST** Layouts use adaptive sizing primitives (`Grid`/`FlexLayout` with proportional
  (`*`/`Auto`) sizing, `OnIdiom`/`OnPlatform` markup extensions, or
  `VisualStateManager`/`AdaptiveTrigger`) rather than fixed pixel dimensions.
- **MUST** Verify each new or changed page on at least one phone-class and one tablet-class
  screen profile, in both portrait and landscape, before marking the task complete; for
  `[VERIFY DURING IMPLEMENTATION]`-flagged UI tasks, note the profiles checked in the Completed
  blockquote.
- **SHOULD** Prefer declarative XAML sizing (Grid ratios, `HorizontalOptions="FillAndExpand"`,
  etc.) over manual `OnSizeAllocated`/pixel-math layout logic.
- **SHOULD** Verify orientation-change behavior doesn't clip or truncate content.
- **MAY** Use a UI toolkit's adaptive-layout component (e.g. .NET MAUI Community Toolkit,
  Syncfusion, Telerik) in place of hand-rolled adaptive layout, provided it doesn't override
  the platform's own size-class behavior in a way that defeats the MUST rules above.

### Dynamic Content Delivery

> **Addition — 2026-08-13:** Concrete MAUI instantiation of Chapter 13's "Data-Driven Content —
> Preferred Default" rule, split by target — mobile and desktop do not share one delivery model
> for content that changes independently of app releases.

**Mobile (`Platforms/iOS/`, `Platforms/Android/`):** structured, independently-changing content
(version-history/changelog entries, announcements, and similar) is fetched through a dedicated
`{AppName}.API` endpoint and DTO (Chapter 9), consumed via the client's existing typed HTTP
client — never bundled as a local data file in the app package. A bundled file only updates on the
next store release; every user must install that update before seeing new content. This reinforces
the "pure API consumer" rule above rather than adding an exception to it.

**Desktop (`Platforms/Windows/`, `Platforms/MacCatalyst/`):** not store-review-gated the same way
— a desktop client may read and write local files as part of ordinary runtime operation. A local
content file is acceptable, in two forms: bundled with the app at install, for content that
changes at the app's own release cadence; or written/refreshed by the app itself at runtime as a
local cache synced from `{AppName}.API`, which gives desktop live-updatable content without
needing a full app update. Prefer the runtime-synced-cache form for content whose source of truth
is shared with other clients (e.g. the same version-history list mobile and Website both show), so
every client reads from one authoritative source; reserve the bundled-at-install form for content
that is genuinely desktop-specific.

- **MUST** Mobile targets source independently-changing structured content through the API —
  never a bundled local file — except content that shares the app's own release cadence
  (Chapter 13).
- **SHOULD** Desktop targets source the same centrally-authored content through an API-synced
  local cache rather than a bundled-at-install file, to keep desktop and mobile reading from one
  source of truth.
- **MAY** Desktop targets use a purely bundled local file for content that is genuinely
  desktop-specific and tied to the app's own release cadence.

---

## Chapter 13 — Coding Standards

Consistent code style reduces cognitive overhead when reading unfamiliar code. Every rule applies uniformly across all projects. When in doubt, choose clarity over brevity.

### Naming Conventions

| Symbol | Convention | Example |
|--------|------------|---------|
| Class | PascalCase | `CoinRepository`, `AuthService` |
| Interface | PascalCase, `I` prefix | `ICoinRepository`, `IAuthService` |
| Public property | PascalCase | `CoinGuid`, `YearMinted`, `IsActive` |
| Public method | PascalCase, verb-first | `GetCoinByGuidAsync`, `SoftDeleteAsync` |
| Private field | camelCase, `_` prefix | `_dbContext`, `_logger`, `_coinRepository` |
| Local variable | camelCase, verbose | `requestedCoin`, `userDisplayName`, `refreshTokenExpiry` |
| Method parameter | camelCase, verbose | `coinGuid`, `deletedByUser`, `pageNumber` |
| Constant | PascalCase | `MaxPageSize`, `DefaultSortOrder` |
| Enum type | PascalCase, singular | `CurrencyCode`, `TransactionType` |
| Async method | PascalCase, `Async` suffix | `GetAllCoinsAsync`, `SaveChangesAsync` |

### Verbose, Descriptive Names

Names must communicate intent without requiring the reader to look at the implementation. Single-letter names, abbreviations, and vague names like `tmp`, `obj`, `val`, or `str` are not acceptable.

```csharp
// ❌ Avoid — forces the reader to mentally decode the name
var r = await repo.Get(id);
bool f = r != null;

// ✅ Preferred — intent is immediately clear
var requestedCoin = await coinRepository.GetByGuidAsync(coinGuid);
bool coinWasFound = requestedCoin is not null;
```

### Async / Await

- **MUST** Every I/O-bound operation is `async`/`await` across all project tiers. Never use `.Result`, `.Wait()`, or `.GetAwaiter().GetResult()`.
- **MUST** Every `async` method name ends with `Async`.
- **MUST** Return `Task`, never `void`, from `async` methods. `async void` is permitted only for Blazor event handlers.
- **SHOULD** Pass `CancellationToken` through the full call stack for long-running or HTTP-triggered operations.

### Comments & Documentation

- **MUST** Do not add comments that restate what the code already says. `// increment the counter` above `counter++` adds no value.
- **MUST** Use `// TODO: description` (Visual Studio Task List) for known incomplete work. Never leave `// REMEMBER!!!` style comments in committed code.
- **SHOULD** Add XML doc comments to all public API controller actions, service interface members, and all `Contracts` library members.
- **SHOULD** Comment genuinely complex logic: business rules, state machines, and cryptographic operations.

### General Code Style

- **MUST** Use `var` when the type is obvious from the right-hand side. Use explicit types when it is not.
- **MUST** Use `string.IsNullOrWhiteSpace()` rather than `== null || == ""`.
- **MUST** Enable nullable reference types in all new projects and treat nullable warnings as errors in CI builds.
- **SHOULD** Use pattern matching (`is not null`, switch expressions) over `if/else` chains for null checks.
- **SHOULD** Return `IReadOnlyList<T>` or `IEnumerable<T>` from public APIs over `List<T>` to prevent unintended external mutation.
- **MAY** Use primary constructors (C# 12) for DI-heavy classes to reduce constructor boilerplate.

### String Externalization — Resource Files

All user-facing strings must be stored in `.resx` resource files. Embedding string literals directly in service or controller code is not permitted.

**Rationale:** Literal strings scattered across service and controller code cannot be audited, are duplicated silently, and make future localization a full-codebase rewrite. Resource files give one authoritative location per message and generate a strongly-typed accessor class at build time.

> **Addition — 2026-07-23 — Code vs. data-file distinction:** The distinction drawn above
> generalizes beyond resource files: a file is evaluated as *code* or *data* by whether it
> contains executable logic, not by its physical location in the project or its role in the
> build. A `.resx` file participates in compilation (it generates a `*.Designer.cs` accessor) and
> is still a data file, because it contains no executable logic. The same test applies to
> `appsettings.json`/`appsettings.*.json` and any other JSON, XML, or YAML configuration file. See
> Chapter 4 (Versioning Strategy) and Chapter 14 (Configuration & Secrets) for two rules this
> distinction resolves directly.

#### File Location and Naming

Each project that surfaces strings to users owns one resource file per logical domain, placed in a `Resources/` folder at the project root.

| Project | Resource File | Generated Class |
|---------|--------------|-----------------|
| `VegaIdentity.API` | `Resources/AuthMessages.resx` | `AuthMessages` |
| `VegaIdentity.Website` | `Resources/WebsiteMessages.resx` | `WebsiteMessages` |

Additional resource files may be added per project when a single file grows unwieldy (e.g., `AdminMessages.resx`, `AccountMessages.resx`). One file per logical domain, not one file per controller.

#### Key Naming Convention

Keys use `{Domain}_{Context}_{Description}` format in PascalCase:

```
Register_Underage
Register_AlreadyRegistered
Login_InvalidCredentials
Common_SolutionNotFound
Email_VerificationSent
```

The prefix is the feature area or shared group (`Common_` for strings used across multiple flows). Keys must be descriptive enough to locate the usage without reading the value.

#### Usage Pattern

```csharp
// ✅ Correct — strongly-typed accessor via generated designer class
using VegaIdentity.API.Resources;

throw new AuthException("UNDERAGE", AuthMessages.Register_Underage);
throw new AuthException("ALREADY_REGISTERED", AuthMessages.Register_AlreadyRegistered);

// ❌ Prohibited — literal string embedded at call site
throw new AuthException("UNDERAGE", "You must be at least 16 years old to register.");
```

#### Rules

- **MUST** Every string that appears in an API response body, exception message, or UI label originates from a resource file. No exceptions for "simple" or "temporary" messages.
- **MUST** Never define a `private const string` or `static readonly string` that duplicates a resource key. The resource file is the constant.
- **MUST** The `Resources/` folder is committed. The generated `*.Designer.cs` file is committed alongside its `.resx` source.
- **SHOULD** Group related messages under a common prefix key rather than creating a new resource file for a single additional message.
- **SHOULD** Write resource values in full, grammatical sentences with correct punctuation — these may be displayed directly to end users.
- **MAY** Define a `Common_` prefix group for error strings shared across multiple service classes within the same project.

### Data-Driven Content — Preferred Default

> **Addition — 2026-08-13:** Elevates the "Code vs. data-file distinction" Addition above from a
> single blockquote into a first-class, named rule other chapters can cross-reference. Prompted by
> a real incident: a version-history page's content list had no data source separate from the
> markup rendering it, so adding an entry required editing the page itself. See Chapter 11 and
> Chapter 12 for this rule's concrete, per-project-type instantiations.

Whenever content values change independently of the logic that renders them, source those values
from a data file — or, for a distributed client, the API — rather than embedding them in code.
This applies to every project type and rendering surface GPG governs, not only to the
string-externalization case above.

- **MUST** Structured, repeating content (a version-history/changelog list, FAQ items,
  testimonials, portfolio or pricing entries, and similar) is never hand-authored inline in a
  `.razor`, `.xaml`, `.cs`, or other executable-logic file.
- **MUST** For a server-hosted surface (`{AppName}.Website`), a bundled data file committed to the
  project and shipped with the next deploy is the default delivery mechanism — see Chapter 11.
- **MUST** For a distributed client's mobile targets (`{AppName}.MAUI`, `Platforms/iOS/` and
  `Platforms/Android/`), content that changes independently of app releases is sourced through the
  API, never bundled as a local file in the app package — see Chapter 12.
- **SHOULD** For a distributed client's desktop targets (`{AppName}.MAUI`, `Platforms/Windows/`
  and `Platforms/MacCatalyst/`), prefer a local content file the app syncs from the API at
  runtime over a purely bundled-at-install file, for content whose source of truth is shared with
  other clients — see Chapter 12.
- **SHOULD** Escalate to a database-backed content table (Chapter 17 seed-data pattern) only on a
  confirmed requirement for live, non-developer editing — do not build admin-editable content
  storage speculatively.
- **MUST** Escalate to a headless CMS or other external content service only through Material
  Decision Escalation (bootstrap doc, Architecture phase) — never a default choice.
- **MAY** Keep content that shares its host app's own release cadence and needs no update between
  releases (fixed onboarding copy, bundled legal text for offline access) in a bundled data file
  even on a mobile target — the MUST rules above target content whose value is *independent*
  update cadence, not literally all content.

---

## Chapter 14 — Configuration & Secrets

Configuration is layered: base `appsettings.json` holds non-sensitive defaults; environment files override them; credentials are never committed to source control under any circumstances.

### Configuration File Hierarchy

| File | Committed? | Contains |
|------|------------|----------|
| `appsettings.json` | Yes | Log levels, feature flags, pagination defaults, app name/version, supported cultures |
| `appsettings.Development.json` | Yes | Developer-friendly overrides: verbose logging, exception pages |
| `appsettings.Production.json` | Yes | Production non-sensitive overrides. No credentials. |
| User Secrets | Never | Runtime connection strings (`AppDb`, `IdentityDb`), migration connection strings (`MigrationsDb`, `MigrationsIdentityDb`), JWT secret, email credentials |
| Environment variables | N/A | CI/CD and server runtime secrets. Override any `appsettings` value. |
| Key Vault / Secrets Manager | N/A | Production-grade secret store for hosted environments |

### Strongly-Typed Configuration

```csharp
// Program.cs — bind config sections to typed classes
builder.Services.Configure<JwtConfig>(builder.Configuration.GetSection("JwtConfig"));
builder.Services.Configure<DebuggingConfig>(builder.Configuration.GetSection("Debugging"));

// Usage via IOptions — never read IConfiguration by magic string in business logic
public class AuthService(IOptions<JwtConfig> jwtOptions) { ... }
```

### Configuration Rules

- **MUST** Connection strings, JWT secrets, and API keys are never in any committed file.
- **MUST** Both `.gitignore` and `.copilotignore` list all credential-containing files.
- **MUST** Use `env.IsDevelopment()` for debug-mode toggles. Never use a hardcoded `static bool DebugMode = true` field.
- **SHOULD** Validate required config on startup: `services.AddOptions<T>().ValidateDataAnnotations().ValidateOnStart()` so missing secrets fail immediately at launch.
- **MUST** Maintain four named connection strings: `ConnectionStrings:AppDb` and `ConnectionStrings:IdentityDb` (runtime, minimal permissions) and `ConnectionStrings:MigrationsDb` and `ConnectionStrings:MigrationsIdentityDb` (elevated, deploy-time only, never read by the running application). All four live in User Secrets locally; `AppDb` and `IdentityDb` are injected as environment variables in production; `MigrationsDb` and `MigrationsIdentityDb` are injected only in the CI/CD pipeline migration step and are absent from the running application's environment.

> **Addition — 2026-07-24 — Log retention setting:** The `appsettings.json` row's "Log levels"
> content extends to log retention: `Logging:RetentionDays` (or equivalent key) is a non-sensitive
> default belonging in `appsettings.json`, per Chapter 6's log rotation/retention rule.

---

## Chapter 15 — Error Handling

Errors are caught at defined boundaries, logged with full context, and returned as structured predictable responses. Raw stack traces must never reach any client in any environment.

### Global Exception Middleware

```csharp
// API/Middleware/ExceptionHandlingMiddleware.cs
public class ExceptionHandlingMiddleware(RequestDelegate next,
    ILogger<ExceptionHandlingMiddleware> logger)
{
    public async Task InvokeAsync(HttpContext httpContext)
    {
        try { await next(httpContext); }
        catch (Exception unexpectedException)
        {
            logger.LogError(unexpectedException,
                "Unhandled exception on {Method} {Path}",
                httpContext.Request.Method, httpContext.Request.Path);

            httpContext.Response.StatusCode = 500;
            await httpContext.Response.WriteAsJsonAsync(new
            {
                Error   = "An unexpected error occurred.",
                TraceId = httpContext.TraceIdentifier  // correlates to server log
            });
        }
    }
}
```

### Custom Exception Types

```csharp
// Support/Exceptions/ — map these to HTTP status codes in the middleware
public class NotFoundException(string entityName, object key)
    : Exception($"{entityName} with key {key} was not found.");

public class DomainValidationException(string message)
    : Exception(message);
```

### Blazor Error Boundaries

```razor
<ErrorBoundary>
    <ChildContent><CoinList UserId="@currentUserId" /></ChildContent>
    <ErrorContent><p>Unable to load this section. Please try again.</p></ErrorContent>
</ErrorBoundary>
```

### Error Handling Rules

- **MUST** Register `ExceptionHandlingMiddleware` as the first item in the API pipeline.
- **MUST** Never return raw exception messages or stack traces to clients in any environment. Return a generic message with a `TraceId`. **Exception:** users holding the `Dev` role may view raw error details through the Dev Toolbar — see below.
- **MUST** `ShowStackTrace` is controlled by configuration (Chapter 14). It is always `false` outside of Development.
- **MUST** Log the full exception at `Error` level before returning a sanitized response.
- **SHOULD** Map custom exception types to specific HTTP status codes in the global middleware.
- **SHOULD** Wrap independent Blazor page sections in `<ErrorBoundary>` so one component failure does not blank the entire page.

### Dev Toolbar

When the authenticated user holds the `Dev` role, the UI must render a persistent Dev Toolbar (or equivalent dev menu/panel). This toolbar is invisible to all other roles and is never rendered in any context where the current user does not have `Dev` in their active JWT claims.

**Required Dev Toolbar capabilities:**

| # | Feature | Description |
|---|---------|-------------|
| 1 | Raw Error Details | On any runtime error, displays the full exception message, exception type, and stack trace that would otherwise be suppressed. Presented in a collapsible panel or modal alongside the standard user-facing error message. |
| 2 | Request / Response Inspector | Log of the last N API calls made by this client: method, URL, HTTP status, latency (ms), and collapsible request/response body. Cleared on page reload. |
| 3 | JWT Inspector | Decoded view of the current access token: all claims, issued-at timestamp, expiry time, and a live countdown to expiry. |
| 4 | Feature Flag Override | Toggle any named feature flag on or off for this session only. Overrides do not affect other users and reset on logout. |
| 5 | Session Info | Current user ID, GUID, active roles from JWT, refresh token expiry, and solution context identifier. |
| 6 | Log Stream Viewer | Tail of recent structured server-side log entries at `Warning` level and above, filtered to TraceIds associated with this user’s requests. Requires the API to expose a scoped log query endpoint gated to the `Dev` role. |
| 7 | Performance Alerts | Highlights any API response that exceeded a configurable latency threshold (default 500 ms). Shows endpoint, duration, and timestamp. |
| 8 | State Snapshot | Dumps the current client-side application state (store / context / signal graph) to a readable, collapsible panel. Useful for diagnosing stale or unexpected UI state. |
| 9 | Network Latency Overlay | Per-request timing badge rendered on-screen for all in-flight and recently completed API calls, showing endpoint name and round-trip time. |

**Rules:**

- **MUST** The Dev Toolbar is only rendered when the JWT `role` claims include `Dev`. Never infer Dev access from any other signal.
- **MUST** The raw error detail panel must not replace the standard error message — it is additive. Non-dev users still see the sanitized message.
- **MUST** Raw error data is never written to the DOM in a way that is accessible to non-dev users (no hidden fields, no HTML comments).
- **SHOULD** The API may optionally include an extended error payload when the `X-Dev-Request: true` header is present and the token carries the `Dev` role — this avoids a second round-trip to retrieve raw details.

---

## Chapter 16 — Source Control & Commit Rules

Source control discipline makes it possible to trace why a change was made, roll back a broken release, and collaborate without conflicts.

### Repository Structure

- One Git repository per solution. Do not split into separate repos unless organizational scale demands it.
- The `docs/` folder at the solution root stores architecture documents, ERDs, generated `openapi.json`, and this guidelines file.
- `.gitignore` must exclude: `bin/`, `obj/`, `.vs/`, `*.user`, and all credential-containing files.
- `.copilotignore` must list the same credential files as `.gitignore` to prevent AI tools from reading secrets.

### Branch Strategy

| Branch | Purpose | Who Creates |
|--------|---------|-------------|
| `master` / `main` | Production-ready code only. Deployments triggered from this branch. | Protected — merged via PR only |
| `develop` | Integration branch. Completed features merged here first. | Protected — merged via PR only |
| `feature/{description}` | One branch per feature or story. | Developer |
| `fix/{issue}-{description}` | Bug fix branches, referencing an issue number. | Developer |
| `release/{version}` | Release preparation: version bumps and changelog only. | Release manager |

### Commit Message Format

```
{type}({scope}): {short description in present tense, under 72 chars}

Body: explain WHY the change was made, not what was changed.
The diff already shows what changed.

Refs: #{issue-number}

Types: feat | fix | refactor | docs | test | chore
```

### Source Control Rules

- **MUST** Credentials and secrets are never committed. Period.
- **MUST** Every commit must build cleanly and pass all existing tests.
- **MUST** Commit messages describe *why* the change was made, not what changed.
- **SHOULD** Commit at logical stopping points: a completed feature, a passing test, a fixed bug. Avoid mixing unrelated changes in one commit.
- **SHOULD** Commit at least once every 4 active working days on a feature branch to reduce merge conflict risk.
- **SHOULD** Tag releases on the main branch: `git tag -a v1.3.0 -m "Release 1.3.0"`

> **✅ Note:** Add a `.copilotignore` file in the solution root that mirrors `.gitignore` entries for all files containing credentials, to prevent GitHub Copilot from reading or suggesting edits to those files.

---

## Chapter 17 — Database Seed Data Patterns

**Target Audience:** DBAs, backend developers, DevOps, infrastructure leads  
~~**Applicability:** Any Vega Discoveries solution with a database (SSDT `.sqlproj`)~~  
**Applicability:** Any Vega Discoveries solution with a database (`.Database` DbUp class library)  
**Context:** Reference data, configuration seeds, and migration sequences for all solutions

---

### Overview

Seed data represents reference tables, configuration values, and static lookup data inserted during initial database deployment and migrations. This chapter defines patterns, methodologies, and validation strategies applicable to all Vega Discoveries solutions.

Seed data differs from:
- **Transaction data** — User-created records (never seeded in bulk)
- **Transient data** — Session state, temporary calculations (not seeded; ephemeral)
- **Configuration** — Can live in appsettings.json (but may also be seeded for auditability)

---

### Part 1: Seed Data Lifecycle and Phases

#### Phase Binding

Each seed data insertion is tied to a migration phase:

- **Phase 1 (Initialization)** — Solution registration, fundamental lookups
- **Phase 2 (Domain)** — Entity-scoped seed data (e.g., carrier codes, type enums)
- **Phase 3–6** — Feature-specific seeds (email templates, API configuration)
- **Phase 7+ (Infrastructure)** — Operational seeds (monitoring policies, rate limits)

**Principle:** Seed data creation order mirrors the dependency graph; a seed inserted in Phase 3 must reference seed data created in Phase 1 or 2.

#### Idempotency — Critical Pattern

All seed data inserts must be **idempotent** — running a migration multiple times produces the same result.

**Pattern:**

```sql
-- ❌ NOT idempotent (fails on re-run if record exists)
INSERT INTO [ConfigurationTable] ([Key], [Value]) 
VALUES ('MfaCodeLifetime', '10');

-- ✅ Idempotent (safe on re-run)
INSERT INTO [ConfigurationTable] ([Key], [Value])
SELECT 'MfaCodeLifetime', '10'
WHERE NOT EXISTS (
  SELECT 1 FROM [ConfigurationTable] 
  WHERE [Key] = 'MfaCodeLifetime' AND IsDeleted = 0
);
```

**Why:** Migrations may be re-run in non-prod environments for testing, schema resets, or CI/CD replay scenarios. Idempotent inserts prevent duplicate-key errors.

#### Transaction Scope

All related seed operations (table creation + seeding + index creation) belong in a single transaction:

```sql
BEGIN TRANSACTION
  -- 1. Create table
  CREATE TABLE [EmailType] (...)
  
  -- 2. Seed records
  INSERT INTO [EmailType] (...)
  
  -- 3. Create indexes
  CREATE INDEX [IX_EmailType_Name] ON [EmailType] ([Name])
  
COMMIT TRANSACTION
```

**Rationale:** If any step fails, the entire migration rolls back; no partial schema or orphaned seed data.

---

### Part 2: Seed Data Organization

#### By Table Category

Organize seeds into logical categories:

| Category | Purpose | Typical Tables | Insertion Order |
|----------|---------|-----------------|-----------------|
| **Framework** | Core system configuration (roles, types, status enums) | EmailType, UserRole, AccountStatus | Phase 1–2 |
| **Reference** | Static lookup data (carriers, time zones, countries) | SmsCarrier, TimeZone, Country | Phase 2–3 |
| **Operations** | Runtime configuration (rate limit policies, thresholds) | RateLimitPolicy, SecurityPolicy | Phase 4+ |
| **Solutions** | Solution registration and solution-specific data | RegisteredSolutions, SolutionConfig | Phase 1 (solution-specific) |

#### Seed Data Storage in Migrations

~~In SSDT projects, seed data lives in **post-deployment scripts** (not EF Core migrations).~~
In the `.Database` DbUp class library, seed data scripts are placed in the `PostDeployment/` folder and executed via `NullJournal` (always-run, idempotent).

**File location:** `VegaIdentity.Database/PostDeployment/`

**Naming convention:** `Script.PostDeployment.sql` or numbered scripts like `001_InitializeSeed.sql`, `002_EmailTypes.sql`

**Execution order:** Post-deployment scripts run **after** all schema migrations complete, in alphabetical order by filename.

---

### Part 3: Seed Data Schema Design

#### Required Columns for Seed Records

Every seed record must capture:

| Column | Type | Purpose | Always Seed? |
|--------|------|---------|-------------|
| `[Key]ID` or `[Key]GUID` | INT or UNIQUEIDENTIFIER | Primary key (database-assigned) | No — DB default |
| `Name` or `Code` | NVARCHAR(255) | Stable lookup identifier (what code references) | **Yes** — application dependency |
| `DisplayName` or `Label` | NVARCHAR(255) | Human-readable name for UI | **Yes** |
| `Description` | NVARCHAR(2000) | Explanation for ops/support | **Yes** |
| `SortOrder` | INT | UI display order (ascending) | **Yes** |
| `IsActive` | BIT | Soft-delete indicator (1 = active) | **Yes — always 1 for new seeds** |
| `CreatedUser` | NVARCHAR(150) | Audit: who created this | **Yes — always 'system'** |
| `CreatedDate` | DATETIME2(7) | Audit: when created | **Yes — use DB DEFAULT GETUTCDATE()** |
| `LastUpdatedUser` | NVARCHAR(150) | Audit: last modifier | **Yes — same as CreatedUser** |
| `LastUpdatedDate` | DATETIME2(7) | Audit: last update time | **Yes — use DB DEFAULT GETUTCDATE()** |
| `IsDeleted` | BIT | Hard-delete flag (0 = not deleted) | **Yes — always 0 for new seeds** |
| `DeletedDate` | DATETIME2(7) | Audit: when deleted | No — NULL for new seeds |
| `DeletedUser` | NVARCHAR(150) | Audit: who deleted | No — NULL for new seeds |

**Pattern for INSERT:**

```sql
INSERT INTO [ReferenceTable] 
  ([Name], [DisplayName], [Description], [SortOrder], [IsActive], [CreatedUser], [LastUpdatedUser])
VALUES 
  ('enum_value', 'Display Name', 'Description', 10, 1, 'system', 'system')
  -- DB DEFAULT handles CreatedDate, LastUpdatedDate
```

---

### Part 4: Insertion Order and Dependencies

#### Build a Dependency Graph Before Inserting

If Table B has a foreign key to Table A, insert Table A seeds **first**.

**Example dependency chain:**

```
EmailType (no dependencies)
  ↓ (EmailTemplate.EmailTypeId → EmailType.EmailTypeID)
EmailTemplate
  ↓ (EmailTemplateBlock.EmailTemplateId → EmailTemplate.EmailTemplateID)
EmailTemplateBlock
  ↓ (EmailBlock.EmailBlockID referenced by EmailTemplateBlock)
EmailBlock
```

**Seed in order: EmailType → EmailBlock → EmailTemplate → EmailTemplateBlock**

#### Using DECLAREs for Cross-Table References

When seeding dependent records, retrieve the parent ID once:

```sql
-- ✅ Efficient: single SELECT, then reference in VALUES
DECLARE @EmailTypeId INT = (
  SELECT EmailTypeID FROM [EmailType] 
  WHERE Name = 'EmailVerification' AND IsDeleted = 0
);

INSERT INTO [EmailTemplate] ([EmailTypeId], [Name], [Subject], ...)
VALUES (@EmailTypeId, 'EmailVerification_Default', 'Verify Your Email', ...);
```

**Rationale:** Avoids repeated subqueries; makes dependency explicit.

---

### Part 5: Validation After Seed Insertion

#### Post-Insert Verification

After seeds are inserted, verify:

1. **Count check** — Verify expected row count

```sql
SELECT COUNT(*) AS ActualCount FROM [EmailType] WHERE IsDeleted = 0;
-- Expected: 3 (EmailVerification, PasswordReset, SmsVerification)
```

2. **Uniqueness check** — Verify no duplicate names

```sql
SELECT [Name], COUNT(*) AS DuplicateCount 
FROM [EmailType] 
WHERE IsDeleted = 0
GROUP BY [Name]
HAVING COUNT(*) > 1;
-- Expected: (no rows — all unique)
```

3. **Referential integrity check** — Verify foreign keys

```sql
SELECT COUNT(*) AS OrphanedRecords
FROM [EmailTemplate] et
LEFT JOIN [EmailType] et2 ON et.EmailTypeId = et2.EmailTypeID
WHERE et.IsDeleted = 0 AND et2.EmailTypeID IS NULL;
-- Expected: 0 (no orphaned templates)
```

4. **Audit trail check** — Verify created/updated dates are set

```sql
SELECT COUNT(*) AS MissingAudit 
FROM [EmailType] 
WHERE IsDeleted = 0 AND (CreatedDate IS NULL OR CreatedUser IS NULL);
-- Expected: 0
```

#### Validation Checklist Template

For each seeded table:

- [ ] Correct number of rows inserted (use COUNT query)
- [ ] All rows have `IsActive = 1` or `IsDeleted = 0` (as appropriate)
- [ ] All `Name` / `Code` values are unique and match application constants
- [ ] All foreign key references resolve (no orphaned records)
- [ ] All audit columns are populated (`CreatedUser`, `CreatedDate`, etc.)
- [ ] No duplicate names (run GROUP BY query)

---

### Part 6: Updating Seed Data in Future Releases

#### When to UPDATE vs. INSERT

| Scenario | Action | Example |
|----------|--------|---------|
| Add a **new** reference value | `INSERT` (idempotently) | Add new SMS carrier to SmsCarrier table |
| Change a **display name** | `UPDATE` existing record | Change 'PasswordReset' → 'Password Reset Flow' |
| Retire an old value | `UPDATE IsActive = 0` (soft-delete) | Disable legacy email type |
| Remove entirely (rare) | `UPDATE IsDeleted = 1` (hard-delete) | Only if never referenced |

#### Safe UPDATE Pattern

```sql
-- ✅ Idempotent update (safe on re-run)
UPDATE [EmailType] 
SET [DisplayName] = 'Password Reset Flow', [LastUpdatedUser] = 'system'
WHERE [Name] = 'PasswordReset' 
  AND [IsDeleted] = 0 
  AND [DisplayName] != 'Password Reset Flow';  -- Only update if different
```

---

### Part 7: Rollback and Recovery

#### Soft-Delete (Recommended for Production)

When seed data must be deactivated but audit trail must remain:

```sql
UPDATE [SmsCarrier] 
SET [IsActive] = 0, [LastUpdatedUser] = 'admin'
WHERE [CarrierCode] = 'deprecated_carrier';
```

**Advantage:** Previous references are preserved; data audit trail is intact.

#### Hard-Delete (Only if Safe)

Only use if the seeded record is **guaranteed unreferenced**:

```sql
DELETE FROM [SmsCarrier] 
WHERE [CarrierCode] = 'never_used_carrier' 
  AND (SELECT COUNT(*) FROM [UserPhoneNumber] WHERE [CarrierId] = SmsCarrier.SmsCarrierId) = 0;
```

**Caution:** Hard-delete removes audit trail. Use only in pre-production scenarios.

---

### Part 8: Seed Data and Environment Differences

#### When Seed Data Differs by Environment

Some seed data is **environment-independent** (core reference data), some **environment-specific** (operational thresholds).

**Environment-independent (same across Dev/Staging/Prod):**
- Email types (EmailVerification, PasswordReset, SmsVerification)
- SMS carriers
- Framework roles (User, Admin, Dev)
- Standard enums

**Environment-specific (may differ):**
- Rate limit thresholds (strict in Prod, relaxed in Dev)
- Email sender addresses (noreply-dev@, noreply-prod@)
- Solution registration (each environment registers different solutions)

**Pattern:**

```sql
-- Post-deployment script with environment detection
DECLARE @Environment NVARCHAR(50) = '$(Environment)';

-- Core seeds (all environments)
INSERT INTO [EmailType] ([Name], [DisplayName], ...) 
SELECT 'EmailVerification', 'Email Verification', ...
WHERE NOT EXISTS (SELECT 1 FROM [EmailType] WHERE Name = 'EmailVerification');

-- Environment-specific seeds
IF @Environment = 'Production'
BEGIN
  INSERT INTO [RateLimitPolicy] ([Name], [Threshold], [WindowMinutes], ...)
  VALUES ('AuthLogin', 5, 30, ...)  -- 5 attempts per 30 min
END
ELSE
BEGIN
  INSERT INTO [RateLimitPolicy] ([Name], [Threshold], [WindowMinutes], ...)
  VALUES ('AuthLogin', 50, 30, ...)  -- 50 attempts per 30 min (dev-friendly)
END
```

---

### Part 9: Seed Data in CI/CD Pipelines

#### Integration with Build and Deployment

1. **Local Development**
   - Post-deployment scripts run automatically on `dotnet build`
   - Developer verifies seeds via test queries after build

2. **Continuous Integration**
   - Schema deployed to test database
   - Post-deployment scripts execute
   - Integration tests verify seed data exists and is correct
   - Example assertion: `Assert.Equal(3, context.EmailTypes.Where(x => !x.IsDeleted).Count())`

3. **Staging/Production Deployment**
   - DACPAC published via automated pipeline
   - Post-deployment scripts run (idempotent)
   - Ops team runs validation queries post-deployment
   - Alerts fire if seed count is wrong (config drift detection)

#### Example Test Assertion

```csharp
[Fact]
public void PostDeploymentSeeds_EmailTypesExist()
{
  // Arrange
  using var db = new AppIdentityDbContext();
  
  // Act
  var emailTypes = db.EmailTypes.Where(x => !x.IsDeleted).ToList();
  
  // Assert
  Assert.NotEmpty(emailTypes);
  Assert.Contains(emailTypes, x => x.Name == "EmailVerification");
  Assert.Contains(emailTypes, x => x.Name == "PasswordReset");
  Assert.Contains(emailTypes, x => x.Name == "SmsVerification");
}
```

---

### Part 10: Common Seed Data Patterns Across All Solutions

#### Pattern 1: Email Types

Every solution that sends emails should seed standard email types:

```sql
INSERT INTO [EmailType] ([Name], [DisplayName], [Description], [SortOrder], [IsActive], [CreatedUser], [LastUpdatedUser])
SELECT 'EmailVerification', 'Email Verification', 'Account email verification', 10, 1, 'system', 'system'
WHERE NOT EXISTS (SELECT 1 FROM [EmailType] WHERE Name = 'EmailVerification');

INSERT INTO [EmailType] ([Name], [DisplayName], [Description], [SortOrder], [IsActive], [CreatedUser], [LastUpdatedUser])
SELECT 'PasswordReset', 'Password Reset', 'Password reset flow', 20, 1, 'system', 'system'
WHERE NOT EXISTS (SELECT 1 FROM [EmailType] WHERE Name = 'PasswordReset');
```

#### Pattern 2: Solution Registration

Each solution's database must register itself:

```sql
INSERT INTO [RegisteredSolutions] ([Name], [AudienceIdentifier], [FromAddress], [FromDisplayName], [CreatedUser], [LastUpdatedUser], [IsActive])
SELECT 'MyConsumerSolution', 'vegadiscoveries.myconsomersolution', 'noreply@myconsomersolution.vegadiscoveries.com', 'MyConsumer Notifications', 'system', 'system', 1
WHERE NOT EXISTS (SELECT 1 FROM [RegisteredSolutions] WHERE Name = 'MyConsumerSolution' AND IsDeleted = 0);
```

#### Pattern 3: Lookup/Reference Tables

Tables that support dropdowns or type validation:

```sql
INSERT INTO [Country] ([Code], [Name], [DisplayName], [IsActive], [CreatedUser], [LastUpdatedUser])
SELECT 'US', 'United States', 'United States of America', 1, 'system', 'system'
WHERE NOT EXISTS (SELECT 1 FROM [Country] WHERE Code = 'US' AND IsDeleted = 0);
```

---

### Part 11: Documentation Requirements for Seed Data

When documenting seed data in a solution:

1. **Purpose** — Why this seed exists (what feature depends on it?)
2. **Table** — Which table holds it
3. **Columns** — Which columns are populated; which are defaults
4. **Records** — Exact INSERT statements (SQL or code template)
5. **Phase** — When in the migration sequence it's inserted
6. **Validation** — Verification query or test assertion
7. **Updates** — How to add new values in future releases
8. **Dependencies** — What this seed depends on; what depends on it

---

### Part 12: Anti-Patterns to Avoid

#### ❌ Non-Idempotent Inserts

```sql
-- WRONG: Fails on re-run if record exists
INSERT INTO [EmailType] ([Name], [DisplayName]) VALUES ('EmailVerification', 'Email Verification');
```

**Fix:** Use `WHERE NOT EXISTS`.

#### ❌ Hardcoded IDs in Foreign Keys

```sql
-- WRONG: Assumes EmailTypeID = 1 (brittle)
INSERT INTO [EmailTemplate] ([EmailTypeId], [Name]) VALUES (1, 'EmailVerification_Default');
```

**Fix:** Use DECLARE to look up the ID:

```sql
DECLARE @EmailTypeId INT = (SELECT EmailTypeID FROM [EmailType] WHERE Name = 'EmailVerification');
INSERT INTO [EmailTemplate] ([EmailTypeId], [Name]) VALUES (@EmailTypeId, 'EmailVerification_Default');
```

#### ❌ Mixing Schema and Seed in Single Script

```sql
-- WRONG: Schema and data in one script; hard to separate concerns
CREATE TABLE [EmailType] (...);
INSERT INTO [EmailType] (...) VALUES (...);
```

**Fix:** Separate into schema (migrations) and seeds (post-deploy scripts).

#### ❌ Missing Audit Columns

```sql
-- WRONG: No CreatedUser, CreatedDate, IsDeleted
INSERT INTO [EmailType] ([Name], [DisplayName]) VALUES (...);
```

**Fix:** Always include audit columns (or rely on DB DEFAULT).

#### ❌ Seed Data Without Validation

Deploy seeds without verifying they actually exist post-deployment.

**Fix:** Add validation queries to post-deploy script or integration tests.

---

### Summary

**Seed data patterns for all Vega Discoveries solutions:**

1. ✅ **Idempotent inserts** — Safe on re-run
2. ✅ **Phase-bound** — Tied to migration phases
3. ✅ **Transactional** — All-or-nothing per migration
4. ✅ **Audited** — CreatedUser, CreatedDate, IsDeleted
5. ✅ **Validated** — Post-insert verification queries
6. ✅ **Documented** — Purpose, table, phase, validation
7. ✅ **Environment-aware** — Core seeds vs. environment-specific seeds
8. ✅ **Updateable** — Safe UPDATE pattern for future releases

For solution-specific seed data (constants, configuration, reference tables), see the solution's own documentation.

---

## Changelog

| Version | Date | Description |
|---------|------|-------------|
| V1.00 | 2026-03-13 | Initial release. Full guidelines covering solution structure, project roles, folder organisation, versioning, authentication & security, mobile readiness, database architecture (two-DB model, CommonColumns, stored procedure naming, DB rules), data access patterns, API design, DTOs, logging, error handling, configuration & secrets, Blazor website, and source control. |
| — | 2026-05-17 | **Parent/child sanity check.** All 16 chapter section files verified against corresponding parent chapters. No discrepancies found. |
| V1.11 | 2026-05-17 | **SortOrder Convention** added to Chapter 7. Expanded `SortOrder` table entry to note default value, direction, and pointer to new subsection. Added `### SortOrder Convention` subsection documenting: the three natural display bands (< 100 promoted, = 100 normal, > 100 demoted); the required secondary sort column for deterministic tie-breaking; and the grouping extension pattern using multiples of 10 where integer division extracts the group key. Explicit rule added that `SortOrder` is never used for chronological ordering — datetime columns serve that purpose. |
| V1.10 | 2026-03-23 | **Two-database model clarified:** `Email` (normalised to lowercase, unique-constrained) documented as the logical cross-database key between identity DB and app DB. **App DB `User` table** added — defines the minimum app-domain user record (`UserID`, `UserGUID`, `Email`, `CommonColumns`) with cross-database link rules including simultaneous creation at registration and email-change rollback strategy. **App DB `Role` and `UserRole` tables** added — `Role` table defines project-specific named roles (seeded at startup); `UserRole` junction table maps accounts to roles with audit columns. Standard generic role set (User/10, Admin/20, Dev/30) documented as a reference; projects must define their own domain-specific roles and default role assignment. **Roles & Authorization** section expanded with standard roles table, JWT stamping rule (roles queried from app DB at token generation), and re-validation requirement for sensitive operations. **Registration flow** updated to include app DB `User` insert and default role `UserRole` assignment as steps 3–4 with compensating rollback. |
