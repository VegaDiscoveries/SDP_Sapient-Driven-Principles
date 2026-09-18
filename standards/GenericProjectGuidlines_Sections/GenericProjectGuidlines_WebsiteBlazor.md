# Chapter 11 — Website — Blazor

> *Section file for `GenericProjectGuidlines_V1.11_20260904.md`*
>
> **⚠️ Sync rule — agent instruction:** This is a section file. Any change made here **must be mirrored in the corresponding chapter** of `GenericProjectGuidlines_V1.11_20260904.md`. Any change made in the parent document's corresponding chapter must be mirrored back here. Both files must remain identical in content for their shared sections.
>
> **TOC Maintenance:** If this section is renamed or deleted, update both the parent document's Contents list AND the `GenericProjectGuidlines_TOC.md` file. See the TOC file for detailed maintenance instructions.

---

The website is a **Blazor Web App** targeting .NET 10. All new projects use Blazor for the frontend. MVC controller patterns are reserved for the API project only.

## Page Base Classes

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

## Blazor Rules

- **MUST** All authenticated pages declare `@attribute [Authorize]` and inherit from `SecurePageBase`.
- **MUST** Role names are referenced via `RoleDefs` constants. No inline role string literals.
- **MUST** Never place data access logic directly in a `.razor` file. Use the `DataAccess` class or an injected service.
- **SHOULD** If a component's `@code` block exceeds ~60 lines, extract a code-behind `.razor.cs` partial class.
- **SHOULD** Where an existing method in `StringExtensions` or `SessionExtensions` (`Support/Extensions/`) already covers the case, use it rather than duplicating the logic inline; this does not restrict writing new logic (inline or as a new extension) where no existing extension covers the case.
- **MUST** Group pages by access level: `Pages/Public/` and `Pages/Secure/`.

---

## Responsive Layout

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
- **MUST** Verify each new or changed customer-facing page at three reference widths — phone
  (~375px), tablet (~768px), desktop (~1440px) — before marking the task complete; for
  `[VERIFY DURING IMPLEMENTATION]`-flagged UI tasks, note the widths checked in the Completed
  blockquote.
- **MUST** Prefer CSS-only responsive behavior (media queries, container queries) over
  JavaScript-driven layout switching, to keep behavior predictable and testable, unless using a
  component library's built-in responsive grid per the MAY rule below.
- **MAY** Use a component library's built-in responsive grid (e.g. Bootstrap, MudBlazor) in
  place of hand-rolled Flexbox/Grid, provided its breakpoints are not overridden in a way that
  defeats the MUST rules above.

## Dynamic Content Collections

> **Addition — 2026-08-13:** Added after a real incident where a version-history page's milestone
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

## Cookie Consent

> **Addition — 2026-08-23:** Concrete Website (Blazor) instantiation of Chapter 13's "Cookie /
> Tracking Consent — Required for Any Web-Rendering Project Type" rule. No GPG chapter previously
> addressed cookie/tracking consent at all. Designed to the GDPR/ePrivacy baseline (the strictest
> single regime), with explicit reconciliation of CCPA/CPRA, PIPEDA/Quebec Law 25, and LGPD's
> distinct requirements rather than assuming GDPR alone covers every regime.

Every customer-facing page that sets or reads non-essential cookies (or equivalent client-side
storage — see the `Necessary` category note below) presents a consent banner before any such
storage is set or any non-essential script executes. "Optional" means any category other than
`Necessary`.

### Category Model

- **MUST** Cookie categories are `Necessary` (always on, non-toggleable — exempt from consent
  under ePrivacy Art. 5(3) as strictly technical/functional storage), `Functional`, `Analytics`,
  and `Marketing` (all three optional, default OFF, individually toggleable). Sourced from
  `Content/cookie-categories.json` via the existing content-loading service (see Dynamic Content
  Collections above) — category data, not markup.
- **MUST** The encrypted-`localStorage` access-token mechanism Chapter 5 already governs (see
  Client-Side Token Storage Strategies) falls under `Necessary` as strictly-necessary technical
  storage — cross-reference Chapter 5 for its own security handling here; do not re-derive it in
  this subsection.

```csharp
// Content/CookieCategory.cs
public record CookieCategory(string Key, string Label, string Description, bool Required);
```

```json
// Content/cookie-categories.json
[
  { "key": "necessary",  "label": "Necessary",  "description": "...", "required": true  },
  { "key": "functional", "label": "Functional", "description": "...", "required": false },
  { "key": "analytics",  "label": "Analytics",  "description": "...", "required": false },
  { "key": "marketing",  "label": "Marketing",  "description": "...", "required": false }
]
```

### Banner and Consent Component

- **MUST** The banner presents **Accept All** and **Reject All** at equal visual weight — same
  size, same prominence, same click count. A **Manage Preferences** control opens a per-category
  panel; no optional category is pre-ticked.
- **MUST** Non-essential scripts are emitted neutralized (`type="text/plain"
  data-cookie-category="{category}"`) and reactivated by a JS module only after that category's
  consent is granted — hiding the banner is not sufficient; the script must not execute
  pre-consent.
- **MUST** A persistent "Manage Cookie Preferences" control, reachable from every page (typically
  the footer), reopens the panel at any time — withdrawal must be exactly as easy as consent.
- **MUST** A prior consent record is discarded and the banner re-shown when the record is 12
  months old or older, OR the site's policy version / category set has changed since that record
  was written — whichever triggers first.
- **MUST** The banner links to the project's Privacy Policy page if one exists. This subsection
  does not itself require creating a Privacy Policy page — that is a separate content deliverable
  outside a coding-standards chapter's scope.

```razor
@* Components/CookieConsent.razor — extends Microsoft's official ITrackingConsentFeature pattern
   (learn.microsoft.com/aspnet/core/blazor/security/gdpr, which is Accept-only as shipped) with
   categories, Reject, and block-before-consent script gating. *@
@implements IAsyncDisposable
@inject IJSRuntime JS
@inject ConsentAuditService ConsentAudit

@if (showBanner)
{
    <div id="cookieConsent" class="cookie-consent" role="dialog" aria-label="Cookie preferences">
        <p>@BannerCopy</p>
        <button @onclick="AcceptAll" class="cookie-consent__accept">Accept All</button>
        <button @onclick="RejectAll" class="cookie-consent__reject">Reject All</button>
        <button @onclick="() => showPanel = true">Manage Preferences</button>
    </div>
}
@if (showPanel)
{
    @foreach (var category in Categories)
    {
        <label>
            <input type="checkbox" checked="@IsAccepted(category.Key)" disabled="@category.Required"
                   @onchange="e => SetCategory(category.Key, (bool)e.Value!)" />
            @category.Label — @category.Description
        </label>
    }
    <button @onclick="SavePreferences">Save Preferences</button>
}

@code {
    // OnInitialized: load the stored consent value, apply the 12-month/policy-version expiry
    // rule above, and set showBanner accordingly.
    // AcceptAll/RejectAll/SavePreferences: update the client-side gating value, invoke the JS
    // module to reactivate neutralized scripts for accepted categories, then write through to
    // ConsentAuditService (below) — always both, never only one.
}
```

```js
// Components/CookieConsent.razor.js
export function reactivateScripts(category) {
  document.querySelectorAll(`script[data-cookie-category="${category}"]`).forEach(old => {
    const script = document.createElement('script');
    for (const attr of old.attributes) {
      if (attr.name !== 'type') script.setAttribute(attr.name, attr.value);
    }
    script.text = old.text;
    old.replaceWith(script);
  });
}
```

### Consent Audit Log

- **MUST** Every Accept/Reject/category-change event is written to a durable, append-only
  consent-audit record — the client-side gating value alone (cookie/`localStorage`, clearable by
  the visitor) does not satisfy GDPR Art. 7(1)'s requirement that the controller be able to
  demonstrate consent was given.
- **MUST** Storage tier is verified with the user during Phase 4 (Architecture) — never
  auto-detected and applied silently (see the bootstrap doc's Phase 4 Mechanics). If the solution
  already has a database project of any type, that project is named and confirmed as the target.
  If not, the storage method is confirmed with the user directly (the flat-file fallback below, or
  another mechanism the user names).
- **MUST** (LGPD) The audit record includes a `JurisdictionDetected` field and is retained for at
  least 18 months.

```csharp
// {AppName}.Domain/ConsentLog.cs — deliberately NOT built on CommonColumns (see Chapter 7): a
// consent-audit row is an immutable event record, never updated or soft-deleted after insert, so
// CommonColumns' mutable-entity fields (IsActive, SortOrder, LastUpdated*, IsDeleted) do not
// apply. This is the "table that omits common columns" case Chapter 7 requires written
// justification for — this comment is that justification.
public class ConsentLog
{
    public int Id { get; set; }                       // ConsentLogID
    public Guid Guid { get; set; }                     // ConsentLogGUID
    public Guid VisitorId { get; set; }                // client-generated; stored with the gating value
    public string CategoriesAccepted { get; set; } = string.Empty;   // comma-separated category keys
    public string CategoriesRejected { get; set; } = string.Empty;
    public string PolicyVersion { get; set; } = string.Empty;
    public string ConsentMethod { get; set; } = string.Empty;        // "AcceptAll" | "RejectAll" | "ManagePreferences"
    public string JurisdictionDetected { get; set; } = string.Empty; // LGPD requirement — see 2c
    public DateTime CreatedDate { get; set; }          // event timestamp — GETUTCDATE() default
}

// Contracts/Requests/Consent/RecordConsentRequestDto.cs — per Chapter 9's DTO rules
public class RecordConsentRequestDto
{
    [Required] public Guid VisitorId { get; set; }
    [Required] public List<string> CategoriesAccepted { get; set; } = [];
    [Required] public List<string> CategoriesRejected { get; set; } = [];
    [Required] public string PolicyVersion { get; set; } = string.Empty;
    [Required] public string ConsentMethod { get; set; } = string.Empty;
    [Required] public string JurisdictionDetected { get; set; } = string.Empty;
}
```

The endpoint (`POST /api/v1/consent-events`) returns Chapter 10's standard `ApiResponse<T>`
envelope like every other endpoint — no special-casing for this feature.

- **MUST** If the solution has no database project, an append-only JSON/XML log file is an
  acceptable fallback, but this has real limits: no concurrent-write safety under real traffic, no
  query path for a data-subject "right to access" request. Escalate to a lightweight embedded DB
  (e.g. SQLite) once traffic or DSAR volume exceeds what a flat file can safely handle — that
  escalation is a new dependency subject to ordinary Material Decision Escalation (Phase 4 in the
  bootstrap doc), not a special case.

### Multi-Jurisdiction Reconciliation

- **MUST** (CCPA/CPRA) A conspicuous "Do Not Sell or Share My Personal Information" link (or the
  CPRA-permitted "Your Privacy Choices" toggle) appears on the homepage/footer, leading to the
  Manage Preferences panel — always on, regardless of whether `Marketing` is currently enabled.
- **MUST** (CCPA/CPRA) The Global Privacy Control (`navigator.globalPrivacyControl`) browser
  signal is recognized; when present, the site auto-applies a reject-optional outcome and visibly
  confirms it (e.g. "Opt-Out Preference Signal Honored").
- PIPEDA, Quebec Law 25, and LGPD's opt-in requirements are satisfied by the GDPR-strict opt-in
  baseline above by construction — no separate rule is added for these three.

### Google Consent Mode v2 (Conditional)

- **MUST** If the project integrates Google Analytics or Google Ads (confirmed via the Phase 4
  Architecture question — see the bootstrap doc), the four Consent Mode v2 signals map onto the
  category model: `analytics_storage` ← `Analytics`; `ad_storage`/`ad_user_data`/
  `ad_personalization` ← `Marketing`.

```js
// Sent on every consent decision, before GA/Ads scripts reactivate:
gtag('consent', 'update', {
  'analytics_storage': categories.includes('analytics') ? 'granted' : 'denied',
  'ad_storage': categories.includes('marketing') ? 'granted' : 'denied',
  'ad_user_data': categories.includes('marketing') ? 'granted' : 'denied',
  'ad_personalization': categories.includes('marketing') ? 'granted' : 'denied'
});
```

- **MAY** Escalate to a certified CMP (Cookiebot/OneTrust/Osano) instead of the in-house
  component only when a confirmed IAB TCF or programmatic-ad requirement exists — subject to
  Material Decision Escalation like any other new external dependency.
