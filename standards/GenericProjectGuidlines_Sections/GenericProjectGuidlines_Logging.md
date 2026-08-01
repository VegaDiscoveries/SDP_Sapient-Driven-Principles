# Chapter 6 — Logging

> *Section file for `GenericProjectGuidlines_V1.10_20260323.md`*
>
> **⚠️ Sync rule — agent instruction:** This is a section file. Any change made here **must be mirrored in the corresponding chapter** of `GenericProjectGuidlines_V1.10_20260323.md`. Any change made in the parent document's corresponding chapter must be mirrored back here. Both files must remain identical in content for their shared sections.
>
> **TOC Maintenance:** If this section is renamed or deleted, update both the parent document's Contents list AND the `GenericProjectGuidlines_TOC.md` file. See the TOC file for detailed maintenance instructions.

---

Structured logging must be configured from day one. `Console.WriteLine` is not acceptable in any project tier. Every log entry must carry enough context to reconstruct what happened without a debugger.

## Logging Provider

Use **NLog** or **Serilog** wired into `Microsoft.Extensions.Logging`. All application code uses `ILogger<T>` exclusively — never a static logger reference.

```csharp
// Program.cs — NLog setup
builder.Logging.ClearProviders();
builder.Logging.SetMinimumLevel(LogLevel.Information);
builder.Host.UseNLog();
```

## Log Level Guide

| Level | Use For | Enabled In |
|-------|---------|------------|
| `Trace` | Raw HTTP bodies, SQL parameters | Development only |
| `Debug` | Method flow, variable values | Development only |
| `Information` | Normal milestones: user logged in, record saved | All environments |
| `Warning` | Unexpected but recoverable: deprecated version called, retry | All environments |
| `Error` | Single-operation failures: DB save failed, API timeout | All environments |
| `Critical` | Application-threatening failures: cannot connect to DB on startup | All environments |

## Logging Rules

- **MUST** Use structured templates with named placeholders: `_logger.LogInformation("User {UserId} logged in from {IpAddress}", userId, ip)`
- **MUST** Never use string interpolation in log calls. It defeats structured log indexing.
- **MUST** Never log passwords, JWT secrets, connection strings, or refresh token values at any log level.
- **MUST** Log at `Error` level (not `Warning`) whenever an exception is caught and not re-thrown.
- **SHOULD** Include a correlation / request trace ID in every entry so that all log lines for a single HTTP request can be grouped.
- **SHOULD** Log application name, version, and environment at `Information` on startup.
- **SHOULD** Configure at minimum two targets: rolling file (persistence) and console (development).

> **⚠️ Never do this:** `_logger.LogDebug($"Connection: {connectionString}")` — connection strings contain credentials.

> **Addition — 2026-07-24 — Log file rotation and retention:**
>
> - **MUST** The rolling file target writes one log file per calendar day, named with an
>   embedded `yyyyMMdd` date segment (e.g. `log-20260724.log`). All entries for that day append
>   to the same file.
> - **MUST** Retention is a configured number of days, never hardcoded. Read it from
>   `appsettings.json` via strongly-typed configuration (see Chapter 14) — e.g.
>   `Logging:RetentionDays`. Files older than the configured window are removed automatically by
>   the provider's own archival mechanism: NLog's `archiveEvery="Day"` + `archiveNumbering="Date"`
>   + `maxArchiveFiles` bound to the config value, or Serilog's
>   `rollingInterval: RollingInterval.Day` + `retainedFileCountLimit` bound to the config value.
> - **SHOULD** Default `RetentionDays` to a conservative value (e.g. `30`) in `appsettings.json`,
>   overridable per environment via `appsettings.{Environment}.json`.
