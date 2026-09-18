<#
.SYNOPSIS
    Resolve the model tier/id for an SDP dispatch from file-derivable signals only (role, phase,
    task flags, eval-cycle counters, Pros-Cons-Gaps rotation state) - never reads phase-document
    prose. Returns resolved:false when the decision requires reading the task's own text -
    the calling skill applies its own judgment against the tier taxonomy in the roster
    (sdp-shared/scripts/script-support/sdp-subagent-model-roster.json) in that case.

.PARAMETER workspaceRoot
    Path to the caller's active workspace root for this dispatch - the solution root for
    phases-1-7 callers, or .\[resolved_project] for project-level callers. Used only to resolve
    -phaseStateFile. This script also independently resolves the solution root (see .NOTES) for
    the model roster and SDP-Config.json, which are solution-level resources regardless of which
    root is passed here - a mixed-root script, same pattern as sdp-gate-review-gpg-check.ps1.

.PARAMETER role
    Dispatch role for this session: WORKER | REVIEWER | GATE_REVIEWER. Case-insensitive.

.PARAMETER phase
    Current phase name/slug for this dispatch (e.g. "Architecture", "Implementation Overview",
    "Refined Plan", "Phase Readiness", "Concept"). Matched case-insensitively as a substring
    against the known Pros-Cons-Gaps and standard-floor phase names - the caller does not need
    to normalize casing or pass an exact phase-file slug.

.PARAMETER phaseStateFile
    Path to the relevant [phase]_state.json, relative to -workspaceRoot.

.PARAMETER taskId
    Optional. The task ID key within -phaseStateFile's tasks map. Absent for phase-level
    dispatches that have no single task ID.

.NOTES
    Mixed-root script: -workspaceRoot resolves -phaseStateFile only. The model roster
    (sdp-shared/scripts/script-support/sdp-subagent-model-roster.json) and
    prosConsGapsModelDiversity (SDP-Config.json) are solution-level resources never duplicated
    per project, so they are resolved against an independently-derived $solutionRoot
    (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)), never against $workspaceRoot - see
    SDP-Script-Authoring.md's Mixed-root scripts section and sdp-gate-review-gpg-check.ps1's
    standards/ resolution, the reference case for this pattern.

    Read-only: this script never writes phaseStateFile, SDP-Config.json, or any state.json. When
    a Pros-Cons-Gaps rotation resolves a model, the CALLING SKILL (sdp-solution-phase-coordinator)
    is responsible for appending the chosen model's roster id to pros_cons_gaps.cycle_models.
    This split is deliberate, not an oversight: the coordinator's own MODEL EVAL step runs this
    script and then acts on the result, including that append - not this script; and every
    existing SDP script that touches state.json writes only its own narrowly-scoped fact
    (sdp-preflight.ps1 writes only its own preflight timestamps; sdp-gate-review-gpg-check.ps1
    writes workflow_status/halt_reason only on its one designated halt path) rather than
    open-ended bookkeeping on a caller's behalf. Appending to a rotation history array the
    caller owns is exactly that kind of open-ended bookkeeping, so it stays with the coordinator.

    Rule evaluation order (first match wins):
      1. model_tier_override on the task entry - always wins.
      2. role=REVIEWER and phase is Architecture/Implementation Overview - Pros-Cons-Gaps
         rotation (Section 8), gated by SDP-Config.json prosConsGapsModelDiversity.enabled.
         When the gate is off: resolved:false, today's behavior (no phase-floor fallback -
         this is a deliberate full revert, not a partial one).
      3. role=REVIEWER, a task entry exists, and eval_cycle_attempts - eval_cycles >= 1 (a
         re-evaluation in progress) - floors at most_capable.
      4. Task entry carries flag PARTIAL_COMPLIANCE_ESCALATE - floors at most_capable.
      5. role=GATE_REVIEWER - floors at most_capable. Section 7.2 states only that
         least_capable is excluded for this role; this script reads Section 7.5's grouping of
         "GATE_REVIEWER/re-evaluation escalation" as one bracket, together with Recommendation 7
         (gate reviews are the review-of-record for a whole phase - Section 3's asymmetry
         argument applies at full strength), as resolving to the same most_capable floor a
         re-evaluation gets, not merely ruling out the weakest tier. This is a judgment call
         where the source document does not use unambiguous phrasing - flagged here and in the
         implementing session's report so a caller who intended only the weaker
         "not least_capable" floor can override it via model_tier_override.
      6. Phase is Architecture, Implementation Overview, Refined Plan, or Phase Readiness (any
         role not already resolved above) - floors at standard (Section 7.3).
      7. Otherwise - resolved:false; the calling skill applies Section 2's taxonomy to the
         task text already in its own context.
    least_capable is never assigned by this script (Section 4/7.3: nothing SDP dispatches
    should default to least_capable; that tier is reserved for genuinely mechanical,
    complete-spec work identified by reading the task's own text, i.e. fallback territory).
    frontier_escalation is never assigned by this script (reserved for escalation only, per the
    roster's own tier definition and Section 8.2 Option 1).

    Stdout: single-line JSON result object -
      { "status": "success", "resolved": true, "model_id": "...", "tier": "...",
        "reason": "...", "diversityDegraded": true }
      (diversityDegraded is present only when true - omitted otherwise)
      { "status": "success", "resolved": false, "model_id": null, "tier": null, "reason": "..." }
      { "status": "error", "resolved": false, "model_id": null, "tier": null, "reason": null,
        "error": "..." }
    Exit codes: 0 = success (resolved:true or resolved:false are both expected, non-error
    outcomes); 1 = operational error (missing/invalid parameter, missing or unparseable file).
#>

param(
    [string]$workspaceRoot = "",
    [string]$role = "",
    [string]$phase = "",
    [string]$phaseStateFile = "",
    [string]$taskId = ""
)

if (-not $workspaceRoot) {
    $workspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
# Independent - roster and SDP-Config.json are solution-level resources, never per-project.
# Do not derive this from $workspaceRoot; do not assume the two roots coincide.
$solutionRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Write-Result([hashtable]$hash) {
    Write-Output ($hash | ConvertTo-Json -Compress -Depth 6)
}

function Exit-Error([string]$msg) {
    $r = [ordered]@{
        status   = "error"
        resolved = $false
        model_id = $null
        tier     = $null
        reason   = $null
        error    = $msg
    }
    Write-Result $r
    exit 1
}

function Write-Success($resolved, $modelId, $tier, [string]$reason, [bool]$diversityDegraded) {
    $r = [ordered]@{
        status   = "success"
        resolved = [bool]$resolved
        model_id = $modelId
        tier     = $tier
        reason   = $reason
    }
    if ($diversityDegraded) { $r["diversityDegraded"] = $true }
    Write-Result $r
    exit 0
}

# ---------------------------------------------------------------------------
# Parameter validation
# ---------------------------------------------------------------------------

$validRoles = @("WORKER", "REVIEWER", "GATE_REVIEWER")
if ($role) { $role = $role.ToUpperInvariant() }
if (-not $role -or $validRoles -notcontains $role) {
    Exit-Error "Invalid or missing -role '$role' - expected one of: $($validRoles -join ', ')."
}

if (-not $phase) {
    Exit-Error "Missing required -phase parameter."
}

if (-not $phaseStateFile) {
    Exit-Error "Missing required -phaseStateFile parameter."
}

$phaseStateFullPath = Join-Path $workspaceRoot $phaseStateFile
if (-not (Test-Path $phaseStateFullPath)) {
    Exit-Error "Phase state file not found: $phaseStateFullPath"
}

try {
    $phaseStateContent = [string](Get-Content $phaseStateFullPath -Raw -Encoding UTF8)
    $phaseState = $phaseStateContent | ConvertFrom-Json
} catch {
    Exit-Error "Failed to parse phase state file '$phaseStateFile': $($_.Exception.Message)"
}

$rosterPath = Join-Path $solutionRoot "sdp-shared/scripts/script-support/sdp-subagent-model-roster.json"
if (-not (Test-Path $rosterPath)) {
    Exit-Error "Model roster not found: $rosterPath"
}
try {
    $rosterContent = [string](Get-Content $rosterPath -Raw -Encoding UTF8)
    $roster = $rosterContent | ConvertFrom-Json
} catch {
    Exit-Error "Failed to parse model roster '$rosterPath': $($_.Exception.Message)"
}

# prosConsGapsModelDiversity.enabled - default true (Section 10.7's documented default) when
# the config file or the key is absent. A config parse failure falls back to the same default
# rather than halting a read-only advisory script over an unrelated file's syntax error.
$configPath = Join-Path $solutionRoot "SDP-Config.json"
$diversityEnabled = $true
if (Test-Path $configPath) {
    try {
        $configContent = [string](Get-Content $configPath -Raw -Encoding UTF8)
        $config = $configContent | ConvertFrom-Json
        if ($config.PSObject.Properties['prosConsGapsModelDiversity'] -and
            $config.prosConsGapsModelDiversity.PSObject.Properties['enabled']) {
            $diversityEnabled = [bool]$config.prosConsGapsModelDiversity.enabled
        }
    } catch {
        # Fall back to the documented default.
    }
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Get-TaskEntry($phaseStateObj, [string]$id) {
    # Mirrors sdp-create-prompt.ps1's task-entry resolution exactly (array keyed by .id,
    # object keyed by ID under .tasks, or top-level keyed by ID) so this script reads the
    # identical shape rather than inventing a parallel one.
    if (-not $id) { return $null }
    if ($phaseStateObj.tasks -is [array]) {
        return ($phaseStateObj.tasks | Where-Object { $_.id -eq $id } | Select-Object -First 1)
    } elseif ($phaseStateObj.tasks) {
        $prop = $phaseStateObj.tasks.PSObject.Properties[$id]
        if ($prop) { return $prop.Value }
        return $null
    } else {
        $prop = $phaseStateObj.PSObject.Properties[$id]
        if ($prop) { return $prop.Value }
        return $null
    }
}

function Get-FirstModelId($rosterObj, [string]$tierName) {
    $matches = @($rosterObj.models | Where-Object { $_.tier -eq $tierName })
    if ($matches.Count -gt 0) { return $matches[0].id }
    return $null
}

function Resolve-TierOrFallback([string]$tierName, [string]$reasonText) {
    $modelId = Get-FirstModelId $roster $tierName
    if (-not $modelId) {
        Write-Success $false $null $null "Rule matched (would floor at '$tierName') but the roster has no model tagged '$tierName' configured. $reasonText" $false
    }
    Write-Success $true $modelId $tierName $reasonText $false
}

$taskEntry = Get-TaskEntry $phaseState $taskId

$phaseLower = $phase.ToLowerInvariant()
$isPCGPhase = ($phaseLower -match "architecture") -or ($phaseLower -match "overview")
$isStandardFloorPhase = $isPCGPhase -or ($phaseLower -match "refined plan") -or ($phaseLower -match "readiness")

# ---------------------------------------------------------------------------
# Rule 1 - model_tier_override always wins (Section 7.2).
# ---------------------------------------------------------------------------

if ($taskEntry -and $taskEntry.PSObject.Properties['model_tier_override'] -and $taskEntry.model_tier_override) {
    $overrideValue = "$($taskEntry.model_tier_override)"
    $tierMatch = @($roster.tiers | Where-Object { $_.tier -eq $overrideValue })
    $modelMatch = @($roster.models | Where-Object { $_.id -eq $overrideValue })
    if ($modelMatch.Count -gt 0) {
        Write-Success $true $modelMatch[0].id $modelMatch[0].tier "model_tier_override explicit model id '$overrideValue' on task '$taskId'." $false
    } elseif ($tierMatch.Count -gt 0) {
        $overrideModelId = Get-FirstModelId $roster $overrideValue
        if ($overrideModelId) {
            Write-Success $true $overrideModelId $overrideValue "model_tier_override explicit tier '$overrideValue' on task '$taskId'." $false
        }
    }
    # An override value matching neither a known tier nor a roster model id is not applied -
    # falls through to the normal rule evaluation below rather than guessing at caller intent.
}

# ---------------------------------------------------------------------------
# Rule 2 - Pros-Cons-Gaps rotation for Architecture/Implementation Overview REVIEWER
# dispatches (Section 8), gated by prosConsGapsModelDiversity.enabled.
# ---------------------------------------------------------------------------

if ($role -eq "REVIEWER" -and $isPCGPhase) {
    if (-not $diversityEnabled) {
        Write-Success $false $null $null "prosConsGapsModelDiversity.enabled is false - Pros-Cons-Gaps dispatch reverts to today's behavior (no model specified; subagent inherits the dispatching session's model)." $false
    }

    $pcg = $phaseState.pros_cons_gaps
    $cycleModels = @()
    if ($pcg -and $pcg.PSObject.Properties['cycle_models'] -and $pcg.cycle_models) {
        $cycleModels = @($pcg.cycle_models)
    }
    $cycleCount = 0
    if ($pcg -and $pcg.PSObject.Properties['cycle_count']) { $cycleCount = [int]$pcg.cycle_count }
    $cycleTarget = 2
    if ($pcg -and $pcg.PSObject.Properties['cycle_target']) { $cycleTarget = [int]$pcg.cycle_target }

    # Eligible pool: standard-and-above only, roster listing order preserved. Never
    # least_capable (below the diversity floor) or frontier_escalation (reserved - Section 8.2
    # Option 1 explicitly excludes it from this rotation).
    $pool = @($roster.models | Where-Object { $_.tier -eq "standard" -or $_.tier -eq "most_capable" })

    if ($pool.Count -eq 0) {
        Write-Success $false $null $null "No standard-or-above model is configured in the roster - the Pros-Cons-Gaps diversity/floor requirement cannot be met." $true
    }

    # Round-robin over the pool in roster order: index = cycles already recorded mod pool size.
    # Because the pool has one entry per tier, this is exactly "skip tiers already used in
    # cycle_models until the pool is exhausted, then wrap" (Section 8.2 Option 1) without
    # needing a separate used-tier set.
    $degraded = $pool.Count -lt 2
    $index = $cycleModels.Count % $pool.Count
    $chosen = $pool[$index]
    $cycleLabel = $cycleCount + 1
    $reasonText = "pros_cons_gaps rotation, cycle $cycleLabel of $cycleTarget, model '$($chosen.id)' (tier $($chosen.tier))."
    if ($degraded) {
        $reasonText += " Degraded: fewer than 2 standard-or-above models are configured in the roster, so diversity cannot be satisfied this cycle - dispatching the one available eligible model instead of silently claiming diversity was met."
    }
    Write-Success $true $chosen.id $chosen.tier $reasonText $degraded
}

# ---------------------------------------------------------------------------
# Rule 3 - re-evaluation in progress (REVIEWER, eval_cycle_attempts - eval_cycles >= 1)
# floors at most_capable (Section 7.2/Section 4).
# ---------------------------------------------------------------------------

if ($role -eq "REVIEWER" -and $taskEntry) {
    $evalCycles = 0
    if ($taskEntry.PSObject.Properties['eval_cycles']) { $evalCycles = [int]$taskEntry.eval_cycles }
    $evalAttempts = 0
    if ($taskEntry.PSObject.Properties['eval_cycle_attempts']) { $evalAttempts = [int]$taskEntry.eval_cycle_attempts }
    if (($evalAttempts - $evalCycles) -ge 1) {
        Resolve-TierOrFallback "most_capable" "Re-evaluation in progress on task '$taskId' (eval_cycle_attempts $evalAttempts - eval_cycles $evalCycles >= 1) - floors at most_capable."
    }
}

# ---------------------------------------------------------------------------
# Rule 4 - PARTIAL_COMPLIANCE_ESCALATE floors at most_capable (Section 7.2).
# ---------------------------------------------------------------------------

if ($taskEntry -and $taskEntry.PSObject.Properties['flags'] -and $taskEntry.flags -and
    (@($taskEntry.flags) -contains "PARTIAL_COMPLIANCE_ESCALATE")) {
    Resolve-TierOrFallback "most_capable" "Task '$taskId' carries flag PARTIAL_COMPLIANCE_ESCALATE - floors at most_capable."
}

# ---------------------------------------------------------------------------
# Rule 5 - GATE_REVIEWER floors at most_capable. See .NOTES for why this script reads
# Section 7.2's "excludes least_capable" together with Section 7.5/Recommendation 7 as a
# most_capable floor rather than only ruling out the weakest tier.
# ---------------------------------------------------------------------------

if ($role -eq "GATE_REVIEWER") {
    Resolve-TierOrFallback "most_capable" "GATE_REVIEWER is the review-of-record for the whole phase (Section 3's asymmetry argument, Recommendation 7); least_capable is excluded outright per Section 7.2."
}

# ---------------------------------------------------------------------------
# Rule 6 - Architecture, Implementation Overview, Refined Plan, or Phase Readiness phase
# dispatches floor at standard when not already resolved above (Section 7.3).
# ---------------------------------------------------------------------------

if ($isStandardFloorPhase) {
    Resolve-TierOrFallback "standard" "Phase '$phase' floors at standard (Architecture/Implementation Overview/Refined Plan/Phase Readiness dispatches never default below standard - Section 7.3)."
}

# ---------------------------------------------------------------------------
# Rule 7 - no file-derivable rule matched. The calling skill applies Section 2's taxonomy
# to the task text already in its own context (Section 7.3/7.4).
# ---------------------------------------------------------------------------

Write-Success $false $null $null "Ordinary $role task, no phase/flag rule determines tier - task-shape read required." $false
