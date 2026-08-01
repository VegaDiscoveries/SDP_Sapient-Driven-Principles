<#
.SYNOPSIS
    Deterministic backend for the sdp-solution-create-prompt skill Steps 1-2: read
    SDP-Solution.json and .sdp-solution-workflow/state.json, extract solution_name, and either
    the shared-cross-project-task fields (active_solution_task, task_status) or, when no shared
    task is active, the phases-1-7 fields (current_phase, phase_gate) - plus last_session and
    workflow_status either way. The LLM takes over at Step 2 (confirming role/projects from the
    invoking coordinator's conversation context, which is not file-accessible) to build the
    sentinel and write sdp-solution-docs/00_solution_prompt.txt.

.NOTES
    Reads:
      SDP-Solution.json
      .sdp-solution-workflow/state.json
    Writes: nothing - this script is read-only.
    Stdout: single-line JSON result object - contract documented in this script's calling
      skill, sdp-shared/ai-skills/sdp-solution-create-prompt/SKILL.md; the phases-1-7 branch
      adds mode/current_phase/phase_gate_status/gate_eval_cycles fields alongside the existing
      ones, rather than replacing the contract.
    Exit codes: 0 = success; 1 = error (missing file, no matching task entry for a set
      active_solution_task, or both active_solution_task and current_phase absent - nothing to
      dispatch). Risk tier is Recoverable per the eval - on error the calling skill falls back to
      reading both files manually with the Read tool.
#>

$solutionRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Write-Result([hashtable]$hash) {
    Write-Output ($hash | ConvertTo-Json -Compress -Depth 6)
}

function Exit-Error([string]$msg) {
    $r = [ordered]@{
        status                = "error"
        error                 = $msg
        mode                  = $null
        solution_name         = $null
        active_solution_task  = $null
        task_status           = $null
        current_phase         = $null
        phase_gate_status     = $null
        gate_eval_cycles      = $null
        last_session          = $null
        workflow_status       = $null
    }
    Write-Result $r
    exit 1
}

# ---------------------------------------------------------------------------
# Step 1: Read SDP-Solution.json
# ---------------------------------------------------------------------------

$sdpSolutionPath = Join-Path $solutionRoot "SDP-Solution.json"
if (-not (Test-Path $sdpSolutionPath)) {
    Exit-Error "SDP-Solution.json not found at solution root. Run the sdp-workspace-setup skill to create it before proceeding."
}

try {
    $sdpSolution = Get-Content $sdpSolutionPath -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    Exit-Error "Failed to parse SDP-Solution.json: $($_.Exception.Message)"
}

$solutionName       = $sdpSolution.solution_name
$activeSolutionTask = $sdpSolution.active_solution_task

# ---------------------------------------------------------------------------
# Step 2: Read .sdp-solution-workflow/state.json
# ---------------------------------------------------------------------------

$statePath = Join-Path $solutionRoot ".sdp-solution-workflow/state.json"
if (-not (Test-Path $statePath)) {
    Exit-Error ".sdp-solution-workflow/state.json not found. Solution workflow state has not been initialized - run solution setup to create it."
}

try {
    $state = Get-Content $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    Exit-Error "Failed to parse .sdp-solution-workflow/state.json: $($_.Exception.Message)"
}

$lastSessionInt = if ($state.PSObject.Properties['last_session'] -and $state.last_session) { [int]$state.last_session } else { 0 }
$lastSessionStr = if ($lastSessionInt -gt 0) { "session-{0:D3}" -f $lastSessionInt } else { $null }

$workflowStatus = if ($state.PSObject.Properties['workflow_status'] -and $state.workflow_status) { $state.workflow_status } else { "active" }

# ---------------------------------------------------------------------------
# Step 2a: Branch on which dispatch mode applies - shared cross-project task,
# or phases 1-7 (mutually exclusive; active_solution_task is checked first
# since it is the more specific, longer-established case)
# ---------------------------------------------------------------------------

if ($activeSolutionTask) {
    $taskEntry = @($state.tasks) | Where-Object { $_.id -eq $activeSolutionTask } | Select-Object -First 1
    if (-not $taskEntry) {
        Exit-Error "No task entry for '$activeSolutionTask' found in .sdp-solution-workflow/state.json. State file may be out of sync with SDP-Solution.json - verify both files."
    }

    $r = [ordered]@{
        status                = "success"
        error                 = $null
        mode                  = "shared_task"
        solution_name         = $solutionName
        active_solution_task  = $activeSolutionTask
        task_status           = $taskEntry.status
        current_phase         = $null
        phase_gate_status     = $null
        gate_eval_cycles      = $null
        last_session          = $lastSessionStr
        workflow_status       = $workflowStatus
    }
    Write-Result $r
    exit 0
}

$currentPhase = $state.current_phase
if (-not $currentPhase) {
    Exit-Error "SDP-Solution.json has no active_solution_task and .sdp-solution-workflow/state.json has no current_phase - nothing to dispatch. sdp-solution-coordinator must set one of the two before sdp-solution-create-prompt can write the prompt."
}

$phaseGate = if ($state.PSObject.Properties['phase_gate']) { $state.phase_gate } else { $null }
$phaseGateStatus = if ($phaseGate -and $phaseGate.PSObject.Properties['status'] -and $phaseGate.status) { "$($phaseGate.status)" } else { "pending" }
$gateEvalCycles  = if ($phaseGate -and $phaseGate.PSObject.Properties['gate_eval_cycles']) { [int]$phaseGate.gate_eval_cycles } else { 0 }

# ---------------------------------------------------------------------------
# Output result
# ---------------------------------------------------------------------------

$r = [ordered]@{
    status                = "success"
    error                 = $null
    mode                  = "phases_1_7"
    solution_name         = $solutionName
    active_solution_task  = $null
    task_status           = $null
    current_phase         = $currentPhase
    phase_gate_status     = $phaseGateStatus
    gate_eval_cycles      = $gateEvalCycles
    last_session          = $lastSessionStr
    workflow_status       = $workflowStatus
}
Write-Result $r
exit 0
