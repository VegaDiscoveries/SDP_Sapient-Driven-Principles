# Chapter 14 — Configuration & Secrets

> *Section file for `GenericProjectGuidlines_V1.10_20260323.md`*
>
> **⚠️ Sync rule — agent instruction:** This is a section file. Any change made here **must be mirrored in the corresponding chapter** of `GenericProjectGuidlines_V1.10_20260323.md`. Any change made in the parent document's corresponding chapter must be mirrored back here. Both files must remain identical in content for their shared sections.
>
> **TOC Maintenance:** If this section is renamed or deleted, update both the parent document's Contents list AND the `GenericProjectGuidlines_TOC.md` file. See the TOC file for detailed maintenance instructions.

---

Configuration is layered: base `appsettings.json` holds non-sensitive defaults; environment files override them; credentials are never committed to source control under any circumstances.

## Configuration File Hierarchy

| File | Committed? | Contains |
|------|------------|----------|
| `appsettings.json` | Yes | Log levels, feature flags, pagination defaults, app name/version, supported cultures |
| `appsettings.Development.json` | Yes | Developer-friendly overrides: verbose logging, exception pages |
| `appsettings.Production.json` | Yes | Production non-sensitive overrides. No credentials. |
| User Secrets | Never | Runtime connection strings (`AppDb`, `IdentityDb`), migration connection strings (`MigrationsDb`, `MigrationsIdentityDb`), JWT secret, email credentials |
| Environment variables | N/A | CI/CD and server runtime secrets. Override any `appsettings` value. |
| Key Vault / Secrets Manager | N/A | Production-grade secret store for hosted environments |

## Strongly-Typed Configuration

```csharp
// Program.cs — bind config sections to typed classes
builder.Services.Configure<JwtConfig>(builder.Configuration.GetSection("JwtConfig"));
builder.Services.Configure<DebuggingConfig>(builder.Configuration.GetSection("Debugging"));

// Usage via IOptions — never read IConfiguration by magic string in business logic
public class AuthService(IOptions<JwtConfig> jwtOptions) { ... }
```

## Configuration Rules

- **MUST** Connection strings, JWT secrets, and API keys are never in any committed file.
- **MUST** Both `.gitignore` and `.copilotignore` list all credential-containing files.
- **MUST** Use `env.IsDevelopment()` for debug-mode toggles. Never use a hardcoded `static bool DebugMode = true` field.
- **SHOULD** Validate required config on startup: `services.AddOptions<T>().ValidateDataAnnotations().ValidateOnStart()` so missing secrets fail immediately at launch.
- **MUST** Maintain four named connection strings: `ConnectionStrings:AppDb` and `ConnectionStrings:IdentityDb` (runtime, minimal permissions) and `ConnectionStrings:MigrationsDb` and `ConnectionStrings:MigrationsIdentityDb` (elevated, deploy-time only, never read by the running application). All four live in User Secrets locally; `AppDb` and `IdentityDb` are injected as environment variables in production; `MigrationsDb` and `MigrationsIdentityDb` are injected only in the CI/CD pipeline migration step and are absent from the running application's environment.

> **Addition — 2026-07-24 — Log retention setting:** The `appsettings.json` row's "Log levels"
> content extends to log retention: `Logging:RetentionDays` (or equivalent key) is a non-sensitive
> default belonging in `appsettings.json`, per Chapter 6's log rotation/retention rule.
