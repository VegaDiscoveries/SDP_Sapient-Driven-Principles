# Chapter 3 — Folder & File Organization

> *Section file for `GenericProjectGuidlines_V1.10_20260323.md`*
>
> **⚠️ Sync rule — agent instruction:** This is a section file. Any change made here **must be mirrored in the corresponding chapter** of `GenericProjectGuidlines_V1.10_20260323.md`. Any change made in the parent document's corresponding chapter must be mirrored back here. Both files must remain identical in content for their shared sections.
>
> **TOC Maintenance:** If this section is renamed or deleted, update both the parent document's Contents list AND the `GenericProjectGuidlines_TOC.md` file. See the TOC file for detailed maintenance instructions.

---

A consistent folder structure across all projects reduces the time needed to navigate unfamiliar code and makes onboarding new team members faster. Create a folder only when there are two or more files that share a common scope. Never create empty folders as placeholders in source control.

## Domain Project

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

## Contracts Project

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

## API Project

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

## Website Project

```
  {AppName}.Website/
  ├── Components/
  │   ├── Account/                    // Identity scaffolded pages and email sender
  │   ├── Layout/                     // MainLayout.razor, NavMenu.razor
  │   ├── Pages/
  │   │   ├── Public/                 // pages accessible without authentication
  │   │   └── Secure/                 // pages requiring authentication
  │   └── Support/                    // PageBase.cs, SecurePageBase.cs
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

## File Naming Rules

- **MUST** File names match the primary class they contain exactly (PascalCase). One primary class per file.
- **MUST** DTO files end with the suffix `Dto`. Example: `LoginRequestDto.cs`, `UserSummaryDto.cs`.
- **MUST** Interface files are prefixed with `I` and named identically to their implementation. Example: `IUserRepository.cs` / `UserRepository.cs`.
- **MUST** Controller files end with `Controller`. Service files end with `Service`. DbContext files end with `DbContext`.
- **MUST** Namespaces mirror the folder path from the project root. File at `{AppName}.API/Controllers/V1/AuthController.cs` → namespace `{AppName}.API.Controllers.V1`.
- **SHOULD** Use file-scoped namespace declarations (`namespace Foo.Bar;`) to reduce indentation depth.
- **SHOULD** Extension method files end with `Extensions`. Example: `StringExtensions.cs`, `SessionExtensions.cs`.
- **MAY** Group tightly related small classes (e.g., a set of custom exception types) in a single file when each class is under 30 lines.
