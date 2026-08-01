## Purpose

Deterministic loop guard for a recurring `/loop` session: check for API error signals, read
workflow state, evaluate a prompt-file sentinel against current state, and dispatch a single
action — or stop if the workflow requires human input.

Each loop fire takes exactly one action: GENERATE (write next dispatch prompt), EXECUTE (run
current dispatch prompt), GATE_REPAIR (dispatch COORDINATOR to complete a gate dispatch that
never got its session file), API_RECOVERY (resume interrupted session), or STOP.

## Inputs

- Current conversation context (API error scan only — no file tools)
- `[resolved_project]/.sdp-workflow/state.json` — workflow status and active work item
- Phase state file — active task status, flags, `eval_cycle_attempts`, and `eval_cycles`
- `[resolved_project]/sdp-docs/00_prompt.txt` — sentinel line only (first line read)
- `SDP-Config.json` — `autoResolveHalt.evalCycleAttemptThreshold` (default 2) and
  `autoResolveHalt.pushOnEvalBlock` (default false)
- `.sdp-solution-workflow/logging/loop-logs/loop-metrics-*.jsonl` — write-only, solution-root,
  append-only fire log (Step 6). One file per calendar day; Step 6 always targets today's file,
  creating it on the first fire of the day. Not read by this skill.

`[resolved_project]` is resolved from the sentinel `projects=` field in Step 1b (first entry
when multiple projects are listed). All file paths in this skill use `[resolved_project]` as
their root.

## Procedure

### Step 1: API Error Pre-Check

Scan only the **most recent 10 lines** of the current conversation context for the literal
text `API Error: ` (with the colon and trailing space). If fewer than 10 lines are available,
scan all available lines.

- If `API Error: ` is found within the scanned lines: record **action = API_RECOVERY**.
  Skip Steps 2–4 entirely — proceed to Step 5.
- If `API Error: ` is not found (including when fewer than 10 lines were available):
  proceed to Step 1b.

### Step 1b: Resolve Project

Attempt to resolve `[resolved_project]` using the following priority order:

**Level 1 — Sentinel `projects=` attribute (primary).**
Read only the first line of `SDP-Solution.json` → `last_active_projects[0]` to derive a
candidate path, then read the first line of `[candidate]/sdp-docs/00_prompt.txt`. If
`SDP-Solution.json` is readable and `last_active_projects` is non-empty, use that candidate
path for the initial read. Otherwise attempt to read `sdp-docs/00_prompt.txt` directly (legacy
single-project path).

Attempt to extract the `projects=` attribute from the sentinel pattern:
`[sdp-prompt work_item="..." expected_status="..." role="..." projects="..."]`

- If the `projects=` attribute is present and non-empty: take the **first** comma-separated
  entry as `[resolved_project]` (e.g., `projects="sdp-project_VirtualCoinFolio.API,sdp-project_VirtualCoinFolio.Website"`
  → `resolved_project = sdp-project_VirtualCoinFolio.API`). Trim any whitespace.

**Level 2 — `SDP-Solution.json` `last_active_projects` (fallback).**
If the sentinel read above did not yield a `projects=` attribute:

- If `SDP-Solution.json` was readable and `last_active_projects[0]` is present: use that
  value as `[resolved_project]`. Log: "sdp-project-state-loop: no `projects=` in sentinel — resolved
  from SDP-Solution.json last_active_projects."
- If `SDP-Solution.json` is absent: set `[resolved_project]` to `.` (dot — preserves legacy
  single-project behavior). Log: "sdp-project-state-loop: SDP-Solution.json not found — using
  workspace root as project root."
- If `SDP-Solution.json` is readable but `last_active_projects` is empty or absent: read the
  `projects` array from `SDP-Solution.json`.
  - If `projects` contains exactly 1 entry: use it as `[resolved_project]`. Log:
    "sdp-project-state-loop: last_active_projects empty — auto-resolved from single projects entry."
  - If `projects` contains 2 or more entries: report "⛔ sdp-project-state-loop:
    `last_active_projects` is empty and multiple projects are registered — cannot
    auto-resolve. Set `last_active_projects` in `SDP-Solution.json` to the target project
    and retry." Stop — do not proceed.
  - If `projects` is empty or absent: set `[resolved_project]` to `.` (dot — legacy
    fallback). Log: "sdp-project-state-loop: no projects registered — using workspace root as
    project root."

Record `[resolved_project]`. All subsequent file paths in this skill use this value as their
root prefix (e.g., `[resolved_project]/.sdp-workflow/state.json`).

Proceed to Step 2.

### Step 2: Read Workflow State

1. Read `[resolved_project]/.sdp-workflow/state.json` (project resolved in Step 1b).
2. If the file cannot be read: invoke
   `/sdp-create-banner icon=warning row=0 row: Status | [resolved_project]/.sdp-workflow/state.json not found or unreadable — no dispatch.`
   Record `action = STOP`, `reason = "state.json not found
   or unreadable"`. Proceed to Step 6 to record the fire, then stop — do not proceed to Step 3.
3. If `workflow_status` is `"halted"`: play the notification tone (non-blocking — ignore any
   failure and continue): run `./sdp-shared/scripts/sdp-tone.ps1 -trigger "halt.generic"` via
   the PowerShell tool. Then invoke
   `/sdp-create-banner icon=error row=0 row: Status | Workflow halted — [halt_reason from state.json]. No dispatch.`
   Record `action = STOP`, `reason = "workflow already halted:
   [halt_reason]"`. Proceed to Step 6 to record the fire, then stop.
4. If `active_work_item` is null: play the notification tone (non-blocking — ignore any failure
   and continue): run `./sdp-shared/scripts/sdp-tone.ps1 -trigger "halt.generic"` via the
   PowerShell tool. Then invoke
   `/sdp-create-banner icon=warning row=0 row: Status | sdp-project-state-loop: no active work item — no dispatch.`
   Record `action = STOP`, `reason = "no active work item"`. Proceed to Step 6 to record the
   fire, then stop.
5. Record `active_work_item`.

### Step 3: Read Task State

1. Identify the phase state file using this three-tier resolution (matching
   `sdp-create-prompt.ps1`'s proven derivation — do not invent a different one):
   a. **Primary:** if `active_phase_file` is present in state.json, derive the candidate by
      replacing its trailing `.md` with `_state.json`. If that file exists, use it.
   b. **Fallback — legacy integer convention:** extract the first integer found in
      `current_phase` (e.g., `"phase10_batch_evaluation"` → `10`). Candidate:
      `[resolved_project]/.sdp-workflow/phase[N]_state.json`. If it exists, use it.
   c. **Fallback — broad search:** if neither candidate exists, search
      `[resolved_project]/sdp-docs/` (recursively) for files matching `*phase*state.json` whose
      name contains `phase[N]` (same N as sub-step b). If exactly one match: use it. If zero or
      multiple matches: treat the phase state file as unreadable — proceed to sub-step 3 below.
2. Read the phase state file identified above.
3. If the file cannot be read: invoke
   `/sdp-create-banner icon=warning row=0 row: Status | Phase state file [path] not found or unreadable — no dispatch.`
   Record `action = STOP`, `reason = "phase state file not found or unreadable"`.
   Proceed to Step 6 to record the fire, then stop.
4. Find the entry for `active_work_item` and read its `status` field and `flags` array.
5. If `"DIAGNOSIS_BLOCKED"` is present in flags: play the notification tone (non-blocking —
   ignore any failure and continue): run `./sdp-shared/scripts/sdp-tone.ps1 -trigger "halt.generic"`
   via the PowerShell tool. Then invoke
   `/sdp-create-banner icon=error row=0 row: Status | [active_work_item] has DIAGNOSIS_BLOCKED — user decision required before dispatch. No dispatch.`
   Record
   `action = STOP`, `reason = "[active_work_item] DIAGNOSIS_BLOCKED"`. Proceed to Step 6 to
   record the fire, then stop.
6. If `"PARTIAL_COMPLIANCE_ESCALATE"` is present in flags: play the notification tone
   (non-blocking — ignore any failure and continue): run
   `./sdp-shared/scripts/sdp-tone.ps1 -trigger "halt.generic"` via the PowerShell tool. Then
   invoke
   `/sdp-create-banner icon=error row=0 row: Status | [active_work_item] has PARTIAL_COMPLIANCE_ESCALATE — design review required before next WORKER dispatch. No dispatch.`
   Record `action = STOP`, `reason = "[active_work_item]
   PARTIAL_COMPLIANCE_ESCALATE"`. Proceed to Step 6 to record the fire, then stop.
7. Record task `status`.
8. Read `eval_cycle_attempts` from the entry; if the field is absent, treat it as 0.
   Record as `eval_cycle_attempts`.
9. Read `eval_cycles` from the entry; if the field is absent, treat it as 0.
   Record as `eval_cycles`.
10. Read `phase_gate` from `[resolved_project]/.sdp-workflow/state.json` (already read in
    Step 2). If the `phase_gate` key is absent, treat as
    `{ "status": "pending", "gate_review_attempts": 0, "gate_eval_cycles": 0 }`.
    Record `gate_review_attempts` and `gate_eval_cycles`.

### Step 4: Evaluate Sentinel

1. Read only the first line of `[resolved_project]/sdp-docs/00_prompt.txt` using the Read
   tool (limit: 1 line). (`[resolved_project]` was set in Step 1b; this read may reuse the
   cached first line from Step 1b if already in context — the path is identical.)
2. Attempt to parse the sentinel pattern:
   `[sdp-prompt work_item="<ID>" expected_status="<STATUS>" role="<ROLE>" projects="<PROJECTS>"]`
   The `role` and `projects` fields may be absent in prompts written before these attributes
   were introduced — treat a missing `role` as unknown; a missing `projects` is already
   handled by Step 1b's fallback.
3. If the file cannot be read, is empty, contains the stub
   `(empty — COORDINATOR writes this after each dispatch)`, or the first line does not match
   the sentinel pattern: record **action = GENERATE**. Reason: "no valid sentinel".
   Proceed to Step 5.
4. Extract `work_item`, `expected_status`, `role`, and `projects` from the sentinel (record
   `role` as `sentinel_role`; if the field is absent, record `sentinel_role` as unknown;
   `projects` was already consumed in Step 1b for path resolution).
5. **If `sentinel_role` is `GATE_REVIEWER`:** bypass the `work_item == active_work_item`
   comparison. Instead:
   a. Compare `work_item` against `current_phase` from `state.json`. If they do not match:
      record **action = GENERATE**. Reason: "GATE_REVIEWER sentinel work_item '[extracted]'
      does not match current_phase '[current_phase]'". Proceed to Step 5.
   b. Compare `expected_status` against `state.json.phase_gate.status`. If they do not match:
      record **action = GENERATE**. Reason: "GATE_REVIEWER sentinel expected_status
      '[extracted]' does not match phase_gate.status '[phase_gate.status]'". Proceed to Step 5.
   c. **Dispatch-file integrity check.** Sub-steps a and b matched — before trusting the
      sentinel, confirm a real GATE_REVIEWER dispatch file backs it:
      - If `state.json.last_session` is absent, null, or `"none"`: record
        **action = GATE_REPAIR**. Reason: "GATE_REVIEWER sentinel has no last_session
        recorded — no dispatch file exists". Proceed to Step 5.
      - Read `[resolved_project]/.sdp-workflow/sessions/session-[last_session].md` (the
        session number extracted from `last_session`). If the file does not exist: record
        **action = GATE_REPAIR**. Reason: "GATE_REVIEWER sentinel references
        session-[last_session].md, which does not exist". Proceed to Step 5.
      - If the file exists, read it in full — this is a short template file and the one
        exception to this skill's "read only the sentinel line" pattern, because the
        session file's `Role:` and `Work Item:` fields are the only on-disk record of what
        a prior dispatch actually committed. Check for both a line matching
        `Role: GATE_REVIEWER` and a line matching `Work Item: [current_phase]` (the exact
        value from `state.json.current_phase`). If either is absent or does not match:
        record **action = GATE_REPAIR**. Reason: "session-[last_session].md does not match
        the GATE_REVIEWER sentinel — Role or Work Item field mismatch". Proceed to Step 5.
      - Both fields present and matching: proceed to sub-step d.
   d. Sub-steps a, b, and c all passed: record **action = EXECUTE**. Proceed to Step 5.
   Do not evaluate sub-steps 6–7 when `sentinel_role` is `GATE_REVIEWER`.
6. If extracted `work_item` does not equal `active_work_item` (from Step 2): record
   **action = GENERATE**. Reason: "sentinel work_item '[extracted]' does not match active
   work item '[active_work_item]'". Proceed to Step 5.
7. If extracted `expected_status` does not equal current task `status` (from Step 3): record
   **action = GENERATE**. Reason: "sentinel expected status '[extracted]' does not match
   current status '[status]'". Proceed to Step 5.
8. Both values match: record **action = EXECUTE**. Proceed to Step 5.

### Step 5: Execute

Act based on the action recorded in Steps 1–4.

**API_RECOVERY:**
1. Play the notification tone (non-blocking — ignore any failure and continue): run
   `./sdp-shared/scripts/sdp-tone.ps1 -trigger "api.error_detected"` via the PowerShell tool.
2. Announce: "sdp-project-state-loop: API Error detected — spawning subagent to resume via
   sdp-project-run-prompt."
3. Spawn a subagent via the Agent tool with the following prompt:
   "You are an SDP workflow recovery subagent. An API error interrupted the previous session.
   Invoke `sdp-project-run-prompt` to resume from `[resolved_project]/sdp-docs/00_prompt.txt`. Do not
   take any other action." (Use the `[resolved_project]` value resolved in Step 1b — substitute
   the actual path, not the placeholder.)
4. After the subagent returns: report "sdp-project-state-loop: recovery subagent returned." Record
   `action = API_RECOVERY`, `reason = "API error detected"`. Proceed to Step 6 to record the
   fire, then stop.

**GENERATE:**
1. Announce: "sdp-project-state-loop: [reason from Step 4] — spawning subagent to generate next
   dispatch via sdp-project-create-prompt (project: [resolved_project])."
2. Spawn a subagent via the Agent tool with the following prompt:
   "You are an SDP workflow dispatch subagent. Invoke `sdp-project-create-prompt` to generate the
   next SDP dispatch prompt. The resolved project is `[resolved_project]` — pass
   `-workspaceRoot .\[resolved_project]` to `sdp-create-prompt.ps1` when the skill calls it.
   Do not take any other action."
3. After the subagent returns: report "sdp-project-state-loop: sdp-project-create-prompt subagent returned."
   `action` and `reason` are already recorded from Step 4. Proceed to Step 6 to record the
   fire, then stop.

**GATE_REPAIR:**
1. Announce: "sdp-project-state-loop: [reason from Step 4] — spawning subagent to repair the gate
   dispatch via sdp-project-coordinator (project: [resolved_project])."
2. Spawn a subagent via the Agent tool with the following prompt:
   "You are an SDP workflow dispatch subagent. Invoke `sdp-project-coordinator` for
   `[resolved_project]` to complete the pending phase-gate dispatch. Do not take any other
   action."
3. After the subagent returns: re-read `[resolved_project]/.sdp-workflow/state.json`
   (`last_session`, `phase_gate.status`). If `last_session` resolves to an existing session
   file, re-read its `Role:` and `Work Item:` lines using the same check as Step 4 sub-step c.
   - **Repaired** — the session file now matches `Role: GATE_REVIEWER` /
     `Work Item: [current_phase]`, or `phase_gate.status` is no longer `"pending"`/`"blocked"`
     because COORDINATOR advanced the phase or a different task took dispatch priority: report
     "sdp-project-state-loop: gate dispatch repaired by sdp-project-coordinator." Record `action = GATE_REPAIR`,
     `halted = false`. Proceed to Step 6 to record the fire, then stop — the next scheduled
     fire re-evaluates the sentinel against the corrected state.
   - **Not repaired** — the session file is still missing or still mismatched after
     `sdp-project-coordinator` returned: this is not a transient condition a retry will fix.
     Set `workflow_status = "halted"` and `halt_reason = "[current_phase] GATE_REVIEWER
     dispatch could not be repaired — sdp-project-coordinator returned without creating a matching
     session file. Manual investigation required, then run /sdp-project-coordinator to resume."` in
     `state.json`. Play the notification tone (non-blocking): run
     `./sdp-shared/scripts/sdp-tone.ps1 -trigger "halt.no_progress"` via the PowerShell tool.
     Invoke:
     `/sdp-create-banner icon=error row=0 row: Status | sdp-project-state-loop: halted — gate dispatch repair failed. Manual investigation required.`
     Record `action = GATE_REPAIR`, `halted = true`, `halt_reason` as above.
     Proceed to Step 6 to record the fire, then stop.

**EXECUTE:**
0. Record `status_before` = task `status` from Step 3.
1. Read `autoResolveHalt.evalCycleAttemptThreshold` from `SDP-Config.json`; if absent, use 2.
   Record as `haltThreshold`. Read `autoResolveHalt.pushOnEvalBlock`; if absent, use false.
   Record as `pushOnEvalBlock`.
2. Announce: "sdp-project-state-loop: sentinel valid ([active_work_item] / [status]) — spawning
   subagent to execute current dispatch via sdp-project-run-prompt."
3. Increment the attempt counter appropriate to the sentinel role:
   - If task `status` (from Step 3) is `WORK_COMPLETE` **AND `sentinel_role` is `REVIEWER`**:
     write `eval_cycle_attempts + 1` to the phase state file entry for `active_work_item`.
     Record the updated value as `eval_cycle_attempts`. Do **not** increment when
     `sentinel_role` is `COORDINATOR` (the COORDINATOR dispatch-of-REVIEWER fire also reads
     `WORK_COMPLETE` but is not a REVIEWER attempt) or when `sentinel_role` is unknown (fail
     safe — never increment on an untagged prompt).
   - If `sentinel_role` is `GATE_REVIEWER`: write
     `state.json.phase_gate.gate_review_attempts + 1` to `state.json`. Record the updated
     value as `gate_review_attempts`. Do **not** increment `eval_cycle_attempts` for
     GATE_REVIEWER fires — they are tracked separately.
   - For all other sentinel roles: no increment.
4. Spawn a subagent via the Agent tool with the following prompt:
   "You are an SDP workflow dispatch subagent. Invoke `sdp-project-run-prompt` to execute the current
   dispatch prompt at `[resolved_project]/sdp-docs/00_prompt.txt`. Do not take any other action."
5. After the subagent returns:
   - **Task dispatch (`sentinel_role` is WORKER, REVIEWER, or COORDINATOR):** Read the phase
     state file identified in Step 3 to confirm the new task status. Report: "sdp-project-state-loop:
     dispatch subagent returned — task status is now [status]." Record `status_after = [status]`.
     Do not parse the subagent's text output for the outcome.
   - **Gate dispatch (`sentinel_role` is GATE_REVIEWER):** Read `state.json.phase_gate.status`
     to confirm the gate verdict. Report: "sdp-project-state-loop: GATE_REVIEWER subagent returned —
     phase_gate.status is now [status]." Record `status_after = [status]`. Do not parse the
     subagent's text output.
6. Evaluate halt conditions:
   - **Task halt:** If new task status is still `WORK_COMPLETE` AND
     `eval_cycle_attempts - eval_cycles >= haltThreshold`: proceed to **Halt Evaluation** below
     (task variant).
   - **Gate halt:** If `sentinel_role` is `GATE_REVIEWER` AND
     `gate_review_attempts - gate_eval_cycles >= haltThreshold`: proceed to
     **Gate Halt Evaluation** below.
   - **Neither halt condition applies:** record `halted = false`. Proceed to Step 6 to record
     the fire, then stop.

**STOP** (any stop condition from Steps 2–3):
No subagent spawned. Reason already reported in the step that triggered the stop. `action` and
`reason` were already recorded at that step, which already redirects to Step 6 — this branch
exists only to document the STOP action for the Execute dispatch table; no further action is
taken here.

**Halt Evaluation** (entered from EXECUTE sub-step 6):

0. **Commit and push SDP infrastructure writes before analysis.**
   The phase state file (from Step 3) was modified in EXECUTE sub-step 3 (`eval_cycle_attempts`
   increment). `[resolved_project]/.sdp-workflow/state.json` may have been modified by a prior
   coordinator run. Both are workflow bookkeeping — not REVIEWER output. Commit and push them
   before the git analysis in sub-steps 1–4 so that analysis reflects only what the REVIEWER
   produced (or didn't produce), not state-loop/coordinator housekeeping.

   a. Run `git branch --show-current` to resolve `[branch]`.
   b. Run `git add [resolved_project]/.sdp-workflow/state.json [phase_state_file_path] [resolved_project]/.sdp-workflow/sessions/ [resolved_project]/sdp-docs/00_prompt.txt [resolved_project]/.sdp-workflow/temp/ .sdp-solution-workflow/logging/loop-logs/`
      (where `[phase_state_file_path]` is the path read in Step 3). `[resolved_project]/sdp-docs/00_prompt.txt` is
      included because a prior COORDINATOR-dispatch fire may have rewritten it and left it
      uncommitted — staging it here prevents it from being misread as drift in sub-steps 1–4.
      `[resolved_project]/.sdp-workflow/temp/` and `.sdp-solution-workflow/logging/loop-logs/`
      are included for the same reason: `sdp-create-prompt.ps1` writes a new temp/tracking
      file on every GENERATE fire and this skill appends to the current dated
      `loop-metrics-*.jsonl` file on every fire — both are intended to be `.gitignore`d per the
      workspace setup template, but a
      workspace whose `.gitignore` predates that convention (or where these paths were
      already tracked before it was added) will show them as real diffs; staging them here
      prevents pure automation churn from being misread as drift in sub-steps 1–4.
   c. Run `git diff --cached --quiet`. If exit code is non-zero (staged changes exist):
      - Commit: `git commit -m "chore(sdp): project-state-loop infrastructure commit — [active_work_item]"`
      - Push: `git push origin [branch]`
      - On push success: append to the `auto_actions` array in `state.json`:
        `{ "timestamp": "[ISO timestamp]", "trigger": "halt-eval pre-commit",
        "action": "infrastructure commit+push", "task": "[active_work_item]",
        "outcome": "success" }`
      - On push failure: set `workflow_status = "halted"` and `halt_reason =
        "[active_work_item] REVIEWER blocked [eval_cycle_attempts]× — infrastructure push
        failed: [error]. Push manually and run /sdp-project-coordinator to resume."` in `state.json`.
        Play the notification tone (non-blocking — ignore any failure and continue): run
        `./sdp-shared/scripts/sdp-tone.ps1 -trigger "halt.no_progress"` via the PowerShell tool.
        Invoke `/sdp-create-banner icon=error row=0 row: Status | sdp-project-state-loop: halted —
        infrastructure push failed: [error]. Push manually and run /sdp-project-coordinator to
        resume.` Record `halted = true`,
        `halt_reason = "[active_work_item] infrastructure push failed: [error]"`. Proceed to
        Step 6 to record the fire, then stop.
   d. If `git diff --cached --quiet` exits 0 (nothing staged): skip commit and push.
   e. Proceed to sub-step 1.

1. Run `git branch --show-current` to get `branch`.
2. Run `git log origin/[branch]..HEAD --oneline` to check for unpushed commits.
3. Run `git status --porcelain` to check for uncommitted changes. Before classifying, exclude
   SDP housekeeping paths from the output: `[resolved_project]/.sdp-workflow/state.json`
   (re-dirtied by the Step 0c `auto_actions` append on push success), the phase state file
   read in Step 3, anything under `[resolved_project]/.sdp-workflow/sessions/`,
   `[resolved_project]/sdp-docs/00_prompt.txt`, anything under
   `[resolved_project]/.sdp-workflow/temp/`, and anything under
   `.sdp-solution-workflow/logging/loop-logs/`.
   These are workflow bookkeeping written by the loop, COORDINATOR, or `sdp-project-create-prompt` —
   not REVIEWER output or implementation drift. Treat only the remaining (non-housekeeping)
   lines as uncommitted changes.
4. Determine cause:
   - If git log output is non-empty: cause = **UNPUSHED_COMMITS**; record line count as `commitCount`.
   - Else if the filtered git status output (housekeeping paths excluded) is non-empty: cause = **UNCOMMITTED_CHANGES**.
   - Else: cause = **UNKNOWN**.
5. Act based on cause and `pushOnEvalBlock`:

   **UNPUSHED_COMMITS and `pushOnEvalBlock` is true:**
   a. Run `git push origin [branch]`.
   b. If push succeeds: write `eval_cycle_attempts = eval_cycles` to the phase state file entry
      for `active_work_item` (reset the counter). Append to the `auto_actions` array in
      `state.json`: `{ "timestamp": "[ISO timestamp]", "trigger": "eval_cycle_attempts >= [haltThreshold]",
      "action": "git push", "task": "[active_work_item]", "commits_pushed": [commitCount], "outcome": "success" }`.
      Invoke:
      `/sdp-create-banner icon=success row=0 row: Status | sdp-project-state-loop: auto-pushed [commitCount] commits for [active_work_item] — eval_cycle_attempts reset. Loop continuing.`
      Record `halted = false`,
      `reason = "auto-pushed [commitCount] commits, eval_cycle_attempts reset"`. Proceed to
      Step 6 to record the fire, then stop this fire (the loop's next scheduled fire continues
      normally).
   c. If push fails: set `workflow_status = "halted"` and `halt_reason =
      "[active_work_item] REVIEWER blocked [eval_cycle_attempts]× — git push failed: [error].
      Push manually and run /sdp-project-coordinator to resume."` in `state.json`.
      Play the notification tone (non-blocking — ignore any failure and continue): run
      `./sdp-shared/scripts/sdp-tone.ps1 -trigger "halt.no_progress"` via the PowerShell tool.
      Invoke:
      `/sdp-create-banner icon=error row=0 row: Status | sdp-project-state-loop: halted — git push failed: [error]. Push manually and run /sdp-project-coordinator to resume.`
      Record `halted = true`, `halt_reason = "[active_work_item]
      git push failed: [error]"`. Proceed to Step 6 to record the fire, then stop.

   **UNPUSHED_COMMITS and `pushOnEvalBlock` is false:**
   a. Set `workflow_status = "halted"` and `halt_reason = "[active_work_item] REVIEWER blocked
      [eval_cycle_attempts]× — [commitCount] unpushed commits on [branch]. Run
      git push origin [branch] to unblock."` in `state.json`.
   b. Play the notification tone (non-blocking — ignore any failure and continue): run
      `./sdp-shared/scripts/sdp-tone.ps1 -trigger "halt.no_progress"` via the PowerShell tool.
      Invoke:
      `/sdp-create-banner icon=error row=0 row: Status | sdp-project-state-loop: halted — REVIEWER blocked [eval_cycle_attempts]× — [commitCount] unpushed commits detected. Run git push origin [branch] to unblock, then /sdp-project-coordinator to resume.`
      Record `halted = true`, `halt_reason =
      "[active_work_item] [commitCount] unpushed commits on [branch]"`. Proceed to Step 6 to
      record the fire, then stop.

   **UNCOMMITTED_CHANGES:**
   a. Set `workflow_status = "halted"` and `halt_reason = "[active_work_item] REVIEWER blocked
      [eval_cycle_attempts]× — uncommitted changes in working tree. Commit and push, then run
      /sdp-project-coordinator to resume."` in `state.json`.
   b. Play the notification tone (non-blocking — ignore any failure and continue): run
      `./sdp-shared/scripts/sdp-tone.ps1 -trigger "halt.no_progress"` via the PowerShell tool.
      Invoke:
      `/sdp-create-banner icon=error row=0 row: Status | sdp-project-state-loop: halted — REVIEWER blocked [eval_cycle_attempts]× — uncommitted changes detected. Commit and push, then run /sdp-project-coordinator to resume.`
      Record `halted = true`, `halt_reason = "[active_work_item] uncommitted changes in
      working tree"`. Proceed to Step 6 to record the fire, then stop.

   **UNKNOWN:**
   a. Set `workflow_status = "halted"` and `halt_reason = "[active_work_item] REVIEWER blocked
      [eval_cycle_attempts]× — cause unknown (clean tree, nothing to push). Human review
      required."` in `state.json`.
   b. Play the notification tone (non-blocking — ignore any failure and continue): run
      `./sdp-shared/scripts/sdp-tone.ps1 -trigger "halt.no_progress"` via the PowerShell tool.
      Invoke:
      `/sdp-create-banner icon=error row=0 row: Status | sdp-project-state-loop: halted — REVIEWER blocked [eval_cycle_attempts]× — cause unknown. Human review required before loop can continue.`
      Record `halted = true`,
      `halt_reason = "[active_work_item] cause unknown — clean tree, nothing to push"`.
      Proceed to Step 6 to record the fire, then stop.

**Gate Halt Evaluation** (entered from EXECUTE sub-step 6, gate halt branch):

Follows the same sequence as the task Halt Evaluation, substituting gate-specific field names
and messages throughout.

0. **Commit and push SDP infrastructure writes before analysis.**
   `[resolved_project]/.sdp-workflow/state.json` was modified in EXECUTE sub-step 3
   (`gate_review_attempts` increment). Commit and push it before the git analysis so that
   analysis reflects only what GATE_REVIEWER produced (or didn't produce), not state-loop
   housekeeping.

   a. Run `git branch --show-current` to resolve `[branch]`.
   b. Run `git add [resolved_project]/.sdp-workflow/state.json [resolved_project]/.sdp-workflow/sessions/ [resolved_project]/sdp-docs/00_prompt.txt [resolved_project]/.sdp-workflow/temp/ .sdp-solution-workflow/logging/loop-logs/`.
      The last two paths are automation churn from `sdp-create-prompt.ps1` and this skill's
      own fire log — see the task-variant Halt Evaluation sub-step 0b for why they're staged
      here rather than left to be misread as drift.
   c. Run `git diff --cached --quiet`. If exit code is non-zero (staged changes exist):
      - Commit: `git commit -m "chore(sdp): project-state-loop gate infrastructure commit — [current_phase]"`
      - Push: `git push origin [branch]`
      - On push success: append to `auto_actions` in `state.json`:
        `{ "timestamp": "[ISO timestamp]", "trigger": "gate-halt-eval pre-commit",
        "action": "infrastructure commit+push", "phase": "[current_phase]", "outcome": "success" }`
      - On push failure: set `workflow_status = "halted"` and `halt_reason =
        "[current_phase] GATE_REVIEWER blocked [gate_review_attempts]× — infrastructure push
        failed: [error]. Push manually and run /sdp-project-coordinator to resume."` in `state.json`.
        Play the notification tone (non-blocking): run
        `./sdp-shared/scripts/sdp-tone.ps1 -trigger "halt.no_progress"` via the PowerShell tool.
        Invoke `/sdp-create-banner icon=error row=0 row: Status | sdp-project-state-loop: halted —
        gate infrastructure push failed: [error].` Record
        `halted = true`, `halt_reason = "[current_phase] gate infrastructure push failed:
        [error]"`. Proceed to Step 6 to record the fire, then stop.
   d. If nothing staged: skip commit and push.
   e. Proceed to sub-step 1.

1. Run `git branch --show-current` to get `branch`.
2. Run `git log origin/[branch]..HEAD --oneline` to check for unpushed commits.
3. Run `git status --porcelain`. Exclude SDP housekeeping paths:
   `[resolved_project]/.sdp-workflow/state.json`, anything under
   `[resolved_project]/.sdp-workflow/sessions/`,
   `[resolved_project]/sdp-docs/00_prompt.txt`, anything under
   `[resolved_project]/.sdp-workflow/temp/`, and anything under
   `.sdp-solution-workflow/logging/loop-logs/`.
   Treat only remaining lines as uncommitted changes.
4. Determine cause: UNPUSHED_COMMITS, UNCOMMITTED_CHANGES, or UNKNOWN (same logic as task
   Halt Evaluation).
5. Act based on cause and `pushOnEvalBlock`:

   **UNPUSHED_COMMITS and `pushOnEvalBlock` is true:**
   a. Run `git push origin [branch]`.
   b. If push succeeds: write `phase_gate.gate_review_attempts = phase_gate.gate_eval_cycles`
      to `state.json` (reset the counter). Append to `auto_actions`:
      `{ "timestamp": "[ISO timestamp]", "trigger": "gate_review_attempts >= [haltThreshold]",
      "action": "git push", "phase": "[current_phase]", "commits_pushed": [commitCount],
      "outcome": "success" }`. Invoke `/sdp-create-banner icon=success row=0 row: Status |
      sdp-project-state-loop: auto-pushed [commitCount] commits for phase [current_phase] —
      gate_review_attempts reset. Loop continuing.` Record
      `halted = false`, `reason = "auto-pushed [commitCount] commits, gate_review_attempts
      reset"`. Proceed to Step 6 to record the fire, then stop this fire (the loop's next
      scheduled fire continues normally).
   c. If push fails: set `workflow_status = "halted"` and `halt_reason =
      "[current_phase] GATE_REVIEWER blocked [gate_review_attempts]× — git push failed:
      [error]. Push manually and run /sdp-project-coordinator to resume."` in `state.json`.
      Play the notification tone (non-blocking): run
      `./sdp-shared/scripts/sdp-tone.ps1 -trigger "halt.no_progress"` via the PowerShell tool.
      Invoke:
      `/sdp-create-banner icon=error row=0 row: Status | sdp-project-state-loop: halted — gate push failed: [error].`
      Record `halted = true`,
      `halt_reason = "[current_phase] gate push failed: [error]"`. Proceed to Step 6 to record
      the fire, then stop.

   **UNPUSHED_COMMITS and `pushOnEvalBlock` is false:**
   a. Set `workflow_status = "halted"` and `halt_reason = "[current_phase] GATE_REVIEWER
      blocked [gate_review_attempts]× — [commitCount] unpushed commits on [branch]. Run
      git push origin [branch] to unblock."` in `state.json`.
   b. Play the notification tone (non-blocking): run
      `./sdp-shared/scripts/sdp-tone.ps1 -trigger "halt.no_progress"` via the PowerShell tool.
      Invoke:
      `/sdp-create-banner icon=error row=0 row: Status | sdp-project-state-loop: halted — GATE_REVIEWER blocked [gate_review_attempts]× — [commitCount] unpushed commits. Run git push origin [branch], then /sdp-project-coordinator.`
      Record `halted = true`, `halt_reason = "[current_phase]
      [commitCount] unpushed commits on [branch]"`. Proceed to Step 6 to record the fire, then
      stop.

   **UNCOMMITTED_CHANGES:**
   a. Set `workflow_status = "halted"` and `halt_reason = "[current_phase] GATE_REVIEWER
      blocked [gate_review_attempts]× — uncommitted changes in working tree. Commit and push,
      then run /sdp-project-coordinator to resume."` in `state.json`.
   b. Play the notification tone (non-blocking): run
      `./sdp-shared/scripts/sdp-tone.ps1 -trigger "halt.no_progress"` via the PowerShell tool.
      Invoke:
      `/sdp-create-banner icon=error row=0 row: Status | sdp-project-state-loop: halted — GATE_REVIEWER blocked [gate_review_attempts]× — uncommitted changes. Commit and push, then run /sdp-project-coordinator.`
      Record
      `halted = true`, `halt_reason = "[current_phase] uncommitted changes in working tree"`.
      Proceed to Step 6 to record the fire, then stop.

   **UNKNOWN:**
   a. Set `workflow_status = "halted"` and `halt_reason = "[current_phase] GATE_REVIEWER
      blocked [gate_review_attempts]× — cause unknown (clean tree, nothing to push). Human
      review required."` in `state.json`.
   b. Play the notification tone (non-blocking): run
      `./sdp-shared/scripts/sdp-tone.ps1 -trigger "halt.no_progress"` via the PowerShell tool.
      Invoke:
      `/sdp-create-banner icon=error row=0 row: Status | sdp-project-state-loop: halted — GATE_REVIEWER blocked [gate_review_attempts]× — cause unknown. Human review required.`
      Record `halted = true`, `halt_reason =
      "[current_phase] cause unknown — clean tree, nothing to push"`. Proceed to Step 6 to
      record the fire, then stop.

### Step 6: Record Fire Metrics

Append exactly one JSON line to today's
`.sdp-solution-workflow/logging/loop-logs/loop-metrics-[yyyyMMdd].jsonl` file at the solution
root (solution-level — shared across every project this loop dispatches, not per-project)
recording the outcome of this fire, then stop. This step runs for every action type
(API_RECOVERY, GENERATE, EXECUTE, STOP) and is the only point in this skill that writes to this
file. The file rotates purely by calendar date, independent of loop start/stop or any other
workflow action — there is no "current run" to look up, just today's date.

1. Assemble the JSON object using the values recorded earlier in this fire. Fields not
   applicable to this action's path are written as `null`:
   ```json
   {"timestamp":"[ISO 8601 timestamp, e.g. via Get-Date -Format o]","project":"[resolved_project]","action":"[API_RECOVERY|GENERATE|EXECUTE|GATE_REPAIR|STOP]","work_item":"[active_work_item or null]","role":"[sentinel_role or null]","reason":"[reason recorded for this fire, or null]","status_before":"[status_before or null]","status_after":"[status_after or null]","halted":[true|false],"halt_reason":"[halt_reason or null]"}
   ```
2. Append the line via the PowerShell tool, targeting today's file by name — do not overwrite:
   ```
   Add-Content -Path ".sdp-solution-workflow/logging/loop-logs/loop-metrics-$(Get-Date -Format 'yyyyMMdd').jsonl" -Value '[the JSON line from
   sub-step 1, as a single-line compact JSON string]' -Encoding utf8
   ```
   `Add-Content` creates the file if it does not yet exist (first fire of the day) and appends a
   line if it does — no read-before-write or existence check is required.
3. If the `Add-Content` call fails for any reason (e.g., path not found, permission denied):
   ignore the failure and continue — a metrics write failure must never block or halt the loop.
   Do not retry.
4. **If `halted` is `true` for this fire:** also record it in the semantic workflow-log stream
   (non-blocking — ignore any failure and continue): run
   `./sdp-shared/scripts/sdp-workflow-log.ps1 -trigger "loop.stuck_halt" -role "STATE_LOOP"
   -workItem "[work_item, or empty for a gate halt]" -phase "[current_phase, gate halts only]"
   -outcome "HALTED" -reason "[halt_reason]"` via the PowerShell tool. This is the single choke
   point for every halt branch in both Halt Evaluation variants (task and gate) — every one of
   them sets `halted = true` and reaches this step, so no individual halt branch needs its own
   separate log call.
5. Stop. This is the final step of the fire regardless of which action was taken.

## Constraints

- Do not invoke any SDP skill directly — all dispatch is via the Agent tool (subagent).
- `GATE_REPAIR` never increments `gate_review_attempts` — it is dispatch-file repair, not a
  review attempt; only `EXECUTE` increments it.
- `GATE_REPAIR` spawns `sdp-project-coordinator`, not `sdp-project-create-prompt`. Re-running
  `sdp-project-create-prompt` here would regenerate the identical unrepaired sentinel without ever
  creating the missing session file, since `sdp-project-create-prompt` is explicitly forbidden from
  writing session files or `state.json`.
- This skill writes only to: (1) the active phase state file to update `eval_cycle_attempts`
  (task dispatch); (2) `[resolved_project]/.sdp-workflow/state.json` to update
  `phase_gate.gate_review_attempts` (gate dispatch), or when a halt condition is reached or an
  auto-push action is logged; (3) today's
  `.sdp-solution-workflow/logging/loop-logs/loop-metrics-*.jsonl` file at the solution root
  (Step 6, every fire — append-only, one line per fire); (4) today's
  `.sdp-solution-workflow/logging/workflow-logs/workflow-log-*.jsonl` file, only when `halted`
  is `true` (Step 6 sub-step 4, via `sdp-workflow-log.ps1`). It does not modify any other file.
- The Step 6 metrics write is always the last action of a fire, runs for every action type, and
  is strictly append-only — never truncate, rewrite, or reorder existing lines in the target
  `loop-metrics-*.jsonl` file. A write failure there is non-blocking (see Step 6 sub-step 3) and
  must never itself trigger a halt.
- The context check in Step 1 uses the agent's knowledge of the current conversation only —
  no file tools. Do not search files for `API Error: `.
- Scan only the most recent 10 lines for API error detection — do not trigger API_RECOVERY
  from `API Error: ` found in earlier conversation turns, documents, or planning text.
- Read only the first line of `[resolved_project]/sdp-docs/00_prompt.txt` in Steps 1b and
  4 — do not read the full file.
- Outcome detection after EXECUTE: read the phase state file to determine the new task status.
  Do not parse subagent text output for the outcome.
- Never leave `[resolved_project]` unresolved because the sentinel's `projects=` field is
  absent — fall back through Step 1b's resolution order; only default to `.` (dot, workspace
  root) once every fallback level is exhausted, preserving backward-compatible single-project
  behavior.
- Never treat a GENERATE or STOP outcome as a failure requiring remediation — both are correct,
  complete fire outcomes on their own terms.
- STOP means the workflow requires human input before the loop can advance; never STOP without
  reporting the reason explicitly.
- Never begin Halt Evaluation's git-state analysis (task or gate variant, sub-steps 1+) before
  completing sub-step 0's infrastructure commit/push — sub-step 0 must run first so the
  analysis reflects only REVIEWER/GATE_REVIEWER output, not state-loop or coordinator
  housekeeping.
- This skill issues non-blocking audible tone calls (`./sdp-shared/scripts/sdp-tone.ps1
  -trigger ...`) at the API-error point and at each halt/STOP point. These are system calls
  (audible notification), not file writes; any failure is ignored so they never block the loop.

## Outputs

- **API_RECOVERY:** Subagent spawned to invoke `sdp-project-run-prompt`; outcome reported on return.
- **GENERATE:** Subagent spawned to invoke `sdp-project-create-prompt`; reason for generation reported.
- **EXECUTE:** Subagent spawned to invoke `sdp-project-run-prompt`; new task status read from phase
  state file after return. If a halt condition is detected post-return, `state.json` is updated
  with `workflow_status = "halted"` and the loop stops. If `pushOnEvalBlock` is true and an
  auto-push resolves the block, the action is logged to `state.json` and the loop continues.
- **GATE_REPAIR:** Subagent spawned to invoke `sdp-project-coordinator`; session-file match
  re-verified on return. Self-heals into a correct GATE_REVIEWER dispatch, or halts
  immediately if the repair did not take — no repeated silent retries.
- **STOP:** Reason reported; no subagent spawned.
- **Every fire (Step 6):** One JSON line appended to today's
  `.sdp-solution-workflow/logging/loop-logs/loop-metrics-*.jsonl` file at the solution root
  recording `timestamp`, `project`, `action`, `work_item`, `role`, `reason`, `status_before`,
  `status_after`, `halted`, and `halt_reason`.
