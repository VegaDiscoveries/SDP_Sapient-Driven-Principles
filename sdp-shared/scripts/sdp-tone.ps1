<#
.SYNOPSIS
    Play the configured SDP notification tone(s): a single skill start/end tone, or a multi-note
    workflow-event sequence.

.PARAMETER skillName
    The invoking skill name, e.g. "sdp-project-worker". Used with -event for the skill start/end channel.

.PARAMETER event
    "start" or "end". Used with -skillName.

.PARAMETER trigger
    A workflow trigger name, e.g. "halt.no_progress". Resolves a named sequence (+ profile) via the
    events table. This is a separate channel from -skillName/-event.

.PARAMETER whatIf
    Diagnostic switch. Resolve the full playback plan and write it as a single compact JSON line to
    stdout INSTEAD of producing sound. Without this switch the script writes nothing to stdout.
    Intended for deterministic testing without audio hardware.

.NOTES
    Reads SDP-Tones.json from sdp-shared/scripts/script-support/ (a sibling folder to this
    script).
    Exits silently (exit 0) under all failure conditions — tones are non-blocking by design.
    Channels:
      Skill tone : -skillName X -event start|end  ->  assignments -> palette -> single beep
      Workflow   : -trigger NAME                  ->  events -> sequences (+ profiles) -> note series
    Event lookup: first events entry whose trigger matches AND enabled is not false. profile defaults
    to "once"; repeat/gapMs on the binding override the named profile. A note element is either a
    palette id (string) or an inline {hz, ms[, gapMs]} object; hz <= 0 is a silent rest.
    Unknown/missing/disabled lookups are silent (no sound, no stdout unless -whatIf).

    Metrics: every real (non -whatIf) invocation on either channel that reaches a skillName+event
    pair or a trigger lookup appends one JSON line to today's
    loop-metrics-yyyyMMdd.jsonl file under .sdp-solution-workflow/logging/loop-logs/ at the
    workspace root (created on first write of the day) — this brackets subagent work
    (skill start/end) and workflow events (halts, milestones) independent of sdp-project-state-loop's own
    per-fire entries in the same file. -whatIf never writes to this file (diagnostic/test
    isolation). A metrics write failure is silently ignored — it must never affect tone playback
    or the exit code.
#>
param(
    [string]$skillName = "",
    [string]$event     = "",
    [string]$trigger   = "",
    [switch]$whatIf
)

# Locate SDP-Tones.json under script-support/, a sibling folder to this script
$workspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$configPath = Join-Path $PSScriptRoot "script-support/SDP-Tones.json"
if (-not (Test-Path $configPath)) { exit 0 }

try {
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
} catch { exit 0 }

if ($config.enabled -ne $true) { exit 0 }

function Emit-Plan($obj) {
    if ($whatIf) { Write-Output ($obj | ConvertTo-Json -Compress -Depth 6) }
}

# Solution-level metrics log (shared with sdp-project-state-loop's own per-fire entries in the same
# file). One dated file per calendar day, named loop-metrics-yyyyMMdd.jsonl — rotates purely on
# date, independent of any workflow action (loop start/stop, skill activity, etc.). Writes
# always target today's file; AppendAllText creates it on first write of the day, no explicit
# existence check needed.
$metricsDir = Join-Path $workspaceRoot ".sdp-solution-workflow/logging/loop-logs"

function Resolve-MetricsPath {
    if (-not (Test-Path $metricsDir)) {
        New-Item -ItemType Directory -Path $metricsDir -Force | Out-Null
    }
    $stamp = (Get-Date).ToString("yyyyMMdd")
    return (Join-Path $metricsDir "loop-metrics-$stamp.jsonl")
}

function Write-MetricsLine($obj) {
    if ($whatIf) { return }
    try {
        $metricsPath = Resolve-MetricsPath
        $line = ($obj | ConvertTo-Json -Compress -Depth 6)
        # AppendAllText with an explicit no-BOM UTF8Encoding avoids Add-Content's PS 5.1 behavior
        # of writing a BOM on first creation, which would corrupt line 1's JSON parse.
        [System.IO.File]::AppendAllText($metricsPath, $line + "`n", (New-Object System.Text.UTF8Encoding($false)))
    } catch { }
}

# ──────────────────────────────────────────────────────────────────────────
# Workflow-event channel
# ──────────────────────────────────────────────────────────────────────────
if ($trigger) {
    if (-not $config.events) {
        Emit-Plan @{ resolved = $false; channel = "event"; trigger = $trigger; reason = "no events table" }
        Write-MetricsLine @{ source = "sdp-tone"; channel = "event"; timestamp = (Get-Date).ToString("o"); trigger = $trigger; resolved = $false; sequence = $null; reason = "no events table" }
        exit 0
    }

    $binding = @($config.events | Where-Object { $_.trigger -eq $trigger -and $_.enabled -ne $false }) | Select-Object -First 1
    if (-not $binding) {
        Emit-Plan @{ resolved = $false; channel = "event"; trigger = $trigger; reason = "no enabled binding" }
        Write-MetricsLine @{ source = "sdp-tone"; channel = "event"; timestamp = (Get-Date).ToString("o"); trigger = $trigger; resolved = $false; sequence = $null; reason = "no enabled binding" }
        exit 0
    }

    $seq = $null
    if ($config.sequences) { $seq = $config.sequences.($binding.sequence) }
    if (-not $seq) {
        Emit-Plan @{ resolved = $false; channel = "event"; trigger = $trigger; reason = "sequence not found: $($binding.sequence)" }
        Write-MetricsLine @{ source = "sdp-tone"; channel = "event"; timestamp = (Get-Date).ToString("o"); trigger = $trigger; resolved = $false; sequence = $binding.sequence; reason = "sequence not found: $($binding.sequence)" }
        exit 0
    }

    # Profile (default "once"), then inline binding overrides
    $repeat = 1; $betweenRepeats = 0
    if ($binding.profile -and $config.profiles) {
        $prof = $config.profiles.($binding.profile)
        if ($prof) {
            if ($null -ne $prof.repeat) { $repeat = [int]$prof.repeat }
            if ($null -ne $prof.gapMs)  { $betweenRepeats = [int]$prof.gapMs }
        }
    }
    if ($null -ne $binding.repeat) { $repeat = [int]$binding.repeat }
    if ($null -ne $binding.gapMs)  { $betweenRepeats = [int]$binding.gapMs }
    if ($repeat -lt 1) { $repeat = 1 }

    $seqGap = 0
    if ($null -ne $seq.gapMs) { $seqGap = [int]$seq.gapMs }

    # Resolve note list: palette id (string) or inline {hz,ms[,gapMs]}; hz <= 0 = rest
    $notes = @()
    foreach ($n in $seq.notes) {
        $hz = $null; $ms = $null; $g = $seqGap
        if ($n -is [string]) {
            $p = @($config.palette | Where-Object { $_.id -eq $n }) | Select-Object -First 1
            if ($p) { $hz = [int]$p.hz; $ms = [int]$p.ms }
        } else {
            if ($null -ne $n.hz) { $hz = [int]$n.hz }
            if ($null -ne $n.ms) { $ms = [int]$n.ms }
            if ($null -ne $n.gapMs) { $g = [int]$n.gapMs }
        }
        if ($null -ne $hz -and $null -ne $ms) {
            $notes += [pscustomobject]@{ hz = $hz; ms = $ms; gap = $g }
        }
    }
    if ($notes.Count -eq 0) {
        Emit-Plan @{ resolved = $false; channel = "event"; trigger = $trigger; reason = "no playable notes" }
        Write-MetricsLine @{ source = "sdp-tone"; channel = "event"; timestamp = (Get-Date).ToString("o"); trigger = $trigger; resolved = $false; sequence = $binding.sequence; reason = "no playable notes" }
        exit 0
    }

    if ($whatIf) {
        Emit-Plan @{
            resolved            = $true
            channel             = "event"
            trigger             = $trigger
            sequence            = $binding.sequence
            repeat              = $repeat
            gapMsBetweenRepeats = $betweenRepeats
            notes               = @($notes | ForEach-Object { @{ hz = $_.hz; ms = $_.ms; gap = $_.gap } })
        }
        exit 0
    }

    for ($r = 0; $r -lt $repeat; $r++) {
        foreach ($note in $notes) {
            try {
                if ($note.hz -le 0) { Start-Sleep -Milliseconds $note.ms }
                else { [console]::Beep($note.hz, $note.ms) }   # valid Hz 37-32767; out-of-range throws -> caught
            } catch { }
            if ($note.gap -gt 0) { Start-Sleep -Milliseconds $note.gap }
        }
        if ($r -lt ($repeat - 1) -and $betweenRepeats -gt 0) { Start-Sleep -Milliseconds $betweenRepeats }
    }
    Write-MetricsLine @{ source = "sdp-tone"; channel = "event"; timestamp = (Get-Date).ToString("o"); trigger = $trigger; resolved = $true; sequence = $binding.sequence; reason = $null }
    exit 0
}

# ──────────────────────────────────────────────────────────────────────────
# Skill start/end channel (original behavior)
# ──────────────────────────────────────────────────────────────────────────
if (-not $skillName -or -not $event) { exit 0 }
if ($event -ne "start" -and $event -ne "end") { exit 0 }

$assignments = $config.assignments
if (-not $assignments) {
    Write-MetricsLine @{ source = "sdp-tone"; channel = "skill"; timestamp = (Get-Date).ToString("o"); skillName = $skillName; event = $event; resolved = $false; toneId = $null; reason = "no assignments table" }
    exit 0
}

$eventField = if ($event -eq "start") { "useAtSkillStart" } else { "useAtSkillEnd" }

$toneId = $null
# Exact skillName match — if any exact entries exist, use them exclusively (no wildcard fallthrough)
$exactMatches = @($assignments | Where-Object { $_.sdpSkillName -eq $skillName })
if ($exactMatches.Count -gt 0) {
    foreach ($a in $exactMatches) {
        $val = $a.$eventField
        if ($null -ne $val -and $val -ne "") { $toneId = $val; break }
    }
} else {
    $wildcardMatches = @($assignments | Where-Object { $_.sdpSkillName -eq "*" })
    foreach ($a in $wildcardMatches) {
        $val = $a.$eventField
        if ($null -ne $val -and $val -ne "") { $toneId = $val; break }
    }
}

if (-not $toneId) {
    Emit-Plan @{ resolved = $false; channel = "assignment"; skillName = $skillName; event = $event; reason = "no tone assigned" }
    Write-MetricsLine @{ source = "sdp-tone"; channel = "skill"; timestamp = (Get-Date).ToString("o"); skillName = $skillName; event = $event; resolved = $false; toneId = $null; reason = "no tone assigned" }
    exit 0
}

if (-not $config.palette) {
    Write-MetricsLine @{ source = "sdp-tone"; channel = "skill"; timestamp = (Get-Date).ToString("o"); skillName = $skillName; event = $event; resolved = $false; toneId = $toneId; reason = "no palette table" }
    exit 0
}

$hz = $null; $ms = $null
foreach ($p in $config.palette) {
    if ($p.id -eq $toneId) { $hz = [int]$p.hz; $ms = [int]$p.ms; break }
}
if ($null -eq $hz -or $null -eq $ms) {
    Emit-Plan @{ resolved = $false; channel = "assignment"; skillName = $skillName; event = $event; reason = "palette id not found: $toneId" }
    Write-MetricsLine @{ source = "sdp-tone"; channel = "skill"; timestamp = (Get-Date).ToString("o"); skillName = $skillName; event = $event; resolved = $false; toneId = $toneId; reason = "palette id not found: $toneId" }
    exit 0
}

if ($whatIf) {
    Emit-Plan @{ resolved = $true; channel = "assignment"; skillName = $skillName; event = $event; toneId = $toneId; hz = $hz; ms = $ms }
    exit 0
}

try { [console]::Beep($hz, $ms) } catch { }
Write-MetricsLine @{ source = "sdp-tone"; channel = "skill"; timestamp = (Get-Date).ToString("o"); skillName = $skillName; event = $event; resolved = $true; toneId = $toneId; reason = $null }
exit 0
