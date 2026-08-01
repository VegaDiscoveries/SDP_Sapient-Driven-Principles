<#
.SYNOPSIS
    Read SDP workflow state and write a temp file containing all sections for
    sdp-docs/00_prompt.txt. Called by the sdp-project-create-prompt Level 2 skill.

.PARAMETER workspaceRoot
    Path to the workspace root. Defaults to two levels above this script
    (sdp-shared/scripts/), matching the sdp-tone.ps1 convention.

.NOTES
    Writes:
      sdp-docs/00_prompt.txt  (normal path — the next-session dispatch prompt,
                               assembled from the section strings; UTF-8 no BOM so the
                               first-line sentinel stays parseable by sdp-project-state-loop)
      .sdp-workflow/temp/phase-{N}/phase{N}-sdp-create-prompt-{YYYYDDMMHHMM}.json
      .sdp-workflow/temp/sdp-create-prompt-tracking.json
    The halt and error paths do NOT touch sdp-docs/00_prompt.txt.
    Stdout: single-line JSON result object.
    Exit 0 on success or halted workflow; Exit 1 on error.
#>
param(
    [string]$workspaceRoot = ""
)

$solutionRoot    = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$resolvedProject = "."

if (-not $workspaceRoot) {
    $sdpSolutionFile = Join-Path $solutionRoot "SDP-Solution.json"
    if (Test-Path $sdpSolutionFile) {
        try {
            $sdpSolution = Get-Content $sdpSolutionFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $lastActive  = if ($sdpSolution.last_active_projects -and
                               $sdpSolution.last_active_projects.Count -gt 0) {
                $sdpSolution.last_active_projects[0]
            } else { $null }

            if ($lastActive -and $lastActive -ne ".") {
                $workspaceRoot   = Join-Path $solutionRoot $lastActive
                $resolvedProject = $lastActive
            } elseif ($sdpSolution.projects -and $sdpSolution.projects.Count -eq 1) {
                $proj = $sdpSolution.projects[0]
                if ($proj -and $proj -ne ".") {
                    $workspaceRoot   = Join-Path $solutionRoot $proj
                    $resolvedProject = $proj
                } else {
                    $workspaceRoot   = $solutionRoot
                    $resolvedProject = "."
                }
            } elseif ($sdpSolution.projects -and $sdpSolution.projects.Count -gt 1) {
                Write-Output (@{
                    status          = "error"
                    resolvedProject = $null
                    tempFile        = $null
                    error           = "SDP-Solution.json last_active_projects is empty and multiple projects are registered: $($sdpSolution.projects -join ', '). Set last_active_projects in SDP-Solution.json and retry, or pass -workspaceRoot explicitly."
                } | ConvertTo-Json -Compress)
                exit 1
            } else {
                $workspaceRoot   = $solutionRoot
                $resolvedProject = "."
            }
        } catch {
            $workspaceRoot   = $solutionRoot
            $resolvedProject = "."
        }
    } else {
        $workspaceRoot   = $solutionRoot
        $resolvedProject = "."
    }
} else {
    $rel             = $workspaceRoot.Replace($solutionRoot, "").TrimStart("/").TrimStart("\").Replace("\", "/")
    $resolvedProject = if ($rel) { $rel } else { "." }
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Result([hashtable]$hash) {
    Write-Output ($hash | ConvertTo-Json -Compress -Depth 5)
}

function Get-Timestamp {
    # Format: YYYYDDMMHHMM  e.g. 202619061430 = 2026-06-19 14:30
    return (Get-Date).ToString("yyyyddMMHHmm")
}

function Get-RelativePath([string]$fullPath) {
    return $fullPath.Replace($workspaceRoot, "").TrimStart("/").TrimStart("\").Replace("\", "/")
}

function Resolve-WsPath([string]$relative) {
    # Accept forward or back slashes; split and rejoin with the platform-native separator.
    $parts = $relative -split '[/\\]' | Where-Object { $_ -ne '' }
    $result = $workspaceRoot
    foreach ($p in $parts) { $result = Join-Path $result $p }
    return $result
}

function Get-PhaseFileFromRegistry([string]$registryPath, [string]$phaseId) {
    # registry.md columns: | # | Phase | Phase File | Status | Session | Depends On |
    # Returns the Phase File value for the row whose Phase column matches $phaseId, or
    # $null if the registry is missing, unreadable, or has no matching row. Reading this
    # column is required for the gate phase-document path — reconstructing it via a
    # sdp-docs/[phaseId].md naming convention does not match every project's actual
    # phase-document naming (see sdp-project-coordinator's Gate Dispatch Variant, which reads this
    # same column for the same reason).
    if (-not (Test-Path $registryPath)) { return $null }
    try {
        $lines = (Get-Content $registryPath -Raw -Encoding UTF8 -ErrorAction Stop) -split '\r?\n'
    } catch { return $null }
    foreach ($line in $lines) {
        if ($line -notmatch '^\s*\|') { continue }
        $cols = ($line.Trim().Trim('|') -split '\|') | ForEach-Object { $_.Trim().Trim('`') }
        if ($cols.Count -lt 3) { continue }
        if ($cols[1] -eq $phaseId) { return $cols[2] }
    }
    return $null
}

function Write-TempError([string]$errorMsg, [int]$phase, [int]$retryCount) {
    try {
        $ts       = Get-Timestamp
        $tempDir  = Resolve-WsPath ".sdp-workflow/temp/phase-$phase"
        if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }
        $tempPath = Join-Path $tempDir "phase$phase-sdp-create-prompt-$ts.json"

        $content = [ordered]@{
            _meta = [ordered]@{
                created       = (Get-Date).ToString("yyyy-dd-MM-HHmm")
                phase         = $phase
                skill         = "sdp-project-create-prompt"
                script_status = "error"
                error         = $errorMsg
                retry_count   = $retryCount
            }
        }
        $content | ConvertTo-Json -Depth 5 | Set-Content $tempPath -Encoding UTF8

        # Tracking file
        $trackingPath = Resolve-WsPath ".sdp-workflow/temp/sdp-create-prompt-tracking.json"
        $trackingDir  = Split-Path -Parent $trackingPath
        if (-not (Test-Path $trackingDir)) { New-Item -ItemType Directory -Path $trackingDir -Force | Out-Null }
        [ordered]@{
            generated_at      = (Get-Date).ToString("yyyy-dd-MM-HHmm")
            active_temp_file  = Get-RelativePath $tempPath
            script_status     = "error"
            state_snapshot    = $null
        } | ConvertTo-Json -Depth 3 | Set-Content $trackingPath -Encoding UTF8

        Write-Result @{ status = "error"; resolvedProject = $resolvedProject; tempFile = (Get-RelativePath $tempPath); error = $errorMsg }
    } catch {
        Write-Result @{ status = "error"; resolvedProject = $resolvedProject; tempFile = $null; error = $errorMsg }
    }
}

# ---------------------------------------------------------------------------
# Step 1: Read state.json
# ---------------------------------------------------------------------------

$stateFile = Resolve-WsPath ".sdp-workflow/state.json"
$phase     = 0

if (-not (Test-Path $stateFile)) {
    Write-TempError "state.json not found at: $(Get-RelativePath $stateFile)" $phase 0
    exit 1
}

$state = $null
try {
    # Read JSON/text inputs as UTF-8 explicitly. Windows PowerShell 5.1 otherwise
    # decodes a no-BOM file using the system ANSI codepage, corrupting any multibyte
    # character (e.g. an em-dash in project_name or halt_reason) before it reaches the
    # prompt. -Encoding UTF8 handles both BOM and no-BOM UTF-8 correctly.
    $state = Get-Content $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    Write-TempError "Failed to parse state.json: $($_.Exception.Message)" $phase 0
    exit 1
}

$phase = if ($null -ne $state.current_phase) {
    $raw = "$($state.current_phase)"
    if ($raw -match '(\d+)') { [int]$Matches[1] } else { 0 }
} else { 0 }

# ---------------------------------------------------------------------------
# Check for prior temp file (for retry_count)
# ---------------------------------------------------------------------------

$retryCount  = 0
$trackingPath = Resolve-WsPath ".sdp-workflow/temp/sdp-create-prompt-tracking.json"

if (Test-Path $trackingPath) {
    try {
        $tracking = Get-Content $trackingPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($tracking.active_temp_file) {
            $priorTempFull = Resolve-WsPath $tracking.active_temp_file
            if (Test-Path $priorTempFull) {
                $priorTemp = Get-Content $priorTempFull -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($priorTemp._meta -and $null -ne $priorTemp._meta.retry_count) {
                    # Only carry forward and increment across consecutive error runs (the
                    # retry sequence). A prior success or halt is not a retry — reset to 0 so
                    # the counter does not climb monotonically across clean invocations.
                    if ($priorTemp._meta.script_status -eq "error") {
                        $retryCount = [int]$priorTemp._meta.retry_count + 1
                    } else {
                        $retryCount = 0
                    }
                }
            }
        }
    } catch { }
}

# ---------------------------------------------------------------------------
# Halted workflow — write halt temp and exit cleanly
# ---------------------------------------------------------------------------

if ($state.workflow_status -eq "halted") {
    $haltReason = if ($state.halt_reason) { $state.halt_reason } else { "No halt reason recorded in state.json" }
    $ts      = Get-Timestamp
    $tempDir = Resolve-WsPath ".sdp-workflow/temp/phase-$phase"
    if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }
    $tempPath = Join-Path $tempDir "phase$phase-sdp-create-prompt-$ts.json"

    [ordered]@{
        _meta = [ordered]@{
            created       = (Get-Date).ToString("yyyy-dd-MM-HHmm")
            phase         = $phase
            skill         = "sdp-project-create-prompt"
            script_status = "halted"
            error         = $null
            retry_count   = $retryCount
        }
        halt_reason = $haltReason
    } | ConvertTo-Json -Depth 5 | Set-Content $tempPath -Encoding UTF8

    $trackingDir = Split-Path -Parent $trackingPath
    if (-not (Test-Path $trackingDir)) { New-Item -ItemType Directory -Path $trackingDir -Force | Out-Null }
    [ordered]@{
        generated_at     = (Get-Date).ToString("yyyy-dd-MM-HHmm")
        active_temp_file = Get-RelativePath $tempPath
        script_status    = "halted"
        state_snapshot   = [ordered]@{
            workflow_status  = $state.workflow_status
            current_phase    = $state.current_phase
            active_work_item = $state.active_work_item
            last_session     = $state.last_session
        }
    } | ConvertTo-Json -Depth 5 | Set-Content $trackingPath -Encoding UTF8

    Write-Result @{ status = "halted"; resolvedProject = $resolvedProject; tempFile = (Get-RelativePath $tempPath); haltReason = $haltReason }
    exit 0
}

# ---------------------------------------------------------------------------
# Step 2: Read registry.md and last session file
# ---------------------------------------------------------------------------

$registryFile = Resolve-WsPath ".sdp-workflow/registry.md"
# Registry existence is confirmed here for Key Files listing (Section 5, non-gate path).
# For the GATE_REVIEWER path specifically, the registry's Phase File column is also read
# below (via Get-PhaseFileFromRegistry) to resolve the actual phase-document path.
$registryExists = Test-Path $registryFile

$lastSessionContent = ""
if ($state.last_session) {
    $sessionFile = Resolve-WsPath ".sdp-workflow/sessions/session-$($state.last_session).md"
    if (Test-Path $sessionFile) {
        try { $lastSessionContent = Get-Content $sessionFile -Raw -Encoding UTF8 } catch { }
    }
}

# ---------------------------------------------------------------------------
# Step 3: Read phase state file — determine next role and task status
# ---------------------------------------------------------------------------

$nextRole   = "COORDINATOR"
$taskStatus = "none"
$taskFlags  = @()
$phaseStateRelPath = ""

$activeWorkItem = if ($state.active_work_item) { $state.active_work_item } else { "none" }

if ($activeWorkItem -ne "none" -and $activeWorkItem -ne $null) {
    # Prefer active_phase_file from state.json for reliable path derivation
    $phaseStateFile = ""
    if ($state.active_phase_file) {
        $derived = Resolve-WsPath ($state.active_phase_file -replace '\.md$', '_state.json')
        if (Test-Path $derived) { $phaseStateFile = $derived }
    }
    # Fallback: original integer-based convention
    if (-not $phaseStateFile) {
        $candidate = Resolve-WsPath ".sdp-workflow/phase${phase}_state.json"
        if (Test-Path $candidate) { $phaseStateFile = $candidate }
    }
    # Fallback: broad search in sdp-docs
    if (-not $phaseStateFile) {
        $sdpDocsDir = Join-Path $workspaceRoot "sdp-docs"
        if (Test-Path $sdpDocsDir) {
            $candidates = Get-ChildItem -Path $sdpDocsDir -Filter "*phase*state.json" -Recurse -ErrorAction SilentlyContinue |
                          Where-Object { $_.Name -match "phase$phase" }
            if ($candidates) { $phaseStateFile = $candidates[0].FullName }
        }
    }

    if (Test-Path $phaseStateFile) {
        $phaseStateRelPath = Get-RelativePath $phaseStateFile
        try {
            $phaseState = Get-Content $phaseStateFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $taskEntry  = $null

            # Support both array and object keyed by ID
            if ($phaseState.tasks -is [array]) {
                $taskEntry = $phaseState.tasks | Where-Object { $_.id -eq $activeWorkItem }
            } elseif ($phaseState.tasks) {
                $prop = $phaseState.tasks.PSObject.Properties[$activeWorkItem]
                if ($prop) { $taskEntry = $prop.Value }
            } else {
                # Top-level keyed by ID
                $prop = $phaseState.PSObject.Properties[$activeWorkItem]
                if ($prop) { $taskEntry = $prop.Value }
            }

            if ($taskEntry) {
                $taskStatus = $taskEntry.status
                if ($taskEntry.flags) { $taskFlags = @($taskEntry.flags) }

                $nextRole = switch ($taskStatus) {
                    "PENDING"       { "WORKER" }
                    "WORK_COMPLETE" { "COORDINATOR" }
                    "REJECTED"      { "COORDINATOR" }
                    "VERIFIED"      { "COORDINATOR" }
                    default         { "COORDINATOR" }
                }
            }
        } catch {
            # Phase state unreadable — default to COORDINATOR
        }
    }
}

# ---------------------------------------------------------------------------
# Gate state (read-only here — no longer overrides nextRole). Removed the prior
# GATE_REVIEWER shortcut (user direction, 2026-07-12; root-caused against
# CapEx-Watch's 8 recurring GATE_REPAIR fires this same period): this script is
# constitutionally forbidden from writing session files or state.json, so a
# GATE_REVIEWER sentinel written here can never be backed by a real dispatch —
# state.json.last_session still points at the prior WORKER/REVIEWER session,
# guaranteeing sdp-project-state-loop's Step 4.5c integrity check fails on the very next
# EXECUTE and fires GATE_REPAIR to re-dispatch sdp-project-coordinator anyway. That
# decision belongs solely to sdp-project-coordinator's Gate Dispatch Variant, which
# writes the session file, sentinel, and last_session together, atomically.
# With the override gone, a VERIFIED last task now falls through to the
# existing switch above (VERIFIED -> COORDINATOR unconditionally), so
# sdp-project-coordinator gets dispatched directly and performs the real gate dispatch
# on its own next fire -- no wasted premature sentinel, no repair cycle.
# $phaseGate/$phaseGateStatus/$phaseGateEvalCycles remain below only because the
# still-present (but now unreachable) GATE_REVIEWER rendering branches further
# down reference them; not touched here to keep this change to the one thing it
# was scoped to fix.
# ---------------------------------------------------------------------------

$phaseGate          = if ($state.PSObject.Properties['phase_gate']) { $state.phase_gate } else { $null }
$phaseGateStatus    = if ($phaseGate -and $phaseGate.PSObject.Properties['status'])       { "$($phaseGate.status)" }       else { "passed" }
$phaseGateEvalCycles = if ($phaseGate -and $phaseGate.PSObject.Properties['gate_eval_cycles']) { [int]$phaseGate.gate_eval_cycles } else { 0 }

# ---------------------------------------------------------------------------
# Gate phase-document path — resolved from registry.md's Phase File column, not
# reconstructed via a sdp-docs/[current_phase].md naming convention (does not match
# every project's actual phase-document naming). Falls back to that convention only
# when the registry lookup fails, flagged via $gatePhaseDocFromRegistry so the caveat
# can be surfaced to the dispatched GATE_REVIEWER session.
# ---------------------------------------------------------------------------

$gatePhaseDocPath = $null
$gatePhaseDocFromRegistry = $false
if ($nextRole -eq "GATE_REVIEWER") {
    $gatePhaseDocPath = Get-PhaseFileFromRegistry $registryFile "$($state.current_phase)"
    if ($gatePhaseDocPath) {
        $gatePhaseDocFromRegistry = $true
    } else {
        $gatePhaseDocPath = "sdp-docs/$($state.current_phase).md"
    }
}

# ---------------------------------------------------------------------------
# Step 4: Read SDP-Document-List.json — classify auto-loaded files
# ---------------------------------------------------------------------------

$autoLoadedPaths = @()
$docListFile = Join-Path $workspaceRoot "SDP-Document-List.json"
if (Test-Path $docListFile) {
    try {
        $docList = Get-Content $docListFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($entry in $docList) {
            if ($entry.includeInReadDocs -eq $true) {
                $autoLoadedPaths += $entry.path
            }
        }
    } catch { }
}

# ---------------------------------------------------------------------------
# Detect known flags
# ---------------------------------------------------------------------------

$diagBlocked     = $taskFlags -contains "DIAGNOSIS_BLOCKED"
$partialEscalate = $taskFlags -contains "PARTIAL_COMPLIANCE_ESCALATE"

# ---------------------------------------------------------------------------
# Build section content
# ---------------------------------------------------------------------------

$projectName  = if ($state.project_name) { $state.project_name } `
                elseif ($state.project)   { $state.project } `
                else                      { "this project" }
$lastSession  = if ($state.last_session) { $state.last_session } else { "none" }
$workflowStatus = if ($state.workflow_status) { $state.workflow_status } else { "active" }

# Sentinel — GATE_REVIEWER uses current_phase as work_item and phase_gate.status as expected_status
if ($nextRole -eq "GATE_REVIEWER") {
    $sentinelWorkItem = if ($state.current_phase) { "$($state.current_phase)" } else { "unknown-phase" }
    $sentinelStatus   = $phaseGateStatus
} else {
    $sentinelWorkItem = $activeWorkItem
    $sentinelStatus   = if ($taskStatus -ne "none") { $taskStatus } else { "none" }
}
$sentinel = "[sdp-prompt work_item=`"$sentinelWorkItem`" expected_status=`"$sentinelStatus`" role=`"$nextRole`"]"

# --- Section 1 ---
$section1 = "You are acting as $nextRole for the **$projectName** project using the SDP workflow."

# --- Section 2 ---
$section2Lines = @()
if ($nextRole -eq "WORKER" -or $nextRole -eq "REVIEWER") {
    if ($lastSession -ne "none") {
        $sessionId      = $lastSession -replace '^session-', ''
        $sessionRelPath = ".sdp-workflow/sessions/session-$sessionId.md"
        if ($autoLoadedPaths -notcontains $sessionRelPath) {
            $section2Lines += "- Read ``$sessionRelPath`` as step 2 of your role procedure - this is your dispatch file."
        }
    }
}
$section2 = if ($section2Lines.Count -gt 0) {
    $section2Lines -join "`n"
} else {
    "All required context files are loaded automatically at session start via sdp-project-read-docs."
}

# --- Section 3 ---
$nextActionDesc = switch ($nextRole) {
    "WORKER"        { "Execute task $activeWorkItem" }
    "REVIEWER"      { "Verify task $activeWorkItem (WORK_COMPLETE)" }
    "GATE_REVIEWER" { "Gate review - phase $($state.current_phase) ($phaseGateStatus, $phaseGateEvalCycles eval cycles)" }
    "COORDINATOR" {
        switch ($taskStatus) {
            "WORK_COMPLETE" { "Dispatch REVIEWER for $activeWorkItem" }
            "REJECTED"      { "Re-queue $activeWorkItem; dispatch new WORKER" }
            "VERIFIED"      { "Advance to next task or phase gate" }
            default         { "Determine next dispatch" }
        }
    }
    default { "Determine next dispatch" }
}

if ($nextRole -eq "GATE_REVIEWER") {
    $section3 = @"
| Field | Value |
|-------|-------|
| Project | $projectName |
| Current phase | $($state.current_phase) |
| Workflow status | $workflowStatus |
| Phase gate status | $phaseGateStatus |
| Gate eval cycles | $phaseGateEvalCycles |
| Last session | $lastSession |
| Next action | $nextActionDesc |
"@
    $section3Table = [ordered]@{
        Project              = $projectName
        "Current phase"      = "$($state.current_phase)"
        "Workflow status"    = $workflowStatus
        "Phase gate status"  = $phaseGateStatus
        "Gate eval cycles"   = "$phaseGateEvalCycles"
        "Last session"       = $lastSession
        "Next action"        = $nextActionDesc
    }
} else {
    $section3 = @"
| Field | Value |
|-------|-------|
| Project | $projectName |
| Current phase | $phase |
| Workflow status | $workflowStatus |
| Active work item | $activeWorkItem |
| Last session | $lastSession |
| Next action | $nextActionDesc |
"@
    $section3Table = [ordered]@{
        Project           = $projectName
        "Current phase"   = "$phase"
        "Workflow status" = $workflowStatus
        "Active work item"= $activeWorkItem
        "Last session"    = $lastSession
        "Next action"     = $nextActionDesc
    }
}

# --- Section 4 ---
$section4 = switch ($nextRole) {
    "WORKER" {
        $lines = @("Your assigned task is **$activeWorkItem**. The task description is in the phase file listed in Section 5. Invoke ``/sdp-project-worker`` to begin.")
        if ($diagBlocked) {
            $lines += ""
            $lines += "> **Flag: DIAGNOSIS_BLOCKED** - A prior fix attempt reached a blocked diagnosis. Read the Completed blockquote for the root cause finding and User decision needed line before beginning work."
        }
        if ($partialEscalate) {
            $lines += ""
            $lines += "> **Flag: PARTIAL_COMPLIANCE_ESCALATE** - Two consecutive partially compliant evaluations recorded. Review all Eval blockquotes and address outstanding compliance items before submitting."
        }
        $lines -join "`n"
    }
    "REVIEWER" {
        $lines = @("Verify **$activeWorkItem** against its acceptance criteria. Read the task description independently before reading the Completed blockquote. The phase file is listed in Section 5. Invoke ``/sdp-project-reviewer`` to begin.")
        if ($diagBlocked) {
            $lines += ""
            $lines += "> **Flag: DIAGNOSIS_BLOCKED** - Note this flag is present. Include an assessment of the blocked diagnosis in your evaluation findings."
        }
        $lines -join "`n"
    }
    "GATE_REVIEWER" {
        if ($phaseGateStatus -eq "blocked") {
            "Review the completed **$($state.current_phase)** phase document against gate criteria. This is a re-gate cycle - a prior gate review returned GATE_BLOCKED. Read the prior GATE_BLOCKED blockquote only *after* forming your independent assessment. The phase document is listed in Section 5. Invoke ``/sdp-project-gate-review`` to begin."
        } else {
            "Review the completed **$($state.current_phase)** phase document against gate criteria (completeness, consistency, GPG alignment, next-phase readiness). The phase document is listed in Section 5. Invoke ``/sdp-project-gate-review`` to begin."
        }
    }
    default {
        "Review workflow state and determine the next dispatch. Invoke ``/sdp-project-coordinator`` to begin."
    }
}

# --- Section 5 ---
$gpgToc = "standards/GenericProjectGuidlines_Sections/GenericProjectGuidlines_TOC.md"
$section5Lines = @()

if ($nextRole -eq "GATE_REVIEWER") {
    # Gate review is document-scoped — include phase doc and session file; exclude phase state file
    $section5Lines += "- Phase document: ``$gatePhaseDocPath``"
    if (-not $gatePhaseDocFromRegistry) {
        $section5Lines += "- WARNING: Phase File not found in registry.md for ``$($state.current_phase)`` - path above was reconstructed via naming convention; verify it exists before relying on it."
    }
    if ($lastSession -ne "none") {
        $sessionId      = $lastSession -replace '^session-', ''
        $sessionRelPath = ".sdp-workflow/sessions/session-$sessionId.md"
        if ($autoLoadedPaths -notcontains $sessionRelPath) {
            $section5Lines += "- Session dispatch file: ``$sessionRelPath``"
        }
    }
    $section5Lines += "- Workflow state: ``.sdp-workflow/state.json``"
    $section5Lines += "- GPG TOC (navigation entry point): ``$gpgToc``"
} else {
    $activePhaseFile = if ($state.active_phase_file) { $state.active_phase_file } else { "" }
    if ($activePhaseFile -and $autoLoadedPaths -notcontains $activePhaseFile) {
        $section5Lines += "- Phase file: ``$activePhaseFile``"
    }
    if ($phaseStateRelPath -and $autoLoadedPaths -notcontains $phaseStateRelPath) {
        $section5Lines += "- Phase state file: ``$phaseStateRelPath``"
    }
    if ($lastSession -ne "none") {
        $sessionId      = $lastSession -replace '^session-', ''
        $sessionRelPath = ".sdp-workflow/sessions/session-$sessionId.md"
        if ($autoLoadedPaths -notcontains $sessionRelPath -and $nextRole -eq "COORDINATOR") {
            $section5Lines += "- Last session dispatch file: ``$sessionRelPath``"
        }
    }
    if (Test-Path $registryFile) {
        $section5Lines += "- Registry: ``.sdp-workflow/registry.md``"
    }
    $section5Lines += "- GPG TOC (navigation entry point): ``$gpgToc``"
}

$section5 = $section5Lines -join "`n"

# ---------------------------------------------------------------------------
# Write temp file
# ---------------------------------------------------------------------------

$ts      = Get-Timestamp
$tempDir = Resolve-WsPath ".sdp-workflow/temp/phase-$phase"
if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }
$tempFileName = "phase$phase-sdp-create-prompt-$ts.json"
$tempPath     = Join-Path $tempDir $tempFileName
$tempRelPath  = Get-RelativePath $tempPath

$tempContent = [ordered]@{
    _meta = [ordered]@{
        created       = (Get-Date).ToString("yyyy-dd-MM-HHmm")
        phase         = $phase
        skill         = "sdp-project-create-prompt"
        script_status = "success"
        error         = $null
        retry_count   = $retryCount
    }
    sentinel        = $sentinel
    next_role       = $nextRole
    flags           = $taskFlags
    section_1       = $section1
    section_2       = $section2
    section_3       = $section3
    section_3_table = $section3Table
    section_4       = $section4
    section_5       = $section5
    section_5_files = $section5Lines
}

try {
    $tempContent | ConvertTo-Json -Depth 10 | Set-Content $tempPath -Encoding UTF8
} catch {
    Write-Result @{ status = "error"; resolvedProject = $resolvedProject; tempFile = $null; error = "Failed to write temp file: $($_.Exception.Message)" }
    exit 1
}

# ---------------------------------------------------------------------------
# Write sdp-docs/00_prompt.txt — the deterministic, single-option dispatch
# prompt. The script is the normal-path writer; the section strings above are
# the final content, so no LLM assembly step is required. The LLM only
# overwrites this file for the rare two-option case (which needs conversational
# context the script cannot see). Written as UTF-8 *without* BOM: sdp-project-state-loop
# reads only the first line and matches the sentinel pattern — a BOM in front of
# `[sdp-prompt` would break that match.
# ---------------------------------------------------------------------------

# Build the em-dash from its code point rather than a literal. Windows PowerShell
# 5.1 parses a no-BOM .ps1 as the ANSI codepage, which would corrupt a literal "—"
# in this source into mojibake before it is ever written. $emdash is U+2014 in
# memory regardless of how the source bytes are read.
$emdash = [char]0x2014
$promptText = @"
$sentinel

## Section 1 $emdash Role Declaration

$section1

## Section 2 $emdash Read First

$section2

## Section 3 $emdash Current State Summary

$section3

## Section 4 $emdash Task Instruction

$section4

## Section 5 $emdash Key Files

$section5
"@

$promptDir = Join-Path $workspaceRoot "sdp-docs"
if (-not (Test-Path $promptDir)) { New-Item -ItemType Directory -Path $promptDir -Force | Out-Null }
$promptPath    = Join-Path $promptDir "00_prompt.txt"
$promptRelPath = Get-RelativePath $promptPath

try {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($promptPath, $promptText, $utf8NoBom)
} catch {
    Write-Result @{ status = "error"; resolvedProject = $resolvedProject; tempFile = $tempRelPath; error = "Failed to write sdp-docs/00_prompt.txt: $($_.Exception.Message)" }
    exit 1
}

# ---------------------------------------------------------------------------
# Write tracking file
# ---------------------------------------------------------------------------

$trackingDir = Split-Path -Parent $trackingPath
if (-not (Test-Path $trackingDir)) { New-Item -ItemType Directory -Path $trackingDir -Force | Out-Null }

try {
    [ordered]@{
        generated_at     = (Get-Date).ToString("yyyy-dd-MM-HHmm")
        active_temp_file = $tempRelPath
        script_status    = "success"
        state_snapshot   = [ordered]@{
            workflow_status  = $workflowStatus
            current_phase    = $state.current_phase
            active_work_item = $activeWorkItem
            last_session     = $lastSession
        }
    } | ConvertTo-Json -Depth 5 | Set-Content $trackingPath -Encoding UTF8
} catch {
    # Non-fatal — tracking file failure does not block main output
}

# ---------------------------------------------------------------------------
# Output result
# ---------------------------------------------------------------------------

Write-Result @{
    status          = "success"
    resolvedProject = $resolvedProject
    tempFile        = $tempRelPath
    promptFile      = $promptRelPath
    nextRole        = $nextRole
    workItem        = $sentinelWorkItem
    flags           = $taskFlags
}

exit 0
