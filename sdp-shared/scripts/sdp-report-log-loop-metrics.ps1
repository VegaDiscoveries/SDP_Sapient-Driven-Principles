<#
.SYNOPSIS
    Parse a solution's loop-metrics-*.jsonl tone/action log and compute the deterministic parts of
    an SDP loop metrics report: the six-bucket time accounting (pre-rendered as
    bucketTableMarkdown, Total row included), halt/halt-resolution/off-hours/user-interrupted
    interval tables (three separate tables -- Halt windows with a duration breakdown, Halt-
    resolution windows with deterministic Evidence, User-interrupted windows with a correlated-
    action-log-entry breadcrumb), both SVG time-flow bars, the task-by-task outcomes table
    (including elapsed-time fields, with a dispatch-start candidate-chain breadcrumb when the
    WORKER start time is ambiguous), the loop-fire breakdown counts with Meaning text (pre-
    rendered as loopFireTableMarkdown), and the Phase/Work Covered table (work-item-to-phase
    mapping, primarily sourced from each referenced project's own sdp-docs/*_state.json files --
    see the Phase / Work Covered section below for the full source/fallback chain). Everything
    else in this file is either a fixed, dataset-agnostic rule or an explicit breadcrumb for
    report-assembly judgment to resolve -- it never silently guesses. Narrative content (root-
    cause analysis, gate-finding materiality, "next step" recommendations, Current State,
    breadcrumb resolution) is explicitly out of scope -- those require judgment this script does
    not perform, even where (as in Phase/Work Covered) the script does read project files for a
    fixed, dataset-agnostic mapping rule rather than for narrative interpretation.

.PARAMETER JsonlPath
    Path to a loop-metrics-*.jsonl file. The calling skill always resolves and passes this
    explicitly (one file exists per calendar day under .sdp-solution-workflow/logging/loop-logs/
    at the solution root). If omitted (e.g. direct script invocation outside the skill),
    defaults to the most recently dated file in that folder — normally today's, matching
    sdp-tone.ps1's own write-target resolution.

.PARAMETER Date
    Single calendar date filter (yyyy-MM-dd). Only events on this date are included.

.PARAMETER StartDate
    Inclusive range start (yyyy-MM-dd). Used together with -EndDate.

.PARAMETER EndDate
    Inclusive range end (yyyy-MM-dd). Used together with -StartDate.

.PARAMETER Days
    Integer, must be > 0. Trailing window ending today, inclusive: 1 = today only, 2 = yesterday
    and today, N = the N calendar days ending today.

.PARAMETER IncludeSeconds
    Switch. When present, every time value in the output is formatted hh:mm:ss instead of the
    default hh:mm. Precision of the underlying computation is unaffected either way -- this only
    changes how many digits are printed.

.PARAMETER OffHoursThresholdMinutes
    Integer, must be > 0. Minimum duration (minutes) of total log silence -- zero events of any
    kind, tone or action -- required to reclassify an Unproductive or Idle segment as Off-hours.
    When omitted, defaults to script-support/sdp-report-log-loop-metrics-skills.json's
    `offHoursThresholdMinutesDefault` (30 as of this writing: comfortably above the observed
    ~5-minute cron cadence, and above the shortest genuine "briefly looked at it" gap seen in
    practice -- 21 minutes, immediately followed by real resolution work -- correctly stays
    Unproductive, not Off-hours). An explicit -OffHoursThresholdMinutes always overrides the
    config default.

.NOTES
    Stdout: single-line JSON result object (agent-consumed script per SDP-Script-Authoring.md).
    Exit codes: 0 = success (status may still be "error" inside the JSON for a handled condition);
    1 reserved for an operational failure that prevented any JSON from being written at all.
    Filter precedence if more than one is supplied: -Date > -StartDate/-EndDate > -Days > full file.
#>
param(
    [string]$JsonlPath = "",
    [string]$Date = "",
    [string]$StartDate = "",
    [string]$EndDate = "",
    [int]$Days = 0,
    [switch]$IncludeSeconds,
    [int]$OffHoursThresholdMinutes = -1
)

function Write-Result([hashtable]$hash) {
    Write-Output ($hash | ConvertTo-Json -Compress -Depth 12)
}

$workspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $JsonlPath) {
    $loopLogsDir = Join-Path $workspaceRoot ".sdp-solution-workflow/logging/loop-logs"
    $latest = Get-ChildItem -Path $loopLogsDir -Filter "loop-metrics-*.jsonl" -File -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if ($latest) { $JsonlPath = $latest.FullName }
    else {
        Write-Result @{ status = "error"; error = "no loop-metrics-*.jsonl files found under $loopLogsDir and -JsonlPath was not provided" }
        exit 0
    }
}

if (-not (Test-Path $JsonlPath)) {
    Write-Result @{ status = "error"; error = "jsonl not found: $JsonlPath" }
    exit 0
}

# ---------------------------------------------------------------------------
# Load the skill-role config (script-support/sdp-report-log-loop-metrics-skills.json). Each
# productive role (WORKER/REVIEWER/COORDINATOR/GATE_REVIEWER) carries every literal skillName it
# has ever been logged under, oldest first, current name last -- this is what lets a report run
# against a historical date correctly recognize and merge events logged under a since-renamed
# skill name into the SAME canonical bucket as current-named events, instead of just one or the
# other. See the JSON file's own `_doc` field for the full schema and the future-rename
# maintenance rule (append the new name; never remove or reorder an existing one).
# ---------------------------------------------------------------------------
$skillConfigPath = Join-Path $PSScriptRoot "script-support/sdp-report-log-loop-metrics-skills.json"
if (-not (Test-Path $skillConfigPath)) {
    Write-Result @{ status = "error"; error = "skill-role config not found: $skillConfigPath" }
    exit 0
}
try {
    $skillConfig = Get-Content $skillConfigPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
} catch {
    Write-Result @{ status = "error"; error = "failed to parse skill-role config ($skillConfigPath): $($_.Exception.Message)" }
    exit 0
}

$skillAliasToCanonical = @{}
$roleCanonicalName = @{}
foreach ($roleEntry in $skillConfig.roles) {
    $aliases = @($roleEntry.aliases)
    if ($aliases.Count -eq 0) { continue }
    $canonical = $aliases[-1]
    $roleCanonicalName[[string]$roleEntry.role] = $canonical
    foreach ($alias in $aliases) { $skillAliasToCanonical[[string]$alias] = $canonical }
}
$canonicalWorker = $roleCanonicalName["WORKER"]
$canonicalReviewer = $roleCanonicalName["REVIEWER"]
$canonicalCoordinator = $roleCanonicalName["COORDINATOR"]
$canonicalGateReviewer = $roleCanonicalName["GATE_REVIEWER"]

# -OffHoursThresholdMinutes falls back to the config default only when the caller didn't pass it
# explicitly -- an explicit CLI value always takes precedence over the config default.
if (-not $PSBoundParameters.ContainsKey('OffHoursThresholdMinutes')) {
    if ($skillConfig.offHoursThresholdMinutesDefault) {
        $OffHoursThresholdMinutes = [int]$skillConfig.offHoursThresholdMinutesDefault
    }
}
$unloggedGapThresholdSeconds = if ($skillConfig.unloggedGapThresholdSeconds) { [int]$skillConfig.unloggedGapThresholdSeconds } else { 900 }

if ($OffHoursThresholdMinutes -le 0) {
    Write-Result @{ status = "error"; error = "OffHoursThresholdMinutes must be > 0" }
    exit 0
}

# ---------------------------------------------------------------------------
# Load and parse every line (one JSON object per line -- not a single array).
# ---------------------------------------------------------------------------
$rawLines = Get-Content $JsonlPath -Encoding UTF8
$events = @()
foreach ($line in $rawLines) {
    if (-not $line -or $line.Trim() -eq "") { continue }
    try {
        $obj = $line | ConvertFrom-Json
        if ($obj.timestamp) { $events += $obj }
    } catch { }
}

if ($events.Count -eq 0) {
    Write-Result @{ status = "error"; error = "no parseable timestamped events in jsonl" }
    exit 0
}

# Normalize every event's skillName to its canonical CURRENT name immediately after parsing, before
# any interval computation, bucketing, or -eq comparison happens downstream. This is what actually
# fixes the historical-bucketing bug: a `sdp-worker` tone event from before that skill was renamed
# and a `sdp-project-worker` tone event logged today both normalize to the same canonical name here,
# so they merge into one continuous timeline for that role rather than one of them silently falling
# out of every comparison that only ever checked for the current literal name.
foreach ($e in $events) {
    if ($e.PSObject.Properties['skillName'] -and $e.skillName) {
        $rawSkillName = [string]$e.skillName
        if ($skillAliasToCanonical.ContainsKey($rawSkillName)) {
            $e.skillName = $skillAliasToCanonical[$rawSkillName]
        }
    }
}

# Attach a parsed [datetime] for sorting/filtering/arithmetic without re-parsing repeatedly.
foreach ($e in $events) {
    Add-Member -InputObject $e -MemberType NoteProperty -Name "_dt" -Value ([datetimeoffset]::Parse($e.timestamp)) -Force
}
$events = @($events | Sort-Object { $_._dt })

# ---------------------------------------------------------------------------
# Date filter (mutually exclusive precedence: Date > StartDate/EndDate > Days > full file)
# ---------------------------------------------------------------------------
$filterStart = $null
$filterEndExclusive = $null
if ($Date) {
    $d = [datetime]::Parse($Date)
    $filterStart = $d.Date
    $filterEndExclusive = $d.Date.AddDays(1)
} elseif ($StartDate -and $EndDate) {
    $filterStart = ([datetime]::Parse($StartDate)).Date
    $filterEndExclusive = ([datetime]::Parse($EndDate)).Date.AddDays(1)
} elseif ($Days -gt 0) {
    $today = (Get-Date).Date
    $filterStart = $today.AddDays(-($Days - 1))
    $filterEndExclusive = $today.AddDays(1)
}

if ($filterStart) {
    $events = @($events | Where-Object { $_._dt.DateTime -ge $filterStart -and $_._dt.DateTime -lt $filterEndExclusive })
}

if ($events.Count -eq 0) {
    Write-Result @{ status = "error"; error = "no events remain after applying the date filter" }
    exit 0
}

$periodStart = $events[0]._dt
$periodEnd = $events[-1]._dt

# ---------------------------------------------------------------------------
# Time display helpers
# ---------------------------------------------------------------------------
function Format-Clock([datetimeoffset]$dt) {
    if ($IncludeSeconds) { return $dt.ToString("HH:mm:ss") }
    return $dt.ToString("HH:mm")
}

function Format-Duration([double]$totalSeconds) {
    $s = [int][math]::Truncate($totalSeconds)
    $h = [int]([math]::Truncate($s / 3600))
    $m = [int]([math]::Truncate(($s % 3600) / 60))
    $sec = [int]($s % 60)
    if ($IncludeSeconds) {
        if ($h -gt 0) { return ("{0}h {1:D2}m {2:D2}s" -f $h, $m, $sec) }
        if ($m -gt 0) { return ("{0}m {1:D2}s" -f $m, $sec) }
        return ("{0}s" -f $sec)
    }
    if ($h -gt 0) { return ("{0}h {1:D2}m" -f $h, $m) }
    return ("{0}m" -f $m)
}

# ---------------------------------------------------------------------------
# Title / period-covered date-range resolution
# ---------------------------------------------------------------------------
$startDateOnly = $periodStart.Date
$endDateOnly = $periodEnd.Date
$titleDate = if ($startDateOnly -eq $endDateOnly) {
    $startDateOnly.ToString("yyyy-MM-dd")
} else {
    "{0} -> {1}" -f $startDateOnly.ToString("yyyy-MM-dd"), $endDateOnly.ToString("yyyy-MM-dd")
}
# NOTE: the report itself renders the real unicode right-arrow (U+2192) between the two dates;
# this script emits the ASCII placeholder "->" in the JSON envelope to stay ASCII-source-safe
# (PS 5.1 / non-BOM parsing lesson from SDP-Script-Authoring.md). The skill substitutes the
# proper glyph when writing markdown.

# ---------------------------------------------------------------------------
# Action-log entries (the four-field family: action/work_item/role/status_before/status_after/
# halted/halt_reason) vs. skill tone entries (channel:"skill") vs. named events (channel:"event").
# ---------------------------------------------------------------------------
$actionEvents = @($events | Where-Object { $_.action })
$skillToneEvents = @($events | Where-Object { $_.channel -eq "skill" })

$productiveSkills = @($canonicalWorker, $canonicalReviewer, $canonicalCoordinator, $canonicalGateReviewer)

# ---------------------------------------------------------------------------
# Header metadata -- source file, project name(s), report-prepared date. Project comes from the
# `project` field carried on action-log entries; more than one distinct value means this period
# spans multiple projects (the skill lists all of them rather than picking one).
# ---------------------------------------------------------------------------
$sourceLineCount = $rawLines.Count
$sourceRelative = Split-Path -Leaf $JsonlPath
$projectNames = @($events | Where-Object { $_.project } | Select-Object -ExpandProperty project -Unique)
$reportPreparedDate = (Get-Date).ToString("yyyy-MM-dd")

# ---------------------------------------------------------------------------
# Skill start/end pairing -- PRODUCTIVE SKILLS ONLY (sdp-project-worker/reviewer/coordinator/gate-review).
# Bookkeeping skills (sdp-project-state-loop, sdp-project-run-prompt, etc.) fire dozens of times per period as
# normal cadence; applying orphan-detection to them mistook routine metrics-log write-failure
# noise (a missing `end` tone due to a transient write race, same phenomenon as a missing
# action-log line) for genuine user interruption. User-interrupted is only meaningful for a
# skill that represents real work being cut off mid-session, so it is scoped to the four
# productive skills. The orphan rule: a `start` is orphaned if no matching `end` for that same
# skill appears before the next `start` of that same skill; the orphaned span runs from its own
# timestamp to that next start (the point the flow resumed). Concurrent/overlapping invocations
# of the *same* skill beyond one pending start are not handled by this rule (an open question,
# not yet stress-tested against real data) -- flagged in pairingWarnings.
# ---------------------------------------------------------------------------
$allIntervals = @()      # every real (start,end) pair for the four productive skills
$userInterruptedSpans = @()
$pairingWarnings = @()

foreach ($skillName in $productiveSkills) {
    $skillEvents = @($skillToneEvents | Where-Object { $_.skillName -eq $skillName } | Sort-Object { $_._dt })
    $pendingStart = $null
    foreach ($ev in $skillEvents) {
        if ($ev.event -eq "start") {
            if ($pendingStart) {
                # A second start with no intervening end -- prior one is orphaned (User-interrupted).
                $userInterruptedSpans += [pscustomobject]@{
                    skill = $skillName
                    orphanStart = $pendingStart._dt
                    flowResumed = $ev._dt
                }
                $pairingWarnings += "multiple pending starts for $skillName before $($ev._dt.ToString('o'))"
            }
            $pendingStart = $ev
        } elseif ($ev.event -eq "end") {
            if ($pendingStart) {
                $allIntervals += [pscustomobject]@{
                    skill = $skillName
                    start = $pendingStart._dt
                    end = $ev._dt
                }
                $pendingStart = $null
            }
            # An `end` with no pending start is a logging oddity -- ignored, not fabricated.
        }
    }
    if ($pendingStart) {
        # Orphaned start with no later start of the same skill in this window at all --
        # runs to the end of the parsed period (flow never confirmed resumed within scope).
        $userInterruptedSpans += [pscustomobject]@{
            skill = $skillName
            orphanStart = $pendingStart._dt
            flowResumed = $periodEnd
        }
    }
}

# ---------------------------------------------------------------------------
# Halt windows -- two-pass detection.
# Pass 1 (outer bound): onset = first action-log entry where `halted` flips from falsy to true;
# outer bound = the next action-log entry after onset where `halted` is falsy, or end-of-period.
# This outer bound can lag well behind the real resolution moment, because state.json's halted
# flag only becomes *observable* in the log the next time some action-log entry happens to be
# written -- which may be much later than the actual fix.
# Pass 2 (true resolution): a halt is only ever cleared by a `sdp-project-coordinator` session (per the
# bootstrap doc's halt-recovery design). Within [onset, outer bound), any sdp-project-coordinator interval
# that STARTS in that range is the actual halt-resolution work. True Resolved = the end of the
# LAST such coordinator interval, if any; otherwise Resolved = the outer bound as-is (no
# resolution work happened inside this window -- matches an unattended halt exactly).
# ---------------------------------------------------------------------------
$outerWindows = @()
$inHalt = $false
$currentOnset = $null
$currentHaltReason = $null
foreach ($a in $actionEvents) {
    $isHalted = ($a.halted -eq $true)
    if ($isHalted -and -not $inHalt) {
        $inHalt = $true
        $currentOnset = $a._dt
        $currentHaltReason = $a.halt_reason
    } elseif (-not $isHalted -and $inHalt) {
        $outerWindows += [pscustomobject]@{ onset = $currentOnset; outerBound = $a._dt; outerBoundKnown = $true; cause = $currentHaltReason }
        $inHalt = $false; $currentOnset = $null; $currentHaltReason = $null
    }
}
if ($inHalt) {
    $outerWindows += [pscustomobject]@{ onset = $currentOnset; outerBound = $periodEnd; outerBoundKnown = $false; cause = $currentHaltReason }
}

$coordinatorIntervals = @($allIntervals | Where-Object { $_.skill -eq $canonicalCoordinator })
$haltWindows = @()
$haltResolutionIntervals = @()
for ($i = 0; $i -lt $outerWindows.Count; $i++) {
    $ow = $outerWindows[$i]
    $resolving = @($coordinatorIntervals | Where-Object { $_.start -ge $ow.onset -and $_.start -lt $ow.outerBound } | Sort-Object start)
    if ($resolving.Count -gt 0) {
        $trueResolved = ($resolving | Sort-Object end | Select-Object -Last 1).end
        foreach ($r in $resolving) {
            $haltResolutionIntervals += [pscustomobject]@{ skill = $canonicalCoordinator; start = $r.start; end = $r.end; haltWindowIndex = $i + 1 }
        }
        $resolvedKnown = $true
    } else {
        $trueResolved = $ow.outerBound
        $resolvedKnown = $ow.outerBoundKnown
    }
    $haltWindows += [pscustomobject]@{ onset = $ow.onset; resolved = $trueResolved; resolvedKnown = $resolvedKnown; cause = $ow.cause }
}

# ---------------------------------------------------------------------------
# Productive intervals: any of the four productive-skill intervals whose START does not fall
# inside any halt window's final [onset, resolved) span. (Halt-resolution intervals -- the
# coordinator sessions that clear a halt -- are already carved out above and excluded here.)
# ---------------------------------------------------------------------------
$productiveIntervals = @()
foreach ($iv in $allIntervals) {
    $insideHalt = $haltWindows | Where-Object { $iv.start -ge $_.onset -and $iv.start -lt $_.resolved } | Select-Object -First 1
    $isHaltResolution = @($haltResolutionIntervals | Where-Object { $_.start -eq $iv.start -and $_.end -eq $iv.end -and $_.skill -eq $iv.skill }).Count -gt 0
    if (-not $insideHalt -and -not $isHaltResolution) {
        $productiveIntervals += $iv
    }
}

$totalSeconds = ($periodEnd - $periodStart).TotalSeconds

# ---------------------------------------------------------------------------
# Off-hours candidates -- total log silence (zero events of ANY kind: tone or action) lasting
# >= the threshold, computed directly from the full sorted $events list. This must come from raw
# event gaps, not from an already-coarse "Unproductive minus resolution" chunk: a halt window can
# contain both a genuinely silent multi-hour stretch AND a shorter stretch where the loop is
# actively ticking (STOP fires every ~5 min on a still-blocked condition) in the same coarse span
# -- only the raw gaps themselves prove true silence. An earlier version of this reclassified
# whole leftover Unproductive/Idle chunks by duration alone, which wrongly swallowed a genuinely-
# attended ~50-minute STOP-cycling stretch into "no active session" because it happened to sit
# next to a real 4-hour silence within the same halt window.
# ---------------------------------------------------------------------------
$offHoursThresholdSeconds = $OffHoursThresholdMinutes * 60
$offHoursCandidates = @()
for ($i = 1; $i -lt $events.Count; $i++) {
    $gapSeconds = ($events[$i]._dt - $events[$i - 1]._dt).TotalSeconds
    if ($gapSeconds -ge $offHoursThresholdSeconds) {
        $gapStart = $events[$i - 1]._dt
        $gapEnd = $events[$i]._dt
        $owningWindow = $haltWindows | Where-Object { $gapStart -ge $_.onset -and $gapStart -lt $_.resolved } | Select-Object -First 1
        $idx = if ($owningWindow) { [array]::IndexOf($haltWindows, $owningWindow) + 1 } else { $null }
        $offHoursCandidates += [pscustomobject]@{ start = $gapStart; end = $gapEnd; bucket = "OffHours"; haltWindowIndex = $idx }
    }
}

# ---------------------------------------------------------------------------
# Canonical timeline -- ONE full, non-overlapping partition of [periodStart, periodEnd], built
# once and used as the single source of truth for every bucket total AND both SVG bars. Lesson
# learned more than once while building this: independently re-deriving the "same" duration in
# more than one place is exactly how a pairing/overlap bug hides behind an always-balancing
# residual, because the residual (Idle) just silently absorbs the discrepancy either way.
#
# Precedence within a halt window: Halt-resolution, User-interrupted, and Off-hours spans are all
# "hard evidence" tagged intervals (each anchored to real event timestamps, not inferred); any of
# the three can land inside a halt window's onset->resolved span. All three are carved out first:
# only the leftover gaps in a halt window, after removing every Halt-resolution, User-interrupted,
# and Off-hours span that falls inside it, become Unproductive -- time with log evidence something
# was still cycling/present (e.g. STOP fires), just not fixing it. Without carving out
# User-interrupted first, a User-interrupted span inside a halt window was being double-counted
# (also Unproductive).
#
# Off-hours vs. User-interrupted precedence (user direction, 2026-07-12): a User-interrupted span
# and an Off-hours candidate can overlap the same stretch -- e.g. a WORKER pauses itself awaiting a
# user decision, one bookkeeping tick fires shortly after, then the log goes genuinely silent
# overnight until the user returns. Off-hours (raw event-silence, the hardest evidence available)
# takes precedence: any portion of a User-interrupted span that overlaps an Off-hours candidate is
# reclassified as Off-hours; only the non-silent leftover remains User-interrupted. Previously this
# had no explicit rule -- the later "fill" step's first-start-wins tie-break silently favored
# User-interrupted every time (it's anchored to the orphaned `start` tone, which almost always
# precedes the silence that follows it), overstating User-interrupted and understating Off-hours
# for exactly this kind of overnight pause.
# ---------------------------------------------------------------------------
function Subtract-Intervals([datetimeoffset]$spanStart, [datetimeoffset]$spanEnd, $cutIntervals) {
    $relevant = @($cutIntervals | Where-Object { $_.start -lt $spanEnd -and $_.end -gt $spanStart } | Sort-Object start)
    $leftover = @()
    $cursor = $spanStart
    foreach ($c in $relevant) {
        $cStart = if ($c.start -lt $spanStart) { $spanStart } else { $c.start }
        $cEnd = if ($c.end -gt $spanEnd) { $spanEnd } else { $c.end }
        if ($cStart -gt $cursor) {
            $leftover += [pscustomobject]@{ start = $cursor; end = $cStart }
        }
        if ($cEnd -gt $cursor) { $cursor = $cEnd }
    }
    if ($cursor -lt $spanEnd) {
        $leftover += [pscustomobject]@{ start = $cursor; end = $spanEnd }
    }
    return $leftover
}

function Build-CanonicalTimeline {
    $tagged = @()
    # Off-hours carve-out applies to every interval-based bucket, not just User-interrupted (user
    # direction, 2026-07-12): a skill start/end pair can be a normal, cleanly-paired interval and
    # still span genuine overnight silence in the middle if the subagent itself didn't emit an end
    # tone until it truly finished -- e.g. a WORKER that paused awaiting a user decision, went quiet
    # for hours, then resumed and eventually returned, all within one start/end pair with no orphan
    # involved at all. That case was invisible to the User-interrupted-only carve-out above (it
    # never even reaches userInterruptedSpans, since the pairing itself never broke). Off-hours
    # still requires the same >=OffHoursThresholdMinutes of *total* raw silence to fire at all, so
    # this doesn't touch anything shorter than that threshold at the start of a gap.
    foreach ($iv in $productiveIntervals) {
        $leftoverSegs = @(Subtract-Intervals $iv.start $iv.end $offHoursCandidates)
        foreach ($seg in $leftoverSegs) {
            $tagged += [pscustomobject]@{ start = $seg.start; end = $seg.end; bucket = "Productive"; haltWindowIndex = $null }
        }
    }
    foreach ($iv in $haltResolutionIntervals) {
        $leftoverSegs = @(Subtract-Intervals $iv.start $iv.end $offHoursCandidates)
        foreach ($seg in $leftoverSegs) {
            $tagged += [pscustomobject]@{ start = $seg.start; end = $seg.end; bucket = "HaltResolution"; haltWindowIndex = $iv.haltWindowIndex }
        }
    }
    foreach ($sp in $userInterruptedSpans) {
        $leftoverSegs = @(Subtract-Intervals $sp.orphanStart $sp.flowResumed $offHoursCandidates)
        foreach ($seg in $leftoverSegs) {
            $owningWindow = $haltWindows | Where-Object { $seg.start -ge $_.onset -and $seg.start -lt $_.resolved } | Select-Object -First 1
            $idx = if ($owningWindow) { [array]::IndexOf($haltWindows, $owningWindow) + 1 } else { $null }
            $tagged += [pscustomobject]@{ start = $seg.start; end = $seg.end; bucket = "UserInterrupted"; haltWindowIndex = $idx }
        }
    }
    foreach ($oh in $offHoursCandidates) {
        $tagged += [pscustomobject]@{ start = $oh.start; end = $oh.end; bucket = "OffHours"; haltWindowIndex = $oh.haltWindowIndex }
    }

    for ($i = 0; $i -lt $haltWindows.Count; $i++) {
        $hw = $haltWindows[$i]
        $idx = $i + 1
        $fixedInWindow = @($tagged | Where-Object { $_.haltWindowIndex -eq $idx -and ($_.bucket -eq "HaltResolution" -or $_.bucket -eq "UserInterrupted" -or $_.bucket -eq "OffHours") } | Sort-Object start)
        $cursor = $hw.onset
        foreach ($f in $fixedInWindow) {
            $fStart = if ($f.start -lt $hw.onset) { $hw.onset } else { $f.start }
            $fEnd = if ($f.end -gt $hw.resolved) { $hw.resolved } else { $f.end }
            if ($fStart -gt $cursor) {
                $tagged += [pscustomobject]@{ start = $cursor; end = $fStart; bucket = "Unproductive"; haltWindowIndex = $idx }
            }
            if ($fEnd -gt $cursor) { $cursor = $fEnd }
        }
        if ($cursor -lt $hw.resolved) {
            $tagged += [pscustomobject]@{ start = $cursor; end = $hw.resolved; bucket = "Unproductive"; haltWindowIndex = $idx }
        }
    }

    $tagged = @($tagged | Where-Object { $_.end -gt $_.start } | Sort-Object start)

    $filled = @()
    $cursor = $periodStart
    foreach ($t in $tagged) {
        if ($t.start -gt $cursor) {
            $filled += [pscustomobject]@{ start = $cursor; end = $t.start; bucket = "Idle"; haltWindowIndex = $null }
        }
        if ($t.end -gt $cursor) { $filled += $t; $cursor = $t.end }
    }
    if ($cursor -lt $periodEnd) {
        $filled += [pscustomobject]@{ start = $cursor; end = $periodEnd; bucket = "Idle"; haltWindowIndex = $null }
    }
    return $filled
}

$timeline = @(Build-CanonicalTimeline)

function Sum-BucketSeconds($name) {
    $segs = @($timeline | Where-Object { $_.bucket -eq $name })
    if ($segs.Count -eq 0) { return 0.0 }
    return (($segs | ForEach-Object { ($_.end - $_.start).TotalSeconds } | Measure-Object -Sum).Sum)
}

function Sum-BucketSecondsForWindow($name, $idx) {
    $segs = @($timeline | Where-Object { $_.bucket -eq $name -and $_.haltWindowIndex -eq $idx })
    if ($segs.Count -eq 0) { return 0.0 }
    return (($segs | ForEach-Object { ($_.end - $_.start).TotalSeconds } | Measure-Object -Sum).Sum)
}

$productiveSeconds = Sum-BucketSeconds "Productive"
$haltResolutionSeconds = Sum-BucketSeconds "HaltResolution"
$unproductiveSeconds = Sum-BucketSeconds "Unproductive"
$userInterruptedSeconds = Sum-BucketSeconds "UserInterrupted"
$offHoursSeconds = Sum-BucketSeconds "OffHours"
$idleSeconds = Sum-BucketSeconds "Idle"

function Pct($seconds) { if ($totalSeconds -le 0) { return 0 } return [math]::Round(($seconds / $totalSeconds) * 100, 1) }

$buckets = [ordered]@{
    totalSeconds = $totalSeconds
    productiveSeconds = $productiveSeconds
    haltResolutionSeconds = $haltResolutionSeconds
    offHoursSeconds = $offHoursSeconds
    unproductiveSeconds = $unproductiveSeconds
    userInterruptedSeconds = $userInterruptedSeconds
    idleSeconds = $idleSeconds
    totalDisplay = Format-Duration $totalSeconds
    productiveDisplay = Format-Duration $productiveSeconds
    haltResolutionDisplay = Format-Duration $haltResolutionSeconds
    offHoursDisplay = Format-Duration $offHoursSeconds
    unproductiveDisplay = Format-Duration $unproductiveSeconds
    userInterruptedDisplay = Format-Duration $userInterruptedSeconds
    idleDisplay = Format-Duration $idleSeconds
    productivePct = Pct $productiveSeconds
    haltResolutionPct = Pct $haltResolutionSeconds
    offHoursPct = Pct $offHoursSeconds
    unproductivePct = Pct $unproductiveSeconds
    userInterruptedPct = Pct $userInterruptedSeconds
    idlePct = Pct $idleSeconds
}

# ---------------------------------------------------------------------------
# Bucket table -- pre-rendered markdown, restoring the 2026-07-11 17:24 report's table shape
# (Total row + footnote-anchored header) verbatim. Off-hours is included as a 6th row even though
# that report predates the Off-hours bucket entirely (added later, still real/current/verified
# functionality) -- the restored report simply never had a chance to show it, this isn't a case
# of conflicting direction. Row order matches the composition bar's segment order.
# ---------------------------------------------------------------------------
$bucketTableMarkdown = @"
| Bucket<a id="bucket-footnote-ref"></a><sup>[1](#bucket-footnote)</sup> | Duration | % of total |
|---|---|---|
| **Total period covered** | **$($buckets.totalDisplay)** | 100% |
| Productive (active WORKER/REVIEWER/COORDINATOR/GATE_REVIEWER execution, excluding halt-resolution work) | $($buckets.productiveDisplay) | $($buckets.productivePct)% |
| Halt resolution (COORDINATOR work performed while ``workflow_status`` was still halted) | $($buckets.haltResolutionDisplay) | $($buckets.haltResolutionPct)% |
| Off-hours (no active session -- total log silence of $OffHoursThresholdMinutes minutes or more) | $($buckets.offHoursDisplay) | $($buckets.offHoursPct)% |
| Unproductive (halted, unattended -- no resolution work in progress) | $($buckets.unproductiveDisplay) | $($buckets.unproductivePct)% |
| User-interrupted (SDP flow broken off by the user before a skill session completed) | $($buckets.userInterruptedDisplay) | $($buckets.userInterruptedPct)% |
| Idle / dispatch overhead (sentinel eval, prompt regeneration, cron gaps, pre-work-verify, read-docs) | $($buckets.idleDisplay) | $($buckets.idlePct)% |
"@

# ---------------------------------------------------------------------------
# SVG bars -- status-palette hex values fixed per the dataviz-skill-validated mapping, except
# Off-hours: white fill with a border (user direction, 2026-07-11) -- not drawn from the
# status/categorical palette, not run through the palette validator.
# ---------------------------------------------------------------------------
$colorProductive = "#0ca30c"
$colorHaltRes = "#2a78d6"
$colorUnproductive = "#d03b3b"
$colorUserInt = "#fab219"
$colorIdle = "#ec835a"
$colorOffHours = "#ffffff"
$colorOffHoursBorder = "#898781"

$barWidth = 880
$barHeight = 22
$barY = 20

function New-CompositionBarSvg {
    $segs = @(
        @{ w = $buckets.productivePct; c = $colorProductive; label = "Productive"; border = $null }
        @{ w = $buckets.haltResolutionPct; c = $colorHaltRes; label = "Halt resolution"; border = $null }
        @{ w = $buckets.offHoursPct; c = $colorOffHours; label = "Off-hours"; border = $colorOffHoursBorder }
        @{ w = $buckets.unproductivePct; c = $colorUnproductive; label = "Halted"; border = $null }
        @{ w = $buckets.userInterruptedPct; c = $colorUserInt; label = "User-interrupted"; border = $null }
        @{ w = $buckets.idlePct; c = $colorIdle; label = "Idle"; border = $null }
    )
    $gap = 2
    $usable = $barWidth - ($gap * ($segs.Count - 1))
    $totalPct = 0.0
    foreach ($s in $segs) { $totalPct += $s.w }
    $x = 0
    $rects = ""
    for ($i = 0; $i -lt $segs.Count; $i++) {
        $w = if ($totalPct -gt 0) { [math]::Round(($segs[$i].w / $totalPct) * $usable, 2) } else { 0 }
        $rx = if ($i -eq 0 -or $i -eq ($segs.Count - 1)) { ' rx="4"' } else { '' }
        $strokeAttrs = if ($segs[$i].border) { " stroke=`"$($segs[$i].border)`" stroke-width=`"1`"" } else { '' }
        $rects += "  <rect x=`"$x`" y=`"$barY`" width=`"$w`" height=`"$barHeight`"$rx fill=`"$($segs[$i].c)`"$strokeAttrs/>`n"
        $x = $x + $w + $gap
    }
    $startLabel = Format-Clock $periodStart
    $endLabel = Format-Clock $periodEnd
    $label = "Time composition: " + (($segs | ForEach-Object { "$($_.label) $($_.w)%" }) -join ", ")
    return "<svg width=`"$barWidth`" height=`"70`" viewBox=`"0 0 $barWidth 70`" xmlns=`"http://www.w3.org/2000/svg`" role=`"img`" aria-label=`"$label`">`n$rects  <text x=`"0`" y=`"58`" text-anchor=`"start`" font-family=`"system-ui, -apple-system, 'Segoe UI', sans-serif`" font-size=`"11`" fill=`"#898781`">$startLabel</text>`n  <text x=`"$barWidth`" y=`"58`" text-anchor=`"end`" font-family=`"system-ui, -apple-system, 'Segoe UI', sans-serif`" font-size=`"11`" fill=`"#898781`">$endLabel</text>`n</svg>"
}

function Get-DaySegments([datetimeoffset]$rangeStart, [datetimeoffset]$rangeEnd) {
    # Splits [rangeStart, rangeEnd) into per-calendar-day spans at local midnight boundaries, each
    # tagged with its upper-case day-of-week name. Used to overlay day labels on the chronological
    # bar whenever a report period crosses one or more midnights (user direction, 2026-07-12 --
    # see docs/ReportEdit.png).
    $segments = @()
    $cursor = $rangeStart
    while ($cursor -lt $rangeEnd) {
        $nextMidnightLocal = $cursor.DateTime.Date.AddDays(1)
        $nextMidnight = [datetimeoffset]::new($nextMidnightLocal, $cursor.Offset)
        $segEnd = if ($nextMidnight -lt $rangeEnd) { $nextMidnight } else { $rangeEnd }
        $segments += [pscustomobject]@{ start = $cursor; end = $segEnd; label = $cursor.DateTime.DayOfWeek.ToString().ToUpper() }
        $cursor = $segEnd
    }
    return $segments
}

function New-ChronologicalBarSvg {
    $colorMap = @{
        Productive = $colorProductive
        HaltResolution = $colorHaltRes
        UserInterrupted = $colorUserInt
        Unproductive = $colorUnproductive
        Idle = $colorIdle
        OffHours = $colorOffHours
    }
    $sorted = @($timeline | Sort-Object start)
    $scale = if ($totalSeconds -gt 0) { $barWidth / $totalSeconds } else { 0 }

    # Day-of-week header row: only rendered when the period crosses at least one midnight. Adds a
    # fixed 26px band above the bar (divider line + centered day-name label per calendar day, plus
    # a boundary tick at each midnight crossing) without disturbing the single-day layout at all.
    $daySegments = @(Get-DaySegments $periodStart $periodEnd)
    $isMultiDay = $daySegments.Count -gt 1
    $headerOffset = if ($isMultiDay) { 26 } else { 0 }
    $barYAdjusted = $barY + $headerOffset
    $svgHeight = 70 + $headerOffset
    $textY = 58 + $headerOffset

    $rects = ""
    $x = 0.0
    $n = $sorted.Count
    for ($i = 0; $i -lt $n; $i++) {
        $seg = $sorted[$i]
        $w = ($seg.end - $seg.start).TotalSeconds * $scale
        $rx = if ($i -eq 0 -or $i -eq ($n - 1)) { ' rx="4"' } else { '' }
        $strokeAttrs = if ($seg.bucket -eq "OffHours") { " stroke=`"$colorOffHoursBorder`" stroke-width=`"1`"" } else { '' }
        $rects += ("  <rect x=`"{0:N2}`" y=`"$barYAdjusted`" width=`"{1:N2}`" height=`"$barHeight`"$rx fill=`"$($colorMap[$seg.bucket])`"$strokeAttrs/>`n" -f $x, $w)
        $x += $w
    }

    $dayHeaderMarkup = ""
    $dayLabelsForAria = @()
    if ($isMultiDay) {
        $dayHeaderMarkup += "  <line x1=`"0`" y1=`"22`" x2=`"$barWidth`" y2=`"22`" stroke=`"#898781`" stroke-width=`"1`"/>`n"
        foreach ($ds in $daySegments) {
            $dayLabelsForAria += $ds.label
            $segStartX = ($ds.start - $periodStart).TotalSeconds * $scale
            $segEndX = ($ds.end - $periodStart).TotalSeconds * $scale
            $midX = [math]::Round((($segStartX + $segEndX) / 2), 2)
            $dayHeaderMarkup += "  <text x=`"$midX`" y=`"16`" text-anchor=`"middle`" font-family=`"system-ui, -apple-system, 'Segoe UI', sans-serif`" font-size=`"12`" font-weight=`"600`" fill=`"#333333`">$($ds.label)</text>`n"
        }
        for ($b = 1; $b -lt $daySegments.Count; $b++) {
            $boundaryX = [math]::Round((($daySegments[$b].start - $periodStart).TotalSeconds * $scale), 2)
            $dayHeaderMarkup += "  <line x1=`"$boundaryX`" y1=`"6`" x2=`"$boundaryX`" y2=`"22`" stroke=`"#898781`" stroke-width=`"1`"/>`n"
        }
    }

    $startLabel = Format-Clock $periodStart
    $endLabel = Format-Clock $periodEnd
    $ariaLabel = "Chronological time flow from $startLabel to $endLabel, colored by bucket"
    if ($isMultiDay) { $ariaLabel += " (spanning " + ($dayLabelsForAria -join " and ") + ")" }
    return "<svg width=`"$barWidth`" height=`"$svgHeight`" viewBox=`"0 0 $barWidth $svgHeight`" xmlns=`"http://www.w3.org/2000/svg`" role=`"img`" aria-label=`"$ariaLabel`">`n$dayHeaderMarkup$rects  <text x=`"0`" y=`"$textY`" text-anchor=`"start`" font-family=`"system-ui, -apple-system, 'Segoe UI', sans-serif`" font-size=`"11`" fill=`"#898781`">$startLabel</text>`n  <text x=`"$barWidth`" y=`"$textY`" text-anchor=`"end`" font-family=`"system-ui, -apple-system, 'Segoe UI', sans-serif`" font-size=`"11`" fill=`"#898781`">$endLabel</text>`n</svg>"
}

$compositionBarSvg = New-CompositionBarSvg
$chronologicalBarSvg = New-ChronologicalBarSvg

$legendHtml = "<div>`n" + (
    "<span style=`"display:inline-block;width:10px;height:10px;background:$colorProductive;border-radius:2px;margin-right:4px;vertical-align:middle;`"></span>Productive $($buckets.productiveDisplay) ($($buckets.productivePct)%)&nbsp;&nbsp;&nbsp;" +
    "<span style=`"display:inline-block;width:10px;height:10px;background:$colorHaltRes;border-radius:2px;margin-right:4px;vertical-align:middle;`"></span>Halt resolution $($buckets.haltResolutionDisplay) ($($buckets.haltResolutionPct)%)&nbsp;&nbsp;&nbsp;" +
    "<span style=`"display:inline-block;width:10px;height:10px;background:$colorOffHours;border:1px solid $colorOffHoursBorder;border-radius:2px;margin-right:4px;vertical-align:middle;`"></span>Off-hours $($buckets.offHoursDisplay) ($($buckets.offHoursPct)%)&nbsp;&nbsp;&nbsp;" +
    "<span style=`"display:inline-block;width:10px;height:10px;background:$colorUnproductive;border-radius:2px;margin-right:4px;vertical-align:middle;`"></span>Unproductive/halted $($buckets.unproductiveDisplay) ($($buckets.unproductivePct)%)&nbsp;&nbsp;&nbsp;" +
    "<span style=`"display:inline-block;width:10px;height:10px;background:$colorUserInt;border-radius:2px;margin-right:4px;vertical-align:middle;`"></span>User-interrupted $($buckets.userInterruptedDisplay) ($($buckets.userInterruptedPct)%)&nbsp;&nbsp;&nbsp;" +
    "<span style=`"display:inline-block;width:10px;height:10px;background:$colorIdle;border-radius:2px;margin-right:4px;vertical-align:middle;`"></span>Idle/overhead $($buckets.idleDisplay) ($($buckets.idlePct)%)"
) + "`n</div>"

# ---------------------------------------------------------------------------
# Halt windows / halt-resolution windows / user-interrupted windows -- restored to the original
# three-separate-table shape (2026-07-11 17:24 report), not the interleaved-timeline design this
# script previously used with no source. `timeline` is kept (internal/optional use -- e.g. an
# agent wanting the raw interleaved sequence) but the report no longer renders it as its own
# sub-table; the restored report's Duration-breakdown-in-parens + Evidence-column design is used
# instead, both fully deterministic (see durationBreakdownDisplay / evidence below -- no LLM
# judgment involved in any of this section).
# ---------------------------------------------------------------------------
function Format-HaltDurationBreakdown($hw, $unattendedSec, $resSec, $offHoursSec, $uiSec, $hasResolutionEntries) {
    $bucketList = @()
    if ($unattendedSec -gt 0) { $bucketList += @{ label = "unattended"; text = "$(Format-Duration $unattendedSec) unattended" } }
    if ($resSec -gt 0) { $bucketList += @{ label = "resolution"; text = "$(Format-Duration $resSec) resolution" } }
    if ($offHoursSec -gt 0) { $bucketList += @{ label = "off-hours"; text = "$(Format-Duration $offHoursSec) off-hours" } }
    if ($uiSec -gt 0) { $bucketList += @{ label = "user-interrupted"; text = "$(Format-Duration $uiSec) user-interrupted" } }

    $inner = if ($bucketList.Count -eq 0) { $null }
        elseif ($bucketList.Count -eq 1) { "100% $($bucketList[0].label)" }
        else {
            $suffixNote = if ($hasResolutionEntries) { " -- see below" } else { "" }
            (($bucketList | ForEach-Object { $_.text }) -join " + ") + $suffixNote
        }

    $prefix = if (-not $hw.resolvedKnown) { "through end of log" } else { $null }
    $clauses = @($prefix, $inner) | Where-Object { $_ }
    if ($clauses.Count -eq 0) { return "" }
    return " (" + ($clauses -join ", ") + ")"
}

$haltWindowRows = @()
for ($i = 0; $i -lt $haltWindows.Count; $i++) {
    $hw = $haltWindows[$i]
    $idx = $i + 1
    $windowSpan = ($hw.resolved - $hw.onset).TotalSeconds
    $resInWindow = Sum-BucketSecondsForWindow "HaltResolution" $idx
    $uiInWindow = Sum-BucketSecondsForWindow "UserInterrupted" $idx
    $offHoursInWindow = Sum-BucketSecondsForWindow "OffHours" $idx
    $unattended = Sum-BucketSecondsForWindow "Unproductive" $idx
    $hasResolutionEntries = @($haltResolutionIntervals | Where-Object { $_.haltWindowIndex -eq $idx }).Count -gt 0

    $windowSegs = @($timeline | Where-Object { $_.haltWindowIndex -eq $idx } | Sort-Object start)
    $timelineRows = @()
    foreach ($seg in $windowSegs) {
        $typeLabel = switch ($seg.bucket) {
            "HaltResolution" { "Resolution" }
            "UserInterrupted" { "User-interrupted" }
            "OffHours" { "Off-hours" }
            "Unproductive" { "Unattended" }
            default { $seg.bucket }
        }
        $timelineRows += [ordered]@{
            type = $typeLabel
            startDisplay = Format-Clock $seg.start
            endDisplay = Format-Clock $seg.end
            durationDisplay = Format-Duration (($seg.end - $seg.start).TotalSeconds)
        }
    }

    $haltWindowRows += [ordered]@{
        index = $idx
        onsetDisplay = Format-Clock $hw.onset
        resolvedDisplay = if ($hw.resolvedKnown) { Format-Clock $hw.resolved } else { "unresolved -- window ends at " + (Format-Clock $hw.resolved) }
        resolvedKnown = $hw.resolvedKnown
        durationDisplay = (Format-Duration $windowSpan) + (Format-HaltDurationBreakdown $hw $unattended $resInWindow $offHoursInWindow $uiInWindow $hasResolutionEntries)
        unattendedDisplay = Format-Duration $unattended
        resolutionDisplay = Format-Duration $resInWindow
        offHoursDisplay = Format-Duration $offHoursInWindow
        userInterruptedDisplay = Format-Duration $uiInWindow
        cause = $hw.cause
        timeline = $timelineRows
    }
}

# Evidence per resolution interval: deterministic first-vs-last-in-window branch. The LAST
# resolving interval (by end time) in a window is by definition the one whose end equals that
# window's Resolved time (see the two-pass halt-window detection above) -- everything earlier in
# the same window is a prior attempt that didn't clear it. No judgment, just interval ordering.
$haltResolutionRows = @()
$resolutionGroups = $haltResolutionIntervals | Group-Object haltWindowIndex
foreach ($grp in $resolutionGroups) {
    $sortedGroup = @($grp.Group | Sort-Object end)
    for ($j = 0; $j -lt $sortedGroup.Count; $j++) {
        $ri = $sortedGroup[$j]
        $isLast = ($j -eq ($sortedGroup.Count - 1))
        $evidence = if ($isLast) {
            "The coordinator session whose end ($(Format-Clock $ri.end)) matches Halt window $($ri.haltWindowIndex)'s Resolved time -- this is the session that actually cleared the halt."
        } else {
            "Coordinator session inside the still-halted window -- an earlier attempt that did not clear the halt."
        }
        $haltResolutionRows += [ordered]@{
            haltWindowIndex = $ri.haltWindowIndex
            skill = $ri.skill
            startDisplay = Format-Clock $ri.start
            endDisplay = Format-Clock $ri.end
            durationDisplay = Format-Duration (($ri.end - $ri.start).TotalSeconds)
            evidence = $evidence
        }
    }
}

# Deterministic prose for halt windows with zero resolution entries -- same "no entries" fact the
# restored report stated in prose, generalized to any window/dataset.
$haltResolutionEmptyNotes = @()
for ($i = 0; $i -lt $haltWindows.Count; $i++) {
    $idx = $i + 1
    if (-not (@($haltResolutionIntervals | Where-Object { $_.haltWindowIndex -eq $idx }).Count -gt 0)) {
        $haltResolutionEmptyNotes += "Halt window $idx has no entries here: no coordinator/worker/reviewer/gate-review session ran between onset and resolution -- evidence nobody actively worked this halt during that window."
    }
}

# User-interrupted Evidence breadcrumb: the nearest action-log entry (any work_item/role) whose
# timestamp falls inside the orphan span, if one exists. This is a breadcrumb, not a final
# sentence -- the report-assembly skill decides whether/how to describe it (user direction,
# 2026-07-12): if present, it corroborates the interruption; if null, only the orphan pairing
# itself is evidence and nothing should be speculated about the gap. Shared with the Phase/Work
# Covered mapping below (Get-OrphanCorrelatedEntry), which needs the same lookup to scope a
# phase's start-extension to its own work items rather than to any orphan in the whole log.
function Get-OrphanCorrelatedEntry($span) {
    $correlated = @($actionEvents | Where-Object { $_._dt -ge $span.orphanStart -and $_._dt -le $span.flowResumed } | Sort-Object _dt | Select-Object -First 1)
    if ($correlated.Count -gt 0) { return $correlated[0] }
    return $null
}

$userInterruptedRows = @()
foreach ($sp in $userInterruptedSpans) {
    $correlated = Get-OrphanCorrelatedEntry $sp
    $correlatedEntry = if ($correlated) {
        [ordered]@{
            action = $correlated.action
            workItem = $correlated.work_item
            statusBefore = $correlated.status_before
            statusAfter = $correlated.status_after
            timestampDisplay = Format-Clock $correlated._dt
        }
    } else { $null }
    $userInterruptedRows += [ordered]@{
        skill = $sp.skill
        orphanStartDisplay = Format-Clock $sp.orphanStart
        flowResumedDisplay = Format-Clock $sp.flowResumed
        durationDisplay = Format-Duration (($sp.flowResumed - $sp.orphanStart).TotalSeconds)
        correlatedEntry = $correlatedEntry
    }
}

# Off-hours spans that do NOT fall inside any halt window (general case -- none in the log that
# drove this design, but the mechanism must not assume a halt is always in effect).
$offHoursWindowRows = @()
$offHoursIndex = 0
foreach ($seg in ($timeline | Where-Object { $_.bucket -eq "OffHours" -and -not $_.haltWindowIndex } | Sort-Object start)) {
    $offHoursIndex += 1
    $offHoursWindowRows += [ordered]@{
        index = $offHoursIndex
        startDisplay = Format-Clock $seg.start
        endDisplay = Format-Clock $seg.end
        durationDisplay = Format-Duration (($seg.end - $seg.start).TotalSeconds)
    }
}

# ---------------------------------------------------------------------------
# Loop fire breakdown -- tally by action-log action type (generic vocabulary: EXECUTE / GENERATE
# / GATE_REPAIR / STOP are the fixed action names sdp-project-state-loop and sdp-project-create-prompt write --
# not specific to any one dataset). Meaning text is a static, dataset-agnostic lookup restored
# from the 2026-07-11 17:24 report -- these are fixed definitions of the action vocabulary itself,
# not something that varies by period, so they belong here rather than being re-authored per run.
# GATE_REPAIR's "(see bug below)" pointer only makes sense when a Specific Issues section actually
# exists this run -- that's a skill-side conditional (Step 5 outcome), not something this script
# can know, so the base meaning here stays generic.
# ---------------------------------------------------------------------------
$actionMeanings = @{
    EXECUTE = "Dispatch ran (WORKER/REVIEWER/COORDINATOR/GATE_REVIEWER)"
    GENERATE = "Sentinel stale -> regenerated next dispatch prompt"
    GATE_REPAIR = "Gate dispatch self-heal cycle"
    STOP = "No-op fire, workflow already halted"
}

$loopFireCounts = @{}
foreach ($a in $actionEvents) {
    $key = [string]$a.action
    if (-not $loopFireCounts.ContainsKey($key)) { $loopFireCounts[$key] = 0 }
    $loopFireCounts[$key] += 1
}
$loopFireBreakdown = @()
foreach ($k in ($loopFireCounts.Keys | Sort-Object)) {
    $meaning = if ($actionMeanings.ContainsKey($k)) { $actionMeanings[$k] } else { $null }
    $loopFireBreakdown += [ordered]@{ action = $k; count = $loopFireCounts[$k]; meaning = $meaning }
}
$totalLoggedFires = ($loopFireCounts.Values | Measure-Object -Sum).Sum

# ---------------------------------------------------------------------------
# Phase / Work Covered -- work-item-to-phase mapping.
#
# Primary source, per project referenced in this period's events: that project's own phase
# `sdp-docs/*_state.json` files. Each one is self-describing -- it carries its own `phase` id and
# a `tasks` object keyed by work-item ID -- and is the exact record `sdp-project-coordinator`/
# `sdp-project-worker`/`sdp-project-reviewer` themselves read and write, so it's authoritative for phase<->task
# membership without needing `registry.md` at all. `registry.md` is consulted afterward, and only
# to resolve a phase id to its human-readable name for display -- a missing or wrong `registry.md`
# row can therefore only leave a phase unnamed (`phaseNameKnown: false`, already-supported by the
# existing schema), never mis-group a task, because grouping never reads registry.md as ground
# truth for anything.
#
# Fallback 1 (no `sdp-docs/*_state.json` files found for a project at all -- directory absent,
# unreadable, or none parse to a usable `phase`+`tasks` pair): reverts to the original halt_reason-
# pattern derivation ("[phase_id] GATE_REVIEWER blocked Nx - [reason]"), scoped to that project's
# own work items, exactly as this script behaved before per-task state-file mapping existed.
#
# Fallback 2 (a work item appears in this project's action log but neither source above claims
# it -- e.g. relocated/renamed since its state file was last touched): grouped into an explicit
# "(unmapped)" row rather than silently dropped or mis-attributed, so the report stays honest
# about what could and couldn't be resolved.
# ---------------------------------------------------------------------------
function Get-RegistryPhaseNames([string]$projectRoot) {
    # phaseFile (normalized, forward-slash) -> human-readable phase name, from registry.md's
    # `| # | Phase | Phase File | ... |` rows. Returns an empty map on any failure to read/parse
    # -- a missing or malformed registry.md degrades to "no names known", never an error.
    $map = @{}
    $registryPath = Join-Path $projectRoot ".sdp-workflow/registry.md"
    if (-not (Test-Path $registryPath)) { return $map }
    try {
        $lines = Get-Content $registryPath -Encoding UTF8 -ErrorAction Stop
    } catch { return $map }
    foreach ($line in $lines) {
        if ($line -notmatch '^\|\s*\d+\s*\|') { continue }
        $cols = $line.Trim().Trim('|') -split '\|'
        if ($cols.Count -lt 3) { continue }
        $name = $cols[1].Trim()
        $phaseFile = $cols[2].Trim().Replace('\', '/')
        if (-not $name -or -not $phaseFile) { continue }
        # First row wins on a duplicate/conflicting Phase File value -- inaccurate registry data
        # degrades to "first match", never a crash or a fabricated name.
        if (-not $map.ContainsKey($phaseFile)) { $map[$phaseFile] = $name }
    }
    return $map
}

function Get-ProjectPhaseTaskMap([string]$projectRoot) {
    # Returns $null when no usable phase state files exist (signals "use Fallback 1"), otherwise
    # @{ taskToPhase = @{ taskId -> phaseId }; phaseFile = @{ phaseId -> phaseFile }; phaseNames =
    # @{ phaseId -> name, only when registry.md had a matching row } }.
    $sdpDocsDir = Join-Path $projectRoot "sdp-docs"
    if (-not (Test-Path $sdpDocsDir)) { return $null }
    $stateFiles = @(Get-ChildItem -Path $sdpDocsDir -Filter "*_state.json" -File -ErrorAction SilentlyContinue)
    if ($stateFiles.Count -eq 0) { return $null }

    $registryNames = Get-RegistryPhaseNames $projectRoot
    $taskToPhase = @{}
    $phaseFileById = @{}
    $phaseNameById = @{}
    $foundAny = $false
    foreach ($sf in $stateFiles) {
        try {
            $stateObj = Get-Content $sf.FullName -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        } catch { continue }
        if (-not $stateObj.phase -or -not $stateObj.tasks) { continue }
        $phaseIdValue = [string]$stateObj.phase
        $phaseFileValue = if ($stateObj.phase_file) { ([string]$stateObj.phase_file).Replace('\', '/') } else { $null }
        $foundAny = $true
        $phaseFileById[$phaseIdValue] = $phaseFileValue
        if ($phaseFileValue -and $registryNames.ContainsKey($phaseFileValue)) {
            $phaseNameById[$phaseIdValue] = $registryNames[$phaseFileValue]
        }
        foreach ($taskProp in $stateObj.tasks.PSObject.Properties) {
            $taskToPhase[$taskProp.Name] = $phaseIdValue
        }
    }
    if (-not $foundAny) { return $null }
    return @{ taskToPhase = $taskToPhase; phaseFile = $phaseFileById; phaseNames = $phaseNameById }
}

$phaseRows = @()
$projectsThisPeriod = @($actionEvents | Where-Object { $_.project } | Select-Object -ExpandProperty project -Unique)
if ($projectsThisPeriod.Count -eq 0) { $projectsThisPeriod = @($null) }

foreach ($proj in $projectsThisPeriod) {
    $projEvents = if ($proj) { @($actionEvents | Where-Object { $_.project -eq $proj }) } else { $actionEvents }
    $projItems = @($projEvents | Where-Object { $_.work_item } | Select-Object -ExpandProperty work_item -Unique)
    if ($projItems.Count -eq 0) { continue }

    $projectRoot = if ($proj) { Join-Path $workspaceRoot $proj } else { $workspaceRoot }
    $mapping = if (Test-Path $projectRoot) { Get-ProjectPhaseTaskMap $projectRoot } else { $null }

    $itemsByPhase = [ordered]@{}
    $unmappedItems = @()
    $mappingSource = $null

    if ($mapping) {
        $mappingSource = "state-files"
        $knownPhaseIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@($mapping.phaseFile.Keys))
        foreach ($item in $projItems) {
            if ($knownPhaseIds.Contains($item)) {
                # The item IS a phase id -- a phase-level dispatch marker (e.g. a GATE_REVIEWER
                # work_item), not a child task. Ensures the phase's own row exists even if no
                # child task fired this period; contributes to timing via the `-eq` clause below,
                # never listed as a work item itself.
                if (-not $itemsByPhase.Contains($item)) { $itemsByPhase[$item] = @() }
                continue
            }
            $ownerPhase = if ($mapping.taskToPhase.ContainsKey($item)) { $mapping.taskToPhase[$item] } else { $null }
            if ($ownerPhase) {
                if (-not $itemsByPhase.Contains($ownerPhase)) { $itemsByPhase[$ownerPhase] = @() }
                $itemsByPhase[$ownerPhase] = @($itemsByPhase[$ownerPhase]) + $item
            } else {
                $unmappedItems += $item
            }
        }
    } else {
        # Fallback 1: halt_reason pattern, scoped to this project's own halt windows.
        $mappingSource = "halt-reason"
        $haltPhaseIds = @()
        foreach ($hw in $haltWindows) {
            if ($hw.cause -and $hw.cause -match '^([A-Za-z0-9_]+)\s+GATE_REVIEWER') { $haltPhaseIds += $Matches[1] }
        }
        $haltPhaseIds = @($haltPhaseIds | Select-Object -Unique)
        if ($haltPhaseIds.Count -gt 0) {
            # No per-item membership data of its own -- a halt_reason names a phase, never a task
            # list -- so (as before per-task mapping existed) the named phase claims every OTHER
            # work item seen in this project this period. Kept verbatim from pre-extension
            # behavior for the case where phase state files aren't available at all.
            foreach ($haltPhaseId in $haltPhaseIds) {
                $itemsByPhase[$haltPhaseId] = @($projItems | Where-Object { $_ -ne $haltPhaseId })
            }
        } else {
            $mappingSource = "unmapped"
            $unmappedItems = $projItems
        }
    }

    foreach ($phaseKey in $itemsByPhase.Keys) {
        $items = @($itemsByPhase[$phaseKey])
        $itemSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$items)
        $allRelevant = @($projEvents | Where-Object { $itemSet.Contains($_.work_item) -or $_.work_item -eq $phaseKey })
        if ($allRelevant.Count -eq 0) { continue }
        $first = ($allRelevant | Sort-Object _dt | Select-Object -First 1)._dt
        $last = ($allRelevant | Sort-Object _dt | Select-Object -Last 1)._dt
        # Extend start to include an orphaned/interrupted dispatch attempt for one of THIS phase's
        # own items -- scoped correlation (Get-OrphanCorrelatedEntry), not a blanket earliest-
        # orphan-in-the-whole-log extension, which would misattribute another phase's interruption
        # to this one now that more than one phase row can exist in a single report.
        foreach ($sp in $userInterruptedSpans) {
            $corrEntry = Get-OrphanCorrelatedEntry $sp
            $corrItem = if ($corrEntry) { $corrEntry.work_item } else { $null }
            if ($corrItem -and ($itemSet.Contains($corrItem) -or $corrItem -eq $phaseKey) -and $sp.orphanStart -lt $first) {
                $first = $sp.orphanStart
            }
        }
        $phaseNameKnown = $false
        if ($mapping -and $mapping.phaseNames.ContainsKey($phaseKey)) { $phaseNameKnown = $true }
        $phaseRows += [ordered]@{
            phaseId = $phaseKey
            phaseName = if ($phaseNameKnown) { $mapping.phaseNames[$phaseKey] } else { $null }
            phaseNameKnown = $phaseNameKnown
            project = $proj
            mappingSource = $mappingSource
            workItems = $items
            startDisplay = Format-Clock $first
            endDisplay = Format-Clock $last
            durationDisplay = Format-Duration (($last - $first).TotalSeconds)
        }
    }

    if ($unmappedItems.Count -gt 0) {
        $itemSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$unmappedItems)
        $allRelevant = @($projEvents | Where-Object { $itemSet.Contains($_.work_item) })
        if ($allRelevant.Count -gt 0) {
            $first = ($allRelevant | Sort-Object _dt | Select-Object -First 1)._dt
            $last = ($allRelevant | Sort-Object _dt | Select-Object -Last 1)._dt
            $phaseRows += [ordered]@{
                phaseId = "(unmapped)"
                phaseName = $null
                phaseNameKnown = $false
                project = $proj
                mappingSource = $mappingSource
                workItems = $unmappedItems
                startDisplay = Format-Clock $first
                endDisplay = Format-Clock $last
                durationDisplay = Format-Duration (($last - $first).TotalSeconds)
            }
        }
    }
}

if ($phaseRows.Count -eq 0) {
    # Ultimate fallback -- no work-item-bearing events anywhere in this period.
    $workItemsByProject = @($actionEvents | Where-Object { $_.work_item } | Select-Object -ExpandProperty work_item -Unique)
    $phaseRows += [ordered]@{
        phaseId = $null
        phaseName = $null
        phaseNameKnown = $false
        project = $null
        mappingSource = "none"
        workItems = $workItemsByProject
        startDisplay = Format-Clock $periodStart
        endDisplay = Format-Clock $periodEnd
        durationDisplay = Format-Duration $totalSeconds
    }
}

# ---------------------------------------------------------------------------
# Task-by-task outcomes -- WORKER WORK_COMPLETE and REVIEWER VERIFIED EXECUTE entries per
# work_item. A missing EXECUTE record is inferred from the next GENERATE entry for the same
# work_item/role whose reason references the expected status -- a generic "missing action-log
# line" pattern (see Methodology), not a one-off.
#
# Elapsed-time breadcrumb (user direction, 2026-07-12): the WORKER dispatch-start timestamp isn't
# directly logged per work_item -- it's inferred from the nearest preceding sdp-project-worker skill-tone
# interval. When that interval's own start was itself the resumption of an orphaned/interrupted
# earlier attempt, a single "true" start time isn't something this script can responsibly pick --
# it emits the full candidate chain instead (workerDispatchCandidates) and
# workerElapsedComputable:false, leaving the estimate + `~` marking to the report-assembly skill.
# reviewerElapsedDisplay has no such ambiguity (both endpoints are already-known EXECUTE/GENERATE
# timestamps) -- its confidence rides entirely on the existing reviewerVerifiedInferred flag.
# ---------------------------------------------------------------------------
function Get-WorkerDispatchChain([datetimeoffset]$primaryStart) {
    $chain = @([ordered]@{ startDisplay = (Format-Clock $primaryStart); outcome = "resumed" })
    $cursor = $primaryStart
    $guard = 0
    while ($guard -lt 10) {
        $guard++
        $match = @($userInterruptedSpans | Where-Object { $_.skill -eq $canonicalWorker -and $_.flowResumed -eq $cursor } | Select-Object -First 1)
        if ($match.Count -eq 0) { break }
        $chain = @([ordered]@{ startDisplay = (Format-Clock $match[0].orphanStart); outcome = "orphaned" }) + $chain
        $cursor = $match[0].orphanStart
    }
    return $chain
}

# ---------------------------------------------------------------------------
# No-progress-fire breadcrumb (user direction, 2026-07-12): a WORKER EXECUTE fire with no status
# transition (status_before == status_after) is structurally identical whether it means "the
# session paused awaiting a human decision" or "the state-loop is polling a background job the
# WORKER deliberately kicked off" -- verified against this exact dataset, which has real examples
# of both. Only the free-text reason distinguishes them, and that's judgment (reading prose), not
# a fixed rule -- so this is raw facts only, grouped by work_item, for the report-assembly skill
# to interpret. Never used here to move seconds between buckets.
# ---------------------------------------------------------------------------
$noProgressFiresByWorkItem = @{}
foreach ($a in $actionEvents) {
    if ($a.role -eq "WORKER" -and $a.action -eq "EXECUTE" -and $a.work_item -and ($a.status_before -eq $a.status_after)) {
        $wi = $a.work_item
        if (-not $noProgressFiresByWorkItem.ContainsKey($wi)) { $noProgressFiresByWorkItem[$wi] = @() }
        $noProgressFiresByWorkItem[$wi] += [ordered]@{
            timestampDisplay = Format-Clock $a._dt
            reason = $a.reason
        }
    }
}

$taskRows = @()
$workItemsForTasks = @($actionEvents | Where-Object { $_.work_item -and $_.role -in @("WORKER", "REVIEWER") } | Select-Object -ExpandProperty work_item -Unique)
foreach ($wi in $workItemsForTasks) {
    $workerComplete = @($actionEvents | Where-Object { $_.work_item -eq $wi -and $_.role -eq "WORKER" -and $_.status_after -eq "WORK_COMPLETE" } | Sort-Object _dt | Select-Object -First 1)
    $reviewerVerified = @($actionEvents | Where-Object { $_.work_item -eq $wi -and $_.role -eq "REVIEWER" -and $_.status_after -eq "VERIFIED" } | Sort-Object _dt | Select-Object -First 1)
    $inferred = $false
    $reviewerVerifiedDisplay = $null
    $reviewerVerifiedDt = $null
    if ($reviewerVerified.Count -gt 0) {
        $reviewerVerifiedDisplay = Format-Clock $reviewerVerified[0]._dt
        $reviewerVerifiedDt = $reviewerVerified[0]._dt
    } else {
        # Look for a GENERATE entry for this work_item/REVIEWER whose reason cites VERIFIED.
        $gen = @($actionEvents | Where-Object { $_.work_item -eq $wi -and $_.role -eq "REVIEWER" -and $_.action -eq "GENERATE" -and $_.reason -match "VERIFIED" } | Sort-Object _dt | Select-Object -First 1)
        if ($gen.Count -gt 0) {
            $reviewerVerifiedDisplay = Format-Clock $gen[0]._dt
            $reviewerVerifiedDt = $gen[0]._dt
            $inferred = $true
        }
    }

    if (-not ($workerComplete.Count -gt 0 -or $reviewerVerifiedDisplay)) { continue }

    $workerElapsedComputable = $false
    $workerElapsedDisplay = $null
    $workerDispatchStartDisplay = $null
    $workerDispatchCandidates = @()
    if ($workerComplete.Count -gt 0) {
        $primaryInterval = @($allIntervals | Where-Object { $_.skill -eq $canonicalWorker -and $_.end -le $workerComplete[0]._dt } | Sort-Object end -Descending | Select-Object -First 1)
        if ($primaryInterval.Count -gt 0) {
            $chain = @(Get-WorkerDispatchChain $primaryInterval[0].start)
            if ($chain.Count -eq 1) {
                $workerElapsedComputable = $true
                $workerDispatchStartDisplay = $chain[0].startDisplay
                $workerElapsedDisplay = Format-Duration (($workerComplete[0]._dt - $primaryInterval[0].start).TotalSeconds)
            } else {
                $workerDispatchCandidates = $chain
            }
        }
    }

    $reviewerElapsedDisplay = $null
    if ($workerComplete.Count -gt 0 -and $reviewerVerifiedDt) {
        $reviewerElapsedDisplay = Format-Duration (($reviewerVerifiedDt - $workerComplete[0]._dt).TotalSeconds)
    }

    # @(...) wrap is load-bearing: PowerShell's ConvertTo-Json collapses a 1-element array into a
    # bare object (and the pipeline drops a 0-element array to nothing) unless the value is forced
    # into array context at the point of assignment -- verified directly against this exact
    # pattern before applying it (2026-07-12); without it, FILING-1's single breadcrumb serialized
    # as `{...}` instead of `[{...}]`, and empty arrays serialized as `{}` instead of `[]`.
    $noProgressFires = @(if ($noProgressFiresByWorkItem.ContainsKey($wi)) { $noProgressFiresByWorkItem[$wi] } else { @() })

    $taskRows += [ordered]@{
        workItem = $wi
        workerCompleteDisplay = if ($workerComplete.Count -gt 0) { Format-Clock $workerComplete[0]._dt } else { $null }
        reviewerVerifiedDisplay = $reviewerVerifiedDisplay
        reviewerVerifiedInferred = $inferred
        workerElapsedComputable = $workerElapsedComputable
        workerElapsedDisplay = $workerElapsedDisplay
        workerDispatchStartDisplay = $workerDispatchStartDisplay
        workerDispatchCandidates = $workerDispatchCandidates
        reviewerElapsedDisplay = $reviewerElapsedDisplay
        noProgressFires = $noProgressFires
    }
}

# ---------------------------------------------------------------------------
# Anomaly facts for the LLM to phrase (Data-quality notes) -- raw detections only, no narrative.
# This threshold (15 min) is intentionally lower/separate from the Off-hours threshold (default
# 30 min): this one flags any gap worth a second look in prose; Off-hours is the stricter bar for
# actually moving seconds between buckets.
# ---------------------------------------------------------------------------
$gapThresholdSeconds = $unloggedGapThresholdSeconds  # sourced from script-support config (default 900 = 15 min); zero logged events of any kind for this long is worth flagging
$unloggedGaps = @()
for ($i = 1; $i -lt $events.Count; $i++) {
    $gap = ($events[$i]._dt - $events[$i - 1]._dt).TotalSeconds
    if ($gap -ge $gapThresholdSeconds) {
        $unloggedGaps += [ordered]@{
            startDisplay = Format-Clock $events[$i - 1]._dt
            endDisplay = Format-Clock $events[$i]._dt
            durationDisplay = Format-Duration $gap
        }
    }
}

$missingExecuteInferences = @($taskRows | Where-Object { $_.reviewerVerifiedInferred } | ForEach-Object { $_.workItem })

# ---------------------------------------------------------------------------
# Loop fire breakdown table -- pre-rendered markdown including the Total row, whose Meaning cell
# carries the generic undercounting caveat (restored report's version referenced a specific
# PowerShell error string this pipeline has no way to know -- unloggedGaps only has gap timing,
# not root cause -- so the caveat here is worded from what's actually derivable: gap count only).
# ---------------------------------------------------------------------------
$loopFireTableRows = ($loopFireBreakdown | ForEach-Object { "| $($_.action) | $($_.count) | $($_.meaning) |" }) -join "`n"
$totalMeaning = if ($unloggedGaps.Count -gt 0) {
    "Actual fire count may be higher -- $($unloggedGaps.Count) unlogged gap(s) this period had zero log entries of any kind (see Data-quality notes below)."
} else {
    ""
}
$loopFireTableMarkdown = @"
| Action | Count | Meaning |
|---|---|---|
$loopFireTableRows
| **Total logged** | **$totalLoggedFires** | $totalMeaning |
"@

# ---------------------------------------------------------------------------
# Static Methodology boilerplate (emitted verbatim -- mirrors the bucket definitions computed
# above; keep the two in sync if either changes). Restored to the 2026-07-11 17:24 report's fuller
# wording -- the mutual-exclusivity framing, the write-failure-vs-genuine-interruption distinction,
# and pointers to the tables that carry the supporting evidence. Table names are referenced in
# plain text, not hardcoded anchors -- anchor/link presentation is a skill-side (report-assembly)
# concern, not something this script should assume about how its output gets rendered.
# ---------------------------------------------------------------------------
$methodologyMarkdown = @"
- *Productive* time is the sum of non-overlapping start-to-end intervals for the ``$canonicalWorker``, ``$canonicalReviewer``, ``$canonicalCoordinator``, and ``$canonicalGateReviewer`` skill invocations recorded in the tone log (normalized from any prior name that skill has been renamed from, per `script-support/sdp-report-log-loop-metrics-skills.json`) -- the intervals where a subagent was actually doing implementation, review, or dispatch-decision work -- **excluding** any such interval that occurs while ``workflow_status: "halted"`` was in effect (those go to *Halt resolution* instead; the two buckets are mutually exclusive by construction, not just by convention) and excluding any portion that overlaps genuine log silence (see *Off-hours* below) -- a cleanly-paired start/end interval can still span an overnight gap in the middle if the subagent itself didn't emit its ``end`` tone until it truly finished (e.g. a WORKER that paused awaiting a user decision, went quiet for hours, then resumed and eventually returned, all within one start/end pair with no orphan involved at all). Only the non-silent portions of such an interval count as Productive.
- *Halt resolution* time is the sum of the same four skills' start-to-end intervals, restricted to those that occur *while* ``workflow_status: "halted"`` was in effect -- concrete evidence that a human/agent broke a halt's passive retry cycle to actively diagnose and fix it, rather than letting the automated loop simply keep re-firing a no-op ``STOP``. A halt window with **no** Halt-resolution interval inside it means the passive ``STOP`` cycle ran uninterrupted until something else ended it (cron cancellation, log end) -- evidence nobody was actively working the fix during that window. A halt window that **does** contain one or more Halt-resolution intervals means the passive cycle was broken by real dispatch work before the halt cleared. Only intervals with direct skill-tone evidence count here -- a silent gap between two Halt-resolution intervals, still inside the same halted window, is not assumed to be active work and falls to *Unproductive* instead, even though a human may well have been present; the classification only credits what the log can actually show.
- *Off-hours (no active session)* time is any stretch of total log silence -- zero events of any kind -- lasting $OffHoursThresholdMinutes minutes or more, whether or not a halt was in effect at the time. It means nobody and nothing was running, not that a live session was blocked and unattended. This is the hardest evidence available (a raw event gap, not an inferred pairing), so it takes precedence over every other bucket wherever it overlaps one -- Productive, Halt resolution, and User-interrupted intervals are all carved against it before anything else is computed. Below the threshold, a gap simply stays whatever bucket it would otherwise be; the threshold is a floor, not a per-bucket setting.
- *Unproductive* time is the sum of all halt-window spans, each bounded by the fire that set the halt and the fire/session that cleared it (or end-of-log if a halt is still unresolved), **minus** any Halt-resolution, User-interrupted, and Off-hours time within that span -- so it measures only the halted time with *no* recorded resolution work in progress. See the Halt windows table for the full halt spans and the Halt-resolution windows table for the carve-outs.
- *User-interrupted* time is the sum of spans where a skill ``start`` tone has no matching ``end`` tone before the next ``start`` of that same skill (or before the flow's next dispatch/redispatch), measured from the orphaned ``start`` to the point the flow resumed, minus any portion that overlaps genuine log silence (see *Off-hours* above -- the same carve-out applies here as everywhere else). This is distinct from a transient ``action``-log write failure, where the underlying skill completed fine and only the log *line* was lost -- an orphaned ``start``/``end`` pair instead means the skill *session itself* was broken off before completion, treated as the user interrupting the SDP flow (e.g. closing the session) rather than a logging artifact. The Duration shown in the User-interrupted windows table is still the full orphan-to-resumed span, even though only the non-silent leftover counted toward this bucket's total. See the User-interrupted windows table for this period's specific occurrences.
- *Idle/overhead* is the **residual**: Total minus Productive minus Halt resolution minus Off-hours minus Unproductive minus User-interrupted. It is not independently summed from bookkeeping-skill intervals and gaps -- it is whatever wall-clock time remains after the five measured buckets above are subtracted, so it also absorbs any margin of error in those five. Its plausible components are ``sdp-project-state-loop``/``sdp-project-run-prompt``/``sdp-project-create-prompt`` bookkeeping overhead, ``sdp-project-pre-work-verify`` and ``sdp-project-read-docs`` calls, and unlogged gaps between fires -- none separately verified. This is an estimate from tone-log timestamps, not an instrumented measurement; any fires missing a metrics-log entry (e.g. a transient log-write failure) widen this margin further.
"@

# ---------------------------------------------------------------------------
# Emit the JSON envelope.
# ---------------------------------------------------------------------------
Write-Result @{
    status = "success"
    error = $null
    period = @{
        startIso = $periodStart.ToString("o")
        endIso = $periodEnd.ToString("o")
        startDisplay = Format-Clock $periodStart
        endDisplay = Format-Clock $periodEnd
        titleDate = $titleDate
    }
    header = @{
        sourceFile = $sourceRelative
        sourceLineCount = $sourceLineCount
        projectNames = $projectNames
        reportPreparedDate = $reportPreparedDate
    }
    buckets = $buckets
    bucketTableMarkdown = $bucketTableMarkdown
    haltWindows = $haltWindowRows
    haltResolutionWindows = $haltResolutionRows
    haltResolutionEmptyNotes = $haltResolutionEmptyNotes
    userInterruptedWindows = $userInterruptedRows
    offHoursWindows = $offHoursWindowRows
    offHoursThresholdMinutes = $OffHoursThresholdMinutes
    loopFireBreakdown = $loopFireBreakdown
    loopFireTableMarkdown = $loopFireTableMarkdown
    totalLoggedFires = $totalLoggedFires
    phaseWorkCovered = $phaseRows
    taskByTaskOutcomes = $taskRows
    compositionBarSvg = $compositionBarSvg
    chronologicalBarSvg = $chronologicalBarSvg
    legendHtml = $legendHtml
    methodologyMarkdown = $methodologyMarkdown
    anomalies = @{
        unloggedGaps = $unloggedGaps
        missingExecuteInferredWorkItems = $missingExecuteInferences
    }
    pairingWarnings = $pairingWarnings
}
exit 0
