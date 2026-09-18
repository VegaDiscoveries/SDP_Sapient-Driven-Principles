## Purpose

Explicit per-session opt-in to auto-advance the solution's own phases 1-7 (Concept through
Phase Readiness) via a recurring loop. Distinct entry point from `sdp-auto`/`sdp-state-loop-start`
— neither of those is modified by this skill; both continue to refuse phases-1-7 dispatch
exactly as before for anyone not using this one. Starts the loop first (so its interval clock
begins running immediately), then runs one `sdp-solution-phase-coordinator` pass to prime an
accurate `sdp-solution-docs/00_solution_prompt.txt` before the loop's first fire — the same
ordering `sdp-state-loop-start` already uses for the project-level case, and for the identical
reason (the `loop` skill only schedules the recurring fire; it does not fire immediately on
creation).

This skill is user-initiated only. It is never called by `sdp-solution-phase-state-loop` or any
other SDP skill — calling it from within an automated path would cause loop proliferation.

## Inputs

- `SDP-Solution.json` — confirms the solution root is set up (no per-project resolution needed;
  phases 1-7 are solution-scoped, not project-scoped)
- `.sdp-solution-workflow/state.json` — `current_phase` (confirms phases 1-7 have actually
  started for this solution; nothing to auto-advance if not)
- `SDP-Config.json` — `loopInterval.interval_minutes`

## Procedure

### Step 0: Await Session-Start Completion

1. Check whether the session-start hook triggered `sdp-initialize-sdp` in this session (the
   SessionStart hook's actual configured target). Signs it was triggered but not yet confirmed:
   the `sdp-initialize-sdp` skill invocation appears in conversation context but its closing
   banner and one-sentence closing statement have not yet been output.
2. If still in progress: invoke
   `/sdp-create-banner icon=pending row=0 row: Status | sdp-solution-phase-auto: awaiting session-start (sdp-initialize-sdp) completion before proceeding.`
   Halt. Resume from Step 0 once `sdp-initialize-sdp` completes.
3. If completed (or not triggered this session): proceed to Step 1.

### Step 1: Validate Preconditions

1. Read `SDP-Solution.json` at the solution root. If absent or unreadable: halt — invoke
   `/sdp-create-banner icon=error row=0 row: Status | Cannot start the solution-phase loop — SDP-Solution.json not found at solution root. Run /sdp-workspace-setup first.`
2. Read `.sdp-solution-workflow/state.json`. If absent or unreadable: halt — invoke
   `/sdp-create-banner icon=error row=0 row: Status | Cannot start the solution-phase loop — .sdp-solution-workflow/state.json not found. Run /sdp-solution-new-concept-intake or /brainstorming first to seed phases 1-7.`
3. If `current_phase` is `null`: halt — invoke
   `/sdp-create-banner icon=warning row=0 row: Status | current_phase is null — phases 1-7 have not started (or are already complete) for this solution. Nothing for sdp-solution-phase-state-loop to advance. If phases 1-7 are complete, use /sdp-auto or /sdp-state-loop-start for post-Phase-7 dispatch instead.`
4. Otherwise: invoke
   `/sdp-create-banner icon=info row=0 row: Status | Preconditions confirmed — current_phase is '[value]'. Proceeding.`

### Step 2: Start the Loop

1. **Guard against duplicate loops.** List active scheduled jobs via the `CronList` tool.
   - If any active job's command invokes `/sdp-solution-phase-state-loop`: halt — invoke
     `/sdp-create-banner icon=warning row=0 row: Status | sdp-solution-phase-auto: a solution-phase loop is already active ([job id(s)]) — not starting a second. Run /sdp-cancel-auto first if you intend to restart it.`
     Do not proceed to Step 3.
   - If any active job's command invokes `/sdp-project-state-loop` or
     `/sdp-solution-state-loop` (post-Phase-7 loops — not a solution-phase loop, so not covered
     by the bullet above): cancel it via the `CronDelete` tool, mirroring
     `sdp-solution-new-concept-intake` Step 4a's identical guard for the same reason — those
     loops dispatch post-Phase-7 project work, which has nothing to do while phases 1-7 are
     active, and leaving one running unattended while a human is meant to be driving fresh
     solution-level work is the same confusing-state risk that skill's own Step 4a already
     guards against. Note the cancellation for Step 3's closing banner (an added row, same shape
     as that skill's own Step 5 hand-off banner).
2. Read `SDP-Config.json`.
   - If the file cannot be read or `loopInterval.interval_minutes` is absent: use interval = 5.
     Invoke `/sdp-create-banner icon=warning row=0 row: Status | sdp-solution-phase-auto: SDP-Config.json not found or missing loopInterval.interval_minutes — defaulting to 5-minute loop interval.`
   - If readable: use `loopInterval.interval_minutes` as the interval.
3. Invoke the `loop` skill with argument `[interval]m sdp-solution-phase-state-loop`.
4. Do not announce separately here — Step 3 sub-step 3 below reports the loop-started fact
   together with the priming outcome in one closing banner, mirroring
   `sdp-state-loop-start`'s own ordering.

### Step 3: Prime the Dispatch Prompt

1. Invoke
   `/sdp-create-banner icon=in-progress row=0 row: Status | Priming dispatch prompt — spawning a COORDINATOR subagent so sdp-solution-docs/00_solution_prompt.txt is accurate before the loop's first fire.`
2. Spawn a subagent via the Agent tool: "You are an SDP COORDINATOR priming subagent. Invoke
   `sdp-solution-phase-coordinator` to determine the correct next phases-1-7 dispatch and write
   an accurate `sdp-solution-docs/00_solution_prompt.txt` and session file. Do NOT spawn any
   WORKER, REVIEWER, or GATE_REVIEWER subagent yourself — the recurring loop performs execution.
   Stop after the dispatch prompt and session file are written."
3. After the subagent returns, confirm from files (not the subagent's text): read the first
   line of `sdp-solution-docs/00_solution_prompt.txt`. If it matches the phases-1-7 sentinel
   shape, invoke
   `/sdp-create-banner icon=success,success row=0,1 row: Loop | Loop started — sdp-solution-phase-state-loop will monitor and dispatch every [interval] minutes. row: Primed | sdp-solution-phase-coordinator primed the prompt for [current_phase] (role [role]) — the loop's first fire will execute it.`
   If no valid sentinel was written: invoke
   `/sdp-create-banner icon=success row=0 row: Loop | Loop started — sdp-solution-phase-state-loop will monitor and dispatch every [interval] minutes.`
   then read `.sdp-solution-workflow/state.json`; if `workflow_status` is `"halted"`, invoke
   `/sdp-create-banner icon=warning row=0 row: Status | [blocking condition] — the loop will STOP on its first fire until this condition is resolved.`
4. If Step 2 sub-step 1 cancelled a conflicting `/sdp-project-state-loop` or
   `/sdp-solution-state-loop` job, append a row to whichever banner variant sub-step 3 fired:
   `row: Cancelled | A running post-Phase-7 loop ([job id(s)]) was stopped — phases 1-7 are
   active again.` Omit this row entirely if sub-step 1 found no conflicting job to cancel.

## Constraints

- User-initiated only — never call this skill from within `sdp-solution-phase-state-loop` or any
  other SDP skill.
- Never write project files or solution-phase files directly — the dispatch prompt, session
  file, and `state.json` updates come from the spawned `sdp-solution-phase-coordinator` subagent
  in Step 3.
- Do not begin Step 1 until any session-start `sdp-initialize-sdp` invocation has reached its
  closing banner and closing statement.
- Never start a second loop when an active `sdp-solution-phase-state-loop` job already exists —
  Step 2 sub-step 1 checks via `CronList` and halts if one is found.
- Never start the loop or spawn priming when `current_phase` is `null` — Step 1 sub-step 3
  halts first.
- The priming subagent must not spawn a WORKER, REVIEWER, or GATE_REVIEWER — Step 3 sub-step 2's
  prompt forbids it explicitly.

## Outputs

- Loop started: `loop` skill running `sdp-solution-phase-state-loop` at the configured interval.
- `sdp-solution-phase-coordinator` subagent spawned to prime an accurate dispatch prompt and
  session file; sentinel read back to confirm.
- This skill writes no project or solution-phase files directly.
