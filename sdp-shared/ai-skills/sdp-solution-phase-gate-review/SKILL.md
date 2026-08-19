## Purpose

Execute a GATE_REVIEWER session for one of the solution's own phases 1-7: independently assess
a completed solution-level phase document against gate criteria, produce a structured verdict
blockquote, and update `phase_gate` state in `.sdp-solution-workflow/state.json`. This is the
solution-scoped counterpart to `sdp-project-gate-review` — same role, same criteria, always solution
root. `sdp-project-gate-review` never accepts a solution-scoped dispatch (it has no `-scope` parameter);
this skill exists specifically so an agent never has to decide whether a project-level skill can
be pointed at solution-level work.

A GATE_REVIEWER session reviews an entire phase document — not a single task. Its output is the
gate verdict blockquote and `phase_gate.status` update; it does not advance `current_phase`,
reset `phase_gate`, or spawn subagents.

**Hybrid model** (mirrors `sdp-project-gate-review`'s own multi-boundary hybrid, reusing its boundary
analysis): three separate scripts own every deterministic block, with two
LLM-judgment phases in between that no script can perform:

- `sdp-solution-phase-gate-review-gpg-check.ps1` (Step 1) — GPG existence check; writes the Halt
  Behavior Contract state on failure.
- `sdp-solution-phase-gate-review-setup.ps1` (Steps 3-5) — reads the dispatch file, cross-checks
  `current_phase`, reads the phase document, strips any prior Gate Verdict blockquote(s) from the
  content handed to the LLM's independent assessment (each surviving line numbered against the
  real file, Read-tool convention, so findings can cite exact lines without opening it), and
  separately surfaces prior `GATE_BLOCKED` blockquotes for the re-gate check.
- `sdp-solution-phase-gate-review-finalize.ps1` (Steps 9-10) — takes the LLM's verdict as an
  explicit `-Verdict` argument (never inferred by the script), updates `phase_gate` state, plays
  the `gate.blocked` tone on a blocked verdict, records a `gate.verdict` entry to
  `workflow-logs/` on either outcome, and returns the fully-templated user report.

Unlike `sdp-project-gate-review`'s three scripts, none of these three take a `-workspaceRoot` or `-scope`
parameter — they always resolve the solution root from their own location
(`Split-Path -Parent (Split-Path -Parent $PSScriptRoot)`), the same self-resolving pattern
`sdp-solution-create-prompt.ps1` already uses. There is only ever one scope here, so there is
nothing to parameterize.

## Inputs

- `.sdp-solution-workflow/state.json` — read by all three scripts; provides `current_phase`,
  `phase_gate.status`, `phase_gate.gate_eval_cycles`, `gpg_version`, and `last_session`.
  `.sdp-solution-workflow/dependencies.json` is also read, Phase-Readiness gates only, by the
  dependency-edge-validity criterion below.
- `.sdp-solution-workflow/sessions/[last_session].md` (dispatch file) — read by the setup
  script; provides role confirmation, phase document path, and re-gate trigger reason if
  applicable. Never carries a `Project:` field.
- Completed phase document — `sdp-solution-docs/[NN_phase_name].md`; read by the setup script,
  path provided in the dispatch file.
- `standards/GenericProjectGuidlines_Sections/GenericProjectGuidlines_TOC.md` — required for GPG
  alignment check (Step 6); read directly by the LLM, not by any script.
- Prior GATE_BLOCKED blockquote(s) — present in the phase document on re-gate cycles only;
  surfaced by the setup script's `prior_gate_blocked_blockquotes` output field.

## Procedure

### Step 1: Run Script — GPG Check

Run `./sdp-shared/scripts/sdp-solution-phase-gate-review-gpg-check.ps1` via the PowerShell tool.
No arguments — the script self-resolves the solution root.

If the PowerShell tool call produces no parseable single-line JSON on stdout (regardless of exit
code): invoke `/sdp-create-banner icon=error row=0 row: Status | Script invocation failed — no
result to parse. Verify sdp-shared/scripts/sdp-solution-phase-gate-review-gpg-check.ps1 is
present and the permission entry in .claude/settings.local.json is registered.` and halt.

Parse the single-line JSON result. Branch on `status`:

- **`"error"`** — Invoke `/sdp-create-banner icon=error row=0 row: Error | [error]`. Halt.
  (Covers a missing or unparseable `state.json`, or a missing `gpg_version` field.)
- **`"halted"`** — The script has already written `workflow_status: "halted"` and `halt_reason`
  to `state.json` when `state_json_written` is `true`. Invoke `/sdp-create-banner icon=error
  row=0 row: Status | [halt_message]`. Halt.
- **`"success"`** — Proceed to Step 2.

### Step 2: SUPERPOWERS CHECK

Verify Superpowers plugin is installed by running `/plugin list`. If installed: Superpowers code
review may be used as a thinking aid before writing the formal gate verdict blockquote; invoke
explicitly — auto-triggering is prohibited. Superpowers output does NOT substitute for the
Bootstrap Gate Verdict blockquote. Missing Superpowers does not block this session.

### Step 3: Run Script — Setup (Read Dispatch File, Read Workflow State, Read Phase Document)

Run `./sdp-shared/scripts/sdp-solution-phase-gate-review-setup.ps1` via the PowerShell tool. No
arguments. Same no-parseable-result handling as Step 1.

Parse the single-line JSON result. Branch on `status`:

- **`"error"`** — Invoke `/sdp-create-banner icon=error row=0 row: Error | [error]`. Halt.
- **`"halted"`** — Invoke `/sdp-create-banner icon=error row=0 row: Status | [halt_message]`.
  Halt. (Covers: no `last_session` recorded; the dispatch file not found; the dispatch file's
  `Role:` field not equal to `GATE_REVIEWER`; no `Phase Document:` field; `current_phase` not
  matching the dispatch file's `Work Item:` field; or the phase document not found.)
- **`"success"`** — Record `session_id`, `role_confirmed`, `current_phase`, `phase_gate_status`,
  `gate_eval_cycles`, `phase_document_path`, `is_regate_cycle`, `regate_trigger_reason`,
  `phase_document_content` (Gate Verdict blockquotes already stripped; every surviving line
  prefixed with its original line number from the real file, same convention as the Read tool —
  cite these numbers directly in findings), and `prior_gate_blocked_blockquotes`. Proceed to
  Step 6.

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

### Step 6: Assess Independently

Assess `phase_document_content` from the Step 3 script result independently against all four
standard criteria, described identically to `sdp-project-gate-review`'s Step 6. This content already has
any prior Gate Verdict blockquote stripped and every surviving line prefixed with its original
line number from the real file (same convention as the Read tool) — cite those numbers directly
in findings. Do not read the actual phase document file at this point (line numbers are already
available without it), and do not read `prior_gate_blocked_blockquotes` before completing this
step.

**Every phase reviewed here is solution-scoped by construction** — unlike `sdp-project-gate-review`,
there is no project-level legacy-migration case to distinguish. **Phase Readiness detection:**
if `current_phase` contains the substring "Phase Readiness", this gate review always assesses
seven additional criteria (below), in addition to the standard four — never five or six; the
ledger always exists at this scope. On any Phase-Readiness-specific finding, Step 8's verdict uses
the Remediation Proposals format instead of the standard numbered-issue-list format — see Step 8.

**Completeness** — all required sections and decisions are present per the phase template and
the bootstrap document's phase structure. No placeholder content remains in substantive fields.

**Internal consistency** — no unresolved contradictions between sections.

**GPG alignment** — read `standards/GenericProjectGuidlines_Sections/GenericProjectGuidlines_TOC.md`
and, for chapter applicability, the bootstrap document's GPG Reading Map (Always-Read-by-Phase
and Conditional-by-Task-Content tables). A chapter is **applicable** to this phase document when
it is Always-Read for this workflow stage, or its Conditional trigger topic matches what the
solution actually builds or decides — regardless of whether the phase document happens to
mention that topic. (No project-level `gpg_excluded_chapters` exclusion applies at this scope —
that field is populated per-project starting at Phase 7 decomposition; solution-scoped phases
1-7 have no such list to consult.) For each applicable chapter: verify the document's choices
align with GPG guidance for that chapter, or that an omission or divergence carries an explicit,
documented rationale. An applicable chapter the document is simply silent on, with no rationale,
is itself a finding — not a pass by default. An undocumented GPG divergence is likewise a
finding, as before.

**Readiness for next phase** — the phase document contains enough detail and enough settled
decisions for the next phase to begin work without circular dependencies or unresolved
prerequisites.

**Concept and Expanded Concept gates only — source coverage:** if this phase's own
`[phase]_state.json` carries a `source_document` field (a tracked source doc exists for this
cycle): confirm `sdp_source_coverage.completed` is `true` and its `source_document` value matches
the tracked reference. Absent or `false` is a finding — this phase cannot pass gate review until
`sdp-solution-source-coverage-check` has certified. If the field is absent (conversational intake, no
tracked source for this cycle): not applicable, no finding, standard four criteria only.

**Architecture and Implementation Overview gates only — Pros-Cons-Gaps cycle ran:** read this
phase's own `[phase]_state.json` for `pros_cons_gaps.cycle_count`. Absent or `0` is a finding —
this phase cannot pass gate review until at least one Pros-Cons-Gaps cycle has actually run, per
the bootstrap doc's Pros-Cons-Gaps Cycle section. This criterion only confirms the cycle
mechanism ran at all — it does not re-derive gap resolution itself; a document that ran the
required cycles but still carries an undisclosed, unaddressed gap is still caught by the
Completeness criterion above, same as any other missing content.

**Phase Readiness gates only — full-lifecycle traceability audit (always eleven criteria total,
never ten):**

- **`.speq`/Context population:** for every project that received decomposed tasks in its
  `.sdp-workflow/registry.md` for the first time this cycle (per
  `sdp-solution-phase-coordinator` Step 2b item 0), its `.speq.md` and `[PROJECT]-Context.md`
  contain real, settled content — no template placeholder text remaining. A project merely
  re-entering decomposition in a later mid-stream cycle, whose files were already populated
  previously, is not re-checked here.
- **Traceability:** if a tracked source doc exists (`user-design-docs/processed/[file]`), trace
  every element in that original source doc forward through every solution-level phase
  deliverable to the final plan and each project's decomposed `registry.md` — every element must
  land somewhere. If no source doc exists, trace from `sdp-solution-docs/01_concept.md` instead.
  Any element with no downstream landing is a finding.
- **Rightsizing:** each decomposed row, in each affected project's own `registry.md`, is a unit
  of work one WORKER dispatch sequence can reasonably complete.
- **Dependency ordering:** the Depends On column across all decomposed rows (within each
  project, and across the cross-project dependency edges) is complete, acyclic, and walkable.
  Within a single project's assigned tasks for the same phase, a task carrying an unresolved
  cross-project dependency should not be ordered ahead of independent, unblocked tasks where
  avoidable — flagged as a finding if it would foreseeably stall independent work.
- **Acceptance criteria completeness:** every work item across every decomposed phase, in every
  affected project, has acceptance criteria written.
- **GPG chapter assignment:** each decomposed phase's state file has a `gpg_chapters` field
  present (empty array is acceptable — absence is the finding).
- **Dependency edge validity:** every edge declared in `.sdp-solution-workflow/dependencies.json`
  references a real project + task (a task ID that actually exists in that project's assigned
  registry rows) or, for a decision-only edge (`producer.type == "decision"`), a `criterion_text`
  that appears verbatim in the named producer task's acceptance criteria. An edge referencing a
  nonexistent project, task, or criterion text is a finding, same severity class as the other
  five.

Record all findings — both pass and fail — per criterion. Do not form a verdict yet.

### Step 7: Re-Gate Check (Re-Gate Cycles Only)

If the Step 3 script result had `is_regate_cycle == true`:

1. Read the prior GATE_BLOCKED blockquote text from `prior_gate_blocked_blockquotes` — already
   extracted; do not re-read the phase document file for this.
2. For each issue listed in a prior blockquote: confirm whether `phase_document_content` now
   addresses it.
3. Incorporate these findings into the Step 6 assessment: resolved issues noted as resolved,
   still-open issues carried forward, new issues added.

Skip this step entirely if `is_regate_cycle == false`.

### Step 8: Append Gate Verdict Blockquote

Append the gate verdict blockquote to the end of the **actual phase document file** at
`sdp-solution-docs/[phase_document_path]` (from the Step 3 script result) — not to the stripped
`phase_document_content` value, which is an assessment-only copy.

```markdown
> **Gate Verdict — [GATE_PASSED | GATE_BLOCKED] — [YYYY-MM-DD HH:MM]**
> Reviewer: [session_id from Step 3]
> [GATE_PASSED: brief confirmation of what was verified and the basis for passing. Reference
>  each assessment criterion.]
> [GATE_BLOCKED, non-Phase-Readiness gate: numbered list of specific issues with section
>  references and required changes before the gate can pass.]
```

**Phase Readiness gate, GATE_BLOCKED only** (any of the six extra criteria): use this format
instead —

```markdown
> **Gate Verdict — GATE_BLOCKED — [YYYY-MM-DD HH:MM]**
> Reviewer: [session_id from Step 3]
> **Traceability gap identified — originates at [Phase Name].**
> [Description of the gap/misalignment and why it originates there.]
>
> **Remediation Proposals:**
> 1. **Target Phase:** [exact .sdp-solution-workflow/registry.md Phase column value] — [one-line
>    description, from full re-phase rework to a small targeted edit]
> 2. **Target Phase:** [exact registry.md Phase column value] — [description]
> 3. **Target Phase:** [exact registry.md Phase column value] — [description]
```

Up to 3 proposals. Every `Target Phase:` value must be copied verbatim from the **solution's
own** `.sdp-solution-workflow/registry.md` Phase column — `sdp-solution-phase-coordinator`'s Step 2e
regression handling matches against this value literally.

**Verdict rules:** identical to `sdp-project-gate-review`'s — GATE_PASSED requires all criteria to pass
with no material findings; any material finding blocks the gate; never issue GATE_PASSED to
avoid a GATE_BLOCKED.

Determine the issue count `N` (0 for GATE_PASSED; the number of numbered issues for
GATE_BLOCKED) — passed to Step 9.

### Step 9: Run Script — Finalize

Run:
```
./sdp-shared/scripts/sdp-solution-phase-gate-review-finalize.ps1 -Verdict [GATE_PASSED|GATE_BLOCKED] -IssueCount [N] -Phase [current_phase]
```
No `-workspaceRoot` — the script self-resolves. Same no-parseable-result handling as Step 1.

Branch on `status`:

- **`"error"`** — Invoke `/sdp-create-banner icon=error row=0 row: Error | [error]`. Halt.
- **`"success"`** — The script has already: incremented `phase_gate.gate_eval_cycles`, set
  `phase_gate.status` to `"passed"` or `"blocked"`, set `updated`, and — on GATE_BLOCKED —
  invoked `sdp-tone.ps1 -trigger "gate.blocked"` as a non-blocking side effect. Proceed to Step 10.

Do not advance `current_phase`. Do not reset `phase_gate`. Those are `sdp-solution-phase-coordinator`
actions, not GATE_REVIEWER actions.

### Step 9a: Commit and Push Gate Output

Run `git status`. If any untracked or modified files exist that are not covered by
`.gitignore`, stage and commit ALL of them — do not enumerate a specific file list. This includes
the Gate Verdict blockquote (Step 8) and `.sdp-solution-workflow/state.json`'s `phase_gate`
update (Step 9). Push via `./sdp-shared/scripts/sdp-github.ps1 push` (PowerShell tool) — read the
JSON envelope: `status: "pushed"` confirms success; an `ok:false`/`status:"error"` envelope means
the push failed — invoke `/sdp-create-banner icon=error row=0 row: Error | Git push failed —
[error from the envelope]. Resolve manually before this session ends.` Skip this step if the
working tree is already clean. Note in the Step 10 report whether a commit was required.

### Step 10: Session End

Invoke `/sdp-create-banner` with the Step 9 script result's `[user_report]` content as the row
content (already fully templated): on GATE_PASSED use `icon=success row=0 row: Status |
[user_report]`; on GATE_BLOCKED use `icon=error row=0 row: Status | [user_report]`. Session ends
here. Do not spawn subagents. Do not perform `sdp-solution-phase-coordinator` actions.

## Constraints

- Never invoked for a project-level gate review — that is `sdp-project-gate-review`'s exclusive job.
  This skill exists only for solution-scoped phases 1-7.
- Never invokes and is never invoked by `sdp-project-gate-review` — no dependency in either direction,
  no `-scope` parameter anywhere in this skill's own procedure or its three backend scripts.
- Never review at single-task granularity — the phase document is the review unit.
- Do not read the prior GATE_BLOCKED blockquote before completing the independent assessment in
  Step 6, and do not open the actual phase document file at that point either — the Step 3
  script's line-numbered `phase_document_content` already provides everything needed to cite
  findings by line.
- Do not advance `current_phase`, reset `phase_gate`, or spawn subagents.
- Do not write `gate_review_attempts` — owned by `sdp-solution-state-loop`.
- A GATE_PASSED verdict requires all four criteria — five when the Concept/Expanded Concept
  source-coverage criterion or the Architecture/Implementation Overview Pros-Cons-Gaps criterion
  applies (never both — the two phase sets are disjoint), or, for Phase Readiness, all eleven — to
  pass with no material findings.
- The Gate Verdict blockquote is distinct from the Doc Review Certification Blockquote.
- The LLM never writes `.sdp-solution-workflow/state.json` directly — all three scripts own
  every state write between them. The only file the LLM edits directly is the phase document
  itself (Step 8). Step 9a's git operations act on already-written content.
- Step 9a must run before Step 10 whenever the working tree is dirty.
- Never pass a fabricated or inferred verdict to Step 9's `-Verdict` argument.
- Never append the Step 8 Gate Verdict blockquote to the stripped `phase_document_content`
  assessment-only copy.

## Outputs

- Gate verdict blockquote appended to the phase document (Step 8, LLM-written)
- `.sdp-solution-workflow/state.json` updated: `phase_gate.gate_eval_cycles` incremented,
  `phase_gate.status` set (Step 9, script-written); `workflow_status`/`halt_reason` set on a
  Step 1 GPG halt
- Working tree committed and pushed (Step 9a)
- `.sdp-solution-workflow/logging/workflow-logs/workflow-log-<local-yyyyMMdd>.jsonl` — one
  `gate.verdict` entry written by `sdp-solution-phase-gate-review-finalize.ps1`
- User-facing outcome report
