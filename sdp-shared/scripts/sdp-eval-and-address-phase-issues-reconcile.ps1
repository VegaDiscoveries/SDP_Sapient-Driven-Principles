<#
.SYNOPSIS
    Reconcile sdp-eval-and-address-phase-issues's two independent blind rating passes per finding
    (escalating any disagreement to the higher-impact band, never averaging or picking the lower
    one), then apply SDP-Config.json's phaseIssuePolicy.bandDisposition map to produce each
    finding's fix/accept disposition. Combines the skill's own Steps 5 and 6 into one script call.

.PARAMETER workspaceRoot
    Path to the solution root. Defaults to two levels above this script (sdp-shared/scripts/).
    Used to resolve SDP-Config.json -- this script is solution-root scoped.

.PARAMETER PassAJsonPath
    Path to the calling skill's saved Pass A output: a JSON array of
    { "findingId", "band", "rationale" } objects (sdp-eval-and-address-phase-issues/SKILL.md
    Step 4 item 5).

.PARAMETER PassBJsonPath
    Path to the calling skill's saved Pass B output, same shape as PassAJsonPath.

.PARAMETER OutputReconciledPath
    Path this script writes findings_reconciled.json to directly (full array, with provenance
    and disagreement detail). Required.

.PARAMETER OutputDisposedPath
    Path this script writes findings_disposed.json to directly (full array, with disposition).
    Required.

.NOTES
    Stdout: single-line JSON result object (agent-consumed script per SDP-Script-Authoring.md) --
    a compact summary (counts, agreement rate, the two output paths) only; the full reconciled/
    disposed arrays are written directly to OutputReconciledPath/OutputDisposedPath rather than
    round-tripped through stdout, since a solution with many findings would otherwise blow past
    a single-line-JSON-on-stdout budget for no benefit (the calling skill never needs to hold the
    full arrays in its own context -- Step 7's worklist script reads OutputDisposedPath directly).
    Exit codes: always 0 -- a missing input file, an incomplete bandDisposition map, or zero
    findings are reported conditions in the JSON, never a script failure, matching the sibling
    sdp-report-workflow-analysis-*.ps1 family's actual exit convention.
#>
param(
    [string]$workspaceRoot = "",
    [string]$PassAJsonPath = "",
    [string]$PassBJsonPath = "",
    [string]$OutputReconciledPath = "",
    [string]$OutputDisposedPath = ""
)

function Write-Result([hashtable]$hash) {
    Write-Output ($hash | ConvertTo-Json -Compress -Depth 12)
}

if (-not $workspaceRoot) {
    $workspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

$BandOrder = @("Required", "Critical", "Structural", "Material", "Clarifying", "Contextual", "Cosmetic", "Administrative")
$BandRank = @{}
for ($i = 0; $i -lt $BandOrder.Count; $i++) { $BandRank[$BandOrder[$i]] = $i }

if (-not $OutputReconciledPath -or -not $OutputDisposedPath) {
    Write-Result @{ status = "error"; error = "OutputReconciledPath and OutputDisposedPath are required" }
    exit 0
}
if (-not $PassAJsonPath -or -not (Test-Path $PassAJsonPath)) {
    Write-Result @{ status = "error"; error = "PassAJsonPath not found: $PassAJsonPath" }
    exit 0
}
if (-not $PassBJsonPath -or -not (Test-Path $PassBJsonPath)) {
    Write-Result @{ status = "error"; error = "PassBJsonPath not found: $PassBJsonPath" }
    exit 0
}

try {
    $passARaw = [string](Get-Content $PassAJsonPath -Raw -Encoding UTF8) | ConvertFrom-Json
    $passA = @($passARaw)
} catch {
    Write-Result @{ status = "error"; error = "failed to parse PassAJsonPath: $($_.Exception.Message)" }
    exit 0
}
try {
    $passBRaw = [string](Get-Content $PassBJsonPath -Raw -Encoding UTF8) | ConvertFrom-Json
    $passB = @($passBRaw)
} catch {
    Write-Result @{ status = "error"; error = "failed to parse PassBJsonPath: $($_.Exception.Message)" }
    exit 0
}

$configPath = Join-Path $workspaceRoot "SDP-Config.json"
if (-not (Test-Path $configPath)) {
    Write-Result @{ status = "error"; error = "SDP-Config.json not found at solution root" }
    exit 0
}
try {
    $configObj = [string](Get-Content $configPath -Raw -Encoding UTF8) | ConvertFrom-Json
} catch {
    Write-Result @{ status = "error"; error = "failed to parse SDP-Config.json: $($_.Exception.Message)" }
    exit 0
}

if (-not $configObj.phaseIssuePolicy -or -not $configObj.phaseIssuePolicy.bandDisposition) {
    Write-Result @{ status = "error"; error = "SDP-Config.json phaseIssuePolicy.bandDisposition is missing" }
    exit 0
}
$bandDisposition = @{}
foreach ($band in $BandOrder) {
    $prop = $configObj.phaseIssuePolicy.bandDisposition.PSObject.Properties[$band]
    if (-not $prop -or ($prop.Value -ne "fix" -and $prop.Value -ne "accept")) {
        Write-Result @{ status = "error"; error = "phaseIssuePolicy.bandDisposition missing or invalid value for band '$band' -- must be 'fix' or 'accept'" }
        exit 0
    }
    $bandDisposition[$band] = [string]$prop.Value
}

function Get-ById($arr) {
    $map = @{}
    foreach ($item in $arr) { $map[[string]$item.findingId] = $item }
    return $map
}

$aById = Get-ById $passA
$bById = Get-ById $passB

$allIds = @()
$seen = @{}
foreach ($id in ($aById.Keys + $bById.Keys)) {
    if (-not $seen.ContainsKey($id)) { $seen[$id] = $true; $allIds += $id }
}

$reconciled = @()
$disagreements = @()
$agreedCount = 0
$singlePassCount = 0

foreach ($id in $allIds) {
    $inA = $aById.ContainsKey($id)
    $inB = $bById.ContainsKey($id)

    if ($inA -and $inB) {
        $itemA = $aById[$id]
        $itemB = $bById[$id]
        $bandA = [string]$itemA.band
        $bandB = [string]$itemB.band
        if ($bandA -eq $bandB) {
            $agreedCount++
            $reconciled += @{
                findingId  = $id
                band       = $bandA
                rationale  = @([string]$itemA.rationale)
                provenance = "agreed"
            }
        } else {
            $rankA = if ($BandRank.ContainsKey($bandA)) { $BandRank[$bandA] } else { 999 }
            $rankB = if ($BandRank.ContainsKey($bandB)) { $BandRank[$bandB] } else { 999 }
            # Lower rank index = higher impact (BandOrder is highest-to-lowest). Escalate to the
            # lower index (higher-impact band) -- never the lower-impact one. See SKILL.md Step 5.
            $resolvedBand = if ($rankA -le $rankB) { $bandA } else { $bandB }
            $disagreements += @{
                findingId  = $id
                bandA      = $bandA
                bandB      = $bandB
                rationaleA = [string]$itemA.rationale
                rationaleB = [string]$itemB.rationale
                resolvedTo = $resolvedBand
            }
            $reconciled += @{
                findingId  = $id
                band       = $resolvedBand
                rationale  = @([string]$itemA.rationale, [string]$itemB.rationale)
                provenance = "disagreed-escalated"
            }
        }
    } else {
        $singlePassCount++
        $only = if ($inA) { $aById[$id] } else { $bById[$id] }
        $reconciled += @{
            findingId  = $id
            band       = [string]$only.band
            rationale  = @([string]$only.rationale)
            provenance = "single-pass"
        }
    }
}

$totalCompared = $agreedCount + $disagreements.Count
$agreementRate = 0
if ($totalCompared -gt 0) { $agreementRate = [math]::Round(($agreedCount / $totalCompared), 4) }

$disposed = @()
$fixCount = 0
$acceptCount = 0
foreach ($r in $reconciled) {
    $band = [string]$r.band
    $disposition = if ($bandDisposition.ContainsKey($band)) { $bandDisposition[$band] } else { "fix" }
    if (-not $bandDisposition.ContainsKey($band)) {
        # Unknown/out-of-taxonomy band from a rating agent: never silently default to "accept" --
        # defaulting to "fix" is the fail-safe direction (over-flag, not under-flag), matching the
        # skill's own disagreement-escalation discipline.
    }
    if ($disposition -eq "fix") { $fixCount++ } else { $acceptCount++ }
    $disposed += @{
        findingId  = $r.findingId
        band       = $band
        rationale  = $r.rationale
        provenance = $r.provenance
        disposition = $disposition
    }
}

$reconciledOut = @{
    agreementRate   = $agreementRate
    agreedCount     = $agreedCount
    disagreedCount  = $disagreements.Count
    singlePassCount = $singlePassCount
    disagreements   = $disagreements
    reconciled      = $reconciled
}
try {
    ($reconciledOut | ConvertTo-Json -Depth 12) | Set-Content -Path $OutputReconciledPath -Encoding UTF8
} catch {
    Write-Result @{ status = "error"; error = "failed to write OutputReconciledPath: $($_.Exception.Message)" }
    exit 0
}
try {
    ($disposed | ConvertTo-Json -Depth 12) | Set-Content -Path $OutputDisposedPath -Encoding UTF8
} catch {
    Write-Result @{ status = "error"; error = "failed to write OutputDisposedPath: $($_.Exception.Message)" }
    exit 0
}

Write-Result @{
    status               = "success"
    findingsReconciledPath = $OutputReconciledPath
    findingsDisposedPath   = $OutputDisposedPath
    agreementRate        = $agreementRate
    agreedCount          = $agreedCount
    disagreedCount       = $disagreements.Count
    singlePassCount      = $singlePassCount
    fixCount             = $fixCount
    acceptCount          = $acceptCount
}
exit 0
