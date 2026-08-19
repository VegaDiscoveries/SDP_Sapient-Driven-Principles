## Purpose

Produce an SDP hook-metrics report — total/Pre/Post/prompt-submit and subagent/main-session
composition bars, a level breakdown chart, a tool-usage chart (stacked Pre/Post), a session/agent
Gantt-style timeline, a prompts-per-session chart plus a prompt-submission ruler, and a work-item
breakdown chart — from a selected `hook-log-*.jsonl` run file, on manual invocation. Every section
is a chart, not a table (user direction, 2026-07-17): this report is entirely single-source, so
one signature blue carries identity throughout, with a light-blue shade for the one real
sub-dimension (Pre vs. Post) and muted gray for "(none)"/absence buckets.

`UserPromptSubmit` (the human-submitted-prompt hook event, main session only — never fires for
subagent dispatch) is a third event type `sdp-hook-log.ps1` logs, alongside `PreToolUse`/
`PostToolUse`. It carries no `tool_name` and is excluded from Tool Usage for that reason (it was
never a tool call); it gets its own Prompts per Session section instead. See
`sdp-report-log-hook-metrics.ps1`'s own `.NOTES`/methodology text for the full mechanism.

This skill is a thin assembler over `sdp-report-log-hook-metrics.ps1`, which does every computation
that can be derived from the jsonl alone via a fixed, dataset-agnostic rule. This skill supplies
only what the script cannot: a short narrative Summary and any data-quality phrasing. The
boundary is data source, not complexity: if a fact is derivable from the selected
`hook-log-*.jsonl` file alone via a fixed, dataset-agnostic rule, it's script work; if it requires
judgment not reducible to a fixed rule, it's skill/LLM work.

**Every structural/formatting decision in Step 4 below is either a literal template or traces to
a named script field — never to a previously-generated report file.** Unlike
`sdp-report-log-loop-metrics`, this report has no ambiguous-from-the-log breadcrumbs to resolve —
hook-log entries are already-complete structured records (tool name, session, timing), not
inferred pairings — so there is exactly one **(judgment)** spot: the Summary paragraph.

## Inputs

- **Which day** — hook-log entries live in one dated file per local calendar day
  (`.sdp-solution-workflow/logging/hook-logs/hook-log-yyyyMMdd.jsonl`, rotated purely by date).
  The user's request may name a day directly (a date, a filename, or "today/latest/most recent");
  if it does not, Step 1 presents a picker — see below. This selection is orthogonal to the
  date-range filters below: it picks *which file*, the filters (if also given) narrow *within*
  that file.
- Optional date filter from the invocation: a single date, a start/end range, or a trailing day
  count, applied within the selected file. Absent any of these, the report covers the full
  selected file.
- Optional `-IncludeSeconds` request (hh:mm:ss instead of hh:mm) — only for debugging an actual
  tool-call-timing question where second-level precision is load-bearing; default is hh:mm.
- Optional output path for the generated report (defaults to
  `sdp-solution-docs/log-reports/hook-metrics/log-report-hook-metrics_[yyyymmdd-hhmm].md` at the
  solution root, where `[yyyymmdd-hhmm]` is the report's creation timestamp — each run writes a
  new, distinctly named file rather than overwriting a prior report).

## Procedure

### Step 1: Resolve invocation parameters

1. **Resolve which day's file to read.**
   - List available files via the PowerShell tool:
     ```
     Get-ChildItem -Path '.sdp-solution-workflow/logging/hook-logs' -Filter 'hook-log-*.jsonl' -File | Sort-Object Name -Descending | Select-Object -ExpandProperty Name
     ```
     If this returns nothing: invoke
     `/sdp-create-banner icon=error row=0 row: Status | No hook-log files found under .sdp-solution-workflow/logging/hook-logs/.`
     and stop — do not proceed to Step 2.
   - If the user's request names a specific day (an explicit date, a filename, or
     "today"/"latest"/"most recent"/"current"): resolve it against the listing above. "Today" /
     "latest" / "most recent" / no day specified anywhere in a request that's otherwise
     unambiguous about wanting the current day → the first (most recent) entry. A named date
     that matches no file: treat as unspecified and fall through to the picker below rather than
     guessing.
   - **If the request does not identify a day at all** (the common case — a bare "generate the
     hook-log report" with no date given): present up to the 4 most recent dates from the
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
   `sdp-solution-docs/log-reports/hook-metrics/` folder exists at the solution root before
   writing; create it first if it does not.

### Step 2: Run the script

Run via the PowerShell tool, always passing the file resolved in Step 1:

```
.\sdp-shared\scripts\sdp-report-log-hook-metrics.ps1 -JsonlPath '[jsonl_path]' [-Date yyyy-MM-dd | -StartDate yyyy-MM-dd -EndDate yyyy-MM-dd | -Days N] [-IncludeSeconds]
```

Parse the single JSON line from stdout.

1. If `status` is `"error"`: invoke
   `/sdp-create-banner icon=error row=0 row: Status | [error field from script].`
   and stop. Do not attempt to assemble a partial report.
2. If `status` is `"success"`: proceed to Step 3 with the full JSON object in hand. Treat every
   field in it as already-correct, final content — do not recompute, re-derive, or "sanity check"
   any number in it by re-reading the jsonl yourself. If a figure looks surprising, that is a
   signal to review the script's logic, not to override it by hand for this one run.

### Step 3: (no cross-file reads)

Unlike `sdp-report-log-loop-metrics`, this report needs no project/phase-state context — every
field it presents traces to the hook-log file itself. Proceed directly to Step 4.

### Step 4: Assemble the report

Write the output file (path from Step 1) with this section order and sourcing. Every item below
is a literal substitution unless marked **(judgment)**.

Before the numbered sections, the file's very first line is always the SDP logo embed, followed
by one blank line, then the numbered content starts. Fixed template — reproduce verbatim, path is
relative from `sdp-solution-docs/log-reports/hook-metrics/` back to the solution root:

```html
<img src="../../../sdp-shared/docs/images/SDP_DocsLogo_WithText_0700x0163.png" alt="SDP Logo" width="375">
```

1. `# SDP Hook-Metrics Report — {{period.titleDate}}` — if `period.titleDate` contains the ASCII
   placeholder `->` (emitted for multi-day periods), replace it with the unicode arrow `→` before
   writing the heading; the script deliberately emits the ASCII form and expects this substitution
   here.
2. Header table — literal template:

   ```html
   <table style="width:100%">
   <tr>
   <td><strong>Report prepared:</strong> {{header.reportPreparedDate}}</td>
   <td style="text-align:center"><strong>Source:</strong> <code>{{header.sourceFile}}</code> ({{header.sourceLineCount}} lines)</td>
   <td style="text-align:right"><strong>Period covered:</strong> {{period.startDisplay}} → {{period.endDisplay}}</td>
   </tr>
   </table>
   ```

   Each `<td>` gets exactly one `style="..."` attribute with all declarations
   semicolon-separated — **never** two separate `style="..."` attributes on the same tag; a
   duplicate attribute is a parse error and every occurrence after the first is silently dropped
   by the renderer.
3. `## Summary` — **(judgment)** LLM-authored narrative paragraph, informed by the full JSON.
   Cover, in any order that reads naturally: (1) total events and the Pre/Post split; (2) the
   subagent-vs-main-session split; (3) the busiest tool and busiest session by event count; (4)
   any notable truncation volume; (5) prompt-submission volume if `totals.promptSubmitCount` is
   notably high or concentrated in one session (`promptsPerSession`) — omit this clause when
   prompt volume isn't a standout figure, same bar as every other item here.
   `header.distinctWorkItemNames` and the `workItemBreakdown` array (see item 9 below) are both
   available if a work-item mention adds useful context here. Do not restate every number already
   shown in the charts below — reference the standout figures, don't repeat the full breakdown.
4. `## Totals` — literal template: `**Total events:** {{totals.totalEvents}}` on its own line,
   then substitute `prePostBarSvg` verbatim followed by `prePostLegendHtml` verbatim, then
   substitute `subagentMainBarSvg` verbatim followed by `subagentMainLegendHtml` verbatim. If
   `truncationNote` is non-empty, append one line: `**Truncated fields:** {{truncationNote}}`;
   omit this line entirely if `truncationNote` is empty (the common case).
5. `## Level Breakdown` — substitute `levelChartSvg` verbatim.
6. `## Tool Usage` — substitute `toolUsageChartSvg` verbatim, followed by `toolUsageLegendHtml`
   verbatim.
7. `## Sessions` — substitute `sessionGanttSvg` verbatim, followed by this fixed one-sentence note
   (literal text, not judgment — reproduce it exactly every run): "Each session lane's lighter
   track spans its full logged period; the darker overlay marks the sub-span(s) where a dispatched
   subagent was active."
8. `## Prompts per Session` — if `promptsPerSessionChartSvg` is `null` (no `UserPromptSubmit`
   events in the period — a normal, expected state, not an error): write the section heading
   followed by one line, `*No prompt-submission events in this period.*`, and skip straight to
   item 9; do not omit the section heading itself even when empty, so a reader always sees the
   section exists. Otherwise: substitute `promptsPerSessionChartSvg` verbatim, then
   `promptTimelineSvg` verbatim, followed by this fixed one-sentence note (literal text, not
   judgment — reproduce it exactly every run): "Each session lane's lighter track spans its full
   logged period, same as the Sessions timeline above; each marker is one prompt submission at the
   moment it was sent."
9. `## Work Item Breakdown` — substitute `workItemChartSvg` verbatim.
10. Data-quality note — **(judgment, bounded)**: if `anomalies.unparseableLineCount` is greater
    than 0, append a blockquote noting the count of unparseable/timestamp-less lines skipped;
    omit entirely if zero. An absent note is the expected, common case — do not manufacture one to
    fill the space.
11. `## Methodology` — substitute `methodologyMarkdown` verbatim.

Follow the report's established visual conventions for anything not dictated above: `hh:mm`-by-
default with an `-IncludeSeconds` override (Time Display Format), no captions narrating what a
chart already shows (Caption/Prose Discipline). Raw HTML/SVG is expected throughout this report
(every section but Summary is a chart) — this is a deliberate departure from the GFM-tables-only
convention the other three report skills in this family follow, per user direction 2026-07-17.

### Step 5: Open the report

Open the written report file via the PowerShell tool (`Invoke-Item '[report_path]'`) so it opens
in the user's default associated application. Do this after the file is fully written, never
before — opening a partially-written file is misleading.

### Step 6: Confirm

Invoke `/sdp-create-banner` with a `Report` row: report path written, period covered, and total
event count, e.g.
`icon=success row=0 row: Report | [report_path] written — period: [period]. [N] events.`

## Constraints

- Never run Step 5 (Open the report) before Step 4's write completes — opening a partially-written
  or stale file is misleading.
- Never hand-edit, re-derive, or "improve" any of the charts (`prePostBarSvg`, `subagentMainBarSvg`,
  `levelChartSvg`, `toolUsageChartSvg`, `sessionGanttSvg`, `promptsPerSessionChartSvg`,
  `promptTimelineSvg`) — substitute each byte for byte. If a chart's geometry or color looks
  wrong, that's a script bug to fix in `sdp-report-log-hook-metrics.ps1`, not something to patch
  in the assembled markdown.
- Never derive report structure, formatting, or content by inspecting a previously-generated
  report file (this skill's own past output) or any other prior run — every structural decision
  must trace to this skill document or a named field in the script's JSON output.
- Never recompute, override, or "correct" a script-produced figure by hand for a single run. If a
  script output looks wrong, that's a script bug to fix in `sdp-report-log-hook-metrics.ps1` and
  re-run — not something to patch around in the assembled report.
- Do not invent a narrative claim the JSON doesn't support (e.g. attributing a spike in truncated
  fields to a specific cause) — the Summary paragraph describes what the numbers show, not why
  they occurred; a "why" requires reading tool_input/tool_output content this script deliberately
  does not surface in aggregate form.
- Do not add narrative captions to any chart that restate what it already shows.

## Outputs

- A markdown report file at the resolved output path, in the section order and sourcing above.
- The report file opened in the user's default associated application.
- User-facing confirmation of what was written.
