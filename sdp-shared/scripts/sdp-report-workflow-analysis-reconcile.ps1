<#
.SYNOPSIS
    Reconcile the sessions script's mechanical draft category (role + status-transition rule)
    against an independent agent classification pass, per session, recording every disagreement
    rather than silently resolving or averaging it. This is the deterministic half of
    sdp-report-workflow-analysis's session-classification step; the agent dispatch and blind
    per-batch reading is the skill's own job (requires judgment this script cannot perform).

.PARAMETER SessionsJsonPath
    Path to the JSON file written by sdp-report-workflow-analysis-sessions.ps1's stdout (the
    calling skill saves that single JSON line to a file before invoking this script).

.PARAMETER ClassificationsJsonPath
    Path to a JSON file the calling skill writes after collecting every classification agent's
    output: an array of objects, each { "file": "<session file path, matching the sessions
    JSON's own file field>", "agentCategory": "<one of the fixed taxonomy category names>" }.
    Every session in SessionsJsonPath must appear exactly once; a session missing from this file
    is reported as an anomaly, not silently skipped.

.NOTES
    Stdout: single-line JSON result object (agent-consumed script per SDP-Script-Authoring.md).
    Exit codes: 0 = success; 1 reserved for an operational failure (missing/unparseable input
    file) that prevented any JSON from being written at all.
#>
param(
    [string]$SessionsJsonPath = "",
    [string]$ClassificationsJsonPath = ""
)

function Write-Result([hashtable]$hash) {
    Write-Output ($hash | ConvertTo-Json -Compress -Depth 12)
}

if (-not $SessionsJsonPath -or -not (Test-Path $SessionsJsonPath)) {
    Write-Result @{ status = "error"; error = "SessionsJsonPath not found: $SessionsJsonPath" }
    exit 0
}
if (-not $ClassificationsJsonPath -or -not (Test-Path $ClassificationsJsonPath)) {
    Write-Result @{ status = "error"; error = "ClassificationsJsonPath not found: $ClassificationsJsonPath" }
    exit 0
}

try {
    $sessionsData = [string](Get-Content $SessionsJsonPath -Raw -Encoding UTF8) | ConvertFrom-Json
} catch {
    Write-Result @{ status = "error"; error = "failed to parse SessionsJsonPath: $($_.Exception.Message)" }
    exit 0
}
try {
    # Assign the ConvertFrom-Json result to a variable BEFORE wrapping with @() -- wrapping the
    # pipeline result directly (`@(... | ConvertFrom-Json)`) double-wraps under Windows
    # PowerShell 5.1, which emits a multi-element array as a single pipeline object. See
    # SDP-Script-Authoring.md's "Capture-then-wrap for ConvertFrom-Json arrays" note.
    $classificationsRaw = [string](Get-Content $ClassificationsJsonPath -Raw -Encoding UTF8) | ConvertFrom-Json
    $classifications = @($classificationsRaw)
} catch {
    Write-Result @{ status = "error"; error = "failed to parse ClassificationsJsonPath: $($_.Exception.Message)" }
    exit 0
}

$agentByFile = @{}
foreach ($c in $classifications) {
    $agentByFile[[string]$c.file] = [string]$c.agentCategory
}

$agreed = 0
$disagreed = 0
$missing = @()
$disagreements = @()
$agentCategoryCounts = @{}

foreach ($s in @($sessionsData.sessions)) {
    $file = [string]$s.file
    $draft = [string]$s.draftCategory
    if (-not $agentByFile.ContainsKey($file)) {
        $missing += $file
        continue
    }
    $agentCategory = $agentByFile[$file]
    if ($agentCategoryCounts.ContainsKey($agentCategory)) { $agentCategoryCounts[$agentCategory] = $agentCategoryCounts[$agentCategory] + 1 } else { $agentCategoryCounts[$agentCategory] = 1 }

    if ($agentCategory -eq $draft) {
        $agreed++
    } else {
        $disagreed++
        $disagreements += @{
            file = $file
            draftCategory = $draft
            agentCategory = $agentCategory
        }
    }
}

$totalCompared = $agreed + $disagreed
$agreementRate = 0
if ($totalCompared -gt 0) { $agreementRate = [math]::Round(($agreed / $totalCompared), 4) }

$result = @{
    status = "success"
    totalSessions = @($sessionsData.sessions).Count
    totalCompared = $totalCompared
    agreed = $agreed
    disagreed = $disagreed
    agreementRate = $agreementRate
    agentCategoryCounts = $agentCategoryCounts
    disagreements = $disagreements
    anomalies = @{
        missingFromClassifications = $missing
        missingCount = $missing.Count
    }
}

Write-Result $result
exit 0
