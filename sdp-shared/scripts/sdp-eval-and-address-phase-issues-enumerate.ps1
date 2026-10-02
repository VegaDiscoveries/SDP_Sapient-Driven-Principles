<#
.SYNOPSIS
    Enumerate every phase document in scope for sdp-eval-and-address-phase-issues: either the
    full solution-plus-project registry walk (whole-sweep mode), or a single named phase document
    (single-task mode, used by sdp-solution-phase-coordinator's Accepted Variance trigger).

.PARAMETER workspaceRoot
    Path to the solution root. Defaults to two levels above this script (sdp-shared/scripts/),
    matching the sdp-tone.ps1 convention. This script is solution-root scoped -- it enumerates
    every project from SDP-Solution.json itself rather than being told a single project to
    operate on.

.PARAMETER PhaseFile
    Single-task mode trigger. When supplied, this is the bare Phase File value (relative to
    sdp-solution-docs/, no prefix -- same convention sdp-solution-phase-coordinator's own
    registry.md reads already use) for exactly one solution-scoped phase document. Mutually
    exclusive with ProjectFilter/SolutionOnly -- when present, the whole-sweep enumeration below
    is skipped entirely and the single resolved document is the only output entry.

.PARAMETER TaskId
    Single-task mode only. Passed through unchanged into the output envelope for the calling
    skill's own use (this script does not validate it against the phase document's content --
    that is the extraction script's job).

.PARAMETER ProjectFilter
    Whole-sweep mode only. Restricts enumeration to the named project's own
    .sdp-workflow/registry.md, skipping the solution-level registry and every other project.

.PARAMETER SolutionOnly
    Whole-sweep mode only. Restricts enumeration to .sdp-solution-workflow/registry.md, skipping
    every project. Mutually exclusive with ProjectFilter.

.NOTES
    Stdout: single-line JSON result object (agent-consumed script per SDP-Script-Authoring.md).
    Exit codes: always 0 -- a missing registry or an empty result is a reported condition in the
    JSON (status/anomalies), never a script failure, matching the sibling
    sdp-report-workflow-analysis-*.ps1 family's actual exit convention.
    Project-level phase document paths (`[project]/sdp-docs/[phaseFile]`) are resolved by
    direct analogy to the confirmed solution-level convention
    (`sdp-solution-docs/[phaseFile]`) -- SDP-Workspace-Setup.md documents the registry.md schema
    as "identical shape" between solution and project scope, but no populated project-level
    registry.md has been inspected directly to confirm this path convention against a real
    example. Flagged here, not silently assumed correct.
#>
param(
    [string]$workspaceRoot = "",
    [string]$PhaseFile = "",
    [string]$TaskId = "",
    [string]$ProjectFilter = "",
    [switch]$SolutionOnly
)

function Write-Result([hashtable]$hash) {
    Write-Output ($hash | ConvertTo-Json -Compress -Depth 12)
}

if (-not $workspaceRoot) {
    $workspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

function Get-RegistryRows([string]$registryPath) {
    if (-not (Test-Path $registryPath)) { return @() }
    $lines = Get-Content $registryPath -Encoding UTF8
    $rows = @()
    $sawSeparator = $false
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if (-not $trimmed.StartsWith("|")) { continue }
        $inner = $trimmed.Trim("|")
        if ($inner -match '^[\s\-:|]+$') { $sawSeparator = $true; continue }
        if (-not $sawSeparator) { continue }
        # Columns, in order, per SDP-Workspace-Setup.md's registry.md template:
        # | # | Phase | Phase File | Status | Session | Depends On |
        $cells = $trimmed.Trim("|") -split '\|' | ForEach-Object { $_.Trim() }
        if ($cells.Count -lt 3) { continue }
        $rows += @{
            number    = $cells[0]
            phase     = $cells[1]
            phaseFile = $cells[2]
            status    = if ($cells.Count -gt 3) { $cells[3] } else { "" }
        }
    }
    return $rows
}

function New-DocEntry([string]$scope, [string]$phaseName, [string]$phaseFile, [string]$docPrefix) {
    $statePath = $phaseFile -replace '\.md$', '_state.json'
    return @{
        scope          = $scope
        phaseName      = $phaseName
        phaseFile      = $phaseFile
        phaseDocPath   = "$docPrefix$phaseFile"
        phaseStatePath = "$docPrefix$statePath"
    }
}

# --- Single-task mode ---
if ($PhaseFile) {
    $docPath = Join-Path $workspaceRoot "sdp-solution-docs/$PhaseFile"
    if (-not (Test-Path $docPath)) {
        Write-Result @{
            status = "error"
            error  = "single-task mode: phase document not found at sdp-solution-docs/$PhaseFile"
        }
        exit 0
    }
    $entry = New-DocEntry "solution" $PhaseFile $PhaseFile "sdp-solution-docs/"
    Write-Result @{
        status         = "success"
        singleTaskMode = $true
        taskId         = $TaskId
        documents      = @($entry)
        documentCount  = 1
    }
    exit 0
}

# --- Whole-sweep mode ---
$documents = @()
$anomalies = @{
    solutionRegistryMissing = $false
    projectRegistriesMissing = @()
}

if (-not $ProjectFilter) {
    $solutionRegistryPath = Join-Path $workspaceRoot ".sdp-solution-workflow/registry.md"
    if (Test-Path $solutionRegistryPath) {
        foreach ($row in (Get-RegistryRows $solutionRegistryPath)) {
            if (-not $row.phaseFile) { continue }
            $documents += New-DocEntry "solution" $row.phase $row.phaseFile "sdp-solution-docs/"
        }
    } else {
        $anomalies.solutionRegistryMissing = $true
    }
}

if (-not $SolutionOnly) {
    $solutionJsonPath = Join-Path $workspaceRoot "SDP-Solution.json"
    if (Test-Path $solutionJsonPath) {
        try {
            $solutionJson = [string](Get-Content $solutionJsonPath -Raw -Encoding UTF8) | ConvertFrom-Json
            foreach ($project in @($solutionJson.projects)) {
                if (-not $project) { continue }
                $projectName = [string]$project.name
                $projectPath = [string]$project.path
                if ($ProjectFilter -and $projectName -ne $ProjectFilter) { continue }
                $projRegistryPath = Join-Path $workspaceRoot (Join-Path $projectPath ".sdp-workflow/registry.md")
                if (-not (Test-Path $projRegistryPath)) {
                    $anomalies.projectRegistriesMissing += $projectName
                    continue
                }
                foreach ($row in (Get-RegistryRows $projRegistryPath)) {
                    if (-not $row.phaseFile) { continue }
                    $documents += New-DocEntry $projectName $row.phase $row.phaseFile "$projectPath/sdp-docs/"
                }
            }
        } catch {
            $anomalies.solutionJsonParseError = $_.Exception.Message
        }
    } else {
        $anomalies.solutionJsonMissing = $true
    }
}

Write-Result @{
    status        = "success"
    singleTaskMode = $false
    documents     = $documents
    documentCount = $documents.Count
    anomalies     = $anomalies
}
exit 0
