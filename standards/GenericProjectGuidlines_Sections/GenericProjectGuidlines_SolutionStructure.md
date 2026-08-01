# Chapter 1 — Solution Structure

> *Section file for `GenericProjectGuidlines_V1.10_20260323.md`*
>
> **⚠️ Sync rule — agent instruction:** This is a section file. Any change made here **must be mirrored in the corresponding chapter** of `GenericProjectGuidlines_V1.10_20260323.md`. Any change made in the parent document's corresponding chapter must be mirrored back here. Both files must remain identical in content for their shared sections.
>
> **TOC Maintenance:** If this section is renamed or deleted, update both the parent document's Contents list AND the `GenericProjectGuidlines_TOC.md` file. See the TOC file for detailed maintenance instructions.
>
> **⚠️ Append-only — agent instruction:** This document is an append-only architecture record. Do not delete or reword existing content. New or revised guidance must be added below the content it supersedes. Strikethrough (`~~text~~`) is a valid edit technique — it visually marks content as superseded while retaining it for audit purposes. Use strikethrough to mark the old text, then place the replacement immediately after on a new line.

---

Every new solution must be laid out with all future consumers — website, API, mobile apps, and shared libraries — accounted for from day one, even if only the website is built first. Retrofitting clean separation later is significantly more expensive than building the seams upfront.

## Required Projects

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

## Dependency Graph

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

## Target Framework Rules

- **MUST** All projects target `net10.0` or the then-current LTS release. Never target an out-of-support TFM (e.g., net5.0, net6.0).
- **MUST** All projects in the same solution must target the same major .NET version.
- **SHOULD** Plan to upgrade to the next LTS within 6 months of its release to stay ahead of support windows.
- **SHOULD** Run `dotnet list package --vulnerable` as part of every CI build and treat any high-severity CVE as a blocking issue.
