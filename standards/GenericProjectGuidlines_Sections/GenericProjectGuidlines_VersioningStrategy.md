# Chapter 4 — Versioning Strategy

> *Section file for `GenericProjectGuidlines_V1.10_20260323.md`*
>
> **⚠️ Sync rule — agent instruction:** This is a section file. Any change made here **must be mirrored in the corresponding chapter** of `GenericProjectGuidlines_V1.10_20260323.md`. Any change made in the parent document's corresponding chapter must be mirrored back here. Both files must remain identical in content for their shared sections.
>
> **TOC Maintenance:** If this section is renamed or deleted, update both the parent document's Contents list AND the `GenericProjectGuidlines_TOC.md` file. See the TOC file for detailed maintenance instructions.

---

Versioning must be planned independently for three separate concerns: the API, the website, and the mobile apps. Conflating these leads to forced lock-step releases and breaks consumer independence.

## API Versioning

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

## Website Versioning

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

## Mobile App Versioning

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
