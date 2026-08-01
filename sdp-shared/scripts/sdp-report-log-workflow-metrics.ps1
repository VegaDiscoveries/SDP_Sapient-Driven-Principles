<#
.SYNOPSIS
    Parse a solution's workflow-log-*.jsonl semantic workflow-event log and compute every part of
    an SDP workflow-log report that is derivable from the jsonl alone via a fixed, dataset-agnostic
    rule: trigger/role/outcome breakdowns, a full chronological events table, a Concerning Events
    table (fixed outcome/trigger filter -- candidate surfacing only, not a materiality judgment),
    and work-item/phase activity tables (first/last/duration span, distinct triggers, final
    outcome). Narrative content (root-cause analysis, materiality of a concerning event, "next
    step" recommendations) is explicitly out of scope -- those require judgment this script does
    not perform; report-assembly judgment belongs to the calling skill.

.PARAMETER JsonlPath
    Path to a workflow-log-*.jsonl file. The calling skill always resolves and passes this
    explicitly (one file exists per local calendar day under
    .sdp-solution-workflow/logging/workflow-logs/ at the solution root). If omitted (e.g. direct
    script invocation outside the skill), defaults to the most recently dated file in that folder.

.PARAMETER Date
    Single calendar date filter (yyyy-MM-dd). Only events on this date are included.

.PARAMETER StartDate
    Inclusive range start (yyyy-MM-dd). Used together with -EndDate.

.PARAMETER EndDate
    Inclusive range end (yyyy-MM-dd). Used together with -StartDate.

.PARAMETER Days
    Integer, must be > 0. Trailing window ending today, inclusive: 1 = today only, 2 = yesterday
    and today, N = the N calendar days ending today.

.PARAMETER IncludeSeconds
    Switch. When present, every time value in the output is formatted hh:mm:ss instead of the
    default hh:mm. Precision of the underlying computation is unaffected either way -- this only
    changes how many digits are printed.

.NOTES
    Stdout: single-line JSON result object (agent-consumed script per SDP-Script-Authoring.md).
    Exit codes: 0 = success (status may still be "error" inside the JSON for a handled condition);
    1 reserved for an operational failure that prevented any JSON from being written at all.
    Filter precedence if more than one is supplied: -Date > -StartDate/-EndDate > -Days > full file.
    `reason`/`detail` are free text supplied by the logging caller (e.g. a phase-gate rejection
    narrative) and can legitimately contain characters that break a markdown table (`|`,
    newlines) -- every table-cell field in this script's output is passed through Format-TableCell
    (pipe-escape, newline-collapse) before being pre-rendered into a *TableMarkdown string.
#>
param(
    [string]$JsonlPath = "",
    [string]$Date = "",
    [string]$StartDate = "",
    [string]$EndDate = "",
    [int]$Days = 0,
    [switch]$IncludeSeconds
)

function Write-Result([hashtable]$hash) {
    Write-Output ($hash | ConvertTo-Json -Compress -Depth 12)
}

function Format-TableCell($value) {
    if ($null -eq $value) { return "" }
    $s = [string]$value
    $s = $s -replace "\r?\n", " "
    $s = $s -replace "\|", "\|"
    return $s
}

$workspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $JsonlPath) {
    $workflowLogsDir = Join-Path $workspaceRoot ".sdp-solution-workflow/logging/workflow-logs"
    $latest = Get-ChildItem -Path $workflowLogsDir -Filter "workflow-log-*.jsonl" -File -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if ($latest) { $JsonlPath = $latest.FullName }
    else {
        Write-Result @{ status = "error"; error = "no workflow-log-*.jsonl files found under $workflowLogsDir and -JsonlPath was not provided" }
        exit 0
    }
}

if (-not (Test-Path $JsonlPath)) {
    Write-Result @{ status = "error"; error = "jsonl not found: $JsonlPath" }
    exit 0
}

# ---------------------------------------------------------------------------
# Load and parse every line (one JSON object per line -- not a single array). A line that fails
# to parse, or lacks a timestamp, is dropped and counted -- never fabricated or fatal.
# ---------------------------------------------------------------------------
$rawLines = Get-Content $JsonlPath -Encoding UTF8
$events = @()
$unparseableLineCount = 0
foreach ($line in $rawLines) {
    if (-not $line -or $line.Trim() -eq "") { continue }
    try {
        $obj = $line | ConvertFrom-Json
        if ($obj.timestamp) { $events += $obj } else { $unparseableLineCount++ }
    } catch { $unparseableLineCount++ }
}

if ($events.Count -eq 0) {
    Write-Result @{ status = "error"; error = "no parseable timestamped events in jsonl" }
    exit 0
}

foreach ($e in $events) {
    Add-Member -InputObject $e -MemberType NoteProperty -Name "_dt" -Value ([datetimeoffset]::Parse($e.timestamp)) -Force
}
$events = @($events | Sort-Object { $_._dt })

# ---------------------------------------------------------------------------
# Date filter (mutually exclusive precedence: Date > StartDate/EndDate > Days > full file)
# ---------------------------------------------------------------------------
$filterStart = $null
$filterEndExclusive = $null
if ($Date) {
    $d = [datetime]::Parse($Date)
    $filterStart = $d.Date
    $filterEndExclusive = $d.Date.AddDays(1)
} elseif ($StartDate -and $EndDate) {
    $filterStart = ([datetime]::Parse($StartDate)).Date
    $filterEndExclusive = ([datetime]::Parse($EndDate)).Date.AddDays(1)
} elseif ($Days -gt 0) {
    $today = (Get-Date).Date
    $filterStart = $today.AddDays(-($Days - 1))
    $filterEndExclusive = $today.AddDays(1)
}

if ($filterStart) {
    $events = @($events | Where-Object { $_._dt.DateTime -ge $filterStart -and $_._dt.DateTime -lt $filterEndExclusive })
}

if ($events.Count -eq 0) {
    Write-Result @{ status = "error"; error = "no events remain after applying the date filter" }
    exit 0
}

$periodStart = $events[0]._dt
$periodEnd = $events[-1]._dt

function Format-Clock([datetimeoffset]$dt) {
    if ($IncludeSeconds) { return $dt.ToString("HH:mm:ss") }
    return $dt.ToString("HH:mm")
}

function Format-Duration([double]$totalSeconds) {
    $s = [int][math]::Truncate($totalSeconds)
    $h = [int]([math]::Truncate($s / 3600))
    $m = [int]([math]::Truncate(($s % 3600) / 60))
    $sec = [int]($s % 60)
    if ($IncludeSeconds) {
        if ($h -gt 0) { return ("{0}h {1:D2}m {2:D2}s" -f $h, $m, $sec) }
        if ($m -gt 0) { return ("{0}m {1:D2}s" -f $m, $sec) }
        return ("{0}s" -f $sec)
    }
    if ($h -gt 0) { return ("{0}h {1:D2}m" -f $h, $m) }
    return ("{0}m" -f $m)
}

$startDateOnly = $periodStart.Date
$endDateOnly = $periodEnd.Date
$titleDate = if ($startDateOnly -eq $endDateOnly) {
    $startDateOnly.ToString("yyyy-MM-dd")
} else {
    "{0} -> {1}" -f $startDateOnly.ToString("yyyy-MM-dd"), $endDateOnly.ToString("yyyy-MM-dd")
}
# NOTE: ASCII "->" placeholder, real unicode arrow substituted by the calling skill -- same
# ASCII-source-safe lesson as sdp-report-log-loop-metrics.ps1 (SDP-Script-Authoring.md).

$sourceLineCount = $rawLines.Count
$sourceRelative = Split-Path -Leaf $JsonlPath
$reportPreparedDate = (Get-Date).ToString("yyyy-MM-dd")
$totalEvents = $events.Count

# ---------------------------------------------------------------------------
# Trigger / role / outcome breakdowns. Role and outcome both get an explicit "(none)" bucket for
# absent values, sorted last regardless of count -- an unattributed/no-outcome bucket must never
# read as the "top" row by table position. Trigger has no such bucket: -trigger is a required,
# non-empty parameter on every sdp-workflow-log.ps1 call (a missing one is a silent no-op that
# never reaches the log at all), so every logged entry has a real trigger value.
# ---------------------------------------------------------------------------
$triggerGroups = $events | Group-Object trigger | Sort-Object Count -Descending
$triggerBreakdown = @()
foreach ($g in $triggerGroups) { $triggerBreakdown += [ordered]@{ trigger = $g.Name; count = $g.Count } }
$triggerRows = ($triggerBreakdown | ForEach-Object { "| $(Format-TableCell $_.trigger) | $($_.count) |" }) -join "`n"
$triggerBreakdownTableMarkdown = @"
| Trigger | Count |
|---|---|
$triggerRows
"@

function Group-WithNoneLast($items, $selector) {
    $groups = $items | Group-Object { $v = & $selector $_; if ($v) { [string]$v } else { "(none)" } }
    $real = @($groups | Where-Object { $_.Name -ne "(none)" } | Sort-Object Count -Descending)
    $none = @($groups | Where-Object { $_.Name -eq "(none)" })
    return $real + $none
}

$roleGroups = Group-WithNoneLast $events { param($e) $e.role }
$roleBreakdown = @()
foreach ($g in $roleGroups) { $roleBreakdown += [ordered]@{ role = $g.Name; count = $g.Count } }
$roleRows = ($roleBreakdown | ForEach-Object { "| $(Format-TableCell $_.role) | $($_.count) |" }) -join "`n"
$roleBreakdownTableMarkdown = @"
| Role | Count |
|---|---|
$roleRows
"@

# Outcome breakdown excludes "(none)" entirely (per Inputs: most workflow events -- e.g. a plain
# dispatch decision -- have no discrete outcome; a "(none)" row here would dwarf every real
# outcome token and add no information).
$outcomeGroups = @($events | Where-Object { $_.outcome } | Group-Object outcome | Sort-Object Count -Descending)
$outcomeBreakdown = @()
foreach ($g in $outcomeGroups) { $outcomeBreakdown += [ordered]@{ outcome = $g.Name; count = $g.Count } }
$outcomeRows = ($outcomeBreakdown | ForEach-Object { "| $(Format-TableCell $_.outcome) | $($_.count) |" }) -join "`n"
$outcomeBreakdownTableMarkdown = @"
| Outcome | Count |
|---|---|
$outcomeRows
"@

# ---------------------------------------------------------------------------
# Event row shape shared by the full chronological table and the Concerning Events subset.
# ---------------------------------------------------------------------------
function New-EventRow($e) {
    return [ordered]@{
        timestampDisplay = Format-Clock $e._dt
        role = if ($e.role) { [string]$e.role } else { $null }
        trigger = [string]$e.trigger
        workItem = if ($e.work_item) { [string]$e.work_item } else { $null }
        phase = if ($e.phase) { [string]$e.phase } else { $null }
        outcome = if ($e.outcome) { [string]$e.outcome } else { $null }
        reason = [string]$e.reason
        detail = if ($e.detail) { [string]$e.detail } else { $null }
    }
}
function Format-EventTableRow($row) {
    return "| $($row.timestampDisplay) | $(Format-TableCell $row.role) | $(Format-TableCell $row.trigger) | $(Format-TableCell $row.workItem) | $(Format-TableCell $row.phase) | $(Format-TableCell $row.outcome) | $(Format-TableCell $row.reason) |"
}

$eventRows = @($events | ForEach-Object { New-EventRow $_ })
$eventsTableRows = ($eventRows | ForEach-Object { Format-EventTableRow $_ }) -join "`n"
$eventsTableMarkdown = @"
| Time | Role | Trigger | Work Item | Phase | Outcome | Reason |
|---|---|---|---|---|---|---|
$eventsTableRows
"@

# ---------------------------------------------------------------------------
# Concerning Events -- a fixed, dataset-agnostic candidate filter (outcome in the blocking-token
# set, or trigger starts with "halt."), not a materiality judgment. Surfacing a row here means
# "worth a human/skill look," not "confirmed a problem" -- the calling skill's own judgment
# decides what (if anything) to say about each one.
# ---------------------------------------------------------------------------
$concerningOutcomes = @("DIAGNOSIS_BLOCKED", "GATE_BLOCKED", "REJECTED")
$concerningEvents = @($events | Where-Object { ($_.outcome -and $concerningOutcomes -contains $_.outcome) -or ($_.trigger -and $_.trigger.ToString().StartsWith("halt.")) })
$concerningRows = @($concerningEvents | ForEach-Object { New-EventRow $_ })
$concerningTableRows = ($concerningRows | ForEach-Object { Format-EventTableRow $_ }) -join "`n"
$concerningTableMarkdown = if ($concerningRows.Count -gt 0) {
@"
| Time | Role | Trigger | Work Item | Phase | Outcome | Reason |
|---|---|---|---|---|---|---|
$concerningTableRows
"@
} else { "" }

# ---------------------------------------------------------------------------
# Work-item activity -- grouped by work_item (real values only; events with no work_item are
# phase- or solution-level and are not represented here -- see Phase Activity below for the
# phase-level equivalent). Final Outcome is the outcome field of the chronologically last event
# for that work_item that actually has a non-null outcome -- not simply the last event's outcome,
# which may itself be null (e.g. a trailing dispatch-decision entry with no discrete outcome).
# ---------------------------------------------------------------------------
$workItemGroups = @($events | Where-Object { $_.work_item } | Group-Object work_item)
$workItemActivity = @()
foreach ($g in ($workItemGroups | Sort-Object { ($_.Group | Sort-Object _dt | Select-Object -First 1)._dt })) {
    $wiEvents = @($g.Group | Sort-Object _dt)
    $first = $wiEvents[0]._dt
    $last = $wiEvents[-1]._dt
    $distinctTriggers = @($wiEvents | Select-Object -ExpandProperty trigger -Unique)
    $lastOutcome = @($wiEvents | Where-Object { $_.outcome } | Sort-Object _dt | Select-Object -Last 1)
    $finalOutcome = if ($lastOutcome.Count -gt 0) { [string]$lastOutcome[0].outcome } else { $null }
    $workItemActivity += [ordered]@{
        workItem = $g.Name
        eventCount = $wiEvents.Count
        firstDisplay = Format-Clock $first
        lastDisplay = Format-Clock $last
        durationDisplay = Format-Duration (($last - $first).TotalSeconds)
        distinctTriggers = $distinctTriggers
        distinctTriggersDisplay = ($distinctTriggers -join ", ")
        finalOutcome = $finalOutcome
    }
}
$workItemActivityRows = ($workItemActivity | ForEach-Object { "| $(Format-TableCell $_.workItem) | $($_.eventCount) | $($_.firstDisplay) | $($_.lastDisplay) | $($_.durationDisplay) | $(Format-TableCell $_.finalOutcome) |" }) -join "`n"
$workItemActivityTableMarkdown = @"
| Work Item | Events | First | Last | Duration | Final Outcome |
|---|---|---|---|---|---|
$workItemActivityRows
"@

# ---------------------------------------------------------------------------
# Phase activity -- same shape as Work Item Activity, grouped by phase instead.
# ---------------------------------------------------------------------------
$phaseGroups = @($events | Where-Object { $_.phase } | Group-Object phase | Sort-Object { ($_.Group | Sort-Object _dt | Select-Object -First 1)._dt })
$phaseActivity = @()
foreach ($g in $phaseGroups) {
    $pEvents = @($g.Group | Sort-Object _dt)
    $first = $pEvents[0]._dt
    $last = $pEvents[-1]._dt
    $phaseActivity += [ordered]@{
        phase = $g.Name
        eventCount = $pEvents.Count
        firstDisplay = Format-Clock $first
        lastDisplay = Format-Clock $last
        durationDisplay = Format-Duration (($last - $first).TotalSeconds)
    }
}
$phaseActivityRows = ($phaseActivity | ForEach-Object { "| $(Format-TableCell $_.phase) | $($_.eventCount) | $($_.firstDisplay) | $($_.lastDisplay) | $($_.durationDisplay) |" }) -join "`n"
$phaseActivityTableMarkdown = @"
| Phase | Events | First | Last | Duration |
|---|---|---|---|---|
$phaseActivityRows
"@

$distinctWorkItemNames = @($events | Where-Object { $_.work_item } | Select-Object -ExpandProperty work_item -Unique)
$distinctPhaseNames = @($events | Where-Object { $_.phase } | Select-Object -ExpandProperty phase -Unique)

# ---------------------------------------------------------------------------
# Static Methodology boilerplate.
# ---------------------------------------------------------------------------
$methodologyMarkdown = @"
- ``trigger`` reuses the same named-event vocabulary as ``SDP-Tones.json``'s ``events`` table
  where applicable -- one taxonomy shared by the tone and logging systems. A trigger absent from
  that table is not an error; ``sdp-workflow-log.ps1`` accepts any non-empty string.
- ``role`` is the dispatching role **at the moment of this event** (``COORDINATOR`` / ``WORKER``
  / ``REVIEWER`` / ``GATE_REVIEWER`` / ``STATE_LOOP``), not a claim about who owns the work item
  overall -- a single work item's timeline in Work Item Activity below will show several
  different roles across its lifecycle.
- *Concerning Events* is a fixed, dataset-agnostic filter -- outcome in
  ``DIAGNOSIS_BLOCKED`` / ``GATE_BLOCKED`` / ``REJECTED``, or a trigger starting with ``halt.`` --
  applied mechanically, with no judgment about severity or root cause. A row appearing here means
  "worth a look," not "confirmed a problem"; materiality assessment is report-assembly work, not
  something this script performs.
- *Work Item Activity* and *Phase Activity* durations are first-timestamp-to-last-timestamp spans
  across this log's own entries for that grouping -- they are **not** the same as
  ``sdp-report-log-loop-metrics``'s elapsed-time figures, which pair explicit dispatch-start/
  completion tone events. A work item with only two log entries an hour apart shows a 1-hour
  span here even if most of that hour was actual implementation work never separately logged.
- *Final Outcome* is the outcome field of the chronologically **last** event for that grouping
  that actually carries a non-null outcome -- not simply the grouping's last event, which may
  itself be an outcome-less entry (e.g. a trailing dispatch-decision log line).
"@

Write-Result @{
    status = "success"
    error = $null
    period = @{
        startIso = $periodStart.ToString("o")
        endIso = $periodEnd.ToString("o")
        startDisplay = Format-Clock $periodStart
        endDisplay = Format-Clock $periodEnd
        titleDate = $titleDate
    }
    header = @{
        sourceFile = $sourceRelative
        sourceLineCount = $sourceLineCount
        reportPreparedDate = $reportPreparedDate
        distinctWorkItemNames = $distinctWorkItemNames
        distinctPhaseNames = $distinctPhaseNames
    }
    totals = @{ totalEvents = $totalEvents }
    triggerBreakdown = $triggerBreakdown
    triggerBreakdownTableMarkdown = $triggerBreakdownTableMarkdown
    roleBreakdown = $roleBreakdown
    roleBreakdownTableMarkdown = $roleBreakdownTableMarkdown
    outcomeBreakdown = $outcomeBreakdown
    outcomeBreakdownTableMarkdown = $outcomeBreakdownTableMarkdown
    events = $eventRows
    eventsTableMarkdown = $eventsTableMarkdown
    concerningEvents = $concerningRows
    concerningTableMarkdown = $concerningTableMarkdown
    concerningCount = $concerningRows.Count
    workItemActivity = $workItemActivity
    workItemActivityTableMarkdown = $workItemActivityTableMarkdown
    phaseActivity = $phaseActivity
    phaseActivityTableMarkdown = $phaseActivityTableMarkdown
    methodologyMarkdown = $methodologyMarkdown
    anomalies = @{
        unparseableLineCount = $unparseableLineCount
    }
}
exit 0
