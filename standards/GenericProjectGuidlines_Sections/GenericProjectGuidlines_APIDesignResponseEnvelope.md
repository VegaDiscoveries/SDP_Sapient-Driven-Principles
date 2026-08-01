# Chapter 10 — API Design & Response Envelope

> *Section file for `GenericProjectGuidlines_V1.10_20260323.md`*
>
> **⚠️ Sync rule — agent instruction:** This is a section file. Any change made here **must be mirrored in the corresponding chapter** of `GenericProjectGuidlines_V1.10_20260323.md`. Any change made in the parent document's corresponding chapter must be mirrored back here. Both files must remain identical in content for their shared sections.
>
> **TOC Maintenance:** If this section is renamed or deleted, update both the parent document's Contents list AND the `GenericProjectGuidlines_TOC.md` file. See the TOC file for detailed maintenance instructions.

---

The API is the single point of truth for all data operations. Its design must be consistent, predictable, and stable enough that a mobile developer building against it does not need to ask questions about what a response will contain.

The foundational design decision for this API is a **standard response envelope**. Every endpoint — without exception — returns the same outer shape. The HTTP status code communicates only the infrastructure-level outcome (auth failure, server crash, bad request shape). The *business* outcome — success, not found, validation failure, no data — is communicated entirely through the envelope. This means a `404 Not Found` HTTP response is never returned by any application endpoint. A missing resource is a *business outcome*, not an HTTP error.

## Standard Response Envelope

The `ApiResponse<T>` class and its companion enum live in the `{AppName}.Contracts` library so that the API, the Blazor website, and the MAUI app all share the exact same wrapper type — just as a typed client generated from the OpenAPI spec would expect.

> **ℹ️ Design origin:** This pattern is a modern, generic C# evolution of the typed service-result wrappers used in earlier Vega Discoveries projects. The core idea — a metadata envelope carrying request context, response metadata, an outcome status, and a single typed data property — is preserved and refined here for REST/JSON APIs.

### ApiResultStatus Enum

```csharp
// {AppName}.Contracts/Responses/ApiResultStatus.cs
namespace {AppName}.Contracts.Responses;

public enum ApiResultStatus
{
    Unknown          = 0,  // default / uninitialised — should never be returned
    Success          = 1,  // data was found and is in Data
    Failure          = 2,  // a server-side operation failed
    ValidationFailed = 3,  // the request was structurally valid but failed business rules
    NoDataFound      = 4,  // request was valid; resource simply does not exist
    Unauthorized     = 5   // access denied by a role check performed inside the service or
                           // repository layer — not by middleware. The caller was fully
                           // authenticated and reached the controller, but their application
                           // role does not permit access to this specific record or operation.
                           // This acts as a defence-in-depth guard for cases where the
                           // calling application did not pre-check roles before requesting.
}
```

### ApiResponse\<T\> Wrapper Class

```csharp
// {AppName}.Contracts/Responses/ApiResponse.cs
namespace {AppName}.Contracts.Responses;

public class ApiResponse<T>
{
    // ── Outcome ───────────────────────────────────────────────────────────────

    /// Status of the operation. Callers must check this, not the HTTP code,
    /// to determine whether usable data was returned.
    public ApiResultStatus Status { get; init; } = ApiResultStatus.Unknown;

    /// True when Status == Success and Data is not null.
    public bool IsSuccess => Status == ApiResultStatus.Success;

    /// True when data was returned. Callers may check this before accessing Data.
    public bool HasData => Data is not null;

    // ── The payload — exactly ONE typed property ──────────────────────────────

    /// The response payload. Null when Status is NoDataFound, Failure, or
    /// ValidationFailed. Always check HasData or Status before accessing.
    public T? Data { get; init; }

    // ── Request context — what was asked ──────────────────────────────────────

    /// The endpoint that produced this response, e.g. "GET /api/v1/coins/{coinGuid}".
    public string Endpoint { get; init; } = string.Empty;

    /// The key parameters that were passed with the request.
    /// Allows the consumer to confirm which record was queried without re-parsing the URL.
    public IReadOnlyDictionary<string, string> RequestKeys { get; init; }
        = new Dictionary<string, string>();

    // ── Response metadata — what happened ─────────────────────────────────────

    /// UTC timestamp of when this response was generated.
    public DateTime ResponseUtc { get; init; } = DateTime.UtcNow;

    /// Correlates this response to the server-side log entry. Include in support tickets.
    public string TraceId { get; init; } = string.Empty;

    /// Human-readable summary of the outcome, safe to display to end users.
    public string? Message { get; init; }

    /// Additional detail about a failure or validation error.
    /// Populated only when Status is Failure or ValidationFailed.
    public string? ErrorDetail { get; init; }

    /// Number of records in Data. 0 when no data was returned.
    /// For single-item responses this is 1 on success and 0 otherwise.
    public int RecordCount { get; init; }
}
```

### ApiResponse Factory (Static Helper)

All controllers create envelope instances through the factory. This prevents inconsistent field population and ensures `Endpoint`, `TraceId`, and `ResponseUtc` are never accidentally omitted.

```csharp
// {AppName}.API/Mapping/ApiResponseFactory.cs
namespace {AppName}.API.Mapping;

public static class ApiResponseFactory
{
    public static ApiResponse<T> Success<T>(T data, string endpoint,
        IReadOnlyDictionary<string, string> requestKeys, string traceId,
        int recordCount = 1) => new()
    {
        Status      = ApiResultStatus.Success,
        Data        = data,
        Endpoint    = endpoint,
        RequestKeys = requestKeys,
        TraceId     = traceId,
        RecordCount = recordCount,
        Message     = "Success"
    };

    public static ApiResponse<T> NoDataFound<T>(string endpoint,
        IReadOnlyDictionary<string, string> requestKeys, string traceId) => new()
    {
        Status      = ApiResultStatus.NoDataFound,
        Data        = default,
        Endpoint    = endpoint,
        RequestKeys = requestKeys,
        TraceId     = traceId,
        RecordCount = 0,
        Message     = "The requested resource was not found."
    };

    public static ApiResponse<T> Failure<T>(string message, string errorDetail,
        string endpoint, IReadOnlyDictionary<string, string> requestKeys,
        string traceId) => new()
    {
        Status      = ApiResultStatus.Failure,
        Endpoint    = endpoint,
        RequestKeys = requestKeys,
        TraceId     = traceId,
        RecordCount = 0,
        Message     = message,
        ErrorDetail = errorDetail
    };

    public static ApiResponse<T> ValidationFailed<T>(string detail, string endpoint,
        IReadOnlyDictionary<string, string> requestKeys, string traceId) => new()
    {
        Status      = ApiResultStatus.ValidationFailed,
        Endpoint    = endpoint,
        RequestKeys = requestKeys,
        TraceId     = traceId,
        RecordCount = 0,
        Message     = "The request could not be completed due to a validation error.",
        ErrorDetail = detail
    };

    // Raised when the service or repository layer determines that the authenticated
    // caller's application role does not permit access to the requested data.
    // This is never the result of a middleware decision; HTTP always returns 200.
    public static ApiResponse<T> Unauthorized<T>(string message, string endpoint,
        IReadOnlyDictionary<string, string> requestKeys, string traceId) => new()
    {
        Status      = ApiResultStatus.Unauthorized,
        Endpoint    = endpoint,
        RequestKeys = requestKeys,
        TraceId     = traceId,
        RecordCount = 0,
        Message     = message,
        ErrorDetail = "Your application role does not permit access to this resource."
    };
}
```

## Controller Structure

Every action method returns `Ok(ApiResponseFactory.{Method}(...))`. The HTTP status code is always `200 OK` for every business outcome. Non-200 codes are reserved exclusively for infrastructure failures that occur *before* the controller body executes.

```csharp
[ApiController]
[Route("api/v{version:apiVersion}/[controller]")]
[ApiVersion("1.0")]
[Authorize]
public class CoinsController(ICoinRepository coinRepository,
                              ILogger<CoinsController> logger) : ControllerBase
{
    private const string EndpointGetCoin = "GET /api/v1/coins/{coinGuid}";

    [HttpGet("{coinGuid:guid}")]
    public async Task<IActionResult> GetCoinAsync(Guid coinGuid)
    {
        var requestKeys = new Dictionary<string, string>
            { ["coinGuid"] = coinGuid.ToString() };

        var requestedCoin = await coinRepository.GetByGuidAsync(coinGuid);

        if (requestedCoin is null)
            return Ok(ApiResponseFactory.NoDataFound<CoinResponseDto>(
                EndpointGetCoin, requestKeys, HttpContext.TraceIdentifier));

        return Ok(ApiResponseFactory.Success(
            requestedCoin.ToResponseDto(),
            EndpointGetCoin, requestKeys, HttpContext.TraceIdentifier));
    }
}
```

### What the Consumer Receives (Example JSON)

```json
// Coin found — Status: Success
{
  "status":       "Success",
  "isSuccess":    true,
  "hasData":      true,
  "data":         { "coinGuid": "3fa85f64...", "name": "1921 Morgan Dollar", ... },
  "endpoint":     "GET /api/v1/coins/{coinGuid}",
  "requestKeys":  { "coinGuid": "3fa85f64..." },
  "responseUtc":  "2026-03-13T14:22:01Z",
  "traceId":      "0HN8K2V5VQE4G:00000001",
  "message":      "Success",
  "errorDetail":  null,
  "recordCount":  1
}

// Coin not found — Status: NoDataFound  (HTTP is still 200 OK)
{
  "status":       "NoDataFound",
  "isSuccess":    false,
  "hasData":      false,
  "data":         null,
  "endpoint":     "GET /api/v1/coins/{coinGuid}",
  "requestKeys":  { "coinGuid": "3fa85f64..." },
  "responseUtc":  "2026-03-13T14:22:01Z",
  "traceId":      "0HN8K2V5VQE4G:00000002",
  "message":      "The requested resource was not found.",
  "errorDetail":  null,
  "recordCount":  0
}
```

## HTTP Status Code Conventions

With the response envelope in place, HTTP status codes revert to their original purpose: describing the *transport and infrastructure* outcome, not the business outcome.

| Scenario | HTTP Code | Envelope `Status` | Notes |
|----------|-----------|-------------------|-------|
| Resource found | 200 OK | `Success` | Data payload is populated, RecordCount ≥ 1 |
| Resource not found | 200 OK | `NoDataFound` | Data is null, RecordCount = 0. **Never 404.** |
| Collection, results exist | 200 OK | `Success` | Data is the list, RecordCount = N |
| Collection, no results | 200 OK | `NoDataFound` | Data is null or empty list, RecordCount = 0. **Never 404.** |
| Create succeeded | 201 Created | `Success` | Include `Location` header with the new resource GUID URL |
| Update / delete succeeded | 200 OK | `Success` | Data contains the updated resource or confirmation |
| Business rule violated | 200 OK | `ValidationFailed` | ErrorDetail describes the rule. Distinct from HTTP 400 (model binding). |
| Data-level access denied | 200 OK | `Unauthorized` | The caller's application role was checked inside the service or repository layer — not by middleware — and does not permit this record or operation. HTTP remains 200. Distinct from HTTP 403, which fires before the controller body runs. |
| Server-side error | 200 OK | `Failure` | Message is user-safe. ErrorDetail contains the TraceId for log lookup. |
| Model binding / bad JSON | 400 Bad Request | N/A — envelope not reached | ASP.NET Core model validation fires before the controller body runs |
| Not authenticated | 401 Unauthorized | N/A — envelope not reached | JWT middleware fires before the controller body runs |
| Not authorised | 403 Forbidden | N/A — envelope not reached | Authorisation policy fires before the controller body runs |
| Unhandled exception | 500 | N/A — envelope not reached | Global exception middleware returns generic message + TraceId (see Chapter 15) |

> **⚠️ Two kinds of "not authorised" — they are not the same thing:** HTTP `401` and `403` are emitted by ASP.NET Core middleware *before* the controller body executes and therefore never produce an envelope. `ApiResultStatus.Unauthorized` is produced *inside* the controller body, by the service or repository layer, when a data-level role check fails; it always travels inside a `200 OK` envelope. Consumers must handle both shapes: envelope-based outcomes for all `200` responses and raw HTTP error codes for infrastructure failures. Document this distinction explicitly in the OpenAPI spec description for every endpoint.

## HTTP Response Code Rules — Auth Endpoints

The following table specifies the exact HTTP codes for all identity and account management endpoints (e.g., `/auth/*`, `/accounts/*`). This follows the envelope pattern where HTTP codes communicate transport-level outcomes; business outcomes are communicated entirely via the envelope.

| Outcome | HTTP Code | Envelope Status | Scenario | Notes |
|---------|-----------|-----------------|----------|-------|
| ✅ Success | **200 OK** | `Success` | Register, login, refresh, logout, password reset, email change, account query | Envelope contains response data (tokens, account details, etc.) |
| ❌ Business rule violation | **200 OK** | `ValidationFailed` | Age < 16, email already registered, password too weak, lockout active | Not a request format error; HTTP 400 is not used |
| ❌ Resource not found | **200 OK** | `NoDataFound` | Account lookup returns no results | Resource missing is a business outcome, not HTTP error |
| ❌ Server operation failed | **200 OK** | `Failure` | Database write error, email service unavailable (non-critical), unexpected condition | Recoverable error; full details logged server-side; user-safe message in envelope |
| ❌ Access denied (data-level) | **200 OK** | `Unauthorized` | User's role checked inside service layer and lacks permission for this record/operation | Distinct from middleware 403; authenticated but not authorized for this data |
| 🚫 Bad request format | **400 Bad Request** | N/A — envelope not reached | Invalid JSON, missing required field, type mismatch | ASP.NET Core model binding validates before controller body executes |
| 🚫 Not authenticated | **401 Unauthorized** | N/A — envelope not reached | Missing or invalid JWT bearer token | JWT middleware validates before controller body executes |
| 🚫 Not authorised (middleware) | **403 Forbidden** | N/A — envelope not reached | `[Authorize(Policy="...")]` policy fails before controller body executes | Distinct from data-level `Unauthorized` in envelope |
| 🚫 Rate limit exceeded | **429 Too Many Requests** | N/A — envelope not reached | Login, register, or refresh attempts exceed per-endpoint threshold | Include `Retry-After` header with seconds until next attempt |
| 🚫 Server error | **500 Internal Server Error** | N/A — envelope not reached | Unhandled exception in middleware or controller | Global exception middleware catches and logs with TraceId |

**Key Rule:** All authentication and account endpoints return **200 OK for all business outcomes** (success, validation failure, access denied at data level, resource not found). The envelope status field communicates the outcome to the caller. HTTP codes communicate *infrastructure* outcomes only (request format, authentication, authorization policy, rate limit, server crash).

## API Design Rules

- **MUST** Every controller action returns `Ok(ApiResponseFactory.{Method}(...))`. Never return `NotFound()`, `NoContent()`, or a raw DTO directly from a controller action. The envelope is the contract.
- **MUST** `ApiResponse<T>` and `ApiResultStatus` live in `{AppName}.Contracts/Responses/`. They must have zero dependencies on `Microsoft.AspNetCore.*` so that MAUI can consume them without a web framework reference.
- **MUST** `ApiResponseFactory` lives in `{AppName}.API/Mapping/` and is the only permitted way to construct `ApiResponse<T>` instances in controller code.
- **MUST** `RequestKeys` must include every route parameter and significant query parameter so that the consumer can confirm exactly which resource was queried without re-parsing the URL.
- **MUST** Route parameters use the GUID: `/api/v1/coins/{coinGuid}`. Never expose integer IDs in routes or in `RequestKeys`.
- **MUST** Never return the domain entity directly. Always map to a response DTO, then wrap in the envelope.
- **MUST** Service and repository methods that return role-restricted data must evaluate the caller's application role internally. When access is denied at the data level, they must surface this so the controller calls `ApiResponseFactory.Unauthorized`. The data layer must never assume the calling application pre-checked roles — this is a required defence-in-depth guard.
- **SHOULD** For paginated list endpoints, wrap results in `PagedResultDto<T>`.
- **SHOULD** Mark public endpoints with `[AllowAnonymous]` explicitly rather than relying on the absence of `[Authorize]`.
- **SHOULD** Enable CORS explicitly with named origins. Never use wildcard (`*`) origins in production.
- **SHOULD** Include the endpoint string constant (e.g., `private const string EndpointGetCoin = "GET /api/v1/coins/{coinGuid}"`) as a `private const` at the top of each controller class to avoid magic strings in every action method.
