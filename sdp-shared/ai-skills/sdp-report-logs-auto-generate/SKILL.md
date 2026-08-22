## Purpose

Generate all 4 SDP log reports (loop-metrics, hook-metrics, workflow-metrics, combined-metrics)
covering the period since the last auto-report, when `sdp-solution-phase-coordinator` Step 2d
detects that every registered project has reached `work_complete` and this is a genuinely new
completion (not a repeat of one already recorded). Also cancels any active state loop and writes
the durable completion record the idempotency guard reads on future invocations.

This skill is caller-invoked only — it is never invoked interactively by a user with no dates
given, and never presents an `AskUserQuestion` picker itself. `sdp-solution-phase-coordinator`
Step 2d resolves `period_start`/`period_end` and the idempotency guard before invoking this skill;
this skill does not re-derive either.

## Inputs

- `--period-start=[yyyy-MM-dd]` — required. Supplied by the caller.
- `--period-end=[yyyy-MM-dd]` — required. Supplied by the caller.

## Procedure

### Step 1: Parse Invocation Arguments

Parse `--period-start=` and `--period-end=` from the invocation arguments. If either is missing
or fails to parse as `yyyy-MM-dd`: invoke
`/sdp-create-banner icon=error row=0 row: Status | sdp-report-logs-auto-generate invoked without a valid --period-start/--period-end — this skill is caller-invoked only, not a user-facing entry point.`
and halt. Do not proceed to Step 2.

### Step 2: Ensure Combined-Log Coverage For Every Day In The Period

For each calendar date from `period_start` to `period_end` inclusive, invoke `sdp-report-logs-combine`
(via the Skill tool) with that date as the invocation argument. This is idempotent — a day already
combined is safely recomputed. Record which dates produced `status: "success"` and which produced
`status: "error"` (a day with none of the three source logs present — not itself a failure of this
skill, just a day with no combined-log entry to include in the range merge below).

### Step 3: Merge Each Source Type Across The Period

Run, once per source type, via the PowerShell tool:

```
.\sdp-shared\scripts\sdp-report-logs-merge-range.ps1 -SourceType [type] -StartDate [period_start] -EndDate [period_end]
```

`[type]` is each of `loop-metrics`, `hook-log`, `workflow-log`, `combined-log` in turn — four
separate calls. Parse each single-line JSON result.

- `status: "success"` — record `outputPath` as this source type's range file, to feed the
  corresponding report skill in Step 4.
- `status: "error"` — no data exists for this source type across the whole period (e.g. no
  hook-log activity occurred). Record this source type as skipped for Step 4; this is not a
  reason to halt the skill — the other source types proceed independently.

If all four return `status: "error"`: invoke
`/sdp-create-banner icon=warning row=0 row: Status | No log data found for any source between [period_start] and [period_end] — no reports generated.`
and proceed directly to Step 6 (still write the completion record and cancel the loop — the
all-complete condition is real even if there's nothing to report on).

### Step 4: Generate Each Report

For each source type with a successfully merged range file from Step 3, invoke the corresponding
report skill via the Skill tool, passing:

```
--range-file=[outputPath from Step 3] --start-date=[period_start] --end-date=[period_end]
```

| Source type | Report skill |
|---|---|
| `loop-metrics` | `sdp-report-log-loop-metrics` |
| `hook-log` | `sdp-report-log-hook-metrics` |
| `workflow-log` | `sdp-report-log-workflow-metrics` |
| `combined-log` | `sdp-report-log-combined-metrics` |

Each report skill's own Level 0 auto-invocation override (see each skill's Step 1) resolves the
supplied file directly and runs its normal procedure otherwise unchanged — including opening the
finished report file. Record each report's output path as it completes.

### Step 5: Confirm Report Generation

Collect the list of report paths actually produced in Step 4. This list may be shorter than 4 if
Step 3 found no data for one or more source types — that is an accurate reflection of what
happened this period, not an error to correct.

### Step 6: Write the Completion Record

Read `.sdp-solution-workflow/state.json`. Append to `auto_actions`:

```json
{
  "timestamp": "[current ISO timestamp]",
  "action": "auto_report_generated",
  "period_start": "[period_start]",
  "period_end": "[period_end]",
  "report_paths": ["[path from Step 5]", "..."]
}
```

Update `updated` to the current ISO date. Write the file. This entry is what
`sdp-solution-phase-coordinator` Step 2d's idempotency guard reads on future invocations to
determine whether a later all-complete detection is genuinely new.

### Step 7: Cancel Any Active State Loop

Invoke `/sdp-cancel-auto` (via the Skill tool). Per that skill's own behavior, this is a safe
no-op if no SDP state-loop cron job is currently running — do not treat "no matching jobs found"
as an error here.

### Step 8: Notify

1. Play the milestone tone (non-blocking — ignore any failure): run
   `.\sdp-shared\scripts\sdp-tone.ps1 -trigger "milestone.all_projects_complete"` via the
   PowerShell tool.
2. Log the event (non-blocking — ignore any failure): run via the PowerShell tool —
   ```
   .\sdp-shared\scripts\sdp-workflow-log.ps1 -trigger "milestone.all_projects_complete" -role "COORDINATOR" -outcome "ALL_PROJECTS_COMPLETE" -reason "Every registered project reached work_complete for period [period_start] to [period_end] — generated [N] of 4 reports; state loop cancelled." -detail "[comma-separated report paths]"
   ```
3. Invoke `/sdp-create-banner` with a `Report` row summarizing what happened, e.g.
   `icon=success row=0 row: Report | All projects complete for [period_start] to [period_end] — [N] of 4 reports generated and opened. State loop cancelled.`

## Constraints

- Never invoke this skill without both `--period-start` and `--period-end` already resolved by
  the caller — this skill never presents a picker or infers a period on its own.
- Never treat a single source type's Step 3 `status: "error"` as a reason to skip the other three
  source types — each source type's data availability is independent.
- Never skip Step 6 (the completion record) or Step 7 (loop cancellation) because Step 3/4
  produced fewer than 4 reports — the all-complete condition and its bookkeeping are independent
  of how much log data happened to exist for the period.
- Never modify a report skill's Step 7 (opening the finished report) — the auto path only
  overrides file/date resolution (each report skill's own Step 1 Level 0), never the rest of that
  skill's procedure.
- Never re-derive the all-complete condition or the idempotency guard here — both are
  `sdp-solution-phase-coordinator` Step 2d's responsibility, before this skill is ever invoked.

## Outputs

- Combined-log files ensured for every day in the period (`sdp-report-logs-combine`, Step 2).
- Up to 4 range-merged jsonl files under `.sdp-solution-workflow/logging/range-merges/` (Step 3).
- Up to 4 generated report files, each opened in the user's default associated application by its
  own report skill's Step 7 (Step 4).
- `.sdp-solution-workflow/state.json.auto_actions` — one new `auto_report_generated` entry
  (Step 6).
- Any active SDP state-loop cron job cancelled (Step 7).
- Tone played, workflow-log entry written, and a chat-facing confirmation banner (Step 8).
