# Generic Project Guidelines — Table of Contents

**Source Document:** `GenericProjectGuidlines_V1.10_20260323.md`  
**Target Framework:** .NET 10 LTS | **Audience:** All project contributors

---

| # | Section | Chapters Covered | Audience | File |
|---|---------|-----------------|----------|------|
| 1 | Solution Structure | Chapter 1 | Architects, tech leads | [GenericProjectGuidlines_SolutionStructure.md](GenericProjectGuidlines_SolutionStructure.md) |
| 2 | Project Roles & Responsibilities | Chapter 2 | All developers | [GenericProjectGuidlines_ProjectRoles.md](GenericProjectGuidlines_ProjectRoles.md) |
| 3 | Folder & File Organization | Chapter 3 | All developers | [GenericProjectGuidlines_FolderFileOrganization.md](GenericProjectGuidlines_FolderFileOrganization.md) |
| 4 | Versioning Strategy | Chapter 4 | Tech leads, DevOps | [GenericProjectGuidlines_VersioningStrategy.md](GenericProjectGuidlines_VersioningStrategy.md) |
| 5 | Authentication & Security | Chapter 5 | API developers, security | [GenericProjectGuidlines_AuthenticationSecurity.md](GenericProjectGuidlines_AuthenticationSecurity.md) |
| 6 | Logging | Chapter 6 | All developers | [GenericProjectGuidlines_Logging.md](GenericProjectGuidlines_Logging.md) |
| 7 | Database Architecture | Chapter 7 | DBAs, backend developers | [GenericProjectGuidlines_DatabaseArchitecture.md](GenericProjectGuidlines_DatabaseArchitecture.md) |
| 8 | Data Access Patterns | Chapter 8 | Backend developers | [GenericProjectGuidlines_DataAccessPatterns.md](GenericProjectGuidlines_DataAccessPatterns.md) |
| 9 | DTO & Contract Library | Chapter 9 | API and mobile developers | [GenericProjectGuidlines_DTOContractLibrary.md](GenericProjectGuidlines_DTOContractLibrary.md) |
| 10 | API Design & Response Envelope | Chapter 10 | API developers, consumers | [GenericProjectGuidlines_APIDesignResponseEnvelope.md](GenericProjectGuidlines_APIDesignResponseEnvelope.md) |
| 11 | Website — Blazor | Chapter 11 | Frontend developers | [GenericProjectGuidlines_WebsiteBlazor.md](GenericProjectGuidlines_WebsiteBlazor.md) |
| 12 | Mobile Readiness | Chapter 12 | Mobile developers, tech leads | [GenericProjectGuidlines_MobileReadiness.md](GenericProjectGuidlines_MobileReadiness.md) |
| 13 | Coding Standards | Chapter 13 | All developers | [GenericProjectGuidlines_CodingStandards.md](GenericProjectGuidlines_CodingStandards.md) |
| 14 | Configuration & Secrets | Chapter 14 | All developers, DevOps | [GenericProjectGuidlines_ConfigurationSecrets.md](GenericProjectGuidlines_ConfigurationSecrets.md) |
| 15 | Error Handling | Chapter 15 | All developers | [GenericProjectGuidlines_ErrorHandling.md](GenericProjectGuidlines_ErrorHandling.md) |
| 16 | Source Control & Commit Rules | Chapter 16 | All developers | [GenericProjectGuidlines_SourceControlCommitRules.md](GenericProjectGuidlines_SourceControlCommitRules.md) |
| 17 | Database Seed Data Patterns | Chapter 17 | DBAs, backend developers, DevOps | [GenericProjectGuidlines_DatabaseSeedDataPatterns.md](GenericProjectGuidlines_DatabaseSeedDataPatterns.md) |

---

## Maintenance Instructions — Keep This TOC in Sync

**When to update this TOC:**
- When a new section file is created or an existing section is renamed
- When a section is deleted or moved to a different folder
- When chapter assignments change

**How to update:**

1. **Add a new row** if a section is added:
   - Add one row to the table in order (by chapter number)
   - Include the chapter number, section name, chapters covered, audience, and file link
   - File name format: `GenericProjectGuidlines_{SectionName}.md`

2. **Update the Contents list** in the parent document `GenericProjectGuidlines_V1.10_20260323.md`:
   - Sync the chapter number and section name to match this TOC exactly
   - Keep the link target as `#chapter-N--section-name` (lowercase, hyphens)

3. **Remove a row** if a section is deleted:
   - Delete the entire row from this table
   - Delete the corresponding chapter reference from the parent document's Contents list
   - Delete the section file from the folder

4. **Verify sync** after any edit:
   - Line count: This TOC should list exactly 17 entries (Chapters 1-17)
   - Links: All `.md` file links in the table must match actual files in this folder
   - Parent document: The "Contents" section must have an entry for each row in this table

**Golden rule:** Every chapter in the parent document must have exactly one corresponding section file, and this TOC must list them all.
