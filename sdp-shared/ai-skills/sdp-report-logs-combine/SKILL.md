## Purpose

Merge one calendar day's three source logs — `loop-metrics-yyyyMMdd.jsonl`,
`hook-log-yyyyMMdd.jsonl`, `workflow-log-yyyyMMdd.jsonl` — into a single normalized
`combined-log-yyyyMMdd.jsonl` under `.sdp-solution-workflow/logging/combined-logs/`, on manual
invocation. This is the data-preparation step for `sdp-report-log-combined-metrics`; it produces
a file, not a report.

This skill is a thin wrapper over `sdp-report-logs-combine.ps1`, which does the entire merge —
normalizing every source entry into one common envelope shape via a fixed, dataset-agnostic rule
per source/sub-shape (see the script's own `.NOTES` for the full field-by-field mapping). There
is no judgment involved in the merge itself; this skill's only job is resolving which date to
combine and reporting the result.

## Inputs

- **Which day** — the user's request may name a day directly (a date, or "today"/"yesterday"); if
  it does not, default to today. Unlike the report skills, there is no "most recent file" picker
  here — this is a creation operation, not a selection over existing output, so a plain default
  is correct and no AskUserQuestion prompt is needed.

## Procedure

### Step 1: Resolve the target date

Determine the date to combine from the user's request (an explicit date, "today", "yesterday", or
similar). If the request does not name a day at all, use today's date
(`Get-Date -Format "yyyy-MM-dd"` via the PowerShell tool — never hand-write today's date).

### Step 2: Run the script

```
.\sdp-shared\scripts\sdp-report-logs-combine.ps1 -Date 'yyyy-MM-dd'
```

Parse the single JSON line from stdout.

1. If `status` is `"error"`: invoke
   `/sdp-create-banner icon=error row=0 row: Status | [error field from script].`
   and stop.
2. If `status` is `"success"`: proceed to Step 3 with the full JSON object in hand. Treat every
   field in it as already-correct, final content — do not re-read or re-verify the output file
   yourself; the script's own envelope (`sourcesFound`, `sourceCounts`, `totalCombinedEntries`) is
   the complete, authoritative record of what happened.

### Step 3: Confirm

Invoke `/sdp-create-banner` with a `Combine` row, drawn directly from the script's JSON output:
the date combined, which of the three sources were found (`sourcesFound`) and which (if any)
were absent, per-source entry counts (`sourceCounts`), the total combined entry count, and the
output path. If any source had a non-zero `unparseableLineCount`, mention it — that source's
file had malformed lines skipped during the merge. E.g.
`icon=success row=0 row: Combine | [date] combined — [sources found/absent]. [per-source counts], [total] total. Written to [output path].`

## Constraints

- Never re-derive or hand-verify the combined file's content — if the entry count or a mapping
  looks wrong, that's a script bug to fix in `sdp-report-logs-combine.ps1` and re-run, not something to
  patch by re-reading and re-summarizing the source jsonl files yourself.
- Do not treat a missing source file (one of the three logs not yet existing for that day) as an
  error — the script already handles this; only report it as a plain fact ("no hook-log activity
  yet today"), not a problem to fix.
- Do not invoke this skill's script with a date range or multiple dates — the combined-log file is
  one-per-calendar-day, matching every other log in this project; combine one day per invocation.

## Outputs

- `combined-log-yyyyMMdd.jsonl` written (or overwritten) under
  `.sdp-solution-workflow/logging/combined-logs/`.
- User-facing confirmation of what was combined, per the script's JSON envelope.
