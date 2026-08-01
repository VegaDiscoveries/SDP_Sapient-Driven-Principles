<#
.SYNOPSIS
    Parse a solution's combined-log-*.jsonl (produced by sdp-report-logs-combine.ps1, which normalizes
    loop-metrics/hook-log/workflow-log into one common envelope shape) and compute every part of
    an SDP combined-metrics report that is derivable from the jsonl alone via a fixed,
    dataset-agnostic rule: source/category/role/outcome/event-name breakdowns, a Concerning Events
    table (fixed outcome/event-name filter), work-item activity, and three timeline SVGs sharing
    one time axis -- (1) a session/agent Gantt-style timeline colored by source, (2) a binned
    stacked histogram colored by event category, (3) a binned stacked histogram colored by role.
    Narrative content (root-cause analysis, materiality of a concerning event, "next step"
    recommendations) is explicitly out of scope; report-assembly judgment belongs to the calling
    skill.

.PARAMETER JsonlPath
    Path to a combined-log-*.jsonl file. The calling skill always resolves and passes this
    explicitly (one file exists per calendar day under
    .sdp-solution-workflow/logging/combined-logs/ at the solution root). If omitted (e.g. direct
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
    Reads the already-normalized envelope shape (timestamp/source/category/role/work_item/phase/
    event_name/outcome/reason/detail/raw) -- it does not re-parse or re-interpret the `raw` field
    of any entry, except where explicitly noted (the Rule 1 timeline reads `raw.session_id`/
    `raw.agent_id`, fields that exist only on hook-log-sourced entries and have no equivalent in
    the normalized envelope, since only hook-log carries session/subagent identity).
    Free-text fields that end up in a markdown table cell (reason) are escaped for pipe
    characters and newlines via Format-TableCell -- unlike sdp-report-log-workflow-metrics.ps1,
    this script's Concerning Events table does not surface `detail`; that field is preserved only
    in each entry's `raw` object.

    Timeline binning (Rules 2/3): a FIXED bin COUNT (40), not a fixed bin duration -- each bin's
    duration is computed as (total period seconds / 40), so a report covering one hour gets the
    same 40-column resolution as one covering a full week, rather than a short period collapsing
    to a handful of near-empty columns under a fixed duration like "15 minutes per bin."

    Session/agent identification (Rule 1): verified directly against real hook-log data before
    implementing (2026-07-17), not assumed from the field names alone -- every `agent_id` observed
    maps to exactly one `session_id` with a contiguous own timespan; no agent_id was observed
    spanning multiple sessions or with a large internal gap suggesting reuse. This script relies
    on that structure (group by session_id, then by agent_id within it) but does not re-verify it
    per run -- a future change to sdp-hook-log.ps1's agent_id semantics would need this script
    revisited.
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
    $combinedLogsDir = Join-Path $workspaceRoot ".sdp-solution-workflow/logging/combined-logs"
    $latest = Get-ChildItem -Path $combinedLogsDir -Filter "combined-log-*.jsonl" -File -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if ($latest) { $JsonlPath = $latest.FullName }
    else {
        Write-Result @{ status = "error"; error = "no combined-log-*.jsonl files found under $combinedLogsDir and -JsonlPath was not provided" }
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

function Group-WithNoneLast($items, $selector) {
    $groups = $items | Group-Object { $v = & $selector $_; if ($v) { [string]$v } else { "(none)" } }
    $real = @($groups | Where-Object { $_.Name -ne "(none)" } | Sort-Object Count -Descending)
    $none = @($groups | Where-Object { $_.Name -eq "(none)" })
    return $real + $none
}

# ---------------------------------------------------------------------------
# Source / category / role / outcome breakdowns.
# ---------------------------------------------------------------------------
$sourceGroups = $events | Group-Object source | Sort-Object Count -Descending
$sourceBreakdown = @()
foreach ($g in $sourceGroups) { $sourceBreakdown += [ordered]@{ source = $g.Name; count = $g.Count } }
$sourceRows = ($sourceBreakdown | ForEach-Object { "| $(Format-TableCell $_.source) | $($_.count) |" }) -join "`n"
$sourceBreakdownTableMarkdown = @"
| Source | Count |
|---|---|
$sourceRows
"@

$categoryGroups = $events | Group-Object category | Sort-Object Count -Descending
$categoryBreakdown = @()
foreach ($g in $categoryGroups) { $categoryBreakdown += [ordered]@{ category = $g.Name; count = $g.Count } }
$categoryRows = ($categoryBreakdown | ForEach-Object { "| $(Format-TableCell $_.category) | $($_.count) |" }) -join "`n"
$categoryBreakdownTableMarkdown = @"
| Category | Count |
|---|---|
$categoryRows
"@

$roleGroups = Group-WithNoneLast $events { param($e) $e.role }
$roleBreakdown = @()
foreach ($g in $roleGroups) { $roleBreakdown += [ordered]@{ role = $g.Name; count = $g.Count } }
$roleRows = ($roleBreakdown | ForEach-Object { "| $(Format-TableCell $_.role) | $($_.count) |" }) -join "`n"
$roleBreakdownTableMarkdown = @"
| Role | Count |
|---|---|
$roleRows
"@

$outcomeGroups = @($events | Where-Object { $_.outcome } | Group-Object outcome | Sort-Object Count -Descending)
$outcomeBreakdown = @()
foreach ($g in $outcomeGroups) { $outcomeBreakdown += [ordered]@{ outcome = $g.Name; count = $g.Count } }
$outcomeRows = ($outcomeBreakdown | ForEach-Object { "| $(Format-TableCell $_.outcome) | $($_.count) |" }) -join "`n"
$outcomeBreakdownTableMarkdown = @"
| Outcome | Count |
|---|---|
$outcomeRows
"@

# event_name breakdown -- bounded cardinality in practice (skill:event pairs, hook-event:tool
# pairs, or a fixed workflow trigger vocabulary), so no top-N cap is applied; every distinct value
# is shown, sorted by count descending.
$eventNameGroups = $events | Group-Object event_name | Sort-Object Count -Descending
$eventNameBreakdown = @()
foreach ($g in $eventNameGroups) { $eventNameBreakdown += [ordered]@{ eventName = $g.Name; count = $g.Count } }
$eventNameRows = ($eventNameBreakdown | ForEach-Object { "| $(Format-TableCell $_.eventName) | $($_.count) |" }) -join "`n"
$eventNameBreakdownTableMarkdown = @"
| Event Name | Count |
|---|---|
$eventNameRows
"@

# ---------------------------------------------------------------------------
# Shared row shape for Concerning Events (the only remaining per-event table -- the full
# chronological table was replaced by the three timelines below, per user direction 2026-07-17:
# a 3800+-row table added no readable value at hook-log's typical event volume).
# ---------------------------------------------------------------------------
function New-EventRow($e) {
    return [ordered]@{
        timestampDisplay = Format-Clock $e._dt
        source = [string]$e.source
        role = if ($e.role) { [string]$e.role } else { $null }
        eventName = [string]$e.event_name
        workItem = if ($e.work_item) { [string]$e.work_item } else { $null }
        phase = if ($e.phase) { [string]$e.phase } else { $null }
        outcome = if ($e.outcome) { [string]$e.outcome } else { $null }
        reason = if ($e.reason) { [string]$e.reason } else { $null }
    }
}
function Format-EventTableRow($row) {
    return "| $($row.timestampDisplay) | $(Format-TableCell $row.source) | $(Format-TableCell $row.role) | $(Format-TableCell $row.eventName) | $(Format-TableCell $row.workItem) | $(Format-TableCell $row.phase) | $(Format-TableCell $row.outcome) | $(Format-TableCell $row.reason) |"
}

# ---------------------------------------------------------------------------
# Concerning Events -- same fixed, dataset-agnostic candidate filter as
# sdp-report-log-workflow-metrics.ps1 (outcome in the blocking-token set, or an event name
# starting with "halt."), extended here to any source since loop-metrics' own workflow-tone
# entries (category "workflow-tone") carry the same halt.* trigger vocabulary once normalized
# into event_name. Not a materiality judgment -- surfacing a row means "worth a look."
# ---------------------------------------------------------------------------
$concerningOutcomes = @("DIAGNOSIS_BLOCKED", "GATE_BLOCKED", "REJECTED")
$concerningEvents = @($events | Where-Object { ($_.outcome -and $concerningOutcomes -contains $_.outcome) -or ($_.event_name -and $_.event_name.ToString().StartsWith("halt.")) })
$concerningRows = @($concerningEvents | ForEach-Object { New-EventRow $_ })
$concerningTableRows = ($concerningRows | ForEach-Object { Format-EventTableRow $_ }) -join "`n"
$concerningTableMarkdown = if ($concerningRows.Count -gt 0) {
@"
| Time | Source | Role | Event | Work Item | Phase | Outcome | Reason |
|---|---|---|---|---|---|---|---|
$concerningTableRows
"@
} else { "" }

# ---------------------------------------------------------------------------
# Work-item activity -- grouped by work_item across all three sources (real values only).
# Distinct Sources shows which log(s) contributed to that work item's story this period -- e.g.
# a work item with both "loop-metrics" and "hook-log" rows had both a dispatch action and actual
# tool-call activity logged. Final Outcome is the outcome field of the chronologically last event
# for that work_item that actually has a non-null outcome.
# ---------------------------------------------------------------------------
$workItemGroups = @($events | Where-Object { $_.work_item } | Group-Object work_item)
$workItemActivity = @()
foreach ($g in ($workItemGroups | Sort-Object { ($_.Group | Sort-Object _dt | Select-Object -First 1)._dt })) {
    $wiEvents = @($g.Group | Sort-Object _dt)
    $first = $wiEvents[0]._dt
    $last = $wiEvents[-1]._dt
    $distinctSources = @($wiEvents | Select-Object -ExpandProperty source -Unique)
    $lastOutcome = @($wiEvents | Where-Object { $_.outcome } | Sort-Object _dt | Select-Object -Last 1)
    $finalOutcome = if ($lastOutcome.Count -gt 0) { [string]$lastOutcome[0].outcome } else { $null }
    $workItemActivity += [ordered]@{
        workItem = $g.Name
        eventCount = $wiEvents.Count
        firstDisplay = Format-Clock $first
        lastDisplay = Format-Clock $last
        durationDisplay = Format-Duration (($last - $first).TotalSeconds)
        distinctSources = $distinctSources
        distinctSourcesDisplay = ($distinctSources -join ", ")
        finalOutcome = $finalOutcome
    }
}
$workItemActivityRows = ($workItemActivity | ForEach-Object { "| $(Format-TableCell $_.workItem) | $($_.eventCount) | $($_.firstDisplay) | $($_.lastDisplay) | $($_.durationDisplay) | $(Format-TableCell $_.distinctSourcesDisplay) | $(Format-TableCell $_.finalOutcome) |" }) -join "`n"
$workItemActivityTableMarkdown = @"
| Work Item | Events | First | Last | Duration | Sources | Final Outcome |
|---|---|---|---|---|---|---|
$workItemActivityRows
"@

$distinctWorkItemNames = @($events | Where-Object { $_.work_item } | Select-Object -ExpandProperty work_item -Unique)

# ---------------------------------------------------------------------------
# Shared timeline helpers -- x-position and time-bin math used by all three Rules.
# ---------------------------------------------------------------------------
$timelineBarWidth = 880
$timelineBinCount = 40
$totalPeriodSeconds = ($periodEnd - $periodStart).TotalSeconds
if ($totalPeriodSeconds -le 0) { $totalPeriodSeconds = 1 }

function Get-XPosition([datetimeoffset]$dt, [datetimeoffset]$rangeStart, [double]$rangeSeconds, [int]$width) {
    if ($rangeSeconds -le 0) { $rangeSeconds = 1 }
    return [math]::Round((($dt - $rangeStart).TotalSeconds / $rangeSeconds) * $width, 2)
}

# ---------------------------------------------------------------------------
# Rule 1: Session / Agent timeline, colored by source. Built only from hook-log-sourced events --
# the only source carrying session_id/agent_id (see .NOTES for the verified session<->agent
# relationship this relies on). loop-metrics/workflow-log entries carry no session_id, so they
# render as their own point-marker pseudo-lanes rather than being force-fit into a session they
# were never attributed to -- this is what gives the "color by source" dimension real meaning
# (every hook-log session lane is necessarily the same hue; the pseudo-lanes are what actually
# differ by source).
# ---------------------------------------------------------------------------
$colorHookLog = "#2a78d6"      # categorical slot 1 (blue)
$colorLoopMetrics = "#008300"  # categorical slot 2 (green)
$colorWorkflowLog = "#e87ba4"  # categorical slot 3 (magenta)

$hookLogEvents = @($events | Where-Object { $_.source -eq "hook-log" })
$loopMetricsEvents = @($events | Where-Object { $_.source -eq "loop-metrics" })
$workflowLogEvents = @($events | Where-Object { $_.source -eq "workflow-log" })

$sessionGroups = @($hookLogEvents | Group-Object { $_.raw.session_id } | Sort-Object { ($_.Group | Sort-Object _dt | Select-Object -First 1)._dt })
$sessionLanes = @()
$sessionOrdinal = 0
foreach ($sg in $sessionGroups) {
    $sessionOrdinal++
    $sessEvents = @($sg.Group | Sort-Object _dt)
    $sessFirst = $sessEvents[0]._dt
    $sessLast = $sessEvents[-1]._dt
    $agentGroups = @($sessEvents | Where-Object { $_.raw.agent_id } | Group-Object { $_.raw.agent_id })
    $agentSpans = @()
    foreach ($ag in $agentGroups) {
        $agEvents = @($ag.Group | Sort-Object _dt)
        $agentSpans += [ordered]@{
            agentId = $ag.Name
            start = $agEvents[0]._dt
            end = $agEvents[-1]._dt
            eventCount = $agEvents.Count
        }
    }
    $sessionLanes += [ordered]@{
        label = "Session $sessionOrdinal"
        sessionId = $sg.Name
        start = $sessFirst
        end = $sessLast
        eventCount = $sessEvents.Count
        agentSpans = $agentSpans
    }
}

function New-SessionAgentTimelineSvg {
    $labelWidth = 110
    $laneHeight = 16
    $laneGap = 4
    $lanePitch = $laneHeight + $laneGap

    $lanes = @()
    if ($loopMetricsEvents.Count -gt 0) { $lanes += [ordered]@{ kind = "points"; label = "loop-metrics"; color = $colorLoopMetrics; events = $loopMetricsEvents } }
    if ($workflowLogEvents.Count -gt 0) { $lanes += [ordered]@{ kind = "points"; label = "workflow-log"; color = $colorWorkflowLog; events = $workflowLogEvents } }
    foreach ($sl in $sessionLanes) { $lanes += [ordered]@{ kind = "session"; data = $sl } }

    if ($lanes.Count -eq 0) { return $null }

    $svgHeight = ($lanes.Count * $lanePitch) + 24
    $rects = ""
    $labels = ""
    $y = 6
    foreach ($lane in $lanes) {
        if ($lane.kind -eq "points") {
            foreach ($e in $lane.events) {
                $cx = Get-XPosition $e._dt $periodStart $totalPeriodSeconds $timelineBarWidth
                $rects += "  <circle cx=`"$cx`" cy=`"$([math]::Round($y + $laneHeight/2,2))`" r=`"4`" fill=`"$($lane.color)`" stroke=`"#fcfcfb`" stroke-width=`"2`"/>`n"
            }
            $labels += "  <text x=`"$($timelineBarWidth+6)`" y=`"$([math]::Round($y + $laneHeight/2 + 4,2))`" text-anchor=`"start`" font-family=`"system-ui, -apple-system, 'Segoe UI', sans-serif`" font-size=`"10`" fill=`"#52514e`">$($lane.label)</text>`n"
        } else {
            $sd = $lane.data
            $x1 = Get-XPosition $sd.start $periodStart $totalPeriodSeconds $timelineBarWidth
            $x2 = Get-XPosition $sd.end $periodStart $totalPeriodSeconds $timelineBarWidth
            $w = [math]::Round([math]::Max($x2 - $x1, 2), 2)
            # Light track = full session span (Meter pattern: lighter step of the same hue reads
            # as "state" across the whole bar) -- see palette.md's Meter contract.
            $rects += "  <rect x=`"$x1`" y=`"$y`" width=`"$w`" height=`"$laneHeight`" rx=`"3`" fill=`"$colorHookLog`" fill-opacity=`"0.25`"/>`n"
            # Full-opacity overlay = subagent-active sub-spans -- only these windows show the
            # "fill" per the same Meter pattern; the rest of the lane stays at track opacity,
            # meaning "parent session's own tool calls, no subagent dispatched at that moment."
            foreach ($ag in $sd.agentSpans) {
                $ax1 = Get-XPosition $ag.start $periodStart $totalPeriodSeconds $timelineBarWidth
                $ax2 = Get-XPosition $ag.end $periodStart $totalPeriodSeconds $timelineBarWidth
                $aw = [math]::Round([math]::Max($ax2 - $ax1, 2), 2)
                $rects += "  <rect x=`"$ax1`" y=`"$y`" width=`"$aw`" height=`"$laneHeight`" rx=`"2`" fill=`"$colorHookLog`"/>`n"
            }
            $labels += "  <text x=`"$($timelineBarWidth+6)`" y=`"$([math]::Round($y + $laneHeight/2 + 4,2))`" text-anchor=`"start`" font-family=`"system-ui, -apple-system, 'Segoe UI', sans-serif`" font-size=`"10`" fill=`"#52514e`">$($sd.label)</text>`n"
        }
        $y += $lanePitch
    }

    $startLabel = Format-Clock $periodStart
    $endLabel = Format-Clock $periodEnd
    $ariaLabel = "Session and agent timeline from $startLabel to $endLabel, colored by source"
    $totalWidth = $timelineBarWidth + $labelWidth
    return "<svg width=`"$totalWidth`" height=`"$([math]::Round($svgHeight+16,2))`" viewBox=`"0 0 $totalWidth $([math]::Round($svgHeight+16,2))`" xmlns=`"http://www.w3.org/2000/svg`" role=`"img`" aria-label=`"$ariaLabel`">`n$labels$rects  <text x=`"0`" y=`"$([math]::Round($svgHeight+8,2))`" text-anchor=`"start`" font-family=`"system-ui, -apple-system, 'Segoe UI', sans-serif`" font-size=`"11`" fill=`"#898781`">$startLabel</text>`n  <text x=`"$timelineBarWidth`" y=`"$([math]::Round($svgHeight+8,2))`" text-anchor=`"end`" font-family=`"system-ui, -apple-system, 'Segoe UI', sans-serif`" font-size=`"11`" fill=`"#898781`">$endLabel</text>`n</svg>"
}

function New-LegendHtml($colorMap, $categoryOrder, $labelMap) {
    $spanParts = @()
    foreach ($c in $categoryOrder) {
        $label = if ($labelMap.Contains($c)) { $labelMap[$c] } else { $c }
        $spanParts += "<span style=`"display:inline-block;width:10px;height:10px;background:$($colorMap[$c]);border-radius:2px;margin-right:4px;vertical-align:middle;`"></span>$label&nbsp;&nbsp;&nbsp;"
    }
    return "<div>`n" + ($spanParts -join "") + "`n</div>"
}

$sessionAgentTimelineSvg = New-SessionAgentTimelineSvg
$rule1ColorMap = [ordered]@{}
$rule1CategoryOrder = @()
$rule1LabelMap = [ordered]@{}
if ($sessionLanes.Count -gt 0) { $rule1ColorMap["hook-log"] = $colorHookLog; $rule1CategoryOrder += "hook-log"; $rule1LabelMap["hook-log"] = "hook-log (session; darker = subagent active)" }
if ($loopMetricsEvents.Count -gt 0) { $rule1ColorMap["loop-metrics"] = $colorLoopMetrics; $rule1CategoryOrder += "loop-metrics"; $rule1LabelMap["loop-metrics"] = "loop-metrics" }
if ($workflowLogEvents.Count -gt 0) { $rule1ColorMap["workflow-log"] = $colorWorkflowLog; $rule1CategoryOrder += "workflow-log"; $rule1LabelMap["workflow-log"] = "workflow-log" }
$sessionAgentLegendHtml = if ($rule1CategoryOrder.Count -gt 0) { New-LegendHtml $rule1ColorMap $rule1CategoryOrder $rule1LabelMap } else { "" }

# ---------------------------------------------------------------------------
# Shared binned-stacked-histogram builder for Rules 2 and 3. Bin COUNT is fixed
# ($timelineBinCount); bin DURATION is computed from the period span, so short and long periods
# both get full column resolution (user direction, 2026-07-17) rather than a fixed duration like
# "15 minutes per bin" starving a short period of columns.
# ---------------------------------------------------------------------------
function New-BinnedStackedTimelineSvg($items, [scriptblock]$categorizer, $categoryOrder, $colorMap, [string]$ariaLabelSuffix) {
    if ($items.Count -eq 0) { return $null }
    $maxBarHeight = 140
    $gap = 2
    $binSeconds = $totalPeriodSeconds / $timelineBinCount
    $colWidth = ($timelineBarWidth - ($gap * ($timelineBinCount - 1))) / $timelineBinCount

    $binTallies = New-Object 'object[]' $timelineBinCount
    for ($i = 0; $i -lt $timelineBinCount; $i++) {
        $t = [ordered]@{}
        foreach ($c in $categoryOrder) { $t[$c] = 0 }
        $binTallies[$i] = $t
    }
    foreach ($item in $items) {
        $offsetSeconds = ($item._dt - $periodStart).TotalSeconds
        $binIndex = [int][math]::Floor($offsetSeconds / $binSeconds)
        if ($binIndex -ge $timelineBinCount) { $binIndex = $timelineBinCount - 1 }
        if ($binIndex -lt 0) { $binIndex = 0 }
        $cat = & $categorizer $item
        if ($binTallies[$binIndex].Contains($cat)) { $binTallies[$binIndex][$cat]++ }
    }

    $maxBinTotal = 0
    foreach ($t in $binTallies) {
        $sum = 0
        foreach ($c in $categoryOrder) { $sum += [int]$t[$c] }
        if ($sum -gt $maxBinTotal) { $maxBinTotal = $sum }
    }
    if ($maxBinTotal -eq 0) { $maxBinTotal = 1 }
    $vScale = $maxBarHeight / $maxBinTotal

    $rects = ""
    for ($i = 0; $i -lt $timelineBinCount; $i++) {
        $x = [math]::Round($i * ($colWidth + $gap), 2)
        $yCursor = $maxBarHeight
        foreach ($c in $categoryOrder) {
            $count = [int]$binTallies[$i][$c]
            if ($count -le 0) { continue }
            $h = [math]::Round($count * $vScale, 2)
            $yTop = [math]::Round($yCursor - $h, 2)
            $rects += "  <rect x=`"$x`" y=`"$yTop`" width=`"$([math]::Round($colWidth,2))`" height=`"$h`" fill=`"$($colorMap[$c])`"/>`n"
            $yCursor -= $h
        }
    }

    $startLabel = Format-Clock $periodStart
    $endLabel = Format-Clock $periodEnd
    $svgHeight = $maxBarHeight + 24
    $ariaLabel = "Event timeline from $startLabel to $endLabel, $ariaLabelSuffix, $timelineBinCount time bins"
    return "<svg width=`"$timelineBarWidth`" height=`"$svgHeight`" viewBox=`"0 0 $timelineBarWidth $svgHeight`" xmlns=`"http://www.w3.org/2000/svg`" role=`"img`" aria-label=`"$ariaLabel`">`n$rects  <line x1=`"0`" y1=`"$maxBarHeight`" x2=`"$timelineBarWidth`" y2=`"$maxBarHeight`" stroke=`"#c3c2b7`" stroke-width=`"1`"/>`n  <text x=`"0`" y=`"$([math]::Round($maxBarHeight+16,2))`" text-anchor=`"start`" font-family=`"system-ui, -apple-system, 'Segoe UI', sans-serif`" font-size=`"11`" fill=`"#898781`">$startLabel</text>`n  <text x=`"$timelineBarWidth`" y=`"$([math]::Round($maxBarHeight+16,2))`" text-anchor=`"end`" font-family=`"system-ui, -apple-system, 'Segoe UI', sans-serif`" font-size=`"11`" fill=`"#898781`">$endLabel</text>`n</svg>"
}

# ---------------------------------------------------------------------------
# Rule 2: Event category timeline. "Tool" (hook-event) splits into Pre/Post as two shades of one
# hue (same-category, two directions -- not two unrelated categories); the other four categories
# each get their own categorical slot. Order and colors are fixed regardless of which categories
# are actually present in a given period, so a color never means something different report to
# report.
#
# Cross-chart color consistency (user direction, 2026-07-17): "workflow-event" here has a true
# 1:1 correspondence to Rule 1's "workflow-log" source lane (it IS that source's only category),
# so it reuses that lane's exact color -- a reader can trace the same underlying data across both
# charts by color alone. "workflow-tone" is deliberately NOT given that same color even though the
# name looks similar: it is loop-metrics-sourced (a workflow-event *tone* trigger logged via
# sdp-tone.ps1, e.g. halt.no_progress), not workflow-log data -- reusing the workflow-log color
# there would misattribute it. "action" and "skill-tone" are also loop-metrics-sourced but do not
# get Rule 1's loop-metrics color either: loop-metrics itself contributes three different
# categories here (skill-tone/action/workflow-tone), so no single one of them can claim "the"
# loop-metrics color without misrepresenting the other two.
# ---------------------------------------------------------------------------
$rule2ColorMap = [ordered]@{
    "tool-pre" = "#86b6ef"
    "tool-post" = "#2a78d6"
    "skill-tone" = "#B7410E"
    "action" = "#1baf7a"
    "workflow-tone" = "#eda100"
    "workflow-event" = "#e87ba4"
}
$rule2LabelMap = [ordered]@{
    "tool-pre" = "Tool (Pre)"
    "tool-post" = "Tool (Post)"
    "skill-tone" = "Skill Tone"
    "action" = "Action"
    "workflow-tone" = "Workflow Tone"
    "workflow-event" = "Workflow Event"
}
$rule2CategoryOrder = @("tool-pre", "tool-post", "skill-tone", "action", "workflow-tone", "workflow-event")
$rule2Categorizer = {
    param($e)
    if ($e.category -eq "hook-event") {
        if ($e.event_name -and $e.event_name.ToString().StartsWith("PreToolUse:")) { return "tool-pre" }
        return "tool-post"
    }
    return $e.category
}
$categoryTimelineSvg = New-BinnedStackedTimelineSvg $events $rule2Categorizer $rule2CategoryOrder $rule2ColorMap "colored by event category"
$presentR2 = @($rule2CategoryOrder | Where-Object { $_ -in @($events | ForEach-Object { & $rule2Categorizer $_ }) })
$categoryTimelineLegendHtml = if ($presentR2.Count -gt 0) { New-LegendHtml $rule2ColorMap $presentR2 $rule2LabelMap } else { "" }

# ---------------------------------------------------------------------------
# Rule 3: Role timeline. "(none)" (no role attributed -- e.g. every hook-log tool call, which
# carries no role field at all) gets the muted axis gray, never a categorical hue, matching the
# "absence is not a vivid category" convention already used for Off-hours in
# sdp-report-log-loop-metrics.ps1.
# ---------------------------------------------------------------------------
$rule3ColorMap = [ordered]@{
    "COORDINATOR" = "#2a78d6"
    "WORKER" = "#008300"
    "REVIEWER" = "#e87ba4"
    "GATE_REVIEWER" = "#eda100"
    "STATE_LOOP" = "#1baf7a"
    "(none)" = "#c3c2b7"
}
$rule3LabelMap = [ordered]@{
    "COORDINATOR" = "COORDINATOR"
    "WORKER" = "WORKER"
    "REVIEWER" = "REVIEWER"
    "GATE_REVIEWER" = "GATE_REVIEWER"
    "STATE_LOOP" = "STATE_LOOP"
    "(none)" = "No role attributed"
}
$rule3CategoryOrder = @("COORDINATOR", "WORKER", "REVIEWER", "GATE_REVIEWER", "STATE_LOOP", "(none)")
$rule3Categorizer = { param($e) if ($e.role) { return [string]$e.role } else { return "(none)" } }
$roleTimelineSvg = New-BinnedStackedTimelineSvg $events $rule3Categorizer $rule3CategoryOrder $rule3ColorMap "colored by role"
$presentR3 = @($rule3CategoryOrder | Where-Object { $_ -in @($events | ForEach-Object { & $rule3Categorizer $_ }) })
$roleTimelineLegendHtml = if ($presentR3.Count -gt 0) { New-LegendHtml $rule3ColorMap $presentR3 $rule3LabelMap } else { "" }

# ---------------------------------------------------------------------------
# Static Methodology boilerplate.
# ---------------------------------------------------------------------------
$methodologyMarkdown = @"
- This report reads the already-normalized envelope shape ``sdp-report-logs-combine.ps1`` produces --
  every field here (``source``, ``category``, ``role``, ``work_item``, ``phase``, ``event_name``,
  ``outcome``, ``reason``) traces to that script's own fixed mapping rules, not a
  re-interpretation of the original ``raw`` entry, except the Session/Agent timeline (Rule 1),
  which reads ``raw.session_id``/``raw.agent_id`` directly since only ``hook-log`` entries carry
  those fields at all.
- *Event* is the unified "what happened" label: for ``loop-metrics`` it is
  ``{skillName}:{event}`` (skill tones), the raw ``trigger`` (workflow tones), or the raw
  ``action`` (dispatch actions); for ``hook-log`` it is ``{hook_event_name}:{tool_name}``; for
  ``workflow-log`` it is the raw ``trigger``.
- *Concerning Events* is a fixed, dataset-agnostic filter -- outcome in
  ``DIAGNOSIS_BLOCKED``/``GATE_BLOCKED``/``REJECTED``, or an event name starting with ``halt.`` --
  applied mechanically, with no judgment about severity or root cause. A row appearing here means
  "worth a look," not "confirmed a problem."
- *Work Item Activity* durations are first-timestamp-to-last-timestamp spans across this period's
  combined entries for that work item -- not an elapsed-time figure paired from explicit
  dispatch-start/completion tone events the way ``sdp-report-log-loop-metrics`` computes them.
- **Session/Agent timeline (Rule 1):** built only from ``hook-log`` entries -- the only source
  carrying ``session_id``/``agent_id``. Each session lane's light "track" spans that
  ``session_id``'s full first-to-last logged event; a darker full-opacity overlay marks the
  sub-span(s) where a distinct ``agent_id`` (a dispatched subagent) was active -- verified
  directly against real data before this script was written: every ``agent_id`` maps to exactly
  one ``session_id``, with its own contiguous timespan, never spanning multiple sessions.
  ``loop-metrics``/``workflow-log`` entries carry no ``session_id`` at all and render as their own
  point-marker lanes rather than being attributed to a session they were never logged against.
- **Category and Role timelines (Rules 2/3):** both are binned stacked histograms, not raw
  per-event marks -- at typical ``hook-log`` volume (thousands of point events per day), a
  mark-per-event rendering is an unreadable solid smear. Bin COUNT is fixed
  ($timelineBinCount); bin DURATION is this period's span divided by that count, so a short
  period gets the same column resolution as a long one. A tall, hook-log-colored/no-role column
  is the expected shape on an interactive session with little automated dispatch activity, not an
  anomaly.
- **"Workflow Tone" vs. "Workflow Event" (Rule 2) are different sources despite the similar
  names:** ``workflow-tone`` is a ``loop-metrics`` entry -- a workflow-event *tone* trigger (e.g.
  ``halt.no_progress``) logged via ``sdp-tone.ps1``'s event channel; ``workflow-event`` is an
  actual ``workflow-log`` entry. Only ``workflow-event`` shares its color with Rule 1's
  ``workflow-log`` lane -- it is that source's only category, a true 1:1 correspondence.
  ``workflow-tone`` keeps its own distinct color precisely because it is *not* workflow-log data,
  even though the name looks related.
- On a high-tool-call-volume day, ``hook-log`` ``hook-event`` activity dominates all three
  timelines by sheer count -- this is expected and not suppressed; the breakdown tables above
  give the exact counts behind what the timelines show visually.
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
    }
    totals = @{ totalEvents = $totalEvents }
    sourceBreakdown = $sourceBreakdown
    sourceBreakdownTableMarkdown = $sourceBreakdownTableMarkdown
    categoryBreakdown = $categoryBreakdown
    categoryBreakdownTableMarkdown = $categoryBreakdownTableMarkdown
    roleBreakdown = $roleBreakdown
    roleBreakdownTableMarkdown = $roleBreakdownTableMarkdown
    outcomeBreakdown = $outcomeBreakdown
    outcomeBreakdownTableMarkdown = $outcomeBreakdownTableMarkdown
    eventNameBreakdown = $eventNameBreakdown
    eventNameBreakdownTableMarkdown = $eventNameBreakdownTableMarkdown
    concerningEvents = $concerningRows
    concerningTableMarkdown = $concerningTableMarkdown
    concerningCount = $concerningRows.Count
    workItemActivity = $workItemActivity
    workItemActivityTableMarkdown = $workItemActivityTableMarkdown
    sessionAgentTimelineSvg = $sessionAgentTimelineSvg
    sessionAgentLegendHtml = $sessionAgentLegendHtml
    categoryTimelineSvg = $categoryTimelineSvg
    categoryTimelineLegendHtml = $categoryTimelineLegendHtml
    roleTimelineSvg = $roleTimelineSvg
    roleTimelineLegendHtml = $roleTimelineLegendHtml
    methodologyMarkdown = $methodologyMarkdown
    anomalies = @{
        unparseableLineCount = $unparseableLineCount
    }
}
exit 0
