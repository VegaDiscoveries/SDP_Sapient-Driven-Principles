# Chapter 13 — Coding Standards

> *Section file for `GenericProjectGuidlines_V1.10_20260323.md`*
>
> **⚠️ Sync rule — agent instruction:** This is a section file. Any change made here **must be mirrored in the corresponding chapter** of `GenericProjectGuidlines_V1.10_20260323.md`. Any change made in the parent document's corresponding chapter must be mirrored back here. Both files must remain identical in content for their shared sections.
>
> **TOC Maintenance:** If this section is renamed or deleted, update both the parent document's Contents list AND the `GenericProjectGuidlines_TOC.md` file. See the TOC file for detailed maintenance instructions.

---

Consistent code style reduces cognitive overhead when reading unfamiliar code. Every rule applies uniformly across all projects. When in doubt, choose clarity over brevity.

## Naming Conventions

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

## Verbose, Descriptive Names

Names must communicate intent without requiring the reader to look at the implementation. Single-letter names, abbreviations, and vague names like `tmp`, `obj`, `val`, or `str` are not acceptable.

```csharp
// ❌ Avoid — forces the reader to mentally decode the name
var r = await repo.Get(id);
bool f = r != null;

// ✅ Preferred — intent is immediately clear
var requestedCoin = await coinRepository.GetByGuidAsync(coinGuid);
bool coinWasFound = requestedCoin is not null;
```

## Async / Await

- **MUST** Every I/O-bound operation is `async`/`await` across all project tiers. Never use `.Result`, `.Wait()`, or `.GetAwaiter().GetResult()`.
- **MUST** Every `async` method name ends with `Async`.
- **MUST** Return `Task`, never `void`, from `async` methods. `async void` is permitted only for Blazor event handlers.
- **SHOULD** Pass `CancellationToken` through the full call stack for long-running or HTTP-triggered operations.

## Comments & Documentation

- **MUST** Do not add comments that restate what the code already says. `// increment the counter` above `counter++` adds no value.
- **MUST** Use `// TODO: description` (Visual Studio Task List) for known incomplete work. Never leave `// REMEMBER!!!` style comments in committed code.
- **SHOULD** Add XML doc comments to all public API controller actions, service interface members, and all `Contracts` library members.
- **SHOULD** Comment genuinely complex logic: business rules, state machines, and cryptographic operations.

## General Code Style

- **MUST** Use `var` when the type is obvious from the right-hand side. Use explicit types when it is not.
- **MUST** Use `string.IsNullOrWhiteSpace()` rather than `== null || == ""`.
- **MUST** Enable nullable reference types in all new projects and treat nullable warnings as errors in CI builds.
- **SHOULD** Use pattern matching (`is not null`, switch expressions) over `if/else` chains for null checks.
- **SHOULD** Return `IReadOnlyList<T>` or `IEnumerable<T>` from public APIs over `List<T>` to prevent unintended external mutation.
- **MAY** Use primary constructors (C# 12) for DI-heavy classes to reduce constructor boilerplate.

## String Externalization — Resource Files

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

### File Location and Naming

Each project that surfaces strings to users owns one resource file per logical domain, placed in a `Resources/` folder at the project root.

| Project | Resource File | Generated Class |
|---------|--------------|-----------------|
| `VegaIdentity.API` | `Resources/AuthMessages.resx` | `AuthMessages` |
| `VegaIdentity.Website` | `Resources/WebsiteMessages.resx` | `WebsiteMessages` |

Additional resource files may be added per project when a single file grows unwieldy (e.g., `AdminMessages.resx`, `AccountMessages.resx`). One file per logical domain, not one file per controller.

### Key Naming Convention

Keys use `{Domain}_{Context}_{Description}` format in PascalCase:

```
Register_Underage
Register_AlreadyRegistered
Login_InvalidCredentials
Common_SolutionNotFound
Email_VerificationSent
```

The prefix is the feature area or shared group (`Common_` for strings used across multiple flows). Keys must be descriptive enough to locate the usage without reading the value.

### Usage Pattern

```csharp
// ✅ Correct — strongly-typed accessor via generated designer class
using VegaIdentity.API.Resources;

throw new AuthException("UNDERAGE", AuthMessages.Register_Underage);
throw new AuthException("ALREADY_REGISTERED", AuthMessages.Register_AlreadyRegistered);

// ❌ Prohibited — literal string embedded at call site
throw new AuthException("UNDERAGE", "You must be at least 16 years old to register.");
```

### Rules

- **MUST** Every string that appears in an API response body, exception message, or UI label originates from a resource file. No exceptions for "simple" or "temporary" messages.
- **MUST** Never define a `private const string` or `static readonly string` that duplicates a resource key. The resource file is the constant.
- **MUST** The `Resources/` folder is committed. The generated `*.Designer.cs` file is committed alongside its `.resx` source.
- **SHOULD** Group related messages under a common prefix key rather than creating a new resource file for a single additional message.
- **SHOULD** Write resource values in full, grammatical sentences with correct punctuation — these may be displayed directly to end users.
- **MAY** Define a `Common_` prefix group for error strings shared across multiple service classes within the same project.

## Data-Driven Content — Preferred Default

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
