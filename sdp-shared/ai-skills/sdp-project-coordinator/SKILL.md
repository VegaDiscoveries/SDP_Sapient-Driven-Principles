## Purpose

Execute a COORDINATOR session for a **single project**: verify preconditions, read workflow
state, determine the next valid dispatch target (WORKER for PENDING tasks, REVIEWER for
WORK_COMPLETE tasks), write the session dispatch file, update state.json, and notify the user.
A COORDINATOR session never touches implementation files or performs work.

**Scope note:** `sdp-project-coordinator` is retained for single-project work only. It does not manage
cross-project tasks. Cross-project orchestration is handled by `sdp-solution-coordinator`.

## Inputs

All paths below are relative to `[resolved_project]` (resolved in Step 1 item 1 below).

- `[resolved_project]/.sdp-workflow/state.json` — required; must exist
- `[resolved_project]/.sdp-workflow/registry.md` — required; phase list, dependency list, and
  the authoritative Phase File column (the source of every phase's document path — never
  reconstruct a phase's file path from `current_phase` or a `[doc_name]_Phases/` convention)
- Phase state file — for each active phase, derived from that phase's registry.md Phase File
  value by replacing its trailing `.md` with `_state.json`; required for each active phase;
  task status source
- `[resolved_project]/.sdp-workflow/sessions/` — required; directory where session dispatch files are written

## Procedure

### Step 1: Check Preconditions

1. **PROJECT RESOLUTION** — Resolve the target project using the priority order below. Use
   the first level that yields a result; do not check subsequent levels.

   **Level 0 — Invocation argument (user or agent):**
   If a project path was passed as an argument on invocation, use it as `[resolved_project]`.
   Read `SDP-Solution.json` to validate the value against the `projects` array. If it does not
   match any registered entry: reject by invoking
   `/sdp-create-banner icon=error row=0 row: Status | Invocation argument '[value]' does not match any project registered in SDP-Solution.json. Available: [list]. Correct the argument and retry.`
   Do not check subsequent levels.

   **Level 1 — Dispatch context (authoritative for formally dispatched subagents):**
   Read the current session file (if one was provided as the opening prompt). If it contains a
   `Project:` field, use that value as `[resolved_project]`. This value is written at dispatch
   time by the coordinator and is locked for this session's lifetime.

   **Level 2 — Physical path extraction (deterministic fallback, no I/O required):**
   If no `Project:` field is present in the session file, examine the path of the file being
   processed (e.g., the session file path, or the path of a state file being read). If the path
   contains an `sdp-project_*` segment, that segment is `[resolved_project]`
   (e.g., `sdp-project_VirtualCoinFolio.API/.sdp-workflow/sessions/session-042.md`
   → `[resolved_project]` = `sdp-project_VirtualCoinFolio.API`).
   If the path contains no `sdp-project_*` segment, this is a solution-level file; no single
   project applies.

   **Level 3 — `SDP-Solution.json` `last_active_projects` (user-direct invocations only):**
   Used only when this skill was invoked directly by the user with no session file or sentinel
   context. Read `last_active_projects` from `SDP-Solution.json` at the solution root; use the
   first entry as `[resolved_project]`. If `last_active_projects` is empty or absent, proceed
   to Level 4.

   If `SDP-Solution.json` is absent at any level that requires it: halt by invoking
   `/sdp-create-banner icon=error row=0 row: Status | SDP-Solution.json not found at solution root. Run /sdp-workspace-setup to create it before proceeding.`

   **Level 4 — `SDP-Solution.json` `projects` (single-project auto-resolve or user selection):**
   Reached only when `last_active_projects` is empty or absent. Read the `projects` array from
   `SDP-Solution.json` (already read in Level 3).
   - If `projects` contains exactly 1 entry: use it as `[resolved_project]`.
   - If `projects` contains 2 or more entries: list the available projects to the user and
     prompt them to select one. Wait for the user's response before continuing.
   - If `projects` is empty or absent: halt by invoking
     `/sdp-create-banner icon=error row=0 row: Status | No projects registered in SDP-Solution.json — register at least one project before proceeding.`

   Once resolved, all state/session file paths in subsequent steps are built under
   `[resolved_project]/`. For single-project workspaces where `last_active_projects` is `["."]`,
   `.\.\[path]` resolves to `.\[path]` — identical to current single-project behavior.

2. **PREFLIGHT CHECK** — Run `./sdp-shared/scripts/sdp-preflight.ps1 -workspaceRoot .\[resolved_project]`
   via the PowerShell tool.
   This one call runs every deterministic precondition from the `SDP-Workspace-Setup.json`
   manifest: the GPG presence/version match, the sdp- skill-pair existence (both Level 1 and
   Level 2), the `sdp-tone` Level 1 present / Level 2 absent invariant, the `sdp-tone.ps1` /
   `sdp-create-prompt.ps1` / `sdp-github.ps1` scripts, `SDP-Tones.json`, and the
   scaffold/config/document-list checks. Read the single-line JSON envelope it emits:
   - If `ok` is `true`: preconditions pass — continue to item 3. (The script advances its own
     per-tier staleness timestamps in `[resolved_project]/.sdp-workflow/state.json`; it makes no
     other state writes and never mutates `workflow_status`.)
   - If `ok` is `false`: halt per the Halt Behavior Contract — set `workflow_status` to
     `"halted"` in `[resolved_project]/.sdp-workflow/state.json` and `halt_reason` to a one-line
     description citing the `failures` array from the envelope (or the `error` field on an
     operational error such as a missing/unparseable manifest, which the script reports with exit
     code 1). Play the notification tone (non-blocking — ignore any failure and continue): run
     `./sdp-shared/scripts/sdp-tone.ps1 -trigger "halt.generic"` via the PowerShell tool. Also
     record the halt (non-blocking — ignore any failure and continue): run
     `./sdp-shared/scripts/sdp-workflow-log.ps1 -trigger "halt.generic" -role "COORDINATOR"
     -outcome "HALTED" -reason "Preflight failed: [failures]"` via the PowerShell tool. Then
     notify the user by invoking
     `/sdp-create-banner icon=error row=0 row: Status | Halted — preflight failed: [failures]. Restore the missing/invalid items and run COORDINATOR to resume.`,
     and terminate.

   To force a full re-check (bypassing the staleness timers — e.g. when re-running COORDINATOR
   immediately after clearing a halt), pass `-Force`. The canonical check inventory lives in
   `[resolved_project]/SDP-Workspace-Setup.json` as data; do not re-enumerate it here.
3. **SUPERPOWERS CHECK** — Verify Superpowers plugin is installed by running `/plugin list`.
   If missing: note it in the upcoming session dispatch file and continue — missing Superpowers
   does not block dispatch, but WORKER/REVIEWER must be instructed to apply equivalent
   discipline manually. (Not script-able: `/plugin list` is a harness command, not a filesystem
   fact — it stays an agent step and is non-blocking.)
   Note: "Superpowers" here refers to the SP plugin (Jesse Vincent), not to SDP skills.
4. **Halt check** — Read `workflow_status` from `[resolved_project]/.sdp-workflow/state.json`.
   If `"halted"`: invoke `/sdp-create-banner icon=error row=0 row: Status | Halted —
   [halt_reason]. Resolve this condition and run COORDINATOR to resume.`, do not proceed to any
   subsequent step, and terminate.
5. **Doc Review check** — For each phase state file that is active or in-progress, check
   whether the `sdp_doc_review` key is present and `sdp_doc_review.completed` is `true`. If
   any staged state file entry is missing the key or has `completed: false`:
   - Run `sdp-project-doc-review` for each unreviewed doc, in document-list order, before dispatching
     any task
   - All pending doc reviews must complete before any staged doc's work is dispatched — even
     if other staged docs are already reviewed
   - Do not proceed to Step 2 until all staged docs have a `completed: true` entry
   This check applies to the active and in-progress phases only. Completed or future phases
   are not checked.
6. **BRAINSTORMING CHECK** — If this session is for Phase 1 (Concept) or Phase 3 (Expanded
   Concept) and the session purpose includes planning, concept development, or structuring a
   new phase document: if Superpowers is installed, invoke `/brainstorming` before proceeding
   to Step 2. Apply the brainstorming capture rule — all output, every decision, constraint,
   and design choice, must be transcribed into the phase document before this session closes.
   Brainstorming output that exists only in chat history is not part of the audit trail.

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

### Step 2: Read Workflow State

1. Read `[resolved_project]/.sdp-workflow/state.json` — note `current_phase`,
   `active_work_item`, `last_session`, and `orchestration_mode`.
2. Read `[resolved_project]/.sdp-workflow/registry.md` — note phase list, status of each
   phase, the Depends On column for each phase, and the Phase File column for each phase (the
   authoritative document path — this is what populates `active_phase_file` in Step 6 and what
   every phase-document reference in this skill is sourced from).
3. For each active or in-progress phase: resolve its phase document path from the Phase File
   column read above — not a constructed `[doc_name]_Phases/[phase].md` convention, which does
   not match every project's actual layout. Derive that phase's state file by replacing the
   Phase File path's trailing `.md` with `_state.json`, and read it. Reading the phase document
   (the `.md`) itself is not required at this step — task status is visible from state files
   alone.

### Step 3: Verify State Consistency

1. For any task that has checkbox `[x]` in its phase file but `status: "PENDING"` in its
   state file: flag the discrepancy to the user before dispatching. Do not silently correct
   it — it indicates a session that updated one artifact but not the other. Pause and wait
   for user instruction before continuing.

### Step 4: Find Next Actionable Task

1. REJECTED tasks take dispatch priority over PENDING tasks. Identify any REJECTED task first.
2. If no REJECTED tasks: find the first PENDING task in the current phase.
3. For any candidate task: check its phase's Depends On column in `registry.md`. Do not
   dispatch if any listed dependency phase is not `[x]` complete. If blocked by a dependency,
   report the dependency to the user and terminate.
4. If the active task has status `WORK_COMPLETE`: the next dispatch target is REVIEWER, not
   WORKER.
5. If no REJECTED or PENDING tasks remain and all tasks in the current phase are VERIFIED:
   read `phase_gate` from `state.json` (if absent, treat as
   `{ "status": "pending", "gate_review_attempts": 0, "gate_eval_cycles": 0 }`).
   Branch on `phase_gate.status`:
   - **`"pending"`:** First gate — dispatch GATE_REVIEWER. Proceed to Step 5 (gate dispatch
     variant) to write the session file and 00_prompt.txt.
   - **`"blocked"`:** `phase_gate.status` reads `"blocked"` for one of two distinct reasons — a
     real GATE_REVIEWER verdict returned GATE_BLOCKED, or the Phase Readiness Regression Procedure
     force-set it on a target/intermediate phase to require a fresh gate before that phase may
     advance again (sub-step 5.c below; bootstrap doc's Phase Readiness Regression Procedure item
     3). Disambiguate using `gate_review_attempts` — never blockquote content. Append-Only
     Discipline means a stale blockquote from an earlier, unrelated block can sit in the phase
     document indefinitely; its mere presence proves nothing about *this* gate cycle.

     **Re-gate (`gate_review_attempts == 0`):** No GATE_REVIEWER has fired against this phase
     since `"blocked"` was most recently set. A real GATE_BLOCKED verdict always leaves
     `gate_review_attempts >= 1` — the counter increments the moment GATE_REVIEWER dispatches,
     owned solely by `sdp-project-state-loop` (its Step 4 sub-step c). So `gate_review_attempts ==
     0` together with `status == "blocked"` can only mean the Regression Procedure just force-set
     it and this phase's fresh WORKER → REVIEWER cycle has now reached all-VERIFIED — the
     precondition already confirmed by this step's opening condition. Treat this exactly like the
     `"pending"` branch: dispatch GATE_REVIEWER, proceed to Step 5 (gate dispatch variant) to write
     the session file and 00_prompt.txt, including the `Re-Gate Trigger:` field (see Gate Dispatch
     Variant below). Do not consult the phase document's blockquote history for this branch — it
     is irrelevant to the decision.

     **Real prior block (`gate_review_attempts >= 1`):** First check whether the GATE_BLOCKED
     blockquote in the phase document contains a `**Remediation Proposals:**` heading (the
     Phase-Readiness-specific verdict format — see the bootstrap doc's Phase 7 entry and
     `sdp-project-gate-review/SKILL.md`). This heading only appears when `current_phase` contains the
     substring "Phase Readiness" — a normal phase's GATE_BLOCKED verdict never has it.

     **Regression halt (Remediation Proposals present):** Halt per the Halt Behavior Contract:
     set `workflow_status = "halted"` and `halt_reason = "Phase Readiness gate found a
     traceability gap — read the Remediation Proposals in the phase document and select one
     before resuming."` Surface all numbered proposals (each with its `Target Phase:` value) to
     the user verbatim. Then invoke
     `/sdp-create-banner icon=error row=0 row: Status | Halted — Phase Readiness gate blocked with remediation proposals. Select one and run COORDINATOR to resume.`
     Terminate. Do not pick a proposal automatically — this is always a human decision.

     **On the next COORDINATOR invocation, once the user has stated their chosen proposal
     (passed as invocation context or stated directly in the resuming session):**
     a. Read the chosen proposal's `Target Phase:` value from the phase document's Remediation
        Proposals list — this is the exact `registry.md` Phase column value to regress to.
     b. Set `current_phase` in `state.json` to that value.
     c. Set `phase_gate.status` to `"blocked"` for that target phase (forcing it to earn a fresh
        gate before advancing again), and reset `phase_gate.gate_review_attempts` to 0.
     d. Reset `eval_cycle_attempts` to 0 with two different scopes (the scoped-reset rule —
        bootstrap doc's Phase Readiness Regression Bookkeeping):
        - **Intermediate phases** — every phase strictly between the target phase and the
          Phase-Readiness phase, in `registry.md` row order (exclusive of both ends): reset
          `eval_cycle_attempts` to 0 for *every* task in each such phase's state file,
          unconditionally. These phases always get a genuinely fresh, full WORKER → REVIEWER →
          gate cycle per the bootstrap doc's Phase Readiness Regression Procedure — no
          intermediate phase is skipped, so every task in them re-executes.
        - **The target phase itself** — reset `eval_cycle_attempts` to 0 *only* for the task(s)
          the chosen remediation actually touches. Judge this from the remediation's own one-line
          scope description in the Gate Verdict blockquote: a "full re-phase rework" remediation
          touches every task in the target phase; a "small targeted edit" remediation touches only
          the specific task(s) it names or implies. Tasks in the target phase that the remediation
          does not touch keep their existing `eval_cycle_attempts` unchanged.
        Do not add any `eval_cycle_attempts` reset for the Phase-Readiness phase itself in this
        step, nor for any phase outside the target-through-Phase-Readiness span.
     e. Append one entry to `state.json`'s `phase_readiness.regressions[]` array —
        `{ "target_phase": "[value]", "date": "[today's ISO date]", "chosen_remediation":
        "[user's selection summary]", "justification": "[from the proposal]" }` — and increment
        `phase_readiness.regression_count` by 1. If the `phase_readiness` block is absent from
        `state.json` (a project scaffolded before this version), initialize it as
        `{ "regression_count": 0, "regressions": [] }` first, then apply the increment/append.
     f. Proceed to normal Step 4 dispatch logic for the new `current_phase` (the target phase is
        now PENDING/REJECTED-eligible for a fresh WORKER dispatch, same as any other phase).

     **Normal halt (no Remediation Proposals heading — existing behavior, unchanged):** Halt per
     the Halt Behavior Contract: set `workflow_status = "halted"` in `state.json` and
     `halt_reason = "Phase [current_phase] gate is BLOCKED — read the GATE_BLOCKED blockquote in
     the phase document and resolve flagged issues before re-dispatching."` Surface the prior
     GATE_BLOCKED blockquote content to the user. Then invoke
     `/sdp-create-banner icon=error row=0 row: Status | Halted — prior gate review returned GATE_BLOCKED. Resolve flagged issues and run COORDINATOR to re-dispatch GATE_REVIEWER.`
     Terminate. Do not auto-re-dispatch into an unmodified blocked document.
   - **`"passed"`:** Gate has passed. If Superpowers is installed: optionally invoke
     `/finishing-a-development-branch` to determine the integration approach before advancing.
     Then advance the workflow:
     a. Mark the just-completed phase's row in `registry.md` as complete: locate the row whose
        Phase column equals the current (pre-advancement) value of `current_phase` in
        `state.json`. If that row's Status column is not already `[x]`, replace it with `[x]`.
        Do not modify any other column in that row (Phase File, Session, Depends On) and do not
        modify any other row. If the Status column already reads `[x]`, make no write — this
        step is idempotent. This is the only condition under which COORDINATOR writes to
        `registry.md`, and flipping this one flag on this one row is the only write it may make.
     b. Scan `registry.md` in row order, starting from the top, and select the first phase that
        is (i) not yet `[x]` complete, and (ii) has every phase listed in its Depends On column
        already `[x]` complete. This selected phase — not simply the next row after the phase
        that just gated — is the new value of `current_phase`. If the row immediately following
        the just-completed phase is itself dependency-blocked, skip it and continue scanning
        subsequent rows; do not stop the scan at the first blocked row.
     c. Reset `phase_gate` in `state.json` to
        `{ "status": "pending", "gate_review_attempts": 0, "gate_eval_cycles": 0 }`.
        Play the notification tone (non-blocking — ignore any failure and continue): run
        `./sdp-shared/scripts/sdp-tone.ps1 -trigger "milestone.phase_complete"` via the
        PowerShell tool. Also record the milestone (non-blocking — ignore any failure and
        continue): run `./sdp-shared/scripts/sdp-workflow-log.ps1 -trigger
        "milestone.phase_complete" -role "COORDINATOR" -outcome "PHASE_COMPLETE" -reason "Gate
        passed; advancing current_phase"` via the PowerShell tool.
     d. If item b found an eligible phase: re-enter Step 4 logic for the new phase (check for
        REJECTED, PENDING, and gate state; proceed to dispatch).
     e. If item b found no eligible phase and every row in `registry.md` is `[x]` complete: play
        the notification tone (non-blocking — ignore any failure and continue): run
        `./sdp-shared/scripts/sdp-tone.ps1 -trigger "milestone.all_complete"` via the PowerShell
        tool. Also record the milestone (non-blocking — ignore any failure and continue): run
        `./sdp-shared/scripts/sdp-workflow-log.ps1 -trigger "milestone.all_complete" -role
        "COORDINATOR" -outcome "ALL_COMPLETE" -reason "Every phase in registry.md is [x]
        complete"` via the PowerShell tool. Then invoke
        `/sdp-create-banner icon=success row=0 row: Status | All phases complete — workflow finished.`
        Terminate without writing a dispatch file.
     f. If item b found no eligible phase but at least one row is still not `[x]` complete: this
        is a dependency deadlock (e.g., a cycle, or a Depends On entry naming a phase that will
        never complete) — not completion. Halt per the Halt Behavior Contract: set
        `workflow_status` to `"halted"` in `state.json` and `halt_reason` to "No phase in
        registry.md is eligible to dispatch — remaining incomplete phases [list] are all blocked
        by unmet dependencies." Notify the user by invoking
        `/sdp-create-banner icon=error row=0 row: Status | No phase in registry.md is eligible to dispatch — remaining incomplete phases [list] are all blocked by unmet dependencies.`
        Do not report "All phases complete" in this case.
6. If no actionable task exists after all checks above: report to the user and terminate
   without writing a dispatch file.

### Step 5: Write Dispatch File (task dispatch) / Gate Dispatch Variant

1. Determine the next session number: read the `[resolved_project]/.sdp-workflow/sessions/`
   directory, find the highest existing `session-NNN.md` number, and increment by 1. If no
   sessions exist, start at `session-001.md`.
2. Write `[resolved_project]/.sdp-workflow/sessions/session-NNN.md` using the session file
   template from the bootstrap document. Include:
   - Role: `WORKER` (for PENDING task) or `REVIEWER` (for WORK_COMPLETE task)
   - **`Project: [resolved_project]`** — always include this field; it locks the project for
     the dispatched session's lifetime
   - Work Item: task ID
   - Bootstrap doc path
   - Phase file path (under `[resolved_project]/`) — the exact value from `registry.md`'s
     Phase File column for the dispatched task's phase (read in Step 2). Do not reconstruct
     this path from `current_phase` or any folder-name convention — the registry column is
     the only authoritative source.
   - Any task flags (e.g., `VERIFY_DURING_IMPLEMENTATION`)
   - If Superpowers is not installed: include the manual TDD/debugging instruction for WORKER,
     or the manual review instruction for REVIEWER
   - If dispatching REVIEWER for a re-evaluation cycle: include the re-evaluation trigger reason
   - If dispatching in `"human-gated"` mode: include the instruction "Start a new subagent
     with this session file as the opening prompt"
   - ~~If the task has a CI acceptance criterion (e.g., "GitHub Actions CI passes"): instruct
     the REVIEWER to run `git status` and commit ALL untracked/modified project files before
     triggering CI — do not enumerate a specific file list in the dispatch instructions~~
     **Superseded by the config-driven CI gate.** The CI-green check is no longer keyed to an
     explicit per-task acceptance criterion. It is governed by `SDP-Config.json` `ci.enabled`:
     when true, WORKER step 5/6 and REVIEWER step 4.1 run `./sdp-shared/scripts/sdp-github.ps1
     ci-status` and wait for the run on the pushed HEAD to go `green` (or handle
     `red` / `no_ci` / `unreachable` / `timeout`) as part of every code/test completion. No
     special dispatch instruction is required — the gate is built into the WORKER/REVIEWER
     procedures. (The prior path fired only on an explicit criterion and never waited for green.)
   - **Never instruct WORKER or REVIEWER to write `eval_cycle_attempts`.** That field is owned
     solely by `sdp-project-state-loop` (see bootstrap Stuck-Loop Detection). A dispatch file may state
     the field's *current* value for context, but must not direct the dispatched role to set,
     seed, or increment it. State-write instructions are limited to: WORKER → `status`,
     `last_session`, `last_updated`; REVIEWER → `eval_cycles` and `status`. An "On success" /
     "On FAIL" step that tells a role to set or increment `eval_cycle_attempts` is the
     stuck-loop accounting corruption this rule exists to prevent.
3. Write `[resolved_project]/sdp-docs/00_prompt.txt` — overwrite with the ready-to-paste
   prompt for the dispatched role using the five-section format defined in the bootstrap
   document's `sdp-docs/00_prompt.txt` template. The file must begin with the sentinel line
   (before Section 1):
   `[sdp-prompt work_item="[TASK-ID]" expected_status="[CURRENT-STATUS]" role="[DISPATCH-ROLE]"]`
   `expected_status` must equal the task's status **at the time of writing** — `PENDING` for a
   WORKER dispatch, `WORK_COMPLETE` for a REVIEWER dispatch. Do NOT write the status the task
   will be in after the session runs. `role` is the role this prompt dispatches — `WORKER` for a
   PENDING task, `REVIEWER` for a WORK_COMPLETE task. The recurring `sdp-project-state-loop` reads `role`
   to count `eval_cycle_attempts` against REVIEWER dispatches only (the COORDINATOR
   dispatch-of-REVIEWER fire also reads `WORK_COMPLETE` but must not consume a REVIEWER attempt —
   see Stuck-Loop Detection). `role` is **mandatory** — omitting it leaves `sdp-project-state-loop`
   unable to distinguish a REVIEWER fire from the COORDINATOR dispatch-of-REVIEWER fire, which
   corrupts `eval_cycle_attempts` accounting. Always write all three sentinel fields
   (`work_item`, `expected_status`, `role`). Follow the sentinel with one blank line, then the
   five sections. Populate sections: Role (WORKER or REVIEWER), current state summary from
   `[resolved_project]/.sdp-workflow/state.json`, Task Instruction (brief task description +
   "Invoke `/sdp-project-worker`" or "Invoke `/sdp-project-reviewer` to begin."), Key Files (state.json,
   session-NNN.md, phase file path — all under `[resolved_project]/`).

**Gate Dispatch Variant** — when dispatching GATE_REVIEWER (Step 4 sub-step 5, `"pending"` branch
or the `"blocked"` branch's Re-gate path):

- Determine the next session number (same method as sub-step 1 above).
- Write `[resolved_project]/.sdp-workflow/sessions/session-NNN.md` using these **exact literal
  field lines** (one per line, `Field: value`) — `sdp-project-gate-review`'s Block 2 setup script
  (`sdp-gate-review-setup.ps1`) parses this file by these field names; do not paraphrase or
  reorder them:
  ```
  Role: GATE_REVIEWER
  Project: [resolved_project]
  Work Item: [current_phase]
  Phase Document: [resolved_project]/[Phase File value from registry.md for current_phase]
  Bootstrap Doc: [bootstrap doc path]
  Re-Gate Trigger: [if a real prior GATE_BLOCKED blockquote exists for this phase (gate_review_attempts was >= 1 before this dispatch), summarize it; otherwise (the Re-gate path — gate_review_attempts was 0, no real block ever occurred) summarize the triggering entry from phase_gate/phase_readiness.regressions[]: target phase, date, chosen remediation. Omit this line entirely on a genuine first-ever gate cycle.]
  Instruction: [Start a new subagent with this session file as the opening prompt — for
    human-gated; omit for loop-orchestrated, where sdp-project-state-loop handles spawning]
  ```
  - `Phase Document:` is the Phase File column value from `registry.md` for `current_phase`,
    prefixed with `[resolved_project]/` — not a path reconstructed from `current_phase` via
    string substitution (`sdp-docs/[current_phase].md`), which does not match every project's
    actual phase-document naming (e.g. a project numbering files `sdp-docs/10_name_plan.md`
    rather than `sdp-docs/phase10_name.md`).
  - `Re-Gate Trigger:` is included on any re-gate cycle — reached via either the `"blocked"`
    branch's Re-gate path (`gate_review_attempts == 0`) or its Real-prior-block path
    (`gate_review_attempts >= 1`) — and omitted only on a genuine first-ever gate cycle
    (`"pending"` with no prior block of any kind, at any point in this phase's history)
  - **Never instruct GATE_REVIEWER to write `gate_review_attempts`** — that field is owned
    solely by `sdp-project-state-loop`. Allowed state-write for GATE_REVIEWER: `phase_gate.status`
    and `phase_gate.gate_eval_cycles` only.
- Write `[resolved_project]/sdp-docs/00_prompt.txt` with the five-section format and the sentinel:
  `[sdp-prompt work_item="[current_phase]" expected_status="[phase_gate.status]" role="GATE_REVIEWER"]`
  `expected_status` is the `phase_gate.status` value at the time of writing (`"pending"` for
  first gate). Section content: Role = GATE_REVIEWER, current state summary including
  `phase_gate.status` and `phase_gate.gate_eval_cycles`, Task Instruction = "Review the
  completed [current_phase] phase document against gate criteria. Invoke `/sdp-project-gate-review`
  to begin.", Key Files = state.json, session-NNN.md, phase document path (note: no phase
  state file — gate review is document-scoped).
- Proceed to Step 6 (gate-aware state write — see note in Step 6).

### Step 6: Update State

1. Update `[resolved_project]/.sdp-workflow/state.json`:
   - Set `last_session` to the new session identifier (e.g., `"session-001"`)
   - **Task dispatch:** Set `active_work_item` to the task ID being dispatched.
   - **Gate dispatch:** Do NOT set `active_work_item` — it remains at the last completed
     task ID or null. Gate reviews are phase-scoped, not task-scoped.
   - Set `active_phase_file` to the Phase File value from `registry.md` for the dispatched
     phase — the current task's phase for a task dispatch, `current_phase` for a gate
     dispatch. Both dispatch types set this field: `sdp-project-state-loop`, `sdp-auto`,
     `sdp-create-prompt.ps1`, and `sdp-solution-coordinator.ps1` all derive the phase state
     file from it (sibling `.md` → `_state.json` replacement) as their primary lookup
     mechanism. This was mandated by the bootstrap document's Implementation Loop step 6 since
     its earliest version but never implemented until this correction — see the 2026-07-10
     correction note there for the full history.
   - Set `updated` to today's ISO date
2. Record the dispatch decision (non-blocking — ignore any failure and continue): run
   `./sdp-shared/scripts/sdp-workflow-log.ps1 -trigger "coordinator.dispatch" -role
   "COORDINATOR" -workItem "[active_work_item, or empty for a gate dispatch]" -phase
   "[dispatched phase]" -outcome "[WORKER_DISPATCHED | REVIEWER_DISPATCHED |
   GATE_REVIEWER_DISPATCHED]" -reason "[one sentence: why this task/phase was selected next —
   e.g. first PENDING task in current phase, REJECTED task taking priority, or all tasks
   VERIFIED and gate is pending]"` via the PowerShell tool. This is the narrative counterpart to
   the mechanical PreToolUse/PostToolUse trail in `sdp-hook-log.ps1` — the reasoning behind a
   dispatch decision is not recoverable from tool-call telemetry alone.

### Step 7: Notify User

1. Read `orchestration_mode` from `[resolved_project]/.sdp-workflow/state.json`.
2. **If `"human-gated"`:** Print:
   "Ready to dispatch [ROLE] for [TASK-ID] — `[resolved_project]/sdp-docs/00_prompt.txt`
   contains the ready-to-paste prompt. Open a new subagent and paste it to begin."
   Terminate. Do not wait for or attempt to detect the outcome.
3. **If `"agent-orchestrated"`:** Spawn a subagent via the Agent tool with the content of
   `[resolved_project]/.sdp-workflow/sessions/session-NNN.md` as the prompt, plus the bootstrap
   doc path. After the Agent tool returns:
   - **Task dispatch:** Derive the phase state file from `active_phase_file` (just written in
     Step 6) by replacing its trailing `.md` with `_state.json`, and read it to get the
     outcome. Continue COORDINATOR logic based on outcome: VERIFIED → find next task;
     REJECTED → re-queue at top of Step 4.
   - **Gate dispatch:** Read `[resolved_project]/.sdp-workflow/state.json` `phase_gate.status`
     to get the gate outcome. GATE_PASSED → re-enter Step 4 (phase advancement branch);
     GATE_BLOCKED → halt per the blocked-gate halt defined in Step 4 sub-step 5.
4. **If `"loop-orchestrated"`:** Do not spawn a subagent — the recurring `sdp-project-state-loop`
   performs all execution. The session dispatch file, `state.json`, and `00_prompt.txt` written
   in Steps 5–6 are the complete handoff. Print:
   "Dispatch prompt written for [ROLE] / [TASK-ID]. The running `sdp-project-state-loop` will execute
   it on its next fire (start it with `/sdp-auto` or `/sdp-state-loop-start` if it is not
   running)."
   Terminate. Do not wait for or attempt to detect the outcome.
5. **If `orchestration_mode` is absent or any other value:** Treat it as `"human-gated"` —
   print the human-gated message from sub-step 2 and terminate. Do not spawn a subagent.

## Constraints

- Never use `sdp-project-coordinator` to dispatch a task with a `parent` field (cross-project tasks) —
  it is scoped to single-project work only; cross-project tasks are dispatched directly by
  `sdp-solution-coordinator`.
- Never touch implementation files, source code, or phase section files during a COORDINATOR
  session. The only files written are
  `[resolved_project]/.sdp-workflow/sessions/session-NNN.md`,
  `[resolved_project]/.sdp-workflow/state.json`,
  `[resolved_project]/sdp-docs/00_prompt.txt`, and, only as described below,
  `[resolved_project]/.sdp-workflow/registry.md`.
- The Phase Readiness regression path (Step 4 sub-step 5, `"blocked"` branch) is the one
  exception to COORDINATOR "never advances `current_phase` except via a passed gate" — it may
  move `current_phase` *backward* to a user-selected `Target Phase:` value, but only after the
  user has explicitly selected a remediation proposal; it never selects one itself.
- The only write COORDINATOR may make to `registry.md` is the Step 4 sub-step 5.a flag flip:
  replacing a single row's Status column with `[x]` when that row's Phase matches the
  just-completed `current_phase` and the column does not already read `[x]`. No other column,
  row, or condition may trigger a `registry.md` write. Never write a free-text note, log entry,
  or narrative description of this action anywhere (including `auto_actions`) — the flag flip
  is the entire and only record of it.
- Never proceed to Step 2 while any active or in-progress phase's state file is missing the
  `sdp_doc_review` key or has `completed: false` — run `sdp-project-doc-review` on every unreviewed doc
  first, even if other staged docs are already reviewed.
- Never silently correct a discrepancy where a task's phase-file checkbox is `[x]` but its
  state-file status is `PENDING` — flag it to the user and pause for instruction before
  continuing or dispatching.
- Do not dispatch WORKER if the active task is in state `WORK_COMPLETE` — dispatch REVIEWER.
- Do not dispatch any task if `workflow_status` is `"halted"`.
- Do not dispatch a phase whose Depends On dependencies are not yet `[x]` complete.
- Phase advancement (Step 4 sub-step 5, `"passed"` branch) must never simply advance to the
  next row in `registry.md` — it must scan in row order and select the next dependency-eligible
  phase. Row order is only the tiebreaker among equally-eligible phases, not the sole ordering
  signal.
- Never report "All phases complete" while at least one `registry.md` row is still not `[x]`
  complete — that state is a dependency deadlock (Step 4 sub-step 5.f), not completion, and
  must be halted per the Halt Behavior Contract instead.
- Never deviate from the `orchestration_mode`-governed dispatch behavior (Step 7):
  `"human-gated"` must only print and terminate, `"agent-orchestrated"` must only spawn and read
  the outcome, `"loop-orchestrated"` must only write the handoff and terminate without spawning.
  Never treat an absent or unrecognized value as anything other than `"human-gated"`.
- In `"loop-orchestrated"` mode, COORDINATOR must not spawn a WORKER or REVIEWER — execution is
  the recurring `sdp-project-state-loop`'s responsibility.
- Dispatch files must never instruct any role to set, seed, or increment `eval_cycle_attempts`
  (owned solely by `sdp-project-state-loop`), and must never omit the sentinel `role` field — omitting
  it corrupts stuck-loop accounting.
- Outcome detection derives the phase state file from `active_phase_file` (sibling `.md` →
  `_state.json` replacement) — never subagent text output, and never a hardcoded
  `[doc_name]_Phases/` path convention, which does not match every project's file layout.
- No role other than COORDINATOR may clear a halt, and COORDINATOR must never clear one without
  first reading `workflow_status` and confirming the blocking condition is resolved — only then
  set `workflow_status` back to `"active"` and clear `halt_reason`.

## Outputs

- `[resolved_project]/.sdp-workflow/sessions/session-NNN.md` — dispatch file for the spawned session
- `[resolved_project]/.sdp-workflow/state.json` — updated `last_session`, `active_work_item`,
  `active_phase_file`, `updated`
- `[resolved_project]/.sdp-workflow/registry.md` — on phase-gate advancement only: the
  just-completed phase's row Status column flipped to `[x]` (Step 4 sub-step 5.a); no other
  write to this file
- `[resolved_project]/sdp-docs/00_prompt.txt` — ready-to-paste prompt for the dispatched WORKER or REVIEWER session
- `.sdp-solution-workflow/logging/workflow-logs/workflow-log-<local-yyyyMMdd>.jsonl` — one
  `coordinator.dispatch` entry per dispatch (plus `halt.generic`/milestone entries where
  applicable), recording the decision and rationale (non-blocking side effect, via
  `sdp-workflow-log.ps1`)
- User-facing notification of dispatch target and next action
