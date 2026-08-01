## Purpose

Walk every not-yet-`[x]`-complete phase in a project's `registry.md`, in dependency order, and
bring each to full readiness for unattended dispatch before the recurring loop starts.

This closes a specific gap: `sdp-project-coordinator`'s Doc Review check (Step 1.5) is scoped to
"active and in-progress phases only" — future phases are reviewed reactively, the moment the
loop reaches them. For a multi-hour unattended run, that means any open decision, coverage gap,
or oversized phase sitting in an unreviewed future phase becomes a mid-loop stop instead of
something resolved before the run ever starts. `sdp-project-loop-prep` is the pre-loop gate that doesn't
otherwise exist: it certifies every not-yet-complete phase — not just the active one — against
three checks (content readiness, source coverage, right-sizing) up front.

`sdp-project-loop-prep` orchestrates three other skills. It does not duplicate their logic and does not
modify them: `sdp-project-doc-review` runs completely unmodified; `sdp-source-coverage-check` and
`sdp-phase-rightsizing-check` are the two new checks this whole effort introduced, each already
built to run standalone or as part of this sweep.

## Inputs

- `SDP-Solution.json` — `projects` / `last_active_projects`, for scope resolution
- Per-project `.sdp-workflow/registry.md` and `.sdp-workflow/state.json`
- Per-project phase documents and phase state files

## Procedure

### Step 0: Await Session-Start Completion

1. Check whether the session-start hook triggered `sdp-initialize-sdp` in this session (the
   SessionStart hook's actual configured target — not `sdp-project-read-docs`/`sdp-solution-read-docs`,
   which are invoked separately, later, by other skills). Signs it was triggered but not yet
   confirmed: the `sdp-initialize-sdp` skill invocation appears in conversation context but its
   closing banner and one-sentence closing statement (its own Output Discipline/Outputs
   contract: opening banner, internal `sdp-solution-read-docs` invocation, closing banner, then
   exactly one short closing statement) have not yet been output.
2. If `sdp-initialize-sdp` is still in progress: halt by invoking `/sdp-create-banner icon=pending row=0 row: Status |
   sdp-project-loop-prep: awaiting session-start (sdp-initialize-sdp) completion before proceeding.`
   Resume from Step 0 once it outputs its closing banner and closing statement.
3. If `sdp-initialize-sdp` has completed (or was not triggered this session): proceed to Step 1.

### Step 1: Resolve Scope

1. If invoked with a project argument: validate it against `SDP-Solution.json`'s `projects`
   array. Valid → use it as the sole project in scope, skip to Step 2. Invalid → halt by
   invoking `/sdp-create-banner icon=error row=0 row: Status | Invocation argument '[value]'
   does not match any project registered in SDP-Solution.json. Available: [list].`
2. Otherwise, read `SDP-Solution.json`.
   - If unreadable: halt by invoking `/sdp-create-banner icon=error row=0 row: Status | Cannot
     prep — SDP-Solution.json not found at solution root.` Also record the halt (non-blocking —
     ignore any failure and continue): run
     `./sdp-shared/scripts/sdp-workflow-log.ps1 -trigger "loop_prep.halt" -role "LOOP_PREP"
     -outcome "HALTED" -reason "SDP-Solution.json not found at solution root"` via the
     PowerShell tool.
   - If `projects` is empty: halt by invoking `/sdp-create-banner icon=error row=0 row: Status |
     No projects registered in SDP-Solution.json — nothing to prep.` Also record the halt
     (non-blocking — ignore any failure and continue):
     run `./sdp-shared/scripts/sdp-workflow-log.ps1 -trigger "loop_prep.halt" -role "LOOP_PREP"
     -outcome "HALTED" -reason "No projects registered in SDP-Solution.json"` via the
     PowerShell tool.
   - If exactly one project is registered: use it without asking.
   - If multiple are registered: ask the user — "Prep just [last_active_projects[0] or the
     first registered project], or every registered project ([list])?" Do not assume either
     answer. Use the user's answer to set the in-scope project list.

### Step 2: Preflight Per Project

For each project in scope: run `./sdp-shared/scripts/sdp-preflight.ps1 -workspaceRoot
.\[project]` via the PowerShell tool.
- `ok:true` → this project proceeds to Step 3.
- `ok:false` → halt this project's prep per the Halt Behavior Contract (set `workflow_status`
  to `"halted"` in that project's `state.json`, `halt_reason` citing the envelope's `failures`),
  report it, and remove this project from the remaining walk — **do not abort prep for other
  in-scope projects.** Note the halted project in the final Step 6 summary. Also record the
  halt (non-blocking — ignore any failure and continue): run
  `./sdp-shared/scripts/sdp-workflow-log.ps1 -trigger "loop_prep.halt" -role "LOOP_PREP"
  -workItem "[project]" -outcome "HALTED" -reason "Preflight failed: [failures]"` via the
  PowerShell tool.

### Step 3: Build the Dependency-Ordered Row List

For each remaining in-scope project: read `registry.md`. Build an ordering of every row not
already marked `[x]` complete such that a row is only visited after every phase listed in its
`Depends On` column has either already been `[x]` complete before this sweep started, or has
already been visited by this sweep. This ordering is what makes
`sdp-phase-rightsizing-check`'s downstream `Depends On` correction safe — a split's correction
to a later row always lands before that row is ever touched.

If no valid ordering exists (a dependency cycle, or a `Depends On` entry naming a phase that
will never complete): halt this project's prep by invoking `/sdp-create-banner icon=error row=0
row: Status | No valid dependency ordering in registry.md for [project] — [describe the
cycle/unmet reference].` Remove this project from the remaining walk; continue with other
in-scope projects. Also record the halt (non-blocking —
ignore any failure and continue): run `./sdp-shared/scripts/sdp-workflow-log.ps1 -trigger
"loop_prep.halt" -role "LOOP_PREP" -workItem "[project]" -outcome "HALTED" -reason "No valid
dependency ordering in registry.md - [describe the cycle/unmet reference]"` via the PowerShell
tool.

### Step 4: Per-Row Sweep

For each row in the dependency-ordered list, in order:

1. Resolve the row's phase document and phase state file from `registry.md`'s Phase File column
   (never reconstruct the path from a naming convention).
2. **Content readiness** — if `sdp_doc_review.completed` is not `true` in the phase state file:
   run `sdp-project-doc-review` against the phase document, unmodified. This may itself pause pending
   the user's resolution of an open item — that is expected and correct, not a failure of this
   sweep. If already `true`: skip.
3. **Source coverage** — if `sdp_source_coverage.completed` is not `true` in the phase state
   file: run `sdp-source-coverage-check` against this phase. The check itself determines and
   reports whether a tracked source document even applies (it self-reports "not applicable" and
   writes no entry when none exists — do not pre-filter which rows get this check). If already
   `true`: skip.
4. **Right-sizing** — if `sdp_rightsizing.completed` is not `true` in the phase state file: run
   `sdp-phase-rightsizing-check` against this phase. If it executes a phase-level split: the
   newly appended `registry.md` rows are new, not-yet-`[x]` rows that also require all three
   checks — fold them into the remaining walk order (re-derive the dependency ordering from
   Step 3 to include them; they depend on each other in the confirmed split chain and on
   whatever the original phase depended on). If already `true`: skip.
5. Move to the next row in the (possibly extended) list. The sweep for a project is not done
   until every row that exists in its `registry.md` at the time of completion — including rows
   created mid-sweep by a split — has all three checks satisfied (or self-reported not
   applicable, for source coverage).

### Step 5: Write the Readiness Marker

Once every row for a project has satisfied Step 4 (walk fully drained, no new rows still
pending): write a `loop_prep` block to that project's `.sdp-workflow/state.json`:

```json
"loop_prep": {
  "purpose": "Informational record of the last full sdp-project-loop-prep sweep. Not read or enforced by sdp-auto or sdp-state-loop-start — those skills are never modified to gate on this field. Prep discipline, not a hard gate, is what ensures this sweep runs before /sdp-auto.",
  "completed_at": "[ISO 8601 datetime]",
  "session": "[session-NNN or user-invoked]",
  "rows_checked": [count],
  "splits_performed": [count]
}
```

### Step 6: Report and Hand Off

Report a full summary: projects covered, rows checked per project, splits performed (with new
row names), coverage gaps found and how each resolved, doc-review items resolved, and any
project halted during Step 2 or Step 3 with its reason. End that summary by invoking
`/sdp-create-banner icon=success row=0 row: Status | Prep complete for [project(s)] — run
/sdp-auto or /sdp-state-loop-start to begin the unattended loop.` Do not invoke either skill
directly — see Constraints.

## Constraints

- Never skip a row's three-part check to avoid an interruption. This skill's success is not
  measured by finishing without asking the user anything. Every ambiguity, gap, coverage miss,
  or right-sizing question that any of the three sub-checks surfaces is presented to the user in
  full — `sdp-project-loop-prep` must never downgrade, suppress, or auto-resolve a sub-check's finding
  to keep its own pass moving. If a sub-check pauses pending the user, this sweep pauses with it.
- Never modify `sdp-project-doc-review`, `sdp-project-gate-review`, `sdp-project-coordinator`, `sdp-project-worker`,
  `sdp-project-reviewer`, `sdp-auto`, or `sdp-state-loop-start`. This skill only calls the first
  unmodified, and defers to the rest unmodified.
- Never call `/sdp-auto` or `/sdp-state-loop-start` directly from within this skill — both
  explicitly forbid being invoked from within another SDP skill (loop proliferation risk); the
  user runs them separately after this skill's Step 6 report, exactly as they would without this
  skill existing.
- The dependency-ordered walk (Step 3) is mandatory. Never process a row before every phase in
  its `Depends On` column has been visited by this sweep or was already `[x]` complete beforehand
  — this is what makes `sdp-phase-rightsizing-check`'s downstream correction safe.
- Never report a project's sweep complete while any row — original or newly created — still has
  an unset check flag. A split occurring mid-sweep extends the walk accordingly.
- A project-level preflight or dependency-ordering failure (Step 2 or Step 3) halts that
  project's prep and is reported; it never aborts prep for other in-scope projects.
- The `loop_prep` marker (Step 5) is informational only. It is never read or enforced by
  `sdp-auto` or `sdp-state-loop-start` — per the constraint above, this skill cannot make them
  enforce it without modifying skills it is forbidden to modify.
- Never reconstruct a row's phase document or phase state file path from a naming convention —
  always resolve it from `registry.md`'s Phase File column.
- Never pre-filter which rows get the source coverage check — the check itself determines and
  reports whether a tracked source document applies.

## Outputs

- `sdp_doc_review`, `sdp_source_coverage`, and `sdp_rightsizing` completion markers set on every
  swept phase's state file
- Zero or more new `registry.md` rows, phase documents, and phase state files (from
  `sdp-phase-rightsizing-check` splits triggered during the sweep)
- Zero or more Coverage Check records appended to phase documents (from
  `sdp-source-coverage-check`)
- Zero or more Decisions Locked / Doc Review certifications (from `sdp-project-doc-review`, unmodified)
- `loop_prep` readiness block written to each in-scope project's `state.json`
- Full summary report to the user, ending with the manual next-step instruction to run
  `/sdp-auto` or `/sdp-state-loop-start`
