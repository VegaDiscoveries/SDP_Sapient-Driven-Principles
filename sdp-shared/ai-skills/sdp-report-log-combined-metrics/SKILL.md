## Purpose

Produce an SDP combined-metrics report — source/category/role/outcome/event-name breakdowns,
three timelines sharing one time axis (session/agent by source, event category, and role), a
Concerning Events table (fixed outcome/event-name filter), and work-item activity — from a
selected `combined-log-*.jsonl` run file, on manual invocation.

This skill is a thin assembler over `sdp-report-log-combined-metrics.ps1`, which does every
computation that can be derived from the jsonl alone via a fixed, dataset-agnostic rule. This
skill supplies only what the script cannot: a short narrative Summary and judgment about which
Concerning Events (if any) are worth calling out by name. The boundary is data source, not
complexity: if a fact is derivable from the selected `combined-log-*.jsonl` file alone via a
fixed, dataset-agnostic rule, it's script work; if it requires judgment not reducible to a fixed
rule, it's skill/LLM work.

**This report depends on a combined-log file existing for the target day.** Unlike the other
three report skills, this one has a prerequisite data-preparation step — `sdp-report-logs-combine` — that
must have already run for the day being reported on. This skill does not invoke that step itself
(see Step 1).

## Inputs

- **Which day** — combined-log entries live in one dated file per calendar day
  (`.sdp-solution-workflow/logging/combined-logs/combined-log-yyyyMMdd.jsonl`, produced by
  `sdp-report-logs-combine`, not by this skill). The user's request may name a day directly (a date, a
  filename, or "today/latest/most recent"); if it does not, Step 1 presents a picker — see below.
  This selection is orthogonal to the date-range filters below: it picks *which file*, the
  filters (if also given) narrow *within* that file.
- Optional date filter from the invocation: a single date, a start/end range, or a trailing day
  count, applied within the selected file. Absent any of these, the report covers the full
  selected file.
- Optional `-IncludeSeconds` request (hh:mm:ss instead of hh:mm) — only for debugging an actual
  timing question where second-level precision is load-bearing; default is hh:mm.
- Optional output path for the generated report (defaults to
  `sdp-solution-docs/log-reports/combined-metrics/log-report-combined-metrics_[yyyymmdd-hhmm].md`
  at the solution root, where `[yyyymmdd-hhmm]` is the report's creation timestamp — each run
  writes a new, distinctly named file rather than overwriting a prior report).

## Procedure

### Step 1: Resolve invocation parameters

1. **Resolve which day's file to read.**
   - List available files via the PowerShell tool:
     ```
     Get-ChildItem -Path '.sdp-solution-workflow/logging/combined-logs' -Filter 'combined-log-*.jsonl' -File | Sort-Object Name -Descending | Select-Object -ExpandProperty Name
     ```
     If this returns nothing: report "⛔ sdp-report-log-combined-metrics: no combined-log files
     found under `.sdp-solution-workflow/logging/combined-logs/`. Run `sdp-report-logs-combine` for the
     target day first." and stop — do not proceed to Step 2. This is the one halt condition
     unique to this skill among the report family: its input file is not a passively-accumulating
     log but the output of a separate on-demand skill, so "none found" most often means that
     prerequisite step hasn't been run yet for the day in question, not that no activity occurred.
   - If the user's request names a specific day (an explicit date, a filename, or
     "today"/"latest"/"most recent"/"current"): resolve it against the listing above. "Today" /
     "latest" / "most recent" / no day specified anywhere in a request that's otherwise
     unambiguous about wanting the current day → the first (most recent) entry. A named date
     that matches no file: treat as unspecified and fall through to the picker below rather than
     guessing — do not silently invoke `sdp-report-logs-combine` yourself to create it; the user may not
     want that day combined yet, or may want to combine it with awareness of what's in it.
   - **If the request does not identify a day at all** (the common case — a bare "generate the
     combined report" with no date given): present up to the 4 most recent dates from the listing
     above via the AskUserQuestion tool, one option per file, labeled with the plain date (e.g.
     "2026-07-17") decoded from the filename — not the raw filename as the label. Wait for the
     user's selection before proceeding. If fewer than 4 files exist, present however many there
     are (AskUserQuestion requires at least 2 options — if only one file exists, skip the question
     and use it directly, telling the user which day was used).
   - The resolved file's full path becomes `[jsonl_path]` for Step 2's `-JsonlPath` argument.
2. Determine, from the user's request or dispatch context: which date filter (if any) applies
   *within* the resolved file, whether `-IncludeSeconds` was requested, and the output report
   path (default per Inputs above). If the default path applies, obtain the creation timestamp
   via the PowerShell tool (`Get-Date -Format "yyyyMMdd-HHmm"`) — never hand-write or infer this
   stamp — and substitute it into the default filename. Confirm the
   `sdp-solution-docs/log-reports/combined-metrics/` folder exists at the solution root before
   writing; create it first if it does not.
3. Resolve the Solution/Projects header fields by reading `SDP-Solution.json` at the solution
   root:
   - If `solution_name` is set to something other than the literal placeholder
     `"[SolutionName]"`, use it verbatim; if `projects` is non-empty, list the registered project
     names. Use whichever of the two is actually populated — they are independent fields.
   - If both are empty/placeholder: check whether `~SDP-Maintenance` exists at the solution root.
     If it does, label Solution as `SDP Main Project` (this is the SDP framework's own
     maintenance/development repo, not a downstream consumer solution) and Projects as
     `n/a — framework repo`. Do not silently invent a name — state why the label was chosen (the
     unconfigured fields plus the `~SDP-Maintenance` marker), the same way Step 4's header
     substitution states it literally.
   - If `~SDP-Maintenance` does not exist and solution info is empty: label Solution as
     `(not configured)` and Projects as `(none registered)` — do not guess a name.

### Step 2: Run the script

Run via the PowerShell tool, always passing the file resolved in Step 1:

```
.\sdp-shared\scripts\sdp-report-log-combined-metrics.ps1 -JsonlPath '[jsonl_path]' [-Date yyyy-MM-dd | -StartDate yyyy-MM-dd -EndDate yyyy-MM-dd | -Days N] [-IncludeSeconds]
```

Parse the single JSON line from stdout.

1. If `status` is `"error"`: report the `error` field to the user and stop. Do not attempt to
   assemble a partial report.
2. If `status` is `"success"`: proceed to Step 3 with the full JSON object in hand. Treat every
   field in it as already-correct, final content — do not recompute, re-derive, or "sanity check"
   any number in it by re-reading the jsonl yourself. If a figure looks surprising, that is a
   signal to review the script's logic, not to override it by hand for this one run.

### Step 3: (no cross-file reads)

Every field this report presents traces to the combined-log file itself — that file already
merged and normalized the three original sources via `sdp-report-logs-combine`. Proceed directly to
Step 4.

### Step 4: Assemble the report

Write the output file (path from Step 1) with this section order and sourcing. Every item below
is a literal substitution unless marked **(judgment)**.

1. `# SDP Combined-Metrics Report — {{period.titleDate}}`
2. Header table — literal template:

   ```html
   <table style="width:100%">
   <tr>
   <td><strong>Report prepared:</strong> {{header.reportPreparedDate}}</td>
   <td style="text-align:center"><strong>Source:</strong> <code>{{header.sourceFile}}</code> ({{header.sourceLineCount}} lines)</td>
   <td style="text-align:right"><strong>Period covered:</strong> {{period.startDisplay}} → {{period.endDisplay}}</td>
   </tr>
   <tr>
   <td><strong>Solution:</strong> {{header.solutionLabel}}</td>
   <td style="text-align:center"><strong>Projects:</strong> {{header.projectsLabel}}</td>
   <td style="text-align:right"></td>
   </tr>
   </table>
   ```

   `{{header.solutionLabel}}`/`{{header.projectsLabel}}` come from Step 1.3's resolution, not
   from the script's JSON — that JSON has no knowledge of `SDP-Solution.json` or the Step 1.3
   fallback labeling logic. Each `<td>` gets exactly one `style="..."` attribute with all declarations
   semicolon-separated — **never** two separate `style="..."` attributes on the same tag; a
   duplicate attribute is a parse error and every occurrence after the first is silently dropped
   by the renderer.
3. `## Summary` — **(judgment)** LLM-authored narrative paragraph, informed by the full JSON.
   Cover, in any order that reads naturally: (1) total events and the source mix (how much of
   this period's volume is `hook-log` tool-call telemetry versus the lower-frequency
   `loop-metrics`/`workflow-log` semantic events); (2) the role mix, if informative; (3)
   `concerningCount` and, if non-zero, a one-line pointer to the Concerning Events section below
   (do not restate each row here); (4) which work items saw the most cross-source activity, if
   informative. Do not restate every number already shown in the tables below.
4. `## Session / Agent Timeline` — substitute `sessionAgentTimelineSvg` verbatim (byte for byte;
   never hand-edit the SVG markup), followed by `sessionAgentLegendHtml` verbatim, followed by
   this fixed one-sentence note (literal text, not judgment — reproduce it exactly every run):
   "Each session lane's lighter track spans its full logged period; the darker overlay marks the
   sub-span(s) where a dispatched subagent was active." Every real invocation reaches this section
   (it is null only when the file has zero events, which the script already errors out on earlier
   — see Step 2), so no omission logic is needed here.
5. `## Event Category Timeline` — substitute `categoryTimelineSvg` verbatim, followed by
   `categoryTimelineLegendHtml` verbatim. Always present, same reasoning as Step 4 above.
6. `## Role Timeline` — substitute `roleTimelineSvg` verbatim, followed by `roleTimelineLegendHtml`
   verbatim. Always present, same reasoning as Step 4 above.
7. `## Source Breakdown` — substitute `sourceBreakdownTableMarkdown` verbatim.
8. `## Category Breakdown` — substitute `categoryBreakdownTableMarkdown` verbatim.
9. `## Role Breakdown` — substitute `roleBreakdownTableMarkdown` verbatim.
10. `## Outcome Breakdown` — substitute `outcomeBreakdownTableMarkdown` verbatim. Omit this
    section entirely if `outcomeBreakdown` is empty.
11. `## Event Name Breakdown` — substitute `eventNameBreakdownTableMarkdown` verbatim.
12. `## Concerning Events` — only if `concerningCount` is greater than 0: substitute
    `concerningTableMarkdown` verbatim, followed by **(judgment, bounded)** — one short sentence
    per row (or per small cluster of related rows) noting what it is, using only the row's own
    `reason`/`outcome`/`event name` fields; never speculate about a cause the row doesn't state.
    Omit this entire section (heading included) if `concerningCount` is 0.
13. `## Work Item Activity` — substitute `workItemActivityTableMarkdown` verbatim.
14. Data-quality note — **(judgment, bounded)**: if `anomalies.unparseableLineCount` is greater
    than 0, append a blockquote noting the count of unparseable/timestamp-less lines skipped;
    omit entirely if zero.
15. `## Methodology` — substitute `methodologyMarkdown` verbatim.

Follow the report's established visual conventions for anything not dictated above: `hh:mm`-by-
default with an `-IncludeSeconds` override (Time Display Format), no captions narrating what a
table already shows (Caption/Prose Discipline), GFM Markdown tables throughout — no raw HTML
except the header table above, which needs `<td>` alignment control a GFM table cannot express.

### Step 5: Open the report

Open the written report file via the PowerShell tool (`Invoke-Item '[report_path]'`) so it opens
in the user's default associated application. Do this after the file is fully written, never
before — opening a partially-written file is misleading.

### Step 6: Confirm

Report to the user: report path written, period covered, total event count, the source mix
(e.g. "3827 hook-log / 19 loop-metrics / 1 workflow-log"), and `concerningCount` (call it out
explicitly if non-zero).

## Constraints

- Never run Step 5 (Open the report) before Step 4's write completes — opening a partially-written
  or stale file is misleading.
- Never hand-edit, re-derive, or "improve" any of the three timeline SVGs (`sessionAgentTimelineSvg`,
  `categoryTimelineSvg`, `roleTimelineSvg`) — substitute each byte for byte. If a timeline's
  geometry or color looks wrong, that's a script bug to fix in
  `sdp-report-log-combined-metrics.ps1`, not something to patch in the assembled markdown.
- Never derive report structure, formatting, or content by inspecting a previously-generated
  report file (this skill's own past output) or any other prior run — every structural decision
  must trace to this skill document or a named field in the script's JSON output.
- Never recompute, override, or "correct" a script-produced figure by hand for a single run. If a
  script output looks wrong, that's a script bug to fix in `sdp-report-log-combined-metrics.ps1`
  and re-run — not something to patch around in the assembled report.
- Never invoke `sdp-report-logs-combine` automatically from within this skill to "fix" a missing
  combined-log file — the halt in Step 1 is deliberate; combining is a separate, explicit user
  decision.
- Never treat a Concerning Events row as a confirmed problem — the script's filter is a fixed
  candidate rule, not a materiality judgment. State what the row's own fields say; do not
  diagnose a root cause the log entry itself doesn't state.
- Do not invent a phase name, outcome, or narrative detail not directly present in the JSON.
- Do not add narrative captions to any table that restate what it already shows.

## Outputs

- A markdown report file at the resolved output path, in the section order and sourcing above.
- The report file opened in the user's default associated application.
- User-facing confirmation of what was written, including the source mix and Concerning Events
  count.
