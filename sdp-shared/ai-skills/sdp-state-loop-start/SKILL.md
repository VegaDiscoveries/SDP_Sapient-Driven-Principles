## Purpose

Explicit per-session opt-in to auto-advance the SDP workflow. User invokes this skill when
they intend the current session to drive the workflow forward. Starts the recurring state-loop
first, then runs COORDINATOR once to write an accurate dispatch prompt and align
`active_work_item` — so the loop's first fire is a clean EXECUTE rather than a wasted prompt
regeneration.

This skill is user-initiated only. It is never called by `sdp-project-state-loop` — calling it from within an automated path would cause loop proliferation.

## Inputs

- `SDP-Solution.json` — `last_active_projects` (validated before loop start)
- `SDP-Config.json` — `loopInterval.interval_minutes`
- `.sdp-workflow/state.json` — `active_work_item` and `workflow_status` (read back after COORDINATOR to confirm the priming outcome)
- `sdp-docs/00_prompt.txt` — sentinel line read back after COORDINATOR to confirm the prompt was written for the active work item

## Procedure

### Step 0: Await Session-Start Completion

1. Check whether the session-start hook triggered `sdp-initialize-sdp` in this session (the
   SessionStart hook's actual configured target — not `sdp-project-read-docs`, a project-scoped
   doc loader invoked separately, later, by other skills). Signs it was triggered but not yet
   confirmed: the `sdp-initialize-sdp` skill invocation appears in conversation context but its
   closing banner and one-sentence closing statement (its own Output Discipline/Outputs
   contract: opening banner, internal `sdp-solution-read-docs` invocation, closing banner, then
   exactly one short closing statement) have not yet been output.
2. If `sdp-initialize-sdp` is still in progress: invoke
   `/sdp-create-banner icon=pending row=0 row: Status | sdp-state-loop-start: awaiting session-start (sdp-initialize-sdp) completion before proceeding.`
   Halt. Resume from Step 0 once `sdp-initialize-sdp` outputs its closing banner and closing
   statement.
3. If `sdp-initialize-sdp` has completed (or was not triggered in this session): proceed to
   Step 1.

### Step 1: Validate Active Project

**Level 0 — Invocation argument (user or agent):** If a project path was passed as an
argument on invocation, skip sub-steps 1–2. Read `SDP-Solution.json` to validate the
argument against the `projects` array. If valid: announce "sdp-state-loop-start: project
resolved from invocation argument — [value]. Proceeding." and use it as `[resolved_project]`
for all subsequent steps. If invalid: halt by invoking
`/sdp-create-banner icon=error row=0 row: Status | Invocation argument '[value]' does not
match any project registered in SDP-Solution.json. Available: [list]. Correct the argument
and retry.`

Read `SDP-Solution.json` at the solution root and verify that `last_active_projects` is present
and non-empty before starting the loop.

1. Read `SDP-Solution.json` from the solution root.
   - If the file cannot be read: halt by invoking
     `/sdp-create-banner icon=error row=0 row: Status | Cannot start loop — SDP-Solution.json
     not found at solution root. Run /sdp-workspace-setup to create it before proceeding.`
     Also record the halt (non-blocking
     — ignore any failure and continue): run `./sdp-shared/scripts/sdp-workflow-log.ps1 -trigger
     "loop_start.precondition_fail" -role "STATE_LOOP_START" -outcome "HALTED" -reason
     "SDP-Solution.json not found at solution root"` via the PowerShell tool.
2. Check that `last_active_projects` is present and contains at least one entry.
   - If the field is absent or the array is empty: read the `projects` array from
     `SDP-Solution.json`.
     - If `projects` contains exactly 1 entry: use it as the active project. Announce by
       invoking `/sdp-create-banner icon=warning row=0 row: Status | sdp-state-loop-start:
       last_active_projects is empty — auto-resolved to single registered project: [project].
       Proceeding.` Use this value as `[resolved_project]` for all subsequent steps in this
       skill.
     - If `projects` contains 2 or more entries: list the available projects and halt by
       invoking `/sdp-create-banner icon=error row=0 row: Status | Cannot start loop —
       last_active_projects is empty and multiple projects are registered: [list]. Set
       last_active_projects in SDP-Solution.json to the target project and retry.` Also
       record the halt (non-blocking — ignore any failure and
       continue): run `./sdp-shared/scripts/sdp-workflow-log.ps1 -trigger
       "loop_start.precondition_fail" -role "STATE_LOOP_START" -outcome "HALTED" -reason
       "last_active_projects empty with multiple projects registered: [list]"` via the
       PowerShell tool.
     - If `projects` is empty or absent: halt by invoking
       `/sdp-create-banner icon=error row=0 row: Status | Cannot start loop — no projects
       registered in SDP-Solution.json. Register at least one project before proceeding.`
       Also record the halt (non-blocking — ignore any
       failure and continue): run `./sdp-shared/scripts/sdp-workflow-log.ps1 -trigger
       "loop_start.precondition_fail" -role "STATE_LOOP_START" -outcome "HALTED" -reason
       "No projects registered in SDP-Solution.json"` via the PowerShell tool.
3. If `last_active_projects` is non-empty: announce the active project(s) and proceed to Step 2.
   "sdp-state-loop-start: active project(s) confirmed — [last_active_projects values]. Proceeding."

### Step 2: Start the State Loop

The loop is started first so its interval clock begins running now and overlaps the COORDINATOR
priming in Step 3 — minimizing the gap before the first productive fire. The `loop` skill only
schedules the recurring fire; it does not fire immediately on creation, so no dispatch happens
until Step 3 has primed the prompt.

1. **Guard against duplicate loops.** List active scheduled jobs via the `CronList` tool. If any
   active job's command invokes `/sdp-project-state-loop` or `/sdp-solution-state-loop`, a loop is
   already running. Report by invoking
   `/sdp-create-banner icon=warning row=0 row: Status | sdp-state-loop-start: a loop is already
   active ([job id(s)]) — not starting a second. Run /sdp-cancel-auto to stop
   it first if you intend to restart.` Halt the
   skill — do not create another loop and do not proceed to Step 3. The existing loop already
   drives dispatch; a second concurrent loop doubles the fire rate and is never wanted.
2. Read `SDP-Config.json`.
   - If the file cannot be read or `loopInterval.interval_minutes` is absent: use interval = 5.
     Announce by invoking `/sdp-create-banner icon=warning row=0 row: Status |
     sdp-state-loop-start: SDP-Config.json not found or missing loopInterval.interval_minutes —
     defaulting to 5-minute loop interval.`
   - If the file can be read: use the value of `loopInterval.interval_minutes` as the interval.
2a. **Phase-7-gate precondition.** Read `.sdp-solution-workflow/state.json`. If `current_phase`
    is not `null`: halt — do not start any loop, and do not proceed to Step 3's COORDINATOR
    priming either. Invoke `/sdp-create-banner icon=error row=0 row: Status | sdp-state-loop-start: phases 1-7 are still active for this solution (current_phase: [value]) — use direct sdp-solution-phase-coordinator dispatch, not the recurring loop, until Phase 7's gate passes.`
    Stop.
2b. **One-time cron-target pick.** Read the current, live count of `SDP-Solution.json`'s
    `projects` array, once. Exactly 1 project → target = `/sdp-project-state-loop`. 2+ projects →
    target = `/sdp-solution-state-loop`.
3. Invoke the `loop` skill with argument `[interval]m [target]` (the target resolved in 2b).
4. Do not announce separately here — Step 3.3 reports "sdp-state-loop-start: loop started —
   [target] will monitor and dispatch every [interval] minutes." together with the
   priming outcome in one closing banner, since both fire once at the end of the same
   invocation.

### Step 3: Prime the Dispatch Prompt

Run a COORDINATOR pass to write an accurate `sdp-docs/00_prompt.txt` and align state before the
loop's first fire. COORDINATOR — unlike `sdp-project-run-prompt` — both writes the sentinel prompt and
sets `active_work_item` in `state.json` to match it, so the loop's first fire sees a sentinel
that matches current state and takes the EXECUTE path instead of spending a fire regenerating a
stale prompt. This priming does not perform the work itself; the loop's first fire does.

1. Announce: "sdp-state-loop-start: priming dispatch prompt — spawning a COORDINATOR subagent so
   `sdp-docs/00_prompt.txt` and `active_work_item` are accurate before the loop's first fire."
2. Spawn a subagent via the Agent tool with the following prompt:
   "You are an SDP COORDINATOR priming subagent. Invoke `sdp-project-coordinator` to determine the next
   dispatch, write `.sdp-workflow/sessions/session-NNN.md`, update `.sdp-workflow/state.json`
   (`active_work_item`, `last_session`), and write `sdp-docs/00_prompt.txt` with a sentinel that
   matches the dispatched task. Do NOT spawn any WORKER or REVIEWER subagent regardless of
   `orchestration_mode` — the recurring loop performs execution. Stop after the dispatch prompt
   and state are written."
   COORDINATOR self-guards against a halted workflow, a missing or blocked active work item, and
   unmet phase dependencies — no precondition check is required here before priming.
3. After the subagent returns, confirm the outcome from state files (not the subagent's text):
   - Read the first line of `sdp-docs/00_prompt.txt`. If it matches the sentinel
     `[sdp-prompt work_item="..." expected_status="..."]`, report by invoking
     `/sdp-create-banner icon=success,success row=0,1
     row: Loop | sdp-state-loop-start: loop started — [target] will monitor and dispatch
     every [interval] minutes.
     row: Dispatch Primed | sdp-state-loop-start: COORDINATOR primed the prompt for [work_item]
     (expected_status [expected_status]) — the loop's first fire will execute it.`
   - If no valid sentinel was written, first report the loop-started fact by invoking
     `/sdp-create-banner icon=success row=0 row: Loop | sdp-state-loop-start: loop started —
     [target] will monitor and dispatch every [interval] minutes.` Then read
     `.sdp-workflow/state.json`. If `workflow_status` is
     `"halted"` or `active_work_item` is null, report the blocking condition from state.json and
     note that the loop will STOP on its first fire until the condition is resolved.

## Constraints

- User-initiated only — never call this skill from within `sdp-project-state-loop`, `sdp-project-coordinator`,
  or any other SDP skill. Doing so causes loop proliferation.
- Never write project files directly from this skill itself — the dispatch prompt, session
  file, and `state.json` updates must come from the spawned COORDINATOR subagent in Step 3. The
  one exception is the non-blocking `sdp-workflow-log.ps1` call on a Step 1 precondition halt —
  a side-effect log write, not a project-state write, same category as an `sdp-tone.ps1` call.
- Do not begin Step 1 until any session-start `sdp-initialize-sdp` invocation has reached its
  closing banner and closing statement. If it has not, halt at Step 0 and wait.
- Never start a loop or spawn priming before Step 1 validates `SDP-Solution.json`
  `last_active_projects` — halt immediately if the file is absent or the field is empty; no
  loop is created and no COORDINATOR subagent is spawned.
- Never add additional precondition checks beyond what Step 3's `sdp-project-coordinator` priming
  already performs (halted workflow, missing or blocked active work item, unmet dependencies)
  — this skill's own checking stops at the Step 1 `last_active_projects` guard. If COORDINATOR
  cannot produce a valid dispatch prompt, the loop's first fire detects the condition and STOPs.
- The priming COORDINATOR must not spawn a WORKER or REVIEWER — execution is the loop's job.
  The Step 3 subagent prompt forbids spawning explicitly so this holds regardless of
  `orchestration_mode`.
- Never start a second loop when an active `sdp-project-state-loop` or `sdp-solution-state-loop` job
  already exists — Step 2.1 checks via `CronList` and halts (does not create another loop, does
  not proceed to Step 3) if one is found.
- Never require `/sdp-state-loop-start` to be re-run between tasks — the loop started in
  Step 2 uses `sdp-project-state-loop` (single project) or `sdp-solution-state-loop` (2+ projects,
  post-Phase-7 only — Step 2.2b picks the target once, never re-evaluated) to dispatch
  deterministically based on workflow state. `sdp-project-state-loop` handles all single-project state
  transitions automatically (WORK_COMPLETE → REVIEWER, VERIFIED → COORDINATOR advance,
  REJECTED → re-queue). `sdp-solution-state-loop` performs `sdp-solution-phase-coordinator`'s
  dispatch-gating pass each fire instead (no per-task state machine of its own).

## Outputs

- `SDP-Solution.json` `last_active_projects` confirmed non-empty (Step 1 guard).
- Loop started: `loop` skill running the resolved target — `sdp-project-state-loop` (single project) or
  `sdp-solution-state-loop` (2+ projects), picked once in Step 2.2b — at the configured interval
  (Step 2).
- COORDINATOR subagent spawned to prime an accurate `sdp-docs/00_prompt.txt` and align
  `active_work_item` so the loop's first fire is a clean EXECUTE; prompt sentinel read back to
  confirm (Step 3).
- This skill writes no project files directly — the dispatch prompt, session file, and
  `state.json` updates are written by the spawned COORDINATOR subagent. On a Step 1
  precondition halt, one `workflow-log-<local-yyyyMMdd>.jsonl` entry is written via
  `sdp-workflow-log.ps1` (non-blocking side effect).
