## Purpose

Prevent duplicate effort, detect partially-complete states, and ensure clean resumption of
interrupted work before a WORKER session begins implementation on any task.

## Project Scope

This skill is invoked inside a WORKER session. By the time it runs, the WORKER has already
resolved `[resolved_project]` from its session file `Project:` field. All artifact scans in
this skill must be scoped to `[resolved_project]` — do not search the solution root or assume
the working directory is the project root.

`[resolved_project]` is the path relative to the solution root, e.g., `sdp-project_AppName.API`.
All search paths must be prefixed accordingly (e.g., `[resolved_project]/src/`,
`[resolved_project]/migrations/`).

## Inputs

- `[resolved_project]` — received from the enclosing WORKER session (already resolved before
  this skill is invoked)
- Task description from the phase file (read as part of WORKER session step 5)
- Task type — inferred from the task description

## Procedure

### Step 1: Scan for Prior Artifacts

Search the codebase, filesystem, database, and migrations for artifacts related to this task.
Scope ALL searches to `[resolved_project]` — do not scan outside this folder. Scope the
search within the project to what the task type implies:

| Task type | What to search for |
|-----------|-------------------|
| Create database | Database existence, schema state, applied migration journal |
| Implement entity / class | Project source for the class files (e.g., `[resolved_project]/src/`) |
| Create migration | Migrations folder for timestamped migration files (e.g., `[resolved_project]/migrations/`) |
| Seed data | Target table contents or post-deploy scripts (e.g., `[resolved_project]/data/`) |
| Other | Infer the primary artifact from the task description and search for it under `[resolved_project]/` |

Look specifically for partial or incomplete artifacts: a class with only some properties,
a table missing columns, a script that was partially applied.

### Step 2: Classify State

Assign exactly one classification:

| State | Definition |
|-------|------------|
| **Not Started** | No artifacts found; no evidence of prior work |
| **In Progress / Incomplete** | Artifacts exist but work is clearly partial |
| **Complete** | Task is finished and meets or exceeds all deliverables in the task description |

### Step 3: Act Based on Classification

**Not Started:** Proceed immediately. No confirmation required.

**In Progress / Incomplete:**
1. Invoke `/sdp-create-banner icon=warning,warning,warning row=0,1,2 row: Artifacts | [what
   artifacts were found] row: Incomplete | [what appears incomplete] row: Last state | [file
   dates, git history if available]` to report to the user what artifacts were found; what
   appears incomplete; last observed state (file dates, git history if available)
2. Ask: "Should I continue from where this was left off, discard and restart, or inspect
   first?"
3. Proceed only after the user confirms
4. Document the resumption or restart choice in the Completed blockquote

**Complete:**
1. Do not re-implement the task
2. Append a note to the phase file: "Pre-work verification: task already complete as of
   [date if determinable]. No work performed."
3. Notify COORDINATOR — do not proceed to implementation

## Constraints

- Never begin WORKER implementation without first executing this skill.
- Do not classify as Not Started after a shallow search — scan all artifact types implied
  by the task description before concluding nothing exists.
- Do not classify as Complete unless all deliverables in the task description are met, not
  just that some artifacts exist.
- Never resume or restart an In Progress / Incomplete task without explicit user
  confirmation.
- Never re-implement a task classified as Complete — append the already-complete note and
  notify COORDINATOR instead of proceeding to implementation.

## Outputs

- One of three outcomes: proceed to implementation / await user confirmation / notify
  COORDINATOR of already-complete task
- For In Progress / Incomplete tasks: resumption or restart choice documented in the
  Completed blockquote
- For Complete tasks: note appended to the phase file
