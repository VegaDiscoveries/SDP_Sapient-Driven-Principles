# Chapter 2 — Project Roles & Responsibilities

> *Section file for `GenericProjectGuidlines_V1.10_20260323.md`*
>
> **⚠️ Sync rule — agent instruction:** This is a section file. Any change made here **must be mirrored in the corresponding chapter** of `GenericProjectGuidlines_V1.10_20260323.md`. Any change made in the parent document's corresponding chapter must be mirrored back here. Both files must remain identical in content for their shared sections.
>
> **TOC Maintenance:** If this section is renamed or deleted, update both the parent document's Contents list AND the `GenericProjectGuidlines_TOC.md` file. See the TOC file for detailed maintenance instructions.

---

Each project in the solution has a clearly defined scope of responsibility. Code placed in the wrong project creates coupling that is expensive to undo. When in doubt, apply the question: *"Does this code need to know about HTTP, the database, or the UI?"* and place it in the outermost project that actually needs that knowledge.

## {AppName}.Domain

Owns the ground truth of what data looks like at rest. Has no knowledge of HTTP, the API surface, or any UI framework.

- Entity classes that map directly to database tables
- The `CommonColumns` base class and `ICommonColumns` interface (see Chapter 7)
- EF Core `DbContext` classes — one for Identity, one for the application domain
- Repository interfaces (`IUserRepository`, `ICoinRepository`, etc.)
- Domain-level enums that describe entity states or types
- EF Core migration files (`Migrations/` subfolder)

> **📋 Not allowed in Domain:** Any reference to `Microsoft.AspNetCore.*`, MVC versioning packages, Swagger, JWT bearer, or any UI framework package.

## {AppName}.Contracts

The shared vocabulary between all consumers of the API. This is the **only** project that both the API and all clients (website, mobile) reference for data shapes. It must be portable to any .NET runtime including MAUI.

- Request DTOs (`LoginRequestDto`, `CreateCoinRequestDto`)
- Response DTOs (`UserProfileResponseDto`, `CoinSummaryDto`)
- Enums that appear in API request or response bodies
- Shared configuration model classes (`JwtConfig`, `PaginationOptions`)
- Data annotation validation attributes on DTO properties

> **📋 Not allowed in Contracts:** EF Core attributes (`[DatabaseGenerated]`, `[ForeignKey]`, `[InverseProperty]`), navigation properties, `DbContext` references, or any `Microsoft.AspNetCore.*` dependency.

## {AppName}.API

The sole gatekeeper between the database and all external consumers. Enforces authentication, authorization, input validation, and business rules before any data is read or written.

- Versioned controllers under `Controllers/V{n}/`
- Service classes that implement repository interfaces from Domain
- JWT token issuance, validation, and refresh token management
- Swagger / OpenAPI configuration and post-build spec file generation
- Localization and culture routing middleware
- Structured logging setup (NLog or Serilog)
- Mapping between Domain entities and Contracts DTOs
- Environment-specific `appsettings.{Environment}.json` files

## {AppName}.Website

A Blazor Web App. Depending on project complexity, it either calls the API over HTTP (full separation) or accesses the database directly via `DbContext` (simpler single-deployment pattern). The choice must be made at project start and recorded in the solution's README.

- Blazor components organized under `Components/`
- `PageBase` and `SecurePageBase` classes for shared lifecycle logic and auth checks
- ASP.NET Core Identity UI for registration, login, and account management
- Role constants, session extensions, and string extensions under `Support/`
- Static assets (CSS, JS, fonts, images) under `wwwroot/`

> **ℹ️ Pattern decision:** Use the API-backed pattern when mobile clients exist or are planned. Use the Blazor-direct-EF pattern only for internal tools or single-deployment sites with no mobile roadmap.

## {AppName}.MAUI

A pure API consumer. References only the `Contracts` library. Contains no business logic and performs no direct database access.

- HTTP client generated from the OpenAPI spec (via Kiota or NSwag) or hand-written typed client
- Platform-specific secure token storage (iOS Keychain, Android Keystore, Windows DPAPI)
- MVVM viewmodels bound to MAUI pages and shell navigation
- Platform-specific code under `Platforms/{iOS|Android|Windows|MacCatalyst}/`
- App version number tracked separately from the API version (see Chapter 4)
- Dynamic, structured screen content sourced per target — mobile always via the API, desktop via
  an API-synced local cache by default (see Chapter 12's Dynamic Content Delivery)
