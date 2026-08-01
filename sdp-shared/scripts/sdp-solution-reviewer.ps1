<#
.SYNOPSIS
    Deterministic backend for the sdp-solution-reviewer skill. Three modes: Bootstrap (read
    state, verify child preconditions, report dispatch targets), Confirm (re-read child
    outcomes after reviewer dispatch, resolve cascade or clear the path to the integration
    check), Finalize (write the session outcome file and set SOL_VERIFIED / SOL_REJECTED once
    the LLM has completed the cross-project integration check).

.PARAMETER Mode
    "Bootstrap" (default), "Confirm", or "Finalize".

.PARAMETER Verdict
    Finalize only. "SOL_VERIFIED" or "SOL_REJECTED" - the LLM's integration-check verdict.

.PARAMETER InterfaceContracts
    Finalize only. "passes" or "fails" - Integration Check item 1.

.PARAMETER SharedTypes
    Finalize only. "passes" or "fails" - Integration Check item 2.

.PARAMETER ErrorHandling
    Finalize only. "passes" or "fails" - Integration Check item 3.

.PARAMETER IntegrationAssumptions
    Finalize only. "passes" or "fails" - Integration Check item 4.

.PARAMETER Findings
    Finalize only. Free-text finding detail, required when any integration check item fails.

.NOTES
    Reads:
      SDP-Solution.json
      .sdp-solution-workflow/state.json
      [child.project]/[derived phase]_state.json  (authoritative child status)
      [child.project]/[child.phase_file]          (rejection summary extraction, Confirm mode)
    Writes:
      .sdp-solution-workflow/state.json               (cached_status corrections, status
        transitions, last_session, updated; halt transitions)
      .sdp-solution-workflow/sessions/session-NNN.md  (Confirm cascade path; Finalize)
      SDP-Solution.json                                (updated)
    Side effect: on every halt, cascade, and Finalize verdict (SOL_VERIFIED/SOL_REJECTED),
      invokes sdp-workflow-log.ps1 (non-blocking - any failure is swallowed) to record the event
      in the semantic workflow-log stream.
    Stdout: single-line JSON result object per mode - contracts for all three modes (Bootstrap,
      Confirm, Finalize) are documented in this script's calling skill, sdp-shared/ai-skills/
      sdp-solution-reviewer/SKILL.md.
    Exit codes: 0 = success, halt, cascade, in_progress, or ready_for_integration_check (all
      expected, non-error terminal states the calling skill branches on); 1 = error (script
      could not complete the operation at all).
#>

param(
    [string]$Mode = "Bootstrap",
    [string]$Verdict = "",
    [string]$InterfaceContracts = "",
    [string]$SharedTypes = "",
    [string]$ErrorHandling = "",
    [string]$IntegrationAssumptions = "",
    [string]$Findings = ""
)

$solutionRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Result([hashtable]$hash) {
    Write-Output ($hash | ConvertTo-Json -Compress -Depth 8)
}

function Exit-Error([string]$msg) {
    $r = [ordered]@{ status = "error"; error = $msg }
    Write-Result $r
    exit 1
}

function Get-RelPath([string]$fullPath) {
    return $fullPath.Replace($solutionRoot, "").TrimStart("\").TrimStart("/").Replace("\", "/")
}

function Get-Flags($obj) {
    if ($obj -and $obj.PSObject.Properties['flags'] -and $obj.flags) { return @($obj.flags) }
    return @()
}

function Get-TaskEntry($stateObj, [string]$taskId) {
    $tasks = @($stateObj.tasks)
    return ($tasks | Where-Object { $_.id -eq $taskId } | Select-Object -First 1)
}

function Get-RejectionSummary([string]$phaseFilePath) {
    if (-not (Test-Path $phaseFilePath)) { return "No rejection details found - phase file missing." }
    try { $content = Get-Content $phaseFilePath -Raw -Encoding UTF8 } catch { return "No rejection details found - phase file unreadable." }
    $m = [regex]::Matches($content, 'Outcome:\s*non-compliant[^\r\n]*')
    if ($m.Count -gt 0) { return ($m[$m.Count - 1].Value).Trim() }
    $m2 = [regex]::Matches($content, '(?m)^>\s*\*\*Eval \d+.*$')
    if ($m2.Count -gt 0) { return ($m2[$m2.Count - 1].Value).Trim() }
    return "Rejection detected but no Eval blockquote found in phase file."
}

function Set-JsonFileWithRetry($obj, [string]$path, [int]$depth) {
    # Set-Content can transiently fail with "file in use" under antivirus/indexer
    # contention on freshly-written files - retry briefly before giving up.
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

function Save-StateJson($stateObj, [string]$path) {
    return (Set-JsonFileWithRetry $stateObj $path 14)
}

function Write-WorkflowLog([string]$trigger, [string]$role, [string]$outcome, [string]$reason) {
    try {
        $workflowLogPath = Join-Path $PSScriptRoot "sdp-workflow-log.ps1"
        if (Test-Path $workflowLogPath) {
            & $workflowLogPath -trigger $trigger -role $role -outcome $outcome -reason $reason | Out-Null
        }
    } catch {
        # Workflow logging is a non-blocking side effect - swallow any failure.
    }
}

function Exit-Halt($stateObj, [string]$statePath, [string]$reason) {
    $stateObj | Add-Member -NotePropertyName workflow_status -NotePropertyValue "halted" -Force
    $stateObj | Add-Member -NotePropertyName halt_reason -NotePropertyValue $reason -Force
    $stateObj | Add-Member -NotePropertyName updated -NotePropertyValue (Get-Date -Format "yyyy-MM-dd") -Force
    $written = Save-StateJson $stateObj $statePath
    Write-WorkflowLog "solution.halt" "SOLUTION_REVIEWER" "halted" $reason
    $r = [ordered]@{
        status       = "halt"
        error        = $null
        halt_message = "Solution reviewer halted - $reason. Resolve this condition and run sdp-solution-coordinator to resume."
        state_json_written = $written
    }
    Write-Result $r
    exit 0
}

# ---------------------------------------------------------------------------
# Shared context load: SDP-Solution.json, .sdp-solution-workflow/state.json, task entry
# ---------------------------------------------------------------------------

function Load-Context {
    $sdpSolutionPath = Join-Path $solutionRoot "SDP-Solution.json"
    if (-not (Test-Path $sdpSolutionPath)) {
        Exit-Error "SDP-Solution.json not found at solution root. Run the sdp-workspace-setup skill to create it before proceeding."
    }
    try {
        $sdpSolution = Get-Content $sdpSolutionPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Exit-Error "Failed to parse SDP-Solution.json: $($_.Exception.Message)"
    }

    $activeSolutionTask = $sdpSolution.active_solution_task
    if (-not $activeSolutionTask) {
        Exit-Error "SDP-Solution.json has no active_solution_task. Set an active solution task before invoking sdp-solution-reviewer."
    }

    $statePath = Join-Path $solutionRoot ".sdp-solution-workflow/state.json"
    if (-not (Test-Path $statePath)) {
        Exit-Error ".sdp-solution-workflow/state.json not found. Solution workflow state has not been initialized - run solution setup to create it."
    }
    try {
        $state = Get-Content $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Exit-Error "Failed to parse .sdp-solution-workflow/state.json: $($_.Exception.Message)"
    }

    $workflowStatus = if ($state.PSObject.Properties['workflow_status'] -and $state.workflow_status) { $state.workflow_status } else { "active" }
    if ($workflowStatus -eq "halted") {
        $haltReason = if ($state.PSObject.Properties['halt_reason'] -and $state.halt_reason) { $state.halt_reason } else { "No halt reason recorded in state.json" }
        $r = [ordered]@{
            status       = "halt"
            error        = $null
            halt_message = "Solution halted - $haltReason. Resolve this condition and run sdp-solution-coordinator to resume."
            state_json_written = $false
        }
        Write-Result $r
        exit 0
    }

    $taskEntry = Get-TaskEntry $state $activeSolutionTask
    if (-not $taskEntry) {
        Exit-Halt $state $statePath "No task entry for '$activeSolutionTask' found in .sdp-solution-workflow/state.json. State file may be out of sync with SDP-Solution.json - verify both files."
    }

    return [ordered]@{
        sdpSolution     = $sdpSolution
        sdpSolutionPath = $sdpSolutionPath
        state           = $state
        statePath       = $statePath
        taskEntry       = $taskEntry
        taskId          = $activeSolutionTask
    }
}

# ---------------------------------------------------------------------------
# Resolve a single child's authoritative status
# ---------------------------------------------------------------------------

function Resolve-ChildStatus($child) {
    $childProject   = $child.project
    $childTaskId    = $child.task_id
    $childPhaseFile = $child.phase_file
    $cachedStatus   = if ($child.PSObject.Properties['cached_status']) { $child.cached_status } else { $null }

    $childStateFile = $null

    if ($childPhaseFile) {
        $docDirFwd     = ($childPhaseFile -replace '\\', '/')
        $docDir        = Split-Path -Parent $docDirFwd
        $phaseBaseName = [System.IO.Path]::GetFileNameWithoutExtension($childPhaseFile)

        # Convention 1: per-phase folder ([docDir]_Phases/[phase]_state.json)
        $candidateDir = Join-Path (Join-Path $solutionRoot $childProject) ("$($docDir)_Phases")
        $candidate1   = Join-Path $candidateDir "$($phaseBaseName)_state.json"
        if (Test-Path $candidate1) {
            $childStateFile = $candidate1
        } else {
            # Convention 2: flat sibling file (.md -> _state.json in place)
            $candidate2 = Join-Path (Join-Path $solutionRoot $childProject) ($childPhaseFile -replace '\.md$', '_state.json')
            if (Test-Path $candidate2) { $childStateFile = $candidate2 }
        }
    }

    if (-not $childStateFile) {
        return [ordered]@{ ok = $false; reason = "cannot resolve state file for '$childProject' ('$childTaskId') from phase_file '$childPhaseFile' - neither the '_Phases' folder convention nor the flat '_state.json' sibling convention produced an existing file" }
    }

    try {
        $childState = Get-Content $childStateFile -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return [ordered]@{ ok = $false; reason = "cannot parse child state file at '$(Get-RelPath $childStateFile)': $($_.Exception.Message)" }
    }

    $childTaskEntry = $null
    if ($childState.PSObject.Properties['tasks']) {
        if ($childState.tasks -is [array]) {
            $childTaskEntry = $childState.tasks | Where-Object { $_.id -eq $childTaskId } | Select-Object -First 1
        } elseif ($childState.tasks) {
            $prop = $childState.tasks.PSObject.Properties[$childTaskId]
            if ($prop) { $childTaskEntry = $prop.Value }
        }
    }
    if (-not $childTaskEntry) {
        $prop = $childState.PSObject.Properties[$childTaskId]
        if ($prop) { $childTaskEntry = $prop.Value }
    }

    if (-not $childTaskEntry -or -not $childTaskEntry.PSObject.Properties['status']) {
        return [ordered]@{ ok = $false; reason = "task entry '$childTaskId' not found in child state file at '$(Get-RelPath $childStateFile)'" }
    }

    $authStatus = $childTaskEntry.status
    return [ordered]@{
        ok                   = $true
        project              = $childProject
        task_id              = $childTaskId
        phase_file           = $childPhaseFile
        state_file           = (Get-RelPath $childStateFile)
        authoritative_status = $authStatus
        cached_status        = $cachedStatus
        was_stale            = [bool]($cachedStatus -and ($authStatus -ne $cachedStatus))
    }
}

function Save-StaleCorrections($taskEntryObj, $resultChildren, $stateObj, [string]$statePathLocal) {
    foreach ($rawChild in @($taskEntryObj.children)) {
        $match = $resultChildren | Where-Object { $_.project -eq $rawChild.project -and $_.task_id -eq $rawChild.task_id }
        if ($match -and $match.cached_status_was_stale) {
            $rawChild | Add-Member -NotePropertyName cached_status -NotePropertyValue $match.authoritative_status -Force
        }
    }
    $stateObj | Add-Member -NotePropertyName updated -NotePropertyValue (Get-Date -Format "yyyy-MM-dd") -Force
    return (Save-StateJson $stateObj $statePathLocal)
}

# ---------------------------------------------------------------------------
# Mode: Bootstrap (Steps 1-3)
# ---------------------------------------------------------------------------

function Invoke-Bootstrap {
    $ctx       = Load-Context
    $state     = $ctx.state
    $statePath = $ctx.statePath
    $taskEntry = $ctx.taskEntry
    $taskId    = $ctx.taskId

    $status = $taskEntry.status
    if ($status -ne "SOL_WORK_COMPLETE") {
        Exit-Error "Solution task '$taskId' is in status '$status', not SOL_WORK_COMPLETE. sdp-solution-reviewer may only run when the worker phase is complete. Current status indicates the coordinator dispatched this reviewer prematurely."
    }

    $children = @($taskEntry.children)
    if ($children.Count -eq 0) {
        Exit-Halt $state $statePath "Solution task '$taskId' has no children listed in .sdp-solution-workflow/state.json - cannot verify preconditions."
    }

    $dispatchMode = if ($taskEntry.PSObject.Properties['dispatch_mode'] -and $taskEntry.dispatch_mode) { $taskEntry.dispatch_mode } else { "synced" }
    $lastSession  = if ($state.PSObject.Properties['last_session'] -and $state.last_session) { [int]$state.last_session } else { 0 }

    $resultChildren = @()
    $anyStale = $false
    foreach ($child in $children) {
        $rc = Resolve-ChildStatus $child
        if (-not $rc.ok) {
            Exit-Halt $state $statePath "Cannot read child state file for '$($child.project)' ('$($child.task_id)') - $($rc.reason)."
        }
        if ($rc.authoritative_status -ne "WORK_COMPLETE" -and $rc.authoritative_status -ne "VERIFIED") {
            Exit-Halt $state $statePath "Child task '$($rc.task_id)' in '$($rc.project)' has status '$($rc.authoritative_status)' - must be WORK_COMPLETE or VERIFIED before sdp-solution-reviewer can run. Coordinator dispatched this reviewer prematurely. Terminate and re-run sdp-solution-coordinator to confirm all children are ready."
        }
        if ($rc.was_stale) { $anyStale = $true }
        $resultChildren += [ordered]@{
            project                 = $rc.project
            task_id                 = $rc.task_id
            phase_file              = $rc.phase_file
            state_file              = $rc.state_file
            authoritative_status    = $rc.authoritative_status
            cached_status_was_stale = $rc.was_stale
            needs_dispatch          = ($rc.authoritative_status -eq "WORK_COMPLETE")
        }
    }

    if ($anyStale) {
        $written = Save-StaleCorrections $taskEntry $resultChildren $state $statePath
        if (-not $written) {
            Exit-Error "Detected stale cached_status values for solution task '$taskId' but failed to persist the correction to .sdp-solution-workflow/state.json. Verify the file manually before retrying."
        }
    }

    $r = [ordered]@{
        status                = "success"
        error                 = $null
        halt_message          = $null
        active_solution_task  = $taskId
        dispatch_mode         = $dispatchMode
        last_session          = $lastSession
        children              = $resultChildren
    }
    Write-Result $r
    exit 0
}

# ---------------------------------------------------------------------------
# Mode: Confirm (Steps 5-6, post-dispatch)
# ---------------------------------------------------------------------------

function Invoke-Confirm {
    $ctx       = Load-Context
    $state     = $ctx.state
    $statePath = $ctx.statePath
    $sdpSolution     = $ctx.sdpSolution
    $sdpSolutionPath = $ctx.sdpSolutionPath
    $taskEntry = $ctx.taskEntry
    $taskId    = $ctx.taskId

    $children = @($taskEntry.children)
    $resultChildren = @()
    $anyStale  = $false
    $rejected  = @()
    $notAllDone = $false

    foreach ($child in $children) {
        $rc = Resolve-ChildStatus $child
        if (-not $rc.ok) {
            Exit-Halt $state $statePath "Cannot re-read child state file for '$($child.project)' ('$($child.task_id)') during outcome confirmation - $($rc.reason)."
        }
        if ($rc.was_stale) { $anyStale = $true }
        $entry = [ordered]@{
            project                 = $rc.project
            task_id                 = $rc.task_id
            phase_file              = $rc.phase_file
            state_file              = $rc.state_file
            authoritative_status    = $rc.authoritative_status
            cached_status_was_stale = $rc.was_stale
        }
        $resultChildren += $entry
        if ($rc.authoritative_status -eq "REJECTED") { $rejected += $rc }
        if ($rc.authoritative_status -eq "WORK_COMPLETE") { $notAllDone = $true }
    }

    if ($anyStale) {
        $written = Save-StaleCorrections $taskEntry $resultChildren $state $statePath
        if (-not $written) {
            Exit-Error "Detected stale cached_status values while confirming outcomes for '$taskId' but failed to persist the correction. Verify .sdp-solution-workflow/state.json manually before retrying."
        }
    }

    if ($rejected.Count -gt 0) {
        $rc0 = $rejected[0]
        $phaseFileFull = Join-Path (Join-Path $solutionRoot $rc0.project) $rc0.phase_file
        $summary = Get-RejectionSummary $phaseFileFull
        $rejectedIds = ($rejected | ForEach-Object { "$($_.task_id) ($($_.project))" }) -join ", "
        $cascadeMessage = "$rejectedIds was rejected - $summary. Cascade review required before any other project in this solution task advances. Confirm cascade scope and resolve the rejection before resuming."

        $taskEntry | Add-Member -NotePropertyName status -NotePropertyValue "SOL_REJECTED" -Force
        $taskEntry | Add-Member -NotePropertyName last_updated -NotePropertyValue (Get-Date -Format "yyyy-MM-dd") -Force
        $existingFlags = Get-Flags $taskEntry
        if ($existingFlags -notcontains "SOL_CASCADE_REVIEW_NEEDED") {
            $taskEntry | Add-Member -NotePropertyName flags -NotePropertyValue (@($existingFlags) + "SOL_CASCADE_REVIEW_NEEDED") -Force
        }

        $lastSession = if ($state.PSObject.Properties['last_session'] -and $state.last_session) { [int]$state.last_session } else { 0 }
        $lastSession++
        $nnn = "{0:D3}" -f $lastSession
        $sessionDir = Join-Path $solutionRoot ".sdp-solution-workflow/sessions"
        if (-not (Test-Path $sessionDir)) { New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null }
        $sessionFileName = "session-$nnn.md"
        $sessionPath = Join-Path $sessionDir $sessionFileName

        $outcomeRows = ($resultChildren | ForEach-Object { "| $($_.project) | $($_.task_id) | $($_.authoritative_status) |" }) -join "`n"

        $content = @"
# Solution Reviewer Session - $nnn

| Field | Value |
|-------|-------|
| Date | $(Get-Date -Format "yyyy-MM-dd") |
| Solution task | $taskId |
| Role | SOLUTION_REVIEWER |
| Outcome | SOL_REJECTED |
| Rejection source | $rejectedIds |

## Child Reviewer Outcomes

| Project | Task ID | Outcome |
|---------|---------|---------|
$outcomeRows

## Findings

$summary
"@
        Set-Content -Path $sessionPath -Value $content -Encoding UTF8

        $state | Add-Member -NotePropertyName last_session -NotePropertyValue $lastSession -Force
        $state | Add-Member -NotePropertyName updated -NotePropertyValue (Get-Date -Format "yyyy-MM-dd") -Force
        $stateWritten = Save-StateJson $state $statePath

        $sdpSolution | Add-Member -NotePropertyName updated -NotePropertyValue (Get-Date -Format "yyyy-MM-dd") -Force
        $solutionWritten = Set-JsonFileWithRetry $sdpSolution $sdpSolutionPath 10

        Write-WorkflowLog "solution.cascade" "SOLUTION_REVIEWER" "SOL_REJECTED" $cascadeMessage

        $r = [ordered]@{
            status                    = "cascade"
            error                     = $null
            active_solution_task      = $taskId
            cascade_message           = $cascadeMessage
            session_file_written      = ".sdp-solution-workflow/sessions/$sessionFileName"
            state_json_written        = $stateWritten
            sdp_solution_json_written = $solutionWritten
            children                  = $resultChildren
        }
        Write-Result $r
        exit 0
    }

    if ($notAllDone) {
        $r = [ordered]@{
            status               = "in_progress"
            error                = $null
            active_solution_task = $taskId
            children             = $resultChildren
        }
        Write-Result $r
        exit 0
    }

    $r = [ordered]@{
        status               = "ready_for_integration_check"
        error                = $null
        active_solution_task = $taskId
        children             = $resultChildren
    }
    Write-Result $r
    exit 0
}

# ---------------------------------------------------------------------------
# Mode: Finalize (Steps 8-11, verdict supplied explicitly by the LLM)
# ---------------------------------------------------------------------------

function Invoke-Finalize {
    if ($Verdict -ne "SOL_VERIFIED" -and $Verdict -ne "SOL_REJECTED") {
        Exit-Error "Finalize mode requires -Verdict of SOL_VERIFIED or SOL_REJECTED - got '$Verdict'."
    }

    $ctx       = Load-Context
    $state     = $ctx.state
    $statePath = $ctx.statePath
    $sdpSolution     = $ctx.sdpSolution
    $sdpSolutionPath = $ctx.sdpSolutionPath
    $taskEntry = $ctx.taskEntry
    $taskId    = $ctx.taskId

    $children = @($taskEntry.children)
    $resultChildren = @()
    foreach ($child in $children) {
        $rc = Resolve-ChildStatus $child
        if (-not $rc.ok) {
            Exit-Halt $state $statePath "Cannot re-read child state file for '$($child.project)' ('$($child.task_id)') during finalize - $($rc.reason)."
        }
        $resultChildren += [ordered]@{ project = $rc.project; task_id = $rc.task_id; authoritative_status = $rc.authoritative_status }
    }

    $lastSession = if ($state.PSObject.Properties['last_session'] -and $state.last_session) { [int]$state.last_session } else { 0 }
    $lastSession++
    $nnn = "{0:D3}" -f $lastSession
    $sessionDir = Join-Path $solutionRoot ".sdp-solution-workflow/sessions"
    if (-not (Test-Path $sessionDir)) { New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null }
    $sessionFileName = "session-$nnn.md"
    $sessionPath = Join-Path $sessionDir $sessionFileName

    $outcomeRows = ($resultChildren | ForEach-Object { "| $($_.project) | $($_.task_id) | $($_.authoritative_status) |" }) -join "`n"
    $findingsText = if ($Findings) { $Findings } else { "n/a" }
    $rejectionSource = if ($Verdict -eq "SOL_REJECTED") { "integration check" } else { "n/a" }

    function Note([string]$verdictItem) {
        if ($verdictItem -eq "fails") { return $findingsText }
        return "n/a"
    }
    function VerdictOrNA([string]$v) { if ($v) { return $v } else { return "n/a" } }

    $findingsSection = if ($Verdict -eq "SOL_REJECTED") { "`n## Findings`n`n$findingsText`n" } else { "" }

    $content = @"
# Solution Reviewer Session - $nnn

| Field | Value |
|-------|-------|
| Date | $(Get-Date -Format "yyyy-MM-dd") |
| Solution task | $taskId |
| Role | SOLUTION_REVIEWER |
| Outcome | $Verdict |
| Rejection source | $rejectionSource |

## Child Reviewer Outcomes

| Project | Task ID | Outcome |
|---------|---------|---------|
$outcomeRows

## Integration Check

| Item | Verdict | Notes |
|------|---------|-------|
| Interface contracts | $(VerdictOrNA $InterfaceContracts) | $(Note $InterfaceContracts) |
| Shared type/enum consistency | $(VerdictOrNA $SharedTypes) | $(Note $SharedTypes) |
| Error handling alignment | $(VerdictOrNA $ErrorHandling) | $(Note $ErrorHandling) |
| Integration assumptions | $(VerdictOrNA $IntegrationAssumptions) | $(Note $IntegrationAssumptions) |
$findingsSection
"@
    Set-Content -Path $sessionPath -Value $content -Encoding UTF8

    $taskEntry | Add-Member -NotePropertyName status -NotePropertyValue $Verdict -Force
    $taskEntry | Add-Member -NotePropertyName last_updated -NotePropertyValue (Get-Date -Format "yyyy-MM-dd") -Force
    if ($Verdict -eq "SOL_REJECTED") {
        $existingFlags = Get-Flags $taskEntry
        if ($existingFlags -notcontains "SOL_CASCADE_REVIEW_NEEDED") {
            $taskEntry | Add-Member -NotePropertyName flags -NotePropertyValue (@($existingFlags) + "SOL_CASCADE_REVIEW_NEEDED") -Force
        }
    }

    $state | Add-Member -NotePropertyName last_session -NotePropertyValue $lastSession -Force
    $state | Add-Member -NotePropertyName updated -NotePropertyValue (Get-Date -Format "yyyy-MM-dd") -Force
    $stateWritten = Save-StateJson $state $statePath

    $sdpSolution | Add-Member -NotePropertyName updated -NotePropertyValue (Get-Date -Format "yyyy-MM-dd") -Force
    $solutionWritten = Set-JsonFileWithRetry $sdpSolution $sdpSolutionPath 10

    if (-not $stateWritten -or -not $solutionWritten) {
        $r = [ordered]@{
            status                = "error"
            error                 = "Session file was written (.sdp-solution-workflow/sessions/$sessionFileName) but failed to persist state.json (written=$stateWritten) or SDP-Solution.json (written=$solutionWritten). Verify both files manually before retrying."
            session_file_written  = ".sdp-solution-workflow/sessions/$sessionFileName"
        }
        Write-Result $r
        exit 1
    }

    $completionMessage = if ($Verdict -eq "SOL_VERIFIED") {
        "Solution task '$taskId' is SOL_VERIFIED - all children verified and the cross-project integration check passed."
    } else {
        "Cross-project integration check failed for solution task '$taskId'. Solution task set to SOL_REJECTED. Cascade review required before any project advances."
    }

    Write-WorkflowLog "solution.finalize" "SOLUTION_REVIEWER" $Verdict $completionMessage

    $r = [ordered]@{
        status                    = "success"
        error                     = $null
        verdict                   = $Verdict
        active_solution_task      = $taskId
        session_file_written      = ".sdp-solution-workflow/sessions/$sessionFileName"
        completion_message        = $completionMessage
        state_json_written        = $stateWritten
        sdp_solution_json_written = $solutionWritten
    }
    Write-Result $r
    exit 0
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

switch ($Mode) {
    "Bootstrap" { Invoke-Bootstrap }
    "Confirm"   { Invoke-Confirm }
    "Finalize"  { Invoke-Finalize }
    default     { Exit-Error "Unknown -Mode '$Mode' - must be Bootstrap, Confirm, or Finalize." }
}
