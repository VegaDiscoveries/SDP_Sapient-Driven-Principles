# Chapter 12 — Mobile Readiness

> *Section file for `GenericProjectGuidlines_V1.10_20260323.md`*
>
> **⚠️ Sync rule — agent instruction:** This is a section file. Any change made here **must be mirrored in the corresponding chapter** of `GenericProjectGuidlines_V1.10_20260323.md`. Any change made in the parent document's corresponding chapter must be mirrored back here. Both files must remain identical in content for their shared sections.
>
> **TOC Maintenance:** If this section is renamed or deleted, update both the parent document's Contents list AND the `GenericProjectGuidlines_TOC.md` file. See the TOC file for detailed maintenance instructions.

---

Every Phase 1 decision either helps or hinders the Phase 2 mobile rollout. The rules here ensure adding a MAUI app later requires only new code — not changed architecture.

## Phase 1 Actions That Enable Mobile

| Action | Why It Matters for Mobile |
|--------|--------------------------|
| JWT bearer tokens (not cookies) | Mobile apps cannot use browser cookies. JWT works identically on iOS, Android, and web. |
| `Contracts` free of web dependencies | MAUI must reference `Contracts` directly. One `AspNetCore` package reference blocks this entirely. |
| Expose GUID not integer ID in API responses | Integer IDs leak DB implementation details. GUIDs are safe in mobile deep links and push notification payloads. |
| OpenAPI spec generated on every build | Enables Kiota/NSwag to generate a typed C# HTTP client for MAUI with one command. |
| `app.UseHttpsRedirection()` | iOS ATS and Android NSC block plain HTTP in production by default. |
| Localization via route culture provider | Mobile device locale maps directly to the API route culture segment. |

## Phase 2 — Generating the Mobile API Client

```bash
kiota generate -l CSharp -d docs/openapi.json \
  -o {AppName}.MAUI/ApiClient \
  -n {AppName}.MAUI.ApiClient
```

## Secure Token Storage (MAUI)

```csharp
// Uses iOS Keychain / Android Keystore / Windows DPAPI automatically
await SecureStorage.Default.SetAsync("refresh_token", newRefreshToken);
var storedRefreshToken = await SecureStorage.Default.GetAsync("refresh_token");
```

- **MUST** Never store JWT tokens in `Preferences` or plain text files. Use `SecureStorage` exclusively.
- **MUST** MAUI references only `{AppName}.Contracts`. Never `Domain` or `API`.
- **SHOULD** Handle `401 Unauthorized` globally in the HTTP client by attempting a silent token refresh before showing a login prompt.
- **SHOULD** Test localization using device locale settings on both iOS Simulator and Android Virtual Device before release.

---

## Adaptive Layout (MAUI UI)

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

## Dynamic Content Delivery

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
