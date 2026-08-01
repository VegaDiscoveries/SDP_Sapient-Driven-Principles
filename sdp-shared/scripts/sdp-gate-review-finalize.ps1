<#
.SYNOPSIS
    Deterministic backend for sdp-project-gate-review Steps 9-10 (Update State, Session End): applies
    the LLM's gate verdict (passed as an explicit structured argument - the script never infers
    it) to [workspaceRoot]/.sdp-workflow/state.json, plays the gate.blocked tone on a blocked
    verdict, and returns the fully-templated user-facing report.

.PARAMETER workspaceRoot
    Path to the active project root ([resolved_project]). Required from the caller.

.PARAMETER Verdict
    "GATE_PASSED" or "GATE_BLOCKED" - the LLM's Step 8 verdict. Required.

.PARAMETER IssueCount
    Number of issues found. Only used in the GATE_BLOCKED user-facing message; ignored for
    GATE_PASSED.

.PARAMETER Phase
    The current phase identifier (e.g. "phase-3"), used only for the user-facing message. If
    omitted, the script's own re-read of state.json's current_phase is used instead.

.NOTES
    Reads:  [workspaceRoot]/.sdp-workflow/state.json
    Writes: [workspaceRoot]/.sdp-workflow/state.json (phase_gate.status,
      phase_gate.gate_eval_cycles, updated)
    Side effect: on GATE_BLOCKED, invokes sdp-tone.ps1 -trigger "gate.blocked" as a child
      process (non-blocking - any failure is swallowed; tone must never block a workflow).
    Side effect: on both GATE_PASSED and GATE_BLOCKED, invokes sdp-workflow-log.ps1 (also
      non-blocking) to record the verdict in the semantic workflow-log stream - the reason
      string points to the phase document's Gate Verdict blockquote rather than duplicating it,
      since that blockquote is the authoritative full assessment.
    Stdout: single-line JSON result object - contract documented in this script's calling
      skill, sdp-shared/ai-skills/sdp-project-gate-review/SKILL.md (Steps 9-10).
    Exit codes: 0 = success; 1 = error (missing/unparseable state.json, invalid -Verdict, or
      the state write itself failed).
#>

param(
    [string]$workspaceRoot = "",
    [string]$Verdict = "",
    [int]$IssueCount = 0,
    [string]$Phase = ""
)

if (-not $workspaceRoot) {
    $workspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

function Write-Result([hashtable]$hash) {
    Write-Output ($hash | ConvertTo-Json -Compress -Depth 6)
}

function Exit-Error([string]$msg) {
    $r = [ordered]@{
        status              = "error"
        error               = $msg
        gate_eval_cycles_new = $null
        phase_gate_status   = $null
        updated             = $null
        user_report         = $null
    }
    Write-Result $r
    exit 1
}

function Set-JsonFileWithRetry($obj, [string]$path, [int]$depth) {
    $json = $obj | ConvertTo-Json -Depth $depth
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Set-Content -Path $path -Value $json -Encoding UTF8
            return $true
        } catch {
            if ($attempt -eq 3) { return $false }
            Start-Sleep -Milliseconds (150 * $attempt)
        }
    }
    return $false
}

if ($Verdict -ne "GATE_PASSED" -and $Verdict -ne "GATE_BLOCKED") {
    Exit-Error "Finalize requires -Verdict of GATE_PASSED or GATE_BLOCKED - got '$Verdict'."
}

$statePath = Join-Path $workspaceRoot ".sdp-workflow/state.json"
if (-not (Test-Path $statePath)) {
    Exit-Error "[workspaceRoot]/.sdp-workflow/state.json not found. Project workflow state has not been initialized - run project setup to create it."
}

try {
    $state = Get-Content $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    Exit-Error "Failed to parse .sdp-workflow/state.json: $($_.Exception.Message)"
}

$currentPhase = if ($Phase) { $Phase } elseif ($state.current_phase) { "$($state.current_phase)" } else { "unknown-phase" }

$phaseGate = if ($state.PSObject.Properties['phase_gate'] -and $state.phase_gate) { $state.phase_gate } else { [ordered]@{ status = "pending"; gate_eval_cycles = 0 } }
$priorCycles = if ($phaseGate.PSObject.Properties['gate_eval_cycles'] -and $phaseGate.gate_eval_cycles) { [int]$phaseGate.gate_eval_cycles } else { 0 }
$newCycles = $priorCycles + 1

$newStatus = if ($Verdict -eq "GATE_PASSED") { "passed" } else { "blocked" }

$phaseGate | Add-Member -NotePropertyName status -NotePropertyValue $newStatus -Force
$phaseGate | Add-Member -NotePropertyName gate_eval_cycles -NotePropertyValue $newCycles -Force

$todayIso = Get-Date -Format "yyyy-MM-dd"
$state | Add-Member -NotePropertyName phase_gate -NotePropertyValue $phaseGate -Force
$state | Add-Member -NotePropertyName updated -NotePropertyValue $todayIso -Force

$written = Set-JsonFileWithRetry $state $statePath 10
if (-not $written) {
    Exit-Error "Failed to persist phase_gate update to .sdp-workflow/state.json. Verify the file manually before retrying."
}

if ($Verdict -eq "GATE_BLOCKED") {
    try {
        $tonePath = Join-Path $PSScriptRoot "sdp-tone.ps1"
        if (Test-Path $tonePath) {
            & $tonePath -trigger "gate.blocked" | Out-Null
        }
    } catch {
        # Tone is a non-blocking notification - swallow any failure.
    }
}

try {
    $workflowLogPath = Join-Path $PSScriptRoot "sdp-workflow-log.ps1"
    if (Test-Path $workflowLogPath) {
        $logReason = if ($Verdict -eq "GATE_PASSED") {
            "Gate passed for phase $currentPhase - see phase document Gate Verdict blockquote for the full assessment."
        } else {
            "Gate blocked for phase $currentPhase - $IssueCount issue(s) found; see phase document Gate Verdict blockquote for the numbered list."
        }
        & $workflowLogPath -trigger "gate.verdict" -role "GATE_REVIEWER" -phase $currentPhase -outcome $Verdict -reason $logReason | Out-Null
    }
} catch {
    # Workflow logging is a non-blocking side effect - swallow any failure.
}

$userReport = if ($Verdict -eq "GATE_PASSED") {
    "Gate verdict: GATE_PASSED - phase $currentPhase passes the gate. phase_gate.status set to passed. Run COORDINATOR to advance to the next phase."
} else {
    "Gate verdict: GATE_BLOCKED - $IssueCount issue(s) found. phase_gate.status set to blocked. Issues must be resolved before re-dispatching GATE_REVIEWER. Run COORDINATOR after issues are resolved."
}

$r = [ordered]@{
    status               = "success"
    error                = $null
    gate_eval_cycles_new = $newCycles
    phase_gate_status    = $newStatus
    updated              = $todayIso
    user_report          = $userReport
}
Write-Result $r
exit 0
