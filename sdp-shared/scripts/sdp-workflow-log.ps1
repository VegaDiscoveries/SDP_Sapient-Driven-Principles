<#
.SYNOPSIS
    Writes a semantic SDP workflow-event log entry - the narrative/reasoning half of the logging
    system, complementing the mechanical PreToolUse/PostToolUse trail in sdp-hook-log.ps1.

.PARAMETER trigger
    Named workflow event, e.g. "gate.blocked", "halt.no_progress", "worker.diagnosis_blocked".
    Reuses the same trigger vocabulary as SDP-Tones.json's events table where applicable - one
    named-event taxonomy shared by the tone and logging systems. Required; a missing trigger is a
    silent no-op (this is a non-blocking utility, never a workflow error).

.PARAMETER role
    The dispatching role at the moment of this event: COORDINATOR | WORKER | REVIEWER |
    GATE_REVIEWER | STATE_LOOP.

.PARAMETER workItem
    The task-level work item ID this event concerns (e.g. "P5-SVC-03"). Empty for phase-level or
    solution-level events that have no single task attached.

.PARAMETER phase
    The phase this event concerns (e.g. "PHASE-06"). Empty when not applicable.

.PARAMETER outcome
    Short structured outcome token, e.g. "GATE_BLOCKED", "VERIFIED", "REJECTED",
    "DIAGNOSIS_BLOCKED". Empty when the event has no discrete outcome (e.g. a dispatch decision).

.PARAMETER reason
    Free-text narrative - the reasoning a hook can never capture. This is the entire point of
    this script's existence; always pass something meaningful here.

.PARAMETER detail
    Optional additional structured or free-text detail beyond -reason. Empty by default.

.NOTES
    Stdout: nothing. Exit code: always 0. Non-blocking utility - a logging failure must never
    halt or block the actual SDP workflow. Exits silently under every failure condition,
    including a missing -trigger or -reason.

    Writes one JSON line per call to .sdp-solution-workflow/logging/workflow-logs/workflow-log-
    <local yyyyMMdd>.jsonl - a sibling to loop-logs/ and hook-logs/, same one-file-per-local-day
    shape and retention sweep (190 days, matching hook-logs/'s window) on first write of each new
    day.

    Correlation with hook-logs/ (the mechanical tool-call trail) is by work_item, not session_id -
    Claude Code does not expose a generic session ID to an agent-invoked script (confirmed against
    the Claude Code docs before this script was written; only a Remote-Control-gated
    CLAUDE_CODE_BRIDGE_SESSION_ID exists, not a general mechanism). This is sufficient in
    practice: SDP's own Role Separation invariant guarantees a single session performs exactly one
    role for exactly one work item during its lifetime, so work_item is already an adequate join
    key without needing a session identifier.
#>
param(
    [string]$trigger  = "",
    [string]$role     = "",
    [string]$workItem = "",
    [string]$phase    = "",
    [string]$outcome  = "",
    [string]$reason   = "",
    [string]$detail   = ""
)

$retentionDays = 190

if (-not $trigger) { exit 0 }
if (-not $reason)  { exit 0 }

$workspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

$entry = [ordered]@{
    timestamp = (Get-Date).ToString("o")
    trigger   = $trigger
    role      = if ($role)     { $role }     else { $null }
    work_item = if ($workItem) { $workItem } else { $null }
    phase     = if ($phase)    { $phase }    else { $null }
    outcome   = if ($outcome)  { $outcome }  else { $null }
    reason    = $reason
    detail    = if ($detail)   { $detail }   else { $null }
}

$logDir = Join-Path $workspaceRoot ".sdp-solution-workflow/logging/workflow-logs"
$stamp = (Get-Date).ToString("yyyyMMdd")
$logPath = Join-Path $logDir "workflow-log-$stamp.jsonl"

if (-not (Test-Path $logPath)) {
    try {
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        # First write of a new local day - sweep files older than $retentionDays. Runs only here,
        # so every other call pays a single Test-Path and nothing more.
        $cutoff = (Get-Date).AddDays(-$retentionDays)
        Get-ChildItem -Path $logDir -Filter "workflow-log-*.jsonl" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $cutoff } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    } catch { }
}

try {
    $line = ($entry | ConvertTo-Json -Compress -Depth 8)
    # AppendAllText with an explicit no-BOM UTF8Encoding avoids Add-Content's PS 5.1 behavior of
    # writing a BOM on first creation, which would corrupt line 1's JSON parse.
    [System.IO.File]::AppendAllText($logPath, $line + "`n", (New-Object System.Text.UTF8Encoding($false)))
} catch { }

exit 0
