## Purpose

Register a new concept — either a user-provided source design document (or a related set of
documents), or a purely conversational description with no document at all — as a mini Phase
1→7 concept cycle in the solution's own `registry.md`, at any project maturity, not only at a
clean, brand-new project. This is a ceremony skill: it ingests (or skips ingestion, in the
no-document case), groups, seeds registry rows and phase stubs, and hands off. It does not
draft phase content itself — Phase 1–7 authorship still happens via the existing, unmodified
bootstrap-document machinery (COORDINATOR + `/brainstorming` for
Phase 1/3, WORKER + Pros-Cons-Gaps for Phase 4/5, WORKER + `sdp-project-doc-review` + gate review for
Phase 6).

Nothing about phase advancement or gate review is clean-project-specific in the existing
machinery — `registry.md`'s row model and `sdp-project-coordinator`'s dependency-eligible phase scan are
already generic. The gap this skill closes is that nothing previously offered a low-effort,
documented way to trigger a new concept cycle mid-project — document-driven or purely
conversational; it was always improvised.

**Two invocation modes:**
- **Document-driven** — one or more files are sitting in the drop zone. Runs the full
  procedure from Step 1 (scan) through Step 4, including tracking the source document for
  later `sdp-source-coverage-check` passes.
- **Conversational** — the user describes a new concept directly, with no document to drop.
  Skips Steps 1–3 (nothing to scan or group) and goes straight to Step 4 (the renumbered "Seed
  the Mini Concept Cycle" step — the old target-confirmation Step 4 no longer exists). No source
  document is tracked, since none exists — `sdp-source-coverage-check` already handles "no tracked source"
  gracefully on later passes (self-reports not applicable and stops), so this is not a gap, just
  a mode where that check never has anything to compare against.

## Inputs

- `sdp-solution-docs/user-design-docs/` — drop zone for source documents (document-driven mode
  only)
- `sdp-solution-docs/user-design-docs/processed/` — destination after ingestion (document-driven
  mode only)
- The solution's own `.sdp-solution-workflow/registry.md`
- For conversational mode: the user's description of the new concept, given directly in this
  session

## Procedure

### Step 0: Determine Invocation Mode

**If the user invoked this skill by dropping file(s) into the drop zone first** (or otherwise
signaled a document exists): this is **document-driven mode** — proceed to Step 1 as normal.

**Otherwise** (the user described a new concept directly, with no indication a document exists):
before assuming conversational mode, ask once: "Do you have any existing design docs, notes, or
write-ups on this concept already? SDP can incorporate them rather than starting from a blank
concept description."
- If yes: tell them where to place files (`sdp-solution-docs/user-design-docs/`), then proceed to
  Step 1 as document-driven mode.
- If no: this is **conversational mode** — skip Steps 1–3 entirely and proceed to Step 4, treating
  the user's description as the sole "source-document set."

### Step 1: Scan the Drop Zone

Scan `sdp-solution-docs/user-design-docs/` (excluding `processed/` and this drop zone's own
`README.md`) for files. If none found:
invoke `/sdp-create-banner icon=warning row=0 row: Status | No unprocessed design docs found in
sdp-solution-docs/user-design-docs/ — drop the file(s) there and run this again.` Stop — do not
proceed to any subsequent step.

### Step 2: Detect the Sections/TOC Pattern (Parent+Sections Grouping)

For each top-level file found (directly in the drop zone, not inside a `_Sections/` subfolder):
check whether an accompanying `[doc_name]_Sections/[doc_name]_TOC.md` folder exists alongside
it — the same parent+sections+TOC pattern already used for the GPG standards document. If
present: the parent doc plus every file in its Sections folder is **one logical source
document**. Mark it as such; its section files are never independently considered in Step 3's
grouping — they are pre-chunked pieces of a single already-large doc, not separate or related
documents in their own right.

### Step 3: Group Remaining Candidates into Source-Document Sets

For every file not already grouped in Step 2:
1. Check its frontmatter for a `source:` field. If present and it points to another dropped
   file, it belongs to that file's set — deterministic, no judgment required.
2. For files with no such marker: read each, and judge independent (unrelated scope) vs.
   related/supporting (shared scope, meant to be read together as one source). Group related
   files into a single set.

Each resulting group — a single file, a parent+Sections group, or a related-files group — is one
source-document set. Each set becomes one mini concept cycle.

### Step 4: Seed the Mini Concept Cycle

For each set (project assignment is no longer determined here — see Section 2 of the design doc:
project discovery happens inside phases 1–7, not before them), in the solution's own
`.sdp-solution-workflow/registry.md`:

1. Determine a project-appropriate phase numbering/naming scheme for the new mini-cycle. If the
   existing `registry.md`'s convention doesn't make the extension obvious (e.g., how phase
   numbers/names should be appended after the highest existing entry), ask the user rather than
   guessing.
2. Append seven new rows: Concept, Research, Expanded Concept, Architecture, Implementation
   Overview, Refined Implementation Plan, and **Phase Readiness** — each named for this cycle
   (e.g. "Concept — [FeatureName]", "Phase Readiness — [FeatureName]"), sequentially chained via
   `Depends On` to each other in that order. The first row's `Depends On` is `"none"` unless the
   new concept is explicitly dependent on already-built project scope — ask the user if this
   isn't obvious from the source document; never infer a dependency silently. The "Phase
   Readiness" row's name must contain that exact substring (not abbreviated or reworded) —
   `sdp-project-coordinator` and `sdp-project-gate-review` detect this phase by that literal substring match.
3. Create each phase's document stub and `[phase]_state.json`, matching the bootstrap
   document's phase document and phase state file templates.
4. **Document-driven mode only:** move the source document — and its Sections folder, if Step 2
   identified one — from the drop zone to `sdp-solution-docs/user-design-docs/processed/`. Only
   move after the registry rows and file stubs above have been successfully written; never
   move-then-fail. **Conversational mode:** skip this sub-step — there is no file to move.
5. **Document-driven mode only:** record the moved path as the tracked source reference in the
   new Concept phase's `[phase]_state.json` (a `source_document` field, pointing at the
   `processed/` location) — this is what `sdp-source-coverage-check` reads on later passes.
   **Conversational mode:** skip this sub-step — do not write a `source_document` field or
   fabricate a reference to a document that doesn't exist.
6. Report the new registry rows and file paths created for this set to the user.

### Step 4a: Cancel Any Running Loop

Mid-stream seeding re-enters phases 1–7 — under the no-cron-during-phases-1–7 model (bootstrap
doc, Phase Readiness / Loop Entry Point), no cron job may be active while phases 1–7 are being
worked.

1. List active scheduled jobs via the `CronList` tool.
2. If any active job's command invokes `/sdp-project-state-loop` or `/sdp-solution-state-loop`: cancel it
   via the `CronDelete` tool. Note the cancellation for Step 5's hand-off banner.
3. If no matching job is found: note nothing to report — Step 5's banner omits the Loop row
   entirely in this case.

### Step 5: Hand Off — Do Not Draft Content

Do not draft Phase 1/3 content directly. That remains COORDINATOR's job (with `/brainstorming`,
per the bootstrap document's existing Phase 1/3 authorship exception), via the normal dispatch
flow. Report via `/sdp-create-banner`:

- **Conversational mode** (no Step 6 row to add): invoke
  `/sdp-create-banner icon=success row=0 row: Status | Mini concept cycle seeded for [set] as
  phases [list] in the solution's registry.md. Run COORDINATOR next to begin Phase 1 drafting.`
- **Document-driven mode:** invoke the same banner with the Step 6 coverage-check row appended
  as a second row (see Step 6 below), plus the cron-cancellation row from Step 4a below if a loop
  was found running — up to three rows in one banner:
  `/sdp-create-banner icon=success row=0 row: Status | Mini concept cycle seeded for [set] as
  phases [list] in the solution's registry.md. Run COORDINATOR next to begin Phase 1 drafting.
  row: Coverage Check | once Phase 1 and Phase 3 are drafted for this cycle,
  sdp-source-coverage-check must run against them before Phase 4 begins — this is a mandatory
  flow step, not optional.`

If Step 4a cancelled a running loop, append a third row to whichever banner variant fired:
`row: Loop | Running loop cancelled — phases 1-7 are active again for this cycle. Restart
/sdp-auto once this cycle's Phase 7 gate passes.`
Omit this row if Step 4a found no cron job running.

Do not spawn a COORDINATOR, WORKER, or REVIEWER subagent from within this skill — this mirrors
the discipline `sdp-auto` and `sdp-state-loop-start` already apply to themselves (never call an
orchestration skill from within another skill); the user or the existing dispatch flow triggers
COORDINATOR separately.

### Step 6: State the Mandatory Coverage-Check Requirement

**Document-driven mode:** include, as the second row of the Step 5 banner, that once Phase 1 and
Phase 3 are drafted for this cycle, `sdp-source-coverage-check` **must** run against them before
Phase 4 begins — this is a mandatory flow step, not optional. This skill cannot perform that
check itself, since Phase 1/3 content doesn't exist yet at the time this skill runs — the
instruction has to travel forward with the dispatch so it isn't lost.

**Conversational mode:** no tracked source document exists, so this requirement doesn't apply —
`sdp-source-coverage-check` will self-report "not applicable" if it's ever run against this
cycle's phases. Do not add a coverage-check row to the Step 5 banner for this mode.

## Constraints

- Never guess a project-appropriate phase-numbering scheme or an implicit dependency without
  asking the user — see Step 4 items 1-2.
- An empty drop zone is never a silent no-op — always alert with the exact path and the next
  action (drop files, run again).
- Never guess a file grouping without either a deterministic `source:` marker or an explicit
  read-and-judge pass — and when a grouping judgment is genuinely unclear, ask the user rather
  than guessing.
- This skill does not draft Phase 1/3 content and does not spawn a COORDINATOR, WORKER, or
  REVIEWER subagent — it only seeds `registry.md` rows, phase stubs, and the source reference,
  then hands off.
- A file is moved to `processed/` only after its registry rows and phase stubs are successfully
  written — never move-then-fail.
- In conversational mode, never write a `source_document` field or otherwise fabricate a tracked
  source reference — there is no document to point at. Leave the field absent, exactly as
  `sdp-source-coverage-check`'s own "no tracked source" path expects.
- The `registry.md` write here is the same disclosed, bounded append-only authority
  `sdp-phase-rightsizing-check` has for a split — append new rows only; never edit or delete an
  existing row.
- Do not treat "finished without asking the user anything" as success — numbering-scheme
  confirmation and dependency confirmation (Step 4 items 1-2) are points where silence in favor
  of an inferred answer is a violation of this skill's purpose.
- Never begin Phase 4 for a cycle before `sdp-source-coverage-check` has run against its drafted
  Phase 1 and Phase 3 documents.

## Outputs

- New rows in the solution's own `.sdp-solution-workflow/registry.md` (7 per confirmed set):
  Concept, Research, Expanded Concept, Architecture, Implementation Overview, Refined
  Implementation Plan, Phase Readiness
- New phase document stubs and phase state files for each
- **Document-driven mode only:** source document (and Sections folder, if any) relocated to
  `processed/`; tracked source reference recorded in the new Concept phase's state file
- User-facing report per set — including the mandatory coverage-check reminder in document-driven
  mode; omitting it in conversational mode
