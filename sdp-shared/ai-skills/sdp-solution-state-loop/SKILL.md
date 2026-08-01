## Purpose

Deterministic loop guard for a recurring `/loop` session, used only in the 2+ project,
post-Phase-7 regime. Unlike `sdp-project-state-loop` (which drives one project's own GENERATE/EXECUTE/
GATE_REPAIR/API_RECOVERY cycle), this skill contains no branching logic of its own — by
construction it is never installed during phases 1–7 (Loop Entry Point, bootstrap doc), so every
fire simply performs `sdp-solution-phase-coordinator`'s post-Phase-7 dispatch-gating role (Step
2d) directly. (`sdp-solution-coordinator` also carries a copy of this Step 2d text, but by that
skill's own admission it never actually executes there — its backing script hard-errors on a
null `active_solution_task` before reaching it. `sdp-solution-phase-coordinator` is the live
copy.)

## Inputs

- `.sdp-solution-workflow/state.json` — `current_phase` (expected `null` — see Constraints),
  `workflow_status`, `halt_reason`
- `.sdp-solution-workflow/dependencies.json` — ledger state read by the dispatch-gating peek
- `SDP-Solution.json` — `projects` registry
- `.sdp-solution-workflow/logging/loop-logs/loop-metrics-*.jsonl` — write-only, append-only fire
  log, same convention `sdp-project-state-loop` already uses at the solution root

## Procedure

### Step 1: API Error Pre-Check

Identical to `sdp-project-state-loop` Step 1: scan the most recent 10 lines of conversation context for
`API Error: `. If found: record `action = API_RECOVERY`, skip to Step 4 with a subagent
instructed to invoke `sdp-project-run-prompt` for solution-level recovery (no `[resolved_project]`
substitution — the dispatch target is the solution root).

### Step 2: Read Solution State

1. Read `.sdp-solution-workflow/state.json`.
2. If `workflow_status` is `"halted"`: record `action = STOP`, `reason = halt_reason`. Proceed to
   Step 4 (fire logging), then stop.
3. If `current_phase` is not `null`: this is a configuration error — a cron job should never exist
   while phases 1–7 are active (Loop Entry Point invariant). Record `action = STOP`,
   `reason = "current_phase is not null — phases 1-7 appear active; this loop should not be
   running (see sdp-new-concept-intake's cron-cancel step)"`. Invoke
   `/sdp-create-banner icon=error row=0 row: Status | sdp-solution-state-loop: current_phase is set — this loop should not be active during phases 1-7. Cancel it and use direct sdp-solution-phase-coordinator dispatch instead.`
   Proceed to Step 4, then stop.

### Step 3: Dispatch-Gating Fire

Spawn a subagent via the Agent tool with the instruction: "Invoke `sdp-solution-phase-coordinator`
to perform this cycle's post-Phase-7 dispatch-gating pass (Step 2d)." Do not parse the subagent's
text output for outcome — after it returns, re-read `.sdp-solution-workflow/state.json` and each
touched project's `state.json` to confirm what actually dispatched, mirroring `sdp-project-state-loop`'s
own "never parse subagent text" discipline. Record `action = DISPATCH_GATING_PASS`.

### Step 4: Record the Fire

Append one line to today's `.sdp-solution-workflow/logging/loop-logs/loop-metrics-*.jsonl`,
mirroring `sdp-project-state-loop` Step 6's envelope shape (fire timestamp, action, reason, halted flag).

## Constraints

- Never installed during phases 1–7 — Step 2's `current_phase` check is a defensive guard, not
  the primary enforcement (the primary enforcement is `sdp-new-concept-intake`'s cron-cancel step
  and `sdp-auto`/`sdp-state-loop-start`'s Phase-7-gate precondition, Task 14).
- Contains no `eval_cycle_attempts`/`gate_review_attempts` halt-threshold machinery —
  dispatch-gating has no per-task or per-gate retry concept; `sdp-solution-phase-coordinator`'s
  own Stuck-Dependency Detection (Task 10) is the equivalent escalation path for this regime.
- Never invoke `sdp-project-coordinator` or `sdp-project-worker`/`sdp-project-reviewer` directly from this skill — always
  via the `sdp-solution-phase-coordinator` subagent dispatch in Step 3, exactly like `sdp-project-state-loop`
  never directly invokes WORKER/REVIEWER logic itself.

## Outputs

- One dispatch-gating pass performed per fire (zero or more projects' `sdp-project-coordinator` invoked)
- `.sdp-solution-workflow/logging/loop-logs/loop-metrics-*.jsonl` — one appended fire record
