## Purpose

Produce an SDP loop metrics report — time accounting (six buckets: Productive, Halt resolution,
Off-hours, Unproductive, User-interrupted, Idle/overhead), both time-flow SVG bars, three
halt/halt-resolution/user-interrupted interval tables, task-by-task outcomes (including elapsed
time), loop-fire breakdown, and a Phase/Work Covered table — from a selected
`loop-metrics-*.jsonl` run file, on manual invocation.

This skill is a thin assembler over `sdp-report-log-loop-metrics.ps1`, which does every computation
that can be derived from the jsonl alone via a fixed, dataset-agnostic rule. This skill supplies
only what the script cannot: content that requires reading a different file (`state.json`, the
phase document) or requires judgment not reducible to a rule (root-cause narrative, materiality,
"next step"). The boundary is data source, not complexity: if a fact is derivable from the
selected `loop-metrics-*.jsonl` file alone via a fixed, dataset-agnostic rule, it's script work; if it requires
reading any other file or judgment that isn't reducible to a fixed rule, it's skill/LLM work,
regardless of how simple the LLM part might look for any one dataset.

**Every structural/formatting decision in Step 6 below is either a literal template or traces to
a named script field — never to a previously-generated report file.** A handful of facts are
genuinely ambiguous from the log alone (a WORKER dispatch-start time when the first attempt was
interrupted and redispatched; whether an orphan span has a corroborating log entry). For those,
the script emits a **breadcrumb** — the raw candidate facts, plus an explicit `...Computable:
false` signal — rather than guessing. This skill's job in those spots is narrow: use the script's
value verbatim when computable; when not, resolve the breadcrumb into a marked estimate (`~`
prefix) using only what the breadcrumb actually contains. Every such spot is marked **(judgment)**
or **(judgment, bounded)** in Step 6; everything else is a direct substitution.

## Inputs

- **Which day** — loop metrics live in one dated file per calendar day
  (`.sdp-solution-workflow/logging/loop-logs/loop-metrics-yyyyMMdd.jsonl`, rotated purely by
  date regardless of workflow action). The user's request may name a day directly (a date, a
  filename, or "today/latest/most recent"); if it does not, Step 1 presents a picker — see
  below. This selection is orthogonal to the date-range filters below: it picks *which file*,
  the filters (if also given) narrow *within* that file — largely moot for a single-day file,
  but still honored if given (e.g. `-IncludeSeconds` needs no filter to be meaningful, but a
  narrower same-day range is still a valid ask).
- Optional date filter from the invocation: a single date, a start/end range, or a trailing
  day count, applied within the selected file. Absent any of these, the report covers the full
  selected file.
- Optional `-IncludeSeconds` request (hh:mm:ss instead of hh:mm) — only for debugging an actual
  SDP mechanism issue where second-level precision is load-bearing; default is hh:mm.
- Optional `-OffHoursThresholdMinutes` override (integer, must be > 0; default 30) — only when the
  user explicitly wants a different total-log-silence threshold for reclassifying an Unproductive
  or Idle segment as Off-hours; the default is the script's own calibrated value (see its
  `.PARAMETER` doc for the rationale) and should not be changed without an explicit ask.
- Optional output path for the generated report (defaults to
  `sdp-solution-docs/log-reports/loop-metrics/log-report-loop-metrics_[yyyymmdd-hhmm].md` at the
  solution root, where `[yyyymmdd-hhmm]` is the report's creation timestamp — each run writes a
  new, distinctly named file rather than overwriting a prior report).

## Procedure

### Step 1: Resolve invocation parameters

1. **Resolve which day's file to read.**
   - List available files via the PowerShell tool:
     ```
     Get-ChildItem -Path '.sdp-solution-workflow/logging/loop-logs' -Filter 'loop-metrics-*.jsonl' -File | Sort-Object Name -Descending | Select-Object -ExpandProperty Name
     ```
     If this returns nothing: invoke
     `/sdp-create-banner icon=error row=0 row: Status | No loop-metrics files found under .sdp-solution-workflow/logging/loop-logs/.`
     and stop — do not proceed to Step 2.
   - If the user's request names a specific day (an explicit date, a filename, or
     "today"/"latest"/"most recent"/"current"): resolve it against the listing above. "Today" /
     "latest" / "most recent" / no day specified anywhere in a request that's otherwise
     unambiguous about wanting the current day → the first (most recent) entry. A named date
     that matches no file: treat as unspecified and fall through to the picker below rather than
     guessing.
   - **If the request does not identify a day at all** (the common case — a bare "generate the
     loop metrics report" with no date given): present up to the 4 most recent dates from the
     listing above via the AskUserQuestion tool, one option per file, labeled with the plain
     date (e.g. "2026-07-17") decoded from the filename — not the raw filename as the label.
     Wait for the user's selection before proceeding. If fewer than 4 files exist, present
     however many there are (AskUserQuestion requires at least 2 options — if only one file
     exists, skip the question, use it directly, and invoke
     `/sdp-create-banner icon=info row=0 row: Report | Using [filename] (only file available) as the report source.`).
   - The resolved file's full path becomes `[jsonl_path]` for Step 2's `-JsonlPath` argument.
2. Determine, from the user's request or dispatch context: which date filter (if any) applies
   *within* the resolved file, whether `-IncludeSeconds` was requested, and the output report
   path (default per Inputs above). If the default path applies, obtain the creation timestamp
   via the PowerShell tool (`Get-Date -Format "yyyyMMdd-HHmm"`) — never hand-write or infer this
   stamp — and substitute it into the default filename. Confirm the
   `sdp-solution-docs/log-reports/loop-metrics/` folder exists at the solution root before
   writing; create it first if it does not.

### Step 2: Run the script

Run via the PowerShell tool, always passing the file resolved in Step 1:

```
.\sdp-shared\scripts\sdp-report-log-loop-metrics.ps1 -JsonlPath '[jsonl_path]' [-Date yyyy-MM-dd | -StartDate yyyy-MM-dd -EndDate yyyy-MM-dd | -Days N] [-IncludeSeconds] [-OffHoursThresholdMinutes N]
```

Parse the single JSON line from stdout.

1. If `status` is `"error"`: invoke
   `/sdp-create-banner icon=error row=0 row: Status | [error field from script].`
   and stop. Do not attempt to assemble a partial report.
2. If `status` is `"success"`: proceed to Step 3 with the full JSON object in hand. Treat every
   field in it as already-correct, final content — do not recompute, re-derive, or "sanity check"
   any number in it by re-reading the jsonl yourself. If a figure looks surprising, that is a
   signal to review the script's logic, not to override it by hand for this one run.

### Step 3: Resolve the target project (for Current State only)

`header.projectNames` in the script output names the project(s) this period covers. If exactly
one name is present, attempt to resolve `[resolved_project]` against it via Level 3 of the
Project Resolution Order (read `SDP-Solution.json`'s `projects` array, matching by folder/project
name). If more than one project name is present, or the resolved project's phase state file
cannot be found, skip Step 4 entirely and omit the Current State section from the report — do not
guess at its content or leave a placeholder; an absent section is honest, a fabricated one is not.

### Step 4: Read Current State (only if Step 3 resolved a single project)

Read the resolved project's active phase state file. Extract `workflow_status`, `halt_reason`
(if halted), `phase_gate.status`, `gate_review_attempts`, `gate_eval_cycles`. Compose the
"Next step" line from this state plus whatever the phase document's own Gate Verdict blockquote
says is still outstanding (see Step 5) — this is judgment, not a template substitution.

### Step 5: Read the phase document for gate-review content (only if applicable)

If the script's `haltWindows` or `loopFireBreakdown` show any `GATE_REPAIR` actions or a
gate-review-related halt, read the relevant phase document directly (path resolved the normal
way, via the phase's registry entry) for:
- The actual Gate Verdict blockquote — findings and their Material/Minor classification. Author
  this from what the document says, in your own words summarizing each finding; do not invent a
  finding the document doesn't contain.
- Enough surrounding context (the `GATE_REPAIR` session files, the relevant skill source if
  reachable) to write the "Recurring bug found" narrative, if a repeating pattern is actually
  present. If only one `GATE_REPAIR` occurred, or no clear repeating cause is identifiable, do
  not force a "Recurring bug" section into existence — omit it. A single occurrence is not a
  pattern.

If neither condition applies (no gate-review activity in this period), skip this step and omit
both the "Gate review verdict" and "Recurring bug found" sections from the report.

### Step 6: Assemble the report

Write the output file (path from Step 1) with this section order and sourcing. Every item below
is a literal substitution unless marked **(judgment)** or **(judgment, bounded)**.

Before the numbered sections, the file's very first line is always the SDP logo embed, followed
by one blank line, then the numbered content starts. Fixed template — reproduce verbatim, path is
relative from `sdp-solution-docs/log-reports/loop-metrics/` back to the solution root:

```html
<img src="../../../sdp-shared/docs/images/SDP_DocsLogo_WithText_0700x0163.png" alt="SDP Logo" width="375">
```

**Anchor convention (deterministic, used throughout):** place `<a id="nav"></a>` immediately
before the header table. The header table's nav cell links only to sections present this run
(`Current state` is never linked): `[Summary](#summary)` always; ` - [Phase / Work](#phase-work-covered)`
when `phaseWorkCovered` is non-empty; ` - [Issues](#specific-issues)` when Step 5 produced a
Specific Issues section this run. Each linked heading gets a matching `<a id="[slug]"></a>`
immediately before its text and a `[↩ Nav](#nav)` link immediately after — e.g.
`## <a id="summary"></a>Summary [↩ Nav](#nav)`.

1. `# SDP Loop Metrics Report — {{period.titleDate}}` — if `period.titleDate` contains the ASCII
   placeholder `->` (emitted for multi-day periods), replace it with the unicode arrow `→` before
   writing the heading; the script deliberately emits the ASCII form and expects this substitution
   here.
2. Header table — literal template:

   ```html
   <a id="nav"></a>
   <table style="width:100%">
   <tr>
   <td><strong>Report prepared:</strong> {{header.reportPreparedDate}}</td>
   <td style="text-align:center"><strong>Source:</strong> <code>{{header.sourceFile}}</code> ({{header.sourceLineCount}} lines)</td>
   <td style="text-align:right"><strong>Project:</strong> <code>{{header.projectNames joined by ", "}}</code></td>
   </tr>
   <tr>
   <td colspan="2" style="font-size:1.5em">
   {{nav links per the Anchor convention above}}
   </td>
   <td style="text-align:right"><strong>Period covered:</strong> {{period.startDisplay}} → {{period.endDisplay}}</td>
   </tr>
   </table>
   ```

   Each `<td>` gets exactly one `style="..."` attribute with all declarations
   semicolon-separated — **never** two separate `style="..."` attributes on the same tag; a
   duplicate attribute is a parse error and every occurrence after the first is silently dropped
   by the renderer.
3. `## Current state` — only if Step 4 ran; **(judgment)** LLM-authored from the phase state
   file plus judgment, per Step 4. Never anchored/linked from the header nav.
4. `## <a id="summary"></a>Summary [↩ Nav](#nav)` with both bars (`compositionBarSvg`,
   `chronologicalBarSvg`) and `legendHtml` — substituted verbatim, byte for byte, from the
   script's output. Do not hand-edit the SVG markup.
5. Bucket table — substitute `bucketTableMarkdown` verbatim. Do not re-derive or reformat it
   from the `buckets` object.
6. `## Loop fire breakdown` — substitute `loopFireTableMarkdown` verbatim. One deterministic
   refinement: if this run includes a Specific Issues section (Step 5 ran), append
   `" (see bug below)"` to the `GATE_REPAIR` row's Meaning text before writing it — the script's
   version is intentionally generic since it can't know whether that section exists this run.
7. `## Summary Details` — **(judgment)** LLM-authored narrative paragraph, informed by
   everything gathered so far. Cover, in any order that reads naturally: (1) total fires and how
   many halts occurred; (2) the single largest driver of non-Productive time; (3) any anomaly from
   Data-quality notes worth calling out; (4) a pointer to Specific Issues if present this run. Do
   not restate bucket percentages already shown in the table above — reference them, don't repeat
   the numbers.
8. Data-quality notes blockquote — **(judgment, bounded)** phrased from
   `anomalies.unloggedGaps`, `anomalies.missingExecuteInferredWorkItems`, and `pairingWarnings`
   (each entry flags an overlapping same-skill invocation the interval-pairing logic doesn't
   model — state it explicitly, don't silently drop it); omit entirely if all three are empty.
9. Halt windows / Halt-resolution windows / User-interrupted windows — **three separate
   tables**, restored from the original design (an earlier version of this skill used an
   interleaved-timeline approach with no source for that design; retired):
   - **Halt windows** — columns `# | Onset | Resolved | Duration | Cause`, one row per
     `haltWindows` entry, `durationDisplay` verbatim (the script already embeds the non-zero
     sub-bucket breakdown and any "-- see below" pointer in that string — do not reconstruct it
     from the individual `unattendedDisplay`/`resolutionDisplay`/etc. fields).
   - **Halt-resolution windows** — columns `# | Halt window | Skill | Start | End | Duration |
     Evidence`, one row per `haltResolutionWindows` entry, `evidence` field verbatim. Immediately
     after this table, append each string in `haltResolutionEmptyNotes` (if any) as its own line
     of prose — these cover halt windows with zero resolution entries. Omit the table itself (but
     not the empty-notes prose) if `haltResolutionWindows` is empty.
   - **User-interrupted windows** — columns `# | Skill | Orphaned start | Flow resumed |
     Duration | Evidence`. The Evidence cell is **(judgment, bounded)**: if `correlatedEntry` is
     non-null, write one sentence describing what its action/status fields show and why that's
     consistent with an interruption; if `correlatedEntry` is null, state only what the orphan
     pairing itself shows — do not speculate about what happened during the gap. If
     `correlatedEntry.reason`'s text indicates the session paused awaiting a user decision (e.g.
     a pre-work-verification pause requesting confirmation before proceeding) rather than an
     unexplained drop, say so explicitly and note when the flow resumed relative to that pause —
     this is a legitimate, correctly-behaving pause, not a broken session, and the Evidence text
     should read that way. Note also that the bucket seconds for this span may already exclude a
     genuine overnight/off-hours stretch in the middle (see the Off-hours precedence rule in the
     script's Methodology, which applies to every interval-based bucket — Productive and Halt
     resolution included, not just User-interrupted) — the Duration column here still shows the
     full orphan-to-resumed span for narrative clarity, even though only part of it counted toward
     the User-interrupted bucket total.
   - **Off-hours windows** — columns `# | Start | End | Duration`, one row per `offHoursWindows`
     entry (`index`/`startDisplay`/`endDisplay`/`durationDisplay` verbatim). Omit the table if
     empty. Do not assume it usually is — Off-hours can now surface outside a halt window from any
     bucket (a long, cleanly-paired Productive interval spanning overnight silence is a real,
     observed case, not just orphan spans) — check the actual data each run rather than defaulting
     to omission.
10. `## <a id="phase-work-covered"></a>Phase / Work Covered [↩ Nav](#nav)` — literal template:

    ```
    | Phase | Work Items | Duration (first dispatch → last phase activity) |
    |---|---|---|
    ```

    One row per `phaseWorkCovered` entry. Phase cell: `` `{{phaseId}}` — {{phaseName}} `` when
    `phaseNameKnown` is `true`, else `` `{{phaseId}}` `` followed by
    `*(human-readable name not independently derivable from this data)*`. Work Items cell:
    `{{workItems joined by ", "}}`, or `—` if `workItems` is empty (this happens when only the
    phase's own dispatch marker — e.g. a `GATE_REVIEWER` fire whose `work_item` is the phase id
    itself — appeared this period, with no child task activity logged). Duration cell:
    `{{startDisplay}} → {{endDisplay}} ({{durationDisplay}})`. When more than one project appears
    across the rows (`project` field differs), prefix each row's Phase cell with
    `` `{{project}}` / `` so rows stay attributable.

    Beneath the table, one line per distinct `mappingSource` value present among this run's rows
    — literal substitutions keyed off that field, not judgment:
    - `state-files`: *Phase/task membership for `{{project}}` sourced directly from its own
      `sdp-docs/*_state.json` files (each phase's own `phase` id and `tasks` map) — the same
      records `sdp-project-coordinator`/`sdp-project-worker`/`sdp-project-reviewer` themselves read and write.*
    - `halt-reason`: *Phase id for `{{project}}` sourced from `halt_reason` strings in the tone
      log — no phase state files (`sdp-docs/*_state.json`) were found for this project, so
      per-task membership could not be derived from its own records; the human-readable name is
      not independently re-derivable from this workspace either way.*
    - `unmapped`: *No phase attribution could be derived for `{{project}}`'s work this period —
      neither phase state files nor a `halt_reason` phase mention were available. Listed work
      items are real (drawn from the action log) but their phase is unknown, not guessed.*
    - `none`: *No phase attribution was attempted — this period has no work-item-bearing log
      entries.*

    A `(unmapped)` `phaseId` value is the script's own explicit "couldn't resolve" marker (not a
    real phase) — do not invent a plausible-looking phase name for it under any circumstance.
    When at least one `state-files` row has `phaseNameKnown: false`, add one sentence noting that
    project's `.sdp-workflow/registry.md` had no row matching that phase's own `phase_file` (or no
    `registry.md` exists at all) — this affects only the display label, never which tasks are
    grouped under the phase, since grouping is sourced from the phase's own state file regardless.
11. `### Task-by-task outcomes` — literal template:

    ```
    | Work Item | WORKER → WORK_COMPLETE | REVIEWER → VERIFIED | Elapsed |
    |---|---|---|---|
    ```

    Elapsed cell:
    - If `workerElapsedComputable` is `true`: `{{workerElapsedDisplay}} (WORKER) + {{"~" if
      reviewerVerifiedInferred}}{{reviewerElapsedDisplay}} (REVIEWER)` — no tilde on the WORKER
      portion; it's script-computed.
    - If `workerElapsedComputable` is `false` and `workerDispatchCandidates` is non-empty —
      **(judgment, bounded)**: inspect the candidate chain and pick the dispatch-start that led to
      completion (the last `"resumed"` entry, unless the chain shows something more informative
      worth noting), compute the estimate from that candidate's `startDisplay` to
      `workerCompleteDisplay` yourself, and prefix the result with `~`. Note the interruption
      briefly if it's informative, e.g. `~39 min (WORKER, interrupted first attempt)`. Never
      invent a start time the candidate chain doesn't contain.
    - If `workerCompleteDisplay` is `null`: `—`. Do not estimate from nothing.
    - A row with `reviewerVerifiedInferred: true` gets the standard "inferred from the
      subsequent GENERATE entry" footnote.

    No-progress-fire caveat — **(judgment, bounded)**: if a row's `noProgressFires` array is
    non-empty, read each entry's `reason` text. This signature covers two very different real
    situations that look identical structurally (a WORKER `EXECUTE` fire with no status
    transition) — a session paused awaiting a human decision, or the state-loop polling a
    background job the WORKER deliberately kicked off — and only the prose tells them apart.
    - If one or more entries clearly describe a pause awaiting a human decision: add a short
      caveat note beneath the table (or inline on that row) stating the interval's elapsed time
      may include wait time, not just active computation. Do not adjust the Elapsed cell or any
      bucket figure — this is narrative only, per the Constraints below.
    - If the entries describe background-job polling (the WORKER checking in on work it kicked
      off itself) rather than a human wait, no caveat is needed — that time is legitimately
      productive even though it didn't produce a status transition.
    - Do not guess when the reason text is ambiguous between the two; state what it shows without
      forcing a classification it doesn't clearly support.
12. `## Specific Issues` (Recurring bug found / Gate review verdict) — **(judgment)** only if
    Step 5 ran; entirely LLM-authored per that step. Heading:
    `## <a id="specific-issues"></a>Specific Issues [↩ Nav](#nav)`.
13. `## <a id="bucket-footnote"></a>Methodology [↩](#bucket-footnote-ref)` —
    `methodologyMarkdown` verbatim.
14. Methodology concern check — **(judgment)**. Review this run's computed buckets and
    intervals against the bucket-definition rules just written for anything internally
    inconsistent — a figure that looks double-counted, a total that doesn't reconcile, an edge
    case the stated rules don't obviously cover. This is a sanity check against *this run's
    actual output*, not a code-history search.
    - If something is found: append `**Note ({{header.reportPreparedDate}}):** {{what was
      observed and why it's flagged}}` after the Methodology bullets.
    - If nothing is found: add no note. An absent note is the expected, common case — do not
      manufacture one to fill the space.

Follow the report's established visual conventions for anything not dictated above: `hh:mm`-by-
default with an `-IncludeSeconds` override (Time Display Format), no captions narrating what a
visual already shows (Caption/Prose Discipline), self-contained `aria-label`s that don't depend
on page position, GFM Markdown tables unless a specific cell/layout need (spanning cells, forced
page width) requires raw HTML — ask before making that trade-off, don't default to HTML silently.

### Step 7: Open the report

Open the written report file via the PowerShell tool (`Invoke-Item '[report_path]'`) so it opens
in the user's default associated application. Do this after the file is fully written, never
before — opening a partially-written file is misleading.

### Step 8: Confirm

Invoke `/sdp-create-banner` with a `Report` row: report path written, period covered, and which
optional sections were included vs. omitted (Current State, Gate review verdict / Recurring bug
found) and why, e.g.
`icon=success row=0 row: Report | [report_path] written — period: [period]. Current State [included/omitted]; Gate/Recurring-bug sections [included/omitted] — [why].`

## Constraints

- Never run Step 7 (Open the report) before Step 6's write completes — opening a partially-written
  or stale file is misleading.
- Never derive report structure, formatting, or content by inspecting a previously-generated
  report file (this skill's own past output) or any other prior run — every structural decision
  must trace to this skill document or a named field in the script's JSON output. A skill
  instruction that says "check the most recent report for the current convention" is itself a
  defect: it makes report N+1 depend on report N, which is disposable, instead of on this document,
  which is authoritative. If a structural gap is found, fix it here, in this file.
- Never recompute, override, or "correct" a script-produced figure by hand for a single run. If a
  script output looks wrong, that's a script bug to fix in `sdp-report-log-loop-metrics.ps1` and
  re-run — not something to patch around in the assembled report.
- Never invent a phase name, a gate finding, or a root-cause narrative that isn't directly
  supported by what was actually read (the phase document, the skill source) or a breadcrumb
  field the script actually emitted. An absent section is always preferable to a fabricated one;
  an unresolved breadcrumb is resolved only from what it actually contains, never invented.
- Do not add narrative captions to either SVG bar or restate in prose what a table/bar already
  shows — a well-built visual (clear legend, sane labels) is self-explanatory; that legibility is
  the point of using a visual instead of more text.
- Do not create `## Current state`, `## Gate review verdict`, or `## Recurring bug found`
  sections when their preconditions (Step 3/4, Step 5) aren't met — these are conditional, not
  standing, sections.
- Never hand-write or infer a value the tooling is meant to supply on its own: the output-path
  timestamp stamp (Step 1.2) must come from `Get-Date -Format "yyyyMMdd-HHmm"`, not a guess or
  hand-typed value; a WORKER dispatch-start time must come from the candidate chain itself, never
  invented (Step 6, Task-by-task outcomes); and the Elapsed cell or any bucket figure must never
  be adjusted for a no-progress-fire caveat — that caveat is narrative only (Step 6, Task-by-task
  outcomes).
- Never hand-alter markup the tooling already produced: the header table's `<td>` elements take
  exactly one `style="..."` attribute each — never two separate `style="..."` attributes on the
  same tag, which silently drops every occurrence after the first (Step 6, header table); and
  script-produced SVG markup (`compositionBarSvg`, `chronologicalBarSvg`) is substituted verbatim,
  byte for byte — never hand-edited (Step 6, Summary).

## Outputs

- A markdown report file at the resolved output path, in the section order and sourcing above.
- The report file opened in the user's default associated application.
- User-facing confirmation of what was written and what was omitted.
