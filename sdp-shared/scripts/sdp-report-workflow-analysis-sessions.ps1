<#
.SYNOPSIS
    Enumerate every session-NNN.md file across the solution's own phases-1-7 sessions folder and
    every registered project's sessions folder, extract the fixed header fields (Date, Role, Work
    Item, Dispatched By) and the Session Outcome status transition, and assign a mechanical draft
    category from a fixed, SDP-state-derived rule table. Draft categories are a coarse signal only
    -- report assembly later runs an independent, blind agent classification pass and reconciles
    it against this draft, per sdp-report-workflow-analysis's own procedure.

.PARAMETER workspaceRoot
    Path to the solution root. Defaults to two levels above this script
    (sdp-shared/scripts/), matching the sdp-tone.ps1 convention.

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

function Get-DraftCategory([string]$role, [string]$statusFrom, [string]$statusTo) {
    $r = ($role -as [string])
    if ($r) { $r = $r.Trim().ToUpperInvariant() }
    switch -Regex ($r) {
        "COORDINATOR" { return "Coordination / Dispatch" }
        "GATE_REVIEWER" {
            if ($statusTo -match "PASSED") { return "Gate Review - Passed" }
            if ($statusTo -match "BLOCKED") { return "Gate Review - Blocked" }
            return "Gate Review - Other"
        }
        "REVIEWER" {
            if ($statusTo -match "VERIFIED") { return "Independent Evaluation - Pass" }
            if ($statusTo -match "REJECTED") { return "Independent Evaluation - Rejected" }
            return "Independent Evaluation - Other"
        }
        "WORKER" {
            if ($statusFrom -match "REJECTED") { return "Rework / Correction" }
            return "Initial Implementation"
        }
        default { return "Other / Uncategorized" }
    }
}

function Get-SessionsFromDir([string]$dir, [string]$sourceLabel, [ref]$sessions, [ref]$unparseable) {
    if (-not (Test-Path $dir)) { return 0 }
    $files = Get-ChildItem -Path $dir -Filter "session-*.md" -File -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        try {
            $content = [string](Get-Content $f.FullName -Raw -Encoding UTF8)
        } catch {
            $unparseable.Value += $f.FullName
            continue
        }
        $date = [regex]::Match($content, '(?m)^Date:\s*(.+)$').Groups[1].Value.Trim()
        $role = [regex]::Match($content, '(?m)^Role:\s*(.+)$').Groups[1].Value.Trim()
        $workItem = [regex]::Match($content, '(?m)^Work Item:\s*(.+)$').Groups[1].Value.Trim()
        $dispatchedBy = [regex]::Match($content, '(?m)^Dispatched By:\s*(.+)$').Groups[1].Value.Trim()
        # The unicode arrow (code point 0x2192) is built at runtime from an ASCII hex literal,
        # never embedded as a literal multi-byte character in this source file -- a no-BOM .ps1
        # parses as the ANSI codepage under Windows PowerShell 5.1, and a literal non-ASCII
        # character corrupts and breaks parsing. See SDP-Script-Authoring.md's ASCII-only-source
        # rule and sdp-github.ps1's own em-dash lesson.
        $arrowChar = [char]0x2192
        $transitionPattern = '(?m)^Status transition:\s*(\S+)\s*(?:->|' + $arrowChar + ')\s*(\S+)'
        $transitionMatch = [regex]::Match($content, $transitionPattern)
        $statusFrom = $null
        $statusTo = $null
        if ($transitionMatch.Success) {
            $statusFrom = $transitionMatch.Groups[1].Value.Trim()
            $statusTo = $transitionMatch.Groups[2].Value.Trim()
        }
        if (-not $role) {
            $unparseable.Value += $f.FullName
        }
        $draftCategory = Get-DraftCategory $role $statusFrom $statusTo
        $sessions.Value += @{
            file = $f.FullName.Substring($workspaceRoot.Length).TrimStart("\", "/")
            source = $sourceLabel
            date = $date
            role = $role
            workItem = $workItem
            dispatchedBy = $dispatchedBy
            statusFrom = $statusFrom
            statusTo = $statusTo
            draftCategory = $draftCategory
        }
    }
    return $files.Count
}

$sessions = @()
$unparseable = @()
$bySource = @()

$solutionSessionsDir = Join-Path $workspaceRoot ".sdp-solution-workflow/sessions"
$solutionCount = Get-SessionsFromDir $solutionSessionsDir "solution" ([ref]$sessions) ([ref]$unparseable)
if ($solutionCount -gt 0) {
    $bySource += @{ source = "solution"; path = ".sdp-solution-workflow/sessions"; count = $solutionCount }
}

$solutionJsonPath = Join-Path $workspaceRoot "SDP-Solution.json"
if (Test-Path $solutionJsonPath) {
    try {
        $solutionJson = [string](Get-Content $solutionJsonPath -Raw -Encoding UTF8) | ConvertFrom-Json
        foreach ($project in @($solutionJson.projects)) {
            if (-not $project) { continue }
            $projectName = [string]$project.name
            $projectPath = [string]$project.path
            $projSessionsDir = Join-Path $workspaceRoot (Join-Path $projectPath ".sdp-workflow/sessions")
            $projCount = Get-SessionsFromDir $projSessionsDir $projectName ([ref]$sessions) ([ref]$unparseable)
            if ($projCount -gt 0) {
                $bySource += @{ source = $projectName; path = "$projectPath/.sdp-workflow/sessions"; count = $projCount }
            }
        }
    } catch {
        # SDP-Solution.json parse failure here is non-fatal to the sessions count already
        # gathered from the solution-level folder; surfaced via anomalies below.
    }
}

$draftCategoryCounts = @{}
foreach ($s in $sessions) {
    $cat = $s.draftCategory
    if ($draftCategoryCounts.ContainsKey($cat)) {
        $draftCategoryCounts[$cat] = $draftCategoryCounts[$cat] + 1
    } else {
        $draftCategoryCounts[$cat] = 1
    }
}

$result = @{
    status = "success"
    totalSessions = $sessions.Count
    bySource = $bySource
    sessions = $sessions
    draftCategoryCounts = $draftCategoryCounts
    anomalies = @{
        unparseableFiles = $unparseable
        unparseableCount = $unparseable.Count
    }
}

Write-Result $result
exit 0
