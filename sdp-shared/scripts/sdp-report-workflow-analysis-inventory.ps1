<#
.SYNOPSIS
    Count design docs processed, phase-1-7 cycles, and registry rows (solution-level and
    per-project) for the sdp-report-workflow-analysis report.

.PARAMETER workspaceRoot
    Path to the solution root. Defaults to two levels above this script
    (sdp-shared/scripts/), matching the sdp-tone.ps1 convention. This script is solution-root
    scoped -- it enumerates every project from SDP-Solution.json itself rather than being told
    a single project to operate on.

.NOTES
    Stdout: single-line JSON result object (agent-consumed script per SDP-Script-Authoring.md).
    Exit codes: 0 = success or a handled condition reported inside the JSON; 1 reserved for an
    operational failure that prevented any JSON from being written at all.
#>
param(
    [string]$workspaceRoot = ""
)

function Write-Result([hashtable]$hash) {
    Write-Output ($hash | ConvertTo-Json -Compress -Depth 12)
}

if (-not $workspaceRoot) {
    $workspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

function Count-RegistryRows([string]$registryPath) {
    if (-not (Test-Path $registryPath)) {
        return $null
    }
    $lines = Get-Content $registryPath -Encoding UTF8
    $total = 0
    $complete = 0
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if (-not $trimmed.StartsWith("|")) { continue }
        # Skip header separator rows: only |, -, :, and whitespace between pipes.
        $inner = $trimmed.Trim("|")
        if ($inner -match '^[\s\-:|]+$') { continue }
        # Skip the header row itself: first data-looking row after a separator is real data,
        # but the header text row (e.g. "| Phase | ... |") has no separator characteristics
        # either -- distinguish by checking the NEXT line is a separator. Simpler and robust:
        # a header row's first cell is a label, not a phase identifier; SDP registries always
        # place the separator row immediately after the header, so require this row to not be
        # immediately followed-by-itself-being the first table row without a preceding separator.
        $total++
        if ($trimmed -match '\[x\]' -or $trimmed -match '\[X\]') { $complete++ }
    }
    # The above counts the header text row as a data row (it contains no brackets, so it never
    # increments $complete, but it does increment $total by one). Subtract exactly one header
    # row if at least one row was found and a separator row exists in the file.
    $hasSeparator = $false
    foreach ($line in $lines) {
        $t = $line.Trim()
        if ($t.StartsWith("|")) {
            $inner = $t.Trim("|")
            if ($inner -match '^[\s\-:|]+$') { $hasSeparator = $true; break }
        }
    }
    if ($hasSeparator -and $total -gt 0) { $total = $total - 1 }
    return @{ totalRows = $total; completeRows = $complete }
}

$result = @{
    status = "success"
    solutionName = $null
    designDocsProcessed = 0
    phaseCycles = @()
    solutionRegistry = $null
    projects = @()
    anomalies = @{
        missingSolutionRegistry = $false
        projectsMissingRegistry = @()
        solutionJsonMissing = $false
    }
}

$solutionJsonPath = Join-Path $workspaceRoot "SDP-Solution.json"
if (-not (Test-Path $solutionJsonPath)) {
    $result.anomalies.solutionJsonMissing = $true
    Write-Result $result
    exit 0
}

try {
    $solutionJson = [string](Get-Content $solutionJsonPath -Raw -Encoding UTF8) | ConvertFrom-Json
} catch {
    Write-Result @{ status = "error"; error = "failed to parse SDP-Solution.json: $($_.Exception.Message)" }
    exit 0
}

$result.solutionName = [string]$solutionJson.solution_name

$processedDir = Join-Path $workspaceRoot "sdp-solution-docs/user-design-docs/processed"
if (Test-Path $processedDir) {
    $result.designDocsProcessed = (Get-ChildItem -Path $processedDir -File -ErrorAction SilentlyContinue | Measure-Object).Count
}

$solutionDocsDir = Join-Path $workspaceRoot "sdp-solution-docs"
if (Test-Path $solutionDocsDir) {
    $cycleDirs = Get-ChildItem -Path $solutionDocsDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d{3}-.+' }
    foreach ($cycleDir in $cycleDirs) {
        $phaseFiles = @(Get-ChildItem -Path $cycleDir.FullName -Filter "*_state.json" -File -ErrorAction SilentlyContinue)
        $result.phaseCycles += @{
            name = $cycleDir.Name
            path = $cycleDir.FullName.Substring($workspaceRoot.Length).TrimStart("\", "/")
            phaseStateFileCount = $phaseFiles.Count
        }
    }
}

$registryPath = Join-Path $workspaceRoot ".sdp-solution-workflow/registry.md"
$registryCounts = Count-RegistryRows $registryPath
if ($null -eq $registryCounts) {
    $result.anomalies.missingSolutionRegistry = $true
} else {
    $result.solutionRegistry = @{
        path = ".sdp-solution-workflow/registry.md"
        totalRows = $registryCounts.totalRows
        completeRows = $registryCounts.completeRows
    }
}

foreach ($project in @($solutionJson.projects)) {
    if (-not $project) { continue }
    $projectName = [string]$project.name
    $projectPath = [string]$project.path
    $projectRegistryPath = Join-Path $workspaceRoot (Join-Path $projectPath ".sdp-workflow/registry.md")
    $projCounts = Count-RegistryRows $projectRegistryPath
    if ($null -eq $projCounts) {
        $result.anomalies.projectsMissingRegistry += $projectName
        $result.projects += @{
            name = $projectName
            path = $projectPath
            registryPath = $null
            totalRows = 0
            completeRows = 0
        }
    } else {
        $result.projects += @{
            name = $projectName
            path = $projectPath
            registryPath = "$projectPath/.sdp-workflow/registry.md"
            totalRows = $projCounts.totalRows
            completeRows = $projCounts.completeRows
        }
    }
}

Write-Result $result
exit 0
