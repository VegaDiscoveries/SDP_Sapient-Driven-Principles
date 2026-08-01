<#
.SYNOPSIS
    Async PreToolUse/PostToolUse/UserPromptSubmit hook target - appends a structured JSON line to
    the day's hook-log file for tool calls and human prompt submissions that
    sdp-hook-log-tools.json marks as loggable. UserPromptSubmit fires only for a human-typed
    prompt in the top-level session (never for subagent dispatch), so it needs no agent_id
    filtering the way tool-call entries do.

.PARAMETER (none)
    This script takes no CLI parameters. The hook event payload (session_id, hook_event_name,
    tool_name, tool_input, tool_output, agent_id, cwd, etc.) is read from stdin as a single JSON
    object, per Claude Code's command hook contract.

.NOTES
    Stdout: nothing. Exit code: always 0.
    Registered as an async ("async": true) command hook for both PreToolUse and PostToolUse with
    no matcher (fires for every tool). Async hooks have their exit code and stdout ignored by
    Claude Code, so this script can never block, deny, or otherwise influence the tool call it is
    observing - confirmed against the Claude Code hooks reference before this script was written.
    Exits silently (exit 0) under every failure condition - this is a pure side-effect logger and
    must never surface as an error to the invoking session.

    Reads sdp-hook-log-tools.json from sdp-shared/scripts/script-support/ (a sibling folder to
    this script) to decide, per tool_name, whether to log this direction (Pre/Post), at what level
    (TIMING/AUDIT/HUMAN_WAIT/DEBUG), and whether subagent-originated calls (agent_id present)
    should be included. Tools not listed fall back to the config's defaultForUnlistedTools entry.
    The same parsed config object's top-level "truncation" block supplies maxFieldChars and
    debugFullCapture (see Get-TruncatedValue below) - no separate file read for these. Its
    "userPromptSubmit" block (enabled/level) separately gates the UserPromptSubmit branch below,
    since that event isn't a tool call and doesn't fit the per-tool_name "tools" map.

    Writes one JSON line per firing to .sdp-solution-workflow/logging/hook-logs/hook-log-
    <local yyyyMMdd>.jsonl. One file per local calendar day (not UTC), by design, so report
    authors never need to translate a date. On the first firing of each local day (i.e. when
    today's file does not yet exist), also sweeps hook-logs/ for files older than $retentionDays
    and deletes them - the only time the sweep runs, so every other firing pays a single
    Test-Path and nothing more.

    work_item is resolved best-effort: reads SDP-Solution.json's last_active_projects[0], then
    that project's .sdp-workflow/state.json active_work_item. Null if either step fails or is
    absent - this must never block the write.

    tool_input/tool_output are walked field-by-field (Get-TruncatedValue) and any individual
    string leaf longer than maxFieldChars is wrapped as {"_truncated": true, "value": "..."} in
    place - sibling fields (e.g. a short "description" next to a long "prompt") are never
    sacrificed just because a neighboring field ran long. maxFieldChars and debugFullCapture are
    read from sdp-hook-log-tools.json's "truncation" block on every firing; debugFullCapture=true
    disables truncation entirely for that firing.
#>

$retentionDays = 190
$defaultMaxFieldChars = 1000

$workspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

$stdin = [Console]::In.ReadToEnd()
if (-not $stdin) { exit 0 }

try { $payload = $stdin | ConvertFrom-Json } catch { exit 0 }

$hookEvent = $payload.hook_event_name
if ($hookEvent -ne "PreToolUse" -and $hookEvent -ne "PostToolUse" -and $hookEvent -ne "UserPromptSubmit") { exit 0 }

$isPromptSubmit = ($hookEvent -eq "UserPromptSubmit")
$toolName = $payload.tool_name
if (-not $isPromptSubmit -and -not $toolName) { exit 0 }

$configPath = Join-Path $PSScriptRoot "script-support/sdp-hook-log-tools.json"
if (-not (Test-Path $configPath)) { exit 0 }
try { $config = [string](Get-Content $configPath -Raw -Encoding UTF8) | ConvertFrom-Json } catch { exit 0 }

# Truncation settings live in this same already-parsed config object (see .NOTES above) -
# no second file read. Any missing/invalid value falls back to the hardcoded default silently.
$maxFieldChars = $defaultMaxFieldChars
$debugFullCapture = $false
try {
    if ($config.truncation) {
        $cfgMax = $config.truncation.maxFieldChars
        if ($null -ne $cfgMax -and ($cfgMax -as [double]) -and ([double]$cfgMax -gt 0)) {
            $maxFieldChars = [int][double]$cfgMax
        }
        if ($config.truncation.debugFullCapture -eq $true) { $debugFullCapture = $true }
    }
} catch { }

# UserPromptSubmit never fires for a dispatched subagent (confirmed against the Claude Code hooks
# reference - it only fires for a human-submitted prompt in the top-level session), so it needs no
# tool-name gate, Pre/Post direction, or subagent-origin filter - just its own on/off switch and
# level, read from a dedicated config block since it isn't a tool call.
if ($isPromptSubmit) {
    $upsCfg = $config.userPromptSubmit
    if (-not $upsCfg -or $upsCfg.enabled -ne $true) { exit 0 }
    $level = if ($upsCfg.level) { $upsCfg.level } else { "AUDIT" }
} else {
    $toolCfg = $config.tools.$toolName
    if (-not $toolCfg) { $toolCfg = $config.defaultForUnlistedTools }
    if (-not $toolCfg) { exit 0 }

    $isSubagent = [bool]$payload.agent_id
    if ($isSubagent -and $toolCfg.includeSubagentOrigin -eq $false) { exit 0 }

    $directionFlag = if ($hookEvent -eq "PreToolUse") { $toolCfg.logPre } else { $toolCfg.logPost }
    if ($directionFlag -ne $true) { exit 0 }
    $level = $toolCfg.level
}

# Best-effort work_item resolution - a lookup failure here must never block the log write.
$workItem = $null
try {
    $solutionPath = Join-Path $workspaceRoot "SDP-Solution.json"
    if (Test-Path $solutionPath) {
        $solution = [string](Get-Content $solutionPath -Raw -Encoding UTF8) | ConvertFrom-Json
        $activeProject = $null
        if ($solution.last_active_projects -and $solution.last_active_projects.Count -gt 0) {
            $activeProject = $solution.last_active_projects[0]
        }
        if ($activeProject) {
            $statePath = Join-Path $workspaceRoot "$activeProject/.sdp-workflow/state.json"
            if (Test-Path $statePath) {
                $state = [string](Get-Content $statePath -Raw -Encoding UTF8) | ConvertFrom-Json
                if ($state.active_work_item) { $workItem = $state.active_work_item }
            }
        }
    }
} catch { }

# Walks the object tree and truncates individual string leaves in place, rather than measuring/
# cutting the whole serialized blob - a long "prompt" next to a short "description" no longer
# costs the description its existence. Depth cap mirrors the -Depth 8 used by the final
# ConvertTo-Json call below; not expected to matter for the shallow shapes tool_input/tool_output
# actually take, kept only as a defensive bound.
function Get-TruncatedValue($value, $depth = 0) {
    if ($null -eq $value) { return $null }
    if ($depth -ge 8) { return $value }

    if ($value -is [string]) {
        if (-not $debugFullCapture -and $value.Length -gt $maxFieldChars) {
            return [pscustomobject]@{ _truncated = $true; value = $value.Substring(0, $maxFieldChars) }
        }
        return $value
    }
    if ($value -is [System.Management.Automation.PSCustomObject]) {
        $result = [ordered]@{}
        foreach ($prop in $value.PSObject.Properties) {
            $result[$prop.Name] = Get-TruncatedValue $prop.Value ($depth + 1)
        }
        return [pscustomobject]$result
    }
    if ($value -is [System.Collections.IEnumerable]) {
        return @($value | ForEach-Object { Get-TruncatedValue $_ ($depth + 1) })
    }
    return $value
}

function Get-CompactField($value) {
    if ($null -eq $value) { return $null }
    try {
        return Get-TruncatedValue $value
    } catch {
        return $null
    }
}

if ($isPromptSubmit) {
    $entry = [ordered]@{
        timestamp       = (Get-Date).ToString("o")
        hook_event_name = $hookEvent
        level           = $level
        tool_name       = $null
        session_id      = $payload.session_id
        agent_id        = $payload.agent_id
        work_item       = $workItem
        cwd             = $payload.cwd
        prompt_id       = $payload.prompt_id
        permission_mode = $payload.permission_mode
        transcript_path = $payload.transcript_path
        prompt          = Get-CompactField $payload.prompt
        tool_input      = $null
        tool_output     = $null
    }
} else {
    $entry = [ordered]@{
        timestamp       = (Get-Date).ToString("o")
        hook_event_name = $hookEvent
        level           = $level
        tool_name       = $toolName
        session_id      = $payload.session_id
        agent_id        = $payload.agent_id
        work_item       = $workItem
        cwd             = $payload.cwd
        tool_input      = Get-CompactField $payload.tool_input
        tool_output     = if ($hookEvent -eq "PostToolUse") { Get-CompactField $payload.tool_output } else { $null }
    }
}

$logDir = Join-Path $workspaceRoot ".sdp-solution-workflow/logging/hook-logs"
$stamp = (Get-Date).ToString("yyyyMMdd")
$logPath = Join-Path $logDir "hook-log-$stamp.jsonl"

if (-not (Test-Path $logPath)) {
    try {
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        # First firing of a new local day - sweep files older than $retentionDays. This block
        # runs only here, so every other firing pays a single Test-Path and nothing more.
        $cutoff = (Get-Date).AddDays(-$retentionDays)
        Get-ChildItem -Path $logDir -Filter "hook-log-*.jsonl" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $cutoff } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    } catch { }
}

try {
    $line = ($entry | ConvertTo-Json -Compress -Depth 8)
    # AppendAllText with an explicit no-BOM UTF8Encoding avoids Add-Content's PS 5.1 behavior of
    # writing a BOM on first creation, which would corrupt line 1's JSON parse.
    [System.IO.File]::AppendAllText($logPath, $line + "`n", (New-Object System.Text.UTF8Encoding($false)))
} catch { }

exit 0
