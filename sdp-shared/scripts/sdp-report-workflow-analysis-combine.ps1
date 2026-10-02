<#
.SYNOPSIS
    Merge every sdp-report-workflow-analysis stage JSON into one enveloped combined JSON file,
    embedding compact sections in full and summarizing bulky per-session/per-day detail --
    keeping the combined file itself a reasonable size for the cross-solution combination Prompt
    #1's "Additional Reporting" step names as the point of producing JSON at all.

.PARAMETER InventoryJsonPath
    Path to sdp-report-workflow-analysis-inventory.ps1's saved stdout JSON.

.PARAMETER SessionsJsonPath
    Path to sdp-report-workflow-analysis-sessions.ps1's saved stdout JSON.

.PARAMETER HookLogsJsonPath
    Path to sdp-report-workflow-analysis-hooklogs.ps1's saved stdout JSON.

.PARAMETER LoopLogsJsonPath
    Path to sdp-report-workflow-analysis-looplogs.ps1's saved stdout JSON.

.PARAMETER WorkflowLogsJsonPath
    Path to sdp-report-workflow-analysis-workflowlogs.ps1's saved stdout JSON.

.PARAMETER ReconcileJsonPath
    Path to sdp-report-workflow-analysis-reconcile.ps1's saved stdout JSON.

.PARAMETER OutputPath
    Full path (including filename) to write the combined JSON to. The calling skill creates the
    dated output folder before passing this.

.NOTES
    Stdout: single-line JSON result object (agent-consumed script per SDP-Script-Authoring.md).
    Exit codes: 0 = success; 1 reserved for an operational failure that prevented the combined
    file from being written at all.
#>
param(
    [string]$InventoryJsonPath = "",
    [string]$SessionsJsonPath = "",
    [string]$HookLogsJsonPath = "",
    [string]$LoopLogsJsonPath = "",
    [string]$WorkflowLogsJsonPath = "",
    [string]$ReconcileJsonPath = "",
    [string]$OutputPath = ""
)

function Write-Result([hashtable]$hash) {
    Write-Output ($hash | ConvertTo-Json -Compress -Depth 12)
}

function Read-JsonFile([string]$path) {
    if (-not $path -or -not (Test-Path $path)) { return $null }
    try {
        return [string](Get-Content $path -Raw -Encoding UTF8) | ConvertFrom-Json
    } catch {
        return $null
    }
}

if (-not $OutputPath) {
    Write-Result @{ status = "error"; error = "OutputPath is required" }
    exit 0
}

$inventory = Read-JsonFile $InventoryJsonPath
$sessions = Read-JsonFile $SessionsJsonPath
$hookLogs = Read-JsonFile $HookLogsJsonPath
$loopLogs = Read-JsonFile $LoopLogsJsonPath
$workflowLogs = Read-JsonFile $WorkflowLogsJsonPath
$reconcile = Read-JsonFile $ReconcileJsonPath

$solutionName = $null
if ($inventory) { $solutionName = $inventory.solutionName }

$sessionsSummary = $null
if ($sessions) {
    $sessionsSummary = @{
        totalSessions = $sessions.totalSessions
        bySource = $sessions.bySource
        draftCategoryCounts = $sessions.draftCategoryCounts
        anomalies = $sessions.anomalies
    }
}

$hookLogsSummary = $null
if ($hookLogs) {
    $hookLogsSummary = @{
        filesProcessed = $hookLogs.filesProcessed
        totalEntries = $hookLogs.totalEntries
        unparseableLineCount = $hookLogs.unparseableLineCount
        toolTotals = $hookLogs.toolTotals
        levelTotals = $hookLogs.levelTotals
        sessionCount = @($hookLogs.bySession).Count
    }
}

$workflowLogsSummary = $null
if ($workflowLogs) {
    $workflowLogsSummary = @{
        filesProcessed = $workflowLogs.filesProcessed
        totalEntries = $workflowLogs.totalEntries
        unparseableLineCount = $workflowLogs.unparseableLineCount
        triggerCounts = $workflowLogs.triggerCounts
        roleCounts = $workflowLogs.roleCounts
        outcomeCounts = $workflowLogs.outcomeCounts
        concerningEventCount = $workflowLogs.concerningEventCount
        concerningEvents = $workflowLogs.concerningEvents
    }
}

$combined = @{
    schema_version = "1.0"
    solution_name = $solutionName
    generated_at = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssK")
    inventory = $inventory
    sessions_summary = $sessionsSummary
    hook_logs_summary = $hookLogsSummary
    loop_logs = $loopLogs
    workflow_logs_summary = $workflowLogsSummary
    session_classification = $reconcile
    detail_files = @{
        inventory = "01_inventory.json"
        sessions = "02_sessions.json"
        hook_logs = "03_hook_logs.json"
        loop_logs = "04_loop_logs.json"
        workflow_logs = "05_workflow_logs.json"
    }
}

try {
    $json = $combined | ConvertTo-Json -Depth 12
    Set-Content -Path $OutputPath -Value $json -Encoding UTF8
} catch {
    Write-Result @{ status = "error"; error = "failed to write combined JSON: $($_.Exception.Message)" }
    exit 0
}

$fileInfo = Get-Item $OutputPath
Write-Result @{ status = "success"; outputPath = $OutputPath; sizeBytes = $fileInfo.Length }
exit 0
