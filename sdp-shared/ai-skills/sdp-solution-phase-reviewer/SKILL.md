## Purpose

Execute a REVIEWER session for one of the solution's own phases 1-7: verify preconditions, form
an independent understanding of the task's acceptance criteria, read the WORKER's Completed
blockquote, independently verify the work, append the Eval and (if passing) Verified blockquotes,
and update state. This is the solution-scoped counterpart to `sdp-project-reviewer` — same role, same
discipline, different root. Never invoked for project-level tasks, and `sdp-project-reviewer` is never
invoked for phases 1-7 — each skill exists for exactly one scope, permanently.

A REVIEWER session is always a separate subagent invocation from the WORKER — no shared
conversation history. Superpowers code review may be used as a thinking aid; it does not
substitute for the formal Eval blockquote.

## Inputs

All paths below are relative to the solution root — there is no project to resolve.

- `.sdp-solution-workflow/sessions/session-NNN.md` — role assignment, phase identifier, phase
  document path, flags, re-evaluation trigger reason for Eval 2+ cycles. Session number from
  `.sdp-solution-workflow/state.json`'s `last_session` field. Never carries a `Project:` field.
- Phase document — `sdp-solution-docs/[NN_phase_name].md`, named by `current_phase` in
  `.sdp-solution-workflow/state.json`; task description, Completed blockquote, and any prior
  Eval/Verified blockquotes.
- `.sdp-solution-workflow/state.json` — `gpg_version`, `last_session`, `current_phase`
- Phase state file (`sdp-solution-docs/[NN_phase_name]_state.json`) — `eval_cycles` and, for
  Architecture/Implementation Overview phases, `pros_cons_gaps.cycle_target`/`cycle_count`, for
  the assigned task

There is no solution-level `.speq.md` contract to read — see `sdp-solution-phase-worker`'s
Inputs section for why.

## Procedure

### Step 1: Verify Preconditions

1. **GPG CHECK** — Read `.sdp-solution-workflow/state.json` and note the `gpg_version` field.
   Verify that `standards/GenericProjectGuidlines_V[version].md` exists (solution root). If
   missing: halt per the Halt Behavior Contract — set `workflow_status` to `"halted"` in
   `.sdp-solution-workflow/state.json`, add `halt_reason`, notify the user by invoking
   `/sdp-create-banner icon=error row=0 row: Status | Halted — [reason]. Resolve this condition
   and run sdp-solution-phase-coordinator to resume.`, and terminate.
   Also record the halt (non-blocking — ignore any failure and continue): run
   `./sdp-shared/scripts/sdp-workflow-log.ps1 -trigger "halt.generic" -role "REVIEWER" -outcome
   "HALTED" -reason "[halt_reason]"` via the PowerShell tool.
2. **SUPERPOWERS CHECK** — Verify Superpowers plugin is installed by running `/plugin list`. If
   installed: Superpowers code review may be used as a thinking aid before writing the formal
   Eval blockquote; invoke explicitly — auto-triggering is prohibited. Superpowers output does
   NOT substitute for the Bootstrap Eval blockquote.

### Step 2: Load Session Context

1. Read the bootstrap document (`SDP_Sapient-Driven-Principles_v*.md`) — review the REVIEWER
   role definition and state machine before proceeding.
2. Read the session dispatch file (`.sdp-solution-workflow/sessions/session-NNN.md` — session
   number from `.sdp-solution-workflow/state.json`'s `last_session` field). Confirm role
   assignment is REVIEWER. Note any re-evaluation trigger reason or other instructions from
   `sdp-solution-phase-coordinator`.
3. Read `.sdp-solution-workflow/state.json` — confirm `current_phase` and flags.

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

1. Read the task description in `sdp-solution-docs/[NN_phase_name].md`. Form an independent
   understanding of the acceptance criteria — record what each criterion requires — before
   reading the Completed blockquote. Do not read the Completed blockquote until this sub-step is
   complete.
2. Read the Completed blockquote. Note what the WORKER claimed to do and any deviations from
   spec noted by the WORKER.
3. **Phase 7 only.** If `current_phase` contains "Phase Readiness" and the reviewed task is the
   decomposition task itself: form independent criteria for the decomposition specifically —
   every decomposed build-phase task assigned to a real project's own `.sdp-workflow/registry.md`,
   every dependency edge in `.sdp-solution-workflow/dependencies.json` well-formed and referencing
   a real project/task, and every cross-project reporting requirement baked into the correct
   producer task's acceptance criteria. This mirrors `sdp-project-gate-review`'s / `sdp-solution-phase-gate-review`'s
   Phase Readiness criteria at task-review granularity rather than phase-gate granularity — this
   step is an ordinary task-level Eval, not a substitute for the later phase gate.
4. **Architecture / Implementation Overview only.** Read this phase's own `[phase]_state.json`
   for `pros_cons_gaps.cycle_target` and `pros_cons_gaps.cycle_count` (written by
   `sdp-solution-phase-coordinator` before this dispatch — `cycle_count` is 0 on the first
   cycle). Form independent criteria as a Pros-Cons-Gaps assessment instead of an
   acceptance-criteria checklist — see Step 5 for the required format.

### Step 4: Independent Verification

1. **Git sweep before verification.** Run `git status`. If any untracked or modified files exist
   that are not covered by `.gitignore`, stage and commit ALL of them — do not enumerate a
   specific file list — and push via `./sdp-shared/scripts/sdp-github.ps1 push` (PowerShell tool;
   read the JSON envelope — `status: "pushed"` confirms success, an `ok:false` / `status:"error"`
   envelope means the push failed and must be surfaced). Note in the Eval blockquote whether a
   catch-up commit was required. Skip this sub-step if the working tree is already clean.

   **CI-green gate (only when `SDP-Config.json` `ci.enabled` is true).** Same contract as
   `sdp-project-reviewer` Step 4 item 1 — `green` continues verification; `red` records a non-compliant
   finding and the task goes to `REJECTED` in Step 6; `no_ci`/`unreachable` continues with a
   disclosed caveat; `timeout` halts per the Halt Behavior Contract.

2. **Group the work before spawning agents.** Cluster the acceptance criteria (or, for
   Pros-Cons-Gaps sessions, the review dimensions — sections, GPG chapters) into logical groups
   with no ordering dependency between groups.

3. **Optional code-review thinking aid.** If Superpowers is installed: optionally invoke
   `/requesting-code-review` before dispatching verification sub-agents. The formal Eval
   blockquote (Step 5) is still required regardless of this step's output.

4. **Spawn one `general-purpose` sub-agent per group, in parallel.** If 2 or more independent
   verification reads are needed and Superpowers is installed: optionally invoke
   `/dispatching-parallel-agents` to structure the parallel dispatch.

   - **Document-review sessions** (the common case for phases 1-6):
     > "Read [file]. For each criterion in [list], answer: does it satisfy the criterion? Return
     > findings only — specific quotes where something passes or fails, gaps where content is
     > missing. Under 200 words per criterion. Do not summarise content you were not asked about."

   - **Phase 7 decomposition sessions:**
     > "Read `.sdp-solution-workflow/dependencies.json` and [affected projects']
     > `.sdp-workflow/registry.md` files. For each dependency edge, confirm the referenced
     > project/task (or, for a decision-type edge, the criterion_text) actually exists. Flag any
     > edge referencing something nonexistent. Do not fix anything."

5. **Receive sub-agent summaries. Synthesize in the main agent.** For any finding flagged as
   uncertain, read those specific files directly in the main context before forming the verdict.

6. **GPG alignment check.** Read
   `standards/GenericProjectGuidlines_Sections/GenericProjectGuidlines_TOC.md`. Scope is limited
   to topics directly affected by this task.

7. **For re-evaluation cycles (Eval 2+):** Begin with the re-evaluation trigger reason from the
   dispatch file. Assess whether the changed spec, resolved dependency, or audit finding changes
   the compliance verdict for any criterion.

### Step 5: Record Evaluation

1. Determine the current eval cycle number N: read `eval_cycles` for the assigned task from
   this phase's own `[phase]_state.json` and add 1.
2. **Architecture / Implementation Overview:** append a Pros-Cons-Gaps evaluation instead of the
   ordinary Eval N blockquote below, per the bootstrap doc's Pros-Cons-Gaps Cycle section:
   ```
   ## Pros-Cons-Gaps — Cycle [pros_cons_gaps.cycle_count + 1] — [YYYY-MM-DD HH:MM]
   ### Pros
   - [what is well-defined and sound]
   ### Cons
   - [weaknesses in current form]
   ### Gaps
   - [missing content, unresolved decisions, unclear boundaries]
   **Unresolved gap count: N**
   ```
   Determine the outcome: **compliant** if the gap count is 0, OR if
   `pros_cons_gaps.cycle_count + 1 >= pros_cons_gaps.cycle_target` — in that second case, state
   the reason explicitly as "cycle target reached with N gaps still open," never worded as if
   the remaining gaps were resolved. Otherwise **non-compliant**. Skip item 3 below for this
   phase — do not also write the ordinary Eval N blockquote format.
3. **All other phases:** append an Eval N blockquote to `sdp-solution-docs/[NN_phase_name].md`
   immediately after the most recent blockquote for this task:
   ```
   > **Eval N — [YYYY-MM-DD HH:MM]:** [Compliance assessment against task spec, criterion by
   > criterion. Outcome: compliant / partially compliant / non-compliant.
   > If non-compliant: specific, actionable notes for the next WORKER session.]
   ```
   - Re-evaluation cycles begin with `Re-evaluation trigger: [describe what changed].`
   - State the outcome explicitly on its own line.
4. **If compliant or partially compliant (either item 2 or item 3 above):** append a Verified N
   blockquote immediately after:
   ```
   > **Verified N — [YYYY-MM-DD HH:MM]:** [Independent confirmation. What was read/run to
   > verify. Outcome: Verified. For a cycle-target-reached Pros-Cons-Gaps compliance: name the
   > gaps still open and note they carry forward to gate review, not silently resolved.]
   ```
5. **If non-compliant:** do NOT write a Verified N blockquote. The task returns to
   `sdp-solution-phase-worker` via `sdp-solution-phase-coordinator`. For Pros-Cons-Gaps: WORKER
   addresses each open gap using the bootstrap doc's Gap Resolution Format.

### Step 6: Update State and Sync

1. Update `sdp-solution-docs/[NN_phase_name]_state.json` (the phase document's path with `.md`
   replaced by `_state.json`) for the evaluated task:
   - **Compliant:** task status → `"VERIFIED"`, increment `eval_cycles` by 1
   - **Partially compliant:** status → `"VERIFIED"`, increment `eval_cycles` by 1, add
     `"PARTIAL_COMPLIANCE"` to the task's flags array (add `"PARTIAL_COMPLIANCE_ESCALATE"` too on
     a second consecutive partial verdict — `sdp-solution-phase-coordinator` must flag it for design
     review before dispatching another WORKER session)
   - **Non-compliant:** status → `"REJECTED"`, increment `eval_cycles` by 1
   - **Architecture / Implementation Overview only:** also increment `pros_cons_gaps.cycle_count`
     by 1, regardless of the compliant/non-compliant outcome — it tracks cycles run, not cycles
     passed. Never write or modify `pros_cons_gaps.cycle_target` — that field is
     `sdp-solution-phase-coordinator`'s to set, once, before the first cycle.
   - Set `last_session` and `updated`
   - **If status became `"VERIFIED"`:** play the notification tone (non-blocking): run
     `./sdp-shared/scripts/sdp-tone.ps1 -trigger "milestone.task_verified"` via the PowerShell
     tool.
2. Record the eval outcome (non-blocking): run `./sdp-shared/scripts/sdp-workflow-log.ps1
   -trigger "reviewer.eval" -role "REVIEWER" -workItem "[current_phase]" -outcome
   "[VERIFIED | REJECTED]" -reason "[one sentence]"` via the PowerShell tool.
3. Mirror phase document changes to the parent solution documents per the sync rule notice, if
   this phase document has section files.
4. Session ends.

## Constraints

- Never invoked for a project-level task — that is `sdp-project-reviewer`'s exclusive job. This skill
  exists only for solution-scoped phases 1-7.
- Never invokes and is never invoked by `sdp-project-reviewer` — no dependency in either direction.
- Never run this session in the same subagent invocation as the WORKER session that produced
  the work — `/clear` within an existing context does not satisfy this requirement.
- Form independent acceptance criteria before reading the Completed blockquote. Do not reverse
  this order.
- Do not write a Verified N blockquote for a non-compliant evaluation under any circumstances.
- Never leave a non-compliant evaluation's correction notes vague or non-actionable.
- Never substitute Superpowers code review for the formal Eval blockquote.
- Never auto-trigger Superpowers code review — it must be invoked explicitly.
- GPG alignment scope is limited to topics directly affected by this task.
- Never write `pros_cons_gaps.cycle_target` — owned solely by `sdp-solution-phase-coordinator`,
  set once before the first cycle. REVIEWER only increments `cycle_count`.

## Outputs

- Phase document (`sdp-solution-docs/[NN_phase_name].md`) updated: Eval N blockquote appended
  (or, for Architecture/Implementation Overview, a Pros-Cons-Gaps — Cycle N evaluation); Verified
  N appended if compliant or partially compliant
- Phase state file (`sdp-solution-docs/[NN_phase_name]_state.json`) updated: task status →
  `VERIFIED` or `REJECTED`; `eval_cycles` incremented; `PARTIAL_COMPLIANCE`/
  `PARTIAL_COMPLIANCE_ESCALATE` flags if applicable; for Architecture/Implementation Overview,
  `pros_cons_gaps.cycle_count` also incremented
- `.sdp-solution-workflow/logging/workflow-logs/workflow-log-<local-yyyyMMdd>.jsonl` — one
  `reviewer.eval` entry (non-blocking side effect, via `sdp-workflow-log.ps1`)
