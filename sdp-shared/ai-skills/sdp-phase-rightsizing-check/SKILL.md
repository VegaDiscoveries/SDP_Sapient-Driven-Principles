## Purpose

Assess whether a phase's task volume is appropriately scoped for a single WORKER dispatch
sequence to complete without a mid-session discovery that the phase is too large — and, with
explicit user approval, restructure an oversized phase into multiple right-sized sub-phases
before any WORKER is ever dispatched against it.

This closes the gap where a WORKER, mid-implementation, discovers a phase is too big and
ad hoc splits it into sub-phases the user never reviewed in advance. That discovery must happen
here, before dispatch — not reactively, inside a WORKER session.

Invoked in two contexts:
- **At creation time** — immediately after **solution-level** Phase 7 decomposes remaining scope
  into build phases and assigns them across projects, evaluating each newly proposed phase **and
  its cross-project assignment** before its row in the **assigned project's own**
  `.sdp-workflow/registry.md` is treated as final — decomposed build-phase rows land only in the
  assigned project's own registry, never the solution's own registry (which holds phase 1–7 rows
  exclusively).
- **As a backstop** — one pass of `sdp-project-loop-prep`'s sweep across every not-yet-`[x]`-complete
  phase, catching phases that predate the Phase 5 sizing signal (see the bootstrap document's
  "Addition — 2026-07-13 — Phase 5 sizing signal" note, since corrected to reference Phase 7) or
  otherwise slipped through.

## Inputs

- Target phase document path + its `[phase]_state.json` — the task list to assess
- For the creation-time context: `.sdp-solution-workflow/state.json` (`current_phase ==
  'Phase Readiness'`, confirming decomposition context) plus **each affected project's own**
  `[resolved_project]/.sdp-workflow/registry.md` and `state.json` — the rows actually being
  assessed live there, not in the solution's own registry.
- For the backstop context: unchanged — `[resolved_project]/.sdp-workflow/registry.md` and
  `state.json`, required for split mechanics (row append, `Depends On` correction) and
  `current_phase`/general state context respectively.

## Procedure

### Step 1: Read the Phase Document and Its Task List

Read the full target phase document. Enumerate every task item
(`- [ ] **[TASK-ID]** ...`) and its scope as written.

### Step 2: Assess Right-Sizing

No numeric threshold substitutes for this judgment. Assess two distinct questions and record
findings for both before proposing anything:

**Phase-level:** does this phase, taken as a whole — its full task list, worked task-by-task
across however many WORKER sessions it takes — represent a unit of work that can be completed
without needing an ad hoc mid-session split? Weigh:
- Task count, and whether tasks span multiple unrelated subsystems, layers, or concerns
- Whether tasks have natural sequential/parallel boundaries that would form cleaner phase
  boundaries than the current single grouping
- Whether the phase's scope, attempted as a single arc, would plausibly span many dispatch
  cycles with no natural checkpoint in between

**Task-level:** is any individual task, on its own, oversized — spanning unrelated subsystems
with no natural stopping point within that one task?

### Step 3: Surface Findings

If the phase is appropriately sized and no task is individually oversized: invoke
`/sdp-create-banner icon=success row=0 row: Sizing | Phase [phase] is appropriately scoped — no split needed.`
Write an `sdp_rightsizing` entry to the phase state file:

```json
"sdp_rightsizing": {
  "purpose": "Records that sdp-phase-rightsizing-check has assessed this phase and found it appropriately scoped, or that a split has been executed. Does not substitute for sdp-project-doc-review or gate review.",
  "completed": true,
  "completed_at": "[ISO 8601 datetime]",
  "session": "[session-NNN or user-invoked]",
  "outcome": "no_split_needed"
}
```

Stop — do not proceed further.

If phase-level oversize is found: present the specific finding as plain text first — the
task-by-task breakdown, why it's oversized, and a recommended split plan (proposed sub-phase
count, a name and one-line scope for each, which existing tasks move to which sub-phase). Then
invoke
`/sdp-create-banner icon=warning row=0 row: Sizing | Phase [phase] is oversized — see task breakdown and split plan above. row: | row: Confirm | Approve this split plan, or provide a corrected version?`
Do not proceed to Step 4 without the user's explicit confirmation of the plan or a corrected
version of it. A recommendation is not confirmation.

If task-level oversize is found (independent of the phase-level question): present the specific
task and a recommended split into sub-tasks as plain text first. Then invoke
`/sdp-create-banner icon=warning row=0 row: Task Split | Task [task] is oversized — see recommended sub-task split above. row: | row: Confirm | Approve this split, or provide a corrected version?`
Do not proceed to Step 6 without confirmation.

### Step 4: Execute the Approved Split (Phase-Level)

On user confirmation of the plan (as presented, or as corrected):

1. For each new sub-phase, in the confirmed order: create its phase document file (following
   the project's existing phase-file naming convention — confirm the exact naming with the user
   if it's ambiguous how the original phase's convention extends, e.g. `05a_`, `05b_` vs. the
   project's own numbering scheme) containing the tasks assigned to it, and its own
   `[phase]_state.json` per the bootstrap document's phase state file template — every task
   `PENDING`, `eval_cycle_attempts: 0`.
2. Append one new row per sub-phase to `registry.md`, in the confirmed sequential order,
   chaining `Depends On` to the previous sub-phase in the chain — the first sub-phase inherits
   the original phase's own `Depends On` value. Never delete or renumber an existing row.
3. Do not delete the original phase row or document. In the **original phase document** (not
   the registry row — `registry.md` has no blockquote convention for this), append a
   strikethrough split note: "~~[original scope statement]~~ — split into phases [list] on
   [date]; see rationale below," followed by the rationale, matching the bootstrap document's
   append-only/strikethrough convention. Set the original row's Status column to `[x]` only if
   every task was redistributed into the new sub-phases; if any task remains in the original
   phase, leave Status as-is — the original phase continues to exist with its now-smaller scope.
4. **Downstream `Depends On` correction** (the bounded, disclosed exception to `registry.md`'s
   write scope — see Constraints): for every other row whose `Depends On` references the
   original (just-split) phase number, and that row has **no dispatch history** (no session
   recorded against it, no task in a status beyond `PENDING`), rewrite that cell to reference
   the new terminal sub-phase — the last one in the confirmed chain — instead of the original
   number. Record the prior value inline using the same strikethrough convention (e.g.,
   `~~5~~ 5d`) so a human scanning the table sees the correction without needing git history.
   A row that already has dispatch history is never touched — this scenario should not occur
   when this skill runs as part of `sdp-project-loop-prep`'s dependency-ordered sweep (nothing
   downstream has been touched yet by the time a split happens), but the guard applies
   regardless of invocation context.
5. Write an `sdp_rightsizing` entry (same shape as the no-split-needed case above, but
   `"outcome": "split_executed"` and a `"new_phases"` array listing the new registry row names)
   to **each** of the original phase's and the new sub-phases' state files — the original
   phase's own remaining scope (if any tasks were left behind) and every new sub-phase are all
   phases `sdp-project-loop-prep` will separately re-encounter in its walk, and each needs its own
   `sdp_doc_review` and `sdp_source_coverage` pass; recording `sdp_rightsizing` here only marks
   that *this* check has already run for each of them, not that the other two checks have.
6. Report the full set of changes made — new rows, new files, corrected cells — as plain text
   first. Then invoke
   `/sdp-create-banner icon=success row=0 row: Sizing | Split executed — see the full list of changes above.`

### Step 5: Re-Verification Note

A newly created sub-phase document is new content that has not been through `sdp-project-doc-review`.

- If this skill is running as part of `sdp-project-loop-prep`'s sweep: no special action needed here —
  the sweep's row-by-row walk will reach the newly appended rows in their turn and run
  `sdp-project-doc-review` (and `sdp-solution-source-coverage-check`, if the original phase traced to a tracked
  source doc) against them before the sweep considers the solution prepped.
- If this skill is invoked standalone (not from `sdp-project-loop-prep`): invoke
  `/sdp-create-banner icon=warning row=0 row: Sizing | New sub-phase documents still need sdp-project-doc-review before any of them can dispatch.`

### Step 6: Task-Level Split (No Registry Change)

For a confirmed task-level oversize: split the task in place within the same phase document and
phase state file — new `TASK-ID`s (e.g. `TASK-12a`, `TASK-12b`), each with its own acceptance
criteria drawn from the original task's scope. No `registry.md` involvement; no new files.

Write an `sdp_rightsizing` entry to the phase state file (`"outcome": "task_split_executed"`,
listing the new `TASK-ID`s in place of `"new_phases"`) — the phase itself has not gained new
rows and does not need re-review by `sdp-project-doc-review`/`sdp-solution-source-coverage-check` on this account
alone, but a future `sdp-project-doc-review` pass should still see the updated task list.

## Constraints

- Never execute a split — phase-level or task-level — without the user's explicit confirmation
  of the specific plan. Presenting a recommendation is not confirmation. This mirrors
  `sdp-project-doc-review`'s Deferral Rules discipline: an item is not closed by a conversational answer
  alone.
- The `registry.md` write authority granted here is a disclosed, bounded exception to
  `sdp-project-coordinator`'s write-scope constraint (`sdp-project-coordinator/SKILL.md`'s "the only write
  COORDINATOR may make to registry.md is the Status-flip" line). This skill may additionally:
  (a) append new rows for a confirmed split, and (b) correct a `Depends On` cell on a
  not-yet-dispatched row that referenced the just-split phase. No other registry.md write is
  authorized by this skill, and no other skill inherits this authority.
- Only correct a downstream `Depends On` cell on a row with no dispatch history. Never rewrite a
  cell on a row that already has a session recorded against it.
- Never delete or renumber an existing `registry.md` row.
- Never delete the original phase document, even after a split — only the original
  `registry.md` row's contents may change (per the row-editing rule above).
- Do not treat "avoiding an interruption" as success. An oversize finding — phase- or
  task-level — is always surfaced; silently deciding a borderline case is "probably fine" to
  avoid the conversation is a violation of this skill's purpose, not a shortcut.

## Outputs

- Zero or more new `registry.md` rows, phase document files, and phase state files
- Original phase document annotated with a strikethrough split note (only if a phase-level
  split occurred)
- Zero or more corrected `Depends On` cells (only on not-yet-dispatched downstream rows)
- `sdp_rightsizing` entry written to every phase state file this check reached a verdict on —
  the original phase (no-split), the original and all new sub-phases (phase-level split), or the
  original phase alone (task-level split)
- User-facing report of every change made, or a "no split needed" confirmation
