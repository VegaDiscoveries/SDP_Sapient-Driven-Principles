## Purpose

Compare a tracked source design document — the original, user-authored doc a concept cycle was
built from — against the downstream SDP-authored phase documents derived from it, and surface
anything present in the source that is not reflected anywhere downstream, as an explicit, named
gap. Never silently dropped, never auto-deferred.

This targets a specific failure mode: Phase 1's job is to scan a large source document and
extract "primary elements" — a deliberate compression, by design. Nothing previously checked
what that compression dropped, until the user manually diffed the source against the as-built
result after Phase 6 was already fully complete — the most expensive point to discover a gap,
since downstream phases are by then already built on the narrowed scope.

Invoked in two contexts:
- **Early** — immediately after **solution-level** Phase 1/3 are drafted for a concept cycle (via
  the now solution-scoped `sdp-new-concept-intake`), before **solution-level** Phase 4 begins.
  This check now runs once per concept cycle at solution scope, not once per project — a single
  source document's coverage is assessed against the solution's own Concept/Expanded Concept
  documents, which may describe requirements spanning several projects. (Prior to the 2026-07-18
  phase pipeline expansion, this was "Phase 1/2... before Phase 3"; prior to this solution-scoping
  change, all of the above ran per-project.) Catches loss at the cheapest point, before any
  architecture/overview/plan work is built on a narrowed scope. **Mandatory** — a normal flow
  step, not optional.
- **Backstop** — again inside `sdp-project-loop-prep`'s sweep, as a final check across every
  not-yet-complete phase's own tracked source doc, in case new source material appeared after
  the early check, or the early check predates this convention for an older cycle.

## Inputs

- Tracked source document reference — unchanged, already solution-scoped: the path recorded by
  `sdp-new-concept-intake` (in the concept cycle's phase state or `state.json`) to the source doc
  under `sdp-solution-docs/user-design-docs/processed/`, including its `[doc_name]_Sections/`
  folder and `[doc_name]_TOC.md` if one exists
- The downstream phase document(s) produced so far for this cycle — now resolved against
  `sdp-solution-docs/01_concept.md` / `03_expanded_concept.md` (or the mini-cycle's equivalently
  numbered stubs) instead of a project's `sdp-docs/`, as many as exist at the time this check runs

## Procedure

### Step 1: Resolve the Source Document Reference

Read the tracked source reference for the phase/cycle under review. If none exists for this
phase/cycle: report "No tracked source document for [phase/cycle] — coverage check not
applicable." Stop. (Covers phases that predate this convention or were never sourced from an
intake-processed doc.)

### Step 2: Build the Source Element Inventory

If the source has an accompanying `[doc_name]_Sections/[doc_name]_TOC.md`: read the TOC first,
then process the source **section-by-section**, one section file at a time. For each section,
extract every distinct requirement, constraint, decision, entity, or workflow the section
describes, and assign each a short reference ID (same convention as the bootstrap document's
Traceability IDs — format doesn't matter, consistency within the check does). Processing
section-by-section is the direct fix for large (10–200 page) sources — never load the full
parent document into a single pass when a Sections folder exists.

If no Sections folder exists: read the full source doc, chunking by its own heading structure if
it is large enough that a single read would be unreliable. Extract the same element inventory.

### Step 3: Build the Downstream Coverage Map

Read every existing downstream phase document for this cycle, resolved under
`sdp-solution-docs/` (Phase 1/3 only, on the early
invocation; every not-yet-complete phase belonging to this cycle, on the backstop invocation).
For each source element from Step 2, determine whether it is reflected downstream — an explicit
task, decision, section, or acceptance criterion that substantively addresses it. A passing
mention is not coverage.

### Step 4: Surface Gaps

For every source element with no downstream coverage: surface it individually to the user —
quote the source element, its reference ID, and a proposed landing spot (an existing phase, a
new phase, or explicitly out of scope). Do not decide an element is unimportant enough to skip
surfacing — that judgment belongs to the user, not this skill.

Resolve each surfaced gap to exactly one of:
- **Brought into scope** — user directs it into an existing or new phase. If this pushes a
  phase over its right-sizing threshold, note that `sdp-phase-rightsizing-check` should be run
  against the affected phase next — this skill does not perform that assessment itself.
- **Explicitly deferred** — user directs it out of scope for this cycle, with a written
  rationale recorded verbatim.
- **Already covered — finding was a false positive** — user confirms coverage this check missed.
  Record the miss in the resolution table for calibration; do not silently trust the check's own
  initial read over the user's correction.

### Step 5: Record the Resolution

Append a Coverage Check record to the phase document that is the natural home for this cycle
(typically Phase 1's document; if the check is running on the backstop pass against a
later-stage phase, append to that phase's own document instead) using this format:

```markdown
## Source Coverage Check — [YYYY-MM-DD]

Source: [tracked source doc path(s)]

| Ref ID | Source Element | Resolution | Landed In |
|--------|-----------------|------------|-----------|
| [ID] | [one-line summary] | Brought into scope / Deferred / Already covered | [phase, or "out of scope — rationale"] |
```

Append-only: a re-run (e.g., the backstop invocation re-checking a cycle already checked early)
adds a new dated Coverage Check section below any prior one — never edits a prior table.

### Step 6: Certify

If every source element resolved to "Brought into scope," "Already covered," or "Explicitly
deferred" (each deferred entry carrying a written rationale): invoke
`/sdp-create-banner icon=success row=0 row: Status | Source coverage check: [source doc] — fully accounted for. [N] elements checked, [M] deferred.`
If any element has no resolution yet: do not certify. This check is not complete until every
extracted element has one of the three resolutions above.

On certification, write an `sdp_source_coverage` entry to the phase state file the check ran
against (same file `sdp_doc_review` is written to), mirroring `sdp-project-doc-review`'s own certification
write:

```json
"sdp_source_coverage": {
  "purpose": "Records that sdp-source-coverage-check has certified this phase's tracked source document as fully accounted for downstream. Does not substitute for sdp-project-doc-review or gate review.",
  "completed": true,
  "completed_at": "[ISO 8601 datetime]",
  "session": "[session-NNN or user-invoked]",
  "source_document": "[tracked source doc path from Step 1]"
}
```

`sdp-project-loop-prep` reads this flag to skip re-running the check against an already-certified phase
whose tracked source hasn't changed since. If the phase has no tracked source document (Step 1
found none applicable), no `sdp_source_coverage` entry is written — `sdp-project-loop-prep` treats an
absent entry on a phase with no source reference as "not applicable," not "not yet checked."

## Constraints

- Never mark an element covered without either confirmed downstream coverage found during the
  scan, or the user's explicit resolution — no autonomous "probably fine."
- Never silently defer. Deferral requires the user's explicit direction and a written rationale,
  matching `sdp-project-doc-review`'s Deferral Rules discipline: a conversational answer alone does not
  close an item.
- Process a source with a Sections/TOC folder section-by-section — never load an entire large
  parent document into one pass.
- This skill does not decide where a newly in-scope element lands structurally beyond what the
  user directs, and does not itself execute a phase split — that is
  `sdp-phase-rightsizing-check`'s job.
- Do not treat "finished without interrupting the user" as success. Every gap found in Step 3 is
  surfaced in Step 4, without exception.
- This skill never writes to `registry.md`.
- Never edit a prior Coverage Check table on re-run — always append a new dated section below it
  (append-only).
- Never certify while any extracted element lacks one of the three resolutions.

## Outputs

- Coverage Check record appended to the relevant phase document (append-only, dated)
- Zero or more phase tasks added or expanded to reflect brought-into-scope elements
- Zero or more explicitly deferred elements, each with a written rationale
- `sdp_source_coverage` entry written to the phase state file on certification (omitted entirely
  when no tracked source document applies)
- Certification reported to the user, or explicit non-certification with the list of
  still-unresolved elements
