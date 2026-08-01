## Purpose

Review a target SDP document for open decisions, informally resolved items, concerns, and
implementation blockers. Surface each item to the user one at a time, resolve it with the
user, lock the resolution into the document before moving to the next item, and certify the
document as gate-ready. After certification, no items remain open or deferred inside
`sdp-docs/`.

This skill is doc-scoped, not task-scoped — it is distinct from `sdp-project-pre-work-verify`, which
checks whether task-level work has already been done. The two are not interchangeable.

## Inputs

- **Target doc path** — required. Must be provided by the user when invoking the skill
  directly (user-invoked trigger), or established by agent context when the skill is run as
  part of staging (agent-staged trigger). If not established, ask the user to provide the path
  before proceeding.
- **Associated state file** — required for Step 4 (Certify). Typically the `[phase]_state.json`
  file associated with the doc, or `.sdp-workflow/state.json` for non-phase docs. If the
  associated state file is not obvious from context, ask the user.
- **Session identifier** — used in the certification blockquote and state file entry. Use the
  current session's `session-NNN` identifier from `state.json`, or `"user-invoked"` when the
  skill is triggered directly by the user outside the SDP workflow.

## Procedure

### Step 1: Identify Target Doc

1. Confirm the target doc path is established (from user input or agent context). If not:
   ask the user to provide it before continuing.
2. Read the full target document using the Read tool.
3. Identify the associated state file. If uncertain, ask the user to confirm.

### Step 2: Review — Identify All Items

Read the full document and identify every item in any of the following categories:

- **Open decisions** — content phrased as a question; marked TBD / TBC; flagged "confirm at
  gate", "proposed — finalize at gate", or "(resolve at plan gate)"; or structured as a
  decision without a locked marker below it
- **Informally resolved** — content that reads as open but appears to have been resolved in
  conversation and not written back (e.g., a question followed by prose that implies an answer
  but no locked entry below it)
- **Concerns** — content that is internally inconsistent, conflicts with project constraints
  or the `.speq` contract, or is likely to cause a WORKER to stall or make an incorrect
  implementation choice
- **Implementation blockers** — missing information a WORKER would need before starting

Record every identified item internally before surfacing any. Order items by document position.
Do not surface any item during this step — complete the full scan first.

If no items are identified: report that to the user, skip Step 3, and proceed directly to
Step 4 (Certify).

### Step 3: Surface, Resolve, and Lock In (one item at a time)

Work through items in order. Complete the full Surface → Resolve → Lock In cycle for each
item before moving to the next.

**Surface** — present the item to the user:
- Quote or reference the exact content from the doc
- State the category: open decision / informally resolved / concern / blocker
- Where options exist: present them with a recommendation and rationale

**Resolve** — work the item to a closed state with the user. An item is closed only when one
of the following is true:
- A resolution has been agreed and is ready to be written into the doc
- The user explicitly defers the item (see Deferral Rules below)

Do not surface the next item until the current item is closed. A conversation answer alone
does not close an item — the resolution must be written into the doc first (see Lock In
below).

If an item cannot be resolved and cannot be deferred: surface the blocker explicitly and halt.
Do not proceed to remaining items. Also record the block (non-blocking — ignore any failure and
continue): run `./sdp-shared/scripts/sdp-workflow-log.ps1 -trigger "doc_review.blocker" -role
"DOC_REVIEWER" -outcome "HALTED" -reason "[item description] - cannot be resolved or
deferred"` via the PowerShell tool.

**Lock In** — immediately after the user confirms a resolution, write it into the doc before
surfacing the next item. Confirm the write with the user before applying it. Use the
Locked-Decision Format:

```markdown
## Decisions Locked — [YYYY-MM-DD]

| Decision | Locked Value | Rationale |
|----------|-------------|-----------|
| [decision title] | [the settled choice — specific, not a recommendation] | [why this option; reference to constraint or user direction] |
```

Append this section below existing content. If a Decisions Locked section already exists
(from a prior review cycle), append new rows to the existing table — do not create a second
section.

Locked decisions are binding. A WORKER that deviates from a locked value without a formal
amendment is non-compliant. A REVIEWER that finds an undisclosed deviation must record it as
a finding.

**Deferral Rules** — an item may be deferred only when the user explicitly directs it:
- **Doc in `sdp-docs/`:** Migrate the deferred item AND every reference to it out of the
  `sdp-docs/` file to a file in `docs/` before proceeding to the next item. Use an existing
  `docs/` file if appropriate; otherwise create one named for the topic. After migration, the
  `sdp-docs/` file must contain no reference to the deferred item.
- **Doc outside `sdp-docs/`:** Mark the item as deferred in place using the standard
  annotation. No migration required.

### Step 4: Certify

Perform this step only after all items from Step 2 are closed (resolved and written, or
deferred per Deferral Rules).

1. Confirm: the doc contains no open decisions, no unresolved concerns, no content a future
   agent could treat as open.
2. Confirm: the doc is ready to pass a gate review — a subsequent gate REVIEWER session should
   find no material issues.
3. Append the Doc Review Certification Blockquote to the end of the doc:

```markdown
> **Doc Review — [YYYY-MM-DD HH:MM]**
> Session: [session-NNN or "user-invoked"]
> Doc: [path to doc relative to workspace root]
> Outcome: Ready for gate review — no open decisions, no unresolved concerns.
> [If any items were deferred: "Deferred items migrated to docs/ — see [filename(s)]."]
```

4. Write the `sdp_doc_review` entry to the associated state file. If the state file already
   has an `sdp_doc_review` key (from a prior incomplete review), overwrite it:

```json
"sdp_doc_review": {
  "purpose": "Records that sdp-project-doc-review has been run against the associated doc. A completed entry means the reviewing agent found the doc ready for gate review — all decisions locked, no open blockers remaining. This flag does not substitute for gate review; a separate REVIEWER session is still required. COORDINATOR checks this flag on every staged state file at session start and runs sdp-project-doc-review in the same session if the flag is absent or false.",
  "completed": true,
  "completed_at": "[ISO 8601 datetime of certification]",
  "session": "[session-NNN or user-invoked]",
  "doc": "[path to doc relative to workspace root]"
}
```
5. Play the notification tone (non-blocking — ignore any failure and continue): run
   `./sdp-shared/scripts/sdp-tone.ps1 -trigger "milestone.doc_certified"` via the
   PowerShell tool.

## Constraints

- An item is not closed until its resolution is written into the doc. A conversation answer
  alone is not sufficient.
- Do not certify until every identified item is locked in writing or deferred per Deferral
  Rules.
- Never write decisions to a separate addendum — always write them directly into the doc.
- Never apply a write without explicit user confirmation.
- Do not surface the next item until the current item is fully closed (written or deferred).
- Never proceed to remaining items when an item cannot be resolved and cannot be deferred —
  surface the blocker explicitly and halt.
- Never defer an item unless the user explicitly directs it.
- Decisions may be locked only via this skill (user approval) or at plan gate (gate REVIEWER).
  An agent must never lock a decision outside these two authorized mechanisms.
- The Doc Review Certification Blockquote is distinct from the Gate Verdict blockquote
  (`**Gate Verdict — GATE_PASSED/GATE_BLOCKED — …**`). Do not treat a Doc Review blockquote
  as evidence that gate review has been performed; a separate REVIEWER session is still
  required before phases advance.
- This skill does not substitute for gate review. Doc review and gate review are two separate
  steps.

## Outputs

- Target doc updated with all resolved decisions in the Decisions Locked table format
- Doc Review Certification Blockquote appended to the target doc
- `sdp_doc_review` entry written (or overwritten) in the associated state file with
  `completed: true`
- If items were deferred: deferred content migrated from `sdp-docs/` to `docs/`; the
  certification blockquote notes the filenames of migration targets
