<#
.SYNOPSIS
    Read SDP-Solution.json and .sdp-solution-workflow/state.json, resolve authoritative
    child project statuses, enforce the cycle sync invariant, determine dispatch targets,
    write session files, and update both state files. Called by the sdp-solution-coordinator
    Level 2 skill; the LLM takes over after this script returns to invoke
    sdp-solution-create-prompt and dispatch subagents (Step 8.3 onward).

.NOTES
    Reads:
      SDP-Solution.json
      .sdp-solution-workflow/state.json
      [child.project]/.sdp-workflow/state.json      (fallback state-file derivation)
      [child.project]/[derived phase]_state.json    (authoritative child status)
      [child.project]/[child.phase_file]            (rejection / diagnosis-blocked text)
    Writes:
      .sdp-solution-workflow/sessions/session-NNN.md  (one per dispatched target)
      .sdp-solution-workflow/state.json               (last_session, cached_status
        corrections, updated; halt / cascade / all_verified transitions)
      SDP-Solution.json                               (last_active_projects, updated,
        active_solution_task on an all_verified transition)
    Side effect: on every halt, blocked (SOL_CASCADE_REVIEW_NEEDED / SOL_DIAGNOSIS_BLOCKED), and
      cascade outcome, invokes sdp-workflow-log.ps1 (non-blocking - any failure is swallowed) to
      record the event in the semantic workflow-log stream.
    Stdout: single-line JSON result object - contract documented in this script's calling
      skill, sdp-shared/ai-skills/sdp-solution-coordinator/SKILL.md.
    Exit codes: 0 = success, halt, blocked, cascade, or all_verified (all are expected,
      non-error terminal states the calling skill branches on); 1 = error (script could
      not complete the operation at all).
#>

$solutionRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Result([hashtable]$hash) {
    Write-Output ($hash | ConvertTo-Json -Compress -Depth 8)
}

function New-ResultBase {
    return [ordered]@{
        status                     = "success"
        error                      = $null
        halt_message               = $null
        blocking_flag              = $null
        blocking_flag_message      = $null
        cascade_messages           = @()
        completion_message         = $null
        active_solution_task       = $null
        workflow_status            = $null
        dispatch_mode              = $null
        sync_step                  = $null
        solution_reviewer_dispatch = $false
        laggards                   = @()
        last_session               = $null
        session_files_written      = @()
        bootstrap_doc               = $null
        state_json_written         = $false
        sdp_solution_json_written  = $false
    }
}

function Get-RelPath([string]$fullPath) {
    return $fullPath.Replace($solutionRoot, "").TrimStart("\").TrimStart("/").Replace("\", "/")
}

function Get-StatusOrdinal([string]$status) {
    switch ($status) {
        "PENDING"       { 0 }
        "WORK_COMPLETE" { 1 }
        "VERIFIED"      { 2 }
        default         { -1 }
    }
}

function Get-Flags($obj) {
    if ($obj -and $obj.PSObject.Properties['flags'] -and $obj.flags) { return @($obj.flags) }
    return @()
}

function Get-BootstrapDocName {
    $files = Get-ChildItem -Path $solutionRoot -Filter "SDP_Sapient-Driven-Principles_v*.md" -File -ErrorAction SilentlyContinue
    if (-not $files) { return $null }
    $best = $null; $bestVer = $null
    foreach ($f in $files) {
        if ($f.Name -match 'v(\d+)\.(\d+)\.(\d+)') {
            $ver = [version]"$($Matches[1]).$($Matches[2]).$($Matches[3])"
            if (-not $bestVer -or $ver -gt $bestVer) { $bestVer = $ver; $best = $f }
        }
    }
    if ($best) { return $best.Name }
    return $files[0].Name
}

function Get-UserDecisionNeededLine([string]$phaseFilePath) {
    if (-not (Test-Path $phaseFilePath)) { return $null }
    try { $content = Get-Content $phaseFilePath -Raw -Encoding UTF8 } catch { return $null }
    $m = [regex]::Matches($content, 'User decision needed:.*')
    if ($m.Count -gt 0) { return ($m[$m.Count - 1].Value).Trim() }
    return $null
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

function Write-HaltState($stateObj, [string]$path, [string]$reason) {
    $stateObj | Add-Member -NotePropertyName workflow_status -NotePropertyValue "halted" -Force
    $stateObj | Add-Member -NotePropertyName halt_reason -NotePropertyValue $reason -Force
    $stateObj | Add-Member -NotePropertyName updated -NotePropertyValue (Get-Date -Format "yyyy-MM-dd") -Force
    $written = Save-StateJson $stateObj $path
    Write-WorkflowLog "solution.halt" "SOLUTION_COORDINATOR" "halted" $reason
    return $written
}

function Exit-Halt($stateObj, [string]$statePath, [string]$reason) {
    $written = Write-HaltState $stateObj $statePath $reason
    $r = New-ResultBase
    $r.status = "halt"
    $r.workflow_status = "halted"
    $r.halt_message = "Solution halted - $reason. Resolve this condition and run sdp-solution-coordinator to resume."
    $r.state_json_written = $written
    Write-Result $r
    exit 0
}

function Exit-Error([string]$msg) {
    $r = New-ResultBase
    $r.status = "error"
    $r.error = $msg
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

$activeSolutionTask = $sdpSolution.active_solution_task
if (-not $activeSolutionTask) {
    Exit-Error "No active solution task - active_solution_task is null in SDP-Solution.json. Set an active solution task before running sdp-solution-coordinator."
}

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

$workflowStatus = if ($state.PSObject.Properties['workflow_status'] -and $state.workflow_status) { $state.workflow_status } else { "active" }
if ($workflowStatus -eq "halted") {
    $haltReason = if ($state.PSObject.Properties['halt_reason'] -and $state.halt_reason) { $state.halt_reason } else { "No halt reason recorded in state.json" }
    $r = New-ResultBase
    $r.status = "halt"
    $r.workflow_status = "halted"
    $r.halt_message = "Solution halted - $haltReason. Resolve this condition and run sdp-solution-coordinator to resume."
    Write-Result $r
    exit 0
}

function Get-TaskEntry($stateObj, [string]$taskId) {
    $tasks = @($stateObj.tasks)
    return ($tasks | Where-Object { $_.id -eq $taskId } | Select-Object -First 1)
}

$currentTaskId = $activeSolutionTask
$taskEntry = Get-TaskEntry $state $currentTaskId
if (-not $taskEntry) {
    Exit-Halt $state $statePath "No task entry for '$currentTaskId' found in .sdp-solution-workflow/state.json. State file may be out of sync with SDP-Solution.json - verify both files."
}

$lastSession = if ($state.PSObject.Properties['last_session'] -and $state.last_session) { [int]$state.last_session } else { 0 }

# ---------------------------------------------------------------------------
# Step 4: Check blocking flags (evaluated once, for the initially active task only)
# ---------------------------------------------------------------------------

$initialFlags = Get-Flags $taskEntry

if ($initialFlags -contains "SOL_CASCADE_REVIEW_NEEDED") {
    $blockMsg = "Solution task '$currentTaskId' is frozen pending cascade review - SOL_CASCADE_REVIEW_NEEDED flag is set. A prior rejection in one project may affect other involved projects. Confirm cascade scope, resolve the rejection, and clear the flag before resuming dispatch."
    Write-WorkflowLog "solution.blocked" "SOLUTION_COORDINATOR" "SOL_CASCADE_REVIEW_NEEDED" $blockMsg
    $r = New-ResultBase
    $r.status = "blocked"
    $r.active_solution_task = $currentTaskId
    $r.blocking_flag = "SOL_CASCADE_REVIEW_NEEDED"
    $r.blocking_flag_message = $blockMsg
    Write-Result $r
    exit 0
}

if ($initialFlags -contains "SOL_DIAGNOSIS_BLOCKED") {
    $blockedDesc = $null
    foreach ($c in @($taskEntry.children)) {
        $childProject = $c.project
        $childPhaseFile = $c.phase_file
        if ($childPhaseFile) {
            $phaseFileFull = Join-Path (Join-Path $solutionRoot $childProject) $childPhaseFile
            $line = Get-UserDecisionNeededLine $phaseFileFull
            if ($line) { $blockedDesc = "'$($c.task_id)' in '$childProject' has a blocked diagnosis - $line"; break }
        }
    }
    if (-not $blockedDesc) { $blockedDesc = "A child project in solution task '$currentTaskId' has a blocked diagnosis" }
    $blockMsg = "$blockedDesc. Provide direction before the solution task can continue."
    Write-WorkflowLog "diagnosis.blocked" "SOLUTION_COORDINATOR" "SOL_DIAGNOSIS_BLOCKED" $blockMsg
    $r = New-ResultBase
    $r.status = "blocked"
    $r.active_solution_task = $currentTaskId
    $r.blocking_flag = "SOL_DIAGNOSIS_BLOCKED"
    $r.blocking_flag_message = $blockMsg
    Write-Result $r
    exit 0
}

# ---------------------------------------------------------------------------
# Step 3: Resolve authoritative child statuses for a given task entry
# ---------------------------------------------------------------------------

function Resolve-Children($taskEntryObj, [string]$taskId, $stateObj, [string]$statePathLocal) {
    $enriched = @()
    $children = @($taskEntryObj.children)

    if ($children.Count -eq 0) {
        Exit-Halt $stateObj $statePathLocal "Solution task '$taskId' has no children listed in .sdp-solution-workflow/state.json - cannot determine dispatch."
    }

    foreach ($child in $children) {
        $childProject   = $child.project
        $childTaskId    = $child.task_id
        $childPhaseFile = $child.phase_file
        $cachedStatus   = if ($child.PSObject.Properties['cached_status']) { $child.cached_status } else { $null }

        $childStateFile = $null

        if ($childPhaseFile) {
            $docDir        = ($childPhaseFile -replace '\\', '/')
            $docDir        = Split-Path -Parent $docDir
            $phaseBaseName = [System.IO.Path]::GetFileNameWithoutExtension($childPhaseFile)
            $candidateDir  = Join-Path (Join-Path $solutionRoot $childProject) ("$($docDir)_Phases")
            $candidateFile = Join-Path $candidateDir "$($phaseBaseName)_state.json"
            if (Test-Path $candidateFile) { $childStateFile = $candidateFile }
        }

        if (-not $childStateFile) {
            $childWorkflowState = Join-Path (Join-Path $solutionRoot $childProject) ".sdp-workflow/state.json"
            if (Test-Path $childWorkflowState) {
                try {
                    $cws = Get-Content $childWorkflowState -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ($cws.active_phase_file) {
                        $derived = Join-Path (Join-Path $solutionRoot $childProject) ($cws.active_phase_file -replace '\.md$', '_state.json')
                        if (Test-Path $derived) { $childStateFile = $derived }
                    }
                } catch { }
            }
        }

        if (-not $childStateFile -or -not (Test-Path $childStateFile)) {
            Exit-Halt $stateObj $statePathLocal "Cannot read child state file for '$childProject' ('$childTaskId') - file not found or unreadable. Verify the project is correctly initialized."
        }

        try {
            $childState = Get-Content $childStateFile -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            Exit-Halt $stateObj $statePathLocal "Cannot parse child state file for '$childProject' ('$childTaskId') at '$(Get-RelPath $childStateFile)': $($_.Exception.Message)"
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
            Exit-Halt $stateObj $statePathLocal "Task entry '$childTaskId' not found in child state file for '$childProject' ($(Get-RelPath $childStateFile))."
        }

        $authStatus = $childTaskEntry.status
        $wasStale = [bool]($cachedStatus -and ($authStatus -ne $cachedStatus))

        $enriched += [ordered]@{
            project                 = $childProject
            task_id                 = $childTaskId
            phase_file              = $childPhaseFile
            state_file              = (Get-RelPath $childStateFile)
            authoritative_status    = $authStatus
            cached_status_was_stale = $wasStale
        }
    }

    return $enriched
}

# ---------------------------------------------------------------------------
# Step 5 (looped for the all_verified -> queued task re-entry case) and Step 9
# ---------------------------------------------------------------------------

$dispatchMode             = $null
$laggardChildren          = $null
$solutionReviewerDispatch = $false
$syncStepName             = $null
$enrichedChildren         = $null

while ($true) {

    $dispatchMode = if ($taskEntry.PSObject.Properties['dispatch_mode'] -and $taskEntry.dispatch_mode) { $taskEntry.dispatch_mode } else { "synced" }
    $enrichedChildren = Resolve-Children $taskEntry $currentTaskId $state $statePath

    # 5.1 - Cascade check
    $rejected = $enrichedChildren | Where-Object { $_.authoritative_status -eq "REJECTED" }
    if ($rejected.Count -gt 0) {
        $cascadeMessages = @()
        foreach ($rc in $rejected) {
            $phaseFileFull = Join-Path (Join-Path $solutionRoot $rc.project) $rc.phase_file
            $summary = Get-RejectionSummary $phaseFileFull
            $cascadeMessages += "'$($rc.task_id)' in '$($rc.project)' was rejected - $summary. Cascade review required before any other project in this solution task advances. Confirm cascade scope and resolve the rejection before resuming."
        }

        $existingFlags = Get-Flags $taskEntry
        if ($existingFlags -notcontains "SOL_CASCADE_REVIEW_NEEDED") {
            $taskEntry | Add-Member -NotePropertyName flags -NotePropertyValue (@($existingFlags) + "SOL_CASCADE_REVIEW_NEEDED") -Force
        }
        $state | Add-Member -NotePropertyName updated -NotePropertyValue (Get-Date -Format "yyyy-MM-dd") -Force
        $written = Save-StateJson $state $statePath
        Write-WorkflowLog "solution.cascade" "SOLUTION_COORDINATOR" "SOL_CASCADE_REVIEW_NEEDED" ($cascadeMessages -join " | ")

        $r = New-ResultBase
        $r.status = "cascade"
        $r.active_solution_task = $currentTaskId
        $r.cascade_messages = $cascadeMessages
        $r.state_json_written = $written
        Write-Result $r
        exit 0
    }

    # 5.2 - All-WORK_COMPLETE check
    $allWorkComplete = -not ($enrichedChildren | Where-Object { $_.authoritative_status -ne "WORK_COMPLETE" })
    if ($allWorkComplete) {
        $solutionReviewerDispatch = $true
        $laggardChildren = $enrichedChildren
        $syncStepName = "WORK_COMPLETE"
        break
    }

    # 5.3 - All-VERIFIED check
    $allVerified = -not ($enrichedChildren | Where-Object { $_.authoritative_status -ne "VERIFIED" })
    if ($allVerified) {
        $taskEntry | Add-Member -NotePropertyName status -NotePropertyValue "SOL_VERIFIED" -Force
        $state | Add-Member -NotePropertyName updated -NotePropertyValue (Get-Date -Format "yyyy-MM-dd") -Force

        $queued = @($state.tasks) | Where-Object { $_.id -ne $currentTaskId -and $_.status -eq "SOL_PENDING" } | Select-Object -First 1

        if ($queued) {
            $state | Add-Member -NotePropertyName active_solution_task -NotePropertyValue $queued.id -Force
            $sdpSolution | Add-Member -NotePropertyName active_solution_task -NotePropertyValue $queued.id -Force
            $sdpSolution | Add-Member -NotePropertyName updated -NotePropertyValue (Get-Date -Format "yyyy-MM-dd") -Force
            $stateWritten = Save-StateJson $state $statePath
            $solutionWritten = Set-JsonFileWithRetry $sdpSolution $sdpSolutionPath 10

            if (-not $stateWritten -or -not $solutionWritten) {
                Exit-Error "Solution task '$currentTaskId' reached SOL_VERIFIED but failed to persist the transition to queued task '$($queued.id)'. Verify .sdp-solution-workflow/state.json and SDP-Solution.json manually before retrying."
            }

            $currentTaskId = $queued.id
            $taskEntry = Get-TaskEntry $state $currentTaskId
            if (-not $taskEntry) {
                Exit-Halt $state $statePath "Queued task '$currentTaskId' not found in .sdp-solution-workflow/state.json immediately after selection - state file is inconsistent."
            }
            continue
        } else {
            $state | Add-Member -NotePropertyName active_solution_task -NotePropertyValue $null -Force
            $sdpSolution | Add-Member -NotePropertyName active_solution_task -NotePropertyValue $null -Force
            $sdpSolution | Add-Member -NotePropertyName updated -NotePropertyValue (Get-Date -Format "yyyy-MM-dd") -Force
            $stateWritten = Save-StateJson $state $statePath
            $solutionWritten = Set-JsonFileWithRetry $sdpSolution $sdpSolutionPath 10

            $r = New-ResultBase
            $r.status = "all_verified"
            $r.active_solution_task = $null
            $r.completion_message = "Solution task '$currentTaskId' is SOL_VERIFIED. No queued tasks remain - the solution workflow is complete."
            $r.state_json_written = $stateWritten
            $r.sdp_solution_json_written = $solutionWritten
            Write-Result $r
            exit 0
        }
    }

    # 5.4 / 5.5 - Sync step identification and laggards
    $ordinals    = $enrichedChildren | ForEach-Object { Get-StatusOrdinal $_.authoritative_status }
    $syncOrdinal = ($ordinals | Measure-Object -Minimum).Minimum
    $syncStepName = switch ($syncOrdinal) { 0 { "PENDING" } 1 { "WORK_COMPLETE" } 2 { "VERIFIED" } default { "UNKNOWN" } }
    $laggardChildren = $enrichedChildren | Where-Object { (Get-StatusOrdinal $_.authoritative_status) -eq $syncOrdinal }
    break
}

# ---------------------------------------------------------------------------
# Step 6 + 7: Determine dispatch targets and write session files
# ---------------------------------------------------------------------------

$sessionDir = Join-Path $solutionRoot ".sdp-solution-workflow/sessions"
if (-not (Test-Path $sessionDir)) { New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null }

$bootstrapDoc        = Get-BootstrapDocName
$sessionFilesWritten = @()
$dispatchedProjects  = @()
$resultLaggards      = @()

if ($solutionReviewerDispatch) {
    $lastSession++
    $nnn             = "{0:D3}" -f $lastSession
    $sessionFileName = "session-$nnn.md"
    $sessionPath     = Join-Path $sessionDir $sessionFileName
    $projectsList    = ($laggardChildren | ForEach-Object { $_.project }) -join ", "

    $content = @"
Role: SOLUTION_REVIEWER
Projects: $projectsList
Work Item: $currentTaskId
Solution Task: $currentTaskId
Bootstrap Doc: $bootstrapDoc
Solution State File: .sdp-solution-workflow/state.json
Instruction: Invoke ``/sdp-solution-reviewer``
Parent Task: $currentTaskId
"@
    Set-Content -Path $sessionPath -Value $content -Encoding UTF8
    $sessionFilesWritten += ".sdp-solution-workflow/sessions/$sessionFileName"
    $dispatchedProjects = @($laggardChildren | ForEach-Object { $_.project })

    foreach ($lc in $laggardChildren) {
        $resultLaggards += [ordered]@{
            task_id                 = $lc.task_id
            project                 = $lc.project
            phase_file              = "$($lc.project)/$($lc.phase_file)"
            state_file              = $lc.state_file
            authoritative_status    = $lc.authoritative_status
            cached_status_was_stale = $lc.cached_status_was_stale
            dispatch_role           = "SOLUTION_REVIEWER"
        }
    }
} else {
    foreach ($lc in $laggardChildren) {
        $role = if ($lc.authoritative_status -eq "PENDING") { "WORKER" } else { "REVIEWER" }
        $lastSession++
        $nnn             = "{0:D3}" -f $lastSession
        $sessionFileName = "session-$nnn.md"
        $sessionPath     = Join-Path $sessionDir $sessionFileName
        $instr           = if ($role -eq "WORKER") { "Invoke ``/sdp-project-worker``" } else { "Invoke ``/sdp-project-reviewer``" }

        $content = @"
Role: $role
Project: $($lc.project)
Work Item: $($lc.task_id)
Solution Task: $currentTaskId
Bootstrap Doc: $bootstrapDoc
Phase File: $($lc.project)/$($lc.phase_file)
State File: $($lc.project)/.sdp-workflow/state.json
Solution State File: .sdp-solution-workflow/state.json
Instruction: $instr
Parent Task: $currentTaskId
"@
        Set-Content -Path $sessionPath -Value $content -Encoding UTF8
        $sessionFilesWritten += ".sdp-solution-workflow/sessions/$sessionFileName"
        $dispatchedProjects += $lc.project

        $resultLaggards += [ordered]@{
            task_id                 = $lc.task_id
            project                 = $lc.project
            phase_file              = "$($lc.project)/$($lc.phase_file)"
            state_file              = $lc.state_file
            authoritative_status    = $lc.authoritative_status
            cached_status_was_stale = $lc.cached_status_was_stale
            dispatch_role           = $role
        }
    }
}

# ---------------------------------------------------------------------------
# Step 8.1 - 8.2: Update state.json and SDP-Solution.json
# ---------------------------------------------------------------------------

foreach ($rawChild in @($taskEntry.children)) {
    $match = $enrichedChildren | Where-Object { $_.project -eq $rawChild.project -and $_.task_id -eq $rawChild.task_id }
    if ($match -and $match.cached_status_was_stale) {
        $rawChild | Add-Member -NotePropertyName cached_status -NotePropertyValue $match.authoritative_status -Force
    }
}

$state | Add-Member -NotePropertyName last_session -NotePropertyValue $lastSession -Force
$state | Add-Member -NotePropertyName updated -NotePropertyValue (Get-Date -Format "yyyy-MM-dd") -Force
$stateWritten = Save-StateJson $state $statePath

$sdpSolution | Add-Member -NotePropertyName last_active_projects -NotePropertyValue @($dispatchedProjects | Select-Object -Unique) -Force
$sdpSolution | Add-Member -NotePropertyName updated -NotePropertyValue (Get-Date -Format "yyyy-MM-dd") -Force
$solutionWritten = Set-JsonFileWithRetry $sdpSolution $sdpSolutionPath 10

if (-not $stateWritten -or -not $solutionWritten) {
    $r = New-ResultBase
    $r.status = "error"
    $r.error = "Session files were written ($($sessionFilesWritten -join ', ')) but failed to persist state.json (written=$stateWritten) or SDP-Solution.json (written=$solutionWritten). Verify both files manually before dispatching."
    $r.session_files_written = $sessionFilesWritten
    $r.state_json_written = $stateWritten
    $r.sdp_solution_json_written = $solutionWritten
    Write-Result $r
    exit 1
}

# ---------------------------------------------------------------------------
# Output result
# ---------------------------------------------------------------------------

$r = New-ResultBase
$r.status = "success"
$r.active_solution_task = $currentTaskId
$r.workflow_status = "active"
$r.dispatch_mode = $dispatchMode
$r.sync_step = $syncStepName
$r.solution_reviewer_dispatch = $solutionReviewerDispatch
$r.laggards = $resultLaggards
$r.last_session = $lastSession
$r.session_files_written = $sessionFilesWritten
$r.bootstrap_doc = $bootstrapDoc
$r.state_json_written = $true
$r.sdp_solution_json_written = $true
Write-Result $r
exit 0
