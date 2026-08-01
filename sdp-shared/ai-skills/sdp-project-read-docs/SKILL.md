
## Purpose

Load solution-level docs and a specified project's docs into agent context so subsequent
answers are grounded in actual project content. This skill is project-scoped — it loads one
project's docs alongside solution-level docs. For solution-level orchestration context
(active project auto-resolution and indexing all registered projects), use
`sdp-solution-read-docs` instead.

This skill is read-only — no files are written, edited, or created. All issues detected during
reading are reported to the user; no corrective actions are taken within this skill.

---

## Two-Pathway Loading Model

This skill loads documents via two pathways on every run.

**Pathway 1 — Solution docs (via solution-root Document List):**
`SDP-Document-List.json` at the solution root is read and all entries with
`includeInReadDocs: true` are loaded into context. Paths are resolved relative to the solution
root. This ensures the bootstrap doc and any other solution-level docs are always in context,
regardless of which project is active.

**Pathway 2 — Specified project docs (via project's Document List):**
Docs for the specified project are loaded via `[project]/SDP-Document-List.json`. Only entries
with `includeInReadDocs: true` are loaded; paths are resolved relative to `[project]/`.

---

## Inputs

**Project argument** — the project to load docs for. Resolution order:
1. Invocation argument passed directly (e.g. `sdp-project-read-docs sdp-project_foo`)
2. Sentinel `projects=` attribute in the opening prompt
3. `sdp-project_*` segment in the current session file path
4. `last_active_projects[0]` from `SDP-Solution.json` at the solution root

**`SDP-Document-List.json`** (solution root) — required for Pathway 1. Entries with
`includeInReadDocs: true` are loaded; paths resolved relative to the solution root. If absent,
report by invoking:
```
/sdp-create-banner icon=warning row=0
row: Warning | No SDP-Document-List.json found at solution root — solution docs not loaded.
```
Proceed to Pathway 2.

**`SDP-Solution.json`** — required only if project resolution falls to Level 4. If absent at
that point, halt by invoking:
```
/sdp-create-banner icon=error row=0
row: Error | SDP-Solution.json not found at solution root — cannot resolve active project.
```

**`[project]/SDP-Document-List.json`** — required for Pathway 2. Expected format: a JSON array
of document entry objects, in priority order. Entries are processed in listed order; if context
fills before all files are read, entries later in the array are dropped first.

```json
[
  {
    "path": "sdp-docs/01_concept.md",
    "name": "Project Concept",
    "role": "project",
    "includeInReadDocs": true
  },
  {
    "path": "sdp-docs/00_prompt.txt",
    "name": "Current Prompt",
    "role": "prompt",
    "includeInReadDocs": false
  }
]
```

**Fields:**
- `path` — file path relative to `[project]/` (NOT the solution root)
- `name` — human-readable label used in confirmation output and error reporting
- `role` — semantic type of the document (e.g. `"project"`, `"speq"`, `"prompt"`)
- `includeInReadDocs` — must be explicitly `true` to be loaded; any other value or absence
  means the entry is registered but not loaded

If `[project]/SDP-Document-List.json` is absent, report by invoking:
```
/sdp-create-banner icon=warning row=0
row: Warning | [project]/SDP-Document-List.json is missing — cannot load project document list.
```
Skip to Step 4 (Confirm).

## Procedure

### Step 1: Resolve Project

**If an invocation argument was passed:** first strip a `--no-tone` token if present anywhere
in it (that token is consumed by the L1 shim's tone-suppression check — see
`.claude/skills/sdp-project-read-docs/SKILL.md` — and is never part of a project identifier). If
anything remains after stripping, use it directly as `[project]`. If nothing remains (the
argument was `--no-tone` alone, with no project name): treat this as "no argument" and fall
through to the three-level order below. Proceed to Step 2.

**If no argument:** resolve via the three-level order:
1. Check the opening prompt for a sentinel `projects=` attribute. If present: use the first
   comma-separated value as `[project]`. Proceed to Step 2.
2. Check the current session file path for an `sdp-project_*` segment. If found: use it as
   `[project]`. Proceed to Step 2.
3. Read `SDP-Solution.json` from the solution root. If absent, halt by invoking:
   ```
   /sdp-create-banner icon=error row=0
   row: Error | SDP-Solution.json not found at solution root — cannot resolve active project.
   ```
   Parse `last_active_projects[0]`. If empty or absent: report by invoking:
   ```
   /sdp-create-banner icon=warning row=0
   row: Warning | No active project in SDP-Solution.json — project docs not loaded.
   ```
   Skip to Step 4.

### Step 2: Pathway 1 — Load Solution Docs

1. Read `SDP-Document-List.json` at the solution root. If absent, report by invoking:
   ```
   /sdp-create-banner icon=warning row=0
   row: Warning | No SDP-Document-List.json at solution root — solution docs not loaded.
   ```
   Proceed to Step 3.
2. Parse JSON. Separate entries into two groups:
   - **Load list** — entries where `includeInReadDocs` is explicitly `true`, in array order
   - **Registered only** — all other entries (field absent, `false`, or any other value)
3. For each entry in the load list, in order: read the file at `[entry.path]` (resolved
   relative to the solution root).
4. If a file cannot be read: record it as unreadable by `entry.name`; continue.
5. If context capacity is reached: stop loading; record unloaded entries by name; continue
   to Step 3 with what was loaded.

### Step 3: Pathway 2 — Load Project Docs

1. Read `[project]/SDP-Document-List.json`. If missing, report by invoking:
   ```
   /sdp-create-banner icon=warning row=0
   row: Warning | [project]/SDP-Document-List.json is missing — cannot load project document list.
   ```
   Skip to Step 4.
2. Parse JSON. Separate entries into two groups:
   - **Load list** — entries where `includeInReadDocs` is explicitly `true`, in array order
   - **Registered only** — all other entries (field absent, `false`, or any other value)
3. For each entry in the load list, in order: read the file at `[project]/[entry.path]`.
4. If a file cannot be read: record it as unreadable by `entry.name`; continue.
5. If context capacity is reached: stop loading; record unloaded entries by name; continue
   to Step 4.

### Step 4: Confirm

Report to the user in one sentence that the skill is complete. List:
- Project resolved to: `[project]` and the resolution method used (argument / sentinel /
  path extraction / SDP-Solution.json)
- Solution docs loaded by name (Pathway 1), or "not loaded" with reason
- Project docs successfully loaded by name (Pathway 2)
- Any docs that were unreadable or skipped due to context limits
- Count of registered-only entries not loaded (both pathways)

Do not include documentation content in this response unless the user explicitly asks.

## Constraints

- Read-only — do not write, edit, or suggest changes to any file.
- Pathway 1 (solution docs): never load an entry from the solution-root
  `SDP-Document-List.json` unless `includeInReadDocs` is explicitly `true`. Paths resolved
  relative to the solution root.
- Pathway 2 (project docs): never load an entry unless `includeInReadDocs` is explicitly
  `true`. Paths resolved relative to `[project]/`, not the solution root.
- Do not invoke other skills within this skill, even if issues are detected in the documentation.
- Do not guess which files to read if any document list is missing.
- Do not summarize or condense documentation content to fit more files into context — report
  the limit and stop.
- Do not include documentation content in the Step 4 confirmation unless the user explicitly
  asks.

## Outputs

- Agent context updated with solution docs (Pathway 1) and specified project docs (Pathway 2).
- One-sentence confirmation listing: project resolved, solution docs loaded, project docs
  loaded by name, any unreadable or skipped, and registered-only entry counts.
- No files are written, created, or modified.
