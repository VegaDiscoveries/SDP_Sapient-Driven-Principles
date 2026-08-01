## Purpose

Write `sdp-solution-docs/00_solution_prompt.txt` at the solution root — a complete, self-contained
prompt that a new solution-level agent session can use immediately to continue orchestration
correctly.

This skill is invoked by one of two different coordinators, depending on dispatch mode —
`sdp-solution-coordinator` for a shared cross-project task (that skill's own Step 1/2), or
`sdp-solution-phase-coordinator` for a phases-1–7 dispatch (that skill's own Step 2a; a dedicated
copy of `sdp-solution-coordinator` created specifically because phases-1–7 dispatch was never
reachable through the original). Whichever one calls, it passes
`role` and `projects` as part of its invocation — these values are present in the calling
coordinator's conversation context at the time this skill executes. `projects` is always
empty/omitted for a phases-1–7 dispatch — that mode's `Project:` field is deliberately absent.

This skill does not modify workflow state, write session files, or dispatch agents. Its sole
output is `sdp-solution-docs/00_solution_prompt.txt`. This file is a working file and is
overwritten on each invocation — it is not append-only.

**Hybrid model:** a script,
`sdp-shared/scripts/sdp-solution-create-prompt.ps1`, owns the two fully-deterministic reads —
`SDP-Solution.json` and `.sdp-solution-workflow/state.json` — and reports `mode`
(`"shared_task"` or `"phases_1_7"`) plus `solution_name`, and either
(`active_solution_task`, `task_status`) or (`current_phase`, `phase_gate_status`,
`gate_eval_cycles`) depending on `mode`, plus `last_session` and `workflow_status` either way, as
a single JSON result. `role` and `projects` are never file-accessible — they exist only in the
invoking coordinator's conversation context (`sdp-solution-coordinator` or
`sdp-solution-phase-coordinator`, per mode) — so the LLM confirms them directly and performs all
template substitution and the file write. Risk tier is Recoverable: on a script error the LLM
falls back to reading both files manually with the Read tool.

## Inputs

- `SDP-Solution.json` (solution root) — read by the script; provides `solution_name` and
  `active_solution_task`
- `.sdp-solution-workflow/state.json` (solution root) — read by the script; provides, depending
  on which is set, the current solution task entry's `status` (shared-task mode) or
  `current_phase`/`phase_gate` (phases-1–7 mode), plus the top-level `last_session` and
  `workflow_status` fields either way
- `role` — the role being dispatched; passed by the invoking coordinator. Shared-task mode:
  `SOLUTION_COORDINATOR`, `SOLUTION_WORKER`, `SOLUTION_REVIEWER`, passed by
  `sdp-solution-coordinator`. Phases-1–7 mode: `WORKER`, `REVIEWER`, `GATE_REVIEWER` — the same
  role names the bootstrap doc's Implementation Loop uses, dispatched here at solution scope
  instead of project scope, passed by `sdp-solution-phase-coordinator`.
- `projects` — comma-separated list of project paths (relative to solution root) involved in
  this dispatch; passed by `sdp-solution-coordinator` in shared-task mode. Empty for a
  phases-1–7 dispatch.

## Procedure

### Step 1: Run Script

Run `./sdp-shared/scripts/sdp-solution-create-prompt.ps1` via the PowerShell tool. No
arguments — the script self-resolves the solution root from its own location.

If the PowerShell tool call produces no parseable single-line JSON on stdout (regardless of
exit code): fall back to reading `SDP-Solution.json` and `.sdp-solution-workflow/state.json`
directly with the Read tool and extracting the same fields manually (this is the Recoverable
fallback — do not halt).

Parse the single-line JSON result. Branch on `status`:

- **`"error"`** — Halt: invoke `/sdp-create-banner icon=error row=0` with
  `row: Error | [error]` (substitute the script's `error` field as the row content). (Covers a
  missing `SDP-Solution.json`, a missing `.sdp-solution-workflow/state.json`, no task entry
  matching a set `active_solution_task`, or both `active_solution_task` and `current_phase`
  absent — nothing to dispatch.)
- **`"success"`** — Record `mode` (`"shared_task"` or `"phases_1_7"`), `solution_name`,
  `last_session` (already formatted as `"session-NNN"`, or `null` if no session has been written
  yet), and `workflow_status`. If `mode` is `"shared_task"`: also record `active_solution_task`
  and `task_status`. If `mode` is `"phases_1_7"`: also record `current_phase`,
  `phase_gate_status`, and `gate_eval_cycles`. Proceed to Step 2.

### Step 2: Confirm Role and Projects from Coordinator Context

The invoking coordinator provides `role` and `projects` as part of the dispatch context — they
are present in the current conversation at the time this skill executes. Confirm `role` is
available and matches the Step 1 `mode`:

- `mode: "shared_task"` — `role` must be one of `SOLUTION_COORDINATOR`, `SOLUTION_WORKER`,
  `SOLUTION_REVIEWER`, provided by `sdp-solution-coordinator`; `projects` must be a non-empty
  comma-separated string of project paths (e.g.,
  `"sdp-project_AppName.API,sdp-project_AppName.Website"`).
- `mode: "phases_1_7"` — `role` must be one of `WORKER`, `REVIEWER`, `GATE_REVIEWER`, provided
  by `sdp-solution-phase-coordinator` (Step 2a item 4 of that skill deliberately omits
  `projects`) — do not treat an empty `projects` as an error in this mode.

If `role` is absent or empty, or (`mode: "shared_task"` only) `projects` is absent or empty:
halt: invoke `/sdp-create-banner icon=error row=0` with
`row: Error | role[, and projects for a shared-task dispatch,] must be provided by the invoking coordinator. This skill cannot determine them independently — re-invoke from a coordinator session that has determined the dispatch target.`

### Step 3: Build the Sentinel Line

**`mode: "shared_task"`** — compose the sentinel exactly as before:

```
[sdp-solution-prompt solution_task="[active_solution_task]" expected_status="[status]" role="[role]" projects="[projects]"]
```

Example:
```
[sdp-solution-prompt solution_task="SOL-001" expected_status="SOL_PENDING" role="SOLUTION_WORKER" projects="sdp-project_AppName.API,sdp-project_AppName.Website"]
```

**`mode: "phases_1_7"`** — compose the sentinel using `current_phase` in place of
`solution_task`, and `phase_gate_status` in place of a task status; `projects` is omitted
entirely (no `projects=""` fragment — the field simply does not appear):

```
[sdp-solution-prompt current_phase="[current_phase]" expected_status="[phase_gate_status]" role="[role]"]
```

Example:
```
[sdp-solution-prompt current_phase="Architecture" expected_status="pending" role="WORKER"]
```

`expected_status` is the status **at the time of writing** — the status it holds now, not the
status it will be in after the dispatched session runs, in either mode.

### Step 4: Write sdp-solution-docs/00_solution_prompt.txt

Write the file at `sdp-solution-docs/00_solution_prompt.txt` (relative to the solution root).
Overwrite any existing content.

**File structure — `mode: "shared_task"`:**

```
[sentinel line from Step 3]

## Section 1 — Role Declaration

You are acting as [role] for the **[solution_name]** solution using the SDP workflow.

## Section 2 — Read First

Before doing anything else, run `/sdp-solution-read-docs` to load the SDP bootstrap document and
all project-specific documentation. Do not proceed to any implementation step until all documents
are loaded.

## Section 3 — Current State Summary

| Field | Value |
|-------|-------|
| Solution | [solution_name] |
| Current solution task | [active_solution_task] |
| Workflow status | [workflow_status from state.json top-level field] |
| Active solution task status | [status] |
| Last session | [last_session — or "none" if null/absent] |
| Next action | [one-line description of what this session must do] |

## Section 4 — Task Instruction

[Task-specific instruction based on role:]

**For SOLUTION_COORDINATOR:**
Review all involved project states, enforce the cycle sync invariant, determine the next
dispatch target (WORKER or REVIEWER per project), write session files, and update
`SDP-Solution.json`. Invoke `/sdp-solution-coordinator` to begin.

**For SOLUTION_WORKER:**
Decompose the active solution task into child project tasks (if not already done), dispatch
project workers across all involved projects, and set the solution task to `SOL_WORK_COMPLETE`
when all children reach `WORK_COMPLETE`. Invoke `/sdp-solution-worker` to begin.

**For SOLUTION_REVIEWER:**
Dispatch project reviewers across all involved projects, perform the cross-project integration
check after all children reach `VERIFIED`, and set the solution task to `SOL_VERIFIED` or
`SOL_REJECTED`. Invoke `/sdp-solution-reviewer` to begin.

## Section 5 — Key Files

- `.sdp-solution-workflow/state.json` — solution task status, children, and session counter
- `.sdp-solution-workflow/sessions/[last_session].md` — most recent solution session file
  (or "no prior session" if last_session is null/absent)
- `SDP-Solution.json` — solution registry; `active_solution_task` and `last_active_projects`
[For each project path in the projects list:]
- `[project_path]/.sdp-workflow/state.json` — authoritative status for [project_path]
```

**File structure — `mode: "phases_1_7"`:**

```
[sentinel line from Step 3]

## Section 1 — Role Declaration

You are acting as [role] for the **[solution_name]** solution using the SDP workflow.

## Section 2 — Read First

Before doing anything else, run `/sdp-solution-read-docs` to load the SDP bootstrap document and
all project-specific documentation. Do not proceed to any implementation step until all documents
are loaded.

## Section 3 — Current State Summary

| Field | Value |
|-------|-------|
| Solution | [solution_name] |
| Current phase | [current_phase] |
| Workflow status | [workflow_status from state.json top-level field] |
| Phase gate status | [phase_gate_status] |
| Last session | [last_session — or "none" if null/absent] |
| Next action | [one-line description of what this session must do] |

## Section 4 — Task Instruction

[Task-specific instruction based on role:]

**For WORKER:**
Implement the assigned task within the `[current_phase]` phase document at
`sdp-solution-docs/[NN_phase_name].md` and record completion. Invoke
`/sdp-solution-phase-worker` to begin — never `/sdp-project-worker`, which is project-scoped only.

**For REVIEWER:**
Independently verify the assigned task within the `[current_phase]` phase document against its
acceptance criteria, record the evaluation, and update state. Invoke
`/sdp-solution-phase-reviewer` to begin — never `/sdp-project-reviewer`, which is project-scoped only.

**For GATE_REVIEWER:**
Assess the completed `[current_phase]` phase document against gate criteria and produce a
verdict. Invoke `/sdp-solution-phase-gate-review` to begin — never `/sdp-project-gate-review`, which is
project-scoped only and has no way to be pointed at solution-level work.

## Section 5 — Key Files

- `.sdp-solution-workflow/state.json` — `current_phase`, `phase_gate`, and session counter
- `.sdp-solution-workflow/sessions/[last_session].md` — most recent solution session file
  (or "no prior session" if last_session is null/absent)
- `sdp-solution-docs/[NN_phase_name].md` — the phase document under review
```

**Substitution rules (both modes):**

- `[role]` — the role value from Step 2 (e.g., `SOLUTION_WORKER`, or `WORKER`)
- `[solution_name]`, `[workflow_status]`, `[last_session]` — from the Step 1 script result;
  write `"none"` for `[last_session]` if `null`
- Shared-task mode: `[active_solution_task]` = `active_solution_task`; `[status]` =
  `task_status`; both from the Step 1 script result
- Phases-1-7 mode: `[current_phase]` = `current_phase`; `[phase_gate_status]` =
  `phase_gate_status`; both from the Step 1 script result; `[NN_phase_name].md` is the file
  matching `current_phase`'s position in the seven-phase sequence (e.g. `current_phase:
  "Architecture"` → `04_architecture.md`) — do not guess a filename that doesn't match this
  convention.
- `[one-line description]` — shared-task mode: infer from the role exactly as before
  (`SOLUTION_COORDINATOR` → "Coordinate dispatch across involved projects", etc.). Phases-1-7
  mode: `WORKER` → "Implement the assigned task and record completion"; `REVIEWER` →
  "Independently verify the assigned task and record the evaluation"; `GATE_REVIEWER` →
  "Assess the completed phase document against gate criteria"
- Use the role-specific Task Instruction paragraph for Section 4 — write only the paragraph
  that matches the current `role`, from whichever mode's set applies; do not include paragraphs
  for other roles or the other mode
- Shared-task mode only: in Section 5, list one state file per involved project (one line per
  project path in the `projects` list)

### Step 5: Confirm

Report to the user in one sentence that `sdp-solution-docs/00_solution_prompt.txt` has been
written. Shared-task mode: state the solution task ID, role, and involved projects. Phases-1-7
mode: state `current_phase` and role.

## Constraints

- Never act on a direct user invocation of this skill, and never proceed without a
  coordinator-provided `role` value matching the Step 1 `mode` — halt immediately (Step 2 check)
  if it is missing or mismatched. `projects` is required only in `shared_task` mode; its absence
  in `phases_1_7` mode is expected, not an error.
- Do not infer `role` or `projects` from `SDP-Solution.json` or state files — these values are
  never file-accessible and are always passed explicitly by the invoking coordinator.
- Do not write session files, update `state.json`, or update `SDP-Solution.json`.
- Do not dispatch agents or invoke other skills within this skill.
- `expected_status` in the sentinel must be the task's status at the time of writing — never a
  future or target status.
- Never prefix a file path with `[resolved_project]` — all paths are relative to the solution
  root (the Claude Code working directory); this skill operates at solution scope only.
- Never let the script write `SDP-Solution.json` or `.sdp-solution-workflow/state.json` — it is
  read-only; all file writing in this skill (`sdp-solution-docs/00_solution_prompt.txt`) is
  performed by the LLM in Step 4.
- Never write Section 4 paragraphs for roles other than the current `role` — write only the
  paragraph that matches it.

## Outputs

- `sdp-solution-docs/00_solution_prompt.txt` — complete, self-contained solution-level prompt
  for the next agent session. Always overwritten.
- One-sentence confirmation to the user: solution task ID, role dispatched, and projects
  involved.
