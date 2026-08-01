<#
.SYNOPSIS
    Launch a new terminal window running `claude` with a configured initial prompt/skill and
    starting directory, and record the spawned instance in SDP-Terminal-Sessions.json.

.PARAMETER terminal
    Optional. Selects an entry from SDP-Config.json's newTerminals array by id (numeric,
    e.g. "0" or "1") or by name (string, e.g. "stateLoop"). Empty string (default) selects the
    entry whose id equals 0. Matching tries id first (if the value parses as an integer), then
    name. An unresolved selector is a hard error (exit 1) - no terminal is launched.

.PARAMETER promptOverride
    Optional. Overrides the selected newTerminals entry's initialPrompt for this invocation only.
    Empty string (default) uses the entry's configured value. Empty result (no override, no
    config value) launches `claude` with no initial prompt.

.PARAMETER whatIf
    Diagnostic switch. Resolve the launcher, prompt, directory, and instance id and write them
    as a single compact JSON line to stdout INSTEAD of launching a process or writing the
    registry file. Intended for deterministic testing without spawning a real window.

.NOTES
    Reads:
      SDP-Config.json                  (newTerminals[] - array of {id, name, initialPrompt,
                                         startingDirectory, hoursToSaveSessionHistory,
                                         permissionMode} entries; selected by -terminal.
                                         Also reads the top-level
                                         newTerminalDefaultHoursToSaveSessionHistory as the
                                         config-wide fallback when a selected entry omits its
                                         own hoursToSaveSessionHistory.)
      sdp-shared/scripts/script-support/SDP-Terminal-Sessions.json
                                        (existing instance registry, if present)
    Writes:
      sdp-shared/scripts/script-support/SDP-Terminal-Sessions.json
                                        (reconciles existing entries, appends the new instance
                                        entry; created if absent)
      A short-lived PID marker file under $env:TEMP (removed after being read).
    Stdout: single-line JSON result object.
    Exit codes: 0 = success (or -whatIf plan); 1 = error (terminal failed to launch, or the
    registry could not be written).
    Sets SDP_TERMINAL_ID in the spawned terminal's environment so a future companion skill can
    identify and update this instance's registry entry when its work completes.

    Reconciliation (runs on every non-whatIf invocation, before appending the new entry): every
    existing entry with status "running" is checked via Get-Process on its recorded pid. If the
    process is no longer running, status becomes "not_running" and notRunningAt is stamped with
    the current time - this is a liveness inference (window closed, crashed, or exited), distinct
    from the future "completed" self-report a companion skill will eventually write. Any entry
    already "not_running" whose notRunningAt is older than the resolved hoursToSaveSessionHistory
    hours is dropped from the registry entirely. Resolution order: the selected entry's own
    hoursToSaveSessionHistory, else SDP-Config.json's top-level newTerminalDefaultHoursToSaveSessionHistory,
    else this script's own last-resort default (168 hours, one week) if SDP-Config.json itself is
    missing/malformed.
    Entries with any
    other status (e.g. a future "completed") are left untouched by this pass.

    PID correlation: `wt.exe` is a thin launcher - when it hands off to an existing or new
    WindowsTerminal.exe host it exits almost immediately, so the PID returned by
    `Start-Process -PassThru` on `wt.exe` belongs to a process that is already gone. To record a
    PID that is actually still running when the caller later wants to kill it, the spawned shell
    itself writes its own $PID to a marker file as the first thing it does; this script polls for
    that file (up to 5s) and reads the real PID from it. If the marker never appears, the
    Start-Process PID is recorded as a best-effort fallback and `pidConfirmed` is set to false.

    Command encoding: the child command is passed via `-EncodedCommand` (Base64 of the UTF-16LE
    script text), not a quoted `-Command "..."` string. wt.exe's own command-line grammar treats
    `;` as an action separator even inside what looks like a quoted argument, so a literal `;` in
    the child command (needed to sequence the PID write, env var, and claude launch) gets split
    by wt and the trailing fragment is misinterpreted as a separate launch target. Base64 has no
    spaces, quotes, or semicolons, so no intermediate parser (wt, cmd, CreateProcess) can
    re-tokenize it.

    Permission mode: the selected entry's permissionMode maps directly to `claude
    --permission-mode <value>` (see SDP-Config.json newTerminalPermissionModeOptions for the
    accepted value list). This replaces an earlier design considered for driving mode selection by
    sending Shift+Tab keystrokes to the spawned window after a delay - rejected because it depends
    on window focus timing and on knowing the current position in the Shift+Tab cycle (which
    changes length based on disableAutoMode and enabled modes), whereas the CLI flag sets the mode
    directly and deterministically. An unrecognized configured value is a hard error (exit 1)
    rather than being passed through to `claude` unvalidated, since a bad flag would otherwise
    fail silently inside the fire-and-forget spawned window.

    Terminal profile selection: newTerminals is an array so SDP-Config.json can declare several
    named launch profiles (e.g. id 0 "go" for an interactive session, id 1 "stateLoop" for
    /sdp-state-loop-start) instead of one fixed configuration. -terminal selects which entry to
    use; omitting it selects id 0 so existing no-argument callers keep working unchanged.
#>
param(
    [string]$terminal = "",
    [string]$promptOverride = "",
    [switch]$whatIf
)

$solutionRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Write-Result([hashtable]$hash) {
    Write-Output ($hash | ConvertTo-Json -Compress)
}

# ---------------------------------------------------------------------------
# Read SDP-Config.json and select a newTerminals[] entry (non-fatal if the
# config file or the newTerminals key is entirely absent - fall back to
# defaults; but an unresolved -terminal selector against an existing array
# IS an error - the caller asked for something specific that doesn't exist).
# ---------------------------------------------------------------------------

$configuredPrompt = ""
$configuredDirectory = ""
$hoursToSaveSessionHistory = 168  # 24*7 (one week) - last-resort fallback only if SDP-Config.json itself is missing/malformed
$configuredPermissionMode = ""
$selectedTerminalId = $null
$selectedTerminalName = $null
$configPath = Join-Path $solutionRoot "SDP-Config.json"

$sdpConfig = $null
if (Test-Path $configPath) {
    try {
        $sdpConfig = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        # Malformed config is non-fatal here - proceed with defaults.
        $sdpConfig = $null
    }
}

# Config-level default, independent of which (if any) newTerminals profile is selected below -
# a per-profile hoursToSaveSessionHistory, if present, overrides this further down.
if ($sdpConfig -and ($null -ne $sdpConfig.newTerminalDefaultHoursToSaveSessionHistory)) {
    try { $hoursToSaveSessionHistory = [double]$sdpConfig.newTerminalDefaultHoursToSaveSessionHistory } catch { }
}

if ($sdpConfig -and $sdpConfig.newTerminals) {
    $entries = @($sdpConfig.newTerminals)
    $selectedEntry = $null

    if (-not $terminal) {
        $selectedEntry = @($entries | Where-Object { $_.id -eq 0 }) | Select-Object -First 1
        if (-not $selectedEntry) {
            Write-Result @{
                status            = "error"
                instanceId        = $null
                pid               = $null
                pidConfirmed      = $false
                launcher          = $null
                resolvedPrompt    = $null
                resolvedDirectory = $null
                error             = "No -terminal specified and no newTerminals entry with id 0 found in SDP-Config.json. Available: $((@($entries | ForEach-Object { "$($_.id):$($_.name)" })) -join ', ')."
            }
            exit 1
        }
    } else {
        $parsedId = 0
        $isNumeric = [int]::TryParse($terminal, [ref]$parsedId)
        if ($isNumeric) {
            $selectedEntry = @($entries | Where-Object { $_.id -eq $parsedId }) | Select-Object -First 1
        }
        if (-not $selectedEntry) {
            $selectedEntry = @($entries | Where-Object { $_.name -eq $terminal }) | Select-Object -First 1
        }
        if (-not $selectedEntry) {
            Write-Result @{
                status            = "error"
                instanceId        = $null
                pid               = $null
                pidConfirmed      = $false
                launcher          = $null
                resolvedPrompt    = $null
                resolvedDirectory = $null
                error             = "No newTerminals entry with id or name '$terminal' found in SDP-Config.json. Available: $((@($entries | ForEach-Object { "$($_.id):$($_.name)" })) -join ', ')."
            }
            exit 1
        }
    }

    $selectedTerminalId = $selectedEntry.id
    $selectedTerminalName = $selectedEntry.name
    if ($selectedEntry.initialPrompt) { $configuredPrompt = $selectedEntry.initialPrompt }
    if ($selectedEntry.startingDirectory) { $configuredDirectory = $selectedEntry.startingDirectory }
    if ($null -ne $selectedEntry.hoursToSaveSessionHistory) {
        try { $hoursToSaveSessionHistory = [double]$selectedEntry.hoursToSaveSessionHistory } catch { }
    }
    if ($selectedEntry.permissionMode) { $configuredPermissionMode = $selectedEntry.permissionMode }
}

$validPermissionModes = @("default", "manual", "acceptEdits", "plan", "auto", "dontAsk", "bypassPermissions")
if ($configuredPermissionMode -and ($validPermissionModes -notcontains $configuredPermissionMode)) {
    Write-Result @{
        status            = "error"
        instanceId        = $null
        pid               = $null
        pidConfirmed      = $false
        launcher          = $null
        resolvedPrompt    = $null
        resolvedDirectory = $null
        error             = "SDP-Config.json newTerminals entry '$selectedTerminalId`:$selectedTerminalName' has permissionMode '$configuredPermissionMode', which is not a recognized value. Valid values: $($validPermissionModes -join ', ')."
    }
    exit 1
}

$resolvedPrompt = if ($promptOverride) { $promptOverride } else { $configuredPrompt }

$resolvedDirectory = if (-not $configuredDirectory) {
    $solutionRoot
} elseif ([System.IO.Path]::IsPathRooted($configuredDirectory)) {
    $configuredDirectory
} else {
    Join-Path $solutionRoot $configuredDirectory
}

# ---------------------------------------------------------------------------
# Resolve launcher and build the child command
# ---------------------------------------------------------------------------

$wtCmd = Get-Command wt.exe -ErrorAction SilentlyContinue
$launcherName = if ($wtCmd) { "wt" } else { "powershell" }

$instanceId = [guid]::NewGuid().ToString()
$markerPath = Join-Path $env:TEMP "sdp-terminal-$instanceId.pid"

$escapedPrompt = $resolvedPrompt -replace "'", "''"
$permissionModeFlag = if ($configuredPermissionMode) { "--permission-mode $configuredPermissionMode " } else { "" }
$claudeInvocation = if ($resolvedPrompt) { "claude $permissionModeFlag'$escapedPrompt'" } else { "claude $permissionModeFlag".TrimEnd() }
# The child writes its own $PID to the marker file before doing anything else - see PID
# correlation note above for why this is necessary instead of trusting Start-Process -PassThru.
$pidWrite = "`$PID | Out-File -FilePath '$markerPath' -Encoding ascii -NoNewline"
$fullCommand = "$pidWrite; `$env:SDP_TERMINAL_ID='$instanceId'; $claudeInvocation"
$encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($fullCommand))

if ($launcherName -eq "wt") {
    $argString = "-d `"$resolvedDirectory`" -- powershell -NoExit -EncodedCommand $encodedCommand"
} else {
    $argString = "-NoExit -EncodedCommand $encodedCommand"
}

if ($whatIf) {
    Write-Result @{
        resolved               = $true
        instanceId             = $instanceId
        selectedTerminalId     = $selectedTerminalId
        selectedTerminalName   = $selectedTerminalName
        launcher               = $launcherName
        resolvedPrompt         = $resolvedPrompt
        resolvedDirectory      = $resolvedDirectory
        resolvedPermissionMode = $configuredPermissionMode
        fullCommand            = $fullCommand
        argString              = $argString
    }
    exit 0
}

# ---------------------------------------------------------------------------
# Launch the terminal
# ---------------------------------------------------------------------------

$proc = $null
try {
    if ($launcherName -eq "wt") {
        $proc = Start-Process -FilePath "wt" -ArgumentList $argString -PassThru
    } else {
        $proc = Start-Process -FilePath "powershell" -ArgumentList $argString -WorkingDirectory $resolvedDirectory -PassThru
    }
} catch {
    Write-Result @{
        status               = "error"
        instanceId           = $null
        selectedTerminalId   = $selectedTerminalId
        selectedTerminalName = $selectedTerminalName
        pid                  = $null
        pidConfirmed         = $false
        launcher             = $launcherName
        resolvedPrompt       = $resolvedPrompt
        resolvedDirectory    = $resolvedDirectory
        error                = "Failed to launch terminal: $($_.Exception.Message)"
    }
    exit 1
}

# ---------------------------------------------------------------------------
# Wait for the child shell to report its own PID via the marker file
# ---------------------------------------------------------------------------

$confirmedPid = $null
$deadline = (Get-Date).AddSeconds(5)
while ((Get-Date) -lt $deadline) {
    if (Test-Path $markerPath) {
        Start-Sleep -Milliseconds 100
        try {
            $confirmedPid = [int]((Get-Content $markerPath -Raw).Trim())
        } catch { }
        break
    }
    Start-Sleep -Milliseconds 200
}
if (Test-Path $markerPath) { Remove-Item $markerPath -Force -ErrorAction SilentlyContinue }

$pidConfirmed = $null -ne $confirmedPid
$recordedPid = if ($pidConfirmed) { $confirmedPid } else { $proc.Id }

# ---------------------------------------------------------------------------
# Record the instance in SDP-Terminal-Sessions.json
# ---------------------------------------------------------------------------

$registryPath = Join-Path $PSScriptRoot "script-support/SDP-Terminal-Sessions.json"

$registry = $null
if (Test-Path $registryPath) {
    try {
        $registry = Get-Content $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        $registry = $null
    }
}
if (-not $registry) {
    $registry = [pscustomobject]@{ schema_version = "1.0"; instances = @() }
}

$instancesList = New-Object System.Collections.Generic.List[object]
if ($registry.instances) {
    foreach ($item in @($registry.instances)) { $instancesList.Add($item) }
}

# ---------------------------------------------------------------------------
# Reconcile existing entries: detect processes no longer running, stamp
# notRunningAt on first detection, then drop entries whose not_running
# timestamp is older than $hoursToSaveSessionHistory. See .NOTES for scope -
# only "running" and "not_running" entries are touched by this pass.
# ---------------------------------------------------------------------------

$markedNotRunningCount = 0
$prunedCount = 0
$reconciledList = New-Object System.Collections.Generic.List[object]
foreach ($entry in $instancesList) {
    if ($entry.status -eq "running") {
        $isAlive = $false
        try {
            $null = Get-Process -Id ([int]$entry.pid) -ErrorAction Stop
            $isAlive = $true
        } catch { $isAlive = $false }
        if (-not $isAlive) {
            $entry | Add-Member -NotePropertyName "status" -NotePropertyValue "not_running" -Force
            $entry | Add-Member -NotePropertyName "notRunningAt" -NotePropertyValue ((Get-Date).ToString("o")) -Force
            $markedNotRunningCount++
        }
    }

    $shouldPrune = $false
    if ($entry.status -eq "not_running" -and $entry.notRunningAt) {
        try {
            $hoursSince = ((Get-Date) - [datetime]$entry.notRunningAt).TotalHours
            if ($hoursSince -ge $hoursToSaveSessionHistory) { $shouldPrune = $true }
        } catch { }
    }

    if ($shouldPrune) { $prunedCount++ } else { $reconciledList.Add($entry) }
}
$instancesList = $reconciledList

$newEntry = [pscustomobject]@{
    id            = $instanceId
    terminalId    = $selectedTerminalId
    terminalName  = $selectedTerminalName
    pid           = $recordedPid
    pidConfirmed  = $pidConfirmed
    launcher      = $launcherName
    initialPrompt = $resolvedPrompt
    workspaceRoot = $resolvedDirectory
    launchedAt    = (Get-Date).ToString("o")
    status        = "running"
    notRunningAt  = $null
    completedAt   = $null
}
$instancesList.Add($newEntry)
$registry | Add-Member -NotePropertyName "instances" -NotePropertyValue $instancesList.ToArray() -Force

try {
    ($registry | ConvertTo-Json -Depth 6) | Set-Content -Path $registryPath -Encoding UTF8
} catch {
    Write-Result @{
        status               = "error"
        instanceId           = $instanceId
        selectedTerminalId   = $selectedTerminalId
        selectedTerminalName = $selectedTerminalName
        pid                  = $recordedPid
        pidConfirmed         = $pidConfirmed
        launcher             = $launcherName
        resolvedPrompt       = $resolvedPrompt
        resolvedDirectory    = $resolvedDirectory
        error                = "Terminal launched (PID $recordedPid) but failed to write SDP-Terminal-Sessions.json: $($_.Exception.Message)"
    }
    exit 1
}

Write-Result @{
    status                 = "success"
    instanceId             = $instanceId
    selectedTerminalId     = $selectedTerminalId
    selectedTerminalName   = $selectedTerminalName
    pid                    = $recordedPid
    pidConfirmed           = $pidConfirmed
    launcher               = $launcherName
    resolvedPrompt         = $resolvedPrompt
    resolvedDirectory      = $resolvedDirectory
    resolvedPermissionMode = $configuredPermissionMode
    markedNotRunningCount  = $markedNotRunningCount
    prunedCount            = $prunedCount
    error                  = $null
}
exit 0
