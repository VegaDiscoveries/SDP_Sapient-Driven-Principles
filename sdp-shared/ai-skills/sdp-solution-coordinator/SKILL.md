## Purpose

Execute a COORDINATOR session at the solution level: read `SDP-Solution.json` and all child
project states, enforce the cycle sync invariant, fan out parallel subagents (one per laggard
project in synced mode) or sequence dispatch, write session files with `Project:` field,
update `last_active_projects` in `SDP-Solution.json`, detect cascades, and terminate. This
skill is stateless across invocations — it reads all child states fresh on each execution and
terminates after each dispatch.

**Hybrid model:** a script owns
every deterministic step — reading both state files, resolving each child's authoritative
status, enforcing the sync invariant, computing laggards, writing session files, and updating
`.sdp-solution-workflow/state.json` / `SDP-Solution.json`. The LLM takes over only where a Skill
tool invocation, Agent tool spawns, or reading a just-returned subagent's outcome is structurally
required — invoking `sdp-solution-create-prompt`, dispatching subagents, and confirming outcomes.
Normal-path tool calls: 1 script invocation + 1 Skill invocation + N Agent dispatches + N outcome
reads. There is no LLM assembly step for session files or state writes on the normal path.

**Scope note:** `sdp-solution-coordinator` manages cross-project tasks only — tasks that have
a `parent` field in their project state entries. Single-project work is managed by
`sdp-project-coordinator`.

**Solution level:** This skill operates at the solution root. All file paths are relative to
the solution root (the Claude Code working directory).

## Inputs

All paths are relative to the solution root. The script reads these directly; the LLM does not
read them on the normal path.

- `SDP-Solution.json` — provides `active_solution_task` and `projects` registry
- `.sdp-solution-workflow/state.json` — provides the solution task entry, children list,
  `workflow_status`, `halt_reason`, and the `last_session` counter
- `[child.project]/[phase]_state.json` (or `[child.project]/.sdp-workflow/state.json` as a
  fallback for path derivation) — authoritative status for each child task
- `[child.project]/[child.phase_file]` — read only when a rejection or diagnosis-blocked
  message needs to be extracted (cascade / `SOL_DIAGNOSIS_BLOCKED` paths)
- `.sdp-solution-workflow/sessions/` — directory where solution session dispatch files are
  written

## Procedure

### Step 0: Preflight Check

Run `./sdp-shared/scripts/sdp-preflight.ps1 -workspaceRoot .` via the PowerShell tool.
`-workspaceRoot .` is the solution root itself — not a per-project path — so the script
resolves the solution-level manifest (`SDP-Solution-Setup.json`) instead of a project's
`SDP-Workspace-Setup.json`. This one call validates every deterministic solution-level
precondition declared in that manifest and emits a single-line JSON envelope. Read it:

- If `ok` is `true`: preconditions pass — proceed to Step 1.
- If `ok` is `false`: halt per the Halt Behavior Contract — set `workflow_status` to
  `"halted"` and `halt_reason` to a one-line description citing the `failures` array from the
  envelope (or the `error` field on an operational error such as a missing/unparseable
  manifest, which the script reports with exit code 1) in `.sdp-solution-workflow/state.json`.
  Play the notification tone (non-blocking — ignore any failure and continue): run
  `./sdp-shared/scripts/sdp-tone.ps1 -trigger "halt.generic"` via the PowerShell tool. Then
  notify the user by invoking
  `/sdp-create-banner icon=error row=0 row: Status | Halted — preflight failed: [failures]. Restore the missing/invalid items and run SOLUTION_COORDINATOR to resume.`,
  and terminate. Do not proceed to Step 1.

To force a full re-check (bypassing the staleness timers — e.g. when re-running
SOLUTION_COORDINATOR immediately after clearing a halt), pass `-Force`. The canonical check
inventory lives in `SDP-Solution-Setup.json` at the solution root as data; do not re-enumerate
it here.

### Step 0a: Migration Detection

Runs once per solution, the first time this skill dispatches in its phases-1–7 driving role
(i.e., the first invocation where `.sdp-solution-workflow/state.json`'s `current_phase` is about
to be set for the first time, or is already set but no prior migration-detection pass has run for
this solution — track this via a `migration_checked: true` flag added to `state.json` on first
pass, adjacent to the existing top-level fields).

1. If `migration_checked` is already `true`: skip this step entirely.
2. Check whether any registered project's `.sdp-workflow/registry.md` contains a row for any of
   the seven phase names (Concept / Research / Expanded Concept / Architecture / Implementation
   Overview / Refined Implementation Plan / Phase Readiness) — a project-scoped phase row is the
   signal this solution predates this design.
3. **None found:** set `migration_checked: true`, proceed normally (Step 1 onward).
4. **Found in one or more projects:** halt (Halt Behavior Contract) with `halt_reason` naming
   every project and phase found, and present the user with the actual content of each affected
   project's existing phase 1–7 documents side by side. This is a one-time, human-directed
   reconciliation — not scriptable. The user decides, per phase, whether one project's existing
   document becomes the solution-level starting point (others' equivalent content struck through
   in place with a pointer to the new solution-level equivalent — Append-Only Discipline) or a
   fresh solution-level document is drafted informed by all of them.
5. **Re-home** once reconciled: seed `.sdp-solution-workflow/registry.md` with rows for the
   resolved phase(s) onward (already-complete phases marked `[x]` immediately, with a note
   referencing the original project-level document); strike through each affected project's own
   phase 1–7 rows in place with a dated pointer to the new solution-level equivalent — never
   deleted. Set `current_phase` to the first not-yet-complete phase per the reconciliation, then
   set `migration_checked: true`.
6. **Resume** — normal operation begins from the reconciled state, no different from a solution
   that started under this design from day one.

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

### Step 1: Run Script

Run `./sdp-shared/scripts/sdp-solution-coordinator.ps1` via the PowerShell tool. No arguments —
the script self-resolves the solution root from its own location.

If the PowerShell tool call produces no parseable single-line JSON on stdout (regardless of exit
code): invoke `/sdp-create-banner icon=error row=0 row: Status | Script invocation failed — no
result to parse. Verify sdp-shared/scripts/sdp-solution-coordinator.ps1 is present and the
permission entry in .claude/settings.local.json is registered.` and halt. Do not proceed to
Step 2.

### Step 2: Handle Result

Parse the single-line JSON result. Branch on `status`:

- **`"error"`** — Invoke `/sdp-create-banner icon=error row=0 row: Error | [error]` (substitute
  the actual `error` field value for `[error]`). Halt. Do not proceed to Step 3. (No state was
  written.)
- **`"halt"`** — Invoke `/sdp-create-banner icon=error row=0 row: Status | [halt_message]`
  (substitute the actual `halt_message` field value). Halt. Do not proceed to Step 3. (The script
  has already written `workflow_status: "halted"` and `halt_reason` to
  `.sdp-solution-workflow/state.json` when `state_json_written` is `true`; when `false`, the
  workflow was already halted from a prior run and this is a read-back only.)
- **`"blocked"`** — Invoke `/sdp-create-banner icon=error row=0 row: Status | [blocking_flag_message]`
  (substitute the actual `blocking_flag_message` field value). Halt. Do not proceed to Step 3. No
  file was written — `SOL_CASCADE_REVIEW_NEEDED` / `SOL_DIAGNOSIS_BLOCKED` must be cleared by the
  user per the original flag-clearing procedure before the next invocation can dispatch.
- **`"cascade"`** — Invoke `/sdp-create-banner icon=error` with one `row:` per entry in
  `cascade_messages` (one banner, one row per message — e.g. `row: Cascade 0 | [message]`,
  `row: Cascade 1 | [message]`, ... — in place of the N separate `⛔`-prefixed lines). Halt. Do
  not proceed to Step 3. The script has already set `SOL_CASCADE_REVIEW_NEEDED` on the task entry
  in `.sdp-solution-workflow/state.json`.
- **`"all_verified"`** — Invoke `/sdp-create-banner icon=success row=0 row: Status | [completion_message]`
  (substitute the actual `completion_message` field value). Play the milestone tone (non-blocking —
  ignore any failure): `./sdp-shared/scripts/sdp-tone.ps1 -trigger "milestone.all_complete"` via
  PowerShell. Terminate. Do not proceed to Step 3. The script has already transitioned the task to
  `SOL_VERIFIED` and either advanced `active_solution_task` to a queued task (if one existed with
  status `SOL_PENDING`) or set it to `null` in both state files.
- **`"success"`** — Proceed to Step 3. The script has already written every session file listed
  in `session_files_written`, updated `.sdp-solution-workflow/state.json` (`last_session`, stale
  `cached_status` corrections on the dispatched task's children, `updated`), and updated
  `SDP-Solution.json` (`last_active_projects` = dispatched project paths, `updated`).

### Step 2a: Phases 1–7 Driving Role

> In practice, dispatch this via `/sdp-solution-phase-coordinator` instead — a dedicated skill
> for Steps 2a-2e below.

This step only ever runs when `.sdp-solution-workflow/state.json`'s `current_phase` is set (i.e.
phases 1–7 are in progress for this solution) — mutually exclusive with the shared-task dispatch
path Step 1/2 already handle for `active_solution_task`. Both mechanisms coexist in the same
`state.json` (Task 1's schema); check `current_phase` first each invocation to determine which
path applies. If `current_phase` is absent or null: phases 1–7 have not started (or already
finished — see Step 2d below) for this solution; skip this step, proceed to whichever of Step 2's
branches applies.

**No cron job ever exists while this step's path is active** — phases 1–7 are always human-gated,
direct session-by-session dispatch (bootstrap doc, Loop Entry Point). This step's logic only ever
runs from a manually-invoked `sdp-solution-coordinator` session, never from a recurring loop fire.

1. Read `.sdp-solution-workflow/state.json` for `current_phase` and `phase_gate.status`.
2. Duplicate `sdp-project-coordinator/SKILL.md` Step 4's decision algorithm exactly (REJECTED-priority
   over PENDING, dependency-blocked checks against `.sdp-solution-workflow/registry.md`'s Depends
   On column, `phase_gate.status` branching when the current phase's tasks are all VERIFIED),
   operating on the solution's own `.sdp-solution-workflow/registry.md` and
   `.sdp-solution-workflow/state.json` instead of a project's. This is a genuine second copy of
   that logic, not a call into `sdp-project-coordinator` — `sdp-project-coordinator/SKILL.md` itself is never
   invoked, read, or modified for this purpose (boundary invariant).

   > **Drift-risk note (one-directional, by design):** this duplicated logic must be kept in sync
   > with `sdp-project-coordinator/SKILL.md` Step 4 if that step ever changes. The safeguard lives only
   > here, not in `sdp-project-coordinator` — a cross-reference comment there would itself be "knowledge
   > of a cross-project concept" inside a file the boundary invariant requires stay ignorant of
   > the solution layer, even as an inert comment. See the design doc's Section 6 for the full
   > reasoning behind this accepted, one-directional limitation.

3. When `phase_gate.status` is `"passed"`: advance `current_phase` per the duplicated algorithm's
   own advancement logic (mark the completed phase's registry row `[x]`, scan for the next
   dependency-eligible row). If the just-completed phase was "Phase Readiness" (Phase 7) and no
   further not-yet-`[x]` phase-1–7 row remains: set `current_phase` to `null` in
   `.sdp-solution-workflow/state.json` — phases 1–7 are complete for this solution; proceed to
   Step 2d below instead of dispatching further phase work this cycle.
4. When a dispatch target is found (REJECTED/PENDING task in `current_phase`, or GATE_REVIEWER
   when all tasks in `current_phase` are VERIFIED): write a session file via
   `sdp-solution-create-prompt` (Step 3, its phases-1–7 branch) targeting the solution root as
   the dispatch scope, `role` = WORKER/REVIEWER/GATE_REVIEWER as determined, `Project:` field
   omitted (this is a solution-scoped dispatch, not a per-project one). `sdp-solution-run-prompt`
   routes each of these three roles to its own dedicated solution-scoped skill —
   `sdp-solution-phase-worker`, `sdp-solution-phase-reviewer`, `sdp-solution-phase-gate-review` — never
   to `sdp-project-worker`/`sdp-project-reviewer`/`sdp-project-gate-review`, which remain project-scoped only and are
   never given a solution-level task. This applies uniformly across all seven phases 1–7, not
   only "Phase Readiness." The Phase-Readiness-specific ten-criterion assessment and Remediation
   Proposals verdict format (Task 6/7) live entirely inside `sdp-solution-phase-gate-review`, which
   always assesses all ten criteria for a Phase Readiness gate — there is no `-scope` flag or
   project/solution branch to apply; that skill exists for exactly one scope.
5. Proceed to Step 3 (existing) with this step's session file, exactly as the shared-task path's
   `session_files_written` result already flows into Step 3/4/5/6.

### Step 2b: Phase 7 Dependency-Declaration Support

Runs only when Step 2a's dispatch target is Phase 7's ("Phase Readiness") decomposition work
itself (i.e., the WORKER task being dispatched is the decomposition task, not a downstream
GATE_REVIEWER pass). This step augments the session file `sdp-solution-create-prompt` writes —
it does not replace any of that skill's existing behavior.

Include in the WORKER session's instructions (added to the session file content):

1. **Assign each decomposed build-phase task to a specific project** — the first moment a
   project's own `.sdp-workflow/registry.md` is populated, with only its assigned implementation
   tasks (never phase 1–6 documents, which never exist at project scope).
2. **Declare cross-project dependency edges directly** in `.sdp-solution-workflow/dependencies.json`
   — decomposition happens inside this one shared, solution-scoped session with full context on
   every project's assigned work, so there is nothing to "read from a sibling." Each edge:

   Task-producer shape (the common case — waiting on actual implemented, verified work):
   ```json
   {
     "consumer": { "project": "sdp-project_A", "task_id": "TASK-ID" },
     "producer": { "type": "task", "project": "sdp-project_B", "task_id": "TASK-ID" },
     "light": "RED",
     "light_attempts": 0,
     "description": "<human-readable — why this edge exists, what's actually being waited on>"
   }
   ```
   Decision-producer shape (waiting only on a decision baked into another task's acceptance
   criteria — see item 3 below):
   ```json
   {
     "consumer": { "project": "sdp-project_A", "task_id": "TASK-ID" },
     "producer": {
       "type": "decision",
       "project": "sdp-project_X",
       "task_id": "TASK-ID",
       "criterion_text": "<verbatim acceptance criterion text>"
     },
     "light": "YELLOW",
     "light_attempts": 0,
     "description": "<human-readable>"
   }
   ```
   **Initial light**, set from what's already known at decomposition time (full context, never a
   guess): **GREEN** if the needed decision was already settled during solution-level
   Architecture/Refined Plan and is already recorded in the solution's own documents (the
   consumer never actually waits; the edge exists for traceability only); **YELLOW** if the
   decision was deliberately deferred to implementation time; **RED** if the dependency is on
   actual implemented, verified work from another project's task.
3. **Bake any needed cross-project reporting requirement directly into the producer task's own
   acceptance criteria**, as ordinary task-scoping language — e.g. "Acceptance criteria: ...
   explicitly document the final decision on the `user_id` column name and type in your
   Completed blockquote." Authored once, at decomposition time, in the project's own native task
   format. The eventual WORKER on that task never needs to know *why* this criterion exists.
4. Write both ledger files as a pair: `.sdp-solution-workflow/dependencies.md` (human-readable
   narrative — why each edge exists, what's actually being waited on) and
   `.sdp-solution-workflow/dependencies.json` (the machine-readable index above, the one this
   skill and Task 10/11's mechanics actually read/write). Owned exclusively by
   `sdp-solution-coordinator` — no project-level skill ever reads or writes either file.

Confirm outcome (Step 5, unchanged) reads `.sdp-solution-workflow/dependencies.json` back to
verify it parses and every edge has the required fields, in addition to the existing phase state
file confirmation.

### Step 2c: Light Resolution Mechanics

Runs every invocation once Phase 7 has passed for this solution (`current_phase` is `null` per
Step 2a item 3) and `.sdp-solution-workflow/dependencies.json` contains at least one non-`GREEN`
edge. This step resolves ledger lights; it does not itself decide whether to dispatch a project's
coordinator this cycle — that is Task 11's Step 2d.

**RED → GREEN (mechanical, no new mechanism):** for each `RED` edge, read the producer project's
own `[phase]_state.json` — already necessary for outcome detection (Step 5, existing). Once that
specific task reaches `VERIFIED` (via the project's own, completely ordinary REVIEWER cycle), flip
the edge to `GREEN` in `.sdp-solution-workflow/dependencies.json`. No dependency-specific action
required from anyone else.

**YELLOW → BLUE → GREEN (or back to YELLOW), mirroring WORKER/REVIEWER separation:**

1. For each `YELLOW` edge: read the producer task's phase document / state file (standard outcome
   detection, never subagent text) and check whether its Completed blockquote addresses the
   decision the edge is waiting on (the acceptance criterion baked in at Task 9 Step 2b item 3).
2. If it appears to: flip `YELLOW → BLUE`. This is a claim, not yet a verified fact.
3. Dispatch a **tightly-scoped REVIEWER subagent** whose only job is confirming that specific
   claim — reading just the relevant excerpt of the producer's work, nothing else.
   - **Confirmed:** flip `BLUE → GREEN`.
   - **Not actually resolved:** flip `BLUE → YELLOW` (back), and append one ordinary new task to
     the **producer project's own registry** to re-evaluate the work, carrying the scoped
     reviewer's specific findings as a Scope note — the same shape as an existing REJECTED-task
     re-queue cycle. This is the one place this skill writes into a project's own file outside
     Phase 7 decomposition — it writes an ordinary new task in the project's own native format,
     containing no ledger concept. A project-level `sdp-project-coordinator` reading this task later sees
     nothing different from any other task it has ever dispatched (boundary invariant).

**Stuck-Dependency Detection**, mirroring the bootstrap doc's Stuck-Loop Detection pattern
(`eval_cycle_attempts`/`gate_review_attempts`), applied to ledger edges: increment each
non-`GREEN` edge's `light_attempts` by 1, once per cycle the edge is found still not `GREEN`. Read
`SDP-Config.json`'s `autoResolveHalt.dependencyAttemptThreshold` (new key, same convention as the
existing `evalCycleAttemptThreshold`; default 2 if absent). When any edge's `light_attempts`
reaches or exceeds this threshold: set `workflow_status` to `"halted"` in
`.sdp-solution-workflow/state.json`, `halt_reason` = `"Dependency edge [consumer task] →
[producer task/decision] has been stuck at [light] for [light_attempts] cycles with no progress —
human review required."` — surfaced via the existing Halt Behavior Contract. This is the same
escalation discipline already applied to `eval_cycle_attempts`/`gate_review_attempts`, extended to
one new counter type.

### Step 2d: Post-Phase-7 Dispatch Gating

Runs every invocation once Phase 7 has passed for this solution. Decides, for each project not
currently a shared-task child (Step 1/2's existing precedence — a shared-task child is never also
considered here), whether to dispatch that project's own `sdp-project-coordinator` this cycle.

1. **Next-actionable-task peek.** For each candidate project, read its `.sdp-workflow/registry.md`
   and `state.json`, and duplicate `sdp-project-coordinator/SKILL.md` Step 4's task-discovery logic
   (REJECTED-priority over PENDING, dependency-blocked checks against the project's own registry,
   `phase_gate.status` branching) to determine what task that project's `sdp-project-coordinator` would
   dispatch next, *without* actually invoking `sdp-project-coordinator`. This is a second, independent
   duplication of the same algorithm Task 9 Step 2a already duplicated for solution-scoped phase
   advancement — same drift-risk note applies (keep in sync with `sdp-project-coordinator` Step 4;
   safeguard lives here only, never as a comment inside `sdp-project-coordinator` itself). This
   peek produces one of three local outcomes, feeding both the dispatch decision below and the
   status recorded in item 6:
   - **No candidate task found** (registry fully `[x]`, no REJECTED/PENDING row, no gate pending) →
     this project's status is `work_complete`. Skip item 2 for this project — there is nothing to
     check against the dependency ledger.
   - **A candidate task exists, but the project's own `workflow_status` is `"halted"`, or the
     candidate task carries `"DIAGNOSIS_BLOCKED"`** → this project's status is `blocked` (a local
     condition needing a human, not a cross-project dependency). Skip item 2 for this project —
     there is nothing to check against the dependency ledger — but do not skip dispatch; proceed
     to item 4 below, which dispatches it anyway.
   - **A candidate task exists and neither of the above applies** → proceed to item 2 to determine
     `work_pending` vs. `waiting`.
2. Check whether the peeked next task appears as a **consumer** in
   `.sdp-solution-workflow/dependencies.json`.
   - No ledger entry, or every edge where this task is the consumer is `GREEN` → dispatch this
     project's `sdp-project-coordinator` normally this cycle; this project's status is
     `work_pending`.
   - Any edge where this task is the consumer is `RED`, `YELLOW`, or `BLUE` → **do not dispatch
     this project's coordinator at all this cycle.** Nothing is written to the project; there is
     simply no session invoked for it. It tries again next cycle. A task can carry more than one
     dependency edge; every one must independently clear — partial clearance is not clearance.
     This project's status is `waiting`.
3. This is a pure read + dispatch-or-skip decision — no flag is ever written into a project's own
   state to communicate the block. `sdp-solution-coordinator` already owns the dispatch decision
   outright; introducing a `CROSS_PROJECT_BLOCKED`-style flag into the consumer project's own
   state would leak solution-level knowledge into project scope where none is needed (rejected
   during design — see the design doc's Section 6).
4. **Dispatch every `work_pending` project, and every `blocked` project too — only `waiting`
   projects are never dispatched.** For each: proceed via the existing Step 3/4/5/6 machinery
   (`sdp-solution-create-prompt` writes the session, subagent dispatches `sdp-project-coordinator` for
   that project — this skill still never invokes `sdp-project-coordinator` itself directly; it dispatches
   a subagent whose instruction is to invoke it, exactly like every other WORKER/REVIEWER dispatch
   this skill already performs).

   **Why `blocked` is dispatched but `waiting` is not — a safety distinction, not an
   inconsistency.** A `blocked` project's own `sdp-project-coordinator` detects the condition
   itself (Step 1a / Step 4 sub-step 4) and safely refuses to do any work, surfacing the specific
   reason directly to the user — dispatching it is a deliberate, harmless pass-through. A `waiting`
   project cannot be handled the same way: `sdp-project-coordinator` never reads
   `dependencies.json` and would proceed anyway if dispatched, exactly the failure this step exists
   to prevent. Item 2's "do not dispatch" outcome for `waiting` is never bypassed.
5. **Record the cycle's dispatch set — one write for the whole cycle, not per project.** After
   items 1-4 have run for every candidate project: set `last_active_projects` in
   `SDP-Solution.json` to the full list of projects actually cleared and dispatched this cycle —
   a full array replace, not an append, mirroring this skill's own script write of
   `last_active_projects` for the shared-task path (`Select-Object -Unique` over that cycle's
   dispatched set — see `sdp-solution-coordinator.ps1`). Update `updated` alongside it. Apply the
   replace uniformly, including the empty case: if no project clears this cycle, set
   `last_active_projects` to `[]` rather than leaving a stale value in place — a stale non-empty
   entry would otherwise be read by `sdp-project-coordinator`'s own Level-3 fallback on a later
   bare invocation, dispatching a project this cycle's dependency-ledger check just found still
   blocked, since `sdp-project-coordinator` never reads `dependencies.json`.

   **`sdp-project-coordinator` must never perform this write itself** — see the identical note in
   `sdp-solution-phase-coordinator/SKILL.md` Step 2d item 5, the live copy of this step (this
   file's own Step 2d never actually executes — Purpose section: the script hard-errors on a null
   `active_solution_task` before reaching it). Kept here anyway, mirroring item 5's text exactly,
   for the same drift-prevention reason the rest of Steps 2a-2e are kept here unmodified.
6. **Record each project's per-cycle status — full coverage, every registered project, every
   cycle.** After items 1-2 have classified every candidate project this cycle: for each entry in
   `SDP-Solution.json`'s `projects[]` array, set a `status` field to one of `work_complete` /
   `work_pending` / `waiting` / `blocked` / `in_shared_task`, exactly as described in
   `sdp-solution-phase-coordinator/SKILL.md` Step 2d item 6, the live copy of this step (this
   file's own Step 2d never actually executes — Purpose section). Kept here anyway, mirroring
   item 6's text, for the same drift-prevention reason the rest of Steps 2a-2e are kept here
   unmodified. `sdp-project-coordinator` must never write this field, same as `last_active_projects`.

### Step 2e: Solution-Level Phase 7 Backward-Regression

Mirrors `sdp-project-coordinator/SKILL.md` Step 4 sub-step 5's `"blocked"` branch exactly (duplicated, not
called — boundary invariant), operating on the solution's own state instead of a project's. Runs
whenever Step 2a finds `phase_gate.status == "blocked"` for the solution's `current_phase`.

1. Check whether the GATE_BLOCKED blockquote in `sdp-solution-docs/07_phase_readiness.md`
   contains a `**Remediation Proposals:**` heading (Task 7's sixth-criterion finding format,
   always produced by `sdp-solution-phase-gate-review` for a Phase Readiness gate at this scope).
2. **Remediation Proposals present:** halt per the Halt Behavior Contract —
   `workflow_status = "halted"`, `halt_reason = "Phase Readiness gate found a traceability gap —
   read the Remediation Proposals in sdp-solution-docs/07_phase_readiness.md and select one before
   resuming."` Surface all numbered proposals (each with its `Target Phase:` value) verbatim.
   Terminate — never pick a proposal automatically.
3. **On the next invocation, once the user has stated their chosen proposal:**
   a. Read the chosen proposal's `Target Phase:` value — the exact `.sdp-solution-workflow/
      registry.md` Phase column value to regress to.
   b. Set `current_phase` in `.sdp-solution-workflow/state.json` to that value; set
      `phase_gate.status` to `"blocked"` for that target phase; reset
      `phase_gate.gate_review_attempts` to 0.
   c. Reset `eval_cycle_attempts` to 0, scoped exactly as `sdp-project-coordinator`'s own mechanism does:
      every task in every intermediate phase strictly between the target and Phase Readiness
      (unconditional reset — genuine re-execution, no intermediate phase skipped), and only the
      specific task(s) the chosen remediation's own scope description names or implies within the
      target phase itself.
   d. Append one entry to `.sdp-solution-workflow/state.json`'s `phase_readiness.regressions[]`
      (Task 1's schema) and increment `phase_readiness.regression_count` by 1.
   e. Proceed to Step 2a's normal dispatch logic for the new `current_phase`.
4. **No Remediation Proposals heading (a normal, non-Phase-Readiness gate block):** halt per the
   existing generic gate-blocked handling — unchanged from how any other phase's GATE_BLOCKED
   verdict is already surfaced.

### Step 3: Invoke sdp-solution-create-prompt

Invoke `sdp-solution-create-prompt` (via the Skill tool) to write
`sdp-solution-docs/00_solution_prompt.txt`. Provide:
- `role`: `"SOLUTION_COORDINATOR"` — records that this dispatch originated from the coordinator
- `projects`: comma-separated list of the `project` field from every entry in the result's
  `laggards` array

### Step 4: Dispatch Subagents

Branch on `solution_reviewer_dispatch` and `dispatch_mode` from the script result:

- **`solution_reviewer_dispatch` is `true`:** Dispatch one subagent using the single session file
  listed in `session_files_written` as its prompt (role `SOLUTION_REVIEWER`, `Projects:` field
  lists every dispatched project). Wait for it to complete.
- **`solution_reviewer_dispatch` is `false` and `dispatch_mode` is `"synced"`:** Dispatch every
  session file in `session_files_written` as parallel Agent tool calls, launched concurrently.
  Each subagent receives its session file content as the prompt plus the `bootstrap_doc` path.
  Wait for all subagents to complete before continuing.
- **`solution_reviewer_dispatch` is `false` and `dispatch_mode` is `"sequenced"`:** Dispatch
  session files one at a time, in the order they appear in `session_files_written` (which matches
  `laggards` order). Dispatch the first, wait for completion, confirm its outcome (Step 5) before
  dispatching the next.

### Step 5: Confirm Outcomes

After all dispatched subagents in this cycle have returned: for each entry in `laggards`, read
its `state_file` to confirm the outcome the subagent produced. Note any child now sitting at a
status that requires a follow-on invocation (e.g., a child now at `WORK_COMPLETE` after `PENDING`
→ that child will be dispatched as `REVIEWER` on the next `sdp-solution-coordinator` invocation).

### Step 6: Terminate

Do not re-invoke the coordinator loop internally — each coordinator invocation is one dispatch
cycle only. If Step 5 shows further dispatch is needed, that happens on the next
`sdp-solution-coordinator` invocation, not within this session.

## Constraints

- This skill is for **cross-project solution tasks only**. It does not dispatch tasks that lack
  a `parent` field in their project state entries. Single-project tasks are managed by
  `sdp-project-coordinator`.
- Never touch implementation files, source code, or project phase section files.
- Do not read or write `.sdp-solution-workflow/state.json`, `SDP-Solution.json`, or session files
  directly — the script owns every write on the normal path (Steps 1–8.2). The only writes the
  LLM performs are via `sdp-solution-create-prompt` in Step 3, and directly to
  `.sdp-solution-workflow/state.json` for the Step 0 preflight-halt case only (mirroring
  `sdp-project-coordinator`'s own preflight-halt write — `sdp-preflight.ps1` itself never mutates
  `workflow_status`).
- Do not invoke `sdp-project-coordinator` for projects involved in a cross-project task — dispatch
  `sdp-project-worker` or `sdp-project-reviewer` directly (via the session files the script already wrote).
- Never loop internally or re-invoke the coordinator after a dispatch cycle completes — each
  invocation is exactly one cycle, then terminate.
- A `"blocked"` or `"cascade"` result blocks all dispatch — do not proceed to Step 3 when either
  is returned.
- Script calling convention: `sdp-solution-coordinator.ps1` is called with no arguments (it
  self-resolves the solution root, matching `sdp-tone.ps1` / `sdp-github.ps1`). The milestone
  tone call in Step 2 is likewise called without `-workspaceRoot`.

## Outputs

- `.sdp-solution-workflow/sessions/session-NNN.md` — written by the script, one per dispatched
  child project (or one for the solution reviewer), each with `Project:` (or `Projects:`) field
- `.sdp-solution-workflow/state.json` — updated by the script: `last_session` counter, stale
  `cached_status` corrections, `updated`; or a halt / cascade / all_verified transition. On a
  Step 0 preflight failure, `workflow_status` and `halt_reason` are instead written directly by
  this skill, before the script ever runs.
- `SDP-Solution.json` — updated by the script: `last_active_projects` (dispatched project paths),
  `updated`; `active_solution_task` is also updated by the script on an all_verified transition
- `sdp-solution-docs/00_solution_prompt.txt` — written by `sdp-solution-create-prompt` (Step 3)
- User-facing notification of dispatch targets, cascade freeze, halt, blocked flag, or completion
  as applicable
