## Purpose

Replace the SDP default standards doc (GenericProjectGuidlines / GPG) with a consumer-supplied
standards doc. The skill enforces structural requirements on the incoming doc, scaffolds the
sections folder, builds an interactive reading map by cross-referencing GPG chapters, updates
every SDP framework file that references the old doc via fresh search (not a hardcoded list),
runs a sanity check pass, and verifies the result.

This skill is a **one-time, solution-root operation**. It modifies SDP framework source files
permanently. The original GPG doc must remain in `standards/` throughout execution — it is the
cross-reference source for Phase 3 and the basis for strikethrough-based updates to the
bootstrap doc in Phase 4.

---

## Inputs

- Consumer's standards doc — path provided by user on invocation (or solicited in Step 1)
- `standards/GenericProjectGuidlines_V*.md` — original GPG parent doc (must be present)
- `standards/GenericProjectGuidlines_Sections/GenericProjectGuidlines_TOC.md` — GPG TOC (used in Phase 3)
- `SDP_Sapient-Driven-Principles_v*.md` — bootstrap doc at solution root (used in Phases 3 and 4)
- All `.md`, `.ps1`, `.json` files in the solution (searched fresh in Phases 4 and 5)

---

## Procedure

### Step 1: Phase 1 — Doc Preparation and Precondition Checks

Complete every sub-step in order. Do not proceed to Step 2 until all sub-steps pass or the
user has confirmed how to handle any exception.

**1a. Obtain doc path**
If the user provided the new standards doc path on invocation, use it. If not, ask:
"What is the path to your standards doc? (Provide the full path or a path relative to the
solution root.)" Wait for the user's response before continuing.

**1b. Location enforcement**
Check whether the provided path is inside the `standards/` folder at the solution root.
- If yes: continue to sub-step 1c.
- If no: inform the user — "Standards docs must reside in `standards/` for the skill to
  update path references correctly. Moving the file there now." Move (copy + delete source)
  the file into `standards/`. If a file by that name already exists in `standards/`, report
  the conflict and ask the user how to resolve before moving. Confirm the final path to the
  user before continuing.

**1c. Version string**
Inspect the filename for a version segment matching `V[major].[minor]_[YYYYMMDD]`
(e.g., `V1.0_20260625`).
- If a version segment is present: extract it as `[version_key]` and continue to sub-step 1d.
- If absent: propose the filename `[BaseName]_V1.0_[today].md` where `[today]` is today's
  date as `YYYYMMDD`. Present the proposal to the user and wait for confirmation or a
  correction. Rename the file to the confirmed name. Set `[version_key]` to `V1.0_[today]`
  (or the confirmed version string). Continue to sub-step 1d.

Derive `[DocName]` from the filename: the base name without the version segment and without
the `.md` extension. Example: `CompanyStandards_V1.0_20260625.md` → `[DocName]` =
`CompanyStandards`, `[version_key]` = `V1.0_20260625`.

**1d. Format check**
Verify the file extension is `.md`.
- If yes: continue to sub-step 1e.
- If no: inform the user — "The standards doc must be a Markdown file. Converting to `.md`
  now." Convert the file to Markdown (best-effort format preservation). After conversion,
  present a summary of structural changes made (headings detected, tables preserved, etc.)
  and ask the user to confirm the conversion is acceptable before continuing. If the user
  reports fidelity issues, halt and ask them to manually produce an acceptable `.md` file,
  then re-run the skill.

**1e. GPG presence check**
Scan `standards/` for files matching `GenericProjectGuidlines_V*.md`.
- If one or more matches found: confirm to the user which GPG file will be used as the
  cross-reference source. Continue to sub-step 1f.
- If no match found: halt. Invoke
  `/sdp-create-banner icon=error row=0 row: Status | The original GPG doc (standards/GenericProjectGuidlines_V*.md) is required for Phase 3 chapter cross-referencing and must be present during this skill's execution. Restore the file to standards/ and re-run /sdp-standards-setup.`
  Do not proceed until the user restores the file and re-invokes the skill.

**1f. Chapter structure extraction**
Read the new doc. Identify the primary chapter structure:
- If the doc uses H2 (`##`) for chapters: use H2 headings as chapter boundaries.
- If the doc uses H1 (`#`) for chapters (and H2 for sub-sections): use H1 headings.
- If the structure is ambiguous: describe what was found and ask the user to confirm which
  heading level defines chapters before continuing.

Extract the ordered chapter list. For each chapter, derive a section filename using the rule:
remove non-alphanumeric characters from the heading, apply TitleCase concatenation, and prefix
with `[DocName]_`. Example: "Chapter 3: Security & Authentication" → `[DocName]_SecurityAuthentication.md`.

Present a confirmation table to the user:

```
| # | Chapter Heading | Proposed Section File |
|---|----------------|-----------------------|
| 1 | [heading]      | [DocName]_[Name].md   |
...
```

Ask: "Does this chapter breakdown look correct? Confirm or provide corrections before scaffolding begins."

Wait for user confirmation. Apply any corrections to the chapter list before proceeding to Step 2.

---

### Step 2: Phase 2 — Scaffolding

After Step 1 user confirmation, proceed without further prompts unless a write fails.

**2a. Create sections folder**
Create `standards/[DocName]_Sections/` if it does not already exist. If it exists and contains
files, invoke
`/sdp-create-banner icon=warning row=0 row: Status | Sections folder already exists with content — proceeding will overwrite existing section files.`
Then separately ask the user: "Confirm?" Wait for confirmation before continuing.

**2b. Inject sync rule notices into parent doc**
Prepend the following block immediately after the document title line (the first `#` heading)
in `standards/[DocName]_V[version_key].md`:

```markdown

> **⚠️ Sync rule — agent instruction:** This is the parent document. Each chapter has a
> corresponding section file in `[DocName]_Sections/`. Any change made to a chapter here
> **must be mirrored in the corresponding section file**. Any change made in a section file
> must be mirrored in the corresponding chapter here. Both must remain identical in content
> for their shared sections.

> **TOC Maintenance:** The section folder contains a `[DocName]_TOC.md` file that must stay
> in sync with the Contents list below. When you add, rename, or delete a chapter/section,
> update both the Contents list here AND the TOC file. See `[DocName]_TOC.md` for detailed
> maintenance instructions.

```

**2c. Create section files**
For each chapter in the confirmed chapter list:
1. Extract the chapter content from the parent doc — from its heading to immediately before
   the next heading of the same level (or end of file for the last chapter).
2. Write `standards/[DocName]_Sections/[DocName]_[ChapterName].md` with this structure:

```markdown
# [Chapter Heading]

> *Section file for `[DocName]_V[version_key].md`*

> **⚠️ Sync rule — agent instruction:** This is a section file. Any change made here
> **must be mirrored in the corresponding chapter** of `[DocName]_V[version_key].md`. Any
> change made in the parent document's corresponding chapter must be mirrored back here.
> Both files must remain identical in content for their shared sections.

> **TOC Maintenance:** If this section is renamed or deleted, update both the parent
> document's Contents list AND the `[DocName]_TOC.md` file. See the TOC file for
> detailed maintenance instructions.

[extracted chapter content follows here]
```

**2d. Create TOC file**
Write `standards/[DocName]_Sections/[DocName]_TOC.md`:

```markdown
# [DocName] — Table of Contents

**Source Document:** `[DocName]_V[version_key].md`

| # | Section Title | Location in Parent | Audience | Section File |
|---|---------------|--------------------|----------|--------------|
| 1 | [heading]     | Chapter 1          | [blank — consumer fills] | [[DocName]_[Name].md]([DocName]_[Name].md) |
...

## TOC Maintenance Instructions

When adding, renaming, or deleting a chapter:

1. **Update this TOC file** — add, rename, or remove the corresponding row.
2. **Update the Contents list** in the parent document `[DocName]_V[version_key].md`:
   reflect the same change there.
3. **Section file naming convention:**
   File name format: `[DocName]_{SectionName}.md`
   `{SectionName}` is the section title with spaces and special characters removed,
   TitleCase concatenated — e.g., "Error Handling" → `[DocName]_ErrorHandling.md`.
4. **If a section is deleted:** remove the section file from this folder, remove its TOC
   row, and remove its entry from the parent document Contents list.
```

**2e. Report scaffolding results**
List every file created and every file modified in this phase. Note any chapters that could
not be cleanly extracted (e.g., chapter with no distinct end boundary) for user review.

---

### Step 3: Phase 3 — Reading Map Generation (Interactive)

**3a. Read source material**
Read in parallel:
- `standards/GenericProjectGuidlines_V*.md` — extract the chapter list (headings only)
- The bootstrap doc (`SDP_Sapient-Driven-Principles_v*.md`) — locate and read the `## GPG Reading Map`
  section in full, capturing both tables (always-read by phase, conditional by task type) and
  the COORDINATOR Dispatch Instruction block
- The confirmed chapter list from Step 1f

**3b. Cross-reference pass**
For each GPG chapter, determine the best match in the new doc's chapter list using semantic
matching (topic coverage, not heading text). Classify each GPG chapter as one of:

| Outcome | Criteria |
|---------|----------|
| **Mapped** | A chapter in the new doc clearly covers the same topic |
| **Partial match** | A chapter in the new doc covers part of the topic; the rest is not addressed |
| **No match** | No chapter in the new doc addresses this topic at all |

**3c. Draft reading map**

Build a draft reading map with three sections:

**Section A — Mapped and partial chapters:**
For each GPG chapter with a mapped or partial match: replace the GPG chapter reference in both
reading map tables with the corresponding new doc chapter reference. For partial matches, note
what is not covered.

**Section B — Coverage notes (for no-match GPG chapters):**
For each GPG chapter with no match: generate a short prose stub. Read the GPG chapter's
section file (`standards/GenericProjectGuidlines_Sections/GenericProjectGuidlines_[ChapterName].md`)
and distill its key principles into 3–5 sentences. These principles will be embedded directly
in the reading map as a coverage note so agents still receive guidance on this topic even
without a dedicated section file to read.

Format each coverage note as:

```markdown
> **Coverage note — [Topic] (from GPG Ch. N):** The registered standards doc does not contain
> a dedicated [topic] chapter. The following principles apply to tasks in this area:
> [3–5 sentence distillation of key GPG principles for this topic]
> WORKER and REVIEWER should apply these principles directly; no section file read is required.
```

**Section C — New-doc-only chapters:**
For each chapter in the new doc that does not map to any GPG chapter: read the chapter content
and assess which SDP workflow stages it applies to. Propose one of:
- Always-read in Phase N: if the chapter covers concerns that apply to all tasks in that phase
- Conditional: if the chapter applies only to specific task types (propose the trigger condition)

**3d. Present draft to user**
Present the complete draft reading map to the user:
- Section A: the updated tables with mapped chapters substituted
- Section B: coverage notes for unmapped GPG topics (with stub prose)
- Section C: proposed entries for new-doc-only chapters

Ask: "Review each section. For Section B gaps, confirm or revise the stub prose. For Section C
new entries, confirm or correct the proposed SDP stage applicability. Reply with any
corrections and I will update before writing."

Wait for user response. Apply all corrections. Produce the final reading map.

**3e. Final reading map format**
The final reading map must be in the exact format of the bootstrap doc's `## GPG Reading Map`
section: the two tables (always-read by phase, conditional by task type), followed by coverage
notes (Section B), followed by new-doc-only chapter entries (Section C), followed by the
COORDINATOR Dispatch Instruction block (updated to reference new doc paths). This is the content
that will replace the old GPG Reading Map in Phase 4.

---

### Step 4: Phase 4 — Workflow File Updates

**4a. Fresh search**
Run searches across all `.md`, `.ps1`, `.json` files in the solution (including hidden folders,
skills, scripts, tests, docs, and manifests). Search for:
- `GenericProjectGuidlines` (any occurrence)
- `gpg_version` (exact string)
- ` GPG ` and `"GPG"` and `GPG\b` (word-boundary matches to catch prose references — avoid
  matching unrelated substrings)

Group all matches by file. Record: file path, line number, matched text, surrounding context
(2 lines before and after).

**4b. Classify files**
Separate the matched files into two groups:

| Group | Files |
|-------|-------|
| **Bootstrap doc** | `SDP_Sapient-Driven-Principles_v*.md` — append-only, strikethrough approach |
| **Framework files** | Everything else (skill files, scripts, JSON manifests, setup docs, tests) — direct replacement |

**4c. Update framework files**
For each framework file with matches, apply the following substitutions. Read the file first,
apply all substitutions, write back. After writing, read the changed section to verify the
new content is correct before moving to the next file.

| Old pattern | New pattern |
|-------------|-------------|
| `GenericProjectGuidlines_V[version].md` | `[DocName]_V[version_key].md` |
| `GenericProjectGuidlines_Sections/` | `[DocName]_Sections/` |
| `GenericProjectGuidlines_TOC.md` | `[DocName]_TOC.md` |
| `GenericProjectGuidlines_[ChapterName].md` | `[DocName]_[MappedChapterName].md` (use mapping from Step 3b) |
| `filename:standards/GenericProjectGuidlines_{}` | `filename:standards/[DocName]_{}` |
| `"gpg_version"` | `"standards_version"` |
| `gpg_version` (unquoted, in JSON pointer or prose) | `standards_version` |
| Prose `GPG` in procedural steps | `standards doc` (or the user's short name for their doc if they provided one in Step 1) |
| `gpg_excluded_chapters` | `standards_excluded_chapters` |

For `sdp-create-prompt.ps1` specifically: update the hardcoded TOC path variable (currently
`$gpgToc = "standards/GenericProjectGuidlines_Sections/GenericProjectGuidlines_TOC.md"`) to
`$standardsToc = "standards/[DocName]_Sections/[DocName]_TOC.md"` and update all three
references to the variable name in the same file.

For `SDP-Document-List.json` at the solution root: update the path entry for the standards doc
to the new filename.

If a file cannot be read or written, record it as a failure. Continue processing remaining
files. Report all failures at the end of sub-step 4c before proceeding.

**4d. Update bootstrap doc (append-only, strikethrough approach)**
The bootstrap doc (`SDP_Sapient-Driven-Principles_v*.md`) is an append-only historical record.
Never delete content from it. Apply all changes using the following rules:

*Inline prose references to `GPG` in role session steps:*
Apply `~~GPG~~` strikethrough and append ` standards doc` immediately after.
Example: `GPG CHECK` → `~~GPG CHECK~~ STANDARDS CHECK`

*Inline code path references to `GenericProjectGuidlines` filenames:*
For references inside backtick code spans, direct replacement is used (strikethrough does not
render inside code spans). Replace the old path with the new path. The overall strikethrough
of the GPG Reading Map section (sub-step below) provides the historical record for the most
significant path references.

*`"gpg_version"` field name references:*
Replace `gpg_version` with `standards_version` in the state.json template and all prose
references to the field name.

*`gpg_excluded_chapters` references:*
Replace with `standards_excluded_chapters`.

*GPG Reading Map section — full supersession:*
Locate the `## GPG Reading Map` heading. Immediately before it, insert:

```markdown
> **Superseded — [today's date]:** The GPG Reading Map below has been replaced by the
> Standards Doc Reading Map section. The original GPG chapter structure is retained here
> for historical reference. Future agents: if you see un-updated GPG references anywhere
> in this document, use the Standards Doc Reading Map below as the authoritative source.

```

Immediately after the end of the GPG Reading Map section (before the next `---` separator or
`##` heading), append the complete final reading map from Step 3e as a new section:

```markdown
## Standards Doc Reading Map

[content from Step 3e final reading map]
```

After all edits: read back the sections of the bootstrap doc that were changed to verify
correct application before proceeding.

**4e. Report Phase 4 changes**
Output a file-by-file change log:
- File path
- Number of substitutions made
- Brief description of what changed (e.g., "gpg_version → standards_version (3 occurrences),
  TOC path updated")

If any files had failures: list them separately with the specific error. Ask the user to
resolve failures before continuing to Phase 5.

---

### Step 5: Phase 5 — Sanity Check Pass

**5a. Re-run search**
Run the same search from Step 4a across all files again.

**5b. Classify remaining hits**
For each remaining match, classify it as one of:

| Classification | Criteria |
|---------------|----------|
| **Auto-correctable** | Same substitution pattern as Phase 4; was missed in first pass |
| **Intentional — superseded** | Inside strikethrough markup (`~~...~~`) in the bootstrap doc; historical record, do not touch |
| **Intentional — docs** | In append-only design spec docs under `docs/` or `research/`; historical record, do not touch |
| **Ambiguous** | Not clearly intentional or auto-correctable; requires user decision |

**5c. Apply auto-corrections**
Apply all auto-correctable fixes immediately. Report each one.

**5d. Surface ambiguous hits**
For each ambiguous remaining hit: show the user the file path, line number, matched text, and
3 lines of surrounding context. Ask: "Is this an intentional retention or should it be
updated?" Apply the user's decision. Do not proceed past this sub-step until every ambiguous
hit is resolved.

**5e. Confirm clean**
After all resolutions: re-run the search one final time. Confirm to the user that the only
remaining hits are in intentional/historical locations. If any unexpected hits remain, repeat
sub-steps 5b–5d.

---

### Step 6: Phase 6 — Verification

Verify the complete result across three dimensions:

**6a. Doc structure**
- `standards/[DocName]_V[version_key].md` exists and contains the sync rule notice
- `standards/[DocName]_Sections/` exists
- Section file count matches the confirmed chapter count from Step 1f
- `standards/[DocName]_Sections/[DocName]_TOC.md` exists
- Each section file exists and contains the sync rule notice

**6b. Framework file integrity**
- `SDP-Workspace-Setup.json` `json-value` check uses `standards_version` pointer and new
  `filename:standards/[DocName]_{}` match pattern
- `sdp-create-prompt.ps1` contains the new TOC path (search for `[DocName]_Sections`)
- `sdp-shared/ai-skills/sdp-project-worker/SKILL.md` references `standards_version`
- `sdp-shared/ai-skills/sdp-project-reviewer/SKILL.md` references `standards_version` and new TOC path
- `sdp-shared/ai-skills/sdp-project-gate-review/SKILL.md` references `standards_version`
- `SDP-Document-List.json` entry references new doc filename

**6c. Bootstrap doc**
- `## GPG Reading Map` section exists and is preceded by the supersession notice
- `## Standards Doc Reading Map` section exists and follows it
- `standards_version` is used in the state.json template within the bootstrap doc

**Report:** For each check, report Pass or Fail. For any Fail: provide the specific corrective
action the user should take. Then invoke `/sdp-create-banner` for the overall verdict: if every
check passed, `icon=success row=0 row: Status | All standards-setup verification checks
passed.`; if any check failed, `icon=error row=0 row: Status | [N] verification check(s)
failed — see corrective actions above.` Do not report the skill complete if any verification
check fails.

---

## Constraints

- Never run this skill outside the solution root; never resolve reads/writes against non-solution-relative paths.
- The original GPG doc must remain in `standards/` for the entire duration of this skill
  (enforced in Step 1e). Do not rename, move, or delete the GPG doc during execution.
- Never rely on a hardcoded/internal file list for Phase 4 — always re-search fresh; this
  ensures correctness even if new skills have been added since this SKILL.md was written.
- Bootstrap doc updates follow the append-only discipline. Never delete content from
  `SDP_Sapient-Driven-Principles_v*.md`. Use strikethrough for prose supersession; direct replacement
  only for content inside backtick code spans where strikethrough cannot render.
- Chapter name mapping in Phase 4 uses the confirmed mapping from Step 3b. If a GPG chapter
  name appears in a framework file but has no mapping (e.g., for a chapter the new doc omits),
  do not silently delete the reference — surface it to the user with the surrounding context
  and ask how to handle it.
- Never suppress or silently skip a file-write failure — record it and continue; never proceed
  to Phase 5 without reporting all recorded failures.
- Do not invoke other SDP skills (sdp-project-coordinator, sdp-project-worker, etc.) from within this skill.
- Never invoke `sdp-preflight.ps1` from this skill — it validates project runtime
  preconditions, not the solution-root framework files being modified here.

---

## Outputs

- `standards/[DocName]_V[version_key].md` — parent doc with sync rule notices injected
- `standards/[DocName]_Sections/[DocName]_TOC.md` — TOC with chapter index and maintenance instructions
- `standards/[DocName]_Sections/[DocName]_[ChapterName].md` — one file per chapter with sync rule notice and extracted content
- All SDP framework files updated (skill files, scripts, JSON manifests, bootstrap doc)
- Phase 4 change log (file-by-file)
- Phase 5 sanity check report (clean confirmation or user-resolved residuals)
- Phase 6 verification report (pass/fail per check)
