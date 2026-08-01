<#
.SYNOPSIS
    Deterministic backend for sdp-solution-phase-gate-review Step 1 (GPG CHECK): read gpg_version
    from .sdp-solution-workflow/state.json, construct the GPG standards file path, and check its
    existence. On a missing GPG file, writes the halt (workflow_status/halt_reason) to
    state.json per the Halt Behavior Contract.

.NOTES
    Solution-root script — no -workspaceRoot parameter. Always operates on the solution root,
    self-resolved from this script's own location, mirroring sdp-solution-create-prompt.ps1's
    pattern. There is only one scope here, so there is nothing to parameterize (unlike
    sdp-gate-review-gpg-check.ps1, which needs -scope because it serves two roots).
    Reads:  .sdp-solution-workflow/state.json
    Writes: .sdp-solution-workflow/state.json (workflow_status/halt_reason/updated, only on the
      gpg_file_exists=false halt path)
    Side effect: on the halt path, invokes sdp-workflow-log.ps1 (non-blocking) to record the
      halt in the semantic workflow-log stream.
    Stdout: single-line JSON result object (same shape as sdp-gate-review-gpg-check.ps1's).
    Exit codes: 0 = success or halted (both expected, non-error terminal states the calling
      skill branches on); 1 = error (state.json missing/unparseable, or gpg_version absent).
#>

$solutionRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Write-Result([hashtable]$hash) {
    Write-Output ($hash | ConvertTo-Json -Compress -Depth 6)
}

function Exit-Error([string]$msg) {
    $r = [ordered]@{
        status        = "error"
        error         = $msg
        gpg_version   = $null
        gpg_file_path = $null
        gpg_file_exists = $null
    }
    Write-Result $r
    exit 1
}

function Set-JsonFileWithRetry($obj, [string]$path, [int]$depth) {
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

$statePath = Join-Path $solutionRoot ".sdp-solution-workflow/state.json"
if (-not (Test-Path $statePath)) {
    Exit-Error ".sdp-solution-workflow/state.json not found. Solution workflow state has not been initialized - run solution setup to create it."
}

try {
    $state = Get-Content $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    Exit-Error "Failed to parse .sdp-solution-workflow/state.json: $($_.Exception.Message)"
}

$gpgVersion = $state.gpg_version
if (-not $gpgVersion) {
    Exit-Error ".sdp-solution-workflow/state.json has no gpg_version field. Set gpg_version before running sdp-solution-phase-gate-review."
}

$gpgFileRelPath = "standards/GenericProjectGuidlines_$gpgVersion.md"
$gpgFileFullPath = Join-Path $solutionRoot $gpgFileRelPath
$gpgFileExists = Test-Path $gpgFileFullPath

if (-not $gpgFileExists) {
    $state | Add-Member -NotePropertyName workflow_status -NotePropertyValue "halted" -Force
    $state | Add-Member -NotePropertyName halt_reason -NotePropertyValue "GPG file missing or version mismatch - expected '$gpgFileRelPath'." -Force
    $state | Add-Member -NotePropertyName updated -NotePropertyValue (Get-Date -Format "yyyy-MM-dd") -Force
    $written = Set-JsonFileWithRetry $state $statePath 14

    try {
        $workflowLogPath = Join-Path $PSScriptRoot "sdp-workflow-log.ps1"
        if (Test-Path $workflowLogPath) {
            & $workflowLogPath -trigger "gpg.missing" -role "GATE_REVIEWER" -outcome "halted" `
                -reason "GPG file missing or version mismatch - expected '$gpgFileRelPath'." | Out-Null
        }
    } catch {
        # Workflow logging is a non-blocking side effect - swallow any failure.
    }

    $r = [ordered]@{
        status              = "halted"
        error               = $null
        gpg_version         = $gpgVersion
        gpg_file_path       = $gpgFileRelPath
        gpg_file_exists     = $false
        state_json_written  = $written
        halt_message        = "GPG file missing or version mismatch. Restore the file and run sdp-solution-phase-coordinator to resume."
    }
    Write-Result $r
    exit 0
}

$r = [ordered]@{
    status          = "success"
    error           = $null
    gpg_version     = $gpgVersion
    gpg_file_path   = $gpgFileRelPath
    gpg_file_exists = $true
}
Write-Result $r
exit 0
