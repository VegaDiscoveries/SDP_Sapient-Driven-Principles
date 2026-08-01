## Purpose

Run a SOLUTION_WORKER session: decompose the active solution task into child project tasks,
dispatch project workers directly across all involved projects (no intermediate
`sdp-project-coordinator`), and set the solution task to `SOL_WORK_COMPLETE` after all child workers
complete.

This skill owns the bidirectional link between the solution task entry and its child project
tasks. It writes `children` entries on the solution task and `parent` fields on each child.
It does not perform review, integration checking, or cascade evaluation — those are
`sdp-solution-reviewer` responsibilities.

## Inputs

- `SDP-Solution.json` (solution root) — provides `active_solution_task`
- `.sdp-solution-workflow/state.json` (solution root) — provides the solution task entry,
  `children` list, `dispatch_mode`, and `last_session` counter
- `.sdp-solution-workflow/sessions/` (solution root) — session files written here
- Each child project's `.sdp-workflow/state.json` (including `active_phase_file`) and
  `.sdp-workflow/registry.md` (Phase File column, fallback when `active_phase_file` is absent)
  — read to identify the correct phase file and to confirm child task status after each
  dispatch. Never assume a fixed phase-file naming convention — it does not match every
  project's layout.

## Procedure

### Step 1: Read SDP-Solution.json

Read `SDP-Solution.json` at the solution root. Extract `active_solution_task`.

If `SDP-Solution.json` is absent: halt — invoke:
> `/sdp-create-banner icon=error row=0 row: Status | SDP-Solution.json not found at solution root. Run /sdp-workspace-setup to create it before proceeding.`

If `active_solution_task` is `null` or missing: halt — invoke:
> `/sdp-create-banner icon=error row=0 row: Status | SDP-Solution.json has no active_solution_task. Set an active solution task before invoking sdp-solution-worker.`

### Step 2: Read Solution State and Confirm Preconditions

Read `.sdp-solution-workflow/state.json` at the solution root.

If absent: halt — invoke:
> `/sdp-create-banner icon=error row=0 row: Status | .sdp-solution-workflow/state.json not found. Solution workflow state has not been initialized — run solution setup to create it.`

Locate the task entry in the `tasks` array whose `id` matches `active_solution_task`. Extract:

- `status` — must be `SOL_PENDING`. If not `SOL_PENDING`: halt — invoke:
  > `/sdp-create-banner icon=error row=0 row: Status | Solution task [id] has status [status] — expected SOL_PENDING. A sdp-solution-worker session may only begin when the solution task is SOL_PENDING. Run sdp-solution-coordinator to assess the current state.`
- `children` — the existing children array (may be empty on first invocation)
- `dispatch_mode` — `"synced"` (default if absent) or `"sequenced"`
- `last_session` — the top-level integer counter from `.sdp-solution-workflow/state.json`

If no task entry matches `active_solution_task`: halt — invoke:
> `/sdp-create-banner icon=error row=0 row: Status | No task entry for [active_solution_task] found in .sdp-solution-workflow/state.json. State file may be out of sync with SDP-Solution.json — verify both files.`

### Material Decision Escalation Check

Before suggesting, selecting, or introducing a language, runtime, framework, library/package (any
source/registry), IDE/tool/plugin, database/data-platform engine, cloud/hosting provider,
third-party API/service, or anything similar that is not already explicitly settled — in `.speq`
(project-scoped, from Phase 7 onward) or, pre-Phase-7, in `01_concept.md`/`03_expanded_concept.md`/
a prior resolved Material Decision Escalation record — or an architectural pattern with no GPG
precedent: stop. If `SDP-Config.json` `materialDecisionEscalation.enabled` is `true` (default), do
not proceed. Halt per the bootstrap doc's Halt Behavior Contract instead — set `workflow_status:
"halted"`, `halt_reason` naming the decision, and append a 2-4 option table (per the Gap
Resolution Format) before ending the session. See the bootstrap doc's Material Decision Escalation
section (Dispatch and Halt Contracts).

### Step 3: Decompose Solution Task into Child Project Tasks (First Worker Session Only)

If `children` is empty (no child tasks have been created yet):

1. Read the solution task's `description` field to understand the cross-project scope.
2. For each project involved in this solution task, decompose the work into a concrete project-
   scoped task. Each child task must:
   - Reference the correct phase file for that project: read `active_phase_file` from
     `[project_path]/.sdp-workflow/state.json`. If absent, read
     `[project_path]/.sdp-workflow/registry.md`'s Phase File column for that project's
     `current_phase`. Never assume a fixed filename (e.g. `sdp-docs/05_refined_plan.md`) — it
     does not match every project's naming.
   - Have a unique task ID in that project's sequence (read the project's phase state file —
     derived from the phase file path above by replacing its trailing `.md` with
     `_state.json` — to determine the next available ID)
   - Have a clear description scoped to what that project must implement

3. For each child task, write a task entry into the project's phase state file — derived from
   the phase file path identified in sub-step 2 above by replacing its trailing `.md` with
   `_state.json`. The entry must include:

   ```json
   {
     "id": "[task-id]",
     "status": "PENDING",
     "parent": "[active_solution_task]",
     "flags": [],
     "eval_cycles": 0,
     "eval_cycle_attempts": 0,
     "last_session": "",
     "last_updated": "[ISO_DATE]"
   }
   ```

4. Write the task description into the project's phase file (the path identified in sub-step 2
   above) using the standard task entry format for that phase file. Place the entry at the
   correct location in the file (after existing tasks or in the designated pending-tasks
   section).

5. Populate the `children` array in the solution task entry in
   `.sdp-solution-workflow/state.json`. Each child entry must be:

   ```json
   {
     "project": "[project_path]",
     "task_id": "[task-id]",
     "phase_file": "[the phase file path identified in sub-step 2 above, relative to project root — this pins the path Step 5 and Step 6 read back from]",
     "cached_status": "PENDING"
   }
   ```

   Write the updated task entry back to `.sdp-solution-workflow/state.json`. Update the
   top-level `updated` field to the current ISO date.

### Step 4: Dispatch Project Workers

For each child task in the `children` array that is not yet at `WORK_COMPLETE`:

**Determine `dispatch_mode`:**

- `"synced"` (default — absent or explicitly set): dispatch all pending children
  simultaneously as parallel subagents using the Agent tool. Each subagent receives its
  own invocation of `sdp-project-worker` with the `Project:` field set to its project path. Do not
  advance to Step 5 until all parallel subagents have returned.

- `"sequenced"`: dispatch children one at a time in the order they appear in the `children`
  array. Dispatch the next child only after the current child has confirmed `WORK_COMPLETE`
  (verified in Step 5). Do not dispatch remaining children until the current one completes.

**For each dispatched child (in both modes), the dispatch must:**
- Write a session file to `.sdp-solution-workflow/sessions/session-NNN.md` (incrementing the
  top-level `last_session` counter in `.sdp-solution-workflow/state.json` before writing, and
  zero-padding to three digits: `session-001.md`). The session file must include a
  `Project: [project_path]` field so `sdp-project-worker` resolves the project via Level 1 project
  resolution.
- Invoke `sdp-project-worker` via the Agent tool, passing the session file path and project path.

**Direct dispatch rule:** Do NOT invoke `sdp-project-coordinator` for any child project in this flow.
`sdp-project-coordinator` is retained exclusively for single-project tasks (tasks with no `parent`
field). A child task with a `parent` field is owned by the solution orchestration cycle and
dispatched directly.

### Step 5: Confirm Child Completion and Update cached_status

After each child worker returns (or after all parallel workers return in synced mode):

1. Read the child's authoritative status from its project state file — derived from the
   `phase_file` value recorded on this child's `children` entry (Step 3.5) by replacing its
   trailing `.md` with `_state.json` — and locate the entry matching `task_id`.
2. Update `cached_status` on the corresponding `children` entry in the solution task entry in
   `.sdp-solution-workflow/state.json` to reflect the confirmed status.
3. Write the updated task entry back to `.sdp-solution-workflow/state.json`. Update the
   top-level `updated` field to the current ISO date.

### Step 6: Handle DIAGNOSIS_BLOCKED

After each child worker returns, check the child's project state entry for a `DIAGNOSIS_BLOCKED`
flag (present in the entry's `flags` array or as a top-level state flag — check both the task
entry and the project state file's top-level flags as applicable).

If any child has `DIAGNOSIS_BLOCKED`:

1. Add `"SOL_DIAGNOSIS_BLOCKED"` to the solution task entry's `flags` array in
   `.sdp-solution-workflow/state.json`. Write the update.
2. Do NOT dispatch any remaining child workers.
3. Write the session outcome file (Step 8 — partial outcome noting the blocked diagnosis).
4. Update `SDP-Solution.json` `updated` field (Step 9).
5. Record the block (non-blocking — ignore any failure and continue): run
   `./sdp-shared/scripts/sdp-workflow-log.ps1 -trigger "diagnosis.blocked" -role
   "SOLUTION_WORKER" -workItem "[task_id]" -outcome "SOL_DIAGNOSIS_BLOCKED" -reason
   "[task_id] in [project_path] has a blocked diagnosis; remaining children not dispatched"` via
   the PowerShell tool.
6. Notify the user — invoke:
   > `/sdp-create-banner icon=error row=0 row: Status | [task_id] in [project_path] has a blocked diagnosis — user decision required before this solution task can continue. Resolve the blocked diagnosis in that project, then re-invoke sdp-solution-worker to resume.`
7. Terminate. Do not advance to Step 7.

### Step 7: Set SOL_WORK_COMPLETE

Once all children are confirmed at `WORK_COMPLETE` (all `cached_status` values updated):

1. Set the solution task `status` to `"SOL_WORK_COMPLETE"` in the task entry in
   `.sdp-solution-workflow/state.json`.
2. Update `last_updated` on the task entry and the top-level `updated` field to the current
   ISO date.
3. Write the updated `.sdp-solution-workflow/state.json`.

### Step 8: Write Session Outcome File

Increment the top-level `last_session` counter in `.sdp-solution-workflow/state.json` (if not
already incremented for the final dispatch in Step 4). Write a session file at
`.sdp-solution-workflow/sessions/session-NNN.md` (zero-padded to three digits).

Session file format:

```markdown
# Solution Session [NNN]

| Field | Value |
|-------|-------|
| Solution Task | [active_solution_task] |
| Role | SOLUTION_WORKER |
| Outcome | [SOL_WORK_COMPLETE or SOL_DIAGNOSIS_BLOCKED] |
| Date | [ISO_DATE] |

## Child Tasks Dispatched

| Project | Task ID | Phase File | Final Status |
|---------|---------|------------|--------------|
[one row per child — project path, task ID, phase file, confirmed status]

## Notes

[Any notable decisions made during decomposition, dispatch, or blocked-diagnosis handling.
"None" if no exceptional conditions occurred.]
```

Update `last_session` on the solution task entry in `.sdp-solution-workflow/state.json` to
the session identifier written (e.g., `"session-003"`). Write the update.

### Step 9: Update SDP-Solution.json

Read `SDP-Solution.json`. Update the `updated` field to the current ISO date. Write the file
back. Do not modify any other field.

Session ends.

## Constraints

- This skill dispatches `sdp-project-worker` directly — never `sdp-project-coordinator` — for child tasks
  that carry a `parent` field.
- This skill does not perform review, integration checking, or cascade evaluation. Set
  `SOL_WORK_COMPLETE` and terminate — do not invoke `sdp-solution-reviewer`.
- Do not read `SDP-Solution.json` `last_active_projects` for project resolution. Project
  paths come from the solution task's `children` array (populated in Step 3) or from the
  dispatch context provided by `sdp-solution-coordinator`.
- Never write session files inside a `sdp-project_*` folder — they belong in
  `.sdp-solution-workflow/sessions/` at the solution root.
- `cached_status` is a convenience field only. The authoritative status is always the child's
  project state file. Do not make dispatch decisions based solely on `cached_status` without
  reading the authoritative source.
- Never re-run Step 3 on re-invocation once `children` is already populated — only Step 4
  (dispatch) resumes, for children not yet at `WORK_COMPLETE`.
- In `"synced"` dispatch mode, do not advance to Step 5 until all parallel subagents have
  returned.
- In `"sequenced"` dispatch mode, do not dispatch the next child until the current child has
  confirmed `WORK_COMPLETE` (verified in Step 5).

## Outputs

- Updated `.sdp-solution-workflow/state.json` — solution task status set to
  `SOL_WORK_COMPLETE` (or `SOL_DIAGNOSIS_BLOCKED` flag set if blocked); `children` array
  populated; `cached_status` values updated; `last_session` counter incremented.
- Session file written to `.sdp-solution-workflow/sessions/session-NNN.md`.
- Child task entries written into each involved project's phase file and phase state JSON
  (Step 3 only — skipped on re-invocation if children already exist).
- `SDP-Solution.json` `updated` field refreshed.
