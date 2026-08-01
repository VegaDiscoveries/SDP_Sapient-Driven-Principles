## Purpose

Execute a COORDINATOR session driving the solution's own phases 1-7 (Concept through Phase
Readiness) and, once Phase 7 has passed, the ongoing cross-project dependency-ledger and
post-Phase-7 dispatch-gating duties that follow. This is a dedicated companion to
`sdp-solution-coordinator` — a straight copy of that skill (SKILL.md and backend script), with
targeted edits limited to what phases-1-7 dispatch actually needs. `sdp-solution-coordinator`
itself owns shared-cross-project-task dispatch only (tasks with a `parent` field) and is never
given a phases-1-7 dispatch; this skill is never given a shared-task dispatch. The two do not
call each other.

**Why a separate skill, not an edit to `sdp-solution-coordinator`:** `sdp-solution-coordinator`'s
Step 1/2 shared-task dispatch path — and its backend script — is proven working in a real
multi-project environment and predates the phases-1-7 driving role entirely. Rather than risk
that proven mechanism by threading a new precondition and a new write path through it, this
skill starts as an exact copy and carries the phases-1-7-specific fixes alone. Most of the
copied content below (Steps 0, 0a, 2a-2e) already existed in `sdp-solution-coordinator/SKILL.md`
verbatim — describing the phases-1-7 driving role correctly in prose — but that skill's own
script hard-errors on a null `active_solution_task` before ever reaching that logic, so it was
never actually reachable there. The targeted fixes here (Steps 1, 2, 2a item 4, 3, 4, 5, marked
below) are what make it reachable and actually write the dispatch artifacts it needs.

**Hybrid model** (shared basis with `sdp-solution-coordinator`, since the script this skill's
copy is based on implements the identical shared-task boundary analysis): the copied script still owns every
deterministic step for the shared-task path (dead code in this skill's actual usage, kept as
copied rather than stripped — see Constraints). For the phases-1-7 path, the LLM owns the
dispatch-target decision (a duplicated copy of `sdp-project-coordinator` Step 4's algorithm, per Step 2a)
and writes the session file and prompt directly — there is no script involvement in that path at
all, mirroring exactly how project-level `sdp-project-coordinator` (no backing script) works.

**Scope note:** This skill manages the solution's phases 1-7 and post-Phase-7 dependency/dispatch
duties only. Shared-cross-project-task dispatch (tasks with a `parent` field) is
`sdp-solution-coordinator`'s exclusive job — never handled here.

**Solution level:** This skill operates at the solution root. All file paths are relative to
the solution root (the Claude Code working directory).

## Inputs

All paths are relative to the solution root.

- `SDP-Solution.json` — provides `active_solution_task` (read once, to confirm it is null —
  see Step 1) and `projects` registry
- `.sdp-solution-workflow/state.json` — provides `current_phase`, `phase_gate`, `last_session`,
  `migration_checked`, `phase_readiness`, and (dead-code path only) the solution task entry,
  children list, `workflow_status`, `halt_reason`
- `.sdp-solution-workflow/registry.md` — phase 1-7 rows, Depends On column
- `.sdp-solution-workflow/dependencies.json`/`.md` — cross-project dependency ledger
- `[project]/.sdp-workflow/registry.md`, `state.json` — read for Phase 7 decomposition and
  post-Phase-7 dispatch gating (Steps 2b/2d)
- `.sdp-solution-workflow/sessions/` — directory where session dispatch files are written

## Procedure

### Step 0: Preflight Check

Run `./sdp-shared/scripts/sdp-preflight.ps1 -workspaceRoot .` via the PowerShell tool.
`-workspaceRoot .` is the solution root itself — not a per-project path — so the script
resolves the solution-level manifest (`SDP-Solution-Setup.json`) instead of a project's
`SDP-Workspace-Setup.json`. This one call validates every deterministic solution-level
precondition declared in that manifest and emits a single-line JSON envelope. Read it:

- If `ok` is `true`: preconditions pass — proceed to Step 0a.
- If `ok` is `false`: halt per the Halt Behavior Contract — set `workflow_status` to
  `"halted"` and `halt_reason` to a one-line description citing the `failures` array from the
  envelope (or the `error` field on an operational error such as a missing/unparseable
  manifest, which the script reports with exit code 1) in `.sdp-solution-workflow/state.json`.
  Play the notification tone (non-blocking — ignore any failure and continue): run
  `./sdp-shared/scripts/sdp-tone.ps1 -trigger "halt.generic"` via the PowerShell tool. Then
  notify the user by invoking
  `/sdp-create-banner icon=error row=0 row: Status | Halted — preflight failed: [failures]. Restore the missing/invalid items and run sdp-solution-phase-coordinator to resume.`,
  and terminate. Do not proceed to Step 0a.

To force a full re-check (bypassing the staleness timers), pass `-Force`. The canonical check
inventory lives in `SDP-Solution-Setup.json` at the solution root as data; do not re-enumerate
it here.

### Step 0a: Migration Detection

Runs once per solution, the first time this skill dispatches (i.e., the first invocation where
`.sdp-solution-workflow/state.json`'s `current_phase` is about to be set for the first time, or
is already set but no prior migration-detection pass has run for this solution — track this via
a `migration_checked: true` flag added to `state.json` on first pass, adjacent to the existing
top-level fields).

1. If `migration_checked` is already `true`: skip this step entirely.
2. Check whether any registered project's `.sdp-workflow/registry.md` contains a row for any of
   the seven phase names (Concept / Research / Expanded Concept / Architecture / Implementation
   Overview / Refined Implementation Plan / Phase Readiness) — a project-scoped phase row is the
   signal this solution predates this design.
3. **None found:** set `migration_checked: true`, proceed normally (Step 1 onward).
4. **Found in one or more projects:** halt (Halt Behavior Contract) with `halt_reason` naming
   every project and phase found, and present the user with the actual content of each affected
   project's existing phase 1-7 documents side by side. This is a one-time, human-directed
   reconciliation — not scriptable. The user decides, per phase, whether one project's existing
   document becomes the solution-level starting point (others' equivalent content struck through
   in place with a pointer to the new solution-level equivalent — Append-Only Discipline) or a
   fresh solution-level document is drafted informed by all of them.
5. **Re-home** once reconciled: seed `.sdp-solution-workflow/registry.md` with rows for the
   resolved phase(s) onward (already-complete phases marked `[x]` immediately, with a note
   referencing the original project-level document); strike through each affected project's own
   phase 1-7 rows in place with a dated pointer to the new solution-level equivalent — never
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

### Step 1: Run Script — **[TARGETED FIX]**

Run `./sdp-shared/scripts/sdp-solution-phase-coordinator.ps1` via the PowerShell tool. No
arguments — the script self-resolves the solution root from its own location.

This is a copy of `sdp-solution-coordinator.ps1` with one targeted fix: where the original
hard-errors on a null `active_solution_task`, this copy instead returns a new graceful
`"no_shared_task"` status — that condition is the expected, common case here, not an error (see
Step 2). Every other line of the copied script — cascade detection, children resolution, the
shared-task session-file template — is unchanged from the original, kept as dead code for this
skill's actual usage (see Constraints).

If the PowerShell tool call produces no parseable single-line JSON on stdout (regardless of exit
code): invoke `/sdp-create-banner icon=error row=0 row: Status | Script invocation failed — no
result to parse. Verify sdp-shared/scripts/sdp-solution-phase-coordinator.ps1 is present and the
permission entry in .claude/settings.local.json is registered.` and halt. Do not proceed to
Step 2.

### Step 2: Handle Result — **[TARGETED FIX: new `"no_shared_task"` branch]**

Parse the single-line JSON result. Branch on `status`:

- **`"no_shared_task"`** — Expected, common case: no shared cross-project task is active. Skip
  Steps 3-6 below (they are the shared-task path) entirely. Proceed directly to Step 2a.
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
  `cascade_messages`. Halt. Do not proceed to Step 3. The script has already set
  `SOL_CASCADE_REVIEW_NEEDED` on the task entry in `.sdp-solution-workflow/state.json`.
- **`"all_verified"`** — Invoke `/sdp-create-banner icon=success row=0 row: Status | [completion_message]`
  (substitute the actual `completion_message` field value). Play the milestone tone (non-blocking —
  ignore any failure): `./sdp-shared/scripts/sdp-tone.ps1 -trigger "milestone.all_complete"` via
  PowerShell. Terminate. Do not proceed to Step 3. The script has already transitioned the task to
  `SOL_VERIFIED` and either advanced `active_solution_task` to a queued task (if one existed with
  status `SOL_PENDING`) or set it to `null` in both state files.
- **`"success"`** — This is the shared-task dead-code path described in Constraints — proceed to
  Step 3 exactly as `sdp-solution-coordinator` would. The script has already written every
  session file listed in `session_files_written`, updated `.sdp-solution-workflow/state.json`
  (`last_session`, stale `cached_status` corrections on the dispatched task's children,
  `updated`), and updated `SDP-Solution.json` (`last_active_projects` = dispatched project
  paths, `updated`).

### Step 2a: Phases 1-7 Driving Role

This step only ever runs when `.sdp-solution-workflow/state.json`'s `current_phase` is set (i.e.
phases 1-7 are in progress for this solution). If `current_phase` is absent or null: phases 1-7
have not started (or already finished — see Step 2d below) for this solution; skip to whichever
of Step 2's other branches applies, or terminate if none does.

**No cron job ever exists while this step's path is active** — phases 1-7 are always human-gated,
direct session-by-session dispatch (bootstrap doc, Loop Entry Point). This step's logic only ever
runs from a manually-invoked `sdp-solution-phase-coordinator` session, never from a recurring
loop fire.

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
   > here, not in `sdp-project-coordinator`. See the design doc's Section 6 for the full reasoning behind
   > this accepted, one-directional limitation.

2b. **SOURCE COVERAGE CHECK** — Before advancing `current_phase` past `"Concept"` or `"Expanded
   Concept"` in item 3 below (i.e. when `phase_gate.status` is `"passed"` and the just-completed
   phase is one of those two): read that phase's own `[phase]_state.json` for a
   `source_document` field. If present and `sdp_source_coverage.completed` is not `true`: run
   `sdp-source-coverage-check` against it before completing the advancement — do not proceed to
   item 3's advancement until it certifies. If the field is absent (conversational intake — no
   tracked source for this cycle): nothing to check, proceed normally. This check applies only to
   the Concept→Research and Expanded Concept→Architecture transitions; other phase transitions
   are unaffected.
3. When `phase_gate.status` is `"passed"`: advance `current_phase` per the duplicated algorithm's
   own advancement logic (mark the completed phase's registry row `[x]`, scan for the next
   dependency-eligible row). If the just-completed phase was "Phase Readiness" (Phase 7) and no
   further not-yet-`[x]` phase-1-7 row remains: set `current_phase` to `null` in
   `.sdp-solution-workflow/state.json` — phases 1-7 are complete for this solution; proceed to
   Step 2d below instead of dispatching further phase work this cycle.
3a. **[Phase 1/3 interactive capture]** When step 2's algorithm determined the dispatch target is
   a **WORKER** task (not REVIEWER/GATE_REVIEWER) and `current_phase` is `"Concept"` or
   `"Expanded Concept"`: before writing the session dispatch file (item 4 below), assemble the
   input material, then run `/brainstorming` interactively with the user in this COORDINATOR
   session — permitted by the bootstrap doc's Role Separation carve-out (writing to
   `sdp-solution-docs/01_concept.md` / `sdp-solution-docs/03_expanded_concept.md` and their
   section files during a `/brainstorming` capture session is not an implementation-file edit).

   **Input material to read first, before opening the brainstorming session:**
   - **Tracked source document, both phases:** read this cycle's Concept phase state file
     (`[phase]_state.json` for the "Concept" row) for a `source_document` field, written by
     `sdp-new-concept-intake` Step 4 item 5. If present, read the file(s) it points to under
     `sdp-solution-docs/user-design-docs/processed/` — if it has an accompanying
     `[doc_name]_Sections/[doc_name]_TOC.md` folder, read the TOC first and process section-by-
     section (same convention `sdp-source-coverage-check` uses — never load a large parent doc in
     one pass). If the field is absent (conversational intake — no tracked source exists for this
     cycle): skip this bullet, nothing to read.
   - **`"Expanded Concept"` only, additionally:** read `sdp-solution-docs/01_concept.md` and
     `sdp-solution-docs/02_research_findings.md`.

   Bring whatever was read into the brainstorming session as the material being expanded, merged,
   or drafted from — per the bootstrap doc's Phase 3 Mechanics entry. This is a proactive
   complement to `sdp-source-coverage-check`, not a replacement for it — that check still runs as
   the mandatory backstop after drafting; reading the original source up front is meant to reduce
   how much it has to catch, not substitute for the audit.

   **State what was read, by name, before opening the brainstorming conversation** — e.g. "I have
   the tracked source (`user-design-docs/processed/[filename]`), `01_concept.md`, and
   `02_research_findings.md` (6 angles) loaded." A summary that only gestures at "the tracked
   source" without naming the actual file read is not sufficient — the user has no way to tell
   from that phrasing whether `source_document` was actually resolved and its file actually read,
   or whether this bullet was silently skipped (e.g. because the field was absent). Tool-call
   transcript entries showing the Read happened are not a substitute for this — the user should
   not have to scroll back through raw tool calls to confirm what COORDINATOR already knows it
   read. If no tracked source exists for this cycle (conversational intake), say that explicitly
   too — "no tracked source document for this cycle" — rather than omitting the line silently.

   Transcribe every decision, constraint, and design choice surfaced into the phase document
   (append-only) before this session closes — do not leave brainstorming output only in chat
   history. Then proceed to item 4: WORKER is still dispatched as normal, and its job is to
   finish/formalize the phase document to the task's full spec from the material just captured,
   not to originate Phase 1/3 content from nothing.
3b. **[Pros-Cons-Gaps cycle setup]** When step 2's algorithm determined the dispatch target is
   **REVIEWER** and `current_phase` is `"Architecture"` or `"Implementation Overview"`: before
   writing the session dispatch file (item 4 below), read this phase's own `[phase]_state.json`.
   If it has no `pros_cons_gaps` object yet (this is the first REVIEWER dispatch for this task):
   write one directly to that file — `{"cycle_target": 2, "cycle_count": 0}`. Use a target higher
   than 2 only when there is a concrete complexity signal already on record for this phase (e.g.
   an unusually large open-question count noted during drafting) — do not prompt the user for a
   number as a matter of routine; 2 is the default per the bootstrap doc's Pros-Cons-Gaps Cycle
   section. If `pros_cons_gaps` is already present (a later cycle for the same task): leave it
   unchanged here — `sdp-solution-phase-reviewer` owns incrementing `cycle_count` itself.
4. **[TARGETED FIX]** When a dispatch target is found (REJECTED/PENDING task in `current_phase`,
   or GATE_REVIEWER when all tasks in `current_phase` are VERIFIED): write the session dispatch
   file **directly** — `sdp-solution-create-prompt` does not write session files (confirmed: its
   own Inputs/Constraints never included this, in either its shared-task or phases-1-7 branch;
   the original Step 2a text delegating this to it was simply wrong). Read `last_session` from
   `.sdp-solution-workflow/state.json`, increment it, and write
   `.sdp-solution-workflow/sessions/session-NNN.md` directly with:
   ```
   Role: [WORKER|REVIEWER|GATE_REVIEWER]
   Work Item: [current_phase]
   Bootstrap Doc: [resolved bootstrap doc filename]
   Phase Document: sdp-solution-docs/[NN_phase_name].md
   Solution State File: .sdp-solution-workflow/state.json
   Re-Gate Trigger: [GATE_REVIEWER dispatches only, and only on a re-gate cycle — Step 2e's
     Re-gate path (gate_review_attempts was 0) or Real-prior-block path (gate_review_attempts was
     >= 1): summarize the trigger per Step 2e item 0. Omit this line entirely for WORKER/REVIEWER
     dispatches and for a genuine first-ever gate cycle.]
   Instruction: Invoke `/sdp-solution-phase-worker` | `/sdp-solution-phase-reviewer` | `/sdp-solution-phase-gate-review` (matching Role)
   ```
   No `Project:` field — this is a solution-scoped dispatch. Then write the incremented
   `last_session` back to `.sdp-solution-workflow/state.json` directly — a narrow, explicit
   exception to the "script owns every write" constraint (Constraints below), scoped to exactly
   this field on this path, mirroring the exception already granted for the Step 0
   preflight-halt write.
5. Proceed to Step 3, which for this path invokes `sdp-solution-create-prompt` to write the
   **prompt text** (`sdp-solution-docs/00_solution_prompt.txt`) — a separate file from the
   session dispatch file just written in item 4 above, serving a separate purpose (the
   self-contained prompt a new subagent session reads, per `sdp-solution-run-prompt`'s job).

### Step 2b: Phase 7 Dependency-Declaration Support

Runs only when Step 2a's dispatch target is Phase 7's ("Phase Readiness") decomposition work
itself (i.e., the WORKER task being dispatched is the decomposition task, not a downstream
GATE_REVIEWER pass). This step augments the session file item 4 above writes directly.

Include in the WORKER session's instructions (added to the session file content):

0. **Populate `.speq.md` and `[PROJECT]-Context.md` for every project receiving decomposed tasks
   for the first time this cycle** — before assigning that project's registry rows (item 1
   below). `sdp-workspace-setup`'s Add-Project Steps already created these as empty template
   stubs; this is the first point where the actual settled decisions exist to populate them with.
   For each such project: read the sections of `sdp-solution-docs/04_architecture.md` and
   `sdp-solution-docs/05_implementation_overview.md` applicable to it (a solution-scoped document
   may cover more than one project), and replace the stub content with the real tech stack,
   naming conventions, file structure, and product-shape decisions already recorded there — do
   not originate new decisions here, only transcribe already-settled ones. A project re-entering
   decomposition in a later mid-stream cycle (its `.speq`/Context already populated from a prior
   cycle) is unaffected — this item applies only the first time a project receives tasks.
1. **Assign each decomposed build-phase task to a specific project** — the first moment a
   project's own `.sdp-workflow/registry.md` is populated, with only its assigned implementation
   tasks (never phase 1-6 documents, which never exist at project scope). Item 0 above must
   complete for a project before its rows are assigned here.
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
   narrative) and `.sdp-solution-workflow/dependencies.json` (the machine-readable index above).
   Owned exclusively by this skill — no project-level skill ever reads or writes either file.

Confirm outcome (Step 5) reads `.sdp-solution-workflow/dependencies.json` back to verify it
parses and every edge has the required fields, in addition to the existing phase state file
confirmation — and, for each project that received tasks for the first time this cycle, confirms
its `.speq.md`/`[PROJECT]-Context.md` no longer contain template placeholder markers (item 0).

### Step 2c: Light Resolution Mechanics

Runs every invocation once Phase 7 has passed for this solution (`current_phase` is `null` per
Step 2a item 3) and `.sdp-solution-workflow/dependencies.json` contains at least one non-`GREEN`
edge. This step resolves ledger lights; it does not itself decide whether to dispatch a project's
coordinator this cycle — that is Step 2d.

**RED → GREEN (mechanical, no new mechanism):** for each `RED` edge, read the producer project's
own `[phase]_state.json` — already necessary for outcome detection. Once that specific task
reaches `VERIFIED` (via the project's own, completely ordinary REVIEWER cycle), flip the edge to
`GREEN` in `.sdp-solution-workflow/dependencies.json`. No dependency-specific action required
from anyone else.

**YELLOW → BLUE → GREEN (or back to YELLOW), mirroring WORKER/REVIEWER separation:**

1. For each `YELLOW` edge: read the producer task's phase document / state file (standard outcome
   detection, never subagent text) and check whether its Completed blockquote addresses the
   decision the edge is waiting on (the acceptance criterion baked in at Step 2b item 3).
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
`SDP-Config.json`'s `autoResolveHalt.dependencyAttemptThreshold` (same convention as the existing
`evalCycleAttemptThreshold`; default 2 if absent). When any edge's `light_attempts` reaches or
exceeds this threshold: set `workflow_status` to `"halted"` in `.sdp-solution-workflow/state.json`,
`halt_reason` = `"Dependency edge [consumer task] → [producer task/decision] has been stuck at
[light] for [light_attempts] cycles with no progress — human review required."` — surfaced via
the existing Halt Behavior Contract.

### Step 2d: Post-Phase-7 Dispatch Gating

Runs every invocation once Phase 7 has passed for this solution. Decides, for each project not
currently a shared-task child of `sdp-solution-coordinator`'s own dispatch, whether to dispatch
that project this cycle — and, if so, whether that means executing its already-fresh dispatch or
generating a new one (item 4 below).

1. **Next-actionable-task peek.** For each candidate project, read its `.sdp-workflow/registry.md`
   and `state.json`, and duplicate `sdp-project-coordinator/SKILL.md` Step 4's task-discovery logic
   (REJECTED-priority over PENDING, dependency-blocked checks against the project's own registry,
   `phase_gate.status` branching) to determine what task that project's `sdp-project-coordinator` would
   dispatch next, *without* actually invoking `sdp-project-coordinator`. This is a second, independent
   duplication of the same algorithm Step 2a already duplicated for solution-scoped phase
   advancement — same drift-risk note applies. This peek produces one of three local outcomes,
   feeding both the dispatch decision below and the status recorded in item 6:
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
   state to communicate the block.
4. **Dispatch every `work_pending` project, and every `blocked` project too — only `waiting`
   projects are never dispatched.** A `blocked` project is always dispatched via 4c
   (`/sdp-project-coordinator`) directly — never via 4a's freshness check or 4b's execute-
   shortcut, neither of which has any halt check of its own (`/sdp-project-run-prompt`'s only
   halt detection is a literal `'Workflow halted'` first-line string match, never actually
   written under the current halt convention; neither `sdp-project-worker` nor
   `sdp-project-pre-work-verify` check `workflow_status` themselves). A blocked project's
   dispatch exists solely so `/sdp-project-coordinator`'s own halt/`DIAGNOSIS_BLOCKED` detection
   can surface the reason to the user — routing it through the execute-shortcut instead would
   dispatch a real WORKER/REVIEWER/GATE_REVIEWER session into a halted project with nothing in
   the chain to stop it. For a `work_pending` project, perform the following two-branch dispatch.

   **4a. Evaluate sentinel freshness** — duplicate `sdp-project-state-loop`'s Step 4 (Evaluate
   Sentinel) comparison exactly, scoped to this project. No project-resolution ambiguity exists
   here — item 1's peek already identified this project and what it expects to dispatch next.
   Read the first line of `[project]/sdp-docs/00_prompt.txt` and compare against current state:
   for a GATE_REVIEWER sentinel, compare `work_item` to `current_phase` and `expected_status` to
   `phase_gate.status`, then run the dispatch-file integrity check (the referenced session file
   exists, and its `Role:`/`Work Item:` lines match); for any other sentinel role, compare
   `work_item` to the project's `active_work_item` and `expected_status` to that task's current
   `status`. This is a third independent duplication of logic living elsewhere in this codebase
   (alongside item 1's duplication of `sdp-project-coordinator` Step 4 and Step 2a's duplication of
   the same) — same drift-risk note applies: keep in sync with `sdp-project-state-loop` Step 4 if
   that step ever changes.

   **4b. Fresh (comparison matches, integrity check passes if applicable):** dispatch a subagent
   with the instruction: "Invoke `/sdp-project-run-prompt` with `[project_path]` as its invocation
   argument, to execute the current dispatch prompt for that project." Always pass the project
   path as a literal, explicit argument — never phrase this as descriptive prose alone ("for that
   project") — so `sdp-project-run-prompt`'s own explicit-argument resolution fires
   deterministically and never falls through to `SDP-Solution.json.last_active_projects`. This is
   the branch that actually executes the pending WORKER/REVIEWER/GATE_REVIEWER.

   **4c. Stale, or first dispatch for this task:** write a session dispatch file directly (same
   pattern as Step 2a item 4, but `Role: WORKER` or `Role: REVIEWER` and a `Project:` field naming
   that project — this is an ordinary per-project dispatch, not a solution-scoped one) and
   dispatch a subagent with the instruction: "Invoke `/sdp-project-coordinator` with
   `[project_path]` as its invocation argument, for that project." Same explicit-argument
   requirement as 4b — pass the project path literally, never as prose alone, so
   `sdp-project-coordinator`'s own Level 0 fires and Level 3 (`last_active_projects`) is never
   consulted. This writes a fresh, correct dispatch; it will be picked up and executed by 4a/4b
   the next time this project is classified `work_pending` (never `blocked` — a blocked project
   always stays on the 4c path per item 4's opening rule, regardless of sentinel freshness) —
   mirroring the exact GENERATE-then-EXECUTE two-fire cadence `sdp-project-state-loop` already
   uses for single-project regimes, just spread across solution-loop cycles instead of
   project-loop cycles. Reusing
   `sdp-project-state-loop`'s own sentinel-freshness judgment inline (4a), rather than invoking
   that skill directly, is deliberate: it has no invocation-argument override of its own and would
   be forced to resolve via `SDP-Solution.json.last_active_projects[0]`, unsafe when this step
   dispatches more than one project in the same cycle.

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
   a full array replace, not an append, mirroring `sdp-solution-coordinator.ps1`'s own
   `last_active_projects` write for the shared-task path (`Select-Object -Unique` over that
   cycle's dispatched set). Update `updated` alongside it. Apply the replace uniformly, including
   the empty case: if no project clears this cycle, set `last_active_projects` to `[]` rather than
   leaving a stale value in place. A stale non-empty entry is not just inaccurate — it is a
   fallback hazard: `sdp-project-coordinator`'s own Level-3 fallback would read it on a later bare
   invocation and dispatch that project directly, bypassing this step's dependency-ledger check
   entirely, since `sdp-project-coordinator` never reads `dependencies.json` and has no way to
   know the project it was just pointed at is still blocked.

   **`sdp-project-coordinator` must never perform this write itself.** It runs as an isolated,
   project-scoped subagent (Role Separation) with no visibility into which sibling projects this
   same cycle also cleared — a per-project write would silently collapse the array to whichever
   project's subagent wrote last, and falls outside that skill's own closed file-write list
   (`sdp-project-coordinator/SKILL.md` Constraints), which contains nothing outside
   `[resolved_project]/`. Only this skill sees the complete cycle's dispatch set.
6. **Record each project's per-cycle status — full coverage, every registered project, every
   cycle.** After items 1-2 have classified every candidate project this cycle: for each entry in
   `SDP-Solution.json`'s `projects[]` array, set a `status` field to one of `work_complete` /
   `work_pending` / `waiting` / `blocked` (the classification from items 1-2, for candidate
   projects) or `in_shared_task` (for any registered project excluded from this cycle's
   candidates because it is currently a shared-task child of `sdp-solution-coordinator`'s own
   dispatch — Step 2d's own exclusion, per its opening paragraph). Update `updated` alongside it.
   Every registered project gets a fresh value every cycle this step runs — never leave a
   project's prior-cycle `status` value in place uncorrected: a stale `status` is a display
   hazard, not just an inaccuracy — `sdp-initialize-sdp` reads it verbatim into its closing
   banner, and a stale `work_pending` on a project that has since gone `blocked` (or vice versa)
   would misdirect the user's next action.

   **No skill may treat this field as authoritative for a dispatch decision** — item 1/2's live
   peek is the only authoritative source for whether a project actually clears this cycle;
   `status` exists solely so a later, unrelated session (a fresh `sdp-initialize-sdp` run, in
   particular) can tell "all work genuinely complete" apart from "work exists but nothing cleared
   this cycle" without re-deriving items 1-2's classification a third time. As with
   `last_active_projects`, `sdp-project-coordinator` must never write this field — it has no
   visibility into sibling projects, no visibility into whether it is itself a shared-task child
   this cycle, and no mandate to write anything outside `[resolved_project]/`.

### Step 2e: Solution-Level Phase 7 Backward-Regression

Mirrors `sdp-project-coordinator/SKILL.md` Step 4 sub-step 5's `"blocked"` branch exactly (duplicated, not
called — boundary invariant), operating on the solution's own state instead of a project's. Runs
whenever Step 2a finds `phase_gate.status == "blocked"` for the solution's `current_phase`.

0. **Disambiguate first, using `phase_gate.gate_review_attempts` — never blockquote content, and
   never assume the relevant document is `07_phase_readiness.md`.** `phase_gate.status ==
   "blocked"` means one of two distinct things: a real `sdp-solution-phase-gate-review` verdict
   returned GATE_BLOCKED for whatever phase is *currently* current, or item 3.b below force-set it
   on a target/intermediate phase to require a fresh gate. Append-Only Discipline means
   `07_phase_readiness.md`'s Remediation Proposals heading, once written, is never removed — so
   checking that fixed file unconditionally, regardless of what `current_phase` actually is, would
   make every later `"blocked"` occurrence for any phase misread as "the same unresolved
   proposals," forever, once a single regression has ever happened. Instead:
   - **`gate_review_attempts == 0`:** No `sdp-solution-phase-gate-review` has fired against this phase since
     `"blocked"` was most recently set — a real GATE_BLOCKED verdict always leaves
     `gate_review_attempts >= 1` (the counter increments the moment a GATE_REVIEWER dispatch
     fires). This can only mean item 3.b just force-set it and this phase's fresh WORKER → REVIEWER
     cycle has now reached all-VERIFIED. Treat exactly like a first gate: dispatch
     `sdp-solution-phase-gate-review` via Step 2a's normal dispatch logic (item 4), including a
     `Re-Gate Trigger:` line in the session file summarizing the triggering entry from
     `phase_readiness.regressions[]` (target phase, date, chosen remediation). Do not perform
     steps 1-2 below for this branch — there is no blockquote to check.
   - **`gate_review_attempts >= 1`:** A real verdict exists. Proceed to step 1, which reads *the
     current phase's own document* — `sdp-solution-docs/[NN_phase_name].md` per Step 2a item 4's
     naming (e.g. `06_refined_implementation_plan.md`, not always `07_phase_readiness.md`) — not a
     hardcoded path.
1. Check whether the GATE_BLOCKED blockquote in the current phase's own document (resolved above)
   contains a `**Remediation Proposals:**` heading (always produced by `sdp-solution-phase-gate-review`
   for a Phase Readiness gate at this scope — see the disambiguation note above for why this
   heading can only appear when `current_phase` actually is "Phase Readiness").
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
      and increment `phase_readiness.regression_count` by 1.
   e. Proceed to Step 2a's normal dispatch logic for the new `current_phase`.
4. **No Remediation Proposals heading (a normal, non-Phase-Readiness gate block):** halt per the
   existing generic gate-blocked handling — unchanged from how any other phase's GATE_BLOCKED
   verdict is already surfaced.

### Step 3: Invoke sdp-solution-create-prompt — **[TARGETED FIX: phases-1-7 branch]**

**Step 2a path only:** Invoke `sdp-solution-create-prompt` (via the Skill tool)
to write `sdp-solution-docs/00_solution_prompt.txt`. Provide `role`: the WORKER/REVIEWER/
GATE_REVIEWER value determined in Step 2a item 4; no `projects` value (a Step 2a dispatch is
always solution-scoped, never per-project). This exercises `sdp-solution-create-prompt`'s
existing phases-1-7 branch (`mode: "phases_1_7"`), added when that gap was originally closed.

**Step 2d path: skip this step entirely — do not invoke `sdp-solution-create-prompt`.** A Step 2d
per-project dispatch is already complete once item 4 runs: it writes its own session file
directly and dispatches a subagent whose job is to invoke `/sdp-project-coordinator` for that
project — a fully self-contained project-level flow that writes its own `sdp-docs/00_prompt.txt`
and needs no solution-level prompt file. `sdp-solution-create-prompt`'s backing script has no
mode for `current_phase: null` with no `active_solution_task` (exactly the regime Step 2d always
runs in) and was never meant to — its two modes (`shared_task`, `phases_1_7`) each assume a
single dispatch target, but Step 2d can dispatch multiple projects in one cycle (item 4: "dispatch
every `work_pending` project"), which a single `sdp-solution-docs/00_solution_prompt.txt` cannot
represent anyway. Proceed directly to Step 4 for a Step 2d dispatch.

**Shared-task path (dead code here — see Constraints):** Invoke `sdp-solution-create-prompt` with
`role: "SOLUTION_COORDINATOR"` and `projects`: comma-separated list of the `project` field from
every entry in the result's `laggards` array — unchanged from `sdp-solution-coordinator`.

### Step 4: Dispatch Subagents — **[TARGETED FIX: phases-1-7 branch]**

**Phases-1-7 path:** Dispatch one subagent using the session file written directly in Step 2a
item 4 (or Step 2d item 4) as its prompt, invoking the skill named in that file's `Instruction:`
field (`sdp-solution-phase-worker`, `sdp-solution-phase-reviewer`, `sdp-solution-phase-gate-review`, or
— Step 2d only — `sdp-project-coordinator` for a per-project dispatch). Wait for it to complete.

**Shared-task path (dead code here):** Branch on `solution_reviewer_dispatch` and `dispatch_mode`
from the script result exactly as `sdp-solution-coordinator` does — parallel/sequenced dispatch
across `session_files_written`.

### Step 5: Confirm Outcomes — **[TARGETED FIX: phases-1-7 branch]**

**Phases-1-7 path:** After the dispatched subagent returns: re-read `.sdp-solution-workflow/
state.json` (never the subagent's own text) to confirm the outcome — task status advanced to
`WORK_COMPLETE`/`VERIFIED`/`REJECTED`, or `phase_gate.status` updated for a GATE_REVIEWER
dispatch. Note whether further dispatch is needed on the next invocation.

**Shared-task path (dead code here):** For each entry in `laggards`, read its `state_file` to
confirm the outcome — unchanged from `sdp-solution-coordinator`.

### Step 6: Terminate

Do not re-invoke this skill internally — each invocation is one dispatch cycle only. If Step 5
shows further dispatch is needed, that happens on the next `sdp-solution-phase-coordinator`
invocation, not within this session.

## Constraints

- **This skill never handles shared-cross-project-task dispatch** — that is
  `sdp-solution-coordinator`'s exclusive job. The copied script and SKILL.md sections describing
  that path (Step 1's `"success"` branch onward, the shared-task halves of Steps 3/4/5) are kept
  as an unmodified copy rather than stripped out — by construction, this skill is only ever
  invoked when `active_solution_task` is null, so that path should never actually fire here. This
  is a deliberate trade-off: leaving proven, working code in place, even unused, carries less risk
  than restructuring it out.
- Never touch implementation files, source code, or project phase section files.
- For the phases-1-7 path: the LLM writes the session dispatch file and the incremented
  `last_session` directly (Step 2a item 4) — a narrow, explicit exception to "the script owns
  every write," scoped to exactly this path, mirroring the Step 0 preflight-halt exception already
  granted in the original skill.
- For Step 2d only: the LLM also writes `last_active_projects` and `updated` directly in
  `SDP-Solution.json` (Step 2d item 5) — a second narrow, explicit exception alongside the one
  above, scoped to exactly this field. This is the only point in the phases-1-7 path that touches
  `SDP-Solution.json` directly; Step 2a's own solution-scoped dispatch never does, since no
  project is dispatched there.
- For the shared-task dead-code path: do not read or write `.sdp-solution-workflow/state.json`,
  `SDP-Solution.json`, or session files directly — unchanged from `sdp-solution-coordinator`.
- Do not invoke `sdp-project-coordinator` for a project directly — dispatch a subagent whose instruction
  is to invoke it (Step 2d), exactly like every other dispatch this skill performs.
- Never loop internally or re-invoke this skill after a dispatch cycle completes — each invocation
  is exactly one cycle, then terminate.
- A `"blocked"` or `"cascade"` result (shared-task dead-code path) blocks all dispatch — do not
  proceed to Step 3 when either is returned.
- Script calling convention: `sdp-solution-phase-coordinator.ps1` is called with no arguments (it
  self-resolves the solution root).
- Never invoke `sdp-solution-coordinator`, and is never invoked by it.

## Outputs

- `.sdp-solution-workflow/sessions/session-NNN.md` — written directly by this skill for the
  phases-1-7 path (Step 2a item 4, and Step 2d item 4c only — item 4b executes an already-fresh
  dispatch and writes no new session file); written by the script for the shared-task dead-code
  path
- `.sdp-solution-workflow/state.json` — `last_session` (written directly for the phases-1-7 path;
  by the script for the shared-task path), `current_phase`/`phase_gate` advancement, dependency
  ledger state, `migration_checked`
- `SDP-Solution.json` — `last_active_projects` (Step 2d item 5: full-replace with the set of
  projects cleared and dispatched this cycle), `projects[].status` (Step 2d item 6: every
  registered project's `work_complete`/`work_pending`/`waiting`/`blocked`/`in_shared_task`
  classification, refreshed in full every cycle), and `updated` — all written directly by this
  skill
- `.sdp-solution-workflow/dependencies.json`/`.md` — written at Phase 7 decomposition, updated by
  light-resolution mechanics
- `sdp-solution-docs/00_solution_prompt.txt` — written by `sdp-solution-create-prompt` (Step 3,
  Step 2a dispatches only — never written for a Step 2d per-project dispatch)
- Each affected project's own `.sdp-workflow/registry.md` — populated at Phase 7 decomposition
- User-facing notification of dispatch targets, halt, blocked flag, or completion as applicable
