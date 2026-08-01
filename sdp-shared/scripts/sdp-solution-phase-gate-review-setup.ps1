<#
.SYNOPSIS
    Deterministic backend for sdp-solution-phase-gate-review Steps 3-5 (Read Dispatch File, Read
    Workflow State, Read Phase Document): derives and reads the solution-level session dispatch
    file, confirms role and current_phase, reads the phase document, strips any prior Gate
    Verdict blockquotes from the content handed to the LLM's independent assessment, and
    separately surfaces any prior GATE_BLOCKED blockquote(s) for the Step 7 re-gate check.

.NOTES
    Solution-root script — no -workspaceRoot parameter. Always operates on the solution root,
    self-resolved from this script's own location.
    Reads:
      .sdp-solution-workflow/state.json
      .sdp-solution-workflow/sessions/[last_session].md  (dispatch file)
      sdp-solution-docs/[phase document path from dispatch file]
    Writes: nothing to solution files - this script is read-only there. Side effect: on any
      halt, invokes sdp-workflow-log.ps1 (non-blocking) to record the halt.
    Stdout: single-line JSON result object (same shape as sdp-gate-review-setup.ps1's).
    Exit codes: 0 = success or halted; 1 = error (state.json missing/unparseable).
#>

$solutionRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Write-Result([hashtable]$hash) {
    Write-Output ($hash | ConvertTo-Json -Compress -Depth 8)
}

function New-ResultBase {
    return [ordered]@{
        status                       = "success"
        error                        = $null
        halt_message                 = $null
        session_id                   = $null
        role_confirmed               = $null
        current_phase                = $null
        phase_gate_status            = $null
        gate_eval_cycles             = $null
        phase_document_path          = $null
        is_regate_cycle              = $null
        regate_trigger_reason        = $null
        phase_document_content       = $null
        prior_gate_blocked_blockquotes = @()
    }
}

function Exit-Error([string]$msg) {
    $r = New-ResultBase
    $r.status = "error"
    $r.error = $msg
    Write-Result $r
    exit 1
}

function Exit-Halted([string]$msg) {
    try {
        $workflowLogPath = Join-Path $PSScriptRoot "sdp-workflow-log.ps1"
        if (Test-Path $workflowLogPath) {
            & $workflowLogPath -trigger "gate_review.setup_halt" -role "GATE_REVIEWER" -outcome "halted" -reason $msg | Out-Null
        }
    } catch {
        # Workflow logging is a non-blocking side effect - swallow any failure.
    }
    $r = New-ResultBase
    $r.status = "halted"
    $r.halt_message = $msg
    Write-Result $r
    exit 0
}

function Get-Field([string]$content, [string]$name) {
    $escaped = [regex]::Escape($name)
    $m = [regex]::Match($content, "(?m)^\s*$escaped\s*:\s*(.+?)\s*`$")
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

function Get-GateVerdictBlocks([string]$content) {
    $lines = $content -split "`r`n|`n"
    $blocks = @()
    $i = 0
    while ($i -lt $lines.Count) {
        if ($lines[$i] -match '^>\s*\*\*Gate Verdict\s*[-—]\s*(GATE_PASSED|GATE_BLOCKED)\s*[-—]') {
            $verdict = $Matches[1]
            $start = $i
            $j = $i
            while ($j -lt $lines.Count -and $lines[$j] -match '^>') { $j++ }
            $blockLines = $lines[$start..($j - 1)]
            $blocks += [ordered]@{ verdict = $verdict; start = $start; end = ($j - 1); text = ($blockLines -join "`n") }
            $i = $j
        } else {
            $i++
        }
    }
    return @($blocks)
}

# ---------------------------------------------------------------------------
# Step 4.1: Read state.json
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

$currentPhase   = $state.current_phase
$lastSessionRaw = $state.last_session

# ---------------------------------------------------------------------------
# Step 3.1: Derive and read the dispatch file
# ---------------------------------------------------------------------------

if (-not $lastSessionRaw) {
    Exit-Halted "No last_session recorded in .sdp-solution-workflow/state.json - there is no dispatch file to confirm a GATE_REVIEWER session against."
}

# last_session is stored as a raw integer in state.json (matching every other script that reads
# it, e.g. sdp-solution-create-prompt.ps1) - format to the zero-padded "session-NNN" convention
# dispatch files actually use before building any path or output field from it.
$lastSession = "session-{0:D3}" -f [int]$lastSessionRaw

$dispatchPath = Join-Path $solutionRoot ".sdp-solution-workflow/sessions/$lastSession.md"
if (-not (Test-Path $dispatchPath)) {
    Exit-Halted "Dispatch file '.sdp-solution-workflow/sessions/$lastSession.md' not found. Cannot confirm this is a GATE_REVIEWER session."
}

try {
    $dispatchContent = [string](Get-Content $dispatchPath -Raw -Encoding UTF8)
} catch {
    Exit-Halted "Dispatch file '.sdp-solution-workflow/sessions/$lastSession.md' could not be read: $($_.Exception.Message)"
}

# ---------------------------------------------------------------------------
# Step 3.2: Confirm role assignment is GATE_REVIEWER
# ---------------------------------------------------------------------------

$role = Get-Field $dispatchContent "Role"
if ($role -ne "GATE_REVIEWER") {
    $roleDisplay = if ($role) { $role } else { "(no Role field found)" }
    Exit-Halted "Role mismatch - dispatch file assigns '$roleDisplay', not GATE_REVIEWER. Session cannot continue."
}

# ---------------------------------------------------------------------------
# Step 3.3: Note phase document path; Step 3.4: note re-gate trigger reason
# ---------------------------------------------------------------------------

$workItem = Get-Field $dispatchContent "Work Item"
$phaseDocField = Get-Field $dispatchContent "Phase Document"
if (-not $phaseDocField) {
    Exit-Halted "Dispatch file '.sdp-solution-workflow/sessions/$lastSession.md' has no 'Phase Document:' field. Cannot locate the phase document to review."
}

$regateTriggerReason = Get-Field $dispatchContent "Re-Gate Trigger"

# Phase document paths here are always relative to the solution root - no per-project prefix
# stripping is needed (that concern is sdp-gate-review-setup.ps1's, for the project-scoped case).
$phaseDocRelToSolution = $phaseDocField -replace '\\', '/'

# ---------------------------------------------------------------------------
# Step 4.2: Confirm current_phase matches the phase identifier in the dispatch file
# ---------------------------------------------------------------------------

if ($workItem -and $currentPhase -and ($workItem -ne $currentPhase)) {
    Exit-Halted "current_phase in .sdp-solution-workflow/state.json ('$currentPhase') does not match the dispatch file's Work Item ('$workItem'). State may be out of sync - verify both before proceeding."
}

# ---------------------------------------------------------------------------
# Step 4.3 / 4.4: Note phase_gate.status and gate_eval_cycles
# ---------------------------------------------------------------------------

$phaseGate = if ($state.PSObject.Properties['phase_gate']) { $state.phase_gate } else { $null }
$phaseGateStatus = if ($phaseGate -and $phaseGate.PSObject.Properties['status'] -and $phaseGate.status) { "$($phaseGate.status)" } else { "pending" }
$gateEvalCycles  = if ($phaseGate -and $phaseGate.PSObject.Properties['gate_eval_cycles']) { [int]$phaseGate.gate_eval_cycles } else { 0 }
$isRegateCycle   = ($phaseGateStatus -eq "blocked")

# ---------------------------------------------------------------------------
# Step 5: Read phase document; strip Gate Verdict blockquotes; surface prior
# GATE_BLOCKED blockquote(s) for the Step 7 re-gate check
# ---------------------------------------------------------------------------

$phaseDocFullPath = Join-Path $solutionRoot $phaseDocRelToSolution
if (-not (Test-Path $phaseDocFullPath)) {
    Exit-Halted "Phase document '$phaseDocRelToSolution' not found. Cannot perform the gate review."
}

try {
    $phaseDocContent = [string](Get-Content $phaseDocFullPath -Raw -Encoding UTF8)
} catch {
    Exit-Halted "Phase document '$phaseDocRelToSolution' could not be read: $($_.Exception.Message)"
}

$blocks = Get-GateVerdictBlocks $phaseDocContent
$priorBlocked = @($blocks | Where-Object { $_.verdict -eq "GATE_BLOCKED" } | ForEach-Object { $_.text })

if ($blocks.Count -gt 0) {
    $stripIndex = @{}
    foreach ($b in $blocks) { for ($k = $b.start; $k -le $b.end; $k++) { $stripIndex[$k] = $true } }
    $lines = $phaseDocContent -split "`r`n|`n"
    $keptLines = for ($k = 0; $k -lt $lines.Count; $k++) { if (-not $stripIndex.ContainsKey($k)) { $lines[$k] } }
    $strippedContent = ($keptLines -join "`n")
} else {
    $strippedContent = $phaseDocContent
}

# ---------------------------------------------------------------------------
# Output result
# ---------------------------------------------------------------------------

$r = New-ResultBase
$r.status                       = "success"
$r.session_id                   = $lastSession
$r.role_confirmed                = $true
$r.current_phase                = $currentPhase
$r.phase_gate_status             = $phaseGateStatus
$r.gate_eval_cycles              = $gateEvalCycles
$r.phase_document_path           = $phaseDocRelToSolution
$r.is_regate_cycle               = $isRegateCycle
$r.regate_trigger_reason         = $regateTriggerReason
$r.phase_document_content        = $strippedContent
$r.prior_gate_blocked_blockquotes = $priorBlocked
Write-Result $r
exit 0
