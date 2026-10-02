<#
.SYNOPSIS
    Stream-parse the solution's hook-log-*.jsonl files (never loading raw lines into agent
    context) and compute entries-per-session, tool-type breakdowns, and action counts per
    session, for the sdp-report-workflow-analysis report.

.PARAMETER workspaceRoot
    Path to the solution root. Defaults to two levels above this script
    (sdp-shared/scripts/), matching the sdp-tone.ps1 convention.

.PARAMETER StartDate
    Inclusive range start (yyyy-MM-dd), matched against each file's date suffix. Omit together
    with -EndDate to process every hook-log-*.jsonl file found.

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

$logDir = Join-Path $workspaceRoot ".sdp-solution-workflow/logging/hook-logs"
if (-not (Test-Path $logDir)) {
    Write-Result @{ status = "success"; filesProcessed = @(); totalEntries = 0; unparseableLineCount = 0; bySession = @(); toolTotals = @{}; levelTotals = @{}; anomalies = @{ logDirMissing = $true } }
    exit 0
}

$allFiles = Get-ChildItem -Path $logDir -Filter "hook-log-*.jsonl" -File -ErrorAction SilentlyContinue
$files = @()
foreach ($f in $allFiles) {
    $m = [regex]::Match($f.Name, 'hook-log-(\d{8})\.jsonl')
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
$sessionMap = @{}
$toolTotals = @{}
$levelTotals = @{}

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
            $sessionId = [string]$entry.session_id
            if (-not $sessionId) { $sessionId = "(unknown)" }
            if (-not $sessionMap.ContainsKey($sessionId)) {
                $sessionMap[$sessionId] = @{
                    sessionId = $sessionId
                    entryCount = 0
                    subagentEntryCount = 0
                    toolCounts = @{}
                    levelCounts = @{}
                }
            }
            $s = $sessionMap[$sessionId]
            $s.entryCount = $s.entryCount + 1
            if ($entry.agent_id) { $s.subagentEntryCount = $s.subagentEntryCount + 1 }

            $tool = [string]$entry.tool_name
            if (-not $tool) { $tool = "(none)" }
            if ($s.toolCounts.ContainsKey($tool)) { $s.toolCounts[$tool] = $s.toolCounts[$tool] + 1 } else { $s.toolCounts[$tool] = 1 }
            if ($toolTotals.ContainsKey($tool)) { $toolTotals[$tool] = $toolTotals[$tool] + 1 } else { $toolTotals[$tool] = 1 }

            $level = [string]$entry.level
            if (-not $level) { $level = "(none)" }
            if ($s.levelCounts.ContainsKey($level)) { $s.levelCounts[$level] = $s.levelCounts[$level] + 1 } else { $s.levelCounts[$level] = 1 }
            if ($levelTotals.ContainsKey($level)) { $levelTotals[$level] = $levelTotals[$level] + 1 } else { $levelTotals[$level] = 1 }
        }
    } finally {
        $reader.Close()
    }
}

$bySession = @()
foreach ($key in $sessionMap.Keys) { $bySession += $sessionMap[$key] }

$result = @{
    status = "success"
    filesProcessed = @($files | ForEach-Object { $_.Name })
    totalEntries = $totalEntries
    unparseableLineCount = $unparseableLineCount
    bySession = $bySession
    toolTotals = $toolTotals
    levelTotals = $levelTotals
    anomalies = @{ logDirMissing = $false }
}

Write-Result $result
exit 0
