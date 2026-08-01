
## Purpose

Load the project's top-level documentation files into agent context so subsequent answers are
grounded in actual project content. This skill is read-only — no files are written, edited,
or created. All issues detected during reading are reported to the user; no corrective actions
are taken within this skill.

---

## Three-Pathway Loading Model

This skill loads documents via three pathways on every run.

**Pathway 1 — Solution docs (via solution-root Document List):**
`SDP-Document-List.json` at the solution root is read and all entries with
`includeInReadDocs: true` are loaded into context. Paths are resolved relative to the solution
root. This governs what solution-level docs (including the bootstrap doc) are loaded at every
session start.

**Pathway 2 — Active project docs (via active project's Document List):**
All docs for the active project are loaded via `[active_project]/SDP-Document-List.json`. The
active project is resolved from `SDP-Solution.json` (`last_active_projects[0]`). Only entries
with `includeInReadDocs: true` are loaded; paths are resolved relative to `[active_project]/`.

**Pathway 3 — Other project doc index (in context, not loaded):**
For each project registered in `SDP-Solution.json` other than the active project, its
`SDP-Document-List.json` is read and entries with `includeInReadDocs: true` are compiled into
a reference list retained in context. These files are NOT loaded. The Confirm step appends:
> "If this task involves coordination across more than one project, load the following project
> docs before proceeding:
> - [project-name]: [file path 1], [file path 2], ...
> - [project-name]: [file path 1], ..."

If only one project is registered (or no other projects exist), Pathway 3 is skipped and the
note is omitted.

---

## Inputs

**`SDP-Document-List.json`** (solution root) — required for Pathway 1. Entries with
`includeInReadDocs: true` are loaded; paths resolved relative to the solution root. If absent:
report "⚠️ No `SDP-Document-List.json` found at solution root — solution docs not loaded."
Proceed to Pathway 2.

**`SDP-Solution.json`** — located at the solution root. Read to resolve the active project
(`last_active_projects[0]`) and the full `projects` array. Required for Pathways 2 and 3. If
absent, halt with:
> "⛔ `SDP-Solution.json` not found at solution root. Run `/sdp-workspace-setup` to create it
> before proceeding."

**`[active_project]/SDP-Document-List.json`** — required for Pathway 2; located inside the
resolved active project folder. Expected format: a JSON array of document entry objects, in
priority order. Entries are processed in listed order; if context fills before all files are
read, entries later in the array are dropped first.

```json
[
  {
    "path": "sdp-docs/01_concept.md",
    "name": "Project Concept",
    "role": "project",
    "includeInReadDocs": true
  },
  {
    "path": "VirtualCoinFolio.API.speq.md",
    "name": "Tech Contract",
    "role": "speq",
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
- `path` — file path relative to `[active_project]/` (NOT the solution root)
- `name` — human-readable label used in confirmation output and error reporting
- `role` — semantic type of the document (e.g. `"project"`, `"speq"`, `"prompt"`)
- `includeInReadDocs` — must be explicitly `true` to be loaded by this skill; any other value
  or absence means the entry is registered but not loaded

If `SDP-Document-List.json` is absent for the active project the skill cannot load project
docs — see Step 2 error handling.

**`[other_project]/SDP-Document-List.json`** — read for Pathway 3 index only; one document
list file is expected per registered project that is not the active project. If any are absent:
record the missing project name in the Confirm output; continue without halting.

## Procedure

### Step 1: Pathway 1 — Load Solution Docs

1. Read `SDP-Document-List.json` at the solution root. If absent: report
   "⚠️ No `SDP-Document-List.json` at solution root — solution docs not loaded." Proceed to
   Step 2.
2. Parse JSON. Separate entries into two groups:
   - **Load list** — entries where `includeInReadDocs` is explicitly `true`, in array order
   - **Registered only** — all other entries (field absent, `false`, or any other value)
3. For each entry in the load list, in order: read the file at `[entry.path]` (resolved
   relative to the solution root).
4. If a file cannot be read: record it as unreadable by `entry.name`; continue to the next
   entry without halting.
5. If context capacity is reached before all entries are read: stop loading; record which
   entries were not loaded by name; continue to Step 2 with what was loaded.

### Step 2: Pathway 2 — Load Active Project Docs

**Level 0 — Invocation argument (user or agent):** If a project path was passed as an
argument on invocation, skip sub-steps 1–2. Read `SDP-Solution.json` to validate the
argument against the `projects` array. If valid: use it as `[active_project]` and proceed
to sub-step 3. If invalid: reject with "⛔ Invocation argument '[value]' does not match
any project registered in `SDP-Solution.json`. Available: [list]. Correct the argument and
re-run."

1. Read `SDP-Solution.json` from the solution root using the Read tool. If absent: halt with:
   "⛔ `SDP-Solution.json` not found at solution root. Run `/sdp-workspace-setup` to create it
   before proceeding."
2. Parse `last_active_projects[0]` from `SDP-Solution.json`. Capture the full `projects` array
   for use in Step 3. If `last_active_projects` is empty or absent: read the `projects` array.
   - If `projects` contains exactly 1 entry: use it as `[active_project]` and proceed to
     sub-step 3.
   - If `projects` contains 2 or more entries: read `.sdp-solution-workflow/state.json`'s
     `current_phase` field.
     - If `current_phase` is not `null` (phases 1–7 still in progress for this solution — no
       project has been assigned real work yet, per the solution-scoped phase pipeline): no
       active project exists to resolve. Report "ℹ️ No active project yet — solution is in
       phases 1–7 (current_phase: [value]); project identity begins at Phase 7's decomposition."
       Skip to Step 3 without loading any project docs. Do not prompt.
     - If `current_phase` is `null`, or `.sdp-solution-workflow/state.json` cannot be read or has
       no `current_phase` field (phase status unknown — e.g. a pre-solution-scoped-model
       workspace): fall back to the original behavior — list the available projects to the user
       and prompt them to select one. Wait for the user's response, then use the selected value
       as `[active_project]` and proceed to sub-step 3.
   - If `projects` is empty or absent: report "⚠️ No projects registered in
     `SDP-Solution.json` — cannot resolve active project. Register at least one project and
     re-run." Skip to Step 3.

3. Read `[active_project]/SDP-Document-List.json` using the Read tool. If missing: report
   "⚠️ `[active_project]/SDP-Document-List.json` is missing — cannot load project document
   list." Skip to Step 3.
4. Parse the JSON array. Separate entries into two groups:
   - **Load list** — entries where `includeInReadDocs` is explicitly `true`, in array order
   - **Registered only** — all other entries (field absent, `false`, or any other value)
5. For each entry in the load list, in order: read the file at
   `[active_project]/[entry.path]` using the Read tool.
6. If a file cannot be read: record it as unreadable by `entry.name`; continue to the next
   entry without halting.
7. If context capacity is reached before all entries are read: stop loading; record which
   entries were not loaded by name; continue to Step 3 with what was loaded.

### Step 3: Pathway 3 — Index Other Project Docs

1. From the `projects` array captured in Step 2: identify all entries that are not
   `[active_project]`. If none: skip to Step 4.
2. For each other project, read `[project]/SDP-Document-List.json`. If absent: record
   "[project] — document list not found"; continue to the next project.
3. Parse JSON. Collect entries where `includeInReadDocs` is explicitly `true`.
4. Do NOT read or load these files. Retain the compiled list in context only.
5. If any project yields an empty load list (no `includeInReadDocs: true` entries): note
   that project as "no loadable docs registered."

### Step 4: Confirm

Report to the user in one sentence that the skill is complete. List:
- Solution docs loaded by name (Pathway 1), or "not loaded" with reason
- Active project docs successfully loaded by name (Pathway 2)
- Any docs that were unreadable or skipped due to context limits (Pathways 1 and 2)
- Count of registered-only entries not loaded (Pathways 1 and 2)
- Other project doc index (Pathway 3) — each project name and its available doc names

If Pathway 3 produced any results, append in-context note:
> "If this task involves coordination across more than one project, load the following project
> docs before proceeding:
> - [project-name]: [file path 1], [file path 2], ...
> - [project-name]: [file path 1], ..."

Do not include documentation content in this response unless the user explicitly asks.

## Constraints

- Read-only — do not write, edit, or suggest changes to any file.
- Pathway 1 (solution docs): do not load entries from the solution-root
  `SDP-Document-List.json` unless `includeInReadDocs` is explicitly `true`. Paths resolved
  relative to the solution root.
- Pathway 2 (active project docs): do not read files whose `includeInReadDocs` is not
  explicitly `true`. Paths are resolved relative to `[active_project]/`, not the solution root.
- Pathway 3 (other project index): index only during this skill's execution — do not load docs
  for any non-active project within this skill run. The indexed list and in-context note are
  how the agent knows what to load when a task requires multi-project coordination.
- Do not invoke other skills within this skill, even if issues are detected in the documentation.
- Do not guess which files to read if any document list is missing.
- Do not summarize or condense documentation content to fit more files into context — report
  the limit and stop.

## Outputs

- Agent context updated with solution docs (Pathway 1), active project docs (Pathway 2), and
  an in-context reference list of other project docs (Pathway 3 — not loaded).
- One-sentence confirmation listing: solution docs loaded (Pathway 1), project docs loaded
  (Pathway 2), other project doc index (Pathway 3), any unreadable or skipped, and
  registered-only entry counts.
- In-context note (when Pathway 3 produces results): which project doc lists are available
  and when to load them.
- No files are written, created, or modified.
