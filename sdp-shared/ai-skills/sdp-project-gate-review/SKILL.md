## Purpose

Before this skill existed, gate reviews were manual operations in all orchestration modes —
the loop terminated when all tasks in a phase were VERIFIED, and the user had to manually
trigger and interpret the gate. After implementation: passing gates run automatically in
loop-orchestrated mode with no user touch; blocked gates halt with a structured, numbered
issue list (section-referenced) rather than a stuck loop or ambiguous halt. Agents identify
and categorize variances against completeness, consistency, and GPG alignment — resolution
of GATE_BLOCKED issues remains a human action.

This skill executes a GATE_REVIEWER session for a **project's** own phase document — not a
solution-level one. It is invoked exactly as it always has been: project-scoped, via
`-workspaceRoot .\[resolved_project]`. Solution-scoped phases 1-7 gate reviews are
`sdp-solution-phase-gate-review`'s exclusive job — see that skill for those; this skill never accepts
a solution-scoped dispatch and has no parameter to request one.

A GATE_REVIEWER session reviews an entire phase document — not a single task. Its output is the
gate verdict blockquote and `phase_gate.status` update; it does not advance `current_phase`,
reset `phase_gate`, or spawn subagents.

**Hybrid model:** a **multi-boundary**
hybrid — three separate scripts own every deterministic block, with two LLM-judgment phases
in between that no script can perform:

- `sdp-gate-review-gpg-check.ps1` (Step 1) — GPG existence check; writes the Halt Behavior
  Contract state on failure.
- `sdp-gate-review-setup.ps1` (Steps 3–5) — reads the dispatch file, cross-checks
  `current_phase`, reads the phase document, strips any prior Gate Verdict blockquote(s) from
  the content handed to the LLM's independent assessment, and separately surfaces prior
  `GATE_BLOCKED` blockquotes for the re-gate check.
- `sdp-gate-review-finalize.ps1` (Steps 9–10) — takes the LLM's verdict as an explicit
  `-Verdict` argument (never inferred by the script — this is the Corrupting-risk mitigation
  from the eval), updates `phase_gate` state, plays the `gate.blocked` tone on a blocked
  verdict, records a `gate.verdict` entry to `workflow-logs/` on either outcome, and returns
  the fully-templated user report.

All three take `-workspaceRoot .\[resolved_project]` — no `-scope` parameter exists on any of
them, and none is ever needed: this skill is always project-scoped.

## Inputs

- `[resolved_project]/.sdp-workflow/state.json` — read by all three scripts; provides
  `current_phase`, `phase_gate.status`, `phase_gate.gate_eval_cycles`, `gpg_version`, and
  `last_session`.
- `[resolved_project]/.sdp-workflow/sessions/[last_session].md` (dispatch file) — read by
  the setup script; provides role confirmation, phase document path, and re-gate trigger
  reason if applicable
- Completed phase document — read by the setup script; path provided in the dispatch file
- `standards/GenericProjectGuidlines_Sections/GenericProjectGuidlines_TOC.md` — required for
  GPG alignment check (Step 6); read directly by the LLM, not by any script
- Prior GATE_BLOCKED blockquote(s) — present in the phase document on re-gate cycles only;
  surfaced by the setup script's `prior_gate_blocked_blockquotes` output field

## Procedure

### Step 1: Run Script — GPG Check

Run `./sdp-shared/scripts/sdp-gate-review-gpg-check.ps1 -workspaceRoot .\[resolved_project]`
via the PowerShell tool.

If the PowerShell tool call produces no parseable single-line JSON on stdout (regardless of
exit code): invoke `/sdp-create-banner icon=error row=0 row: Status | Script invocation
failed — no result to parse. Verify sdp-shared/scripts/sdp-gate-review-gpg-check.ps1 is
present and the permission entry in .claude/settings.local.json is registered.` and halt.

Parse the single-line JSON result. Branch on `status`:

- **`"error"`** — Invoke `/sdp-create-banner icon=error row=0 row: Error | [error]`. Halt.
  (Covers a missing or unparseable `state.json`, or a missing `gpg_version` field.)
- **`"halted"`** — The script has already written `workflow_status: "halted"` and
  `halt_reason` to `state.json` (per the Halt Behavior Contract) when `state_json_written` is
  `true`. Invoke `/sdp-create-banner icon=error row=0 row: Status | [halt_message]`. Halt.
- **`"success"`** — Proceed to Step 2.

### Step 2: SUPERPOWERS CHECK

Verify Superpowers plugin is installed by running `/plugin list`. If installed: Superpowers
code review may be used as a thinking aid before writing the formal gate verdict blockquote;
invoke explicitly — auto-triggering is prohibited. Superpowers output does NOT substitute for
the Bootstrap Gate Verdict blockquote — the formal assessment is still required. Missing
Superpowers does not block this session.

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

### Step 3: Run Script — Setup (Read Dispatch File, Read Workflow State, Read Phase Document)

Run `./sdp-shared/scripts/sdp-gate-review-setup.ps1 -workspaceRoot .\[resolved_project]` via
the PowerShell tool. Same no-parseable-result handling as Step 1.

Parse the single-line JSON result. Branch on `status`:

- **`"error"`** — Invoke `/sdp-create-banner icon=error row=0 row: Error | [error]`. Halt.
  (Covers a missing or unparseable `state.json` — an operational failure prior to any
  session-specific check.)
- **`"halted"`** — Invoke `/sdp-create-banner icon=error row=0 row: Status | [halt_message]`.
  Halt. (Covers: no `last_session` recorded; the dispatch file not found; the dispatch file's
  `Role:` field not equal to `GATE_REVIEWER`; no `Phase Document:` field in the dispatch file;
  `current_phase` not matching the dispatch file's `Work Item:` field; or the phase document
  itself not found. None of these write to `state.json` — only the Step 1 GPG case does.)
- **`"success"`** — Record `session_id`, `role_confirmed`, `current_phase`,
  `phase_gate_status` (`"pending"` for a first gate, `"blocked"` for a re-gate),
  `gate_eval_cycles`, `phase_document_path`, `is_regate_cycle`, `regate_trigger_reason`,
  `phase_document_content` (the phase document's content with any prior Gate Verdict
  blockquotes already stripped — this is what Step 6's independent assessment must be formed
  from), and `prior_gate_blocked_blockquotes` (an array of the prior `GATE_BLOCKED`
  blockquote text, present only when `is_regate_cycle` is `true`). Proceed to Step 6.

### Step 6: Assess Independently

Assess `phase_document_content` from the Step 3 script result independently against all four
criteria. This content already has any prior Gate Verdict blockquote stripped — do not read
the actual phase document file at this point, and do not read `prior_gate_blocked_blockquotes`
before completing this step.

**Phase Readiness detection:** if `current_phase` (from the Step 3 script result) contains the
substring "Phase Readiness", this gate review also assesses five additional criteria (below), in
addition to the standard four. On any Phase-Readiness-specific finding, Step 8's verdict uses the
Remediation Proposals format instead of the standard numbered-issue-list format — see Step 8.
A project-level "Phase Readiness" phase is a transient artifact of a solution still mid-migration
under the pre-2026-07-20 project-scoped model (see the solution-coordinator-orchestration-design
doc's Section 11) — phases 1-7 run exclusively at solution scope for every solution scaffolded
after that design shipped, and that case is `sdp-solution-phase-gate-review`'s job, never this skill's.

**Completeness** — all required sections and decisions are present per the phase template and
the bootstrap document's phase structure. No placeholder content (TBD / TBC / "to be
determined") remains in substantive fields.

**Internal consistency** — no unresolved contradictions between sections. Decisions recorded
in earlier sections are reflected consistently in later sections. No section assumes a
different choice than the one recorded.

**GPG alignment** — read
`standards/GenericProjectGuidlines_Sections/GenericProjectGuidlines_TOC.md`. Cross-reference
its section titles against this phase document's content and decisions. For each chapter whose
topic appears in the phase document: verify the document's choices align with GPG guidance for
that chapter. A GPG divergence that is undocumented (no explicit rationale in the phase
document) is a finding.

**Readiness for next phase** — the phase document contains enough detail and enough settled
decisions for the next phase to begin work without circular dependencies or unresolved
prerequisites. If the next phase begins with a task that has an unsatisfied input, name it
as a finding.

**Phase Readiness gates only — full-lifecycle traceability audit:**

- **Traceability:** if a tracked source doc exists (`user-design-docs/processed/[file]`), trace
  every element in that original source doc forward through every phase deliverable to the final
  plan and decomposed `registry.md` — every element must land somewhere. If no source doc exists,
  trace from `01_concept.md` instead. Any element with no downstream landing is a finding.
- **Rightsizing:** each decomposed `registry.md` row is a unit of work one WORKER dispatch
  sequence can reasonably complete.
- **Dependency ordering:** the Depends On column across all decomposed rows is complete,
  acyclic, and walkable.
- **Acceptance criteria completeness:** every work item across every decomposed phase has
  acceptance criteria written.
- **GPG chapter assignment:** each decomposed phase's state file has a `gpg_chapters` field
  present (empty array is acceptable — absence is the finding).

There is no dependency-edge-validity criterion here — a project-level phase never has a
cross-project dependency ledger; that criterion exists only in `sdp-solution-phase-gate-review`,
where the ledger always exists.

Record all findings — both pass and fail — per criterion. Do not form a verdict yet.

### Step 7: Re-Gate Check (Re-Gate Cycles Only)

If the Step 3 script result had `is_regate_cycle == true`:

1. Read the prior GATE_BLOCKED blockquote text from the Step 3 script result's
   `prior_gate_blocked_blockquotes` array — already extracted; do not re-read the phase
   document file for this.
2. For each issue listed in a prior blockquote: confirm whether `phase_document_content`
   (from Step 3) now addresses it. An issue is addressed if the content contains a clear,
   specific resolution matching the flagged concern. An unchanged or partially-changed section
   does not address the issue.
3. Incorporate these findings into the assessment from Step 6:
   - Prior issues now resolved: note as resolved in the verdict
   - Prior issues still open: carry them forward as findings
   - New issues discovered independently: include as additional findings

Skip this step entirely if `is_regate_cycle == false` (first gate cycle).

### Step 8: Append Gate Verdict Blockquote

Append the gate verdict blockquote to the end of the **actual phase document file** at
`[resolved_project]/[phase_document_path]` (from the Step 3 script result — already relative to
`[resolved_project]`) — not to the stripped `phase_document_content` value, which is an
assessment-only copy. The real file still holds any prior Gate Verdict blockquote(s); appending
below them preserves the append-only history:

```markdown
> **Gate Verdict — [GATE_PASSED | GATE_BLOCKED] — [YYYY-MM-DD HH:MM]**
> Reviewer: [session_id from Step 3]
> [GATE_PASSED: brief confirmation of what was verified and the basis for passing. Reference
>  each assessment criterion.]
> [GATE_BLOCKED, non-Phase-Readiness gate: numbered list of specific issues with section
>  references and required changes before the gate can pass. Each issue must be specific enough
>  for a WORKER to act on without further clarification.]
```

**Phase Readiness gate, GATE_BLOCKED only** (a traceability/rightsizing/dependency/acceptance-
criteria/GPG-chapter finding from Step 6's five extra criteria): use this format instead of the
plain numbered-issue-list body above —

```markdown
> **Gate Verdict — GATE_BLOCKED — [YYYY-MM-DD HH:MM]**
> Reviewer: [session_id from Step 3]
> **Traceability gap identified — originates at [Phase Name].**
> [Description of the gap/misalignment and why it originates there.]
>
> **Remediation Proposals:**
> 1. **Target Phase:** [exact registry.md Phase column value] — [one-line description of this
>    remediation's scope, from full re-phase rework to a small targeted edit]
> 2. **Target Phase:** [exact registry.md Phase column value] — [description]
> 3. **Target Phase:** [exact registry.md Phase column value] — [description]
```

Up to 3 proposals, spanning full re-phase rework to a small targeted edit. Every `Target Phase:`
value must be copied verbatim from `registry.md`'s Phase column for the row being proposed —
`sdp-project-coordinator`'s regression handling (Step 4 sub-step 5) matches against this value literally.

**Verdict rules:**
- GATE_PASSED: all four criteria pass with no material findings. Minor findings that do not
  affect the next phase may be noted but do not block the gate.
- GATE_BLOCKED: any material finding in any criterion blocks the gate. List every material
  issue — a GATE_BLOCKED verdict with incomplete findings will require another re-gate cycle.
- Do not issue a GATE_PASSED verdict to avoid a GATE_BLOCKED. The cost of a false pass is
  a WORKER session built on a flawed foundation.

Determine the issue count `N` (0 for GATE_PASSED; the number of numbered issues for
GATE_BLOCKED) — this is passed to Step 9.

### Step 9: Run Script — Finalize

Run:
```
./sdp-shared/scripts/sdp-gate-review-finalize.ps1 -workspaceRoot .\[resolved_project] -Verdict [GATE_PASSED|GATE_BLOCKED] -IssueCount [N] -Phase [current_phase]
```

Same no-parseable-result handling as Step 1.

Branch on `status`:

- **`"error"`** — Invoke `/sdp-create-banner icon=error row=0 row: Error | [error]`. Halt.
  (Covers an invalid `-Verdict` value, a missing or unparseable `state.json`, or the state
  write itself failing.)
- **`"success"`** — The script has already: incremented `phase_gate.gate_eval_cycles`, set
  `phase_gate.status` to `"passed"` or `"blocked"`, set `updated` to today's ISO date, and — on
  a `GATE_BLOCKED` verdict — invoked `sdp-tone.ps1 -trigger "gate.blocked"` as a non-blocking
  side effect. Proceed to Step 10.

Do not advance `current_phase`. Do not reset `phase_gate`. Do not set `active_work_item`.
Those are COORDINATOR actions, not GATE_REVIEWER actions — and the script does not perform them
either.

### Step 9a: Commit and Push Gate Output

Run `git status`. If any untracked or modified project files exist that are not covered by
`.gitignore`, stage and commit ALL of them — do not enumerate a specific file list. This
includes the Gate Verdict blockquote just appended to the phase document (Step 8),
`state.json`'s `phase_gate` update (Step 9), and any other uncommitted project files found —
do not enumerate a specific file list. Push via `./sdp-shared/scripts/sdp-github.ps1 push`
(PowerShell tool) — read the JSON envelope: `status: "pushed"` confirms success; an
`ok:false` / `status:"error"` envelope means the push failed — invoke `/sdp-create-banner
icon=error row=0 row: Error | Git push failed — [error from the envelope]. Resolve manually
before this session ends.`, not silently treated as session end. Skip this step if the working
tree is already clean. Note in the Step 10 report whether a commit was required and what it
contained.

**Why this step exists:** unlike `sdp-project-reviewer` (which sweeps before verification) and
`sdp-project-worker` (which commits after implementation), `sdp-project-gate-review` previously had no
commit/push step at all — its Gate Verdict blockquote and the `phase_gate.status` update from
Step 9 were left uncommitted at session end. A subsequent `sdp-project-state-loop` Halt Evaluation
firing for an unrelated reason would then see that uncommitted verdict and misreport the halt
cause as `UNCOMMITTED_CHANGES`, when the real blocker was whatever findings the verdict itself
raised.

### Step 10: Session End

Invoke `/sdp-create-banner` with the Step 9 script result's `[user_report]` content as the row
content (already fully templated — do not paraphrase or reconstruct it): on a `GATE_PASSED`
verdict use `icon=success row=0 row: Status | [user_report]`; on a `GATE_BLOCKED` verdict use
`icon=error row=0 row: Status | [user_report]`. Session ends here. Do not spawn subagents. Do
not perform COORDINATOR actions.

## Constraints

- Never accepts a solution-scoped dispatch — this skill has no `-scope` parameter and is never
  invoked for phases 1-7. `sdp-solution-phase-gate-review` is the sole solution-scoped counterpart.
- Never review at single-task granularity — the phase document is the review unit; task-level
  review is `sdp-project-reviewer`'s job, not GATE_REVIEWER's.
- Do not read the prior GATE_BLOCKED blockquote before completing the independent assessment
  in Step 6. Context contamination from a prior blocked verdict is the failure mode this rule
  prevents — this is why the Step 3 script strips prior Gate Verdict blockquotes from
  `phase_document_content` before Step 6 ever sees it.
- Do not advance `current_phase`, reset `phase_gate`, or spawn subagents. Those are
  COORDINATOR responsibilities.
- Do not write `gate_review_attempts` — that field is owned by `sdp-project-state-loop`.
- A GATE_PASSED verdict requires all four criteria to pass with no material findings.
  Do not issue GATE_PASSED to avoid a GATE_BLOCKED.
- A Phase Readiness gate (`current_phase` contains "Phase Readiness") requires all nine
  criteria (the standard four plus the five traceability-audit criteria) to pass — this case
  is a transient migration artifact for a solution still mid-migration to the solution-scoped
  model (see the design doc's Section 11); it is not the normal path. A finding in any
  Phase-Readiness-specific criterion uses the Remediation Proposals verdict format (Step 8),
  never the standard numbered-issue-list format.
- The Gate Verdict blockquote is distinct from the Doc Review Certification Blockquote
  (`**Doc Review — …**`). A Doc Review certification does not substitute for gate review.
- The LLM never writes `state.json` directly in this skill — all three scripts own every
  state write between them (the Step 1 GPG halt write, and the Step 9 `phase_gate` update).
  The only file the LLM edits directly is the phase document itself (Step 8's Gate Verdict
  blockquote). Step 9a's `git add`/`commit`/`push` are shell operations on already-written
  content, not a new file write.
- Step 9a must run before Step 10 whenever the working tree is dirty — do not end the session
  with an uncommitted Gate Verdict blockquote or `phase_gate` update.
- Never pass a fabricated or inferred verdict to Step 9's `-Verdict` argument — it must be the
  LLM's actual Step 6–8 determination; the script trusts this value completely and does not
  re-derive it. This is the Corrupting-risk mitigation the eval calls for.
- Never append the Step 8 Gate Verdict blockquote to the stripped `phase_document_content`
  assessment-only copy — it must be appended to the actual phase document file at
  `[resolved_project]/[phase_document_path]`.

## Outputs

- Gate verdict blockquote appended to the phase document (Step 8, LLM-written)
- `state.json` updated: `phase_gate.gate_eval_cycles` incremented, `phase_gate.status` set
  to `"passed"` or `"blocked"` (Step 9, script-written); `workflow_status`/`halt_reason` set
  on a Step 1 GPG halt
- Working tree committed and pushed (Step 9a) — the phase document and `state.json` changes
  from this session are never left uncommitted
- `.sdp-solution-workflow/logging/workflow-logs/workflow-log-<local-yyyyMMdd>.jsonl` — one
  `gate.verdict` entry (GATE_PASSED or GATE_BLOCKED) written by `sdp-gate-review-finalize.ps1`
  as a non-blocking side effect of Step 9, pointing back to the phase document's Gate Verdict
  blockquote for the full assessment rather than duplicating it
- User-facing outcome report (halt/error messages from any step, or the Step 9
  `user_report` on completion)
