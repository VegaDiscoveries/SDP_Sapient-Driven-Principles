<#
.SYNOPSIS
    Parse a solution's hook-log-*.jsonl raw tool-call and prompt-submission telemetry and compute
    every part of an SDP hook-log report that is derivable from the jsonl alone via a fixed,
    dataset-agnostic rule: total/Pre/Post/prompt counts, subagent-vs-main-session split (as two
    composition bars), a level breakdown, a tool-usage chart (stacked Pre/Post), a session/agent
    Gantt-style timeline, a prompts-per-session chart plus a prompt-submission ruler, and a
    work-item breakdown chart. Narrative content (which sessions or tools are noteworthy, "next
    step" recommendations) is explicitly out of scope -- this script only aggregates; report-
    assembly judgment belongs to the calling skill.

.PARAMETER JsonlPath
    Path to a hook-log-*.jsonl file. The calling skill always resolves and passes this explicitly
    (one file exists per local calendar day under .sdp-solution-workflow/logging/hook-logs/ at
    the solution root). If omitted (e.g. direct script invocation outside the skill), defaults to
    the most recently dated file in that folder.

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
    Free-text fields placed into an SVG <text> element (tool_name, work_item, session labels) are
    escaped for XML special characters via Format-XmlText -- hook-log values are machine-generated
    (tool names, GUIDs), not free text, but the same defense-in-depth used elsewhere applies.

    Color scheme (user direction, 2026-07-17: convert every table in this report to a chart):
    this report is entirely single-source (hook-log), so every chart uses one signature blue
    (`#2a78d6`, the same hex `sdp-report-log-combined-metrics.ps1` uses for its hook-log lane, for
    cross-report consistency) with a light-blue shade (`#86b6ef`) reserved for the one real
    sub-dimension that needs a second color (Pre vs. Post), and muted gray (`#c3c2b7`) for
    "(none)"/absence buckets. Bar/category identity is carried by each row's own direct label, not
    by a distinct hue per category -- there is no fixed, small vocabulary here the way there is for
    Level (only 4 real values) or role in the combined report, so a distinct-hue-per-tool/
    work-item scheme would not scale and would add no information a label doesn't already carry.

    Session/agent Gantt timeline: reuses the exact technique verified and built for
    sdp-report-log-combined-metrics.ps1's Rule 1 (light track = full session span, darker overlay
    = agent_id sub-spans, labels on the right of the bar -- moving them there was itself a fix
    applied to that script after an alignment bug, carried over here from the start). Single-
    source here, so no per-lane color-by-source is needed the way the combined report's pseudo-
    lanes require it.
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

function Format-XmlText($value) {
    if ($null -eq $value) { return "" }
    $s = [string]$value
    $s = $s -replace "&", "&amp;"
    $s = $s -replace "<", "&lt;"
    $s = $s -replace ">", "&gt;"
    return $s
}

$workspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $JsonlPath) {
    $hookLogsDir = Join-Path $workspaceRoot ".sdp-solution-workflow/logging/hook-logs"
    $latest = Get-ChildItem -Path $hookLogsDir -Filter "hook-log-*.jsonl" -File -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if ($latest) { $JsonlPath = $latest.FullName }
    else {
        Write-Result @{ status = "error"; error = "no hook-log-*.jsonl files found under $hookLogsDir and -JsonlPath was not provided" }
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

# ---------------------------------------------------------------------------
# Signature colors -- see .NOTES for the reasoning (single-source report, one hue family).
# ---------------------------------------------------------------------------
$colorPrimary = "#2a78d6"   # blue -- this report's signature color (matches hook-log's identity
                            # in sdp-report-log-combined-metrics.ps1)
$colorSecondary = "#86b6ef" # light blue -- the one real sub-dimension needing a second shade
$colorAccent = "#008300"    # green -- reserved for "subagent" in the Totals composition bar,
                            # deliberately a different hue family from Pre/Post's blues so the
                            # two composition bars are never visually confused with each other
$colorMuted = "#c3c2b7"     # muted gray -- "(none)" / absence buckets, never a vivid hue

# ---------------------------------------------------------------------------
# Totals -- Pre/Post split, subagent-vs-main-session split (agent_id present only inside a
# dispatched subagent's own tool calls, per sdp-hook-log.ps1's own contract).
# ---------------------------------------------------------------------------
$totalEvents = $events.Count
$preCount = @($events | Where-Object { $_.hook_event_name -eq "PreToolUse" }).Count
$postCount = @($events | Where-Object { $_.hook_event_name -eq "PostToolUse" }).Count
$promptSubmitCount = @($events | Where-Object { $_.hook_event_name -eq "UserPromptSubmit" }).Count
$subagentCount = @($events | Where-Object { $_.agent_id }).Count
$mainSessionCount = $totalEvents - $subagentCount
# Tool-call-only view: UserPromptSubmit entries carry no tool_name (they aren't tool calls at all)
# and must not be lumped into the tool-usage "(none)" bucket, which exists for a genuinely missing
# tool_name on a tool-call event, not for an event type that was never a tool call.
$toolCallEvents = @($events | Where-Object { $_.hook_event_name -eq "PreToolUse" -or $_.hook_event_name -eq "PostToolUse" })

# Recurses because sdp-hook-log.ps1 truncates individual string leaves in place, wherever they
# occur in the tree (a nested tool_input.prompt._truncated marker, or one inside an array of
# objects for a tool like AskUserQuestion), not the whole tool_input/tool_output object as a unit
# - a top-level-only check would silently report zero truncation forever once that change shipped.
function Test-Truncated($fieldValue, $depth = 0) {
    if ($null -eq $fieldValue) { return $false }
    if ($depth -ge 8) { return $false }
    if ($fieldValue -is [System.Management.Automation.PSCustomObject]) {
        $props = $fieldValue.PSObject.Properties
        if ($props.Name -contains "_truncated") { return [bool]$fieldValue._truncated }
        foreach ($prop in $props) {
            if (Test-Truncated $prop.Value ($depth + 1)) { return $true }
        }
        return $false
    }
    if ($fieldValue -is [System.Collections.IEnumerable] -and $fieldValue -isnot [string]) {
        foreach ($item in $fieldValue) {
            if (Test-Truncated $item ($depth + 1)) { return $true }
        }
        return $false
    }
    return $false
}
$truncatedInputCount = @($events | Where-Object { Test-Truncated $_.tool_input }).Count
$truncatedOutputCount = @($events | Where-Object { Test-Truncated $_.tool_output }).Count
$truncatedPromptCount = @($events | Where-Object { Test-Truncated $_.prompt }).Count

$totals = [ordered]@{
    totalEvents = $totalEvents
    preCount = $preCount
    postCount = $postCount
    promptSubmitCount = $promptSubmitCount
    subagentCount = $subagentCount
    mainSessionCount = $mainSessionCount
    truncatedInputCount = $truncatedInputCount
    truncatedOutputCount = $truncatedOutputCount
    truncatedPromptCount = $truncatedPromptCount
}

# ---------------------------------------------------------------------------
# Composition bar builder (loop-metrics' established pattern: one row, segments proportional to
# share of total, rounded ends only, 2px gap between segments).
# ---------------------------------------------------------------------------
function New-CompositionBarSvg($segments, [string]$ariaTitle) {
    $barWidth = 820
    $barHeight = 24
    $gap = 2
    $total = ($segments | ForEach-Object { [double]$_.count } | Measure-Object -Sum).Sum
    if ($total -le 0) { $total = 1 }
    $usable = $barWidth - ($gap * ($segments.Count - 1))
    $x = 0.0
    $rects = ""
    for ($i = 0; $i -lt $segments.Count; $i++) {
        $w = [math]::Round(($segments[$i].count / $total) * $usable, 2)
        $rx = if ($i -eq 0 -or $i -eq ($segments.Count - 1)) { ' rx="4"' } else { '' }
        $rects += "  <rect x=`"$([math]::Round($x,2))`" y=`"0`" width=`"$w`" height=`"$barHeight`"$rx fill=`"$($segments[$i].color)`"/>`n"
        $x = $x + $w + $gap
    }
    $ariaLabel = "$ariaTitle composition: " + (($segments | ForEach-Object { "$($_.label) $($_.count)" }) -join ", ")
    return "<svg width=`"$barWidth`" height=`"$barHeight`" viewBox=`"0 0 $barWidth $barHeight`" xmlns=`"http://www.w3.org/2000/svg`" role=`"img`" aria-label=`"$ariaLabel`">`n$rects</svg>"
}

function New-CompositionLegendHtml($segments) {
    $total = ($segments | ForEach-Object { [double]$_.count } | Measure-Object -Sum).Sum
    if ($total -le 0) { $total = 1 }
    $spanParts = foreach ($s in $segments) {
        $pct = [math]::Round(($s.count / $total) * 100, 1)
        "<span style=`"display:inline-block;width:10px;height:10px;background:$($s.color);border-radius:2px;margin-right:4px;vertical-align:middle;`"></span>$($s.label) $($s.count) ($pct%)&nbsp;&nbsp;&nbsp;"
    }
    return "<div>`n" + ($spanParts -join "") + "`n</div>"
}

$prePostBarSvg = New-CompositionBarSvg @(
    [ordered]@{ label = "Pre"; count = $preCount; color = $colorSecondary }
    [ordered]@{ label = "Post"; count = $postCount; color = $colorPrimary }
) "Pre/Post tool-call split"
$prePostLegendHtml = New-CompositionLegendHtml @(
    [ordered]@{ label = "Pre"; count = $preCount; color = $colorSecondary }
    [ordered]@{ label = "Post"; count = $postCount; color = $colorPrimary }
)

$subagentMainBarSvg = New-CompositionBarSvg @(
    [ordered]@{ label = "Subagent"; count = $subagentCount; color = $colorAccent }
    [ordered]@{ label = "Main session"; count = $mainSessionCount; color = $colorMuted }
) "Subagent/main-session split"
$subagentMainLegendHtml = New-CompositionLegendHtml @(
    [ordered]@{ label = "Subagent"; count = $subagentCount; color = $colorAccent }
    [ordered]@{ label = "Main session"; count = $mainSessionCount; color = $colorMuted }
)

# ---------------------------------------------------------------------------
# Shared horizontal bar chart builder (single color per row -- row identity is carried by its own
# direct label, not by hue, since Level/Work-Item/Session category sets are either too small to
# need it (Level) or unbounded (Work Item, Session), neither of which benefits from a distinct hue
# per row the way a small fixed vocabulary like Role does in the combined report).
# ---------------------------------------------------------------------------
function New-HorizontalBarChartSvg($rows, [string]$nameKey, [string]$countKey, $colorForRow, [string]$ariaLabel) {
    if ($rows.Count -eq 0) { return $null }
    $totalWidth = 880
    $labelWidth = 190
    $valueWidth = 50
    $barAreaWidth = $totalWidth - $labelWidth - $valueWidth
    $rowHeight = 20
    $rowGap = 4
    $rowPitch = $rowHeight + $rowGap
    $maxCount = ($rows | ForEach-Object { [double]$_.$countKey } | Measure-Object -Maximum).Maximum
    if ($maxCount -le 0) { $maxCount = 1 }
    $svgHeight = ($rows.Count * $rowPitch) + 6

    $bars = ""
    $labels = ""
    $y = 2
    foreach ($row in $rows) {
        $name = $row.$nameKey
        $count = $row.$countKey
        $w = [math]::Round(($count / $maxCount) * $barAreaWidth, 2)
        if ($w -lt 2) { $w = 2 }
        $color = & $colorForRow $row
        $labels += "  <text x=`"$($labelWidth-8)`" y=`"$([math]::Round($y+$rowHeight/2+4,2))`" text-anchor=`"end`" font-family=`"system-ui, -apple-system, 'Segoe UI', sans-serif`" font-size=`"11`" fill=`"#52514e`">$(Format-XmlText $name)</text>`n"
        $bars += "  <rect x=`"$labelWidth`" y=`"$y`" width=`"$w`" height=`"$rowHeight`" rx=`"4`" fill=`"$color`"/>`n"
        $bars += "  <text x=`"$([math]::Round($labelWidth+$w+6,2))`" y=`"$([math]::Round($y+$rowHeight/2+4,2))`" text-anchor=`"start`" font-family=`"system-ui, -apple-system, 'Segoe UI', sans-serif`" font-size=`"11`" fill=`"#52514e`">$count</text>`n"
        $y += $rowPitch
    }
    return "<svg width=`"$totalWidth`" height=`"$([math]::Round($svgHeight,2))`" viewBox=`"0 0 $totalWidth $([math]::Round($svgHeight,2))`" xmlns=`"http://www.w3.org/2000/svg`" role=`"img`" aria-label=`"$ariaLabel`">`n$labels$bars</svg>"
}

# ---------------------------------------------------------------------------
# Level breakdown -- TIMING/AUDIT/HUMAN_WAIT/DEBUG per sdp-hook-log-tools.json's level field.
# Sorted by count for visual ranking; row color is fixed to $colorPrimary (or $colorMuted for
# "(none)") regardless of rank, so color never means something different report to report.
# ---------------------------------------------------------------------------
$levelGroups = $events | Group-Object { if ($_.level) { [string]$_.level } else { "(none)" } } | Sort-Object Count -Descending
$levelBreakdown = @()
foreach ($g in $levelGroups) {
    $levelBreakdown += [ordered]@{ level = $g.Name; count = $g.Count }
}
$levelChartSvg = New-HorizontalBarChartSvg $levelBreakdown "level" "count" { param($row) if ($row.level -eq "(none)") { $colorMuted } else { $colorPrimary } } "Level breakdown bar chart"

# ---------------------------------------------------------------------------
# Tool usage -- per tool_name: count, Pre/Post split, truncation counts. Charted as a stacked
# horizontal bar (Pre + Post segments); truncation is called out separately as a short list rather
# than a fifth chart dimension, since it applies to only a minority of tools in practice and a
# stacked segment for a usually-zero value would just be visual noise most rows.
# ---------------------------------------------------------------------------
$toolGroups = $toolCallEvents | Group-Object { if ($_.tool_name) { [string]$_.tool_name } else { "(none)" } } | Sort-Object Count -Descending
$toolUsage = @()
foreach ($g in $toolGroups) {
    $toolEvents = @($g.Group)
    $toolPre = @($toolEvents | Where-Object { $_.hook_event_name -eq "PreToolUse" }).Count
    $toolPost = @($toolEvents | Where-Object { $_.hook_event_name -eq "PostToolUse" }).Count
    $toolTruncIn = @($toolEvents | Where-Object { Test-Truncated $_.tool_input }).Count
    $toolTruncOut = @($toolEvents | Where-Object { Test-Truncated $_.tool_output }).Count
    $toolUsage += [ordered]@{
        toolName = $g.Name
        count = $g.Count
        preCount = $toolPre
        postCount = $toolPost
        truncatedInputCount = $toolTruncIn
        truncatedOutputCount = $toolTruncOut
    }
}

function New-StackedToolChartSvg($rows) {
    if ($rows.Count -eq 0) { return $null }
    $totalWidth = 880
    $labelWidth = 190
    $valueWidth = 50
    $barAreaWidth = $totalWidth - $labelWidth - $valueWidth
    $rowHeight = 20
    $rowGap = 4
    $rowPitch = $rowHeight + $rowGap
    $maxCount = ($rows | ForEach-Object { [double]$_.count } | Measure-Object -Maximum).Maximum
    if ($maxCount -le 0) { $maxCount = 1 }
    $svgHeight = ($rows.Count * $rowPitch) + 6

    $bars = ""
    $labels = ""
    $y = 2
    foreach ($row in $rows) {
        $labels += "  <text x=`"$($labelWidth-8)`" y=`"$([math]::Round($y+$rowHeight/2+4,2))`" text-anchor=`"end`" font-family=`"system-ui, -apple-system, 'Segoe UI', sans-serif`" font-size=`"11`" fill=`"#52514e`">$(Format-XmlText $row.toolName)</text>`n"
        $xCursor = $labelWidth
        if ($row.preCount -gt 0) {
            $w = [math]::Round(($row.preCount / $maxCount) * $barAreaWidth, 2)
            $bars += "  <rect x=`"$xCursor`" y=`"$y`" width=`"$w`" height=`"$rowHeight`" fill=`"$colorSecondary`"/>`n"
            $xCursor = [math]::Round($xCursor + $w, 2)
        }
        if ($row.postCount -gt 0) {
            $w = [math]::Round(($row.postCount / $maxCount) * $barAreaWidth, 2)
            $bars += "  <rect x=`"$xCursor`" y=`"$y`" width=`"$w`" height=`"$rowHeight`" fill=`"$colorPrimary`"/>`n"
            $xCursor = [math]::Round($xCursor + $w, 2)
        }
        $bars += "  <text x=`"$([math]::Round($xCursor+6,2))`" y=`"$([math]::Round($y+$rowHeight/2+4,2))`" text-anchor=`"start`" font-family=`"system-ui, -apple-system, 'Segoe UI', sans-serif`" font-size=`"11`" fill=`"#52514e`">$($row.count)</text>`n"
        $y += $rowPitch
    }
    return "<svg width=`"$totalWidth`" height=`"$([math]::Round($svgHeight,2))`" viewBox=`"0 0 $totalWidth $([math]::Round($svgHeight,2))`" xmlns=`"http://www.w3.org/2000/svg`" role=`"img`" aria-label=`"Tool usage stacked bar chart, Pre and Post segments`">`n$labels$bars</svg>"
}

$toolUsageChartSvg = New-StackedToolChartSvg $toolUsage
$toolUsageLegendHtml = "<div>`n<span style=`"display:inline-block;width:10px;height:10px;background:$colorSecondary;border-radius:2px;margin-right:4px;vertical-align:middle;`"></span>Pre&nbsp;&nbsp;&nbsp;<span style=`"display:inline-block;width:10px;height:10px;background:$colorPrimary;border-radius:2px;margin-right:4px;vertical-align:middle;`"></span>Post&nbsp;&nbsp;&nbsp;`n</div>"

$toolsWithTruncation = @($toolUsage | Where-Object { $_.truncatedInputCount -gt 0 -or $_.truncatedOutputCount -gt 0 })
$truncationNoteParts = @()
foreach ($t in $toolsWithTruncation) {
    $bits = @()
    if ($t.truncatedInputCount -gt 0) { $bits += "$($t.truncatedInputCount) in" }
    if ($t.truncatedOutputCount -gt 0) { $bits += "$($t.truncatedOutputCount) out" }
    $truncationNoteParts += "$($t.toolName) ($($bits -join ', '))"
}
$truncationNote = if ($truncationNoteParts.Count -gt 0) { $truncationNoteParts -join "; " } else { "" }

# ---------------------------------------------------------------------------
# Sessions -- grouped by session_id (distinguishes concurrent Claude Code windows, not
# per-workflow-action). Extended (2026-07-17) to also extract per-agent_id sub-spans within each
# session, reusing the technique verified and built for sdp-report-log-combined-metrics.ps1's
# Rule 1 -- every agent_id maps to exactly one session_id with its own contiguous timespan.
# ---------------------------------------------------------------------------
$sessionGroups = $events | Group-Object { if ($_.session_id) { [string]$_.session_id } else { "(none)" } } | Sort-Object { ($_.Group | Sort-Object _dt | Select-Object -First 1)._dt }
$sessions = @()
$sessionOrdinal = 0
foreach ($g in $sessionGroups) {
    $sessionOrdinal++
    $sessEvents = @($g.Group | Sort-Object _dt)
    $first = $sessEvents[0]._dt
    $last = $sessEvents[-1]._dt
    $distinctTools = @($sessEvents | Where-Object { $_.tool_name } | Select-Object -ExpandProperty tool_name -Unique).Count
    $agentGroups = @($sessEvents | Where-Object { $_.agent_id } | Group-Object agent_id)
    $agentSpans = @()
    foreach ($ag in $agentGroups) {
        $agEvents = @($ag.Group | Sort-Object _dt)
        $agentSpans += [ordered]@{ agentId = $ag.Name; start = $agEvents[0]._dt; end = $agEvents[-1]._dt; eventCount = $agEvents.Count }
    }
    $subagentEvents = @($sessEvents | Where-Object { $_.agent_id }).Count
    $promptEvents = @($sessEvents | Where-Object { $_.hook_event_name -eq "UserPromptSubmit" } | Sort-Object _dt)
    $promptTimes = @($promptEvents | ForEach-Object { $_._dt })
    $sessions += [ordered]@{
        sessionId = $g.Name
        label = "Session $sessionOrdinal"
        firstDisplay = Format-Clock $first
        lastDisplay = Format-Clock $last
        durationDisplay = Format-Duration (($last - $first).TotalSeconds)
        eventCount = $sessEvents.Count
        distinctToolCount = $distinctTools
        subagentEventCount = $subagentEvents
        mainEventCount = $sessEvents.Count - $subagentEvents
        promptCount = $promptEvents.Count
        start = $first
        end = $last
        agentSpans = $agentSpans
        promptTimes = $promptTimes
    }
}

# ---------------------------------------------------------------------------
# Session/agent Gantt timeline -- light track (full session span) + darker overlay (agent_id
# sub-spans), the Meter pattern (see dataviz skill), same technique as the combined report's
# Rule 1. Single-source here, so every lane uses $colorPrimary -- no per-lane color dimension is
# needed the way the combined report needs one for its three different sources.
# ---------------------------------------------------------------------------
$timelineBarWidth = 780
$timelineLabelWidth = 110
$totalPeriodSeconds = ($periodEnd - $periodStart).TotalSeconds
if ($totalPeriodSeconds -le 0) { $totalPeriodSeconds = 1 }

function Get-XPosition([datetimeoffset]$dt, [datetimeoffset]$rangeStart, [double]$rangeSeconds, [int]$width) {
    if ($rangeSeconds -le 0) { $rangeSeconds = 1 }
    return [math]::Round((($dt - $rangeStart).TotalSeconds / $rangeSeconds) * $width, 2)
}

function New-SessionGanttSvg($sessionRows) {
    if ($sessionRows.Count -eq 0) { return $null }
    $laneHeight = 16
    $laneGap = 4
    $lanePitch = $laneHeight + $laneGap
    $svgHeight = ($sessionRows.Count * $lanePitch) + 24
    $rects = ""
    $labels = ""
    $y = 6
    foreach ($sd in $sessionRows) {
        $x1 = Get-XPosition $sd.start $periodStart $totalPeriodSeconds $timelineBarWidth
        $x2 = Get-XPosition $sd.end $periodStart $totalPeriodSeconds $timelineBarWidth
        $w = [math]::Round([math]::Max($x2 - $x1, 2), 2)
        $rects += "  <rect x=`"$x1`" y=`"$y`" width=`"$w`" height=`"$laneHeight`" rx=`"3`" fill=`"$colorPrimary`" fill-opacity=`"0.25`"/>`n"
        foreach ($ag in $sd.agentSpans) {
            $ax1 = Get-XPosition $ag.start $periodStart $totalPeriodSeconds $timelineBarWidth
            $ax2 = Get-XPosition $ag.end $periodStart $totalPeriodSeconds $timelineBarWidth
            $aw = [math]::Round([math]::Max($ax2 - $ax1, 2), 2)
            $rects += "  <rect x=`"$ax1`" y=`"$y`" width=`"$aw`" height=`"$laneHeight`" rx=`"2`" fill=`"$colorPrimary`"/>`n"
        }
        $labels += "  <text x=`"$($timelineBarWidth+6)`" y=`"$([math]::Round($y+$laneHeight/2+4,2))`" text-anchor=`"start`" font-family=`"system-ui, -apple-system, 'Segoe UI', sans-serif`" font-size=`"10`" fill=`"#52514e`">$($sd.label)</text>`n"
        $y += $lanePitch
    }
    $startLabel = Format-Clock $periodStart
    $endLabel = Format-Clock $periodEnd
    $totalWidth = $timelineBarWidth + $timelineLabelWidth
    $ariaLabel = "Session and agent timeline from $startLabel to $endLabel"
    return "<svg width=`"$totalWidth`" height=`"$([math]::Round($svgHeight+16,2))`" viewBox=`"0 0 $totalWidth $([math]::Round($svgHeight+16,2))`" xmlns=`"http://www.w3.org/2000/svg`" role=`"img`" aria-label=`"$ariaLabel`">`n$labels$rects  <text x=`"0`" y=`"$([math]::Round($svgHeight+8,2))`" text-anchor=`"start`" font-family=`"system-ui, -apple-system, 'Segoe UI', sans-serif`" font-size=`"11`" fill=`"#898781`">$startLabel</text>`n  <text x=`"$timelineBarWidth`" y=`"$([math]::Round($svgHeight+8,2))`" text-anchor=`"end`" font-family=`"system-ui, -apple-system, 'Segoe UI', sans-serif`" font-size=`"11`" fill=`"#898781`">$endLabel</text>`n</svg>"
}

$sessionGanttSvg = New-SessionGanttSvg $sessions

# ---------------------------------------------------------------------------
# Prompts per session -- dedicated section (user direction, 2026-07-22). Two views of the same
# promptTimes data collected in the Sessions loop above: a count-per-session bar chart (reuses the
# existing generic New-HorizontalBarChartSvg builder verbatim -- promptsPerSession is just rows of
# {sessionLabel, promptCount}, the same shape Level/Work-Item breakdowns already use), and a ruler
# showing *when* within each session those prompts landed.
# ---------------------------------------------------------------------------
$promptsPerSession = @()
foreach ($sd in $sessions) {
    if ($sd.promptCount -gt 0) {
        $promptsPerSession += [ordered]@{ sessionLabel = $sd.label; sessionId = $sd.sessionId; promptCount = $sd.promptCount }
    }
}
$promptsPerSessionChartSvg = New-HorizontalBarChartSvg $promptsPerSession "sessionLabel" "promptCount" { param($row) $colorPrimary } "Prompts per session bar chart"

# Prompt ruler -- same light-track-per-session-lane pattern as New-SessionGanttSvg (identical
# geometry constants, same Get-XPosition helper, same time axis) but a prompt is a point-in-time
# event, not a span, so it plots as a circle marker at its own timestamp rather than an overlay
# rect with a start/end -- the same point-marker idiom sdp-report-log-combined-metrics.ps1's Rule 1
# uses for its own instant (no-duration) events, applied here within each session's existing lane
# instead of as separate pseudo-lanes, since prompts already have a session_id to place them in.
function New-PromptTimelineSvg($sessionRows) {
    $rowsWithPrompts = @($sessionRows | Where-Object { $_.promptCount -gt 0 })
    if ($rowsWithPrompts.Count -eq 0) { return $null }
    $laneHeight = 16
    $laneGap = 4
    $lanePitch = $laneHeight + $laneGap
    $svgHeight = ($rowsWithPrompts.Count * $lanePitch) + 24
    $rects = ""
    $labels = ""
    $y = 6
    foreach ($sd in $rowsWithPrompts) {
        $x1 = Get-XPosition $sd.start $periodStart $totalPeriodSeconds $timelineBarWidth
        $x2 = Get-XPosition $sd.end $periodStart $totalPeriodSeconds $timelineBarWidth
        $w = [math]::Round([math]::Max($x2 - $x1, 2), 2)
        $rects += "  <rect x=`"$x1`" y=`"$y`" width=`"$w`" height=`"$laneHeight`" rx=`"3`" fill=`"$colorPrimary`" fill-opacity=`"0.25`"/>`n"
        foreach ($pt in $sd.promptTimes) {
            $cx = Get-XPosition $pt $periodStart $totalPeriodSeconds $timelineBarWidth
            $rects += "  <circle cx=`"$cx`" cy=`"$([math]::Round($y + $laneHeight/2,2))`" r=`"4`" fill=`"$colorPrimary`" stroke=`"#fcfcfb`" stroke-width=`"2`"/>`n"
        }
        $labels += "  <text x=`"$($timelineBarWidth+6)`" y=`"$([math]::Round($y+$laneHeight/2+4,2))`" text-anchor=`"start`" font-family=`"system-ui, -apple-system, 'Segoe UI', sans-serif`" font-size=`"10`" fill=`"#52514e`">$($sd.label) ($($sd.promptCount))</text>`n"
        $y += $lanePitch
    }
    $startLabel = Format-Clock $periodStart
    $endLabel = Format-Clock $periodEnd
    $totalWidth = $timelineBarWidth + $timelineLabelWidth
    $ariaLabel = "Prompt submission timeline from $startLabel to $endLabel"
    return "<svg width=`"$totalWidth`" height=`"$([math]::Round($svgHeight+16,2))`" viewBox=`"0 0 $totalWidth $([math]::Round($svgHeight+16,2))`" xmlns=`"http://www.w3.org/2000/svg`" role=`"img`" aria-label=`"$ariaLabel`">`n$labels$rects  <text x=`"0`" y=`"$([math]::Round($svgHeight+8,2))`" text-anchor=`"start`" font-family=`"system-ui, -apple-system, 'Segoe UI', sans-serif`" font-size=`"11`" fill=`"#898781`">$startLabel</text>`n  <text x=`"$timelineBarWidth`" y=`"$([math]::Round($svgHeight+8,2))`" text-anchor=`"end`" font-family=`"system-ui, -apple-system, 'Segoe UI', sans-serif`" font-size=`"11`" fill=`"#898781`">$endLabel</text>`n</svg>"
}

$promptTimelineSvg = New-PromptTimelineSvg $sessions

# ---------------------------------------------------------------------------
# Work-item breakdown -- best-effort attribution per sdp-hook-log.ps1's own resolution contract
# (SDP-Solution.json -> active project's state.json -> active_work_item; null on any failure).
# "(none)" is always sorted last regardless of count, so an unattributed bucket never reads as
# the "top" work item by chart position, and gets muted gray rather than the signature blue.
# ---------------------------------------------------------------------------
$workItemGroups = $events | Group-Object { if ($_.work_item) { [string]$_.work_item } else { "(none)" } }
$workItemGroupsSorted = @($workItemGroups | Where-Object { $_.Name -ne "(none)" } | Sort-Object Count -Descending)
$noneGroup = @($workItemGroups | Where-Object { $_.Name -eq "(none)" })
$workItemGroupsSorted += $noneGroup
$workItemBreakdown = @()
foreach ($g in $workItemGroupsSorted) {
    $workItemBreakdown += [ordered]@{ workItem = $g.Name; count = $g.Count }
}
$workItemChartSvg = New-HorizontalBarChartSvg $workItemBreakdown "workItem" "count" { param($row) if ($row.workItem -eq "(none)") { $colorMuted } else { $colorPrimary } } "Work item breakdown bar chart"

$distinctWorkItemNames = @($events | Where-Object { $_.work_item } | Select-Object -ExpandProperty work_item -Unique)

# ---------------------------------------------------------------------------
# Static Methodology boilerplate.
# ---------------------------------------------------------------------------
$methodologyMarkdown = @"
- This report aggregates raw ``PreToolUse``/``PostToolUse`` telemetry as actually logged -- it is
  **not** a complete record of every tool call. ``sdp-hook-log.ps1`` only writes an entry for a
  tool/direction pair that ``sdp-hook-log-tools.json`` explicitly enables (``logPre``/``logPost``
  true); a tool absent from that config, or configured off for a given direction, produces zero
  entries here even though it fired. Counts in this report describe *logged* activity, not total
  activity.
- *Sessions* are grouped by ``session_id``, which distinguishes concurrent Claude Code windows --
  it is not a proxy for a single workflow action or dispatch. The Gantt timeline's lighter track
  spans the *logged* events for that session in this period, not when the window itself opened or
  closed; the darker overlay marks the sub-span(s) where a distinct ``agent_id`` (a dispatched
  subagent) was active.
- *Subagent* (Totals composition bar) counts entries where ``agent_id`` is present -- set only on
  tool calls made from inside a dispatched subagent, distinguishing that subagent's own calls from
  its parent session's. A session with no darker overlay in the Gantt timeline ran no dispatched
  subagent during this period (or none of its subagent's tool calls were logged per the per-tool
  gating above).
- *Work Item* attribution is best-effort, resolved once per call from ``SDP-Solution.json``'s
  active project and that project's ``state.json`` ``active_work_item`` -- a lookup failure at
  any point in that chain yields ``(none)``, not an error. Do not treat ``(none)`` as evidence no
  work was happening; it means attribution could not be resolved at logging time.
- *Truncated* fields reflect ``sdp-hook-log.ps1``'s per-field character cap (``maxFieldChars`` in
  ``sdp-hook-log-tools.json``'s ``truncation`` block, default 1000) on each individual string leaf
  inside ``tool_input``/``tool_output``/``prompt`` -- a truncated field lost its tail, not its
  identity, and a long field never costs a short sibling field its own content. This is expected
  behavior for large payloads (e.g. a big Bash build log, a subagent dispatch prompt, or a long
  user prompt), not evidence of a problem by itself. Listed by tool name rather than charted, since
  truncation applies to only a minority of tools in practice. If ``debugFullCapture`` was ``true``
  for part of the period covered, expect a visible drop in truncation counts during that window --
  not a data gap.
- *Prompts per session* covers ``UserPromptSubmit`` events only -- fires once per human-submitted
  turn in the top-level session, confirmed against the Claude Code hooks reference to never fire
  for subagent dispatch, so every prompt counted here is main-session activity by construction, not
  a filtered subset. These events carry no ``tool_name`` and are excluded from the Tool Usage
  section above for that reason (they were never tool calls) -- ``totals.promptSubmitCount`` is
  their only presence in the Totals section. The prompt ruler uses the same light-track-per-session
  lane as the Sessions timeline, but marks each prompt as a point (a circle), not a span, since a
  prompt submission has no duration the way a subagent dispatch does.
- Bar/row color in every chart in this report is fixed by category identity (or muted gray for
  "(none)"), never by rank -- sorting rows by count for visual ranking never changes what a color
  means.
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
    totals = $totals
    prePostBarSvg = $prePostBarSvg
    prePostLegendHtml = $prePostLegendHtml
    subagentMainBarSvg = $subagentMainBarSvg
    subagentMainLegendHtml = $subagentMainLegendHtml
    levelBreakdown = $levelBreakdown
    levelChartSvg = $levelChartSvg
    toolUsage = $toolUsage
    toolUsageChartSvg = $toolUsageChartSvg
    toolUsageLegendHtml = $toolUsageLegendHtml
    truncationNote = $truncationNote
    sessions = $sessions
    sessionGanttSvg = $sessionGanttSvg
    promptsPerSession = $promptsPerSession
    promptsPerSessionChartSvg = $promptsPerSessionChartSvg
    promptTimelineSvg = $promptTimelineSvg
    workItemBreakdown = $workItemBreakdown
    workItemChartSvg = $workItemChartSvg
    methodologyMarkdown = $methodologyMarkdown
    anomalies = @{
        unparseableLineCount = $unparseableLineCount
    }
}
exit 0
