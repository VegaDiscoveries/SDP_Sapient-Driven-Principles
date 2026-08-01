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
