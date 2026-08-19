## Purpose

Explicit per-session opt-in to auto-advance the SDP workflow. User invokes this skill when
they intend the current session to drive the workflow forward. Verifies the workflow is active
and unblocked, confirms a dispatch prompt is ready, starts a recurring state-loop for automatic
subsequent dispatch, and invokes `sdp-project-run-prompt` for the immediate next step.

This immediate-dispatch behavior (Steps 1-4) is single-project, dot-collapse-path logic only —
Step 0b checks this first and, for any solution-scoped project (including a single one living in
its own `sdp-project_[Name]/` subfolder) or any multi-project solution, either halts with
direction to `/sdp-solution-phase-coordinator` (phases 1-7 still active) or delegates the entire
loop-startup to `/sdp-state-loop-start` (phases 1-7 complete) instead of running Steps 1-5 itself.

This skill is user-initiated only. It is never called by `sdp-project-state-loop` or any other SDP
skill — calling it from within an automated path would cause loop proliferation.

## Inputs

- `SDP-Solution.json` — `last_active_projects` and `projects` (Step 0b — determines whether
  Steps 1-4's dot-collapse assumption applies)
- `.sdp-solution-workflow/state.json` — `current_phase` (Step 0b — phases-1-7 completion check)
- `.sdp-workflow/state.json` — workflow status and active task (Steps 1-4, dot-collapse case only)
- Phase state file — active task flags (Steps 1-4, dot-collapse case only)
- `sdp-docs/00_prompt.txt` — current dispatch prompt written by COORDINATOR (Steps 1-4,
  dot-collapse case only)

## Procedure

### Step 0: Await Session-Start Completion

1. Check whether the session-start hook triggered `sdp-initialize-sdp` in this session (the
   SessionStart hook's actual configured target — not `sdp-project-read-docs`, a project-scoped
   doc loader invoked separately, later, by other skills). Signs it was triggered but not yet
   confirmed: the `sdp-initialize-sdp` skill invocation appears in conversation context but its
   closing banner and one-sentence closing statement (its own Output Discipline/Outputs
   contract: opening banner, internal `sdp-solution-read-docs` invocation, closing banner, then
   exactly one short closing statement) have not yet been output.
2. If `sdp-initialize-sdp` is still in progress: invoke `/sdp-create-banner` with icon=pending and
   the row below, then halt:
   `icon=pending row=0 row: Status | sdp-auto: awaiting session-start (sdp-initialize-sdp) completion before proceeding.`
   Resume from Step 0 once `sdp-initialize-sdp` outputs its closing banner and closing statement.
3. If `sdp-initialize-sdp` has completed (or was not triggered in this session): proceed to
   Step 0b.

### Step 0b: Solution Scope Check

Steps 1-4 below assume `.sdp-workflow/state.json` and `sdp-docs/00_prompt.txt` live at the
solution root — true only for the legacy single-project convention where the project's own path
collapses to `.` (dot). A solution-scoped workspace's projects — including a solitary one —
normally live under a real `sdp-project_[Name]/` subfolder instead, where those paths do not
exist at the root at all. This step determines which case applies before Steps 1-4 run.

1. Read `SDP-Solution.json` at the solution root.
   - If absent or unreadable: pre-solution-scoped or not-yet-configured workspace — proceed to
     Step 1 unchanged.
2. Resolve the candidate project path: use `last_active_projects[0]` if present and non-empty;
   otherwise, if `projects` contains exactly one entry, use that entry's `path`; otherwise (empty
   `last_active_projects` and 2+ `projects` entries, with no way to resolve a single candidate)
   treat this as the multi-project case in sub-step 3 below directly.
3. Branch on the resolved path (or the multi-project case from sub-step 2):
   - **Path is exactly `"."`:** the true single-project dot-collapse convention —
     `.sdp-workflow/state.json` and `sdp-docs/00_prompt.txt` genuinely sit at the solution root.
     Proceed to Step 1 unchanged.
   - **Path is a real subfolder (e.g. `sdp-project_[Name]`), or no single candidate could be
     resolved (2+ `projects` entries with `last_active_projects` empty):** Steps 1-4 do not
     apply — there is no project's `.sdp-workflow/state.json` at the solution root for them to
     read. Skip Steps 1-4 entirely. Proceed to sub-step 4.
4. **Phase-7 completion check.** Read `.sdp-solution-workflow/state.json`'s `current_phase`
   field.
   - **Not `null`** (phases 1-7 still active for this solution): do not start any loop and do
     not attempt any dispatch — per the bootstrap doc's Loop Entry Point invariant, phases 1-7
     are always human-gated, direct session-by-session dispatch; no cron job may exist while
     this path is active. Invoke:
     `/sdp-create-banner icon=warning row=0 row: Status | sdp-auto: this solution's project(s) live in their own subfolder(s) and phases 1-7 are still active (current_phase: [value]) — phases 1-7 must be driven by direct, human-gated /sdp-solution-phase-coordinator sessions, not by /sdp-auto or any recurring loop. Run /sdp-solution-phase-coordinator to continue.`
     Halt. Do not proceed to Step 1, Step 5, or invoke `/sdp-state-loop-start`.
   - **`null`** (phases 1-7 complete): this is the regime `/sdp-state-loop-start` is built for —
     it performs its own project-count-aware resolution and loop-target selection, which Steps
     1-4 below do not. Invoke `/sdp-state-loop-start` via the Skill tool. Invoke
     `/sdp-create-banner icon=success row=0 row: Status | Project(s) live in their own subfolder(s) and phases 1-7 are already complete — delegating to /sdp-state-loop-start for correct loop startup.`
     Terminate once it returns — do not proceed to Step 1 or Step 5 of this skill.

### Step 1: Verify Workflow Is Active

1. Read `.sdp-workflow/state.json`.
2. If the file cannot be read: invoke `/sdp-create-banner` with icon=warning and the row below,
   then halt — do not proceed to Step 2:
   `icon=warning row=0 row: Status | .sdp-workflow/state.json not found — no workflow to advance. Set up the workspace first.`
3. If `workflow_status` is `"halted"`: invoke `/sdp-create-banner` with icon=error and the row
   below, then halt:
   `icon=error row=0 row: Status | Workflow halted — [halt_reason from state.json]. Resolve this condition before running /sdp-auto.`
4. If `workflow_status` is not `"active"`: invoke `/sdp-create-banner` with icon=warning and
   the row below, then halt:
   `icon=warning row=0 row: Status | Workflow status is '[workflow_status]' — nothing to advance.`
5. If `active_work_item` is null: invoke `/sdp-create-banner` with icon=warning and the row
   below, then halt:
   `icon=warning row=0 row: Status | No active work item — run /sdp-project-coordinator to assign the next task, then run /sdp-auto.`

### Step 2: Check for Blocking Flags

1. Identify the phase state file using this three-tier resolution (matching
   `sdp-create-prompt.ps1`'s proven derivation — do not invent a different one):
   a. **Primary:** if `active_phase_file` is present in state.json, derive the candidate by
      replacing its trailing `.md` with `_state.json`. If that file exists, use it.
   b. **Fallback — legacy integer convention:** extract the first integer found in
      `current_phase` (e.g., `"phase10_batch_evaluation"` → `10`). Candidate:
      `.sdp-workflow/phase[N]_state.json`. If it exists, use it.
   c. **Fallback — broad search:** if neither candidate exists, search `sdp-docs/`
      (recursively) for files matching `*phase*state.json` whose name contains `phase[N]`
      (same N as sub-step b). If exactly one match: use it. If zero or multiple matches: treat
      the phase state file as unreadable — proceed to sub-step 3 below.
2. Read the phase state file identified above.
3. If the file cannot be read: invoke `/sdp-create-banner` with icon=warning and the row below,
   then halt:
   `icon=warning row=0 row: Status | Phase state file [path] not found — cannot verify task flags.`
4. Find the entry for `active_work_item` and read its `status` and `flags` array.
5. If `"DIAGNOSIS_BLOCKED"` is present: invoke `/sdp-create-banner` with icon=error and the row
   below, then halt:
   `icon=error row=0 row: Status | [active_work_item] has DIAGNOSIS_BLOCKED — user decision required before dispatch. Provide direction, then run /sdp-auto again.`
6. If `"PARTIAL_COMPLIANCE_ESCALATE"` is present: invoke `/sdp-create-banner` with icon=error
   and the row below, then halt:
   `icon=error row=0 row: Status | [active_work_item] has PARTIAL_COMPLIANCE_ESCALATE — design review required before next WORKER dispatch. Resolve, then run /sdp-auto again.`
7. Record task `status`.

### Step 3: Verify Prompt Is Ready

1. Read `sdp-docs/00_prompt.txt`.
2. If the file cannot be read or is empty: invoke `/sdp-create-banner` with icon=warning and
   the row below, then halt:
   `icon=warning row=0 row: Status | sdp-docs/00_prompt.txt is missing or empty — run /sdp-project-coordinator to generate a dispatch prompt, then run /sdp-auto.`
3. If the file content is the stub `(empty — COORDINATOR writes this after each dispatch)`:
   invoke `/sdp-create-banner` with icon=warning and the row below, then halt:
   `icon=warning row=0 row: Status | No dispatch prompt written yet — run /sdp-project-coordinator to generate one, then run /sdp-auto.`
4. If the file does not contain an `Invoke` instruction matching `` `/sdp-[a-z-]+` ``:
   invoke `/sdp-create-banner` with icon=warning and the row below, then halt:
   `icon=warning row=0 row: Status | sdp-docs/00_prompt.txt has no skill invocation instruction — run /sdp-project-coordinator to regenerate, then run /sdp-auto.`
5. Read the first line of `sdp-docs/00_prompt.txt`. If it matches the sentinel pattern
   `[sdp-prompt work_item="..." expected_status="..."]`:
   - If sentinel `work_item` does not match `active_work_item` from Step 1: invoke
     `/sdp-create-banner` with icon=warning and the row below, then halt:
     `icon=warning row=0 row: Status | Prompt sentinel is for '[sentinel_work_item]' — current active work item is '[active_work_item]'. Run /sdp-project-coordinator to regenerate, then run /sdp-auto.`
   - If sentinel `expected_status` does not match task `status` from Step 2: invoke
     `/sdp-project-coordinator`. After it returns, proceed to Step 4.
   If the first line does not match the sentinel pattern: proceed — pre-sentinel prompt format;
   the Invoke check in sub-step 4 is sufficient.

### Step 4: Dispatch Immediate Next Step

1. Spawn a subagent via the Agent tool with the following prompt:
   "You are an SDP workflow dispatch subagent. Invoke `sdp-project-run-prompt` to execute the current
   dispatch prompt at `sdp-docs/00_prompt.txt`. Do not take any other action."
2. After the subagent returns: read the phase state file identified in Step 2 to confirm the
   new task status. Invoke
   `/sdp-create-banner icon=info row=0 row: Status | Dispatch subagent returned — task status is now [status].`
   Do not parse the subagent's text output for the outcome.

### Step 5: Start the State Loop

1. **Guard against duplicate loops.** List active scheduled jobs via the `CronList` tool. If any
   active job's command invokes `/sdp-project-state-loop` or `/sdp-solution-state-loop`, a loop is already
   running. Do **not** create a second one. Invoke `/sdp-create-banner` with icon=warning and the
   row below to announce it:
   `icon=warning row=0 row: Status | sdp-auto: a loop is already active ([job id(s)]) — not starting a second; the immediate dispatch above still ran. Run /sdp-cancel-auto first if you intend to restart the loop.`
   Skip the remaining sub-steps of Step 5.
2. Read `SDP-Config.json`.
   - If the file cannot be read or `loopInterval.interval_minutes` is absent: use interval = 5.
     Invoke `/sdp-create-banner` with icon=warning and the row below to announce it:
     `icon=warning row=0 row: Status | sdp-auto: SDP-Config.json not found or missing loopInterval.interval_minutes — defaulting to 5-minute loop interval.`
   - If the file can be read: use the value of `loopInterval.interval_minutes` as the interval.
2a. **Phase-7-gate precondition.** Read `.sdp-solution-workflow/state.json`. If `current_phase`
    is not `null` (phases 1–7 still in progress for this solution): halt — do not start any loop.
    Invoke `/sdp-create-banner icon=error row=0 row: Status | sdp-auto: phases 1-7 are still active for this solution (current_phase: [value]) — use direct sdp-solution-phase-coordinator dispatch, not the recurring loop, until Phase 7's gate passes.`
    Stop; skip the remaining sub-steps of Step 5.
2b. **One-time cron-target pick.** Read the current, live count of `SDP-Solution.json`'s
    `projects` array. This read happens once, here — never re-evaluated on any later cron fire.
    - Exactly 1 project → target = `/sdp-project-state-loop` (unmodified, today's single-project
      behavior).
    - 2+ projects → target = `/sdp-solution-state-loop` (Task 12).
3. Invoke the `loop` skill with argument `[interval]m [target]` (the target resolved in 2b).
4. Invoke `/sdp-create-banner` with icon=success and the row below to announce it:
   `icon=success row=0 row: Status | sdp-auto: loop started — [target] will monitor and dispatch every [interval] minutes.`

## Constraints

- User-initiated only — never call this skill from within `sdp-project-state-loop`, `sdp-project-coordinator`,
  or any other SDP skill. Doing so causes loop proliferation.
- Do not modify any file.
- Do not begin Step 0b until any session-start `sdp-initialize-sdp` invocation has reached its
  closing banner and closing statement. If it has not, halt at Step 0 and wait.
- Never run Steps 1-4 when Step 0b determines the resolved project's path is not exactly `"."`
  (a real `sdp-project_[Name]/` subfolder, whether one project or several) — those steps assume
  `.sdp-workflow/state.json` and `sdp-docs/00_prompt.txt` sit at the solution root, which is false
  for any solution-scoped project. Step 0b's branching (halt toward
  `/sdp-solution-phase-coordinator`, or delegate to `/sdp-state-loop-start`) replaces them for
  that case.
- Never start a loop or attempt any dispatch when Step 0b finds phases 1-7 still active
  (`current_phase` not `null`) for a non-dot-collapse project — per the bootstrap doc's Loop
  Entry Point invariant, that regime is always human-gated via direct
  `/sdp-solution-phase-coordinator` sessions, never `/sdp-auto` or any recurring loop.
- Do not parse the Step 4 dispatch subagent's text output to determine its outcome — always
  re-read the phase state file instead (mirrors core invariant #7, Outcome Detection Via State
  File Only).
- Do not start the loop (Step 5) if any halt condition in Steps 1–3 is triggered.
- The loop started in Step 5 uses `sdp-project-state-loop` (single project) or `sdp-solution-state-loop`
  (2+ projects, post-Phase-7 only — Step 5.2b picks the target once, never re-evaluated) to
  dispatch deterministically based on workflow state. `sdp-project-state-loop` handles all
  single-project state transitions automatically — WORK_COMPLETE → REVIEWER, VERIFIED →
  COORDINATOR advance, REJECTED → re-queue — without requiring `/sdp-auto` to be re-run between
  tasks. `sdp-solution-state-loop` performs `sdp-solution-phase-coordinator`'s dispatch-gating pass
  each fire instead (no per-task state machine of its own).

## Outputs

- **Dot-collapse path (Step 0b → Step 1 unchanged):** Loop started — `loop` skill running
  `sdp-project-state-loop` at the configured interval (Step 5.2b's "2+ projects" branch is
  unreachable via this path, since a dot-collapse project is always the sole project). Subagent
  spawned to invoke `sdp-project-run-prompt` for the immediate next dispatch; new task status read
  from phase state file after return.
- **Non-dot-collapse path, phases 1-7 active (Step 0b sub-step 4):** No loop started, no
  dispatch attempted — halt banner only, directing the user to `/sdp-solution-phase-coordinator`.
- **Non-dot-collapse path, phases 1-7 complete (Step 0b sub-step 4):** `/sdp-state-loop-start`
  invoked via the Skill tool — that skill's own outputs (loop start + COORDINATOR priming) apply;
  this skill performs none of Steps 1-5 itself in this case.
- No files written or modified by this skill directly in any path.
