<#
.SYNOPSIS
    Resolve the active SDP project, read sdp-docs/00_prompt.txt, identify the next
    skill to invoke, and output a JSON result for the sdp-project-run-prompt skill to act on.

.PARAMETER project
    Optional project path (relative to solution root). When provided, validated
    against SDP-Solution.json projects array (Level 0 resolution). When absent,
    resolved from last_active_projects[0] (Level 3).

.NOTES
    Reads:
      SDP-Solution.json                              (project resolution)
      [resolved_project]/sdp-docs/00_prompt.txt      (prompt file)
    Writes: nothing.
    Stdout: single-line JSON result object.
    Exit 0 on success, halted, or no-prompt; Exit 1 on error.
#>
param(
    [string]$project = ""
)

$solutionRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Write-Result([hashtable]$hash) {
    Write-Output ($hash | ConvertTo-Json -Compress)
}

# ---------------------------------------------------------------------------
# Read SDP-Solution.json
# ---------------------------------------------------------------------------

$sdpSolutionFile = Join-Path $solutionRoot "SDP-Solution.json"

if (-not (Test-Path $sdpSolutionFile)) {
    Write-Result @{
        status          = "error"
        resolvedProject = $null
        skillName       = $null
        selectionReason = $null
        error           = "SDP-Solution.json not found at solution root. Run the sdp-workspace-setup skill to create it before proceeding."
    }
    exit 1
}

$sdpSolution = $null
try {
    $sdpSolution = Get-Content $sdpSolutionFile -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    Write-Result @{
        status          = "error"
        resolvedProject = $null
        skillName       = $null
        selectionReason = $null
        error           = "Failed to parse SDP-Solution.json: $($_.Exception.Message)"
    }
    exit 1
}

# ---------------------------------------------------------------------------
# Project resolution
# ---------------------------------------------------------------------------

$resolvedProject = $null

if ($project) {
    # Level 0 — validate invocation argument against projects array
    $registered = @($sdpSolution.projects | ForEach-Object { $_.path })
    if ($registered -notcontains $project) {
        $available = $registered -join ", "
        Write-Result @{
            status          = "error"
            resolvedProject = $null
            skillName       = $null
            selectionReason = $null
            error           = "Invocation argument '$project' does not match any project registered in SDP-Solution.json. Available: $available. Correct the argument and retry."
        }
        exit 1
    }
    $resolvedProject = $project
} else {
    # Level 3 — last_active_projects[0], fallback to projects array
    $lastActive = if ($sdpSolution.last_active_projects -and
                      $sdpSolution.last_active_projects.Count -gt 0) {
        $sdpSolution.last_active_projects[0]
    } else { $null }

    if ($lastActive) {
        $resolvedProject = $lastActive
    } elseif ($sdpSolution.projects -and $sdpSolution.projects.Count -eq 1) {
        $resolvedProject = $sdpSolution.projects[0].path
    } elseif ($sdpSolution.projects -and $sdpSolution.projects.Count -gt 1) {
        $available = ($sdpSolution.projects | ForEach-Object { $_.path }) -join ", "
        Write-Result @{
            status          = "error"
            resolvedProject = $null
            skillName       = $null
            selectionReason = $null
            error           = "SDP-Solution.json last_active_projects is empty and multiple projects are registered: $available. Set last_active_projects and retry."
        }
        exit 1
    } else {
        Write-Result @{
            status          = "error"
            resolvedProject = $null
            skillName       = $null
            selectionReason = $null
            error           = "No projects registered in SDP-Solution.json. Register at least one project before proceeding."
        }
        exit 1
    }
}

# Resolve workspace path from project identifier
$workspaceRoot = if ($resolvedProject -and $resolvedProject -ne ".") {
    Join-Path $solutionRoot $resolvedProject
} else {
    $resolvedProject = "."
    $solutionRoot
}

# ---------------------------------------------------------------------------
# Halt check — authoritative source is state.json, not the prompt file
# ---------------------------------------------------------------------------

# The Halt Behavior Contract records a halt in .sdp-workflow/state.json's workflow_status/
# halt_reason fields, delivered to the user via banner — it never writes a "Workflow halted"
# marker into sdp-docs/00_prompt.txt's first line (the check further below predates that
# convention and is kept only as a harmless secondary check, never the primary one).
$projectStatePath = Join-Path $workspaceRoot ".sdp-workflow/state.json"
if (Test-Path $projectStatePath) {
    try {
        $projectState = Get-Content $projectStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($projectState.workflow_status -eq "halted") {
            $haltReason = if ($projectState.halt_reason) { $projectState.halt_reason } else { "No reason recorded" }
            Write-Result @{
                status          = "halted"
                resolvedProject = $resolvedProject
                skillName       = $null
                selectionReason = $null
                error           = "Workflow is halted - $haltReason. Resolve this condition before proceeding."
            }
            exit 0
        }
    } catch {
        # Unparseable state.json is not this check's concern — the prompt-read section below
        # will surface its own error if the workflow can't otherwise proceed.
    }
}

# ---------------------------------------------------------------------------
# Read prompt file
# ---------------------------------------------------------------------------

$promptRelPath = "$resolvedProject/sdp-docs/00_prompt.txt"
$promptPath    = Join-Path $workspaceRoot "sdp-docs\00_prompt.txt"

if (-not (Test-Path $promptPath)) {
    Write-Result @{
        status          = "no-prompt"
        resolvedProject = $resolvedProject
        skillName       = $null
        selectionReason = $null
        error           = "$promptRelPath is missing - no prompt to run. Run /sdp-project-create-prompt to generate one."
    }
    exit 0
}

$promptContent = $null
try {
    $promptContent = Get-Content $promptPath -Raw -Encoding UTF8
} catch {
    Write-Result @{
        status          = "error"
        resolvedProject = $resolvedProject
        skillName       = $null
        selectionReason = $null
        error           = "Failed to read ${promptRelPath}: $($_.Exception.Message)"
    }
    exit 1
}

if (-not $promptContent -or $promptContent.Trim().Length -eq 0) {
    Write-Result @{
        status          = "no-prompt"
        resolvedProject = $resolvedProject
        skillName       = $null
        selectionReason = $null
        error           = "$promptRelPath is empty - no prompt to run. Run /sdp-project-create-prompt to generate one."
    }
    exit 0
}

# ---------------------------------------------------------------------------
# Check for halted workflow marker
# ---------------------------------------------------------------------------

$firstLine = ($promptContent -split "`n")[0].Trim()
if ($firstLine -match 'Workflow halted') {
    $haltReason = if ($firstLine -match 'Workflow halted[:\s]+(.+)') {
        $Matches[1].Trim()
    } else { "No reason recorded" }
    Write-Result @{
        status          = "halted"
        resolvedProject = $resolvedProject
        skillName       = $null
        selectionReason = $null
        error           = "Workflow is halted - $haltReason. Resolve this condition before proceeding."
    }
    exit 0
}

# ---------------------------------------------------------------------------
# Parse sentinel — Level 1 project override
# ---------------------------------------------------------------------------

if ($firstLine -match '\[sdp-prompt[^\]]*\bprojects="([^"]+)"') {
    $sentinelProjects = $Matches[1]
    $firstProject     = ($sentinelProjects -split ",")[0].Trim()
    if ($firstProject) { $resolvedProject = $firstProject }
}

# ---------------------------------------------------------------------------
# Scan for skill invocation instructions
# ---------------------------------------------------------------------------

# Matches: Invoke (optional colon) whitespace backtick /sdp-<name> backtick
$invokePattern = 'Invoke:?\s*`/sdp-([a-z][a-z-]*)`'
$allMatches    = [regex]::Matches($promptContent, $invokePattern)

$distinctSkills = [System.Collections.Generic.List[string]]::new()
foreach ($m in $allMatches) {
    $name = $m.Groups[1].Value
    if (-not $distinctSkills.Contains($name)) { $distinctSkills.Add($name) }
}

if ($distinctSkills.Count -eq 0) {
    Write-Result @{
        status          = "error"
        resolvedProject = $resolvedProject
        skillName       = $null
        selectionReason = $null
        error           = "No skill invocation instruction found in $promptRelPath - cannot determine next action. Check the file or run /sdp-project-create-prompt to regenerate."
    }
    exit 1
}

if ($distinctSkills.Count -eq 1) {
    Write-Result @{
        status          = "success"
        resolvedProject = $resolvedProject
        skillName       = $distinctSkills[0]
        selectionReason = "one-match"
        error           = $null
    }
    exit 0
}

# Two or more distinct skills — locate Two Paths block and select first Invoke after it
$twoPathsMatch = [regex]::Match($promptContent, 'Two Paths')
if ($twoPathsMatch.Success) {
    $afterTwoPaths = $promptContent.Substring($twoPathsMatch.Index)
    $option1Match  = [regex]::Match($afterTwoPaths, $invokePattern)
    if ($option1Match.Success) {
        Write-Result @{
            status          = "success"
            resolvedProject = $resolvedProject
            skillName       = $option1Match.Groups[1].Value
            selectionReason = "two-option-auto"
            error           = $null
        }
        exit 0
    }
}

# Fallback — no Two Paths block found; use first distinct match
Write-Result @{
    status          = "success"
    resolvedProject = $resolvedProject
    skillName       = $distinctSkills[0]
    selectionReason = "two-option-auto"
    error           = $null
}
exit 0
