<#
.SYNOPSIS
    Concatenate a date range's worth of one source log type's per-calendar-day jsonl files
    (loop-metrics-*.jsonl, hook-log-*.jsonl, workflow-log-*.jsonl, or combined-log-*.jsonl) into a
    single multi-day jsonl file under .sdp-solution-workflow/logging/range-merges/. Every one of
    the four report scripts (sdp-report-log-loop-metrics.ps1, sdp-report-log-hook-metrics.ps1,
    sdp-report-log-workflow-metrics.ps1, sdp-report-log-combined-metrics.ps1) already reads
    whatever file it is handed via -JsonlPath and filters by the timestamp embedded in each line,
    not the filename -- this script exists only to produce that one file. No re-parsing or
    re-sorting is done: each day's source file is already internally chronological and
    non-overlapping with its neighbors, so plain concatenation in ascending date order preserves
    overall chronological order.

.PARAMETER SourceType
    Which of the four source families to merge: "loop-metrics" | "hook-log" | "workflow-log" |
    "combined-log". Determines both the source folder and filename prefix -- the caller does not
    name folders directly.

.PARAMETER StartDate
    Inclusive range start (yyyy-MM-dd).

.PARAMETER EndDate
    Inclusive range end (yyyy-MM-dd).

.PARAMETER OutputPath
    Optional. Defaults to
    .sdp-solution-workflow/logging/range-merges/[prefix]-[startStamp]_to_[endStamp].jsonl at the
    solution root.

.NOTES
    Stdout: single-line JSON result object (agent-consumed script per SDP-Script-Authoring.md).
    Exit codes: 0 = success (status may still be "error" inside the JSON for a handled condition);
    1 reserved for an operational failure that prevented any JSON from being written at all.

    A calendar day within the range with no source file for that day contributes zero lines and is
    listed in `datesMissing`, not treated as an error -- mirrors sdp-report-logs-combine.ps1's own
    "a missing source is a normal, expected state" rule. Only a range with zero files found across
    every day is an error (nothing to merge).

    Output is a full overwrite (regenerable derived artifact keyed by source type + range), not an
    append-only log -- re-running for the same range recomputes cleanly.
#>
param(
    [string]$SourceType = "",
    [string]$StartDate = "",
    [string]$EndDate = "",
    [string]$OutputPath = ""
)

function Write-Result([hashtable]$hash) {
    Write-Output ($hash | ConvertTo-Json -Compress -Depth 8)
}

$workspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

$sourceMap = @{
    "loop-metrics"  = @{ dir = ".sdp-solution-workflow/logging/loop-logs";     prefix = "loop-metrics" }
    "hook-log"      = @{ dir = ".sdp-solution-workflow/logging/hook-logs";     prefix = "hook-log" }
    "workflow-log"  = @{ dir = ".sdp-solution-workflow/logging/workflow-logs"; prefix = "workflow-log" }
    "combined-log"  = @{ dir = ".sdp-solution-workflow/logging/combined-logs"; prefix = "combined-log" }
}

if (-not $sourceMap.ContainsKey($SourceType)) {
    Write-Result @{ status = "error"; error = "invalid -SourceType '$SourceType' (expected one of: loop-metrics, hook-log, workflow-log, combined-log)" }
    exit 0
}

try {
    $parsedStart = ([datetime]::Parse($StartDate)).Date
    $parsedEnd = ([datetime]::Parse($EndDate)).Date
} catch {
    Write-Result @{ status = "error"; error = "invalid -StartDate/-EndDate value (expected yyyy-MM-dd)" }
    exit 0
}

if ($parsedEnd -lt $parsedStart) {
    Write-Result @{ status = "error"; error = "-EndDate ($EndDate) is before -StartDate ($StartDate)" }
    exit 0
}

$sourceDir = Join-Path $workspaceRoot $sourceMap[$SourceType].dir
$prefix = $sourceMap[$SourceType].prefix
$startStamp = $parsedStart.ToString("yyyyMMdd")
$endStamp = $parsedEnd.ToString("yyyyMMdd")

if (-not $OutputPath) {
    $outDir = Join-Path $workspaceRoot ".sdp-solution-workflow/logging/range-merges"
    $OutputPath = Join-Path $outDir "$prefix-${startStamp}_to_$endStamp.jsonl"
} else {
    $outDir = Split-Path -Parent $OutputPath
}

$filesFound = @()
$datesMissing = @()
$allLines = @()

$cursor = $parsedStart
while ($cursor -le $parsedEnd) {
    $stamp = $cursor.ToString("yyyyMMdd")
    $dayPath = Join-Path $sourceDir "$prefix-$stamp.jsonl"
    if (Test-Path $dayPath) {
        $filesFound += (Split-Path -Leaf $dayPath)
        $dayLines = Get-Content $dayPath -Encoding UTF8 | Where-Object { $_ -and $_.Trim() -ne "" }
        $allLines += $dayLines
    } else {
        $datesMissing += $cursor.ToString("yyyy-MM-dd")
    }
    $cursor = $cursor.AddDays(1)
}

if ($filesFound.Count -eq 0) {
    Write-Result @{ status = "error"; error = "no $prefix-*.jsonl files found for any date between $StartDate and $EndDate under $($sourceMap[$SourceType].dir)" }
    exit 0
}

if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$content = if ($allLines.Count -gt 0) { ($allLines -join "`n") + "`n" } else { "" }
[System.IO.File]::WriteAllText($OutputPath, $content, (New-Object System.Text.UTF8Encoding($false)))

Write-Result @{
    status = "success"
    error = $null
    sourceType = $SourceType
    startDate = $parsedStart.ToString("yyyy-MM-dd")
    endDate = $parsedEnd.ToString("yyyy-MM-dd")
    filesFound = $filesFound
    datesMissing = $datesMissing
    totalEntries = $allLines.Count
    outputPath = $OutputPath
}
exit 0
