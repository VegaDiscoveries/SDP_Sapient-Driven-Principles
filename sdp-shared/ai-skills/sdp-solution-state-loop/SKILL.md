## Purpose

Deterministic loop guard for a recurring `/loop` session, used only in the 2+ project,
post-Phase-7 regime. Unlike `sdp-project-state-loop` (which drives one project's own GENERATE/EXECUTE/
GATE_REPAIR/API_RECOVERY cycle), this skill contains no branching logic of its own for the
dispatch-gating role — by construction it is never installed during phases 1–7 (Loop Entry Point,
bootstrap doc), so every fire performs `sdp-solution-phase-coordinator`'s post-Phase-7
dispatch-gating role (Step 2d) directly. (`sdp-solution-coordinator` also carries a copy of this
Step 2d text, but by that skill's own admission it never actually executes there — its backing
script hard-errors on a null `active_solution_task` before reaching it.
`sdp-solution-phase-coordinator` is the live copy.)

Every fire also performs a subagent-budget check first (Step 1) — see
`~SDP-Maintenance/~docs/subagent-budget-respawn-design.md` for the full RESPAWN design. Claude
Code enforces a hard per-session, cumulative-lifetime subagent-spawn ceiling; this loop can run
unattended for many hours, so it must detect the budget approaching exhaustion and hand off to a
fresh terminal session automatically, without human intervention, before the platform's own hard
cap ever fires mid-dispatch.

## Inputs

- `.sdp-solution-workflow/state.json` — `current_phase` (expected `null` — see Constraints),
  `workflow_status`, `halt_reason`, `auto_actions` (RESPAWN bookkeeping)
- `.sdp-solution-workflow/dependencies.json` — ledger state read by the dispatch-gating peek
- `SDP-Solution.json` — `projects` registry
- `SDP-Config.json` — `sessionSubagentBudget` (`maxSubagentsPerSession`, `respawnAtCount`,
  `hardStopCount`, `autoRespawn`)
- `sdp-shared/scripts/script-support/SDP-Terminal-Sessions.json` — this session's own
  terminal-registry row (status update on RESPAWN)
- `.sdp-solution-workflow/logging/loop-logs/loop-metrics-*.jsonl` — write-only, append-only fire
  log, same convention `sdp-project-state-loop` already uses at the solution root
- `.sdp-solution-workflow/logging/hook-logs/hook-log-*.jsonl` — read by the budget-check
  sub-skills (`sdp-claude-session-get-sessionid`, `sdp-claude-session-get-agentcount`)

## Procedure

### Step 1: Subagent Budget Check

1. Run via the PowerShell tool — reads `sessionSubagentBudget` from `SDP-Config.json` and, only
   if enabled, also generates the discovery marker in this same call (no separate script file;
   mechanical value generation only, same marker shape `sdp-claude-session-get-sessionid` itself
   uses):
   ```
   $cfg = Get-Content SDP-Config.json -Raw | ConvertFrom-Json
   $budget = $cfg.sessionSubagentBudget
   if (-not $budget -or $budget.autoRespawn -ne $true) {
     @{ enabled = $false } | ConvertTo-Json -Compress
   } else {
     $marker = "SESSION-ID-TEST-MARKER-" + [guid]::NewGuid().ToString("N").Substring(0,16)
     @{ enabled = $true; respawnAtCount = $budget.respawnAtCount; hardStopCount = $budget.hardStopCount; marker = $marker } | ConvertTo-Json -Compress
   }
   ```
   If `enabled` is `false`: record `respawnPending = false`, `skipDispatchThisFire = false`.
   Proceed to Step 2.
2. Otherwise, invoke `/sdp-claude-session-get-agentcount -marker "[literal marker from sub-step
   1]"` — no `-sessionId` (its self-discovery mode already resolves and returns `session_id`
   internally before it can count agents, so a separate `sdp-claude-session-get-sessionid` call
   is unnecessary for this caller, which needs both values — see the design doc's design-session
   #2 addition). Record `ownSessionId = result.session_id`, `agentCount = result.agent_count`. If
   the result's `status` is not `"success"`: no budget check can be performed this fire — fail
   safe, record `respawnPending = false`, `skipDispatchThisFire = false` (skip the respawn
   attempt rather than risk a decision on incomplete data; the next fire retries). Proceed to
   Step 2.
3. If `agentCount < respawnAtCount`: record `respawnPending = false`,
   `skipDispatchThisFire = false`. Proceed to Step 2.
4. If `respawnAtCount <= agentCount < hardStopCount`: record `respawnPending = true`,
   `skipDispatchThisFire = false`. Invoke `/sdp-cancel-auto` **immediately** — before anything
   else in this fire proceeds — so no further scheduled fire can race the transition, regardless
   of how long the rest of this fire's own dispatch takes. Proceed to Step 2; this fire's own
   normal dispatch logic (Steps 2–4 below) still runs (never orphan an already-due dispatch —
   there is still comfortable headroom under the hard cap at this tier).
5. If `agentCount >= hardStopCount`: record `respawnPending = true`,
   `skipDispatchThisFire = true`. Invoke `/sdp-cancel-auto` immediately. **Skip Steps 2–4 below
   entirely this fire** — proceed directly to Step 5. The dispatch that would have run is picked
   up by the new session's own first fire instead (`/sdp-state-loop-start` already primes an
   accurate first-fire dispatch on launch, so nothing is silently dropped — only delayed by one
   respawn cycle). This tier exists because a single fire's dispatch-gating pass can itself
   consume more agents than the `respawnAtCount` buffer alone would safely cover — see the design
   doc's Con 1 resolution.

### Step 2: API Error Pre-Check

Skipped entirely when `skipDispatchThisFire` is `true` (Step 1 sub-step 5) — proceed directly to
Step 5. Otherwise, identical to `sdp-project-state-loop` Step 1: scan the most recent 10 lines of
conversation context for `API Error: `. If found: record `action = API_RECOVERY`, skip to Step 5
with a subagent instructed to invoke `sdp-project-run-prompt` for solution-level recovery (no
`[resolved_project]` substitution — the dispatch target is the solution root).

### Step 3: Read Solution State

Skipped entirely when `skipDispatchThisFire` is `true` — proceed directly to Step 5.

1. Read `.sdp-solution-workflow/state.json`.
2. If `workflow_status` is `"halted"`: record `action = STOP`, `reason = halt_reason`. Proceed to
   Step 5 (fire logging), then stop.
3. If `current_phase` is not `null`: this is a configuration error — a cron job should never exist
   while phases 1–7 are active (Loop Entry Point invariant). Record `action = STOP`,
   `reason = "current_phase is not null — phases 1-7 appear active; this loop should not be
   running (see sdp-solution-new-concept-intake's cron-cancel step)"`. Invoke
   `/sdp-create-banner icon=error row=0 row: Status | sdp-solution-state-loop: current_phase is set — this loop should not be active during phases 1-7. Cancel it and use direct sdp-solution-phase-coordinator dispatch instead.`
   Proceed to Step 5, then stop.

### Step 4: Dispatch-Gating Fire

Skipped entirely when `skipDispatchThisFire` is `true` — proceed directly to Step 5.

Spawn a subagent via the Agent tool with the instruction: "Invoke `sdp-solution-phase-coordinator`
to perform this cycle's post-Phase-7 dispatch-gating pass (Step 2d)." Do not parse the subagent's
text output for outcome — after it returns, re-read `.sdp-solution-workflow/state.json` and each
touched project's `state.json` to confirm what actually dispatched, mirroring `sdp-project-state-loop`'s
own "never parse subagent text" discipline. Record `action = DISPATCH_GATING_PASS`.

### Step 5: Record the Fire

1. Append one line to today's `.sdp-solution-workflow/logging/loop-logs/loop-metrics-*.jsonl`,
   mirroring `sdp-project-state-loop` Step 6's envelope shape (fire timestamp, action, reason,
   halted flag). When `skipDispatchThisFire` was `true` (Steps 2–4 were skipped this fire), this
   line records `action: "SKIPPED_FOR_RESPAWN"` instead of a normal dispatch action, so the
   metrics stream doesn't misreport a dispatch that never ran.
2. **If `respawnPending` is `true`:**
   a. Launch the replacement terminal:
      ```
      sdp-claude-new-terminal -terminal session-respawn -callerSessionId [ownSessionId] -promptOverride "/sdp-claude-session-init -launcherSessionId [ownSessionId] -thenRun \"/sdp-state-loop-start\""
      ```
      The static `session-respawn` profile entry in `SDP-Config.json`'s `newTerminals[]`
      documents the intended shape for reference; the real launch always goes through
      `-promptOverride` since a static profile can never hold a per-launch dynamic `session_id`.
   b. Append to `auto_actions` in `.sdp-solution-workflow/state.json`:
      `{"timestamp": "[ISO]", "trigger": "sessionSubagentBudget.respawnAtCount reached",
      "action": "session_respawn", "agent_count": [agentCount], "launcher_session_id":
      "[ownSessionId]", "outcome": "success"|"error"}` — `launcher_session_id` is the
      correlation key `sdp-claude-session-init` uses to find and confirm this entry from the new
      session (see that skill's own Step 3).
   c. Log via `sdp-workflow-log.ps1` (role `STATE_LOOP`, outcome reflecting the respawn) — same
      semantic workflow-log stream other significant loop events already use.
   d. Invoke `/sdp-create-banner` (icon=success) reporting the respawn and that this session's
      loop has stopped — continue in the new terminal. On a launch failure instead (sub-step a's
      envelope reports `status: "error"`): the cron job is already cancelled by this point (Step
      1 sub-step 4 or 5) — this session cannot silently keep looping. Invoke
      `/sdp-create-banner` (icon=error) reporting the launch error instead, and leave
      `workflow_status` at `"active"` (still not a halt — a human needs to manually launch the
      replacement, but SDP's own workflow state isn't blocked). Do not retry the launch
      automatically within the same fire; do not write any further escalation flag beyond the
      `auto_actions` entry (sub-step b, `outcome: "error"`) — a resolution was considered and
      declined as not actually closing the gap (see the design doc's Con 3 resolution); the
      residual risk of an unattended failure going unnoticed is accepted.
   e. Append a **second** line to today's `loop-metrics-*.jsonl` with `action: "RESPAWN"` — kept
      separate from the fire's normal action line (written in sub-step 1) rather than overloading
      the existing single-action-per-line schema, since RESPAWN is a distinct event layered on
      top of whatever this fire's normal dispatch action was (or `"SKIPPED_FOR_RESPAWN"` — see
      sub-step 1).
   f. Look up this session's own row in `SDP-Terminal-Sessions.json` via `ownSessionId`
      matching that row's `sessionId` field. If found: set `status` to `"idle-respawned"` —
      gives any future reader of the registry a way to distinguish a live session from one that
      cancelled its own loop and went idle after a successful respawn. If no matching row is
      found (this session was not itself launched via `sdp-claude-new-terminal.ps1` — true only
      for the first session in a chain; every session after the first hop has its own row from
      its own launch): skip silently, do not create or guess at a match.

## Constraints

- Never installed during phases 1–7 — Step 3's `current_phase` check is a defensive guard, not
  the primary enforcement (the primary enforcement is `sdp-solution-new-concept-intake`'s cron-cancel step
  and `sdp-auto`/`sdp-state-loop-start`'s Phase-7-gate precondition, Task 14).
- Contains no `eval_cycle_attempts`/`gate_review_attempts` halt-threshold machinery —
  dispatch-gating has no per-task or per-gate retry concept; `sdp-solution-phase-coordinator`'s
  own Stuck-Dependency Detection (Task 10) is the equivalent escalation path for this regime.
- Never invoke `sdp-project-coordinator` or `sdp-project-worker`/`sdp-project-reviewer` directly from this skill — always
  via the `sdp-solution-phase-coordinator` subagent dispatch in Step 4, exactly like `sdp-project-state-loop`
  never directly invokes WORKER/REVIEWER logic itself.
- Never modify `sdp-project-state-loop` to add the equivalent subagent-budget check — that is a
  separate, later change, out of scope for this design (Core Invariant #8, Skill Scope Boundary:
  a project-level skill is never modified to add solution-level capability, and the reverse holds
  by the same reasoning here).
- Never treat a RESPAWN (`respawnPending = true`) as a halt — `workflow_status` is never touched
  by Step 5 sub-step 2; the workflow is not blocked, only this OS process is being retired in
  favor of a fresh one.
- Never retry a failed replacement-terminal launch automatically within the same fire (Step 5
  sub-step 2d).

## Outputs

- One dispatch-gating pass performed per fire (zero or more projects' `sdp-project-coordinator`
  invoked) — skipped entirely on a `hardStopCount`-tier fire (Step 1 sub-step 5).
- `.sdp-solution-workflow/logging/loop-logs/loop-metrics-*.jsonl` — one appended fire record,
  plus a second `RESPAWN` record on any fire where `respawnPending` was `true`.
- On a RESPAWN fire: replacement terminal launched, `auto_actions` entry appended, workflow-log
  entry written, banner shown, and this session's own terminal-registry row marked
  `"idle-respawned"`.
