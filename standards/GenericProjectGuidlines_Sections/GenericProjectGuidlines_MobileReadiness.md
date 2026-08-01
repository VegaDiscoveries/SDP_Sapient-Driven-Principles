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
