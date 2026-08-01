# Chapter 17 — Database Seed Data Patterns

**Target Audience:** DBAs, backend developers, DevOps, infrastructure leads  
~~**Applicability:** Any Vega Discoveries solution with a database (SSDT `.sqlproj`)~~  
**Applicability:** Any Vega Discoveries solution with a database (`.Database` DbUp class library)  
**Context:** Reference data, configuration seeds, and migration sequences for all solutions

> **⚠️ Append-only — agent instruction:** This document is an append-only architecture record. Do not delete or reword existing content. New or revised guidance must be added below the content it supersedes. Strikethrough (`~~text~~`) is a valid edit technique — it visually marks content as superseded while retaining it for audit purposes. Use strikethrough to mark the old text, then place the replacement immediately after on a new line.

---

## Overview

Seed data represents reference tables, configuration values, and static lookup data inserted during initial database deployment and migrations. This chapter defines patterns, methodologies, and validation strategies applicable to all Vega Discoveries solutions.

Seed data differs from:
- **Transaction data** — User-created records (never seeded in bulk)
- **Transient data** — Session state, temporary calculations (not seeded; ephemeral)
- **Configuration** — Can live in appsettings.json (but may also be seeded for auditability)

---

## Part 1: Seed Data Lifecycle and Phases

### Phase Binding

Each seed data insertion is tied to a migration phase:

- **Phase 1 (Initialization)** — Solution registration, fundamental lookups
- **Phase 2 (Domain)** — Entity-scoped seed data (e.g., carrier codes, type enums)
- **Phase 3–6** — Feature-specific seeds (email templates, API configuration)
- **Phase 7+ (Infrastructure)** — Operational seeds (monitoring policies, rate limits)

**Principle:** Seed data creation order mirrors the dependency graph; a seed inserted in Phase 3 must reference seed data created in Phase 1 or 2.

### Idempotency — Critical Pattern

All seed data inserts must be **idempotent** — running a migration multiple times produces the same result.

**Pattern:**

```sql
-- ❌ NOT idempotent (fails on re-run if record exists)
INSERT INTO [ConfigurationTable] ([Key], [Value]) 
VALUES ('MfaCodeLifetime', '10');

-- ✅ Idempotent (safe on re-run)
INSERT INTO [ConfigurationTable] ([Key], [Value])
SELECT 'MfaCodeLifetime', '10'
WHERE NOT EXISTS (
  SELECT 1 FROM [ConfigurationTable] 
  WHERE [Key] = 'MfaCodeLifetime' AND IsDeleted = 0
);
```

**Why:** Migrations may be re-run in non-prod environments for testing, schema resets, or CI/CD replay scenarios. Idempotent inserts prevent duplicate-key errors.

### Transaction Scope

All related seed operations (table creation + seeding + index creation) belong in a single transaction:

```sql
BEGIN TRANSACTION
  -- 1. Create table
  CREATE TABLE [EmailType] (...)
  
  -- 2. Seed records
  INSERT INTO [EmailType] (...)
  
  -- 3. Create indexes
  CREATE INDEX [IX_EmailType_Name] ON [EmailType] ([Name])
  
COMMIT TRANSACTION
```

**Rationale:** If any step fails, the entire migration rolls back; no partial schema or orphaned seed data.

---

## Part 2: Seed Data Organization

### By Table Category

Organize seeds into logical categories:

| Category | Purpose | Typical Tables | Insertion Order |
|----------|---------|-----------------|-----------------|
| **Framework** | Core system configuration (roles, types, status enums) | EmailType, UserRole, AccountStatus | Phase 1–2 |
| **Reference** | Static lookup data (carriers, time zones, countries) | SmsCarrier, TimeZone, Country | Phase 2–3 |
| **Operations** | Runtime configuration (rate limit policies, thresholds) | RateLimitPolicy, SecurityPolicy | Phase 4+ |
| **Solutions** | Solution registration and solution-specific data | RegisteredSolutions, SolutionConfig | Phase 1 (solution-specific) |

### Seed Data Storage in Migrations

~~In SSDT projects, seed data lives in **post-deployment scripts** (not EF Core migrations).~~
In the `.Database` DbUp class library, seed data scripts are placed in the `PostDeployment/` folder and executed via `NullJournal` (always-run, idempotent).

**File location:** `VegaIdentity.Database/PostDeployment/`

**Naming convention:** `Script.PostDeployment.sql` or numbered scripts like `001_InitializeSeed.sql`, `002_EmailTypes.sql`

**Execution order:** Post-deployment scripts run **after** all schema migrations complete, in alphabetical order by filename.

---

## Part 3: Seed Data Schema Design

### Required Columns for Seed Records

Every seed record must capture:

| Column | Type | Purpose | Always Seed? |
|--------|------|---------|-------------|
| `[Key]ID` or `[Key]GUID` | INT or UNIQUEIDENTIFIER | Primary key (database-assigned) | No — DB default |
| `Name` or `Code` | NVARCHAR(255) | Stable lookup identifier (what code references) | **Yes** — application dependency |
| `DisplayName` or `Label` | NVARCHAR(255) | Human-readable name for UI | **Yes** |
| `Description` | NVARCHAR(2000) | Explanation for ops/support | **Yes** |
| `SortOrder` | INT | UI display order (ascending) | **Yes** |
| `IsActive` | BIT | Soft-delete indicator (1 = active) | **Yes — always 1 for new seeds** |
| `CreatedUser` | NVARCHAR(150) | Audit: who created this | **Yes — always 'system'** |
| `CreatedDate` | DATETIME2(7) | Audit: when created | **Yes — use DB DEFAULT GETUTCDATE()** |
| `LastUpdatedUser` | NVARCHAR(150) | Audit: last modifier | **Yes — same as CreatedUser** |
| `LastUpdatedDate` | DATETIME2(7) | Audit: last update time | **Yes — use DB DEFAULT GETUTCDATE()** |
| `IsDeleted` | BIT | Hard-delete flag (0 = not deleted) | **Yes — always 0 for new seeds** |
| `DeletedDate` | DATETIME2(7) | Audit: when deleted | No — NULL for new seeds |
| `DeletedUser` | NVARCHAR(150) | Audit: who deleted | No — NULL for new seeds |

**Pattern for INSERT:**

```sql
INSERT INTO [ReferenceTable] 
  ([Name], [DisplayName], [Description], [SortOrder], [IsActive], [CreatedUser], [LastUpdatedUser])
VALUES 
  ('enum_value', 'Display Name', 'Description', 10, 1, 'system', 'system')
  -- DB DEFAULT handles CreatedDate, LastUpdatedDate
```

---

## Part 4: Insertion Order and Dependencies

### Build a Dependency Graph Before Inserting

If Table B has a foreign key to Table A, insert Table A seeds **first**.

**Example dependency chain:**

```
EmailType (no dependencies)
  ↓ (EmailTemplate.EmailTypeId → EmailType.EmailTypeID)
EmailTemplate
  ↓ (EmailTemplateBlock.EmailTemplateId → EmailTemplate.EmailTemplateID)
EmailTemplateBlock
  ↓ (EmailBlock.EmailBlockID referenced by EmailTemplateBlock)
EmailBlock
```

**Seed in order: EmailType → EmailBlock → EmailTemplate → EmailTemplateBlock**

### Using DECLAREs for Cross-Table References

When seeding dependent records, retrieve the parent ID once:

```sql
-- ✅ Efficient: single SELECT, then reference in VALUES
DECLARE @EmailTypeId INT = (
  SELECT EmailTypeID FROM [EmailType] 
  WHERE Name = 'EmailVerification' AND IsDeleted = 0
);

INSERT INTO [EmailTemplate] ([EmailTypeId], [Name], [Subject], ...)
VALUES (@EmailTypeId, 'EmailVerification_Default', 'Verify Your Email', ...);
```

**Rationale:** Avoids repeated subqueries; makes dependency explicit.

---

## Part 5: Validation After Seed Insertion

### Post-Insert Verification

After seeds are inserted, verify:

1. **Count check** — Verify expected row count

```sql
SELECT COUNT(*) AS ActualCount FROM [EmailType] WHERE IsDeleted = 0;
-- Expected: 3 (EmailVerification, PasswordReset, SmsVerification)
```

2. **Uniqueness check** — Verify no duplicate names

```sql
SELECT [Name], COUNT(*) AS DuplicateCount 
FROM [EmailType] 
WHERE IsDeleted = 0
GROUP BY [Name]
HAVING COUNT(*) > 1;
-- Expected: (no rows — all unique)
```

3. **Referential integrity check** — Verify foreign keys

```sql
SELECT COUNT(*) AS OrphanedRecords
FROM [EmailTemplate] et
LEFT JOIN [EmailType] et2 ON et.EmailTypeId = et2.EmailTypeID
WHERE et.IsDeleted = 0 AND et2.EmailTypeID IS NULL;
-- Expected: 0 (no orphaned templates)
```

4. **Audit trail check** — Verify created/updated dates are set

```sql
SELECT COUNT(*) AS MissingAudit 
FROM [EmailType] 
WHERE IsDeleted = 0 AND (CreatedDate IS NULL OR CreatedUser IS NULL);
-- Expected: 0
```

### Validation Checklist Template

For each seeded table:

- [ ] Correct number of rows inserted (use COUNT query)
- [ ] All rows have `IsActive = 1` or `IsDeleted = 0` (as appropriate)
- [ ] All `Name` / `Code` values are unique and match application constants
- [ ] All foreign key references resolve (no orphaned records)
- [ ] All audit columns are populated (`CreatedUser`, `CreatedDate`, etc.)
- [ ] No duplicate names (run GROUP BY query)

---

## Part 6: Updating Seed Data in Future Releases

### When to UPDATE vs. INSERT

| Scenario | Action | Example |
|----------|--------|---------|
| Add a **new** reference value | `INSERT` (idempotently) | Add new SMS carrier to SmsCarrier table |
| Change a **display name** | `UPDATE` existing record | Change 'PasswordReset' → 'Password Reset Flow' |
| Retire an old value | `UPDATE IsActive = 0` (soft-delete) | Disable legacy email type |
| Remove entirely (rare) | `UPDATE IsDeleted = 1` (hard-delete) | Only if never referenced |

### Safe UPDATE Pattern

```sql
-- ✅ Idempotent update (safe on re-run)
UPDATE [EmailType] 
SET [DisplayName] = 'Password Reset Flow', [LastUpdatedUser] = 'system'
WHERE [Name] = 'PasswordReset' 
  AND [IsDeleted] = 0 
  AND [DisplayName] != 'Password Reset Flow';  -- Only update if different
```

---

## Part 7: Rollback and Recovery

### Soft-Delete (Recommended for Production)

When seed data must be deactivated but audit trail must remain:

```sql
UPDATE [SmsCarrier] 
SET [IsActive] = 0, [LastUpdatedUser] = 'admin'
WHERE [CarrierCode] = 'deprecated_carrier';
```

**Advantage:** Previous references are preserved; data audit trail is intact.

### Hard-Delete (Only if Safe)

Only use if the seeded record is **guaranteed unreferenced**:

```sql
DELETE FROM [SmsCarrier] 
WHERE [CarrierCode] = 'never_used_carrier' 
  AND (SELECT COUNT(*) FROM [UserPhoneNumber] WHERE [CarrierId] = SmsCarrier.SmsCarrierId) = 0;
```

**Caution:** Hard-delete removes audit trail. Use only in pre-production scenarios.

---

## Part 8: Seed Data and Environment Differences

### When Seed Data Differs by Environment

Some seed data is **environment-independent** (core reference data), some **environment-specific** (operational thresholds).

**Environment-independent (same across Dev/Staging/Prod):**
- Email types (EmailVerification, PasswordReset, SmsVerification)
- SMS carriers
- Framework roles (User, Admin, Dev)
- Standard enums

**Environment-specific (may differ):**
- Rate limit thresholds (strict in Prod, relaxed in Dev)
- Email sender addresses (noreply-dev@, noreply-prod@)
- Solution registration (each environment registers different solutions)

**Pattern:**

```sql
-- Post-deployment script with environment detection
DECLARE @Environment NVARCHAR(50) = '$(Environment)';

-- Core seeds (all environments)
INSERT INTO [EmailType] ([Name], [DisplayName], ...) 
SELECT 'EmailVerification', 'Email Verification', ...
WHERE NOT EXISTS (SELECT 1 FROM [EmailType] WHERE Name = 'EmailVerification');

-- Environment-specific seeds
IF @Environment = 'Production'
BEGIN
  INSERT INTO [RateLimitPolicy] ([Name], [Threshold], [WindowMinutes], ...)
  VALUES ('AuthLogin', 5, 30, ...)  -- 5 attempts per 30 min
END
ELSE
BEGIN
  INSERT INTO [RateLimitPolicy] ([Name], [Threshold], [WindowMinutes], ...)
  VALUES ('AuthLogin', 50, 30, ...)  -- 50 attempts per 30 min (dev-friendly)
END
```

---

## Part 9: Seed Data in CI/CD Pipelines

### Integration with Build and Deployment

1. **Local Development**
   - Post-deployment scripts run automatically on `dotnet build`
   - Developer verifies seeds via test queries after build

2. **Continuous Integration**
   - Schema deployed to test database
   - Post-deployment scripts execute
   - Integration tests verify seed data exists and is correct
   - Example assertion: `Assert.Equal(3, context.EmailTypes.Where(x => !x.IsDeleted).Count())`

3. **Staging/Production Deployment**
   - DACPAC published via automated pipeline
   - Post-deployment scripts run (idempotent)
   - Ops team runs validation queries post-deployment
   - Alerts fire if seed count is wrong (config drift detection)

### Example Test Assertion

```csharp
[Fact]
public void PostDeploymentSeeds_EmailTypesExist()
{
  // Arrange
  using var db = new AppIdentityDbContext();
  
  // Act
  var emailTypes = db.EmailTypes.Where(x => !x.IsDeleted).ToList();
  
  // Assert
  Assert.NotEmpty(emailTypes);
  Assert.Contains(emailTypes, x => x.Name == "EmailVerification");
  Assert.Contains(emailTypes, x => x.Name == "PasswordReset");
  Assert.Contains(emailTypes, x => x.Name == "SmsVerification");
}
```

---

## Part 10: Common Seed Data Patterns Across All Solutions

### Pattern 1: Email Types

Every solution that sends emails should seed standard email types:

```sql
INSERT INTO [EmailType] ([Name], [DisplayName], [Description], [SortOrder], [IsActive], [CreatedUser], [LastUpdatedUser])
SELECT 'EmailVerification', 'Email Verification', 'Account email verification', 10, 1, 'system', 'system'
WHERE NOT EXISTS (SELECT 1 FROM [EmailType] WHERE Name = 'EmailVerification');

INSERT INTO [EmailType] ([Name], [DisplayName], [Description], [SortOrder], [IsActive], [CreatedUser], [LastUpdatedUser])
SELECT 'PasswordReset', 'Password Reset', 'Password reset flow', 20, 1, 'system', 'system'
WHERE NOT EXISTS (SELECT 1 FROM [EmailType] WHERE Name = 'PasswordReset');
```

### Pattern 2: Solution Registration

Each solution's database must register itself:

```sql
INSERT INTO [RegisteredSolutions] ([Name], [AudienceIdentifier], [FromAddress], [FromDisplayName], [CreatedUser], [LastUpdatedUser], [IsActive])
SELECT 'MyConsumerSolution', 'vegadiscoveries.myconsomersolution', 'noreply@myconsomersolution.vegadiscoveries.com', 'MyConsumer Notifications', 'system', 'system', 1
WHERE NOT EXISTS (SELECT 1 FROM [RegisteredSolutions] WHERE Name = 'MyConsumerSolution' AND IsDeleted = 0);
```

### Pattern 3: Lookup/Reference Tables

Tables that support dropdowns or type validation:

```sql
INSERT INTO [Country] ([Code], [Name], [DisplayName], [IsActive], [CreatedUser], [LastUpdatedUser])
SELECT 'US', 'United States', 'United States of America', 1, 'system', 'system'
WHERE NOT EXISTS (SELECT 1 FROM [Country] WHERE Code = 'US' AND IsDeleted = 0);
```

---

## Part 11: Documentation Requirements for Seed Data

When documenting seed data in a solution:

1. **Purpose** — Why this seed exists (what feature depends on it?)
2. **Table** — Which table holds it
3. **Columns** — Which columns are populated; which are defaults
4. **Records** — Exact INSERT statements (SQL or code template)
5. **Phase** — When in the migration sequence it's inserted
6. **Validation** — Verification query or test assertion
7. **Updates** — How to add new values in future releases
8. **Dependencies** — What this seed depends on; what depends on it

---

## Part 12: Anti-Patterns to Avoid

### ❌ Non-Idempotent Inserts

```sql
-- WRONG: Fails on re-run if record exists
INSERT INTO [EmailType] ([Name], [DisplayName]) VALUES ('EmailVerification', 'Email Verification');
```

**Fix:** Use `WHERE NOT EXISTS`.

### ❌ Hardcoded IDs in Foreign Keys

```sql
-- WRONG: Assumes EmailTypeID = 1 (brittle)
INSERT INTO [EmailTemplate] ([EmailTypeId], [Name]) VALUES (1, 'EmailVerification_Default');
```

**Fix:** Use DECLARE to look up the ID:

```sql
DECLARE @EmailTypeId INT = (SELECT EmailTypeID FROM [EmailType] WHERE Name = 'EmailVerification');
INSERT INTO [EmailTemplate] ([EmailTypeId], [Name]) VALUES (@EmailTypeId, 'EmailVerification_Default');
```

### ❌ Mixing Schema and Seed in Single Script

```sql
-- WRONG: Schema and data in one script; hard to separate concerns
CREATE TABLE [EmailType] (...);
INSERT INTO [EmailType] (...) VALUES (...);
```

**Fix:** Separate into schema (migrations) and seeds (post-deploy scripts).

### ❌ Missing Audit Columns

```sql
-- WRONG: No CreatedUser, CreatedDate, IsDeleted
INSERT INTO [EmailType] ([Name], [DisplayName]) VALUES (...);
```

**Fix:** Always include audit columns (or rely on DB DEFAULT).

### ❌ Seed Data Without Validation

Deploy seeds without verifying they actually exist post-deployment.

**Fix:** Add validation queries to post-deploy script or integration tests.

---

## Summary

**Seed data patterns for all Vega Discoveries solutions:**

1. ✅ **Idempotent inserts** — Safe on re-run
2. ✅ **Phase-bound** — Tied to migration phases
3. ✅ **Transactional** — All-or-nothing per migration
4. ✅ **Audited** — CreatedUser, CreatedDate, IsDeleted
5. ✅ **Validated** — Post-insert verification queries
6. ✅ **Documented** — Purpose, table, phase, validation
7. ✅ **Environment-aware** — Core seeds vs. environment-specific seeds
8. ✅ **Updateable** — Safe UPDATE pattern for future releases

For solution-specific seed data (constants, configuration, reference tables), see the solution's own documentation.
