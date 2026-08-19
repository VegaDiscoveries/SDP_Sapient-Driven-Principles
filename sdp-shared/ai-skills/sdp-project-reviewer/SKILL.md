## Purpose

Execute a REVIEWER session: verify preconditions, form an independent understanding of the
task's acceptance criteria, read the WORKER's Completed blockquote, independently verify the
implementation, append the Eval and (if passing) Verified blockquotes, and update state. A
REVIEWER session is always a separate subagent invocation from the WORKER — no shared
conversation history. Superpowers code review may be used as a thinking aid; it does not
substitute for the formal Eval blockquote.

## Inputs

All paths below are relative to `[resolved_project]` (resolved in Step 1 item 1 below).

- `[resolved_project]/.sdp-workflow/sessions/session-NNN.md` — role assignment, task ID,
  phase file path, flags (e.g., `VERIFY_DURING_IMPLEMENTATION`), re-evaluation trigger reason
  for Eval 2+ cycles, and `Project:` field. Session number from
  `[resolved_project]/.sdp-workflow/state.json`'s `last_session` field.
- Phase document — path given as `active_phase_file` in `[resolved_project]/.sdp-workflow/state.json`,
  or the session dispatch file's "Phase file path" field if `active_phase_file` is absent; task
  description, Completed blockquote, and any prior Eval/Verified blockquotes. Do not reconstruct
  this path from a `[doc_name]_Phases/[phase_name].md` convention — not every project uses that
  folder layout.
- Phase state file — the phase document's path with its trailing `.md` replaced by `_state.json`;
  confirms assigned task ID, current status, and eval cycle count
- `[resolved_project]/.sdp-workflow/state.json` — `gpg_version`, `last_session`, phase file path
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
   project applies — invoke `/sdp-create-banner icon=error row=0 row: Status | Halted — no
   single project applies to this solution-level file; unable to resolve a project. Resolve
   this condition and run COORDINATOR to resume.`, and terminate.

   Once resolved, all file paths in subsequent steps are built under `[resolved_project]/`.
   For single-project workspaces where `last_active_projects` is `["."]`,
   `.\.\[path]` resolves to `.\[path]` — identical to current single-project behavior.

2. **GPG CHECK** — Read `[resolved_project]/.sdp-workflow/state.json` and note the
   `gpg_version` field. Verify that `standards/GenericProjectGuidlines_V[version].md` exists.
   If missing: halt per the Halt Behavior Contract — set `workflow_status` to `"halted"` in
   `[resolved_project]/.sdp-workflow/state.json`, add `halt_reason`, notify the user by invoking
   `/sdp-create-banner icon=error row=0 row: Status | Halted — [reason]. Resolve this condition
   and run COORDINATOR to resume.`, and terminate.
   Also record the halt (non-blocking — ignore any failure and continue): run
   `./sdp-shared/scripts/sdp-workflow-log.ps1 -trigger "halt.generic" -role "REVIEWER" -outcome
   "HALTED" -reason "[halt_reason]"` via the PowerShell tool.
3. **SUPERPOWERS CHECK** — Verify Superpowers plugin is installed by running `/plugin list`.
   If installed: Superpowers code review may be used as a thinking aid before writing the
   formal Eval blockquote; invoke explicitly — auto-triggering is prohibited. Superpowers
   output does NOT substitute for the Bootstrap Eval blockquote — the formal criterion-by-
   criterion evaluation with explicit outcome is still required.
   Note: "Superpowers" here refers to the SP plugin (Jesse Vincent), not to SDP skills.

### Step 2: Load Session Context

1. Read the bootstrap document (`SDP_Sapient-Driven-Principles_v*.md`) — review the REVIEWER role
   definition and state machine before proceeding.
2. Read the session dispatch file (`[resolved_project]/.sdp-workflow/sessions/session-NNN.md`
   — session number from `[resolved_project]/.sdp-workflow/state.json`'s `last_session`
   field). Confirm role assignment is REVIEWER. Note any re-evaluation trigger reason,
   `VERIFY_DURING_IMPLEMENTATION` flag, or other instructions included by COORDINATOR.
3. Read `[resolved_project]/.sdp-workflow/state.json` — confirm the assigned task ID, phase
   file path, and flags.

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

1. Read `[resolved_project]/[AppName].speq.md` to load the tech contract before forming a
   verification approach. Any row in its Standing Non-Functional Requirements section whose
   "Applies To" matches this task is binding acceptance-criteria input, in addition to the
   task's own written description — include it in sub-step 2's independent understanding.
2. Read the task description in the phase file — the `active_phase_file` path from
   `[resolved_project]/.sdp-workflow/state.json` (or the session dispatch file's "Phase file
   path" field if `active_phase_file` is absent). Form an independent understanding of the
   acceptance criteria — record what each criterion requires, including any applicable Standing
   Non-Functional Requirements row from sub-step 1 — before reading the Completed blockquote.
   Do not read the Completed blockquote until this sub-step is complete.
3. Read the Completed blockquote. Note what the WORKER claimed to do and any deviations from
   spec noted by the WORKER.

### Step 4: Independent Verification

1. **Git sweep before verification.** Run `git status`. If any untracked or modified project
   files exist that are not covered by `.gitignore`, stage and commit ALL of them — do not
   enumerate a specific file list — and ~~push to the remote branch~~ push via
   `./sdp-shared/scripts/sdp-github.ps1 push` (PowerShell tool; read the JSON envelope —
   `status: "pushed"` confirms success, an `ok:false` / `status:"error"` envelope means the
   push failed and must be surfaced). Note in the Eval blockquote whether a catch-up commit
   was required and what it contained. Skip this sub-step if the working tree is already clean.

   **CI-green gate (only when `SDP-Config.json` `ci.enabled` is true).** After the working tree
   is clean and pushed, run `./sdp-shared/scripts/sdp-github.ps1 ci-status` and branch on the
   JSON `status`: `green` → continue verification; `red` → record a **non-compliant** finding in
   the Eval blockquote (cite the failed jobs from `failedJobs` / `run-log-failed`) and set the
   task to `REJECTED` in Step 6 — a red remote CI is a compliance failure regardless of local
   results; `no_ci` / `unreachable` → continue with the local result and disclose the caveat in
   the Eval blockquote; `timeout` → invoke `/sdp-create-banner icon=error row=0 row: Status |
   Halted — CI status check timed out. Resolve this condition and run COORDINATOR to resume.`,
   and halt per the Halt Behavior Contract. When `ci.enabled` is
   false or absent, `ci-status` returns `no_ci` and this gate is a no-op.

2. **Group the work before spawning agents.** Cluster the acceptance criteria (or, for
   Pros-Cons-Gaps sessions, the review dimensions — sections, GPG chapters, upstream spec
   alignment) into logical groups with no ordering dependency between groups.

3. **Optional code-review thinking aid.** If Superpowers is installed: optionally invoke
   `/requesting-code-review` to structure the review approach before dispatching verification
   sub-agents (next sub-step). The formal Eval blockquote (Step 5) is still required regardless
   of this step's output.

4. **Spawn one `general-purpose` sub-agent per group, in parallel.** Tune the prompt to
   the output precision the synthesis step requires. If 2 or more independent verification
   reads are needed and Superpowers is installed: optionally invoke
   `/dispatching-parallel-agents` to structure the parallel dispatch.

   - **Summary-sufficient sessions** (document review, Pros-Cons-Gaps, concept review):
     > "Read [file list]. For each file, answer: does it satisfy [criterion or GPG rule]?
     > Return findings only — specific quotes where something passes or fails, gaps where
     > content is missing. Under 200 words per file. Do not summarise content you were not
     > asked about."

   - **Line-precision sessions** (code implementation review):
     > "Find all source files in [scope] relevant to [criterion]. For each file, return:
     > path, relevant symbol names, and whether they satisfy the criterion. Quote the
     > specific lines that pass or fail. Flag anything uncertain. Do not fix anything."

5. **Receive sub-agent summaries. Synthesize in the main agent.** For any finding flagged
   as uncertain, or any criterion a sub-agent could not fully address: read those specific
   files directly in the main context before forming the verdict. Sub-agent summaries are
   evidence; they do not substitute for direct reads where precision is in doubt.

6. **GPG alignment check.** Read
   `standards/GenericProjectGuidlines_Sections/GenericProjectGuidlines_TOC.md`. The GPG
   chapter reads may be dispatched as part of the parallel group in sub-step 4 above — each
   chapter is an independent read. Scope is limited to topics directly affected by this
   task — do not expand beyond it.

7. **If `VERIFY_DURING_IMPLEMENTATION` flag is set:** Spawn a separate `general-purpose`
   sub-agent to run the test suite and return the result:
   > "Run `[test command]` and return: pass/fail, total count, and any failing test names
   > with error messages. Do not fix anything."
   Receive result before writing Step 5 Eval. Code reading alone does not satisfy this flag.

8. **For re-evaluation cycles (Eval 2+):** Begin with the re-evaluation trigger reason from
   the dispatch file. Assess whether the changed spec, resolved dependency, or audit finding
   changes the compliance verdict for any criterion.

### Step 5: Record Evaluation

1. Determine the current eval cycle number N: read `eval_cycles` from the phase state file
   (the phase file path from Step 3.2 with `.md` replaced by `_state.json`) and add 1
   (e.g., `eval_cycles: 0` → this is Eval 1).
2. Append an Eval N blockquote to the phase file immediately after the most recent blockquote
   for this task:
   ```
   > **Eval N — [YYYY-MM-DD HH:MM]:** [Compliance assessment against task spec, criterion by
   > criterion. Each sub-step addressed explicitly. Build status confirmed.
   > Outcome: compliant / partially compliant / non-compliant.
   > If non-compliant: specific, actionable notes for the next WORKER session.]
   ```
   - For re-evaluation cycles: begin the blockquote body with
     `Re-evaluation trigger: [describe what changed].`
   - State the outcome explicitly on its own line: `Outcome: compliant`,
     `Outcome: partially compliant`, or `Outcome: non-compliant`.
   - If non-compliant: correction notes must be specific and actionable — vague notes are not
     sufficient for the WORKER to correct the work.
3. **If compliant or partially compliant:** Append a Verified N blockquote immediately after
   the Eval N blockquote:
   ```
   > **Verified N — [YYYY-MM-DD HH:MM]:** [Independent confirmation. What was read/run to
   > verify. Outcome: Verified.]
   ```
4. **If non-compliant:** Do NOT write a Verified N blockquote. The task will return to WORKER
   via COORDINATOR.

### Step 6: Update State and Sync

1. Update the phase state file (the phase file path from Step 3.2 with `.md` replaced by
   `_state.json`) for the evaluated task:
   - **Compliant:** `status` → `"VERIFIED"`, increment `eval_cycles` by 1
   - **Partially compliant:** `status` → `"VERIFIED"`, increment `eval_cycles` by 1, add
     `"PARTIAL_COMPLIANCE"` to the `flags` array. If `"PARTIAL_COMPLIANCE"` is already
     present (second consecutive partial verdict), also add `"PARTIAL_COMPLIANCE_ESCALATE"` —
     COORDINATOR must flag this task for design review before dispatching a new WORKER session.
   - **Non-compliant:** `status` → `"REJECTED"`, increment `eval_cycles` by 1
   - Set `last_session` to the current session identifier
   - Set `last_updated` to today's ISO date
   - **If the task status was set to `"VERIFIED"` (compliant or partially compliant):** Play
     the notification tone (non-blocking — ignore any failure and continue): run
     `./sdp-shared/scripts/sdp-tone.ps1 -trigger "milestone.task_verified"` via the PowerShell
     tool (silent unless enabled in SDP-Tones.json).
2. Record the eval outcome (non-blocking — ignore any failure and continue): run
   `./sdp-shared/scripts/sdp-workflow-log.ps1 -trigger "reviewer.eval" -role "REVIEWER"
   -workItem "[task ID]" -outcome "[VERIFIED | REJECTED]" -reason "[one sentence: compliance
   verdict and, if non-compliant, the primary correction needed]"` via the PowerShell tool. This
   is the narrative counterpart to the mechanical tool-call trail — the reasoning behind
   compliant/partially-compliant/non-compliant is not recoverable from tool calls alone.
3. If the phase file has a top-level `**Status:**` header (the standard document template in
   `SDP-Workspace-Setup.md` includes one) and its current value does not reflect this task's new
   evaluated state: strike it through in place and append the corrected value immediately after,
   per Append-Only Discipline — `VERIFIED`, `VERIFIED (partially compliant)`, or `REJECTED` as
   applicable, e.g. `**Status:** ~~WORK_COMPLETE.~~ **VERIFIED (partially compliant)** [DATE,
   this session].` Do not silently overwrite the header. A phase file with no `**Status:**`
   header needs no action here.
4. Mirror all phase file changes to the parent document per the sync rule notice in the
   phase file header.
5. Session ends.

## Constraints

- Never run this session in the same subagent invocation as the WORKER session that produced
  the work — `/clear` within an existing context does not satisfy this requirement.
- Form independent acceptance criteria from the task description before reading the Completed
  blockquote. Do not reverse this order.
- Do not write a Verified N blockquote for a non-compliant evaluation under any circumstances.
- Never leave a non-compliant evaluation's correction notes vague or non-actionable.
- Never substitute Superpowers code review for the formal Eval blockquote — it is always
  required, even when Superpowers was used as a thinking aid.
- Never auto-trigger Superpowers code review — it must be invoked explicitly.
- GPG alignment scope is limited to topics directly affected by this task — do not audit
  unrelated sections.

## Outputs

- Phase file (path from Step 3.2) updated: Eval N blockquote appended; Verified N appended if
  compliant or partially compliant; top-level `**Status:**` header synced to the evaluated
  outcome if present and stale
- Parent document updated: mirrors phase file changes per sync rule
- Phase state file (phase file path with `.md` replaced by `_state.json`) — task status →
  `VERIFIED` or `REJECTED`; `eval_cycles` incremented; `PARTIAL_COMPLIANCE` or
  `PARTIAL_COMPLIANCE_ESCALATE` flags added if applicable
- `.sdp-solution-workflow/logging/workflow-logs/workflow-log-<local-yyyyMMdd>.jsonl` — one
  `reviewer.eval` entry recording the verdict and rationale (non-blocking side effect, via
  `sdp-workflow-log.ps1`)
