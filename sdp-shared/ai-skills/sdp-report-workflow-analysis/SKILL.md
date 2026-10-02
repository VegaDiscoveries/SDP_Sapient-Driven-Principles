## Purpose

Produce a combined workflow-analysis report for the current SDP solution: design docs
processed, phase-1-7 cycles, and registry entries (solution-level and per-project); total
sessions run with a session-to-registry mapping and a category-by-registry-row matrix; hook-log
entries per session with action/tool breakdowns; loop-log kind-of-work breakdown; and
workflow-log trigger/role/outcome breakdowns with a Concerning Events list. Writes both JSON
(for later cross-solution combination) and Markdown (for direct human review) into a dated
folder under `.sdp-solution-workflow/reports/`.

This skill is a thin assembler over six scripts
(`sdp-report-workflow-analysis-inventory.ps1`, `-sessions.ps1`, `-hooklogs.ps1`, `-looplogs.ps1`,
`-workflowlogs.ps1`, `-reconcile.ps1`) and one combine script
(`sdp-report-workflow-analysis-combine.ps1`), each of which computes everything derivable from
its own data source via a fixed, dataset-agnostic rule. The one piece of unavoidable judgment —
whether a session's mechanically-derived draft category actually matches what that session's
own content shows — is resolved by an independent classification pass (Step 7) that reads
session content blind to the script's draft label, so a systematic rule error and a lone
reviewer's misreading cannot both slip through the same blind spot.

## Inputs

- Optional date range for the three log sources (hook-logs, loop-logs, workflow-logs), as a
  `-StartDate`/`-EndDate` pair (`yyyy-MM-dd`). Absent any range, every available day-file for
  each log is processed — a workflow analysis is meant to cover the solution's full history, not
  a single day, unlike this framework's other `sdp-report-log-*` skills which default to the
  most recent day.
- Optional output folder override. Default:
  `.sdp-solution-workflow/reports/[yyyy-MM-dd]_sdp-analysis/` at the solution root, where
  `[yyyy-MM-dd]` is today's date (Step 1 obtains this from the PowerShell tool — never
  hand-typed or inferred).

## Procedure

### Step 1: Resolve and create the output folder

1. Obtain today's date via the PowerShell tool: `Get-Date -Format "yyyy-MM-dd"`. Never hand-write
   or infer this value.
2. Resolve `[output_dir]` = the input override if given, else
   `.sdp-solution-workflow/reports/[today]_sdp-analysis` at the solution root.
3. Create it via the PowerShell tool: `New-Item -ItemType Directory -Force -Path '[output_dir]'`.
   If the folder already exists (a same-day re-run), this is a no-op — treat `[output_dir]` as a
   regenerable derived artifact and let this run's files overwrite the prior run's, the same
   convention `sdp-report-logs-combine.ps1` already uses for its own derived output.

### Step 2: Run Inventory

1. Run via the PowerShell tool: `.\sdp-shared\scripts\sdp-report-workflow-analysis-inventory.ps1`.
2. Capture the single stdout JSON line verbatim. Use the Write tool to save it, byte for byte, to
   `[output_dir]/01_inventory.json` — no reformatting, no re-indentation, no hand edits.
3. Parse the same line for control flow. If `status` is `"error"`: invoke
   `/sdp-create-banner icon=error row=0 row: Status | Inventory step failed: [error field].` and
   stop — do not proceed to Step 3.
4. If `anomalies.solutionJsonMissing` is `true`: invoke
   `/sdp-create-banner icon=error row=0 row: Status | SDP-Solution.json not found at solution root — cannot run a workflow analysis.`
   and stop.

### Step 3: Run Sessions

1. Run via the PowerShell tool: `.\sdp-shared\scripts\sdp-report-workflow-analysis-sessions.ps1`.
2. Capture the stdout JSON line verbatim; save it to `[output_dir]/02_sessions.json` (Write
   tool, no edits).
3. If `status` is `"error"`: invoke
   `/sdp-create-banner icon=error row=0 row: Status | Sessions step failed: [error field].` and
   stop.
4. Note `totalSessions` — used by Step 7's batching decision.

### Step 4: Run Hook Logs

1. Run via the PowerShell tool:
   `.\sdp-shared\scripts\sdp-report-workflow-analysis-hooklogs.ps1 [-StartDate yyyy-MM-dd -EndDate yyyy-MM-dd]`
   (omit both flags unless this invocation supplied a date range).
2. Capture and save verbatim to `[output_dir]/03_hook_logs.json`.
3. `status: "error"` here halts this step only — invoke
   `/sdp-create-banner icon=warning row=0 row: Status | Hook-log step failed: [error field] — continuing with the remaining sources.`
   and proceed to Step 5 anyway. A missing or unparseable hook-log source does not invalidate the
   other four sources.

### Step 5: Run Loop Logs

1. Run via the PowerShell tool:
   `.\sdp-shared\scripts\sdp-report-workflow-analysis-looplogs.ps1 [-StartDate yyyy-MM-dd -EndDate yyyy-MM-dd]`
2. Capture and save verbatim to `[output_dir]/04_loop_logs.json`.
3. Same non-fatal handling as Step 4 on `status: "error"`.

### Step 6: Run Workflow Logs

1. Run via the PowerShell tool:
   `.\sdp-shared\scripts\sdp-report-workflow-analysis-workflowlogs.ps1 [-StartDate yyyy-MM-dd -EndDate yyyy-MM-dd]`
2. Capture and save verbatim to `[output_dir]/05_workflow_logs.json`.
3. Same non-fatal handling as Step 4 on `status: "error"`.

### Step 7: Independent Session Classification

**Purpose of this step:** the sessions script's `draftCategory` (Step 3) is a mechanical rule
over two fields (Role, status transition) — cheap and fast, but blind to what the session
actually did. This step has one or more agents independently read each session's real content
(Dispatch Instructions + Session Outcome) and assign a category from the same fixed list, without
seeing the script's draft label first. Reconciling the two catches both a systematic rule error
(the draft rule is wrong for a whole class of sessions) and a content-based nuance the rule
cannot see (e.g. a `WORKER` session whose actual content shows it was pure coordination-and-defer,
not implementation) — the two failure modes a single classification pass, mechanical or
LLM-only, cannot both catch by itself.

**Fixed taxonomy (do not invent additional categories; every session gets exactly one of these):**
`Coordination / Dispatch`, `Initial Implementation`, `Rework / Correction`,
`Independent Evaluation - Pass`, `Independent Evaluation - Rejected`,
`Independent Evaluation - Other`, `Gate Review - Passed`, `Gate Review - Blocked`,
`Gate Review - Other`, `Other / Uncategorized`.

**Model tier for classification agents:** per the design-time model-selection note, this task
shape — reading a batch of short dispatch/outcome files and assigning a category using the
content, not just the Role field — is a moderate-judgment classification/review task, not a
complete-spec transcription and not an architecture-judgment task. `sdp-select-model.ps1` does
not apply here (its rule set is specific to WORKER/REVIEWER/GATE_REVIEWER Implementation Loop
dispatches against a phase state file, which this is not); resolve directly against
`sdp-shared/scripts/script-support/sdp-subagent-model-roster.json`'s tier taxonomy instead —
this task matches the `standard` tier's `use_when` ("review of moderate-complexity diffs"),
closest analogue for reading and categorizing dispatch content. Dispatch every classification
agent in this step at the `standard` tier's currently-assigned model.

1. If `totalSessions` (Step 3) is `0`: skip this entire step (nothing to classify) and skip Step
   8's `ReconcileJsonPath` argument — proceed to Step 8 with an absent/empty classification
   input. Do not fabricate a classification result for zero sessions.
2. Read `[output_dir]/02_sessions.json`. Build a stripped session list containing only `file`,
   `date`, `role`, `workItem`, `dispatchedBy` for every entry — omit `draftCategory`,
   `statusFrom`, and `statusTo` from what any classification agent sees, so the agent's judgment
   is not anchored by the script's own signal or a near-verbatim restatement of it.
3. Determine batch count: if `totalSessions <= 40`, one batch (one agent handles everything). If
   `totalSessions > 40`, `batchCount = min(6, ceil(totalSessions / 40))` — split the stripped
   session list into `batchCount` contiguous chunks in the list's existing order (mirroring the
   simple, proven range-split — e.g. sessions 1-40, 41-80, 81-120 — from the prior-art solution
   this skill's design is based on).
4. Dispatch one subagent per batch (parallel, single message, multiple Agent tool calls) at the
   `standard` model tier. Each agent's prompt must include: the fixed taxonomy list verbatim; the
   instruction to open each session file in its batch (Read tool) and read its Dispatch
   Instructions and Session Outcome content, not just the header fields already given; and the
   instruction to return, as its final report, a JSON array of exactly
   `{"file": "<the same file path given>", "agentCategory": "<one taxonomy value>"}` objects, one
   per session in its batch, no additional commentary mixed into that array.
5. After all batch agents return: merge every batch's JSON array into one combined array. Use the
   Write tool to save it to `[output_dir]/02_classification_raw.json`.
6. Run via the PowerShell tool:
   `.\sdp-shared\scripts\sdp-report-workflow-analysis-reconcile.ps1 -SessionsJsonPath '[output_dir]/02_sessions.json' -ClassificationsJsonPath '[output_dir]/02_classification_raw.json'`
7. Capture and save the stdout verbatim to `[output_dir]/02_classification.json`.
8. If `status` is `"error"`: invoke
   `/sdp-create-banner icon=warning row=0 row: Status | Session classification reconciliation failed: [error field] — report will omit the classification section.`
   and proceed to Step 8 without a `ReconcileJsonPath` argument.

### Step 8: Combine

1. Run via the PowerShell tool:
   ```
   .\sdp-shared\scripts\sdp-report-workflow-analysis-combine.ps1 `
     -InventoryJsonPath '[output_dir]/01_inventory.json' `
     -SessionsJsonPath '[output_dir]/02_sessions.json' `
     -HookLogsJsonPath '[output_dir]/03_hook_logs.json' `
     -LoopLogsJsonPath '[output_dir]/04_loop_logs.json' `
     -WorkflowLogsJsonPath '[output_dir]/05_workflow_logs.json' `
     -ReconcileJsonPath '[output_dir]/02_classification.json' `
     -OutputPath '[output_dir]/00_combined.json'
   ```
   Omit `-ReconcileJsonPath` if Step 7 was skipped or failed. Omit any of the log-source paths
   whose stage failed in Steps 4-6 (the combine script tolerates a missing/null section for any
   source and records it as absent rather than fabricating one).
2. If `status` is `"error"`: invoke
   `/sdp-create-banner icon=error row=0 row: Status | Combine step failed: [error field].` and
   stop — do not proceed to Step 9 without a combined JSON to render from.

### Step 9: Assemble the Markdown Deliverables

**Every figure in every file this step writes is a literal substitution from a named field in
one of this run's own script JSON outputs (Steps 2-8) — never hand-recomputed, never restated
from memory of an earlier step, never invented.** This is the direct fix for a real defect found
in a prior-art solution this skill's design was compared against: a narrative claim ("12
categories were found") that did not match the categories actually present in that solution's
own delivered data. Treating this step as strict template substitution — the same discipline
`sdp-report-log-loop-metrics`'s own Step 6 already applies to its report — makes that class of
drift structurally impossible here, not just less likely.

Every file's first line is the SDP logo embed (path relative from
`.sdp-solution-workflow/reports/[date]_sdp-analysis/` back to the solution root), followed by one
blank line:

```html
<img src="../../../sdp-shared/docs/images/SDP_DocsLogo_WithText_0700x0163.png" alt="SDP Logo" width="375">
```

1. **`01_inventory.md`** — from `01_inventory.json`: solution name; design docs processed count;
   a table of phase cycles (`name`, `phaseStateFileCount`); a table of registry rows
   (`solutionRegistry` as one row labeled "Solution", then one row per `projects[]` entry) with
   columns Scope / Total Rows / Complete Rows. List any `anomalies` entries as a bullet list
   beneath the tables; omit the anomalies section entirely if all anomaly fields are empty/false.
2. **`02_sessions.md`** — from `02_sessions.json` and (if present) `02_classification.json`: total
   sessions; a table of `bySource` (source, path, count); a table of `draftCategoryCounts`
   (mechanical draft, for reference); if classification ran, a second table of
   `agentCategoryCounts` plus the `agreementRate`/`agreed`/`disagreed` figures, and — if
   `disagreements` is non-empty — a full table of every disagreement (`file`, `draftCategory`,
   `agentCategory`), never a truncated sample. If classification did not run (Step 7 skipped or
   failed), state that plainly and omit the classification tables rather than fabricating them.
3. **`03_hook_logs.md`** — from `03_hook_logs.json`: files processed, total entries,
   unparseable-line count, a table of `toolTotals`, a table of `levelTotals`, and a table of
   `bySession` (sessionId, entryCount, subagentEntryCount) sorted by `entryCount` descending.
4. **`04_loop_logs.md`** — from `04_loop_logs.json`: files processed, total entries, tone-only
   entry count, and the `workKindMatrix` table (action, description, count) sorted by count
   descending.
5. **`05_workflow_logs.md`** — from `05_workflow_logs.json`: files processed, total entries,
   tables of `triggerCounts`/`roleCounts`/`outcomeCounts`, and — if `concerningEvents` is
   non-empty — a full table of every concerning event (timestamp, trigger, role, workItem,
   outcome, reason); note if `anomalies.concerningEventsTruncated` is `true`.
6. **`00_report.md`** — the synthesized top-level deliverable, from `00_combined.json` plus a
   pointer to each detail file:
   - `# SDP Workflow Analysis — {{solution_name}} — {{generated_at}}`
   - A one-paragraph **(judgment, bounded)** summary: total sessions, registry completion
     (solution + each project, from `inventory`), and the classification agreement rate if
     present — state only what the numbers show, do not editorialize beyond them.
   - `## Design Docs, Phase Cycles, and Registry` — the same table as `01_inventory.md`,
     substituted from `inventory` verbatim.
   - `## Sessions` — `sessions_summary`'s `bySource` and `draftCategoryCounts` tables, plus the
     `session_classification` agreement rate and disagreement table if present.
   - `## Hook Logs` — `hook_logs_summary`'s `toolTotals`/`levelTotals` tables and `sessionCount`.
   - `## Loop Logs` — `loop_logs.workKindMatrix` table in full (this section is small enough to
     embed directly rather than only summarize, per the combine script's own compact-vs-bulky
     split).
   - `## Workflow Logs` — `workflow_logs_summary`'s breakdown tables and `concerningEventCount`;
     if greater than zero, direct the reader to `05_workflow_logs.md` for the full list rather
     than repeating it here.
   - `## Detail Files` — a bullet list linking each of the five stage `.md` files and the raw
     `00_combined.json`, for a reader or a future cross-solution-combination agent who needs the
     full per-session/per-day detail this top-level report intentionally summarizes.

### Step 10: Confirm

Invoke `/sdp-create-banner` with a `Report` row naming `[output_dir]`, `totalSessions`, whether
classification ran, and which of the three log sources (hook/loop/workflow) succeeded vs. were
skipped, e.g.
`icon=success row=0 row: Report | [output_dir] written — [N] sessions analyzed. Classification: [ran/skipped]. Logs: hook [ok/skipped], loop [ok/skipped], workflow [ok/skipped].`

## Constraints

- Never fabricate a section, table, or figure this step's own script outputs did not produce —
  an absent section (missing log source, skipped classification, zero sessions) is always
  reported as absent, never filled in with an invented or estimated value.
- Never let a classification agent see the sessions script's `draftCategory` before it submits
  its own classification for that session — an anchored agent produces false agreement, which
  defeats the entire purpose of Step 7.
- Never allow a classification agent to invent a category outside the fixed taxonomy list, and
  never silently map an agent's out-of-taxonomy answer onto the nearest fixed value —
  treat an out-of-taxonomy response as a reconciliation anomaly to surface, not a value to
  normalize away quietly.
- Never recompute, override, or "correct" a script-produced figure by hand for a single run. If a
  figure looks wrong, that is a script bug to fix in the relevant
  `sdp-report-workflow-analysis-*.ps1` file and re-run — not something to patch around in the
  assembled Markdown.
- Never truncate a disagreement list or a concerning-events list in the Markdown output when the
  underlying JSON contains the full list — Step 9 explicitly requires the full table, not a
  sample, for exactly the data a reader would use to decide whether to trust the report's own
  agreement rate.
- Never write to any location outside `[output_dir]` for this run's deliverables.

## Outputs

- `[output_dir]/01_inventory.json` / `.md`
- `[output_dir]/02_sessions.json` / `.md`, plus `02_classification_raw.json` and
  `02_classification.json` when Step 7 ran
- `[output_dir]/03_hook_logs.json` / `.md`
- `[output_dir]/04_loop_logs.json` / `.md`
- `[output_dir]/05_workflow_logs.json` / `.md`
- `[output_dir]/00_combined.json` and `[output_dir]/00_report.md`
- User-facing confirmation banner naming the output folder and what was included vs. skipped.
