# Chapter 11 — Website — Blazor

> *Section file for `GenericProjectGuidlines_V1.10_20260323.md`*
>
> **⚠️ Sync rule — agent instruction:** This is a section file. Any change made here **must be mirrored in the corresponding chapter** of `GenericProjectGuidlines_V1.10_20260323.md`. Any change made in the parent document's corresponding chapter must be mirrored back here. Both files must remain identical in content for their shared sections.
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
- **SHOULD** Use `StringExtensions` and `SessionExtensions` from `Support/Extensions/` rather than duplicating logic inline.
- **SHOULD** Group pages by access level: `Pages/Public/` and `Pages/Secure/`.

---

## Responsive Layout

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

## Dynamic Content Collections

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
