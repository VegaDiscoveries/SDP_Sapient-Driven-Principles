<#
.SYNOPSIS
    Parse the solution's workflow-log-*.jsonl files (the semantic/narrative log -- trigger,
    role, outcome, work item, reason) and compute trigger/role/outcome breakdowns plus a
    Concerning Events list, for the sdp-report-workflow-analysis report. This log source is not
    named in the original Prompt #1 request that this report family is based on -- it is
    included deliberately to close a gap one of the reviewed prior methodologies flagged but did
    not act on (workflow-logs carry the "why" behind a dispatch decision that hook-logs and
    loop-logs cannot).

.PARAMETER workspaceRoot
    Path to the solution root. Defaults to two levels above this script
    (sdp-shared/scripts/), matching the sdp-tone.ps1 convention.

.PARAMETER StartDate
    Inclusive range start (yyyy-MM-dd), matched against each file's date suffix. Omit together
    with -EndDate to process every workflow-log-*.jsonl file found.

.PARAMETER EndDate
    Inclusive range end (yyyy-MM-dd). Used together with -StartDate.

.NOTES
    Stdout: single-line JSON result object (agent-consumed script per SDP-Script-Authoring.md).
    Exit codes: 0 = success or a handled condition reported inside the JSON; 1 reserved for an
    operational failure that prevented any JSON from being written at all.
#>
param(
    [string]$workspaceRoot = "",
    [string]$StartDate = "",
    [string]$EndDate = "",
    [int]$MaxConcerningEvents = 200
)

function Write-Result([hashtable]$hash) {
    Write-Output ($hash | ConvertTo-Json -Compress -Depth 12)
}

if (-not $workspaceRoot) {
    $workspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

$concerningOutcomes = @("DIAGNOSIS_BLOCKED", "GATE_BLOCKED", "REJECTED")

$logDir = Join-Path $workspaceRoot ".sdp-solution-workflow/logging/workflow-logs"
if (-not (Test-Path $logDir)) {
    Write-Result @{ status = "success"; filesProcessed = @(); totalEntries = 0; unparseableLineCount = 0; triggerCounts = @{}; roleCounts = @{}; outcomeCounts = @{}; concerningEventCount = 0; concerningEvents = @(); anomalies = @{ logDirMissing = $true } }
    exit 0
}

$allFiles = Get-ChildItem -Path $logDir -Filter "workflow-log-*.jsonl" -File -ErrorAction SilentlyContinue
$files = @()
foreach ($f in $allFiles) {
    $m = [regex]::Match($f.Name, 'workflow-log-(\d{8})\.jsonl')
    if (-not $m.Success) { continue }
    $fileDate = [datetime]::ParseExact($m.Groups[1].Value, "yyyyMMdd", $null)
    if ($StartDate) {
        $sd = [datetime]::ParseExact($StartDate, "yyyy-MM-dd", $null)
        if ($fileDate -lt $sd) { continue }
    }
    if ($EndDate) {
        $ed = [datetime]::ParseExact($EndDate, "yyyy-MM-dd", $null)
        if ($fileDate -gt $ed) { continue }
    }
    $files += $f
}

$totalEntries = 0
$unparseableLineCount = 0
$triggerCounts = @{}
$roleCounts = @{}
$outcomeCounts = @{}
$concerningEvents = @()

foreach ($f in $files) {
    $reader = [System.IO.StreamReader]::new($f.FullName, [System.Text.Encoding]::UTF8)
    try {
        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $entry = $line | ConvertFrom-Json -ErrorAction Stop
            } catch {
                $unparseableLineCount++
                continue
            }
            $totalEntries++

            $trigger = [string]$entry.trigger
            if (-not $trigger) { $trigger = "(none)" }
            if ($triggerCounts.ContainsKey($trigger)) { $triggerCounts[$trigger] = $triggerCounts[$trigger] + 1 } else { $triggerCounts[$trigger] = 1 }

            $role = [string]$entry.role
            if (-not $role) { $role = "(none)" }
            if ($roleCounts.ContainsKey($role)) { $roleCounts[$role] = $roleCounts[$role] + 1 } else { $roleCounts[$role] = 1 }

            $outcome = [string]$entry.outcome
            if (-not $outcome) { $outcome = "(none)" }
            if ($outcomeCounts.ContainsKey($outcome)) { $outcomeCounts[$outcome] = $outcomeCounts[$outcome] + 1 } else { $outcomeCounts[$outcome] = 1 }

            $isConcerning = ($concerningOutcomes -contains $outcome) -or ($trigger -like "halt.*")
            if ($isConcerning -and $concerningEvents.Count -lt $MaxConcerningEvents) {
                $concerningEvents += @{
                    timestamp = [string]$entry.timestamp
                    trigger = $trigger
                    role = $role
                    workItem = [string]$entry.work_item
                    outcome = $outcome
                    reason = [string]$entry.reason
                }
            }
        }
    } finally {
        $reader.Close()
    }
}

$concerningEventCount = 0
foreach ($outcome in $concerningOutcomes) {
    if ($outcomeCounts.ContainsKey($outcome)) { $concerningEventCount += $outcomeCounts[$outcome] }
}
foreach ($trigger in $triggerCounts.Keys) {
    if ($trigger -like "halt.*") { $concerningEventCount += $triggerCounts[$trigger] }
}

$result = @{
    status = "success"
    filesProcessed = @($files | ForEach-Object { $_.Name })
    totalEntries = $totalEntries
    unparseableLineCount = $unparseableLineCount
    triggerCounts = $triggerCounts
    roleCounts = $roleCounts
    outcomeCounts = $outcomeCounts
    concerningEventCount = $concerningEventCount
    concerningEvents = $concerningEvents
    anomalies = @{ logDirMissing = $false; concerningEventsTruncated = ($concerningEvents.Count -ge $MaxConcerningEvents) }
}

Write-Result $result
exit 0
