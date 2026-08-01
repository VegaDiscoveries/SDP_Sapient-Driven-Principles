<#
.SYNOPSIS
    Merge one calendar day's three source logs (loop-metrics-*.jsonl, hook-log-*.jsonl,
    workflow-log-*.jsonl) into a single normalized combined-log-yyyyMMdd.jsonl under
    .sdp-solution-workflow/logging/combined-logs/. Every source entry is mapped, via a fixed
    dataset-agnostic rule per source/shape, into one common envelope shape so a single downstream
    reader (sdp-report-log-combined-metrics.ps1) can process all three without shape-specific
    branching. No entry is dropped or summarized -- the original object is preserved verbatim in
    the envelope's `raw` field, so the combine is lossless regardless of how the normalized
    (best-effort) fields are derived.

.PARAMETER Date
    Calendar date to combine (yyyy-MM-dd). Defaults to today. Unlike the report scripts, this is
    a creation operation, not a selection over existing files -- there is no "most recent file"
    to default to; today is the only sensible default.

.NOTES
    Stdout: single-line JSON result object (agent-consumed script per SDP-Script-Authoring.md).
    Exit codes: 0 = success (status may still be "error" inside the JSON for a handled condition);
    1 reserved for an operational failure that prevented any JSON from being written at all.

    Idempotent: re-running for the same -Date recomputes and overwrites that day's
    combined-log-yyyyMMdd.jsonl in full (Set-Content, not Add-Content) -- this is a derived
    artifact rebuilt from the three source-of-truth logs, not itself a source log, so there is no
    append-only concern the way there is for loop-metrics-*.jsonl/hook-log-*.jsonl/
    workflow-log-*.jsonl themselves.

    A source file that does not exist for the requested date contributes zero entries and is
    noted in `sourcesFound`/`sourceCounts`, not treated as an error -- e.g. a fresh workspace's
    first day may have loop-metrics activity but no hook-log or workflow-log entries yet. Only
    all three being absent is an error (nothing to combine).

    Unified envelope shape (every line of the output file):
        timestamp   -- ISO 8601, verbatim from the source entry
        source      -- "loop-metrics" | "hook-log" | "workflow-log"
        category    -- source-specific sub-shape: loop-metrics has three (see Normalization
                       Rules below); hook-log and workflow-log have exactly one each
        role        -- string or null
        work_item   -- string or null
        phase       -- string or null
        event_name  -- normalized single "what happened" label (mapping below)
        outcome     -- string or null
        reason      -- string or null
        detail      -- string or null (workflow-log's `detail` field only; null elsewhere)
        raw         -- the original parsed JSON object, untouched

    Normalization Rules (fixed, dataset-agnostic; see .NOTES for the full field-by-field mapping
    reasoning -- summarized here for the JSON consumer):
      loop-metrics / channel=="skill"  -> category "skill-tone";    event_name "{skillName}:{event}"
      loop-metrics / channel=="event"  -> category "workflow-tone"; event_name "{trigger}"
      loop-metrics / has .action       -> category "action";       event_name "{action}"; role/work_item
                                           from the entry; outcome = status_after; reason = .reason if
                                           present, else .halt_reason if halted, else null
      hook-log (every entry)           -> category "hook-event";   event_name "{hook_event_name}:{tool_name}";
                                           work_item from the entry; role/phase/outcome always null
      workflow-log (every entry)       -> category "workflow-event"; event_name = .trigger; role/work_item/
                                           phase/outcome/reason/detail all taken directly from the entry
#>
param(
    [string]$Date = ""
)

function Write-Result([hashtable]$hash) {
    Write-Output ($hash | ConvertTo-Json -Compress -Depth 12)
}

$workspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

if (-not $Date) { $Date = (Get-Date).ToString("yyyy-MM-dd") }
try {
    $parsedDate = [datetime]::Parse($Date)
} catch {
    Write-Result @{ status = "error"; error = "invalid -Date value: $Date (expected yyyy-MM-dd)" }
    exit 0
}
$stamp = $parsedDate.ToString("yyyyMMdd")

$loopPath = Join-Path $workspaceRoot ".sdp-solution-workflow/logging/loop-logs/loop-metrics-$stamp.jsonl"
$hookPath = Join-Path $workspaceRoot ".sdp-solution-workflow/logging/hook-logs/hook-log-$stamp.jsonl"
$workflowPath = Join-Path $workspaceRoot ".sdp-solution-workflow/logging/workflow-logs/workflow-log-$stamp.jsonl"
$outDir = Join-Path $workspaceRoot ".sdp-solution-workflow/logging/combined-logs"
$outPath = Join-Path $outDir "combined-log-$stamp.jsonl"

function Read-JsonlEntries([string]$path) {
    # Returns @{ entries = @(...); unparseableLineCount = N }. Missing file -> zero entries, not
    # an error -- the caller decides whether "all three missing" is fatal.
    if (-not (Test-Path $path)) { return @{ entries = @(); unparseableLineCount = 0 } }
    $rawLines = Get-Content $path -Encoding UTF8
    $entries = @()
    $badCount = 0
    foreach ($line in $rawLines) {
        if (-not $line -or $line.Trim() -eq "") { continue }
        try {
            $obj = $line | ConvertFrom-Json
            if ($obj.timestamp) { $entries += $obj } else { $badCount++ }
        } catch { $badCount++ }
    }
    return @{ entries = $entries; unparseableLineCount = $badCount }
}

$loopResult = Read-JsonlEntries $loopPath
$hookResult = Read-JsonlEntries $hookPath
$workflowResult = Read-JsonlEntries $workflowPath

$sourcesFound = @()
if (Test-Path $loopPath) { $sourcesFound += "loop-metrics" }
if (Test-Path $hookPath) { $sourcesFound += "hook-log" }
if (Test-Path $workflowPath) { $sourcesFound += "workflow-log" }

if ($sourcesFound.Count -eq 0) {
    Write-Result @{ status = "error"; error = "no source logs found for date $Date (checked loop-logs/, hook-logs/, workflow-logs/)" }
    exit 0
}

# ---------------------------------------------------------------------------
# Normalization -- one function per source, each a fixed field-mapping rule (see .NOTES). Every
# normalized object carries the complete original entry verbatim in `raw`, so nothing is lost
# even where a normalized field is null because the source shape doesn't have an equivalent.
# ---------------------------------------------------------------------------
function New-Envelope($timestamp, $source, $category, $role, $workItem, $phase, $eventName, $outcome, $reason, $detail, $raw) {
    return [ordered]@{
        timestamp = $timestamp
        source = $source
        category = $category
        role = $role
        work_item = $workItem
        phase = $phase
        event_name = $eventName
        outcome = $outcome
        reason = $reason
        detail = $detail
        raw = $raw
    }
}

$combined = @()

foreach ($e in $loopResult.entries) {
    if ($e.channel -eq "skill") {
        $combined += New-Envelope $e.timestamp "loop-metrics" "skill-tone" $null $null $null "$($e.skillName):$($e.event)" $null $e.reason $null $e
    } elseif ($e.channel -eq "event") {
        $combined += New-Envelope $e.timestamp "loop-metrics" "workflow-tone" $null $null $null ([string]$e.trigger) $null $e.reason $null $e
    } elseif ($e.action) {
        $reasonValue = if ($e.reason) { $e.reason } elseif ($e.halted -eq $true -and $e.halt_reason) { $e.halt_reason } else { $null }
        $workItemValue = if ($e.work_item) { [string]$e.work_item } else { $null }
        $roleValue = if ($e.role) { [string]$e.role } else { $null }
        $outcomeValue = if ($e.status_after) { [string]$e.status_after } else { $null }
        $combined += New-Envelope $e.timestamp "loop-metrics" "action" $roleValue $workItemValue $null ([string]$e.action) $outcomeValue $reasonValue $null $e
    }
    # Any loop-metrics entry matching none of the three known shapes is skipped, not fabricated
    # into a guessed category -- this would only happen if a future writer adds a fourth shape
    # this script hasn't been updated for yet.
}

foreach ($e in $hookResult.entries) {
    $workItemValue = if ($e.work_item) { [string]$e.work_item } else { $null }
    $eventName = "$($e.hook_event_name):$($e.tool_name)"
    $combined += New-Envelope $e.timestamp "hook-log" "hook-event" $null $workItemValue $null $eventName $null $null $null $e
}

foreach ($e in $workflowResult.entries) {
    $roleValue = if ($e.role) { [string]$e.role } else { $null }
    $workItemValue = if ($e.work_item) { [string]$e.work_item } else { $null }
    $phaseValue = if ($e.phase) { [string]$e.phase } else { $null }
    $outcomeValue = if ($e.outcome) { [string]$e.outcome } else { $null }
    $reasonValue = if ($e.reason) { [string]$e.reason } else { $null }
    $detailValue = if ($e.detail) { [string]$e.detail } else { $null }
    $combined += New-Envelope $e.timestamp "workflow-log" "workflow-event" $roleValue $workItemValue $phaseValue ([string]$e.trigger) $outcomeValue $reasonValue $detailValue $e
}

if ($combined.Count -eq 0) {
    Write-Result @{ status = "error"; error = "source log(s) present for date $Date but contained zero parseable entries" }
    exit 0
}

$combined = @($combined | Sort-Object { [datetimeoffset]::Parse($_.timestamp) })

# ---------------------------------------------------------------------------
# Write the combined file -- overwrite in full (this is a derived/regenerable artifact, not an
# append-only source log). UTF-8 no-BOM so line 1 parses cleanly, matching every other jsonl
# writer in this project (sdp-tone.ps1, sdp-hook-log.ps1, sdp-workflow-log.ps1).
# ---------------------------------------------------------------------------
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$lines = $combined | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 12 }
$content = ($lines -join "`n") + "`n"
[System.IO.File]::WriteAllText($outPath, $content, (New-Object System.Text.UTF8Encoding($false)))

$sourceCounts = @{
    "loop-metrics" = @{ entriesRead = $loopResult.entries.Count; unparseableLineCount = $loopResult.unparseableLineCount }
    "hook-log" = @{ entriesRead = $hookResult.entries.Count; unparseableLineCount = $hookResult.unparseableLineCount }
    "workflow-log" = @{ entriesRead = $workflowResult.entries.Count; unparseableLineCount = $workflowResult.unparseableLineCount }
}

Write-Result @{
    status = "success"
    error = $null
    date = $parsedDate.ToString("yyyy-MM-dd")
    outputPath = $outPath
    sourcesFound = $sourcesFound
    sourceCounts = $sourceCounts
    totalCombinedEntries = $combined.Count
}
exit 0
