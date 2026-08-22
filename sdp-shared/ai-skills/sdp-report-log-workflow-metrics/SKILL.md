## Purpose

Produce an SDP workflow-metrics report — trigger/role/outcome breakdowns, a full chronological
events table, a Concerning Events table (fixed outcome/trigger filter), and work-item/phase
activity tables (first/last/duration span, distinct triggers, final outcome) — from a selected
`workflow-log-*.jsonl` run file, on manual invocation.

This skill is a thin assembler over `sdp-report-log-workflow-metrics.ps1`, which does every
computation that can be derived from the jsonl alone via a fixed, dataset-agnostic rule. This
skill supplies only what the script cannot: a short narrative Summary and judgment about which
Concerning Events (if any) are worth calling out by name. The boundary is data source, not
complexity: if a fact is derivable from the selected `workflow-log-*.jsonl` file alone via a
fixed, dataset-agnostic rule, it's script work; if it requires judgment not reducible to a fixed
rule, it's skill/LLM work.

**Every structural/formatting decision in Step 4 below is either a literal template or traces to
a named script field — never to a previously-generated report file.** Unlike
`sdp-report-log-loop-metrics`, this log is already a semantic narrative (`reason` is free text
authored at logging time by the writing skill/script) — there is no ambiguous pairing or
breadcrumb to resolve. The two **(judgment)** spots are the Summary paragraph and the optional
Concerning Events commentary; everything else is a direct substitution.

## Inputs

- **Which day** — workflow-log entries live in one dated file per local calendar day
  (`.sdp-solution-workflow/logging/workflow-logs/workflow-log-yyyyMMdd.jsonl`, rotated purely by
  date). The user's request may name a day directly (a date, a filename, or
  "today/latest/most recent"); if it does not, Step 1 presents a picker — see below. This
  selection is orthogonal to the date-range filters below: it picks *which file*, the filters (if
  also given) narrow *within* that file.
- Optional date filter from the invocation: a single date, a start/end range, or a trailing day
  count, applied within the selected file. Absent any of these, the report covers the full
  selected file.
- Optional `-IncludeSeconds` request (hh:mm:ss instead of hh:mm) — only for debugging an actual
  timing question where second-level precision is load-bearing; default is hh:mm.
- Optional output path for the generated report (defaults to
  `sdp-solution-docs/log-reports/workflow-metrics/log-report-workflow-metrics_[yyyymmdd-hhmm].md`
  at the solution root, where `[yyyymmdd-hhmm]` is the report's creation timestamp — each run
  writes a new, distinctly named file rather than overwriting a prior report).

## Procedure

### Step 1: Resolve invocation parameters

**Level 0 — Auto-invocation override (used by `sdp-report-logs-auto-generate`):** if this
invocation explicitly supplies `--range-file=[path]`, `--start-date=[yyyy-MM-dd]`, and
`--end-date=[yyyy-MM-dd]` (a pre-built multi-day merge produced by
`sdp-report-logs-merge-range.ps1`), use `[path]` directly as `[jsonl_path]` and the given dates as
this run's `-StartDate`/`-EndDate` — skip sub-step 1 below (the single-day file listing and
picker) entirely. Sub-step 2 still runs normally (output path, `-IncludeSeconds`); the supplied
dates are the already-resolved date filter, not something to determine from the request.

1. **Resolve which day's file to read.**
   - List available files via the PowerShell tool:
     ```
     Get-ChildItem -Path '.sdp-solution-workflow/logging/workflow-logs' -Filter 'workflow-log-*.jsonl' -File | Sort-Object Name -Descending | Select-Object -ExpandProperty Name
     ```
     If this returns nothing: invoke
     `/sdp-create-banner icon=error row=0 row: Status | No workflow-log files found under .sdp-solution-workflow/logging/workflow-logs/.`
     and stop — do not proceed to Step 2.
   - If the user's request names a specific day (an explicit date, a filename, or
     "today"/"latest"/"most recent"/"current"): resolve it against the listing above. "Today" /
     "latest" / "most recent" / no day specified anywhere in a request that's otherwise
     unambiguous about wanting the current day → the first (most recent) entry. A named date
     that matches no file: treat as unspecified and fall through to the picker below rather than
     guessing.
   - **If the request does not identify a day at all** (the common case — a bare "generate the
     workflow-log report" with no date given): present up to the 4 most recent dates from the
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
   `sdp-solution-docs/log-reports/workflow-metrics/` folder exists at the solution root before
   writing; create it first if it does not.

### Step 2: Run the script

Run via the PowerShell tool, always passing the file resolved in Step 1:

```
.\sdp-shared\scripts\sdp-report-log-workflow-metrics.ps1 -JsonlPath '[jsonl_path]' [-Date yyyy-MM-dd | -StartDate yyyy-MM-dd -EndDate yyyy-MM-dd | -Days N] [-IncludeSeconds]
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
field it presents, including `reason`/`detail` narrative text, already exists verbatim in the
workflow-log file itself. Proceed directly to Step 4.

### Step 4: Assemble the report

Write the output file (path from Step 1) with this section order and sourcing. Every item below
is a literal substitution unless marked **(judgment)**.

Before the numbered sections, the file's very first line is always the SDP logo embed, followed
by one blank line, then the numbered content starts. Fixed template — reproduce verbatim, path is
relative from `sdp-solution-docs/log-reports/workflow-metrics/` back to the solution root:

```html
<img src="../../../sdp-shared/docs/images/SDP_DocsLogo_WithText_0700x0163.png" alt="SDP Logo" width="375">
```

1. `# SDP Workflow-Metrics Report — {{period.titleDate}}` — if `period.titleDate` contains the
   ASCII placeholder `->` (emitted for multi-day periods), replace it with the unicode arrow `→`
   before writing the heading; the script deliberately emits the ASCII form and expects this
   substitution here.
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
   Cover, in any order that reads naturally: (1) total events and the most common trigger; (2)
   the role mix; (3) `concerningCount` and, if non-zero, a one-line pointer to the Concerning
   Events section below (do not restate each row here — that table speaks for itself); (4) which
   work items or phases saw the most activity, if that's informative — `header.distinctWorkItemNames`
   / `header.distinctPhaseNames` and the `workItemActivity`/`phaseActivity` arrays (see items 8-9
   below) are the source for this. Do not restate every number already shown in the tables below.
4. `## Trigger Breakdown` — substitute `triggerBreakdownTableMarkdown` verbatim.
5. `## Role Breakdown` — substitute `roleBreakdownTableMarkdown` verbatim.
6. `## Outcome Breakdown` — substitute `outcomeBreakdownTableMarkdown` verbatim. Omit this
   section entirely if `outcomeBreakdown` is empty (a period with no discrete-outcome events is
   normal — most dispatch-decision events have none).
7. `## Concerning Events` — only if `concerningCount` is greater than 0: substitute
   `concerningTableMarkdown` verbatim, followed by **(judgment, bounded)** — one short sentence
   per row (or per small cluster of related rows) noting what it is, using only the row's own
   `reason`/`outcome`/`trigger` fields; never speculate about a cause the row doesn't state. Omit
   this entire section (heading included) if `concerningCount` is 0 — an absent section is
   honest, a fabricated "no concerning events this period" filler line is not.
8. `## Work Item Activity` — substitute `workItemActivityTableMarkdown` verbatim.
9. `## Phase Activity` — substitute `phaseActivityTableMarkdown` verbatim. Omit this section
   entirely if `phaseActivity` is empty.
10. `## Full Event Log` — substitute `eventsTableMarkdown` verbatim. This is the complete
    chronological record — every other section above is a derived view of the same rows.
11. Data-quality note — **(judgment, bounded)**: if `anomalies.unparseableLineCount` is greater
    than 0, append a blockquote noting the count of unparseable/timestamp-less lines skipped;
    omit entirely if zero.
12. `## Methodology` — substitute `methodologyMarkdown` verbatim.

Follow the report's established visual conventions for anything not dictated above: `hh:mm`-by-
default with an `-IncludeSeconds` override (Time Display Format), no captions narrating what a
table already shows (Caption/Prose Discipline), GFM Markdown tables throughout — no raw HTML
except the header table above, which needs `<td>` alignment control a GFM table cannot express.

### Step 5: Open the report

Open the written report file via the PowerShell tool (`Invoke-Item '[report_path]'`) so it opens
in the user's default associated application. Do this after the file is fully written, never
before — opening a partially-written file is misleading.

### Step 6: Confirm

Invoke `/sdp-create-banner` with a `Report` row: report path written, period covered, total
event count, and `concerningCount` (call it out explicitly if non-zero — that's the figure most
likely to change what the user does next), e.g.
`icon=success row=0 row: Report | [report_path] written — period: [period]. [N] events. concerningCount: [N].`

## Constraints

- Never run Step 5 (Open the report) before Step 4's write completes — opening a partially-written
  or stale file is misleading.
- Never derive report structure, formatting, or content by inspecting a previously-generated
  report file (this skill's own past output) or any other prior run — every structural decision
  must trace to this skill document or a named field in the script's JSON output.
- Never recompute, override, or "correct" a script-produced figure by hand for a single run. If a
  script output looks wrong, that's a script bug to fix in `sdp-report-log-workflow-metrics.ps1` and
  re-run — not something to patch around in the assembled report.
- Never treat a Concerning Events row as a confirmed problem — the script's filter is a fixed
  candidate rule (see the script's own Methodology text), not a materiality judgment. State what
  the row's own fields say; do not diagnose a root cause the log entry itself doesn't state.
- Do not invent a phase name, outcome, or narrative detail not directly present in the JSON —
  `reason`/`detail` are the only free-text fields, and they are quoted/summarized from what they
  actually say, never embellished.
- Do not add narrative captions to any table that restate what it already shows.

## Outputs

- A markdown report file at the resolved output path, in the section order and sourcing above.
- The report file opened in the user's default associated application.
- User-facing confirmation of what was written, including the Concerning Events count.
