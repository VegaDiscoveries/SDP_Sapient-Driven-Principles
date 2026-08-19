## Purpose

Read `sdp-solution-docs/00_solution_prompt.txt` from the solution root, parse the
`[sdp-solution-prompt ...]` sentinel on the first line, identify the correct solution-level
skill from the `role=` field, and invoke it.

This skill contains no workflow logic of its own — it reads the prompt and dispatches to the
correct solution-level role skill. It is always invoked directly by the user (never by a
formally dispatched subagent), so no project or session resolution is required — the prompt
file is at a fixed, known location.

## Inputs

- `sdp-solution-docs/00_solution_prompt.txt` — written by `sdp-solution-coordinator` after
  every dispatch. Contains an `[sdp-solution-prompt ...]` sentinel on the first line and a
  five-section prompt body. The `role=` field in the sentinel determines which solution-level
  skill to invoke.

## Procedure

### Step 1: Read the Solution Prompt File

1. Read `sdp-solution-docs/00_solution_prompt.txt` from the solution root.
2. If the file cannot be read or does not exist: halt — invoke
   `/sdp-create-banner icon=error row=0 row: Status | sdp-solution-docs/00_solution_prompt.txt not found at solution root. Run /sdp-solution-coordinator to generate it before proceeding.`
3. If the file is empty: halt — invoke
   `/sdp-create-banner icon=warning row=0 row: Status | sdp-solution-docs/00_solution_prompt.txt is empty — no solution prompt to run. Run /sdp-solution-coordinator to generate one.`

### Step 2: Parse the Sentinel

1. Read the first line of the file.
2. Check whether the first line matches one of the two sentinel shapes
   `sdp-solution-create-prompt` writes, depending on dispatch mode:
   - Shared-task mode: `[sdp-solution-prompt solution_task="..." expected_status="..." role="..." projects="..."]`
   - Phases-1-7 mode: `[sdp-solution-prompt current_phase="..." expected_status="..." role="..."]`
     (no `projects=` fragment — its absence is expected in this shape, not a malformation)
3. If the first line does not begin with `[sdp-solution-prompt `: halt — invoke
   `/sdp-create-banner icon=error row=0 row: Status | sdp-solution-docs/00_solution_prompt.txt does not begin with an [sdp-solution-prompt ...] sentinel — file may be corrupt or written by an unexpected source. Inspect the file and run /sdp-solution-coordinator to regenerate if needed.`
4. If the first line begins with `[sdp-solution-prompt ` but is malformed (missing `role=`
   field or the closing `]`): halt — invoke
   `/sdp-create-banner icon=error row=0 row: Status | sdp-solution-docs/00_solution_prompt.txt sentinel is malformed — role= field is missing or the sentinel is not properly closed. Inspect the file and run /sdp-solution-coordinator to regenerate.`
5. Extract the value of the `role=` attribute from the sentinel (the value between the
   double quotes following `role=`). Proceed to Step 3.

### Step 3: Map Role to Skill

Map the extracted `role=` value to a skill name using this table:

| `role=` value          | Skill to invoke                | Scope |
|------------------------|---------------------------------|-------|
| `SOLUTION_COORDINATOR` | `sdp-solution-coordinator`      | Shared-task orchestration |
| `SOLUTION_WORKER`      | `sdp-solution-worker`           | Shared-task orchestration |
| `SOLUTION_REVIEWER`    | `sdp-solution-reviewer`         | Shared-task orchestration |
| `WORKER`               | `sdp-solution-phase-worker`     | Phases 1-7 |
| `REVIEWER`             | `sdp-solution-phase-reviewer`   | Phases 1-7 |
| `GATE_REVIEWER`        | `sdp-solution-phase-gate-review`      | Phases 1-7 |

The phases-1-7 roles (`WORKER`/`REVIEWER`/`GATE_REVIEWER`) route to the dedicated
`sdp-solution-phase-*`/`sdp-solution-phase-gate-review` skills — **never** to `sdp-project-worker`,
`sdp-project-reviewer`, or `sdp-project-gate-review`, which are project-scoped only and have no way to accept a
solution-level dispatch.

If the `role=` value is not one of the six values above: halt — invoke
`/sdp-create-banner icon=error row=0 row: Status | Unrecognised role= value in sdp-solution-docs/00_solution_prompt.txt: [value]. Valid values are SOLUTION_COORDINATOR, SOLUTION_WORKER, SOLUTION_REVIEWER, WORKER, REVIEWER, GATE_REVIEWER. Inspect the file and run /sdp-solution-coordinator to regenerate.`

### Step 4: Invoke the Skill

1. Invoke
   `/sdp-create-banner icon=info row=0 row: Status | Identified next solution step: role=[role-value] — invoking /[skill-name] now.`
2. Use the Skill tool to invoke the identified skill. Pass the bare skill name without the
   leading `/` (e.g., `sdp-solution-coordinator`, not `/sdp-solution-coordinator`).
3. The invoked skill takes over from this point. `sdp-solution-run-prompt` has no further
   steps after the Skill tool call.

## Constraints

- Read `sdp-solution-docs/00_solution_prompt.txt` only — do not read any other files in
  this skill.
- Do not read `SDP-Solution.json`. The solution prompt file is at a fixed location; no
  registry lookup is needed.
- Do not invoke more than one skill per run.
- Do not modify any file.
- Do not summarize the prompt content, explain the workflow state, or take any action beyond
  reading the prompt, identifying, and invoking the next solution-level skill.

## Outputs

- The solution-level role skill identified from the `role=` field is invoked via the Skill
  tool.
- No files written or modified.
