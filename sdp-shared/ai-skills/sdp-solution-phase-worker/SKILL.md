## Purpose

Execute a WORKER session for one of the solution's own phases 1-7 (Concept through Phase
Readiness): verify preconditions, load task context from the solution-level dispatch and phase
document, run pre-work verification, implement the assigned phase task, and record completion.
This is the solution-scoped counterpart to `sdp-project-worker` — same role, same discipline, different
root. Never invoked for project-level tasks, and `sdp-project-worker` is never invoked for phases 1-7 —
each skill exists for exactly one scope, permanently.

A WORKER session never evaluates its own output against acceptance criteria — session ends after
the state file is updated.

## Inputs

All paths below are relative to the solution root — there is no project to resolve.

- `.sdp-solution-workflow/sessions/session-NNN.md` — role assignment, phase identifier, phase
  document path, flags, and any COORDINATOR instructions. Session number is read from
  `.sdp-solution-workflow/state.json`'s `last_session` field. Never carries a `Project:` field —
  its absence is the signal this is a solution-scoped dispatch (`sdp-solution-phase-coordinator`
  Step 2a item 4 deliberately omits it).
- Phase document — `sdp-solution-docs/[NN_phase_name].md` (e.g. `sdp-solution-docs/01_concept.md`,
  `sdp-solution-docs/07_phase_readiness.md`), named by `current_phase` in
  `.sdp-solution-workflow/state.json`; task description and full task spec.
- `.sdp-solution-workflow/state.json` — `gpg_version`, `last_session`, `current_phase`
- `.sdp-solution-workflow/registry.md` — phase row status, Depends On column (read for context;
  not written here except by the Phase 7 decomposition sub-step)

There is no solution-level `.speq.md` contract to read — that document is project-specific
(binding tech-stack/naming decisions for implementation), and phases 1-7 draft solution-shape
documents, not implementation code.

## Procedure

### Step 1: Verify Preconditions

1. **GPG CHECK** — Read `.sdp-solution-workflow/state.json` and note the `gpg_version` field.
   Verify that `standards/GenericProjectGuidlines_V[version].md` exists (resolved against the
   solution root — the only root that exists here). If missing: halt per the Halt Behavior
   Contract — set `workflow_status` to `"halted"` in `.sdp-solution-workflow/state.json`, add
   `halt_reason`, notify the user by invoking `/sdp-create-banner icon=error row=0 row: Status |
   Halted — [reason]. Resolve this condition and run sdp-solution-phase-coordinator to resume.`, and
   terminate.
   Also record the halt (non-blocking — ignore any failure and continue): run
   `./sdp-shared/scripts/sdp-workflow-log.ps1 -trigger "halt.generic" -role "WORKER" -outcome
   "HALTED" -reason "[halt_reason]"` via the PowerShell tool.
2. **SUPERPOWERS CHECK** — Verify Superpowers plugin is installed by running `/plugin list`.
   - If installed: apply TDD for all implementation (tests must fail before implementation
     begins — relevant only if this task involves scripted/tooling work; most phase-document
     drafting has no tests to fail); apply four-phase root cause methodology before any
     drafting-blocker fix attempt; invoke skills explicitly only — auto-triggering is prohibited;
     do NOT use `/execute-plan` review checkpoints under any circumstances.
   - If missing: apply equivalent debugging discipline manually as described in the session
     dispatch file.
   - Note: "Superpowers" here refers to the SP plugin (Jesse Vincent), not to SDP skills.

### Step 2: Load Session Context

1. Read the bootstrap document (`SDP_Sapient-Driven-Principles_v*.md`) — review the WORKER role
   definition, the Document Lifecycle and Phase Gates section, and the state machine before
   proceeding.
2. Read the session dispatch file (`.sdp-solution-workflow/sessions/session-NNN.md` — session
   number from `.sdp-solution-workflow/state.json`'s `last_session` field). Confirm role
   assignment is WORKER. Note any flags or Superpowers instructions included by
   `sdp-solution-phase-coordinator`.
3. Read `.sdp-solution-workflow/state.json` — confirm `current_phase` and any flags.

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

1. If `current_phase` is an architecture-class phase (Architecture, Implementation Overview):
   read the relevant GPG section file(s) — per the bootstrap doc's GPG Reading Map — before
   forming an approach. Note applicable GPG patterns.
2. Read the full phase document at `sdp-solution-docs/[NN_phase_name].md`. Understand the
   assigned task in the context of the whole document — the same task-item format (checkbox +
   Completed/Eval/Verified blockquotes) the bootstrap doc defines for any phase document applies
   here unchanged.
2a. **Phase 3 (Expanded Concept) only:** also read `sdp-solution-docs/01_concept.md` and
    `sdp-solution-docs/02_research_findings.md` before drafting — the expanded concept must
    address every research angle from Phase 2, cited by angle, and build on Phase 1's concept
    rather than restate it. Also check this cycle's Concept phase state file for a
    `source_document` field (written by `sdp-new-concept-intake` Step 4 item 5); if present, read
    the tracked source file(s) it points to under `sdp-solution-docs/user-design-docs/processed/`
    (section-by-section if a `[doc_name]_Sections/[doc_name]_TOC.md` folder exists, same
    convention as `sdp-source-coverage-check`) — the expanded concept must not lose detail present
    in the original source that the Phase 1 concept compressed away. If
    `sdp-solution-docs/03_expanded_concept.md` already contains COORDINATOR-captured brainstorming
    material (per the bootstrap doc's "Phase 1 / Phase 3 — Interactive Capture Mechanics"), treat
    that material as the starting point to finish and formalize — do not originate content that
    contradicts or ignores it.
3. State what the assigned task requires before starting work. Proceed without waiting for user
   confirmation unless the restatement reveals an interpretation conflict — in that case, pause
   and state the conflict explicitly.
4. If the task has a prior non-compliant Eval blockquote: read it carefully before beginning
   work. The corrective notes from the REVIEWER are the starting point.
   If Superpowers is installed: invoke `/receiving-code-review` before beginning corrective work.
4a. **Architecture / Implementation Overview — prior Pros-Cons-Gaps cycle.** If item 4's prior
   evaluation is a `## Pros-Cons-Gaps — Cycle N` entry rather than an ordinary Eval N blockquote:
   each open gap in its Gaps section is the actual work item for this session — address every
   one of them using the bootstrap doc's Gap Resolution Format (options table, Decision Made
   block, GPG Reference when applicable), appended below the gap it resolves, never replacing
   the original gap text. This is the concrete form item 4's "corrective notes" take for this
   phase, not a separate procedure.
5. **Phase 7 only — read the decomposition instructions.** If `current_phase` contains the
   substring "Phase Readiness" and the assigned task is the decomposition task itself (not a
   downstream GATE_REVIEWER pass), the session dispatch file carries additional instructions
   from `sdp-solution-phase-coordinator` Step 2b — populating `.speq.md`/`[PROJECT]-Context.md`
   (stub → real content) for every project newly receiving tasks this cycle, assigning decomposed
   build-phase tasks to specific projects, declaring cross-project dependency edges in
   `.sdp-solution-workflow/dependencies.json`
   / `.md`, and baking cross-project reporting requirements into producer tasks' own acceptance
   criteria. Follow those instructions exactly as written in the dispatch file; this skill does
   not restate that mechanism — see `sdp-solution-phase-coordinator/SKILL.md` Step 2b for the
   authoritative procedure.
6. **Parallel pre-implementation research (before Step 4), when the phase content genuinely
   benefits from it** — mirrors `sdp-project-worker`'s own parallel-research step:
   - **Architecture/design phases — GPG pattern reads:** spawn one `general-purpose` sub-agent
     per applicable GPG chapter, each returning only the patterns directly applicable to this
     task, under 150 words.
   - **Phase 7 decomposition — cross-project context reads:** spawn an `Explore` sub-agent per
     assigned project to map its existing registry/state, if the decomposition needs to reference
     prior work already done in that project.
   If Superpowers is installed and 2 or more independent research reads are needed: optionally
   invoke `/dispatching-parallel-agents` to structure the parallel dispatch.

### Step 4: Pre-Work Verification

`sdp-project-pre-work-verify` is a project-scoped skill (its own procedure explicitly scopes every scan
to `[resolved_project]` and forbids searching the solution root) — it is not invoked here.
Instead, apply the bootstrap doc's generic Pre-Work Verification Protocol directly, scoped to
this solution-level phase document:

1. **Scan for prior artifacts.** Check whether `sdp-solution-docs/[NN_phase_name].md` already
   has substantive content for the assigned task beyond a template stub, and whether the task's
   checkbox is already `[x]` with a Completed blockquote present.
2. **Classify state:** Not Started (stub only, no Completed blockquote) / In Progress or
   Incomplete (partial content, or a Completed blockquote with a prior non-compliant Eval and no
   corrective work yet) / Complete (Completed blockquote present, task checkbox `[x]`, no open
   REJECTED cycle).
3. **Act:** Not Started → proceed to Step 5. In Progress/Incomplete → report findings and await
   user confirmation before continuing. Complete → do not proceed to Step 5; notify
   `sdp-solution-phase-coordinator` that the task is already done.

### Step 5: Implement the Task

1. Perform all work required by the task description. Address every sub-step and constraint in
   the task spec — for phases 1-6 this is drafting or revising the phase document's content
   (Architecture/Implementation Overview corrective cycles: resolving each open gap per Step 3
   item 4a); for Phase 7's decomposition task, this is Step 3 item 5's augmented procedure.
2. Where the task involves scripted or tooling work with a test surface: apply TDD (tests fail
   before implementation). If Superpowers is installed, invoke `/test-driven-development` first.
   Most phase-document drafting has no test surface — this sub-step is conditional, not a
   universal requirement for every phases-1-7 task.
3. For any blocking issue or defect encountered while drafting: apply four-phase root cause
   analysis before attempting a fix. If Superpowers is installed, invoke `/systematic-debugging`
   before any fix attempt.
4. Do not evaluate the completed work against acceptance criteria — that is
   `sdp-solution-phase-reviewer`'s role.

### Step 5a: Verify Before Recording Completion

1. If Superpowers is installed: invoke `/verification-before-completion` now — before marking
   the checkbox or writing the Completed blockquote. For phase-document drafting this means
   confirming the document actually contains what the task required, not a build/test pass.
2. Do not proceed to Step 6 until verification passes or any failures are resolved and retested.

### Step 6: Record Completion and Update State

1. Mark the task checkbox `[x]` in `sdp-solution-docs/[NN_phase_name].md`.
2. Append a Completed blockquote immediately after the task item:
   ```
   > **Completed: [YYYY-MM-DD HH:MM]** — [What was done. Decisions made. Any deviations from
   > spec and why.]
   ```
   Phase 7's decomposition task's Completed blockquote must also confirm: every project newly
   receiving tasks this cycle has its `.speq.md`/`[PROJECT]-Context.md` populated with real
   content (no template placeholders remaining); every decomposed
   build-phase task was assigned to a project's own `.sdp-workflow/registry.md`, and
   `.sdp-solution-workflow/dependencies.json` parses with every edge carrying its required
   fields (per Step 3 item 5 / `sdp-solution-phase-coordinator` Step 2b's Confirm-outcome check).
3. Update `sdp-solution-docs/[NN_phase_name]_state.json` (the phase document's path with `.md`
   replaced by `_state.json`):
   - Set the task's `status` to `"WORK_COMPLETE"`
   - Set `last_session` to the current session identifier
   - Set `last_updated` to today's ISO date
   - Do **not** write, add, or modify `eval_cycle_attempts` — owned solely by
     `sdp-solution-state-loop` (mirrors the bootstrap Stuck-Loop Detection table exactly; a
     WORKER write here corrupts REVIEWER-attempt accounting).
4. Update `.sdp-solution-workflow/state.json`:
   - Set `phase_gate.status` to `"pending"` if this was the phase's first task reaching
     WORK_COMPLETE and no gate has run yet; otherwise leave `phase_gate` untouched (gate
     transitions are `sdp-solution-phase-gate-review`'s job, not WORKER's).
   - Set `last_session` to the current session identifier.
   - Set `updated` to today's ISO date.
   - Do **not** write, add, or modify `eval_cycle_attempts` — owned solely by `sdp-solution-state-loop`
     (mirrors the bootstrap Stuck-Loop Detection table exactly; a WORKER write here corrupts
     REVIEWER-attempt accounting).
5. Mirror phase document changes to the parent solution documents per the sync rule notice, if
   this phase document has section files.
6. Commit all work: run `git status` to identify every untracked and modified file. Stage and
   commit ALL files not covered by `.gitignore` — do not enumerate a specific file list. This
   includes the phase document, its `_state.json` file, `.sdp-solution-workflow/state.json`, and
   (for Phase 7) every affected project's `.sdp-workflow/registry.md` plus the dependency ledger
   files. Push via `./sdp-shared/scripts/sdp-github.ps1 push` (PowerShell tool) — read the JSON
   envelope: `status: "pushed"` confirms success; an `ok:false` / `status:"error"` envelope means
   the push failed — surface it and do not mark the task complete. Record the short commit hash
   in the Completed blockquote.
7. **CI-green gate (only when `SDP-Config.json` `ci.enabled` is true).** Same contract as
   `sdp-project-worker` Step 6 item 6 — `green` proceeds; `red` requires four-phase root cause analysis,
   fix, re-commit, re-push, re-check; `no_ci`/`unreachable` proceeds with a disclosed caveat;
   `timeout` halts per the Halt Behavior Contract rather than guessing the outcome.
8. Record completion (non-blocking — ignore any failure and continue): run
   `./sdp-shared/scripts/sdp-workflow-log.ps1 -trigger "worker.complete" -role "WORKER" -workItem
   "[current_phase]" -outcome "WORK_COMPLETE" -reason "[one sentence: what was done, and any
   deviation from spec and why]"` via the PowerShell tool.
9. Session ends. Do not proceed to evaluate or verify the completed work.

## Constraints

- Never invoked for a project-level task — that is `sdp-project-worker`'s exclusive job. This skill
  exists only for solution-scoped phases 1-7.
- Never invokes `sdp-project-pre-work-verify` — that skill is hard-scoped to `[resolved_project]` and
  must not be pointed at solution-level content. Step 4 above is the equivalent, applied inline.
- Never invokes `sdp-project-worker` and is never invoked by it — no dependency in either direction.
- A single session handles exactly one assigned phase task. Do not begin a second task.
- Never evaluate own output against acceptance criteria — session ends after state update.
- `/execute-plan` review checkpoints are prohibited — they violate Bootstrap context isolation.
- Never skip TDD or four-phase debugging discipline merely because Superpowers is not installed
  — apply both manually where the task has a test surface.
- Never write `eval_cycle_attempts` — owned solely by `sdp-solution-state-loop`.
- Never mark the task complete when a push fails or CI returns `red`.
- For Phase 7 specifically: never write a `CROSS_PROJECT_BLOCKED`-style flag into any project's
  own state file — dependency-ledger data lives exclusively in
  `.sdp-solution-workflow/dependencies.json`/`.md`, per the design's boundary invariant.

## Outputs

- Phase document (`sdp-solution-docs/[NN_phase_name].md`) updated: task checkbox `[x]`, Completed
  blockquote appended
- Phase state file (`sdp-solution-docs/[NN_phase_name]_state.json`) updated: task `status` →
  `WORK_COMPLETE`, `last_session`, `last_updated`
- `.sdp-solution-workflow/state.json` updated: `last_session`, `updated`, `phase_gate.status` set
  to `"pending"` on first WORK_COMPLETE for the phase
- Phase 7 only: each assigned project's own `.sdp-workflow/registry.md` populated with its
  decomposed tasks; `.sdp-solution-workflow/dependencies.json`/`.md` written
- `.sdp-solution-workflow/logging/workflow-logs/workflow-log-<local-yyyyMMdd>.jsonl` — one
  `worker.complete` entry (non-blocking side effect, via `sdp-workflow-log.ps1`)
