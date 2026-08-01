# Chapter 15 — Error Handling

> *Section file for `GenericProjectGuidlines_V1.10_20260323.md`*
>
> **⚠️ Sync rule — agent instruction:** This is a section file. Any change made here **must be mirrored in the corresponding chapter** of `GenericProjectGuidlines_V1.10_20260323.md`. Any change made in the parent document's corresponding chapter must be mirrored back here. Both files must remain identical in content for their shared sections.
>
> **TOC Maintenance:** If this section is renamed or deleted, update both the parent document's Contents list AND the `GenericProjectGuidlines_TOC.md` file. See the TOC file for detailed maintenance instructions.

---

Errors are caught at defined boundaries, logged with full context, and returned as structured predictable responses. Raw stack traces must never reach any client in any environment.

## Global Exception Middleware

```csharp
// API/Middleware/ExceptionHandlingMiddleware.cs
public class ExceptionHandlingMiddleware(RequestDelegate next,
    ILogger<ExceptionHandlingMiddleware> logger)
{
    public async Task InvokeAsync(HttpContext httpContext)
    {
        try { await next(httpContext); }
        catch (Exception unexpectedException)
        {
            logger.LogError(unexpectedException,
                "Unhandled exception on {Method} {Path}",
                httpContext.Request.Method, httpContext.Request.Path);

            httpContext.Response.StatusCode = 500;
            await httpContext.Response.WriteAsJsonAsync(new
            {
                Error   = "An unexpected error occurred.",
                TraceId = httpContext.TraceIdentifier  // correlates to server log
            });
        }
    }
}
```

## Custom Exception Types

```csharp
// Support/Exceptions/ — map these to HTTP status codes in the middleware
public class NotFoundException(string entityName, object key)
    : Exception($"{entityName} with key {key} was not found.");

public class DomainValidationException(string message)
    : Exception(message);
```

## Blazor Error Boundaries

```razor
<ErrorBoundary>
    <ChildContent><CoinList UserId="@currentUserId" /></ChildContent>
    <ErrorContent><p>Unable to load this section. Please try again.</p></ErrorContent>
</ErrorBoundary>
```

## Error Handling Rules

- **MUST** Register `ExceptionHandlingMiddleware` as the first item in the API pipeline.
- **MUST** Never return raw exception messages or stack traces to clients in any environment. Return a generic message with a `TraceId`. **Exception:** users holding the `Dev` role may view raw error details through the Dev Toolbar — see below.
- **MUST** `ShowStackTrace` is controlled by configuration (Chapter 14). It is always `false` outside of Development.
- **MUST** Log the full exception at `Error` level before returning a sanitized response.
- **SHOULD** Map custom exception types to specific HTTP status codes in the global middleware.
- **SHOULD** Wrap independent Blazor page sections in `<ErrorBoundary>` so one component failure does not blank the entire page.

## Dev Toolbar

When the authenticated user holds the `Dev` role, the UI must render a persistent Dev Toolbar (or equivalent dev menu/panel). This toolbar is invisible to all other roles and is never rendered in any context where the current user does not have `Dev` in their active JWT claims.

**Required Dev Toolbar capabilities:**

| # | Feature | Description |
|---|---------|-------------|
| 1 | Raw Error Details | On any runtime error, displays the full exception message, exception type, and stack trace that would otherwise be suppressed. Presented in a collapsible panel or modal alongside the standard user-facing error message. |
| 2 | Request / Response Inspector | Log of the last N API calls made by this client: method, URL, HTTP status, latency (ms), and collapsible request/response body. Cleared on page reload. |
| 3 | JWT Inspector | Decoded view of the current access token: all claims, issued-at timestamp, expiry time, and a live countdown to expiry. |
| 4 | Feature Flag Override | Toggle any named feature flag on or off for this session only. Overrides do not affect other users and reset on logout. |
| 5 | Session Info | Current user ID, GUID, active roles from JWT, refresh token expiry, and solution context identifier. |
| 6 | Log Stream Viewer | Tail of recent structured server-side log entries at `Warning` level and above, filtered to TraceIds associated with this user’s requests. Requires the API to expose a scoped log query endpoint gated to the `Dev` role. |
| 7 | Performance Alerts | Highlights any API response that exceeded a configurable latency threshold (default 500 ms). Shows endpoint, duration, and timestamp. |
| 8 | State Snapshot | Dumps the current client-side application state (store / context / signal graph) to a readable, collapsible panel. Useful for diagnosing stale or unexpected UI state. |
| 9 | Network Latency Overlay | Per-request timing badge rendered on-screen for all in-flight and recently completed API calls, showing endpoint name and round-trip time. |

**Rules:**

- **MUST** The Dev Toolbar is only rendered when the JWT `role` claims include `Dev`. Never infer Dev access from any other signal.
- **MUST** The raw error detail panel must not replace the standard error message — it is additive. Non-dev users still see the sanitized message.
- **MUST** Raw error data is never written to the DOM in a way that is accessible to non-dev users (no hidden fields, no HTML comments).
- **SHOULD** The API may optionally include an extended error payload when the `X-Dev-Request: true` header is present and the token carries the `Dev` role — this avoids a second round-trip to retrieve raw details.
