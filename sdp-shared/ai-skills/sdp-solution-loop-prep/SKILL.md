## Purpose

Run once, immediately after solution-level Phase 7's gate passes. For each project registered in
`SDP-Solution.json`, walk its freshly-decomposed `.sdp-workflow/registry.md` (the rows Phase 7 just
assigned it) in dependency order and bring each to full readiness for unattended dispatch —
mirrors `sdp-project-loop-prep`'s own per-project sweep exactly, just triggered at this specific transition
rather than on-demand before an arbitrary loop start. Migration detection (Task 11, Step 0a) is a
separate, earlier concern — it runs before solution-level phases 1–7 are drafted, not here.

## Inputs

- `SDP-Solution.json` — `projects` array, full sweep scope (every registered project, not a
  user-selectable subset — unlike `sdp-project-loop-prep`, this always runs solution-wide)
- Per-project `.sdp-workflow/registry.md` and `.sdp-workflow/state.json` — the rows Phase 7 just
  assigned

## Procedure

### Step 1: Confirm Trigger Condition

Read `.sdp-solution-workflow/state.json`. Confirm `current_phase` was "Phase Readiness" and
`phase_gate.status` is now `"passed"` (i.e. this is genuinely the Phase-7-passed transition, not
an arbitrary invocation). If not: report "sdp-solution-loop-prep: Phase 7 has not just passed for
this solution — nothing to prep yet" and stop.

### Step 2: Preflight Per Project

For every project in `SDP-Solution.json`'s `projects` array: run
`./sdp-shared/scripts/sdp-preflight.ps1 -workspaceRoot .\[project]`, identical to `sdp-project-loop-prep`
Step 2 — `ok:false` halts that project's prep only, never aborts the sweep for other projects.

### Step 3: Build the Dependency-Ordered Row List (Per Project)

Identical to `sdp-project-loop-prep` Step 3, applied to each project's freshly-decomposed
`.sdp-workflow/registry.md` independently — these are the build-phase rows Phase 7's decomposition
(Task 9, Step 2b) just wrote.

### Step 4: Per-Row Sweep (Per Project)

Identical three-part check to `sdp-project-loop-prep` Step 4 (content readiness via `sdp-project-doc-review`,
source coverage via `sdp-source-coverage-check`, right-sizing via `sdp-phase-rightsizing-check`),
run against each project's decomposed rows.

### Step 5: Write the Readiness Marker (Per Project)

Identical to `sdp-project-loop-prep` Step 5 — write a `loop_prep` block to each swept project's own
`.sdp-workflow/state.json`.

### Step 6: Report and Hand Off

Report a full summary across every project: rows checked, splits performed, coverage gaps found
and how resolved, any project halted during Step 2 or Step 3. End by inviting the user to run
`/sdp-auto` or `/sdp-state-loop-start` — the one-time project-count check inside those skills
(Task 14) picks `/sdp-project-state-loop` or `/sdp-solution-state-loop` automatically. Do not invoke
either skill directly.

## Constraints

Identical to `sdp-project-loop-prep`'s Constraints, with one addition: never invoke this skill for a
subset of projects — the Phase-7-passed transition it runs at is inherently solution-wide (every
project just received freshly-decomposed work from the same Phase 7 pass).

## Outputs

Identical shape to `sdp-project-loop-prep`'s Outputs, applied across every registered project instead of
a resolvable scope.
