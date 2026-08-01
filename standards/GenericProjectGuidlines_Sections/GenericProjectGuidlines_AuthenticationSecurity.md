# Chapter 5 — Authentication & Security

> *Section file for `GenericProjectGuidlines_V1.10_20260323.md`*
>
> **⚠️ Sync rule — agent instruction:** This is a section file. Any change made here **must be mirrored in the corresponding chapter** of `GenericProjectGuidlines_V1.10_20260323.md`. Any change made in the parent document's corresponding chapter must be mirrored back here. Both files must remain identical in content for their shared sections.
>
> **TOC Maintenance:** If this section is renamed or deleted, update both the parent document's Contents list AND the `GenericProjectGuidlines_TOC.md` file. See the TOC file for detailed maintenance instructions.

---

Authentication is implemented once, in the API, using JWT bearer tokens. This single implementation serves the website (via stored tokens or a thin cookie wrapper), the mobile app (via secure OS storage), and any future third-party integrations without redesign.

## JWT Bearer Tokens

```csharp
// Program.cs — token validation (correct for all client types)
var tokenValidationParameters = new TokenValidationParameters
{
    ValidateIssuerSigningKey = true,
    IssuerSigningKey         = new SymmetricSecurityKey(Encoding.ASCII.GetBytes(jwtSecret)),
    ValidateIssuer           = false,
    ValidateAudience         = true,
    ValidAudience            = jwtConfig.Audience,  // solution-specific audience identifier
    ValidateLifetime         = true,
    RequireExpirationTime    = true,
    ClockSkew                = TimeSpan.Zero  // no grace period on expiry
};
```

Every solution validates tokens against its own `AudienceIdentifier`, ensuring a token issued for one Vega Discoveries solution is rejected by all others and that an explicit login is required per solution.

## Shared Identity Database & Solution Registry

For Vega Discoveries projects the Identity database is shared across all solutions. Each solution is registered in the `RegisteredSolutions` table, which is the authority for valid audience identifiers and enables per-solution credential and token scoping.

```
RegisteredSolutions
├── SolutionID            INT IDENTITY PK
├── SolutionGUID          UNIQUEIDENTIFIER DEFAULT newid()
├── Name                  NVARCHAR(255)   e.g. "BookVault"
├── AudienceIdentifier    NVARCHAR(255)   e.g. "vegadiscoveries.bookvault"
│                                         stamped into the JWT aud claim on login
└── + CommonColumns
```

The `AudienceIdentifier` is stored in each solution's `appsettings.json` (non-sensitive) and bound via `IOptions<JwtConfig>`. The JWT secret remains in User Secrets / environment variables only.

## Per-Solution Passwords

Each user has a single `AspNetUsers` record as their identity anchor. Login passwords are stored per solution in `UserSolutionCredential`. The standard `AspNetUsers.PasswordHash` column is repurposed to store the **Reset PIN hash** — a global recovery credential set once at first registration, never used during any login flow.

### UserSolutionCredential Table

```
UserSolutionCredential         one row per user per solution
├── UserSolutionCredentialID   INT IDENTITY PK
├── UserSolutionCredentialGUID UNIQUEIDENTIFIER DEFAULT newid()
├── UserID                     FK → AspNetUsers
├── SolutionID                 FK → RegisteredSolutions
├── PasswordHash               solution-specific login password hash
├── FailedAttemptCount         lockout tracked independently per solution
├── LockoutEnd                 solution-scoped lockout expiry (UTC)
├── LastPasswordChangedDate    UTC timestamp of last password change
└── + CommonColumns
UNIQUE constraint on (UserID, SolutionID)
```

### AspNetUsers.PasswordHash — Repurposed as Reset PIN

The Reset PIN is:
- Set once by the user at first registration on any Vega Discoveries solution
- Stored as a bcrypt hash in `AspNetUsers.PasswordHash`
- Never read during a login attempt on any solution
- Used exclusively as a second validation factor during the password reset flow
- Changeable only by providing the current Reset PIN — never via an email link alone

Users must be clearly instructed not to reuse a solution password as their Reset PIN.

## Registration Flow

**First registration (user's first Vega Discoveries solution):**
1. User registers on Solution A — provides email, solution password, and Reset PIN
2. `AspNetUsers` row created in the identity DB — `PasswordHash` stores the hashed Reset PIN; `NormalizedEmail` stored as lowercase
3. `UserSolutionCredential` row created for Solution A — stores the solution password hash
4. `User` row created in the **app DB** — `Email` set to lowercase email (matching `AspNetUsers.NormalizedEmail`). Immediately after, a `UserRole` row is inserted assigning the project-defined default role (defined in the project documentation). Steps 2–4 are committed as separate transactions with compensating rollback: if any app DB insert fails, the identity DB rows created in steps 2–3 are rolled back.

**Subsequent registration (user joins a second solution later):**
1. Email lookup finds the existing `AspNetUsers` row
2. User sets a solution password for Solution B
3. New `UserSolutionCredential` row created for Solution B
4. `AspNetUsers.PasswordHash` (Reset PIN) is not changed

## Password Reset Flow

Password resets use a short-lived **signed JWT reset token** embedded in the reset URL. The built-in `exp` claim prevents reset links from living indefinitely. The token is signed with the server's existing JWT secret — no additional key infrastructure is required.

```
1.  User requests password reset for Solution A

2.  User is challenged for their Reset PIN
    2a. PIN valid:
        — Server generates a signed JWT reset token:
              { "sub":          "<userId>",
                "resetPinHash": "<current AspNetUsers.PasswordHash>",
                "solutionId":   "<SolutionGUID>",
                "purpose":      "password-reset",
                "jti":          "<unique token id>",
                "exp":          <now + 20 minutes> }
              Signed with the server JWT secret
        — Token embedded in the reset URL
        — Reset link sent to the user's registered email address
        — User shown confirmation screen with options:
              [ Resend Email ]  [ Contact Support ]  [ Back to Login ]

    2b. PIN invalid:
        — User notified that the Reset PIN was not recognised
        — Prompted to contact support
        — No email sent

3.  User clicks the reset link — reset form requests new solution password only

4.  Server validates the JWT reset token:
        i.   Signature valid
        ii.  exp claim not expired (≤ 20 minutes)
        iii. purpose claim == "password-reset"
        iv.  resetPinHash claim matches current AspNetUsers.PasswordHash
             (mismatch: Reset PIN changed after link was issued — link rejected)
        v.   jti not in ConsumedResetTokens (single-use check)
        — Any failed check rejects with a generic error; no reason given to caller

5.  All checks pass:
        — UserSolutionCredential.PasswordHash updated for Solution A only
        — jti recorded in ConsumedResetTokens to prevent replay

6.  All other solution credentials untouched
```

## Refresh Tokens

Access tokens are short-lived (15–60 minutes). Refresh tokens allow clients to obtain new access tokens silently. Each refresh token is stored in the database, tied to a device fingerprint, and rotated on every use.

- Refresh token entity lives in `Domain/Entities/RefreshToken.cs` and inherits `CommonColumns`
- Fields: `UserId`, `JwtId`, `Token` (hashed), `ExpiryDate`, `IsUsed`, `IsRevoked`, `IpAddress`, `DeviceIdentifier`
- On use: mark old token `IsUsed = true`, issue a new refresh token (rotation)
- On logout: set `IsRevoked = true` for all tokens belonging to that user on that device

## Token Lifetime Defaults

Framework-level baselines for all solutions. Solutions may tighten (shorten) these values by documenting the override in the project documentation. Relaxing a default beyond these baselines requires architectural review.

| Token Type | Default Lifetime | Notes |
|------------|-----------------|-------|
| Access token | 15 minutes | Short-lived; renewed via refresh token |
| Refresh token | 30 days | Rotated on every use; revocable per-device |

- **MUST** `ClockSkew = TimeSpan.Zero` on all `TokenValidationParameters` — no grace period is applied on top of the configured lifetime.
- **SHOULD** Access token lifetime is chosen to minimize the stolen-token exposure window without forcing excessive refresh requests.
- **SHOULD** Refresh token lifetime balances session usability against the risk window of a long-lived stolen token.
- **SHOULD** Where regulatory compliance mandates shorter lifetimes, the stricter value always takes precedence and must be documented.

## Account Lockout Baselines

Framework-level defaults for brute-force protection. Solutions may tighten these values by documenting the override in the project documentation. Relaxing a default requires architectural review.

| Parameter | Default | Notes |
|-----------|---------|-------|
| Failed attempt threshold | 5 attempts | Counted within the rolling window below |
| Rolling window | 30 minutes | Attempts older than 30 min are not counted toward the threshold |
| Lockout duration | 30 minutes | Fixed; non-escalating |
| Counter reset | 24 hours | Nightly job resets `FailedLoginAttempts` for records with no failure in the past 24 hours |

**Scope:** Lockout is per-solution. A lockout on Solution A does not affect the user's access to Solution B.

**Override support:** Per-solution limits are stored in `RegisteredSolutions` or equivalent configuration, enabling ops to tighten thresholds without code deployment.

- **MUST** Lockout state is tracked in `UserSolutionCredential` (`FailedLoginAttempts`, `LastFailedLoginDateUtc`, `LockoutEndDateUtc`).
- **MUST** On successful login: reset `FailedLoginAttempts = 0` and `LockoutEndDateUtc = NULL`.
- **MUST** The locked-out user receives a generic message: "Account is temporarily locked due to multiple failed login attempts. Please try again later." No threshold values are disclosed to the caller.
- **MUST** Manual lockout unlock via the Admin Panel clears `LockoutEndDateUtc` and `FailedLoginAttempts` for the specific user/solution pair.
- **SHOULD** Alert on more than 10 lockout events for the same account within 24 hours — this pattern indicates a credential-stuffing attack.

## Rate Limiting Architecture

Use `SlidingWindowRateLimiter` (ASP.NET Core built-in) for all auth endpoints. Sliding window is preferred over fixed window for bursty traffic because it prevents bunching at window boundaries.

### Default Policies

| Endpoint | Permit Limit | Window | Segmented by |
|----------|-------------|--------|--------------|
| `POST /auth/login` | 5 attempts | 15 minutes | Per IP |
| `POST /auth/register` | 10 attempts | 60 minutes | Per IP |
| `POST /auth/refresh` | 30 attempts | 60 minutes | Per token |
| `POST /auth/forgot-password` | 3 attempts | 60 minutes | Per email |

### Per-Solution Override Pattern

Policies are stored in the `API_RateLimitPolicy` table. A `NULL` `RegisteredSolutionId` is the system default; a non-null `RegisteredSolutionId` is a solution-specific override. At request time, the solution-specific policy is used if present; otherwise the system default is applied.

This enables ops to tighten or adjust limits per-solution without code changes or redeployment.

### Cache Strategy

- Load all active policies into memory at startup.
- Background job refreshes the cache every 5 minutes.
- No database query on the per-request hot path.
- Changes take effect within the next cache refresh cycle.

### Rules

- **MUST** Rate-limited responses return `429 Too Many Requests` with a `Retry-After` header. Never return `200 OK` for a rate-limited request.
- **MUST** All rate limit policies are stored in `API_RateLimitPolicy` and loaded via the cache. Hard-coded limits in middleware are not permitted.
- **SHOULD** Alert on more than 100 rate-limit hits from a single IP within 1 hour — this pattern indicates credential-stuffing or DDoS.
- **SHOULD** Correlate rate-limit hit events with account lockout events in security monitoring.

## JWKS Endpoint & Key Rotation

VegaIdentity.API is the sole JWT issuer. All consumer APIs (solution APIs) validate tokens using RS256 public keys discovered via the JWKS endpoint — they never hold private keys.

### JWKS Endpoint

| Property | Value |
|----------|-------|
| Path | `/.well-known/jwks.json` |
| Cache-Control | `public, max-age=300` (5-minute TTL) |
| Algorithm | RS256 |
| Key ID format | `rsa_YYYY_qN` (e.g., `rsa_2026_q2`) |

The `kid` claim is stamped into every JWT header and matched against the JWKS at validation time, allowing consumer APIs to select the correct public key without iterating the full set.

### Key Rotation Process

1. Generate a new RSA key pair.
2. Insert the new public key into `API_SigningKey` with `IsCurrent = 1`; set the old key to `IsCurrent = 0`.
3. The JWKS endpoint immediately serves both keys — the overlap window begins.
4. After 30 days: set `DeprecatedAfterUtc` on the old key. It is automatically excluded from the JWKS on the next query.
5. No app restart required. Consumer APIs pick up the new key within their next cache refresh (≤ 5 minutes).

**Overlap window: 30 days.** This ensures all in-flight tokens signed with the old key remain valid throughout their lifetime before the old key is retired.

### Consumer API Discovery Strategy

1. Fetch JWKS on startup; cache in memory.
2. Refresh cache every 5 minutes via background timer.
3. On JWT validation failure where `kid` is not in the cached set: refetch JWKS immediately, then retry. This handles the race condition during rotation where a new token arrives before the cache has refreshed.

### Rules

- **MUST** The JWKS endpoint exposes public keys only. Private keys must never appear in any API response.
- **MUST** Every issued JWT includes a `kid` header claim matching the signing key's `KeyId`.
- **MUST** Consumer APIs use the `kid` claim to select the correct key from the cached JWKS — never iterate-and-try-all.
- **MUST** Alert if `API_SigningKey` has no row with `IsCurrent = 1` — this indicates a failed rotation that must be resolved immediately.
- **SHOULD** Rotate signing keys at least quarterly. Document rotation events in the audit log.

## Client-Side Token Storage Strategies

Token storage strategy must be chosen deliberately before web client implementation. The wrong choice trades security for convenience in ways that are difficult to retrofit.

### Storage Options Summary

| Method | XSS Risk | CSRF Risk | Survives Refresh | Notes |
|--------|----------|-----------|-----------------|-------|
| `localStorage` (plain) | **High** | None | Yes | Plaintext token accessible to any JS |
| `sessionStorage` (plain) | **High** | None | No | Lost on tab close or page refresh |
| In-memory only | None | None | **No** | Lost on every page refresh |
| HttpOnly cookie | None | Moderate | Yes | CSRF-protected by `SameSite=Strict`; limits external link UX |
| `localStorage` (encrypted) | Mitigated | None | Yes | **Recommended for web clients** |

### Recommended Strategy — Encrypted localStorage with Replay Detection

Issue encrypted (non-deterministic AES-GCM) access tokens from the API. The web client stores the encrypted blob in `localStorage`; the plaintext never touches the client. The server decrypts, validates, and marks each token as consumed on first use.

**Why this works:**
- A stolen encrypted token cannot be decrypted by the attacker (server-only decryption key).
- Non-deterministic encryption means the same plaintext produces different ciphertext each time — the attacker cannot re-create or verify the token.
- First use consumes the token. Any replay triggers a security alert and rejection. Damage from a single XSS theft is limited to one request.

**Client storage call:**
```js
localStorage.setItem('accessToken', encryptedToken);
// Authorization header on each request:
Authorization: Bearer {encryptedToken}
```

### Mobile Clients

MAUI and other mobile clients use secure OS storage (Keychain on iOS, Keystore on Android). The HttpOnly cookie and localStorage strategies do not apply. Never use `localStorage` patterns in mobile client code.

### Rules

- **MUST** Web clients store only the encrypted token blob — never the plaintext JWT.
- **MUST** Each encrypted token is single-use. Server marks it consumed on first validation; any subsequent use is a replay and is rejected.
- **MUST** Replay attempts are logged and trigger a security alert.
- **MUST NOT** Store plaintext JWTs in `localStorage` or `sessionStorage`.
- **SHOULD** On replay detection, revoke the user's active refresh tokens and force re-authentication.

## SMS Verification via Email-to-SMS Gateways

SMS verification codes are used for Multi-Factor Authentication (MFA) and password reset flows. This section specifies how to integrate SMS delivery without third-party providers.

### When to Use This Pattern

Use email-to-SMS carrier gateways to deliver SMS codes when:
- Cost control is important (zero API fees, reuses existing email infrastructure)
- International scope is limited to known carriers
- Marketing or high-volume SMS is not needed (security codes only)
- Existing SMTP infrastructure is already operational

**Do NOT use this pattern for:** Marketing campaigns, two-way SMS, high-volume notifications, or custom sender IDs.

### How It Works

Major cellular carriers provide email-to-SMS gateways that automatically convert email to SMS:
- Verizon: `[10-digit-number]@vtext.com` → SMS
- AT&T: `[10-digit-number]@txt.att.net` → SMS
- T-Mobile: `[10-digit-number]@tmomail.net` → SMS
- US Cellular: `[10-digit-number]@mms.uscc.net` → SMS
- (Additional carriers: Rogers, Bell, Telstra, etc. per country)

The system constructs a carrier gateway email address from the user's phone number and carrier selection, then sends it via the existing `IEmailService`. The carrier gateway transparently converts the email to an SMS message. No API integration or rate limits apply.

### Required Schema

**UserPhoneNumber** — Stores verified and unverified phone numbers per user

```sql
CREATE TABLE [UserPhoneNumber] (
    [UserPhoneNumberId] INT PRIMARY KEY IDENTITY(1,1),
    [UserPhoneNumberGuid] UNIQUEIDENTIFIER NOT NULL UNIQUE DEFAULT newid(),
    [UserId] NVARCHAR(128) NOT NULL FOREIGN KEY REFERENCES [AspNetUsers]([Id]),
    [PhoneNumber] NVARCHAR(20) NOT NULL,  -- Normalized: digits only
    [Carrier] NVARCHAR(50) NOT NULL,      -- "verizon", "att", "tmobile", etc.
    [CarrierCountry] NVARCHAR(2) NOT NULL DEFAULT 'US',  -- ISO 3166-1 alpha-2
    [IsVerified] BIT NOT NULL DEFAULT 0,  -- Code verification completed
    [VerifiedDateUtc] DATETIME2 NULL,
    [IsPreferred] BIT NOT NULL DEFAULT 0, -- Primary number for MFA
    [IsSmsEnabled] BIT NOT NULL DEFAULT 1,-- User can disable SMS to this number
    -- CommonColumns (Name, Description, CreatedDate, CreatedUser, LastUpdatedDate, 
    -- LastUpdatedUser, IsActive, SortOrder, IsDeleted, DeletedDate, DeletedUser)
);

CREATE INDEX [IX_UserPhoneNumber_UserId_IsPreferred] 
    ON [UserPhoneNumber]([UserId], [IsPreferred]) 
    WHERE [IsVerified] = 1 AND [IsSmsEnabled] = 1;
CREATE INDEX [IX_UserPhoneNumber_UserId_IsVerified] 
    ON [UserPhoneNumber]([UserId], [IsVerified]);
```

**SmsCarrier** — Reference table for carrier-to-gateway mapping

```sql
CREATE TABLE [SmsCarrier] (
    [SmsCarrierId] INT PRIMARY KEY IDENTITY(1,1),
    [CarrierCode] NVARCHAR(50) NOT NULL UNIQUE,  -- "verizon", "att", "tmobile"
    [CarrierName] NVARCHAR(255) NOT NULL,        -- "Verizon Wireless"
    [CountryCode] NVARCHAR(2) NOT NULL,          -- "US"
    [EmailGateway] NVARCHAR(100) NOT NULL,       -- "vtext.com"
    [CharacterLimit] INT DEFAULT 160,            -- SMS character limit
    [IsActive] BIT NOT NULL DEFAULT 1,
    -- CommonColumns
);

-- Seed data: US, CA, AU carriers (extensible for others)
INSERT INTO [SmsCarrier] ([CarrierCode], [CarrierName], [CountryCode], [EmailGateway], 
                          [CharacterLimit], [Name], [SortOrder])
VALUES 
  ('verizon', 'Verizon Wireless', 'US', 'vtext.com', 160, 'Verizon', 10),
  ('att', 'AT&T Wireless', 'US', 'txt.att.net', 160, 'AT&T', 20),
  ('tmobile', 'T-Mobile US', 'US', 'tmomail.net', 160, 'T-Mobile', 30),
  ('uscc', 'US Cellular', 'US', 'mms.uscc.net', 160, 'US Cellular', 40),
  ('rogers', 'Rogers Wireless', 'CA', 'pcs.rogers.com', 160, 'Rogers', 50),
  ('bell', 'Bell Wireless', 'CA', 'txt.bell.ca', 160, 'Bell', 60),
  ('telstra', 'Telstra Wireless', 'AU', 'telstra.com.au', 160, 'Telstra', 70);
```

### Service Implementation Pattern

```csharp
public interface ISmsService
{
    Task<SmsResult> SendVerificationCodeAsync(string userId, string code, string codeType);
    Task<SmsResult> SendToPhoneAsync(string phoneNumber, string carrier, string countryCode, 
                                      string body, Guid? solutionId = null);
}

public class SmsService : ISmsService
{
    private readonly IEmailService _emailService;
    
    public async Task<SmsResult> SendVerificationCodeAsync(string userId, string code, 
                                                           string codeType)
    {
        // 1. Look up user's preferred phone from UserPhoneNumber table
        // 2. Validate phone is verified and SMS is enabled
        // 3. Look up carrier gateway email from SmsCarrier table
        // 4. Construct SMS recipient: "[phonenumber]@[carrier-gateway]"
        // 5. Delegate to IEmailService.SendAsync() with carrier gateway email
        // 6. Return SmsResult with success status and the email address used
    }
}
```

### Phone Number Registration & Verification Flow

**Step 1 — Register Phone**
```
POST /api/v1/accounts/add-phone
{ "phoneNumber": "2025551234", "carrier": "verizon", "carrierCountry": "US" }

Response: { "userPhoneNumberGuid": "...", "verificationCodeSent": true }
```

Server generates a 6-digit verification code and sends it as SMS to the carrier gateway email.

**Step 2 — Verify Phone**
```
POST /api/v1/accounts/verify-phone
{ "userPhoneNumberGuid": "...", "verificationCode": "654321" }

Response: { "isVerified": true, "isPreferred": true }
```

Server validates the code and marks the UserPhoneNumber row as verified. If this is the user's first verified phone, it is automatically marked as preferred.

**Step 3 — Use for MFA**

On login, if MFA is enabled and the user has a verified phone, they are prompted to select the MFA channel (SMS or Email). See **## Multi-Factor Authentication (MFA) Strategy** below.

### Tradeoffs

**Advantages:**
- ✅ Zero cost — leverages existing email infrastructure; no Twilio/AWS fees
- ✅ No new dependencies — no API credentials to manage
- ✅ Instant delivery — same SMTP latency as email
- ✅ Carrier SLAs — Verizon, AT&T, T-Mobile provide 24/7 infrastructure

**Disadvantages:**
- ❌ User must know their carrier (or auto-detect by area code)
- ❌ 160-character limit (adequate for 6-digit codes, limiting for longer messages)
- ❌ Sender ID is the email address, not customizable
- ❌ No delivery receipts or two-way messaging
- ❌ International complexity — different gateways per country

### Rules

- **MUST** SMS is used for security codes only (MFA, password reset). Not for marketing, alerts, or notifications.
- **MUST** Phone numbers are normalized to digits only; no formatting stored.
- **MUST** Carrier gateways are one-way; do not rely on delivery receipts.
- **MUST** Code lifetime is 5–10 minutes (project-specific, documented in project guidelines).
- **MUST** Codes are single-use; a second attempt generates a new code and re-sends it.
- **MUST** If SMS delivery fails (invalid phone, carrier gateway down, etc.), offer email fallback immediately.
- **SHOULD** Start with US, CA, AU carriers; extend via the extensible `SmsCarrier` seed table for other countries.
- **SHOULD** A user can disable SMS to a specific phone without deleting the record (`IsSmsEnabled = 0`).

## Multi-Factor Authentication (MFA) Strategy

MFA adds a second verification factor for sensitive operations. Two channels are supported: email (primary) and SMS (optional). This section specifies MFA strategy, flow, and channel selection.

### MFA Scope

MFA is required for:
- Login (if MFA is enabled for the account)
- Password reset (always, as second factor after PIN validation)
- Email change (always, as account-level operation)
- Sensitive admin actions (admin-configurable)

### Email MFA — Primary Channel

- **Default:** All users have email MFA enabled by default
- **Mechanism:** One-time code or signed link sent to registered email
- **Infrastructure:** Reuses existing email service and email verification token pattern
- **Enrollment:** Automatic; no user action required beyond email address registration
- **Recovery:** Always available if SMS fails or is unavailable

See **## Email Verification Token Lifecycle** for email token design and lifecycle.

### SMS MFA — Secondary Channel

- **Enrollment:** Requires phone number registration and code-based verification
- **Availability:** Only available if user has at least one verified phone number marked as enabled
- **Mechanism:** SMS sent via email-to-SMS carrier gateway (see **## SMS Verification via Email-to-SMS Gateways**)
- **User Choice:** If user has both email and verified phone, they select the channel at login time

### MFA Login Flow

```
1. User submits credentials (email + password)
2. Validation:
   a. Email and password match a UserSolutionCredential row
   b. Account is not locked out
   c. Account is active and not suspended
3. If MFA is enabled for this account:
   a. Server checks: does user have verified phone AND is SMS enabled on preferred phone?
   b. If YES: prompt user to select channel:
      [ Send SMS to preferred phone ]  [ Send email instead ]
   c. User selects channel
   d. Send code to selected channel
   e. Return { status: "MfaChallengeRequired", mfaSessionId: "..." }
4. Client presents code entry form
5. User enters code: POST /auth/verify-mfa [MfaSessionId] { code }
6. Server validates:
   a. Code matches the sent code
   b. Code has not expired (5–10 minute window)
   c. Code has not been used yet (single-use)
   d. mfaSessionId is valid and not expired
7. On success: Issue access token + refresh token
8. On failure: Return error; user can resend code or retry
```

### Code Delivery Rules

- **MUST** SMS code is 6 digits (easier for users; adequate entropy for short lifetime)
- **MUST** Email code is alphanumeric (7+ characters; higher entropy for longer validity windows)
- **MUST** Code lifetime is 5–10 minutes; project documentation specifies the value
- **MUST** Codes are single-use. A second submission attempt generates and sends a new code, invalidating the prior code
- **MUST** If SMS delivery fails (carrier down, invalid phone, etc.), immediately retry as email
- **MUST** A code sent via one channel cannot be verified via the other channel

### Resend Strategy

- First resend: Immediate (no delay)
- Second resend: 30-second delay (prevents brute-force code enumeration)
- Third resend: Requires support contact (prevents abuse; user is directed to support)

### Rules

- **MUST** MFA is always channel-optional. A user with both email and phone chooses the channel at each login
- **MUST** SMS channel is not available unless the user has at least one verified, enabled phone number
- **MUST** If a user's only MFA phone becomes unverified or disabled mid-session, email channel is offered as fallback
- **MUST** MFA challenge sessions are tied to a `mfaSessionId`. Once verified, the session is consumed and cannot be reused
- **MUST** MFA challenge sessions expire after 15 minutes of inactivity
- **MUST** Administrators can disable MFA for an account from the Admin Panel. The user must re-enable it by re-registering their phone or verifying email
- **SHOULD** Projects should track MFA adoption and engagement metrics (% of users with MFA enabled, SMS vs. email channel preference)
- **SHOULD** Email MFA codes can be single-use or multi-use (project-specific). SMS codes are always single-use

## Email Verification Token Lifecycle

Email verification tokens must be stored in a dedicated table — not in `AspNetUsers` or framework-managed identity tables. This gives explicit control over expiry, cleanup, and multi-token scenarios (e.g., resend without invalidating a prior link).

### Token Table

```
EmailVerificationToken
├── EmailVerificationTokenId    INT IDENTITY PK
├── EmailVerificationTokenGuid  UNIQUEIDENTIFIER NOT NULL UNIQUE
├── UserId                      FK → AspNetUsers.Id
├── Token                       NVARCHAR(512) — bcrypt hash of the token sent in the email
├── EmailAddress                NVARCHAR(256) — the address being verified
├── ExpiryDateUtc               DATETIME2 — default +24 hours from creation
├── IsConsumed                  BIT DEFAULT 0
├── ConsumedDateUtc             DATETIME2 NULL
└── + CommonColumns
```

The plaintext token is sent in the email URL. Only the bcrypt hash is stored. Validation bcrypt-hashes the inbound token and matches against stored hashes — the plaintext is never persisted.

### Verification Flow

1. User clicks the email link; client extracts the plaintext token from the URL.
2. Server bcrypt-hashes the input token and looks it up in `EmailVerificationToken`.
3. Validate: token exists, `IsConsumed = 0`, `ExpiryDateUtc > GETUTCDATE()`, `UserId` matches.
4. On success: set `IsConsumed = 1`, `ConsumedDateUtc = GETUTCDATE()`, set `AspNetUsers.EmailConfirmed = 1`.
5. On any failure: return a generic error — do not disclose which check failed.

### Cleanup Strategy

- Nightly background job soft-deletes (`IsDeleted = 1`) all rows where `ExpiryDateUtc < GETUTCDATE()` AND `IsConsumed = 0`.
- Consumed tokens are retained for audit trail; soft-deleted rather than hard-deleted.

### Rules

- **MUST** Store only the bcrypt hash of the verification token. Never store or log the plaintext.
- **MUST** Default token expiry is 24 hours. Projects must document any override.
- **MUST** A resend issues a new token row — it does not invalidate the prior token. If the user clicks an older link it still validates (unless expired or already consumed).
- **MUST** Nightly cleanup runs to prevent unbounded table growth from abandoned tokens.
- **SHOULD** Verification failure responses are generic and do not indicate which validation check failed, to prevent token enumeration.

## Security Questions Architecture

Security questions provide an additional account verification factor for account recovery, high-risk operations, and multi-factor authentication. This section specifies the design, answer storage, and verification flow.

### Question Library & Assignment

Security questions are **predefined and curated** — users do not create custom questions. A framework-level question library is maintained by the Vega Discoveries ops team via the DevOps dashboard (VegaIdentity.Website). Each solution independently selects which questions are available to its users.

**Question Library Table**

```sql
CREATE TABLE [PredefinedSecurityQuestion] (
    [PredefinedSecurityQuestionId] INT PRIMARY KEY IDENTITY(1,1),
    [QuestionText] NVARCHAR(500) NOT NULL UNIQUE,
    [Category] NVARCHAR(50),              -- e.g., "personal", "security", "childhood"
    [Difficulty] NVARCHAR(50),            -- e.g., "easy", "medium", "hard"
    [IsAssignedToAnySolution] BIT NOT NULL DEFAULT 0,  -- Prevents editing once assigned
    [IsActive] BIT NOT NULL DEFAULT 1,
    -- CommonColumns
);

CREATE INDEX [IX_PredefinedSecurityQuestion_Category] 
    ON [PredefinedSecurityQuestion]([Category]);
CREATE INDEX [IX_PredefinedSecurityQuestion_IsAssignedToAnySolution] 
    ON [PredefinedSecurityQuestion]([IsAssignedToAnySolution]);
```

**Solution-Specific Question Selection**

```sql
CREATE TABLE [SolutionPredefinedSecurityQuestion] (
    [SolutionPredefinedSecurityQuestionId] INT PRIMARY KEY IDENTITY(1,1),
    [SolutionId] INT NOT NULL FOREIGN KEY REFERENCES [RegisteredSolutions]([SolutionId]),
    [PredefinedSecurityQuestionId] INT NOT NULL FOREIGN KEY,
    [SortOrder] INT NOT NULL DEFAULT 100,  -- Per-solution reordering via DevOps dashboard
    -- CommonColumns
    UNIQUE ([SolutionId], [PredefinedSecurityQuestionId])
);

CREATE INDEX [IX_SolutionPredefinedSecurityQuestion_SolutionId_SortOrder] 
    ON [SolutionPredefinedSecurityQuestion]([SolutionId], [SortOrder]);
```

### Answer Storage & Normalization

User-provided answers are **normalized and bcrypt-hashed** before storage. This ensures consistency across variations of the same answer (spacing, capitalization) while preventing plaintext recovery of answers.

**Answer Normalization Strategy**

Apply the following normalization before hashing:
1. Convert to lowercase: `answer.ToLowerInvariant()`
2. Trim leading/trailing whitespace: `.Trim()`
3. Collapse multiple spaces to single spaces: `.Replace("  ", " ")`

Example: `"John  Smith"` → `"john smith"` (normalized and hashed)

**User Security Questions Table**

```sql
CREATE TABLE [UserSecurityQuestion] (
    [UserSecurityQuestionId] INT PRIMARY KEY IDENTITY(1,1),
    [UserSecurityQuestionGuid] UNIQUEIDENTIFIER NOT NULL UNIQUE DEFAULT newid(),
    [UserId] NVARCHAR(128) NOT NULL FOREIGN KEY REFERENCES [AspNetUsers]([Id]),
    [PredefinedSecurityQuestionId] INT NOT NULL FOREIGN KEY,
    [AnswerHash] NVARCHAR(MAX) NOT NULL,  -- bcrypt(normalized_answer, cost >= 12)
    [DisplayOrder] INT NOT NULL,           -- User-facing question order: 1, 2, 3...
    -- CommonColumns
);

CREATE INDEX [IX_UserSecurityQuestion_UserId_DisplayOrder] 
    ON [UserSecurityQuestion]([UserId], [DisplayOrder]);
CREATE INDEX [IX_UserSecurityQuestion_PredefinedSecurityQuestionId] 
    ON [UserSecurityQuestion]([PredefinedSecurityQuestionId]);
```

### Question & Answer Setup Flow

**Step 1 — Get Available Questions (During Registration)**

```csharp
// Client calls endpoint to discover questions for the current solution
GET /api/v1/auth/security-questions?solutionId={guid}

// Response: list of predefined questions ordered by SortOrder
[
    { "questionId": "...", "questionText": "What is your mother's maiden name?" },
    { "questionId": "...", "questionText": "In what city were you born?" },
    { "questionId": "...", "questionText": "What was your first pet's name?" },
    ...
]
```

The server queries `SolutionPredefinedSecurityQuestion` filtered by SolutionId, ordered by SortOrder, and joins to `PredefinedSecurityQuestion` to return question text. **Never expose answer hashes or difficulty ratings.**

**Step 2 — Register User with Security Answers**

```csharp
POST /api/v1/auth/register
{
    "email": "user@example.com",
    "password": "...",
    "resetPin": "...",
    "birthMonth": 3,
    "birthYear": 1990,
    "country": "US",
    "securityQuestions": [
        { "questionId": "question-1-guid", "answer": "Jane" },
        { "questionId": "question-2-guid", "answer": "Boston" }
    ]
}
```

The server:
1. Validates the number of answers matches the solution's requirement (configurable; typically 2–5 questions).
2. For each answer:
   - Apply `NormalizeAnswer(answer)` helper
   - Bcrypt-hash the normalized answer (cost ≥ 12)
   - Insert into `UserSecurityQuestion` with DisplayOrder matching input order
   - Validate that each `questionId` is assigned to the current solution via `SolutionPredefinedSecurityQuestion`

### Answer Verification Flow

**Verification Endpoint**

```csharp
POST /api/v1/accounts/verify-security-answers
{
    "answers": [
        { "questionId": "question-1-guid", "answer": "jane" },
        { "questionId": "question-2-guid", "answer": "boston" }
    ]
}

// Response on success
{ "verified": true }

// Response on failure
{ "verified": false, "message": "One or more answers are incorrect." }
```

**Server Verification Logic**

1. Query `UserSecurityQuestion` rows for the authenticated user, ordered by DisplayOrder.
2. For each provided answer:
   - Apply `NormalizeAnswer(answer)` helper using the same normalization strategy
   - Lookup the bcrypt hash from `UserSecurityQuestion` for the provided `questionId`
   - Use bcrypt.Verify(normalized_input, stored_hash) to compare
   - Do **not** short-circuit on first mismatch — validate all answers silently to prevent answer enumeration
3. Return generic failure message if any answer mismatches; never indicate which answer was wrong.
4. Return success only if all provided answers match.

### Rules

- **MUST** Security questions are predefined and curated by the ops team. Users do not create custom questions.
- **MUST** Only the Vega Discoveries ops team can add or edit PredefinedSecurityQuestion records via the DevOps dashboard (VegaIdentity.Website). No programmatic mutation by the API.
- **MUST** Once a question is assigned to any solution (`SolutionPredefinedSecurityQuestion` row exists), set `IsAssignedToAnySolution = 1` to prevent accidental edits to the question text.
- **MUST** Answers are normalized (lowercase, trimmed, single spaces) and bcrypt-hashed before storage. Apply the same normalization during verification.
- **MUST** Bcrypt cost is ≥ 12. This provides adequate protection for short security question answers without excessive latency.
- **MUST** On verification failure, return a generic message: "One or more answers are incorrect." Never disclose which answer failed or provide a count of correct answers.
- **MUST** Do not short-circuit answer verification. Validate all provided answers against the hash before returning success or failure to prevent answer enumeration via timing.
- **MUST** Each user can set a distinct answer per question. Reusing the same answer across multiple questions is allowed but not recommended in UI guidance.
- **SHOULD** At registration, require at least 2 security questions (configurable per-solution via `SolutionAccountFieldRequirement`). 2–5 questions is typical.
- **SHOULD** Security questions are re-verified as a second factor during sensitive operations: email change, password reset completion, or admin actions.
- **SHOULD** Users can update their security answers in the account settings panel. The update flow is identical to initial setup (normalize, hash, replace prior answers).

## Key Rotation Lifecycle

This section covers the operational calendar and triggers for RS256 signing key rotation. The technical rotation mechanics (JWKS endpoint, `API_SigningKey` table, consumer cache refresh) are covered in [JWKS Endpoint & Key Rotation](#jwks-endpoint--key-rotation).

### Rotation Schedule

| Trigger | Action |
|---------|--------|
| Quarterly (routine) | Generate new key pair; begin 30-day overlap; retire old key after overlap |
| Suspected private key compromise | Emergency rotation — immediate; do not wait for overlap expiry |
| Master key rotation | Re-encrypt all private keys stored in `Furniture` table; no JWKS change required |

### Rotation Checklist

1. Generate a new RSA key pair using approved tooling.
2. Store the new private key in the `Furniture` table (encrypted with the current master key).
3. Insert the new public key into `API_SigningKey` (`IsCurrent = 1`; old key `IsCurrent = 0`).
4. Verify: JWKS endpoint now serves both keys.
5. Monitor: Confirm consumer APIs pick up the new key within 5 minutes (first cache refresh cycle).
6. After 30-day overlap: set `DeprecatedAfterUtc` on the old key.
7. Verify: JWKS no longer includes the old key.
8. Log the rotation event (actor, timestamp, old key ID, new key ID) in the audit log.

### Emergency Rotation

If a private key is suspected compromised:
1. Perform steps 1–4 above immediately.
2. Set `DeprecatedAfterUtc = GETUTCDATE()` on the old key — remove it from JWKS immediately (no 30-day overlap).
3. All tokens signed with the old key become unvalidatable within minutes. Users must re-authenticate.
4. Revoke all active refresh tokens to force clean re-authentication.
5. File a security incident report.

### Rules

- **MUST** All key rotation events are audit-logged: actor, timestamp, old `KeyId`, new `KeyId`.
- **MUST** Emergency rotation bypasses the 30-day overlap and immediately removes the compromised key from JWKS.
- **MUST NOT** Delete a key from `API_SigningKey` during normal rotation — use `DeprecatedAfterUtc` to expire it gracefully.
- **SHOULD** Rotation is performed at least quarterly. If a solution's compliance posture requires shorter intervals, document the override in the project documentation.

## Roles & Authorization

Roles are stored in the app DB (see `## App DB Role Tables` in Chapter 7 — Database Architecture) and stamped into the JWT as `role` claims at login time. Each solution maintains its own role assignments; a user may hold different roles across solutions.

### Standard Roles

The following three roles are seeded by the framework and are present in every solution:

| Role | Default | Purpose |
|------|---------|--------|
| `User` | Yes — generic framework default | Standard authenticated user |
| `Admin` | No | Full solution administration — activates Admin Panel in the UI |
| `Dev` | No | Internal developer and debug access — activates Dev Toolbar in the UI |

The project documentation defines any additional app-specific roles. The project may also override the registration default (e.g., VegaDrop assigns `Player` instead of `User` as the default role).

### Role Rules

- **MUST** Role names are `public const string` fields in a static `RoleDefs` class in `{AppName}.Domain` or `{AppName}.Contracts`. Never use magic strings for role names anywhere in application code.
- **MUST** At JWT generation, query the app DB `UserRole` table for the user's active roles and include them as `role` claims in the token.
- **MUST** For sensitive or destructive operations, re-validate roles against the app DB at request time — do not rely solely on JWT claims, which reflect roles at token issuance.
- **MUST** Pages requiring authentication inherit from `SecurePageBase`. Public pages inherit from `PageBase`.
- **MUST** `app.UseHttpsRedirection()` appears in the pipeline before any auth middleware. iOS ATS and Android NSC reject plain HTTP in production.
- **MUST** JWT secrets are stored in User Secrets locally and in environment variables or Key Vault in production. Never in `appsettings.json`.
- **SHOULD** Use policy-based authorization over direct role checks for fine-grained permissions.
- **SHOULD** A user may hold multiple roles simultaneously. Authorization policies should evaluate the full role set.

### Admin Panel

When the authenticated user holds the `Admin` role, the UI must expose an Admin Panel (or equivalent admin navigation section). This panel is invisible to all other roles and is never rendered unless the current user's active JWT claims include `Admin`.

**Framework-level admin features (required in every solution):**

| Feature | Description |
|---------|-------------|
| User List | Paginated, searchable, filterable list of all registered accounts. Shows email, registration date, last login, active roles, and account status. |
| User Detail | Full account view — login history, active sessions, role assignments, credential records per solution, lockout status. |
| Role Management | Assign or revoke roles for any user. Role changes take effect at next login (JWT not retroactively invalidated unless refresh token is revoked). |
| Account Activate / Deactivate | Soft-disable an account without deleting it. Invalidates active refresh tokens for that account. |
| Manual Lockout Unlock | Clear a `UserSolutionCredential` lockout state for a specific user and solution without requiring a password reset. |
| Active Sessions | List of accounts with a currently valid refresh token, showing solution, issued-at, and expiry. |
| Failed Login Audit | Recent failed login attempts — account, solution, timestamp, IP. Useful for detecting brute-force patterns. |
| Error Log Viewer | Query recent server-side errors by date range or TraceId. Links to structured log store or surfaces the structured log summary inline. |
| System Announcements | Create, update, or remove global banners or notices displayed to all users in the UI. |
| Maintenance Mode | Toggle maintenance mode for the solution. While active, non-admin users receive a maintenance page rather than the app. |
| Feature Flags | Enable or disable named feature flags at runtime. Applied immediately without redeployment. |

**Project-specific admin features** (e.g., game stats, IAP/purchase history, leaderboard management, content moderation queues) must be defined in the project documentation.

**Rules:**

- **MUST** The Admin Panel is only rendered when the JWT `role` claims include `Admin`. Never infer admin access from any other signal.
- **MUST** All destructive admin actions (deactivate account, revoke role, unlock lockout) require re-validation of the acting admin's `Admin` role against the app DB at request time — do not rely solely on the JWT.
- **MUST** All admin actions are audit-logged: actor account ID, target account ID (if applicable), action name, timestamp, and before/after values where relevant.
- **SHOULD** The Admin Panel uses the same auth token as the main application. No separate admin login is required.
- **SHOULD** Admin list views are paginated server-side. Never load all user records in a single query.

## Required Middleware Order

```csharp
app.UseHttpsRedirection();       // 1
app.UseStaticFiles();            // 2 (website only)
app.UseRouting();                // 3
app.UseRequestLocalization();    // 4
app.UseAuthentication();         // 5 — who are you?
app.UseAuthorization();          // 6 — are you allowed?
app.MapControllers();            // 7 — execute endpoint
```

## Authentication Rules

- **MUST** `ValidateAudience = true` on every solution API. Each solution's `AudienceIdentifier` is loaded from `appsettings.json` via `IOptions<JwtConfig>`.
- **MUST** All login endpoints validate credentials against `UserSolutionCredential` for the requesting solution. `AspNetUsers.PasswordHash` is never read during login.
- **MUST** `AspNetUsers.PasswordHash` stores the Reset PIN hash only. Document this explicitly in the Identity database schema notes.
- **MUST** Password reset tokens are short-lived signed JWTs (recommended: 20 minutes). Never embed unsigned or plain values in reset URLs.
- **MUST** Reset tokens are single-use. The `jti` claim is recorded in `ConsumedResetTokens` on first use and rejected on any replay attempt.
- **MUST** Account lockout is tracked per `UserSolutionCredential` row. A lockout on Solution A does not affect the user's access to Solution B.
- **MUST** The Reset PIN can only be changed by providing the current Reset PIN. It must never be changeable via an email link alone.
- **SHOULD** The "email sent" confirmation screen always displays regardless of internal PIN validation outcome, to prevent user enumeration via timing differences.
- **SHOULD** Clearly label the Reset PIN in all UI as a distinct credential from solution passwords, with explicit guidance not to reuse a solution password as the Reset PIN.

---

## CHANGELOG

| Version | Date | Change | Source |
|---------|------|--------|--------|
| 1.11 | 2026-05-19 | Added `## Token Lifetime Defaults` — 15-min access token, 30-day refresh token baselines | Migrated from VegaIdentity RF, Critical Gap 3 |
| 1.11 | 2026-05-19 | Added `## Account Lockout Baselines` — 5 attempts / 30-min window / 30-min lockout with override support | Migrated from VegaIdentity RF, Critical Gap 2 |
| 1.11 | 2026-05-19 | Added `## Rate Limiting Architecture` — SlidingWindowRateLimiter, default policies, per-solution override pattern | Migrated from VegaIdentity RF, Critical Gap 5 |
| 1.11 | 2026-05-19 | Added `## JWKS Endpoint & Key Rotation` — RS256 JWKS endpoint, kid format, 30-day overlap, consumer cache strategy | Migrated from VegaIdentity RF, Critical Gap 4 |
| 1.11 | 2026-05-19 | Added `## Client-Side Token Storage Strategies` — encrypted localStorage with replay detection | Migrated from VegaIdentity RF, Blocking Decision OQ-7 |
| 1.11 | 2026-05-19 | Added `## Email Verification Token Lifecycle` — dedicated table, bcrypt hash, 24h expiry, nightly cleanup | Migrated from VegaIdentity RF, Critical Gap 1 |
| 1.11 | 2026-05-19 | Added `## Key Rotation Lifecycle` — quarterly cadence, emergency rotation checklist, audit log requirements | Migrated from VegaIdentity RF, Critical Gaps 4 + Blocking Decisions OQ-11/OQ-12 |
| 1.12 | 2026-05-21 | Added `## SMS Verification via Email-to-SMS Gateways` — carrier gateway pattern, schema, service implementation, phone registration flow | Migrated from VegaIdentity Review Findings, Section 2.85 (SMS Integration) |
| 1.12 | 2026-05-21 | Added `## Multi-Factor Authentication (MFA) Strategy` — email + SMS channels, login flow, code delivery rules, resend strategy | Migrated from VegaIdentity Review Findings, Section 2.85 (SMS Integration) + MFA design decisions |
| 1.13 | 2026-05-21 | Added `## Security Questions Architecture` — predefined question library, answer normalization + bcrypt hashing, per-solution assignment, verification flow, DevOps dashboard management | User requirements: per-solution demographic fields (birthYear, birthMonth, country, timezone) + security questions for account recovery |
