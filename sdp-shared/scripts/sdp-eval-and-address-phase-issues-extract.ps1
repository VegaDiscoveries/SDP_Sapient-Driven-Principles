<#
.SYNOPSIS
    Extract every discrete open finding across every phase document in scope for
    sdp-eval-and-address-phase-issues, using the six fixed shapes SKILL.md Step 3 defines: an
    open Gap Resolution Format gap, an open Quick Decision Format question, an open Pros-Cons-Gaps
    cycle gap, a still-blocked GATE_BLOCKED issue, the current REJECTED task's Eval finding, and a
    disclosed Issues: bullet. Loops over the full document list internally (one script call for
    the whole sweep) rather than requiring one call per document.

.PARAMETER workspaceRoot
    Path to the solution root. Defaults to two levels above this script (sdp-shared/scripts/).

.PARAMETER DocumentsJsonPath
    Whole-sweep mode. Path to the calling skill's saved copy of
    sdp-eval-and-address-phase-issues-enumerate.ps1's `documents` array (each entry:
    scope/phaseName/phaseFile/phaseDocPath/phaseStatePath). Mutually exclusive with
    SingleTaskMode.

.PARAMETER SingleTaskMode
    When set, process exactly one phase document (PhaseDocPath/PhaseStatePath) and extract only
    shape 5 (the named task's current REJECTED Eval finding) -- shapes 1, 2, 3, 4, and 6 are
    skipped entirely.

.PARAMETER PhaseDocPath
    Single-task mode only. Path to the one phase document, relative to workspaceRoot.

.PARAMETER PhaseStatePath
    Single-task mode only. Path to the matching phase state file, relative to workspaceRoot.

.PARAMETER TaskId
    Required when SingleTaskMode is set. Restricts shape 5 extraction to this task's own Eval
    blockquote sequence.

.PARAMETER OutputPath
    Path this script writes the combined findings list to directly (open_findings.json).
    Required.

.NOTES
    Stdout: single-line JSON result object (agent-consumed script per SDP-Script-Authoring.md) --
    a compact summary (per-shape counts, OutputPath) only; the full findings array is written
    directly to OutputPath rather than round-tripped through stdout, for the same reason
    sdp-eval-and-address-phase-issues-reconcile.ps1 writes its own outputs directly.
    Exit codes: always 0 -- a missing document, an unreadable documents list, or zero findings
    are reported conditions in the JSON, never a script failure, matching the sibling
    sdp-report-workflow-analysis-*.ps1 family's actual exit convention. A single unreadable
    document within a whole-sweep list is recorded per-document and does not fail the run.

    Smoke-tested against a synthetic phase document covering all six finding shapes (both the
    open and the already-resolved/superseded case for each shape that has one) -- this caught and
    fixed a real defect: every regex pattern containing a literal em-dash or emoji character
    (shapes 1, 2, 3, 4, 5's own markers) silently never matched anything, because this file
    originally embedded those characters directly as literal multi-byte source text; a no-BOM
    .ps1 parses as the ANSI codepage under Windows PowerShell 5.1, corrupting them, while
    Get-Content -Encoding UTF8 correctly decodes the *data* being matched against -- the pattern
    and the data were never going to match, with no error raised anywhere to reveal it. Fixed by
    building each such character at runtime via `[char]` code points
    (`$checkMark`/`$hourglass`/`$emDash`, defined once near the top of this file) and
    interpolating them into the pattern strings, instead of embedding them as literal source
    characters. Not yet run against a real consuming solution's actual phase documents -- the
    synthetic fixture exercises the six shapes directly but cannot stand in for the structural
    variety (multi-task documents, non-standard table formatting) a real solution's history would
    contain. Remaining disclosed design-time limitations, not yet confirmed one way or the other
    against real documents:
    - Shape 1 (Gap Resolution Format) and shape 5 (REJECTED Eval) attribution to a specific
      TASK-ID, in a phase document covering more than one task, is done by associating each gap
      or Eval blockquote with the nearest preceding task-item line
      (`- [ ] **[TASK-ID]**` / `- [x] **[TASK-ID]**`) found scanning upward from it. A document
      whose structure doesn't follow this convention will misattribute or leave taskId null.
    - Shape 6 (disclosed Issues: bullets) has no resolution marker in the document at all, by
      design (see the SKILL.md's own disclosed limitation) -- every bullet found is reported,
      with no attempt to detect whether it was separately addressed elsewhere.
    - Table-row parsing (shape 2) assumes a single-line table cell per question, matching every
      worked example in the bootstrap doc; a question wrapped across multiple markdown lines
      within one cell is not reassembled.
#>
param(
    [string]$workspaceRoot = "",
    [string]$DocumentsJsonPath = "",
    [switch]$SingleTaskMode,
    [string]$PhaseDocPath = "",
    [string]$PhaseStatePath = "",
    [string]$TaskId = "",
    [string]$OutputPath = ""
)

function Write-Result([hashtable]$hash) {
    Write-Output ($hash | ConvertTo-Json -Compress -Depth 12)
}

if (-not $workspaceRoot) {
    $workspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

if (-not $OutputPath) {
    Write-Result @{ status = "error"; error = "OutputPath is required" }
    exit 0
}

$taskItemPattern = '^\s*-\s*\[[ x\-]\]\s*\*\*([A-Za-z0-9][A-Za-z0-9\-_]*)\*\*'

# Built at runtime from code points, never embedded as literal multi-byte characters in this
# source file -- a no-BOM .ps1 parses as the ANSI codepage under Windows PowerShell 5.1, and a
# literal non-ASCII character in a regex pattern string silently corrupts and never matches the
# correctly-UTF-8-decoded document text, with no error raised anywhere. See
# SDP-Script-Authoring.md's ASCII-only-source rule and sdp-report-workflow-analysis-sessions.ps1's
# identical arrow-character precedent. Confirmed as a real, reproducible defect in this script
# before this fix (the Resolved-question exclusion, the Pros-Cons-Gaps cycle header, the
# GATE_BLOCKED verdict header, and the Eval blockquote header all silently never matched).
$checkMark = [char]0x2705   # white heavy check mark (RESOLVED tag)
$hourglass = [char]0x23F3   # hourglass with flowing sand (NEEDS DESIGN SESSION / DEFERRED tags)
$emDash = [char]0x2014      # em dash

function Get-TaskStatus($stateObj, [string]$taskId) {
    if (-not $stateObj -or -not $stateObj.tasks) { return $null }
    $prop = $stateObj.tasks.PSObject.Properties[$taskId]
    if (-not $prop) { return $null }
    return [string]$prop.Value.status
}

function Get-DocumentFindings([string]$phaseDocPath, [string]$phaseStatePath, [bool]$singleTaskMode, [string]$targetTaskId) {
    $result = @{ findings = @(); error = $null }

    $docFullPath = Join-Path $workspaceRoot $phaseDocPath
    if (-not (Test-Path $docFullPath)) {
        $result.error = "phase document not found: $phaseDocPath"
        return $result
    }
    $lines = Get-Content $docFullPath -Encoding UTF8
    $totalLines = $lines.Count

    $stateObj = $null
    if ($phaseStatePath) {
        $stateFullPath = Join-Path $workspaceRoot $phaseStatePath
        if (Test-Path $stateFullPath) {
            try { $stateObj = [string](Get-Content $stateFullPath -Raw -Encoding UTF8) | ConvertFrom-Json }
            catch { $stateObj = $null }
        }
    }

    $findings = @()
    $seq = 0
    $currentTaskId = $null

    for ($i = 0; $i -lt $totalLines; $i++) {
        $line = $lines[$i]
        $m = [regex]::Match($line, $taskItemPattern)
        if ($m.Success) { $currentTaskId = $m.Groups[1].Value }

        if (-not $singleTaskMode) {
            # Shape 1: Open gap (Gap Resolution Format)
            $gapMatch = [regex]::Match($line, '^###\s*GAP\s*(\d+):\s*(.+)$')
            if ($gapMatch.Success) {
                $headingText = $gapMatch.Groups[2].Value
                $isResolved = $headingText -match "$checkMark\s*RESOLVED"
                $isOpen = ($headingText -match "$hourglass\s*\[NEEDS DESIGN SESSION\]") -or ($headingText -match "$hourglass\s*\[DEFERRED\]")
                if ($isOpen -and -not $isResolved) {
                    $descLines = @()
                    $j = $i + 1
                    $inGapDesc = $false
                    while ($j -lt $totalLines -and -not ($lines[$j] -match '^##')) {
                        if ($lines[$j] -match '^\*\*The Gap:\*\*') { $inGapDesc = $true }
                        elseif ($lines[$j] -match '^\*\*(Options|Recommended|Impact|Decision Made):') { $inGapDesc = $false }
                        if ($inGapDesc) { $descLines += $lines[$j] }
                        $j++
                    }
                    $seq++
                    $findings += @{
                        seq     = $seq; shape = "openGap"; taskId = $currentTaskId
                        text    = ("GAP " + $gapMatch.Groups[1].Value + ": " + $headingText + " -- " + ($descLines -join " ")).Trim()
                        context = @{ gapNumber = [int]$gapMatch.Groups[1].Value }
                    }
                }
            }

            # Shape 2: Open question (Quick Decision Format)
            $oqMatch = [regex]::Match($line.Trim(), '^\|\s*(OQ-[A-Za-z0-9]+)\s*\|\s*(.+?)\s*\|\s*(.*?)\s*\|\s*$')
            if ($oqMatch.Success) {
                $questionCell = $oqMatch.Groups[2].Value
                if ($questionCell -notmatch "^\*\*Resolved\s*$emDash") {
                    $seq++
                    $findings += @{
                        seq = $seq; shape = "openQuestion"; taskId = $currentTaskId
                        text = $questionCell; context = @{ questionId = $oqMatch.Groups[1].Value }
                    }
                }
            }

            # Shape 6: Disclosed Issues: bullet
            if ($line -match '^\s*>\s*\*\*Issues:\*\*\s*$') {
                $j = $i + 1
                while ($j -lt $totalLines -and $lines[$j] -match '^\s*>\s*-\s+(.+)$') {
                    $bulletMatch = [regex]::Match($lines[$j], '^\s*>\s*-\s+(.+)$')
                    $seq++
                    $findings += @{
                        seq = $seq; shape = "disclosedIssue"; taskId = $currentTaskId
                        text = $bulletMatch.Groups[1].Value; context = @{}
                    }
                    $j++
                }
            }
        }
    }

    if (-not $singleTaskMode) {
        # Shape 3: Open Pros-Cons-Gaps cycle gap, most recent cycle only
        $cycleHeaderIndices = @()
        for ($i = 0; $i -lt $totalLines; $i++) {
            $cm = [regex]::Match($lines[$i], "^##\s*Pros-Cons-Gaps\s*$emDash\s*Cycle\s*(\d+)")
            # PSCustomObject, not a hashtable: piped into Sort-Object below -- see
            # sdp-eval-and-address-phase-issues-worklist.ps1's identical note for why.
            if ($cm.Success) { $cycleHeaderIndices += [PSCustomObject]@{ index = $i; cycle = [int]$cm.Groups[1].Value } }
        }
        if ($cycleHeaderIndices.Count -gt 0) {
            $mostRecent = @($cycleHeaderIndices | Sort-Object -Property cycle -Descending)[0]
            $startIdx = $mostRecent.index
            $endIdx = $totalLines - 1
            for ($i = $startIdx + 1; $i -lt $totalLines; $i++) {
                if ($lines[$i] -match '^##\s' -and $i -gt $startIdx) { $endIdx = $i - 1; break }
            }
            $gapCountMatch = $null
            $inGapsSection = $false
            for ($i = $startIdx; $i -le $endIdx; $i++) {
                if ($lines[$i] -match '^###\s*Gaps\s*$') { $inGapsSection = $true; continue }
                if ($lines[$i] -match '^###\s') { $inGapsSection = $false }
                if ($lines[$i] -match '\*\*Unresolved gap count:\s*(\d+)\*\*') { $gapCountMatch = [int]$matches[1] }
                if ($inGapsSection -and $lines[$i] -match '^\s*-\s+(.+)$') {
                    if ($null -eq $gapCountMatch -or $gapCountMatch -gt 0) {
                        $bulletText = [regex]::Match($lines[$i], '^\s*-\s+(.+)$').Groups[1].Value
                        $seq++
                        $findings += @{
                            seq = $seq; shape = "openProsConsGap"; taskId = $null
                            text = $bulletText; context = @{ cycle = $mostRecent.cycle }
                        }
                    }
                }
            }
        }

        # Shape 4: Open gate-blocked issue (most recent GATE_BLOCKED, only if still blocked)
        $gateBlockedStillOpen = $stateObj -and $stateObj.phase_gate -and ([string]$stateObj.phase_gate.status -eq "blocked")
        if ($gateBlockedStillOpen) {
            $gbIndices = @()
            for ($i = 0; $i -lt $totalLines; $i++) {
                if ($lines[$i] -match "^\s*>\s*\*\*Gate Verdict\s*$emDash\s*GATE_BLOCKED") { $gbIndices += $i }
            }
            if ($gbIndices.Count -gt 0) {
                $lastGb = $gbIndices[$gbIndices.Count - 1]
                $j = $lastGb + 1
                while ($j -lt $totalLines -and $lines[$j] -match '^\s*>') {
                    $issueMatch = [regex]::Match($lines[$j], '^\s*>\s*\d+\.\s+(.+)$')
                    if ($issueMatch.Success) {
                        $seq++
                        $findings += @{ seq = $seq; shape = "openGateBlocked"; taskId = $null; text = $issueMatch.Groups[1].Value; context = @{} }
                    }
                    $j++
                }
            }
        }
    }

    # Shape 5: Open rejected-task finding (most recent non-compliant Eval, task still REJECTED)
    $evalIndices = @()
    $taskIdAtLine = $null
    for ($i = 0; $i -lt $totalLines; $i++) {
        $tm = [regex]::Match($lines[$i], $taskItemPattern)
        if ($tm.Success) { $taskIdAtLine = $tm.Groups[1].Value }
        $em = [regex]::Match($lines[$i], "^\s*>\s*\*\*Eval\s*(\d+)\s*$emDash.*?:\*\*\s*(.*)$")
        # PSCustomObject, not a hashtable: piped into Group-Object/Sort-Object below -- see
        # sdp-eval-and-address-phase-issues-worklist.ps1's identical note for why.
        if ($em.Success) { $evalIndices += [PSCustomObject]@{ index = $i; num = [int]$em.Groups[1].Value; taskId = $taskIdAtLine } }
    }
    if ($evalIndices.Count -gt 0) {
        $targetEvals = $evalIndices
        if ($singleTaskMode) { $targetEvals = @($evalIndices | Where-Object { $_.taskId -eq $targetTaskId }) }
        if ($targetEvals.Count -gt 0) {
            $byTask = @($targetEvals | Group-Object -Property taskId)
            foreach ($group in $byTask) {
                $lastEval = @($group.Group | Sort-Object -Property num -Descending)[0]
                $tid = $lastEval.taskId
                $taskStatus = if ($tid) { Get-TaskStatus $stateObj $tid } else { $null }
                $isRejected = ($taskStatus -eq "REJECTED") -or ($singleTaskMode -and $null -eq $stateObj)
                if (-not $isRejected) { continue }
                $j = $lastEval.index
                $fullText = @()
                while ($j -lt $totalLines -and $lines[$j] -match '^\s*>') {
                    $fullText += ($lines[$j] -replace '^\s*>\s?', '')
                    $j++
                }
                $combinedText = ($fullText -join " ").Trim()
                if ($combinedText -match '(?i)non-compliant') {
                    $seq++
                    $findings += @{ seq = $seq; shape = "openRejectedFinding"; taskId = $tid; text = $combinedText; context = @{ evalNumber = $lastEval.num } }
                }
            }
        }
    }

    $result.findings = $findings
    return $result
}

$allFindings = @()
$docErrors = @()

if ($SingleTaskMode) {
    if (-not $PhaseDocPath) {
        Write-Result @{ status = "error"; error = "PhaseDocPath is required in single-task mode" }
        exit 0
    }
    $r = Get-DocumentFindings $PhaseDocPath $PhaseStatePath $true $TaskId
    if ($r.error) {
        Write-Result @{ status = "error"; error = $r.error }
        exit 0
    }
    foreach ($f in $r.findings) {
        $f.phaseDocPath = $PhaseDocPath
        $allFindings += $f
    }
} else {
    if (-not $DocumentsJsonPath -or -not (Test-Path $DocumentsJsonPath)) {
        Write-Result @{ status = "error"; error = "DocumentsJsonPath not found: $DocumentsJsonPath" }
        exit 0
    }
    try {
        $docsRaw = [string](Get-Content $DocumentsJsonPath -Raw -Encoding UTF8) | ConvertFrom-Json
        $documents = @($docsRaw)
    } catch {
        Write-Result @{ status = "error"; error = "failed to parse DocumentsJsonPath: $($_.Exception.Message)" }
        exit 0
    }
    foreach ($doc in $documents) {
        $r = Get-DocumentFindings ([string]$doc.phaseDocPath) ([string]$doc.phaseStatePath) $false ""
        if ($r.error) {
            $docErrors += @{ phaseDocPath = [string]$doc.phaseDocPath; error = $r.error }
            continue
        }
        foreach ($f in $r.findings) {
            $f.phaseDocPath = [string]$doc.phaseDocPath
            $f.scope = [string]$doc.scope
            $allFindings += $f
        }
    }
}

# Re-sequence seq numbers globally so every (phaseDocPath, seq) pair is unique across documents,
# and assign a stable findingId ("[phaseDocPath]#[seq]") -- this is the identifier rating agents
# are given and must echo back (SKILL.md Step 4 item 5), and the join key
# sdp-eval-and-address-phase-issues-reconcile.ps1 / -worklist.ps1 use to recombine this script's
# full finding text/shape/phaseDocPath with the rating passes' band/rationale.
$globalSeq = 0
foreach ($f in $allFindings) {
    $globalSeq++
    $f.seq = $globalSeq
    $f.findingId = "$($f.phaseDocPath)#$globalSeq"
}

$findingsByType = @{}
foreach ($f in $allFindings) {
    $k = [string]$f.shape
    if ($findingsByType.ContainsKey($k)) { $findingsByType[$k] = $findingsByType[$k] + 1 } else { $findingsByType[$k] = 1 }
}

try {
    ($allFindings | ConvertTo-Json -Depth 12) | Set-Content -Path $OutputPath -Encoding UTF8
} catch {
    Write-Result @{ status = "error"; error = "failed to write OutputPath: $($_.Exception.Message)" }
    exit 0
}

Write-Result @{
    status         = "success"
    singleTaskMode = [bool]$SingleTaskMode
    findingsPath   = $OutputPath
    findingCount   = $allFindings.Count
    findingsByType = $findingsByType
    documentErrors = $docErrors
}
exit 0
