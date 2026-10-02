<#
.SYNOPSIS
    Parse the solution's loop-metrics-*.jsonl files and compute a kind-of-work matrix from each
    fire's own .action field (EXECUTE/GENERATE/REPAIR/STOP/DEFERRED_DISPATCH_IN_FLIGHT, per the
    state-loop action vocabulary already established by sdp-report-log-loop-metrics.ps1), for the
    sdp-report-workflow-analysis report. Deliberately reuses that existing action vocabulary
    rather than inventing a second one for the same data.

.PARAMETER workspaceRoot
    Path to the solution root. Defaults to two levels above this script
    (sdp-shared/scripts/), matching the sdp-tone.ps1 convention.

.PARAMETER StartDate
    Inclusive range start (yyyy-MM-dd), matched against each file's date suffix. Omit together
    with -EndDate to process every loop-metrics-*.jsonl file found.

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
    [string]$EndDate = ""
)

function Write-Result([hashtable]$hash) {
    Write-Output ($hash | ConvertTo-Json -Compress -Depth 12)
}

if (-not $workspaceRoot) {
    $workspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

$actionDescriptions = @{
    "EXECUTE" = "Dispatched a subagent to execute the current sentinel prompt"
    "GENERATE" = "Regenerated a stale dispatch prompt"
    "GATE_REPAIR" = "Ran a bounded mechanical fix-and-verify cycle ahead of a gate review"
    "STOP" = "Fire stopped without dispatch (halt, block, or no active item)"
    "DEFERRED_DISPATCH_IN_FLIGHT" = "Deferred because a prior subagent was still running"
    "RESPAWN" = "Respawned the session after its subagent-spawn budget was reached"
    "SKIPPED_FOR_RESPAWN" = "Fire skipped while a respawn handoff was pending"
}

$logDir = Join-Path $workspaceRoot ".sdp-solution-workflow/logging/loop-logs"
if (-not (Test-Path $logDir)) {
    Write-Result @{ status = "success"; filesProcessed = @(); totalEntries = 0; unparseableLineCount = 0; actionCounts = @{}; workKindMatrix = @(); toneOnlyEntries = 0; anomalies = @{ logDirMissing = $true } }
    exit 0
}

$allFiles = Get-ChildItem -Path $logDir -Filter "loop-metrics-*.jsonl" -File -ErrorAction SilentlyContinue
$files = @()
foreach ($f in $allFiles) {
    $m = [regex]::Match($f.Name, 'loop-metrics-(\d{8})\.jsonl')
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
$actionCounts = @{}
$toneOnlyEntries = 0

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
            $action = [string]$entry.action
            if (-not $action) {
                $toneOnlyEntries++
                continue
            }
            if ($actionCounts.ContainsKey($action)) { $actionCounts[$action] = $actionCounts[$action] + 1 } else { $actionCounts[$action] = 1 }
        }
    } finally {
        $reader.Close()
    }
}

$workKindMatrix = @()
foreach ($action in $actionCounts.Keys) {
    $desc = $actionDescriptions[$action]
    if (-not $desc) { $desc = "Unclassified action value not in the known state-loop vocabulary" }
    $workKindMatrix += @{ action = $action; description = $desc; count = $actionCounts[$action] }
}

$result = @{
    status = "success"
    filesProcessed = @($files | ForEach-Object { $_.Name })
    totalEntries = $totalEntries
    unparseableLineCount = $unparseableLineCount
    actionCounts = $actionCounts
    workKindMatrix = $workKindMatrix
    toneOnlyEntries = $toneOnlyEntries
    anomalies = @{ logDirMissing = $false }
}

Write-Result $result
exit 0
