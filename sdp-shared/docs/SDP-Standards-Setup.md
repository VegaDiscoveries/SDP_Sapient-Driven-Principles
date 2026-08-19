<img src="images/SDP_DocsLogo_WithText_0700x0163.png" alt="SDP Logo" width="375">

# SDP Standards Doc Setup

| Field | Value |
|-------|-------|
| **Version** | 1.0.0 |
| **Updated** | 2026-06-25 |
| **Skill** | `/sdp-standards-setup` |

**Purpose:** Explains how SDP consumers use a custom standards doc in place of the default
GenericProjectGuidlines (GPG). Covers the three consumer scenarios, what the skill automates,
where user input is required, and how to maintain the standards doc after initial setup.

---

## Consumer Scenarios

### Scenario A — Use GPG as-is (default)

No action required. The SDP framework ships with GPG pre-integrated. Run `/sdp-project-read-docs` to
load it. Proceed directly to workspace setup.

### Scenario B — Replace GPG with a structured custom doc

Your standards doc has identifiable chapters (H1 or H2 headings). Run `/sdp-standards-setup`.
The skill handles all structural scaffolding and framework file updates. User input is required
at chapter confirmation (Phase 1) and reading map review (Phase 3).

### Scenario C — Replace GPG with a flat or minimally-structured doc

Your standards doc is a single narrative without clear chapter boundaries, or its sections
do not map cleanly to the GPG chapter topics. Run `/sdp-standards-setup`. In Phase 1, you
will be asked to confirm the chapter breakdown — if the skill cannot identify clear chapters
from headings, it will describe what it found and ask you to define the boundaries manually.
Phase 3 will have more gaps (GPG topics without equivalents), which the skill will fill with
generated stub prose that you review and confirm before it is written.

---

## What the Skill Automates

### Phase 1 — Doc Preparation and Precondition Checks

The skill enforces four requirements before any scaffolding begins:

1. **Location** — the standards doc must be in `standards/`. The skill moves it there
   automatically if it is not.
2. **Version string** — if the filename lacks a version segment (`V[N].[N]_[YYYYMMDD]`),
   the skill proposes `V1.0_[today]` and asks you to confirm before renaming.
3. **Markdown format** — if the file is not `.md`, the skill converts it and asks you to
   verify the conversion before proceeding.
4. **GPG presence** — the original GPG doc must be in `standards/` for Phase 3 cross-referencing.
   If it is not found, the skill halts and requires it to be restored before continuing.

**User input required:** chapter confirmation table. The skill presents one row per detected
chapter with its proposed section filename. You approve or correct before scaffolding starts.

### Phase 2 — Scaffolding

Fully automated after Phase 1 confirmation. The skill:

- Creates `standards/[DocName]_Sections/`
- Extracts each chapter into its own section file with a sync rule notice header
- Creates a TOC file with a chapter index table and maintenance instructions
- Injects sync rule and TOC maintenance notices into the parent doc

No user input is required in this phase.

### Phase 3 — Reading Map Generation

The skill reads the GPG chapter list, the bootstrap doc's existing GPG Reading Map, and your
new doc's chapter list. It cross-references them and builds a draft reading map covering:

- **Mapped chapters** — GPG chapter mapped to the corresponding chapter in your doc
- **Coverage notes** — for GPG topics your doc does not cover, the skill distills 3–5 sentences
  of key principles from the GPG chapter so agents still receive guidance without a section file
  to read
- **New-doc-only chapters** — chapters in your doc that have no GPG equivalent; the skill
  proposes which SDP workflow stages they apply to

**User input required:** you review the complete draft reading map, confirm or revise coverage
note prose, and confirm or correct the SDP stage proposals for new-doc-only chapters. The skill
does not write anything to the bootstrap doc until you confirm the reading map.

### Phase 4 — Workflow File Updates

The skill performs a fresh search across all `.md`, `.ps1`, and `.json` files in the solution
at execution time — it does not maintain a hardcoded list of files to update. Every framework
file that references the old GPG doc name, GPG section paths, or the `gpg_version` field is
updated automatically.

**Bootstrap doc updates follow the append-only discipline.** The `## GPG Reading Map` section
is retained with a supersession notice prepended to it. The new `## Standards Doc Reading Map`
is appended immediately after. This preserves the historical GPG chapter structure so future
agents can identify any references that were missed and understand what changed.

Inline prose references to "GPG" in role session steps are updated with strikethrough:
`~~GPG CHECK~~` → `~~GPG CHECK~~ STANDARDS CHECK`. References inside backtick code spans
receive direct replacement (strikethrough does not render inside code spans).

The field `gpg_version` is renamed `standards_version` everywhere in framework files.

### Phase 5 — Sanity Check Pass

After Phase 4, the skill re-runs the search. Remaining hits are classified:
- Auto-correctable → fixed automatically
- Intentional/historical (in strikethrough content or append-only design docs) → left as-is
- Ambiguous → surfaced to you with context; you decide

The phase does not complete until all ambiguous hits are resolved.

### Phase 6 — Verification

The skill checks that the sections folder, section files, TOC, and all framework file updates
are in place. Reports pass/fail per check. Any failure surfaces a specific corrective action.

---

## The Standards Doc Contract

For SDP to use your standards doc, it must satisfy three structural requirements after the
skill runs:

1. **Parent doc** — `standards/[DocName]_V[version_key].md` with a sync rule notice and TOC
   maintenance notice at the top (injected by the skill in Phase 2).

2. **Sections folder** — `standards/[DocName]_Sections/` containing:
   - `[DocName]_TOC.md` — chapter index with maintenance instructions
   - One `[DocName]_[ChapterName].md` per chapter — extracted content with sync rule notice

3. **Sync rules** — the parent doc and every section file carry notices instructing agents to
   mirror any edit in both directions. This prevents drift between the parent and its sections.

The sections folder exists so agents can read a single chapter in isolation without loading
the full parent doc. This is the same optimization used for the GPG section files.

---

## `standards_version` Field

`state.json` for every project contains a `standards_version` field (formerly `gpg_version`).
Its value is the version key segment of your standards doc filename.

Example: if your doc is `CompanyStandards_V1.0_20260625.md`, set:
```json
"standards_version": "V1.0_20260625"
```

The preflight check (`sdp-preflight.ps1`) validates that a file named
`standards/[DocName]_V{standards_version}.md` exists. If the version key in `state.json` does
not match the actual filename, preflight fails and COORDINATOR halts.

When you update your standards doc to a new version (see Amendment Rules below), update
`standards_version` in every project's `state.json` to match the new version key.

---

## Stub Prose Convention

When your standards doc does not cover a topic that GPG addressed, the reading map includes
a coverage note in place of a section file reference:

```markdown
> **Coverage note — [Topic] (from GPG Ch. N):** The registered standards doc does not contain
> a dedicated [topic] chapter. The following principles apply to tasks in this area:
> [3–5 sentences of key principles]
> WORKER and REVIEWER should apply these principles directly; no section file read is required.
```

COORDINATOR includes the relevant coverage notes in WORKER/REVIEWER dispatch files for tasks
where that topic applies. WORKER reads them directly from the reading map rather than reading
a section file. This maintains standards guidance coverage even for topics your doc omits.

---

## Amendment Rules

When you update your standards doc after initial setup:

**For content changes to an existing chapter (no structural change):**
1. Edit the chapter in the parent doc.
2. Mirror the edit in the corresponding section file.
3. No skill re-run is required.

**For chapter additions:**
1. Add the chapter to the parent doc.
2. Re-run Phase 2 of the skill (create section file + update TOC) — you can invoke the skill
   and it will detect the new chapter and offer to scaffold it.
3. Add the new chapter to the reading map in the bootstrap doc manually, or re-run Phase 3.

**For chapter removals:**
1. Delete or strikethrough (append-only) the chapter content in the parent doc.
2. Delete the corresponding section file from `[DocName]_Sections/`.
3. Remove the chapter from `[DocName]_TOC.md` and from the reading map in the bootstrap doc.

**For version bumps (new version of the doc):**
1. Rename the parent doc file to include the new version key.
2. Update `standards_version` in each project's `state.json` to the new version key.
3. Update the `SDP-Workspace-Setup.json` `json-value` check to use the new version key
   (the `match` field's `filename:` pattern).
4. Update `SDP-Document-List.json` entry to the new filename.
5. Run preflight to confirm the version check passes.

---

## Migration Guide — Applying to an Existing Solution

If the solution already has active projects with `state.json` files containing `gpg_version`,
rename the field in each live `state.json` to `standards_version` after running the skill.
The skill updates the template and all framework files; it does not touch live per-project
`state.json` files.

Steps:
1. Run `/sdp-standards-setup` — updates all framework files.
2. For each `sdp-project_*/` folder: edit `.sdp-workflow/state.json`, rename `gpg_version`
   to `standards_version`.
3. Run `sdp-preflight.ps1 -workspaceRoot .\[project]` for each project to confirm the
   version check passes with the new field name.
