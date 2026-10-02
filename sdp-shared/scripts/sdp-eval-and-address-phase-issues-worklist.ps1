<#
.SYNOPSIS
    Assemble sdp-eval-and-address-phase-issues's final prioritized worklist (JSON + Markdown) by
    joining the disposed findings (band + fix/accept disposition) back against the original
    extracted findings (full text, shape, phase document), grouping fix-disposed findings by band
    highest-impact-first. Combines the skill's own Step 7 sub-steps 7.1-7.3 into one script call.

.PARAMETER workspaceRoot
    Path to the solution root. Defaults to two levels above this script (sdp-shared/scripts/).

.PARAMETER FindingsJsonPath
    Path to open_findings.json (sdp-eval-and-address-phase-issues-extract.ps1's OutputPath) --
    the full finding records (findingId, shape, taskId, text, phaseDocPath).

.PARAMETER DisposedJsonPath
    Path to findings_disposed.json (sdp-eval-and-address-phase-issues-reconcile.ps1's
    OutputDisposedPath) -- the resolved band + disposition per findingId.

.PARAMETER OutputJsonPath
    Path this script writes phase-issues-worklist.json to.

.PARAMETER OutputMarkdownPath
    Path this script writes phase-issues-worklist.md to.

.NOTES
    Stdout: single-line JSON result object (agent-consumed script per SDP-Script-Authoring.md) --
    a compact summary (counts, the two output paths) for the calling skill's own confirmation
    banner (Step 7 item 4); the full worklist content lives in the two output files, not stdout.
    Exit codes: always 0 -- a missing input file or zero findings is a reported condition in the
    JSON, never a script failure, matching the sibling sdp-report-workflow-analysis-*.ps1 family.
#>
param(
    [string]$workspaceRoot = "",
    [string]$FindingsJsonPath = "",
    [string]$DisposedJsonPath = "",
    [string]$OutputJsonPath = "",
    [string]$OutputMarkdownPath = ""
)

function Write-Result([hashtable]$hash) {
    Write-Output ($hash | ConvertTo-Json -Compress -Depth 12)
}

if (-not $workspaceRoot) {
    $workspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

$BandOrder = @("Required", "Critical", "Structural", "Material", "Clarifying", "Contextual", "Cosmetic", "Administrative")

if (-not $OutputJsonPath -or -not $OutputMarkdownPath) {
    Write-Result @{ status = "error"; error = "OutputJsonPath and OutputMarkdownPath are required" }
    exit 0
}
if (-not $FindingsJsonPath -or -not (Test-Path $FindingsJsonPath)) {
    Write-Result @{ status = "error"; error = "FindingsJsonPath not found: $FindingsJsonPath" }
    exit 0
}
if (-not $DisposedJsonPath -or -not (Test-Path $DisposedJsonPath)) {
    Write-Result @{ status = "error"; error = "DisposedJsonPath not found: $DisposedJsonPath" }
    exit 0
}

try {
    $findingsRaw = [string](Get-Content $FindingsJsonPath -Raw -Encoding UTF8) | ConvertFrom-Json
    $findings = @($findingsRaw)
} catch {
    Write-Result @{ status = "error"; error = "failed to parse FindingsJsonPath: $($_.Exception.Message)" }
    exit 0
}
try {
    $disposedRaw = [string](Get-Content $DisposedJsonPath -Raw -Encoding UTF8) | ConvertFrom-Json
    $disposed = @($disposedRaw)
} catch {
    Write-Result @{ status = "error"; error = "failed to parse DisposedJsonPath: $($_.Exception.Message)" }
    exit 0
}

$findingsById = @{}
foreach ($f in $findings) { $findingsById[[string]$f.findingId] = $f }

$fixFindings = @()
$acceptedFindings = @()
$unmatchedDisposed = @()

foreach ($d in $disposed) {
    $id = [string]$d.findingId
    if (-not $findingsById.ContainsKey($id)) {
        $unmatchedDisposed += $id
        continue
    }
    $src = $findingsById[$id]
    # PSCustomObject, not a plain hashtable: a Hashtable piped through Sort-Object/Group-Object
    # -Property (below) risks being enumerated as its own key-value pairs rather than treated as
    # one object under Windows PowerShell 5.1 -- PSCustomObject does not have this failure mode.
    $entry = [PSCustomObject]@{
        findingId    = $id
        phaseDocPath = [string]$src.phaseDocPath
        shape        = [string]$src.shape
        taskId       = $src.taskId
        text         = [string]$src.text
        band         = [string]$d.band
        rationale    = $d.rationale
        provenance   = [string]$d.provenance
    }
    if ([string]$d.disposition -eq "fix") { $fixFindings += $entry } else { $acceptedFindings += $entry }
}

function Get-BandRank([string]$band) {
    $idx = [array]::IndexOf($BandOrder, $band)
    if ($idx -lt 0) { return 999 }
    return $idx
}

# @(...) wrap is required even with PSCustomObject input: Sort-Object/Select-Object still
# unwrap a single-element result to a bare scalar under Windows PowerShell 5.1, and a bare
# scalar's .Count is $null, not 1 -- the same class of gotcha SDP-Script-Authoring.md documents
# for ConvertFrom-Json array results.
$fixFindingsSorted = @($fixFindings | Sort-Object -Property @{Expression = { Get-BandRank $_.band }}, @{Expression = { $_.phaseDocPath }})
$acceptedFindingsSorted = @($acceptedFindings | Sort-Object -Property @{Expression = { Get-BandRank $_.band }}, @{Expression = { $_.phaseDocPath }})

$generatedAt = (Get-Date -Format "yyyy-MM-dd HH:mm")

# Policy map used, read back from disposed entries' own bands for display (not re-read from
# SDP-Config.json here -- sdp-eval-and-address-phase-issues-reconcile.ps1 already resolved and
# validated it; re-reading would risk displaying a policy that no longer matches what was
# actually applied if the config changed between the two script calls in the same run).
$policyApplied = @{}
foreach ($d in $disposed) {
    $b = [string]$d.band
    if (-not $policyApplied.ContainsKey($b)) { $policyApplied[$b] = [string]$d.disposition }
}

$worklistObj = @{
    generated_at         = $generatedAt
    policyApplied        = $policyApplied
    fixFindingCount      = $fixFindingsSorted.Count
    acceptFindingCount   = $acceptedFindingsSorted.Count
    unmatchedCount       = $unmatchedDisposed.Count
    fixFindings          = $fixFindingsSorted
    acceptedFindings     = $acceptedFindingsSorted
    unmatchedDisposed    = $unmatchedDisposed
}

try {
    ($worklistObj | ConvertTo-Json -Depth 12) | Set-Content -Path $OutputJsonPath -Encoding UTF8
} catch {
    Write-Result @{ status = "error"; error = "failed to write OutputJsonPath: $($_.Exception.Message)" }
    exit 0
}

function Format-TableCell([string]$text) {
    if ($null -eq $text) { return "" }
    return ($text -replace '\|', '\|' -replace "`r?`n", ' ')
}

$md = New-Object System.Text.StringBuilder
[void]$md.AppendLine("<img src=`"../../../sdp-shared/docs/images/SDP_DocsLogo_WithText_0700x0163.png`" alt=`"SDP Logo`" width=`"375`">")
[void]$md.AppendLine("")
[void]$md.AppendLine("# Phase Issues Worklist -- $generatedAt")
[void]$md.AppendLine("")
[void]$md.AppendLine("$($fixFindingsSorted.Count) findings to fix, $($acceptedFindingsSorted.Count) accepted as open" + $(if ($unmatchedDisposed.Count -gt 0) { ", $($unmatchedDisposed.Count) unmatched (see Unmatched section)" } else { "" }) + ".")
[void]$md.AppendLine("")

$fixByBand = @($fixFindingsSorted | Group-Object -Property band)
foreach ($band in $BandOrder) {
    $group = $fixByBand | Where-Object { $_.Name -eq $band }
    if (-not $group) { continue }
    [void]$md.AppendLine("## Fix -- $band")
    [void]$md.AppendLine("")
    [void]$md.AppendLine("| Candidate ID | Phase Document | Shape | Rationale |")
    [void]$md.AppendLine("|---|---|---|---|")
    foreach ($f in $group.Group) {
        $rationaleText = (@($f.rationale) -join " / ")
        [void]$md.AppendLine("| $(Format-TableCell $f.findingId) | $(Format-TableCell $f.phaseDocPath) | $(Format-TableCell $f.shape) | $(Format-TableCell $rationaleText) |")
    }
    [void]$md.AppendLine("")
}

[void]$md.AppendLine("## Accepted -- left open")
[void]$md.AppendLine("")
if ($acceptedFindingsSorted.Count -eq 0) {
    [void]$md.AppendLine("None.")
} else {
    [void]$md.AppendLine("| Candidate ID | Phase Document | Shape | Band | Rationale |")
    [void]$md.AppendLine("|---|---|---|---|---|")
    foreach ($f in $acceptedFindingsSorted) {
        $rationaleText = (@($f.rationale) -join " / ")
        [void]$md.AppendLine("| $(Format-TableCell $f.findingId) | $(Format-TableCell $f.phaseDocPath) | $(Format-TableCell $f.shape) | $(Format-TableCell $f.band) | $(Format-TableCell $rationaleText) |")
    }
}
[void]$md.AppendLine("")

if ($unmatchedDisposed.Count -gt 0) {
    [void]$md.AppendLine("## Unmatched")
    [void]$md.AppendLine("")
    [void]$md.AppendLine("A disposed findingId with no matching entry in open_findings.json -- a join failure between the reconcile and extract outputs, not a classification result. Investigate before trusting this run's counts.")
    [void]$md.AppendLine("")
    foreach ($id in $unmatchedDisposed) { [void]$md.AppendLine("- $id") }
    [void]$md.AppendLine("")
}

try {
    $md.ToString() | Set-Content -Path $OutputMarkdownPath -Encoding UTF8
} catch {
    Write-Result @{ status = "error"; error = "failed to write OutputMarkdownPath: $($_.Exception.Message)" }
    exit 0
}

Write-Result @{
    status             = "success"
    worklistJsonPath   = $OutputJsonPath
    worklistMdPath     = $OutputMarkdownPath
    fixFindingCount    = $fixFindingsSorted.Count
    acceptFindingCount = $acceptedFindingsSorted.Count
    unmatchedCount     = $unmatchedDisposed.Count
}
exit 0
