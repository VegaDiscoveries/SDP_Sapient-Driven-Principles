<#
.SYNOPSIS
    Manifest-driven SDP workspace precondition check engine. Runs every deterministic
    precondition (GPG presence/version, skill+script file existence, config/folder/document-list
    scaffolding) from a single declarative manifest (SDP-Workspace-Setup.json) and emits a
    uniform JSON envelope. One PowerShell call replaces dozens of per-session file-existence
    operations, and the canonical check inventory lives in one place as data.

.PARAMETER workspaceRoot
    Path to the workspace root. Defaults to two levels above this script
    (sdp-shared/scripts/), matching the sdp-tone.ps1 / sdp-github.ps1 convention.

.PARAMETER Scope
    Which manifest entries apply: coordinator | gate | setup. v1 runs the full manifest
    regardless of scope; the value is echoed in the envelope for forward compatibility.

.PARAMETER Force
    Bypass the per-tier staleness gates and run every tier (due or not). For a human
    re-running the coordinator after clearing a halt who wants a full re-check. The
    sdp-project-state-loop loop honors the timers; an explicit human invocation may force.

.PARAMETER WhatIf
    Resolve the check list and the tier-gate decision (which tiers are due) to JSON WITHOUT
    reading the target files and WITHOUT writing the timestamp. Dry-run channel and primary
    Pester hook (the sdp-tone.ps1 -whatIf / sdp-github.ps1 -WhatIf precedent).

.NOTES
    Manifest contract - SDP-Workspace-Setup.json is a JSON array of check objects. Each has a
    "type" and a "tier" (setup | integrity) plus type-specific fields:
      file-exists        { path }                         passes when the file exists
      file-absent        { path }                         passes when the file does NOT exist
      dir-exists         { path }                         passes when the directory exists
      skill-pair         { name }                         passes when both
                                                          .claude/skills/<name>/SKILL.md and
                                                          sdp-shared/ai-skills/<name>/SKILL.md exist
      json-value         { file, pointer, match }         passes when the JSON value at pointer
                                                          satisfies match. match is either a
                                                          literal (value -eq match) or
                                                          "filename:<pattern>" where {} is
                                                          replaced by the value and the named
                                                          file must exist
      json-field-present { file, pointer }                passes when the JSON value at pointer
                                                          resolves to anything non-null (including
                                                          false) - presence only, no value
                                                          comparison. Use this over json-value when
                                                          the field is user-editable policy (e.g. a
                                                          feature toggle) and any set value, not
                                                          just one specific one, should pass
      json-last-include  { file, path }                   passes when, in the JSON array file,
                                                          path is the LAST entry with
                                                          includeInReadDocs:true
      hook-registered    { file, event, commandContains } passes when, under
                                                          .hooks.<event> (an array of groups each
                                                          with a .hooks array of steps), any
                                                          step's .command or joined .args
                                                          contains commandContains
      json-array-contains { file, pointer, value }        passes when the array at pointer
                                                          contains an element string-equal to
                                                          value
      glob-exists        { pattern }                      passes when a workspace-relative glob
                                                          (dir portion + filename pattern) matches
                                                          at least one file
      command-available  { command }                      passes when an executable named
                                                          `command` resolves on PATH (Get-Command)
      json-threshold-order { file, pointers, floor? }      passes when the numeric values at each
                                                          pointer (in array order) are strictly
                                                          ascending, and (if `floor` is present)
                                                          the first pointer's value exceeds it

    Tier staleness gate - policy and facts are stored separately by owner:
      SDP-Config.json     preflight.setupValidationIntervalHours / .integrityValidationIntervalHours
                          (user-owned policy; interval 0 = always run)
      state.json          preflight.last_setup_validation / .last_integrity_validation
                          (machine-written facts; the script's only write)
    A tier runs when (now - last_run[tier]) >= interval, or when last_run is absent (fresh
    workspace), or under -Force. On a clean full pass of a tier the script writes that tier's
    timestamp back to state.json (UTF-8 no BOM). A tier with any failure does NOT advance its
    timestamp, so the next run re-checks it.

    Manifest scope resolution - which manifest file applies to -workspaceRoot is resolved
    automatically, not passed as a parameter. A sdp-project_* path segment anywhere in
    -workspaceRoot is definitive and wins unconditionally -> SDP-Workspace-Setup.json.
    Otherwise, SDP-Solution.json at -workspaceRoot decides: absent -> operational error
    (no marker resolvable); present with last_active_projects == ["."] (legacy single-project
    collapse) -> SDP-Workspace-Setup.json; present with any other last_active_projects ->
    SDP-Solution-Setup.json. The resolved filename (or $null if resolution itself failed) is
    always echoed back as manifestUsed.

    Stdout contract - exactly one compact JSON line:
      { "ok": <bool>, "command": "preflight", "scope": "<scope>",
        "manifestUsed": <null|string>,
        "tiersRun": [...], "tiersSkipped": [...],
        "checks": [ { "name": "...", "ok": <bool|null>, "detail": <null|string> } ],
        "failures": [...], "error": <null|string> }
      ok    - did every RUN check pass (skipped tiers do not affect ok)
      manifestUsed - the resolved manifest filename ("SDP-Workspace-Setup.json" or
              "SDP-Solution-Setup.json"), or null when manifest scope resolution itself failed
      error - null on success; a human-readable message on an OPERATIONAL error
              (manifest scope unresolvable, manifest missing/unparseable, state.json unreadable,
              state write failed)

    Exit codes (matches sdp-github.ps1):
      0  whenever the script itself ran correctly - INCLUDING a run that found failures
         (a failed check is a successful observation; the caller branches on ok / failures).
      1  only on an operational/script error. The error envelope is still emitted before exit.

    The script does NOT halt the workflow or mutate workflow_status - the calling skill decides
    what to do with failures. The only write is the per-tier timestamp on a clean pass.
#>
param(
    [string]$workspaceRoot = "",
    [ValidateSet("coordinator", "gate", "setup")]
    [string]$Scope = "coordinator",
    [switch]$Force,
    [switch]$WhatIf
)

if (-not $workspaceRoot) {
    $workspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

# Default staleness intervals (hours) when SDP-Config.json has no preflight block.
$DefaultSetupIntervalHours     = 24
$DefaultIntegrityIntervalHours = 1

# ---------------------------------------------------------------------------
# Emitter - single point of control for the stdout envelope.
# ---------------------------------------------------------------------------

function Write-Result($obj) {
    Write-Output ($obj | ConvertTo-Json -Compress -Depth 8)
}

function New-OperationalError([string]$message, [string]$manifestUsed = $null) {
    return [ordered]@{
        ok           = $false
        command      = "preflight"
        scope        = $Scope
        manifestUsed = $manifestUsed
        tiersRun     = @()
        tiersSkipped = @()
        checks       = @()
        failures     = @()
        error        = $message
    }
}

# ---------------------------------------------------------------------------
# Path helpers
# ---------------------------------------------------------------------------

function Resolve-WsPath([string]$relative) {
    # Accept forward or back slashes in manifest data; split and rejoin with the platform-native separator.
    $parts = $relative -split '[/\\]' | Where-Object { $_ -ne '' }
    $result = $workspaceRoot
    foreach ($p in $parts) { $result = Join-Path $result $p }
    return $result
}

function Get-JsonPointerValue($obj, [string]$pointer) {
    # Walk a dotted pointer (e.g. "gpg_version" or "preflight.last_setup_validation")
    # across PSCustomObject properties. Returns $null if any segment is absent.
    $current = $obj
    foreach ($segment in ($pointer -split '\.')) {
        if ($null -eq $current) { return $null }
        $prop = $current.PSObject.Properties[$segment]
        if (-not $prop) { return $null }
        $current = $prop.Value
    }
    return $current
}

# ---------------------------------------------------------------------------
# Validators - one per check type. None throws; an unexpected condition is
# caught by the dispatcher (Test-Check) and surfaced as ok:false with a detail.
# Each returns @{ ok = <bool>; detail = <null|string> }.
# ---------------------------------------------------------------------------

function Test-FileExists($check) {
    $p = Resolve-WsPath $check.path
    if (Test-Path -LiteralPath $p -PathType Leaf) {
        return @{ ok = $true; detail = $null }
    }
    return @{ ok = $false; detail = "file missing: $($check.path)" }
}

function Test-FileAbsent($check) {
    $p = Resolve-WsPath $check.path
    if (Test-Path -LiteralPath $p -PathType Leaf) {
        return @{ ok = $false; detail = "file must not exist: $($check.path)" }
    }
    return @{ ok = $true; detail = $null }
}

function Test-DirExists($check) {
    $p = Resolve-WsPath $check.path
    if (Test-Path -LiteralPath $p -PathType Container) {
        return @{ ok = $true; detail = $null }
    }
    return @{ ok = $false; detail = "directory missing: $($check.path)" }
}

function Test-SkillPair($check) {
    $l1 = Resolve-WsPath ".claude/skills/$($check.name)/SKILL.md"
    $l2 = Resolve-WsPath "sdp-shared/ai-skills/$($check.name)/SKILL.md"
    $l1ok = Test-Path -LiteralPath $l1 -PathType Leaf
    $l2ok = Test-Path -LiteralPath $l2 -PathType Leaf
    if ($l1ok -and $l2ok) { return @{ ok = $true; detail = $null } }
    $missing = @()
    if (-not $l1ok) { $missing += ".claude/skills/$($check.name)/SKILL.md" }
    if (-not $l2ok) { $missing += "sdp-shared/ai-skills/$($check.name)/SKILL.md" }
    return @{ ok = $false; detail = "skill-pair incomplete: missing $($missing -join ', ')" }
}

function Test-JsonValue($check) {
    $p = Resolve-WsPath $check.file
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        return @{ ok = $false; detail = "json file missing: $($check.file)" }
    }
    $json = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
    $value = Get-JsonPointerValue $json $check.pointer
    if ($null -eq $value) {
        return @{ ok = $false; detail = "pointer not found: $($check.pointer) in $($check.file)" }
    }
    $match = "$($check.match)"
    if ($match -like "filename:*") {
        $pattern  = $match.Substring("filename:".Length)
        $resolved = $pattern.Replace("{}", "$value")
        $target   = Resolve-WsPath $resolved
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            return @{ ok = $true; detail = $null }
        }
        return @{ ok = $false; detail = "expected file from $($check.pointer)='$value' not found: $resolved" }
    }
    if ("$value" -eq $match) { return @{ ok = $true; detail = $null } }
    return @{ ok = $false; detail = "value mismatch at $($check.pointer): got '$value', expected '$match'" }
}

function Test-JsonFieldPresent($check) {
    $p = Resolve-WsPath $check.file
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        return @{ ok = $false; detail = "json file missing: $($check.file)" }
    }
    $json = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
    $value = Get-JsonPointerValue $json $check.pointer
    if ($null -eq $value) {
        return @{ ok = $false; detail = "pointer not found: $($check.pointer) in $($check.file)" }
    }
    return @{ ok = $true; detail = $null }
}

function Test-JsonLastInclude($check) {
    $p = Resolve-WsPath $check.file
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        return @{ ok = $false; detail = "json file missing: $($check.file)" }
    }
    $arr = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
    $included = @($arr | Where-Object { $_.includeInReadDocs -eq $true })
    if ($included.Count -eq 0) {
        return @{ ok = $false; detail = "no entries with includeInReadDocs:true in $($check.file)" }
    }
    $last = $included[$included.Count - 1]
    if ("$($last.path)" -eq "$($check.path)") {
        return @{ ok = $true; detail = $null }
    }
    return @{ ok = $false; detail = "last includeInReadDocs:true entry is '$($last.path)', expected '$($check.path)'" }
}

function Test-HookRegistered($check) {
    $p = Resolve-WsPath $check.file
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        return @{ ok = $false; detail = "file missing: $($check.file)" }
    }
    $json = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
    $groups = $null
    if ($json.hooks) { $groups = $json.hooks.PSObject.Properties[$check.event] }
    if (-not $groups -or -not $groups.Value) {
        return @{ ok = $false; detail = "hook event not found: $($check.event) in $($check.file)" }
    }
    foreach ($group in @($groups.Value)) {
        if (-not $group.hooks) { continue }
        foreach ($step in @($group.hooks)) {
            $command = "$($step.command)"
            $argsJoined = if ($step.args) { (@($step.args) -join ' ') } else { "" }
            if ($command.Contains($check.commandContains) -or $argsJoined.Contains($check.commandContains)) {
                return @{ ok = $true; detail = $null }
            }
        }
    }
    return @{ ok = $false; detail = "commandContains '$($check.commandContains)' not found under hooks.$($check.event) in $($check.file)" }
}

function Test-JsonArrayContains($check) {
    $p = Resolve-WsPath $check.file
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        return @{ ok = $false; detail = "json file missing: $($check.file)" }
    }
    $json = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
    $value = Get-JsonPointerValue $json $check.pointer
    $isEnumerable = ($null -ne $value) -and ($value -isnot [string]) -and ($value -is [System.Collections.IEnumerable] -or $value -is [array])
    if (-not $isEnumerable) {
        return @{ ok = $false; detail = "pointer not found or not an array: $($check.pointer) in $($check.file)" }
    }
    foreach ($el in @($value)) {
        if ("$el" -eq $check.value) { return @{ ok = $true; detail = $null } }
    }
    return @{ ok = $false; detail = "value not found in array at $($check.pointer): '$($check.value)'" }
}

function Test-GlobExists($check) {
    $pattern = $check.pattern
    $lastSlash = [Math]::Max($pattern.LastIndexOf('/'), $pattern.LastIndexOf('\'))
    if ($lastSlash -ge 0) {
        $dirPart  = $pattern.Substring(0, $lastSlash)
        $leafPart = $pattern.Substring($lastSlash + 1)
    } else {
        $dirPart  = ""
        $leafPart = $pattern
    }
    $dir = if ($dirPart) { Resolve-WsPath $dirPart } else { $workspaceRoot }
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        return @{ ok = $false; detail = "directory missing for glob: $($check.pattern)" }
    }
    $matches = @(Get-ChildItem -LiteralPath $dir -Filter $leafPart -File -ErrorAction SilentlyContinue)
    if ($matches.Count -gt 0) {
        return @{ ok = $true; detail = $null }
    }
    return @{ ok = $false; detail = "no file matches glob: $($check.pattern)" }
}

function Test-JsonThresholdOrder($check) {
    # Validates a chain of numeric JSON pointers is in strictly ascending order, with an optional
    # lower floor for the first pointer. Added for sessionSubagentBudget sanity (respawnAtCount <
    # hardStopCount < maxSubagentsPerSession, respawnAtCount above a sane floor) - see the
    # subagent-budget-respawn-design.md Pros-Cons-Gaps resolution (Gap 5, merged with Gap 2).
    $p = Resolve-WsPath $check.file
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        return @{ ok = $false; detail = "json file missing: $($check.file)" }
    }
    $json = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
    $values = @()
    foreach ($ptr in @($check.pointers)) {
        $v = Get-JsonPointerValue $json $ptr
        if ($null -eq $v) {
            return @{ ok = $false; detail = "pointer not found: $ptr in $($check.file)" }
        }
        $numeric = 0.0
        if (-not [double]::TryParse("$v", [ref]$numeric)) {
            return @{ ok = $false; detail = "pointer value not numeric: $ptr = '$v' in $($check.file)" }
        }
        $values += $numeric
    }
    if (($null -ne $check.floor) -and ($values.Count -gt 0)) {
        $floor = [double]$check.floor
        if ($values[0] -le $floor) {
            return @{ ok = $false; detail = "$($check.pointers[0]) ($($values[0])) must be greater than floor ($floor)" }
        }
    }
    for ($i = 1; $i -lt $values.Count; $i++) {
        if ($values[$i] -le $values[$i - 1]) {
            return @{ ok = $false; detail = "$($check.pointers[$i]) ($($values[$i])) must be greater than $($check.pointers[$i - 1]) ($($values[$i - 1]))" }
        }
    }
    return @{ ok = $true; detail = $null }
}

function Test-CommandAvailable($check) {
    # PATH-only check - deliberately does not care whether the resolved executable is a shell
    # builtin, script, or binary. Environment tooling (git, python) is not workspace-relative,
    # so this validator never calls Resolve-WsPath.
    $found = Get-Command -Name $check.command -ErrorAction SilentlyContinue
    if ($found) {
        return @{ ok = $true; detail = $null }
    }
    return @{ ok = $false; detail = "command not found on PATH: $($check.command)" }
}

# ---------------------------------------------------------------------------
# Check naming + dispatch
# ---------------------------------------------------------------------------

function Get-CheckName($check) {
    switch ($check.type) {
        "file-exists"       { return "file-exists:$($check.path)" }
        "file-absent"       { return "file-absent:$($check.path)" }
        "dir-exists"        { return "dir-exists:$($check.path)" }
        "skill-pair"        { return "skill-pair:$($check.name)" }
        "json-value"        { return "json-value:$($check.pointer)" }
        "json-field-present" { return "json-field-present:$($check.pointer)" }
        "json-last-include" { return "json-last-include:$($check.path)" }
        "hook-registered"     { return "hook-registered:$($check.event)" }
        "json-array-contains" { return "json-array-contains:$($check.pointer)" }
        "glob-exists"          { return "glob-exists:$($check.pattern)" }
        "command-available"    { return "command-available:$($check.command)" }
        "json-threshold-order" { return "json-threshold-order:$($check.file):$(($check.pointers) -join ',')" }
        default             { return "unknown:$($check.type)" }
    }
}

function Test-Check($check) {
    # Dispatch to the matching validator. A validator never throws on a normal
    # failed-check path; this try/catch is the backstop for an unexpected condition
    # (e.g. malformed JSON in a target file) so it surfaces as ok:false, not an
    # unhandled exception.
    $name = Get-CheckName $check
    try {
        $r = switch ($check.type) {
            "file-exists"       { Test-FileExists $check }
            "file-absent"       { Test-FileAbsent $check }
            "dir-exists"        { Test-DirExists $check }
            "skill-pair"        { Test-SkillPair $check }
            "json-value"        { Test-JsonValue $check }
            "json-field-present" { Test-JsonFieldPresent $check }
            "json-last-include" { Test-JsonLastInclude $check }
            "hook-registered"     { Test-HookRegistered $check }
            "json-array-contains" { Test-JsonArrayContains $check }
            "glob-exists"          { Test-GlobExists $check }
            "command-available"    { Test-CommandAvailable $check }
            "json-threshold-order" { Test-JsonThresholdOrder $check }
            default             { @{ ok = $false; detail = "unknown check type: $($check.type)" } }
        }
        return [ordered]@{ name = $name; ok = [bool]$r.ok; detail = $r.detail }
    } catch {
        return [ordered]@{ name = $name; ok = $false; detail = "check error: $($_.Exception.Message)" }
    }
}

# ---------------------------------------------------------------------------
# Policy (SDP-Config.json) and facts (state.json) for the staleness gate.
# Policy is user-owned and only read; facts are machine-written by this script.
# ---------------------------------------------------------------------------

function Get-Policy {
    $policy = [ordered]@{
        setup     = $DefaultSetupIntervalHours
        integrity = $DefaultIntegrityIntervalHours
    }
    $path = Join-Path $workspaceRoot "SDP-Config.json"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $policy }
    try {
        $cfg = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($cfg.preflight) {
            if ($null -ne $cfg.preflight.setupValidationIntervalHours)     { $policy.setup     = [int]$cfg.preflight.setupValidationIntervalHours }
            if ($null -ne $cfg.preflight.integrityValidationIntervalHours) { $policy.integrity = [int]$cfg.preflight.integrityValidationIntervalHours }
        }
    } catch { }
    return $policy
}

function Get-StateInfo {
    # Returns @{ exists; parseable; facts = @{ setup; integrity } }. A present-but-unparseable
    # state.json is an OPERATIONAL error (the caller decides to exit 1); an absent state.json is
    # the fresh-workspace case - facts are simply null and every tier is due.
    $info = [ordered]@{
        exists     = $false
        parseable  = $true
        facts      = [ordered]@{ setup = $null; integrity = $null }
    }
    $path = Resolve-WsPath ".sdp-workflow/state.json"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $info }
    $info.exists = $true
    try {
        $state = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($state.preflight) {
            if ($state.preflight.last_setup_validation)     { $info.facts.setup     = "$($state.preflight.last_setup_validation)" }
            if ($state.preflight.last_integrity_validation) { $info.facts.integrity = "$($state.preflight.last_integrity_validation)" }
        }
    } catch {
        $info.parseable = $false
    }
    return $info
}

function Test-TierDue([string]$lastRun, [int]$intervalHours) {
    if ($Force)                 { return $true }   # explicit human override
    if ($intervalHours -le 0)   { return $true }   # interval 0 => always run
    if (-not $lastRun)          { return $true }   # fresh workspace / first run
    try {
        $last = [datetime]::Parse($lastRun, [System.Globalization.CultureInfo]::InvariantCulture)
    } catch {
        return $true   # unparseable timestamp => treat as due
    }
    $elapsedHours = ((Get-Date) - $last).TotalHours
    return ($elapsedHours -ge $intervalHours)
}

function Write-TierTimestamp([string]$tier) {
    # Write only the preflight facts block back to state.json, preserving the rest of the file.
    # UTF-8 no BOM (the sdp-create-prompt.ps1 encoding-hardening lesson). Returns $true on a
    # successful write, $false if the write itself failed (operational error). A missing
    # state.json is a no-op success - there is nowhere to record facts on a fresh workspace and
    # creating a partial state.json would be wrong.
    $path = Resolve-WsPath ".sdp-workflow/state.json"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $true }
    try {
        $state = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $state.PSObject.Properties["preflight"]) {
            $state | Add-Member -NotePropertyName "preflight" -NotePropertyValue ([PSCustomObject]@{})
        }
        $stamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
        $field = "last_${tier}_validation"
        if ($state.preflight.PSObject.Properties[$field]) {
            $state.preflight.$field = $stamp
        } else {
            $state.preflight | Add-Member -NotePropertyName $field -NotePropertyValue $stamp
        }
        $jsonText = $state | ConvertTo-Json -Depth 20
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($path, $jsonText, $utf8NoBom)
        return $true
    } catch {
        return $false
    }
}

# ---------------------------------------------------------------------------
# Manifest scope resolution - which manifest file applies to $workspaceRoot.
# A sdp-project_* path segment is definitive (project manifest, checked first,
# regardless of anything else present at $root). Otherwise SDP-Solution.json's
# presence/content decides between the solution manifest and the legacy
# single-project collapse. Neither marker present -> $null (operational error,
# never a silent guess).
# ---------------------------------------------------------------------------

function Resolve-ManifestFilename([string]$root) {
    $segments = $root -split '[/\\]' | Where-Object { $_ -ne '' }
    if ($segments | Where-Object { $_ -like 'sdp-project_*' }) {
        return "SDP-Workspace-Setup.json"
    }

    $solutionMarker = Join-Path $root "SDP-Solution.json"
    if (-not (Test-Path -LiteralPath $solutionMarker -PathType Leaf)) {
        return $null   # neither marker present - operational error, not a silent guess
    }

    # Legacy single-project collapse (last_active_projects == ["."]) still resolves to the
    # project manifest - the same collapse the bootstrap doc's own Level 3 already documents.
    try {
        $sol = Get-Content -LiteralPath $solutionMarker -Raw -Encoding UTF8 | ConvertFrom-Json
        $lap = @($sol.last_active_projects)
        if ($lap.Count -eq 1 -and $lap[0] -eq '.') {
            return "SDP-Workspace-Setup.json"
        }
    } catch {
        return $null
    }
    return "SDP-Solution-Setup.json"
}

# ---------------------------------------------------------------------------
# Load manifest (operational error on missing/unparseable).
# ---------------------------------------------------------------------------

$manifestFilename = Resolve-ManifestFilename $workspaceRoot
if (-not $manifestFilename) {
    Write-Result (New-OperationalError "no manifest resolvable: neither a sdp-project_* path segment nor SDP-Solution.json found under -workspaceRoot" $null)
    exit 1
}

$manifestPath = Join-Path $workspaceRoot $manifestFilename
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    Write-Result (New-OperationalError "manifest not found: $manifestFilename" $manifestFilename)
    exit 1
}

$manifest = $null
try {
    # Assign first, then wrap. Windows PowerShell 5.1 ConvertFrom-Json emits a multi-element
    # array as a SINGLE pipeline object, so @(Get-Content | ConvertFrom-Json) would double-wrap
    # into a 1-element array holding the real array. Capturing to a variable, then @($var),
    # yields a correctly flat array for both the single-object and multi-object cases.
    $parsed = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $manifest = @($parsed)
} catch {
    Write-Result (New-OperationalError "manifest unparseable: $($_.Exception.Message)" $manifestFilename)
    exit 1
}

# ---------------------------------------------------------------------------
# Last-resort guard. The manifest load above surfaces its own operational
# errors; everything from here on is wrapped so a bug in the orchestration - or
# an unexpected terminating throw from a helper, or from Write-Result /
# ConvertTo-Json itself - still surfaces as a clean error envelope rather than
# an unhandled exception with no JSON line on stdout (the caller reads exactly
# that one line). Mirrors the sdp-github.ps1 dispatch guard. The exit 0 / exit 1
# statements inside terminate the process directly and do not trip the catch.
# ---------------------------------------------------------------------------

try {

    # -----------------------------------------------------------------------
    # Resolve the tier-gate decision. A tier appears in tiersRun / tiersSkipped
    # only if the manifest actually contains checks for it.
    # -----------------------------------------------------------------------

    $policy    = Get-Policy
    $stateInfo = Get-StateInfo

    if ($stateInfo.exists -and -not $stateInfo.parseable) {
        Write-Result (New-OperationalError "state.json unreadable: present but failed to parse" $manifestFilename)
        exit 1
    }

    $tiersPresent = @($manifest | ForEach-Object { $_.tier } | Select-Object -Unique)
    $tierDue = @{}
    foreach ($tier in $tiersPresent) {
        $interval = if ($policy.Contains($tier)) { [int]$policy[$tier] } else { 0 }
        $last     = if ($stateInfo.facts.Contains($tier)) { $stateInfo.facts[$tier] } else { $null }
        $tierDue[$tier] = Test-TierDue $last $interval
    }

    $tiersRun     = @($tiersPresent | Where-Object { $tierDue[$_] })
    $tiersSkipped = @($tiersPresent | Where-Object { -not $tierDue[$_] })

    # -----------------------------------------------------------------------
    # -WhatIf - resolve the plan (checks + due-tier decision) without reading
    # any target file and without writing the timestamp.
    # -----------------------------------------------------------------------

    if ($WhatIf) {
        $planned = @($manifest | ForEach-Object {
            [ordered]@{ name = (Get-CheckName $_); tier = $_.tier; ok = $null; detail = "(whatif - not evaluated)" }
        })
        Write-Result ([ordered]@{
            ok           = $true
            command      = "preflight"
            scope        = $Scope
            manifestUsed = $manifestFilename
            whatIf       = $true
            tiersRun     = $tiersRun
            tiersSkipped = $tiersSkipped
            checks       = $planned
            failures     = @()
            error        = $null
        })
        exit 0
    }

    # -----------------------------------------------------------------------
    # Run the checks for due tiers, grouped by tier so each tier's pass/fail is
    # known independently (timestamp advances per clean tier).
    # -----------------------------------------------------------------------

    $allResults   = New-Object System.Collections.ArrayList
    $tierAllPass  = @{}
    foreach ($tier in $tiersRun) { $tierAllPass[$tier] = $true }

    foreach ($check in $manifest) {
        if (-not ($tiersRun -contains $check.tier)) { continue }
        $res = Test-Check $check
        [void]$allResults.Add($res)
        if (-not $res.ok) { $tierAllPass[$check.tier] = $false }
    }

    $checks   = @($allResults)
    $failures = @($checks | Where-Object { -not $_.ok } | ForEach-Object { $_.name })
    $ok       = ($failures.Count -eq 0)

    # -----------------------------------------------------------------------
    # Write-back: advance each cleanly-passing tier's timestamp. A failing tier
    # leaves its timestamp unchanged so the next run re-checks it. A failed
    # state write is an operational error (exit 1) but the envelope is still
    # emitted.
    # -----------------------------------------------------------------------

    $writeError = $null
    foreach ($tier in $tiersRun) {
        if ($tierAllPass[$tier]) {
            if (-not (Write-TierTimestamp $tier)) {
                $writeError = "failed to write ${tier} validation timestamp to state.json"
            }
        }
    }

    # -----------------------------------------------------------------------
    # Emit envelope. Exit 0 on any clean run (including one with failed checks);
    # exit 1 only on an operational error (a state write that failed).
    # -----------------------------------------------------------------------

    Write-Result ([ordered]@{
        ok           = $ok
        command      = "preflight"
        scope        = $Scope
        manifestUsed = $manifestFilename
        tiersRun     = $tiersRun
        tiersSkipped = $tiersSkipped
        checks       = $checks
        failures     = $failures
        error        = $writeError
    })

    if ($writeError) { exit 1 }
    exit 0

} catch {
    # A bug in the orchestration must still surface as a clean error envelope,
    # never an unhandled exception. exit 1 - operational error.
    Write-Result (New-OperationalError "Unhandled script error: $($_.Exception.Message)" $manifestFilename)
    exit 1
}
