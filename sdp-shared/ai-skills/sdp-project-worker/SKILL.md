## Purpose

Execute a WORKER session: verify preconditions, load task context from the session dispatch
file and phase file, run pre-work verification, implement the assigned task, and record
completion. A WORKER session never evaluates its own output against acceptance criteria —
session ends after the state file is updated.

## Inputs

All paths below are relative to `[resolved_project]` (resolved in Step 1 item 1 below).

- `[resolved_project]/.sdp-workflow/sessions/session-NNN.md` — role assignment, task ID,
  phase file path, flags, `Project:` field, and any COORDINATOR instructions. Session number
  is read from `[resolved_project]/.sdp-workflow/state.json`'s `last_session` field.
- Phase document — path given as `active_phase_file` in `[resolved_project]/.sdp-workflow/state.json`,
  or the session dispatch file's "Phase file path" field if `active_phase_file` is absent; task
  description and full task spec. Do not reconstruct this path from a `[doc_name]_Phases/[phase_name].md`
  convention — not every project uses that folder layout.
- Phase state file — the phase document's path with its trailing `.md` replaced by `_state.json`;
  confirms assigned task ID, status, and flags
- `[resolved_project]/.sdp-workflow/state.json` — `gpg_version`, `last_session`, assigned phase file path
- `[resolved_project]/[AppName].speq.md` — tech contract (stack, naming, file structure)

## Procedure

### Step 1: Verify Preconditions

1. **PROJECT RESOLUTION** — Resolve the target project using the two-level priority order
   below. Use the first level that yields a result; do not check subsequent levels.

   **Level 1 — Dispatch context (authoritative for formally dispatched subagents):**
   Read the session dispatch file (`sessions/session-NNN.md` — session number from
   `state.json`'s `last_session` field, or from the opening prompt context). If it contains a
   `Project:` field, use that value as `[resolved_project]`. This value is written at dispatch
   time by the coordinator and is locked for this session's lifetime.

   **Level 2 — Physical path extraction (deterministic fallback, no I/O required):**
   If no `Project:` field is present in the session file (e.g., an older session file written
   before this convention was adopted), examine the path of the session file being processed.
   If the path contains an `sdp-project_*` segment, that segment is `[resolved_project]`
   (e.g., `sdp-project_VirtualCoinFolio.API/.sdp-workflow/sessions/session-042.md`
   → `[resolved_project]` = `sdp-project_VirtualCoinFolio.API`).
   If the path contains no `sdp-project_*` segment, this is a solution-level file; no single
   project applies — halt and notify the user.

   Once resolved, all file paths in subsequent steps are built under `[resolved_project]/`.
   For single-project workspaces where `last_active_projects` is `["."]`,
   `.\.\[path]` resolves to `.\[path]` — identical to current single-project behavior.

2. **GPG CHECK** — Read `[resolved_project]/.sdp-workflow/state.json` and note the
   `gpg_version` field. Verify that `standards/GenericProjectGuidlines_V[version].md` exists.
   If missing: halt per the Halt Behavior Contract — set `workflow_status` to `"halted"` in
   `[resolved_project]/.sdp-workflow/state.json`, add `halt_reason`, notify the user by invoking
   `/sdp-create-banner icon=error row=0 row: Status | Halted — [reason]. Resolve this condition
   and run COORDINATOR to resume.`, and terminate. Do not proceed with implementation until the
   GPG file is present.
   Also record the halt (non-blocking — ignore any failure and continue): run
   `./sdp-shared/scripts/sdp-workflow-log.ps1 -trigger "halt.generic" -role "WORKER" -outcome
   "HALTED" -reason "[halt_reason]"` via the PowerShell tool.
3. **SUPERPOWERS CHECK** — Verify Superpowers plugin is installed by running `/plugin list`.
   - If installed: apply TDD for all implementation (tests must fail before implementation
     begins); apply four-phase root cause methodology before any fix attempt; invoke skills
     explicitly only — auto-triggering is prohibited; do NOT use `/execute-plan` review
     checkpoints under any circumstances.
   - If missing: apply equivalent TDD and debugging discipline manually as described in the
     session dispatch file.
   - Note: "Superpowers" here refers to the SP plugin (Jesse Vincent), not to SDP skills.

### Step 2: Load Session Context

1. Read the bootstrap document (`SDP_Sapient-Driven-Principles_v*.md`) — review the WORKER role
   definition and state machine before proceeding.
2. Read the session dispatch file (`[resolved_project]/.sdp-workflow/sessions/session-NNN.md`
   — session number from `[resolved_project]/.sdp-workflow/state.json`'s `last_session`
   field). Confirm role assignment is WORKER. Note any flags or Superpowers instructions
   included by COORDINATOR.
3. Read `[resolved_project]/.sdp-workflow/state.json` — confirm the assigned task ID, phase
   file path, and any flags.

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

### Step 3: Load Task Context

1. If the assigned task is in an architecture or design phase: read the relevant GPG section
   file(s) before reading the task. Note applicable GPG patterns before forming an approach.
   Read `[resolved_project]/[AppName].speq.md` to load the tech contract before forming
   an implementation approach.
2. Read the full phase file — the `active_phase_file` path from
   `[resolved_project]/.sdp-workflow/state.json` (or the session dispatch file's "Phase file
   path" field if `active_phase_file` is absent) — understand the assigned task in the context
   of the full phase.
3. State what the assigned task requires before starting work. Proceed without waiting for
   user confirmation unless the restatement reveals an interpretation conflict — in that case,
   pause and state the conflict explicitly.
4. If the task has a prior non-compliant Eval blockquote: read it carefully before beginning
   work. The corrective notes from the REVIEWER are the starting point.
   If Superpowers is installed: invoke `/receiving-code-review` before beginning corrective
   work. This skill enforces structured processing of the REVIEWER's feedback before
   implementation begins — preventing blind re-implementation that misses the root finding.
5. **Parallel pre-implementation research (before Step 4).** Group the reads needed to
   form an implementation approach and dispatch them in parallel:

   - **Architecture/design phases — GPG pattern reads:**
     Spawn one `general-purpose` sub-agent per applicable GPG chapter:
     > "Read [GPG chapter file]. Return only the patterns and rules directly applicable to
     > [task description]. Under 150 words. Do not summarise sections not relevant to the task."
     Receive summaries before proceeding to Step 4. Do not read GPG chapters sequentially
     in the main context when multiple chapters apply.

   - **Implementation phases — codebase context reads:**
     Spawn an `Explore` sub-agent to map existing code relevant to the task:
     > "Find all files in [scope] that define or use [interfaces / modules / types] this
     > task will touch. Return file paths and relevant symbol names only. Do not analyse."
     Then spawn `general-purpose` sub-agents for each located file:
     > "Read [file]. Return: the public interface (function signatures, class definitions),
     > any conventions visible in the file (naming, error handling, logging), and anything
     > that constrains how new code must integrate. Under 200 words."
     Receive summaries before forming the implementation approach in Step 5. Do not load
     full source files into the main context when a summary is sufficient.

   If Superpowers is installed and 2 or more independent research reads are needed: optionally
   invoke `/dispatching-parallel-agents` to structure the parallel dispatch.

### Step 4: Pre-Work Verification

1. Invoke `/sdp-project-pre-work-verify` to scan for prior artifacts, classify task state, and
   determine whether to proceed, resume, or skip.
2. Act on the outcome before continuing:
   - **Not Started** — proceed to Step 5.
   - **In Progress / Incomplete** — await user confirmation before continuing.
   - **Complete** — do not proceed to Step 5. Notify COORDINATOR that the task is already done.

### Step 5: Implement the Task

1. Perform all work required by the task description. Address every sub-step and constraint
   in the task spec.
2. Apply TDD: write failing tests before implementation. If Superpowers is installed, invoke
   `/test-driven-development` before writing any implementation code.
3. For any blocking issue or defect encountered during implementation: apply four-phase root
   cause analysis before attempting a fix. If Superpowers is installed, invoke
   `/systematic-debugging` before any fix attempt.
4. Do not evaluate the completed work against acceptance criteria — that is the REVIEWER's role.

### Step 5a: Verify Before Recording Completion

1. If Superpowers is installed: invoke `/verification-before-completion` now — before marking
   the checkbox or writing the Completed blockquote. This step confirms build passes, tests
   pass, and observable behavior matches the task spec.
2. Do not proceed to Step 6 until verification passes or any failures are resolved and retested.

### Step 6: Record Completion and Update State

1. Mark the task checkbox `[x]` in the phase file (the path noted in Step 3.2).
2. Append a Completed blockquote to the phase file immediately after the task item:
   ```
   > **Completed: [YYYY-MM-DD HH:MM]** — [What was done. Decisions made. Any deviations from
   > spec and why. Build/compile status — e.g. "build passes 0 errors, 0 warnings".]
   ```
   Include explicit build/compile status. If a deploy step is required, append a Deploy
   blockquote per the bootstrap document's deploy annotation pattern.
3. Update the phase state file (the phase file's path with `.md` replaced by `_state.json`):
   - Set the task's `status` to `"WORK_COMPLETE"`
   - Set `last_session` to the current session identifier
   - Set `last_updated` to today's ISO date
   - Do **not** write, add, or modify `eval_cycle_attempts` — that field is owned solely by
     `sdp-project-state-loop` (see the bootstrap Stuck-Loop Detection table). Writing it from a WORKER
     session corrupts REVIEWER-attempt accounting and can trigger a false-positive halt. Leave
     any existing `eval_cycle_attempts` value exactly as found; if it is absent, do not add it.
4. Mirror all phase file changes to the parent document per the sync rule notice in the
   phase file header.
5. Commit all work: run `git status` to identify every untracked and modified file. Stage
   and commit ALL project files not covered by `.gitignore` — do not enumerate a specific
   file list. This includes implementation files, test files, fixtures, phase file changes,
   and state file updates from this and any prior uncommitted sessions. ~~Push to the remote
   branch.~~ Push via `./sdp-shared/scripts/sdp-github.ps1 push` (PowerShell tool) — read the
   JSON envelope: `status: "pushed"` means the push succeeded; an `ok:false` / `status:"error"`
   envelope means the push failed (surface it and do not mark the task complete). Record the
   short commit hash in the Completed blockquote.
6. **CI-green gate (only when `SDP-Config.json` `ci.enabled` is true).** After a successful
   push, run `./sdp-shared/scripts/sdp-github.ps1 ci-status` and branch on the JSON `status`:
   - `green` — proceed to record completion.
   - `red` — do **not** mark the task complete. Read the failed-job detail
     (`failedJobs` / `run-log-failed`), apply four-phase root cause analysis (invoke
     `/systematic-debugging` if Superpowers is installed), fix, re-commit, re-push, and
     re-run `ci-status`. This is the four-phase escalation loop — repeat until `green` or a
     genuine blocked diagnosis is reached.
   - `no_ci` / `unreachable` — CI is not configured or the remote is not reachable; proceed
     with the local-green result and **disclose the caveat** in the Completed blockquote
     (e.g. "CI gate returned no_ci — completion is local-green only").
   - `timeout` — the run did not appear/conclude within `ci.waitTimeoutSeconds`; halt per the
     Halt Behavior Contract rather than guessing the outcome.
   When `ci.enabled` is false or absent, `ci-status` returns `no_ci` and this gate is a no-op
   (today's local-green behavior).
7. Record completion (non-blocking — ignore any failure and continue): run
   `./sdp-shared/scripts/sdp-workflow-log.ps1 -trigger "worker.complete" -role "WORKER"
   -workItem "[task ID]" -outcome "WORK_COMPLETE" -reason "[one sentence: what was done, and
   any deviation from spec and why]"` via the PowerShell tool.
8. Session ends. Do not proceed to evaluate or verify the completed work.

## Constraints

- A single WORKER session handles exactly one assigned task. Do not begin a second task.
- Never evaluate own output against acceptance criteria — session ends after state update.
- `/execute-plan` review checkpoints are prohibited — they violate Bootstrap context isolation.
- Never skip TDD or four-phase debugging discipline merely because Superpowers is not
  installed — apply both manually in that case.
- Do not mirror changes to files outside the assigned phase file and its parent document.
- Never write `eval_cycle_attempts` in the phase state file — it is owned solely by
  `sdp-project-state-loop`. A WORKER write to this field is a stuck-loop accounting corruption.
- Never mark the task complete when a push fails or CI returns `red` — resolve the failure
  (re-commit, re-push, or fix and re-run CI) before recording completion.

## Outputs

- Phase file (path noted in Step 3.2) updated: task checkbox `[x]`, Completed blockquote appended
- Parent document updated: mirrors phase file changes per sync rule
- Phase state file (phase file path with `.md` replaced by `_state.json`) — task status →
  `WORK_COMPLETE`, `last_session`, `last_updated`
- `.sdp-solution-workflow/logging/workflow-logs/workflow-log-<local-yyyyMMdd>.jsonl` — one
  `worker.complete` entry recording the outcome and rationale (non-blocking side effect, via
  `sdp-workflow-log.ps1`)
