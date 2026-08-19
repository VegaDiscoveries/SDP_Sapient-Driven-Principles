<#
.SYNOPSIS
    Deterministic backend for sdp-project-gate-review Steps 3-5 (Read Dispatch File, Read Workflow
    State, Read Phase Document): derives and reads the session dispatch file, confirms role
    and current_phase, reads the phase document, strips any prior Gate Verdict blockquotes
    from the content handed to the LLM's independent assessment (each surviving line prefixed
    with its original line number from the real file, same convention as the Read tool, so
    findings can cite exact lines without opening the raw file), and separately surfaces any
    prior GATE_BLOCKED blockquote(s) for the Step 7 re-gate check.

.PARAMETER workspaceRoot
    Path to the active project root ([resolved_project]). Required from the caller.

.NOTES
    Reads:
      [workspaceRoot]/.sdp-workflow/state.json
      [workspaceRoot]/.sdp-workflow/sessions/[last_session].md  (dispatch file)
      [workspaceRoot]/[phase document path from dispatch file]
    Writes: nothing to project files - this script is read-only there. Side effect: on any
      halt, invokes sdp-workflow-log.ps1 (non-blocking - any failure is swallowed) to record
      the halt in the semantic workflow-log stream.
    Stdout: single-line JSON result object - contract documented in this script's calling
      skill, sdp-shared/ai-skills/sdp-project-gate-review/SKILL.md (Steps 3-5).
    Exit codes: 0 = success or halted (both expected, non-error terminal states the calling
      skill branches on; none of the halted conditions here write state.json - the original
      skill text only invokes the Halt Behavior Contract's state write for the Step 1 GPG
      case, owned by sdp-gate-review-gpg-check.ps1); 1 = error (state.json missing/unparseable
      - an operational failure prior to any session-specific check).
#>

param(
    [string]$workspaceRoot = ""
)

if (-not $workspaceRoot) {
    $workspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

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
        # — (not a literal em-dash character) - a literal non-ASCII character embedded in
        # regex source is silently mis-parsed under Windows PowerShell 5.1 when this file has no
        # UTF-8 BOM (read via the system ANSI codepage, not UTF-8). The \u escape is plain ASCII
        # in the source and is resolved by the .NET regex engine itself, so it is immune to how
        # the file's own bytes get decoded.
        if ($lines[$i] -match '^>\s*\*\*Gate Verdict\s*[-\u2014]\s*(GATE_PASSED|GATE_BLOCKED)\s*[-\u2014]') {
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

$statePath = Join-Path $workspaceRoot ".sdp-workflow/state.json"
if (-not (Test-Path $statePath)) {
    Exit-Error "[workspaceRoot]/.sdp-workflow/state.json not found. Project workflow state has not been initialized - run project setup to create it."
}

try {
    $state = Get-Content $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    Exit-Error "Failed to parse .sdp-workflow/state.json: $($_.Exception.Message)"
}

$currentPhase   = $state.current_phase
$lastSessionRaw = $state.last_session

# ---------------------------------------------------------------------------
# Step 3.1: Derive and read the dispatch file
# ---------------------------------------------------------------------------

if (-not $lastSessionRaw) {
    Exit-Halted "No last_session recorded in .sdp-workflow/state.json - there is no dispatch file to confirm a GATE_REVIEWER session against."
}

# last_session is stored as the "session-NNN" string convention at project scope
# (set by sdp-project-coordinator/SKILL.md Step 6) - use it directly. This differs from
# solution scope, where last_session is a raw integer (sdp-solution-*-setup.ps1 scripts
# correctly cast it) - do not copy that convention here. Handle a raw-integer value
# defensively (older state.json only) by formatting it to the same "session-NNN" convention.
$lastSession = if ($lastSessionRaw -match '^session-\d+$') {
    $lastSessionRaw
} else {
    "session-{0:D3}" -f [int]$lastSessionRaw
}

$dispatchPath = Join-Path $workspaceRoot ".sdp-workflow/sessions/$lastSession.md"
if (-not (Test-Path $dispatchPath)) {
    Exit-Halted "Dispatch file '.sdp-workflow/sessions/$lastSession.md' not found. Cannot confirm this is a GATE_REVIEWER session."
}

try {
    # [string]-cast strips the PSPath/PSProvider note-properties Get-Content attaches to a
    # -Raw result - left on, they drag the whole reflection graph (PSProvider.ImplementingType
    # etc.) into any later ConvertTo-Json call on a value derived from this content, which
    # hangs rather than erroring (observed directly while testing this script).
    $dispatchContent = [string](Get-Content $dispatchPath -Raw -Encoding UTF8)
} catch {
    Exit-Halted "Dispatch file '.sdp-workflow/sessions/$lastSession.md' could not be read: $($_.Exception.Message)"
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
    Exit-Halted "Dispatch file '.sdp-workflow/sessions/$lastSession.md' has no 'Phase Document:' field. Cannot locate the phase document to review."
}

$regateTriggerReason = Get-Field $dispatchContent "Re-Gate Trigger"

# Strip a leading [resolved_project]/ prefix if the dispatch file recorded the path
# relative to the solution root rather than the project root.
$projectFolderName = Split-Path -Leaf $workspaceRoot
$escapedProjectName = [regex]::Escape($projectFolderName)
$phaseDocRelToProject = $phaseDocField -replace '\\', '/'
if ($phaseDocRelToProject -match "^$escapedProjectName/(.+)$") {
    $phaseDocRelToProject = $Matches[1]
}

# ---------------------------------------------------------------------------
# Step 4.2: Confirm current_phase matches the phase identifier in the dispatch file
# ---------------------------------------------------------------------------

if ($workItem -and $currentPhase -and ($workItem -ne $currentPhase)) {
    Exit-Halted "current_phase in state.json ('$currentPhase') does not match the dispatch file's Work Item ('$workItem'). State may be out of sync - verify both before proceeding."
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

$phaseDocFullPath = Join-Path $workspaceRoot $phaseDocRelToProject
if (-not (Test-Path $phaseDocFullPath)) {
    Exit-Halted "Phase document '$phaseDocRelToProject' not found. Cannot perform the gate review."
}

try {
    # [string]-cast for the same reason as $dispatchContent above - this content is put
    # directly into the JSON result (phase_document_content), so the note-property strip is
    # required here, not just defensive.
    $phaseDocContent = [string](Get-Content $phaseDocFullPath -Raw -Encoding UTF8)
} catch {
    Exit-Halted "Phase document '$phaseDocRelToProject' could not be read: $($_.Exception.Message)"
}

$blocks = Get-GateVerdictBlocks $phaseDocContent
$priorBlocked = @($blocks | Where-Object { $_.verdict -eq "GATE_BLOCKED" } | ForEach-Object { $_.text })

# Every surviving line is prefixed with its original 1-indexed line number from the real file
# (same "number, tab, content" convention the Read tool itself uses) so Step 6's independent
# assessment can cite exact lines without ever opening the raw phase document file - the
# instruction it is already required to follow. Gaps in the numbering mark where a stripped
# block used to be; that is expected, not an error. Applied unconditionally (not only when a
# block was actually stripped) so numbering is available on a first gate cycle too.
$stripIndex = @{}
foreach ($b in $blocks) { for ($k = $b.start; $k -le $b.end; $k++) { $stripIndex[$k] = $true } }
$lines = $phaseDocContent -split "`r`n|`n"
$keptLines = for ($k = 0; $k -lt $lines.Count; $k++) { if (-not $stripIndex.ContainsKey($k)) { "{0,6}`t{1}" -f ($k + 1), $lines[$k] } }
$strippedContent = ($keptLines -join "`n")

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
$r.phase_document_path           = $phaseDocRelToProject
$r.is_regate_cycle               = $isRegateCycle
$r.regate_trigger_reason         = $regateTriggerReason
$r.phase_document_content        = $strippedContent
$r.prior_gate_blocked_blockquotes = $priorBlocked
Write-Result $r
exit 0
