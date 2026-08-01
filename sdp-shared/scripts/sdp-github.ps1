<#
.SYNOPSIS
    Unified GitHub/git interaction script for SDP. Wraps all routine git/gh interaction behind
    bounded, named subcommands with a uniform JSON output contract. The CI-green gate is the
    `ci-status` subcommand. One allow-listed entry replaces N per-command permission entries.

.PARAMETER Command
    Positional subcommand to run. Defaults to "help" (lists the available subcommands).
    See the subcommand catalog in .NOTES.

.PARAMETER workspaceRoot
    Path to the workspace root. Defaults to two levels above this script
    (sdp-shared/scripts/), matching the sdp-tone.ps1 / sdp-create-prompt.ps1 convention.

.PARAMETER Branch
    Branch name for branch-create / switch.

.PARAMETER Title
    PR title for pr-create.

.PARAMETER Body
    PR body for pr-create.

.PARAMETER Base
    Base branch for pr-create.

.PARAMETER Number
    PR number for pr-status / pr-view / pr-checks. Absent -> current branch's PR.

.PARAMETER RunId
    Workflow run id for run-log-failed.

.PARAMETER Limit
    Bound on list-style commands (log, run-list, pr-list). Default 20.

.PARAMETER TimeoutSeconds
    Overrides ci.waitTimeoutSeconds for ci-status. When omitted the value from the SDP-Config.json
    ci block (default 600) is used.

.PARAMETER WhatIf
    Resolve the intended git/gh invocation(s) to JSON WITHOUT executing them. Serves as a dry-run
    channel and the primary deterministic test hook (the sdp-tone.ps1 -whatIf precedent).

.NOTES
    Writes: nothing to disk in v1. All output is a single-line JSON envelope on stdout.

    Stdout contract - every invocation emits exactly one compact JSON line:
      { "ok": <bool>, "command": "<name>", "status": "<semantic>", "error": <null|string>, ... }
    On a wrapped-tool failure the envelope also carries "exitCode" and "stderr". The script
    never emits an unhandled git/gh failure - operational errors are caught and surfaced in the
    envelope.

    Exit codes:
      0  whenever the script itself ran correctly - INCLUDING a ci-status run whose result is
         "red" (a red CI is a successful observation, not a script error). Matches the
         sdp-create-prompt.ps1 precedent where a halted workflow exits 0.
      1  only on an operational/script error (a wrapped tool failed, or the requested operation
         could not be completed). The error envelope is still emitted before exit.

    Subcommand catalog - v1 (safe tier: read + non-destructive write):
      Local/git : status, head, current-branch, log, push, fetch, pull, branch-create, switch
      CI (gh)   : ci-status (the gate), run-list, run-log-failed
      PR (gh)   : pr-create, pr-status / pr-view, pr-list, pr-checks
      Meta      : auth-status, repo-view, help

    Destructive tier - recognized but NOT-IMPLEMENTED-v1 (return not_implemented sentinel,
    perform no action): push-force, branch-delete, pr-merge, pr-close, pr-reopen.

    ci-status status values: green | red | no_ci | timeout | unreachable on a clean run, or the
    uniform error envelope if the gate's own gh/git invocation failed. When the SDP-Config.json
    ci block is disabled or absent, ci-status returns no_ci (local-green fallback).
#>
param(
    [Parameter(Position = 0)][string]$Command = "help",
    [string]$workspaceRoot = "",
    [string]$Branch,
    [string]$Title,
    [string]$Body,
    [string]$Base,
    [int]$Number,
    [int]$RunId,
    [int]$Limit = 20,
    [int]$TimeoutSeconds,
    [switch]$WhatIf
)

if (-not $workspaceRoot) {
    $workspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

# ---------------------------------------------------------------------------
# Emitter - single point of control for the stdout envelope.
# ---------------------------------------------------------------------------

function Write-Result($obj) {
    Write-Output ($obj | ConvertTo-Json -Compress -Depth 6)
}

# ---------------------------------------------------------------------------
# Tool wrappers - execute the underlying tool, capture stdout/stderr/exit code,
# and NEVER throw. The caller inspects the returned structured result.
# ---------------------------------------------------------------------------

function Invoke-Tool([string]$exe, [string[]]$arguments) {
    $result = [ordered]@{
        exe      = $exe
        args     = $arguments
        stdout   = ""
        stderr   = ""
        exitCode = $null
        threw    = $false
        error    = $null
    }
    $errFile = $null
    try {
        $errFile = [System.IO.Path]::GetTempFileName()
        # Run the tool from the workspace root so git/gh resolve the correct repo.
        $stdout = & $exe @arguments 2>$errFile
        $result.exitCode = $LASTEXITCODE
        if ($null -ne $stdout) { $result.stdout = ($stdout -join "`n") }
        if (Test-Path $errFile) { $result.stderr = (Get-Content $errFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue) }
        if ($null -eq $result.stderr) { $result.stderr = "" }
    } catch {
        $result.threw = $true
        $result.error = $_.Exception.Message
        if ($null -eq $result.exitCode) { $result.exitCode = -1 }
    } finally {
        if ($errFile -and (Test-Path $errFile)) { Remove-Item $errFile -Force -ErrorAction SilentlyContinue }
    }
    return $result
}

function Invoke-Git([string[]]$arguments)  { return Invoke-Tool "git" $arguments }
function Invoke-Gh([string[]]$arguments)   { return Invoke-Tool "gh"  $arguments }

function Test-ToolOk($r) {
    # A wrapped tool ran cleanly when it did not throw and exited 0.
    return (-not $r.threw) -and ($r.exitCode -eq 0)
}

function New-ToolError([string]$command, [string]$message, $r) {
    $env = [ordered]@{
        ok       = $false
        command  = $command
        status   = "error"
        error    = $message
        exitCode = $r.exitCode
        stderr   = ($r.stderr).Trim()
    }
    return $env
}

# ---------------------------------------------------------------------------
# Config - read the ci block from SDP-Config.json (parallel to autoResolveHalt).
# ---------------------------------------------------------------------------

function Get-CiConfig {
    $cfg = [ordered]@{ enabled = $false; provider = $null; waitTimeoutSeconds = 600 }
    $path = Join-Path $workspaceRoot "SDP-Config.json"
    if (-not (Test-Path $path)) { return $cfg }
    try {
        $json = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($json.ci) {
            if ($null -ne $json.ci.enabled)            { $cfg.enabled = [bool]$json.ci.enabled }
            if ($json.ci.provider)                     { $cfg.provider = "$($json.ci.provider)" }
            if ($null -ne $json.ci.waitTimeoutSeconds) { $cfg.waitTimeoutSeconds = [int]$json.ci.waitTimeoutSeconds }
        }
    } catch { }
    return $cfg
}

# ---------------------------------------------------------------------------
# Plan model - for -WhatIf, describe the intended invocation(s) without running.
# ---------------------------------------------------------------------------

function Get-Plan([string]$command) {
    # Returns the ordered list of intended argv vectors for a command. ci-status and the
    # not_implemented tier have no executable plan (the latter performs no action).
    switch ($command) {
        "status"         { return @(,@("git", "status", "--porcelain=v1", "--branch")) }
        "head"           { return @(,@("git", "rev-parse", "HEAD")) }
        "current-branch" { return @(,@("git", "rev-parse", "--abbrev-ref", "HEAD")) }
        "log"            { return @(,@("git", "log", "--oneline", "-n", "$Limit")) }
        "push"           { return @(,@("git", "push", "origin", "HEAD")) }
        "fetch"          { return @(,@("git", "fetch", "origin")) }
        "pull"           { return @(,@("git", "pull", "--ff-only")) }
        "branch-create"  { return @(,@("git", "checkout", "-b", "$Branch")) }
        "switch"         { return @(,@("git", "checkout", "$Branch")) }
        "ci-status" {
            return @(
                @("git", "rev-parse", "HEAD"),
                @("gh", "run", "list", "--commit", "<HEAD>", "--limit", "1", "--json", "databaseId,status,conclusion,url"),
                @("gh", "run", "watch", "<runId>", "--exit-status")
            )
        }
        "run-list"       { return @(,@("gh", "run", "list", "--limit", "$Limit", "--json", "databaseId,status,conclusion,headBranch,workflowName,url")) }
        "run-log-failed" { return @(,@("gh", "run", "view", "$RunId", "--log-failed")) }
        "pr-create" {
            $a = @("gh", "pr", "create", "--title", "$Title", "--body", "$Body")
            if ($Base) { $a += @("--base", "$Base") }
            return @(,$a)
        }
        "pr-status"  { return @(,(Get-PrViewArgs)) }
        "pr-view"    { return @(,(Get-PrViewArgs)) }
        "pr-list"    { return @(,@("gh", "pr", "list", "--limit", "$Limit", "--json", "number,title,headRefName,state,url")) }
        "pr-checks"  {
            $a = @("gh", "pr", "checks")
            if ($Number -gt 0) { $a += "$Number" }
            return @(,$a)
        }
        "auth-status" { return @(,@("gh", "auth", "status")) }
        "repo-view"   { return @(,@("gh", "repo", "view", "--json", "name,defaultBranchRef,url,nameWithOwner")) }
        default       { return @() }
    }
}

function Get-PrViewArgs {
    $a = @("gh", "pr", "view")
    if ($Number -gt 0) { $a += "$Number" }
    $a += @("--json", "number,title,state,headRefName,url,statusCheckRollup")
    return $a
}

$SafeCommands = @(
    "status", "head", "current-branch", "log", "push", "fetch", "pull",
    "branch-create", "switch", "ci-status", "run-list", "run-log-failed",
    "pr-create", "pr-status", "pr-view", "pr-list", "pr-checks",
    "auth-status", "repo-view"
)
$DestructiveCommands = @{
    "push-force"    = "deferred to v2 - requires guardrail design (no-force-on-shared-branches, branch-protection list)"
    "branch-delete" = "deferred to v2 - requires guardrail design (protected-branch list, unmerged-branch confirmation)"
    "pr-merge"      = "deferred to v2 - requires guardrail design (merge-requires-green-CI, branch-protection list)"
    "pr-close"      = "deferred to v2 - requires guardrail design (state-change confirmation)"
    "pr-reopen"     = "deferred to v2 - requires guardrail design (state-change confirmation)"
}

# ---------------------------------------------------------------------------
# -WhatIf - resolve the plan to JSON and exit 0 without executing anything.
# ---------------------------------------------------------------------------

if ($WhatIf) {
    $cmd = $Command.ToLowerInvariant()
    if ($DestructiveCommands.ContainsKey($cmd)) {
        Write-Result @{ ok = $false; command = $cmd; status = "not_implemented"; error = $null; note = $DestructiveCommands[$cmd]; plan = @() }
        exit 0
    }
    if ($cmd -eq "help") {
        Write-Result @{ ok = $true; command = "help"; status = "ok"; error = $null; plan = @(); safeCommands = $SafeCommands; destructiveCommands = @($DestructiveCommands.Keys) }
        exit 0
    }
    if (-not ($SafeCommands -contains $cmd)) {
        Write-Result @{ ok = $false; command = $cmd; status = "unknown_command"; error = "Unknown subcommand: $cmd"; plan = @() }
        exit 0
    }
    $plan = Get-Plan $cmd
    $planList = New-Object System.Collections.ArrayList
    # PowerShell unrolls a single-element @(,@(...)) on return, leaving a flat string[]
    # for single-vector commands. Normalize: if the first element is a string, the whole
    # thing is one vector; otherwise it is already a list of vectors.
    if ($plan -and $plan.Count -gt 0 -and ($plan[0] -is [string])) {
        [void]$planList.Add([string[]]$plan)
    } else {
        foreach ($p in $plan) { [void]$planList.Add([string[]]$p) }
    }
    $envelope = [ordered]@{
        ok      = $true
        command = $cmd
        status  = "plan"
        error   = $null
        plan    = $planList
    }
    if ($cmd -eq "ci-status") {
        $ci = Get-CiConfig
        $envelope.ciEnabled = $ci.enabled
        $envelope.timeoutSeconds = if ($PSBoundParameters.ContainsKey("TimeoutSeconds")) { $TimeoutSeconds } else { $ci.waitTimeoutSeconds }
    }
    Write-Result $envelope
    exit 0
}

# ---------------------------------------------------------------------------
# Subcommand helpers (live execution). Each returns a result hashtable; each
# wraps git/gh through Invoke-Git / Invoke-Gh and surfaces failures in the
# envelope - no unhandled git/gh failure escapes.
# ---------------------------------------------------------------------------

function Cmd-Status {
    $r = Invoke-Git @("status", "--porcelain=v1", "--branch")
    if (-not (Test-ToolOk $r)) { return New-ToolError "status" "git status failed" $r }
    $lines  = @($r.stdout -split "`n" | Where-Object { $_ -ne "" })
    $branch = ""; $ahead = 0; $behind = 0; $dirty = @()
    foreach ($l in $lines) {
        if ($l.StartsWith("##")) {
            $b = $l.Substring(2).Trim()
            if ($b -match '^([^\.\s]+)') { $branch = $Matches[1] }
            if ($b -match '\[ahead (\d+)') { $ahead = [int]$Matches[1] }
            if ($b -match 'behind (\d+)')  { $behind = [int]$Matches[1] }
        } else {
            $dirty += $l
        }
    }
    return [ordered]@{
        ok = $true; command = "status"; status = "ok"; error = $null
        branch = $branch; ahead = $ahead; behind = $behind
        clean = ($dirty.Count -eq 0); dirty = $dirty
    }
}

function Cmd-Head {
    $r = Invoke-Git @("rev-parse", "HEAD")
    if (-not (Test-ToolOk $r)) { return New-ToolError "head" "git rev-parse HEAD failed" $r }
    return [ordered]@{ ok = $true; command = "head"; status = "ok"; error = $null; sha = $r.stdout.Trim() }
}

function Cmd-CurrentBranch {
    $r = Invoke-Git @("rev-parse", "--abbrev-ref", "HEAD")
    if (-not (Test-ToolOk $r)) { return New-ToolError "current-branch" "git rev-parse --abbrev-ref HEAD failed" $r }
    return [ordered]@{ ok = $true; command = "current-branch"; status = "ok"; error = $null; branch = $r.stdout.Trim() }
}

function Cmd-Log {
    $r = Invoke-Git @("log", "--oneline", "-n", "$Limit")
    if (-not (Test-ToolOk $r)) { return New-ToolError "log" "git log failed" $r }
    $commits = @($r.stdout -split "`n" | Where-Object { $_ -ne "" })
    return [ordered]@{ ok = $true; command = "log"; status = "ok"; error = $null; commits = $commits }
}

function Cmd-Push {
    $r = Invoke-Git @("push", "origin", "HEAD")
    if (-not (Test-ToolOk $r)) { return New-ToolError "push" "git push failed" $r }
    # git push reports to stderr on success; surface both for transparency.
    $detail = (($r.stderr + "`n" + $r.stdout).Trim())
    return [ordered]@{
        ok = $true; command = "push"; status = "pushed"; error = $null
        detail = $detail
    }
}

function Cmd-Fetch {
    $r = Invoke-Git @("fetch", "origin")
    if (-not (Test-ToolOk $r)) { return New-ToolError "fetch" "git fetch failed" $r }
    return [ordered]@{ ok = $true; command = "fetch"; status = "ok"; error = $null }
}

function Cmd-Pull {
    $r = Invoke-Git @("pull", "--ff-only")
    if (-not (Test-ToolOk $r)) { return New-ToolError "pull" "git pull --ff-only failed (non-fast-forward refused)" $r }
    return [ordered]@{ ok = $true; command = "pull"; status = "ok"; error = $null; detail = $r.stdout.Trim() }
}

function Cmd-BranchCreate {
    if (-not $Branch) { return [ordered]@{ ok = $false; command = "branch-create"; status = "error"; error = "-Branch is required" } }
    $r = Invoke-Git @("checkout", "-b", "$Branch")
    if (-not (Test-ToolOk $r)) { return New-ToolError "branch-create" "git checkout -b failed" $r }
    return [ordered]@{ ok = $true; command = "branch-create"; status = "ok"; error = $null; branch = $Branch }
}

function Cmd-Switch {
    if (-not $Branch) { return [ordered]@{ ok = $false; command = "switch"; status = "error"; error = "-Branch is required" } }
    $r = Invoke-Git @("checkout", "$Branch")
    if (-not (Test-ToolOk $r)) { return New-ToolError "switch" "git checkout failed (uncommitted changes would be lost?)" $r }
    return [ordered]@{ ok = $true; command = "switch"; status = "ok"; error = $null; branch = $Branch }
}

function Cmd-CiStatus {
    $ci = Get-CiConfig
    if (-not $ci.enabled) {
        return [ordered]@{ ok = $true; command = "ci-status"; status = "no_ci"; error = $null
            note = "ci.enabled is false or absent in SDP-Config.json - local-green fallback with disclosed caveat." }
    }

    # Auth/reachability precondition - drives the unreachable fallback.
    $auth = Invoke-Gh @("auth", "status")
    if (-not (Test-ToolOk $auth)) {
        return [ordered]@{ ok = $true; command = "ci-status"; status = "unreachable"; error = $null
            note = "gh auth status failed - remote CI unreachable; completion falls back to local-green with a disclosed caveat."
            stderr = ($auth.stderr).Trim() }
    }

    $headR = Invoke-Git @("rev-parse", "HEAD")
    if (-not (Test-ToolOk $headR)) { return New-ToolError "ci-status" "git rev-parse HEAD failed" $headR }
    $head = $headR.stdout.Trim()

    $timeout = if ($PSBoundParameters.ContainsKey("TimeoutSeconds")) { $TimeoutSeconds } else { $ci.waitTimeoutSeconds }
    if ($timeout -le 0) { $timeout = 600 }
    $deadline = (Get-Date).AddSeconds($timeout)

    # Poll until a run for HEAD appears (closes the push race), then watch it.
    $runId = $null; $url = $null
    while ((Get-Date) -lt $deadline) {
        $list = Invoke-Gh @("run", "list", "--commit", $head, "--limit", "1", "--json", "databaseId,status,conclusion,url")
        if (-not (Test-ToolOk $list)) {
            return [ordered]@{ ok = $true; command = "ci-status"; status = "unreachable"; error = $null
                note = "gh run list failed - remote CI unreachable."; stderr = ($list.stderr).Trim() }
        }
        $runs = @()
        try { $runs = @($list.stdout | ConvertFrom-Json) } catch { $runs = @() }
        if ($runs.Count -gt 0) {
            $runId = $runs[0].databaseId
            $url   = $runs[0].url
            break
        }
        Start-Sleep -Seconds 5
    }

    if ($null -eq $runId) {
        return [ordered]@{ ok = $true; command = "ci-status"; status = "timeout"; error = $null
            sha = $head; note = "No CI run appeared for HEAD within ${timeout}s - routed to the Halt Behavior Contract." }
    }

    # Watch the run to completion (bounded by remaining time via gh's own behavior).
    $watch = Invoke-Gh @("run", "watch", "$runId", "--exit-status")
    # gh run watch --exit-status: exit 0 => success (green); non-zero => the run concluded
    # with a non-success conclusion (red) OR the watch itself failed. Disambiguate by
    # re-reading the run's conclusion.
    $view = Invoke-Gh @("run", "view", "$runId", "--json", "status,conclusion,url")
    $conclusion = $null; $rstatus = $null
    if (Test-ToolOk $view) {
        try {
            $vj = $view.stdout | ConvertFrom-Json
            $conclusion = "$($vj.conclusion)"
            $rstatus    = "$($vj.status)"
            if ($vj.url) { $url = $vj.url }
        } catch { }
    }

    if ($conclusion -eq "success") {
        return [ordered]@{ ok = $true; command = "ci-status"; status = "green"; error = $null
            runId = $runId; url = $url; failedJobs = @() }
    }
    if ($conclusion -and $conclusion -ne "success") {
        # Gather failed-job names for the red envelope (best-effort, non-fatal).
        $failed = @()
        $jobs = Invoke-Gh @("run", "view", "$runId", "--json", "jobs")
        if (Test-ToolOk $jobs) {
            try {
                $jj = $jobs.stdout | ConvertFrom-Json
                $failed = @($jj.jobs | Where-Object { $_.conclusion -and $_.conclusion -ne "success" } | ForEach-Object { $_.name })
            } catch { }
        }
        return [ordered]@{ ok = $true; command = "ci-status"; status = "red"; error = $null
            runId = $runId; url = $url; conclusion = $conclusion; failedJobs = $failed }
    }

    # Could not determine a conclusion (watch failed and view inconclusive).
    if (-not (Test-ToolOk $watch)) {
        return [ordered]@{ ok = $true; command = "ci-status"; status = "unreachable"; error = $null
            runId = $runId; url = $url; note = "gh run watch failed and conclusion could not be read."
            stderr = ($watch.stderr).Trim() }
    }
    return [ordered]@{ ok = $true; command = "ci-status"; status = "timeout"; error = $null
        runId = $runId; url = $url; note = "Run did not reach a terminal conclusion." }
}

function Cmd-RunList {
    $r = Invoke-Gh @("run", "list", "--limit", "$Limit", "--json", "databaseId,status,conclusion,headBranch,workflowName,url")
    if (-not (Test-ToolOk $r)) { return New-ToolError "run-list" "gh run list failed" $r }
    $runs = @()
    try { $runs = @($r.stdout | ConvertFrom-Json) } catch { }
    return [ordered]@{ ok = $true; command = "run-list"; status = "ok"; error = $null; runs = $runs }
}

function Cmd-RunLogFailed {
    if ($RunId -le 0) { return [ordered]@{ ok = $false; command = "run-log-failed"; status = "error"; error = "-RunId is required" } }
    $r = Invoke-Gh @("run", "view", "$RunId", "--log-failed")
    if (-not (Test-ToolOk $r)) { return New-ToolError "run-log-failed" "gh run view --log-failed failed" $r }
    $log = $r.stdout
    $max = 8000
    $truncated = $false
    if ($log.Length -gt $max) { $log = $log.Substring(0, $max); $truncated = $true }
    return [ordered]@{ ok = $true; command = "run-log-failed"; status = "ok"; error = $null
        runId = $RunId; log = $log; truncated = $truncated }
}

function Cmd-PrCreate {
    if (-not $Title) { return [ordered]@{ ok = $false; command = "pr-create"; status = "error"; error = "-Title is required" } }
    $a = @("pr", "create", "--title", "$Title", "--body", "$Body")
    if ($Base) { $a += @("--base", "$Base") }
    $r = Invoke-Gh $a
    if (-not (Test-ToolOk $r)) { return New-ToolError "pr-create" "gh pr create failed" $r }
    return [ordered]@{ ok = $true; command = "pr-create"; status = "created"; error = $null; url = $r.stdout.Trim() }
}

function Cmd-PrView([string]$name) {
    $a = @("pr", "view")
    if ($Number -gt 0) { $a += "$Number" }
    $a += @("--json", "number,title,state,headRefName,url,statusCheckRollup")
    $r = Invoke-Gh $a
    if (-not (Test-ToolOk $r)) { return New-ToolError $name "gh pr view failed" $r }
    $pr = $null
    try { $pr = $r.stdout | ConvertFrom-Json } catch { }
    return [ordered]@{ ok = $true; command = $name; status = "ok"; error = $null
        prNumber = $(if ($pr) { $pr.number } else { $null })
        state    = $(if ($pr) { $pr.state } else { $null })
        url      = $(if ($pr) { $pr.url } else { $null })
        pr       = $pr }
}

function Cmd-PrList {
    $r = Invoke-Gh @("pr", "list", "--limit", "$Limit", "--json", "number,title,headRefName,state,url")
    if (-not (Test-ToolOk $r)) { return New-ToolError "pr-list" "gh pr list failed" $r }
    $prs = @()
    try { $prs = @($r.stdout | ConvertFrom-Json) } catch { }
    return [ordered]@{ ok = $true; command = "pr-list"; status = "ok"; error = $null; prs = $prs }
}

function Cmd-PrChecks {
    $a = @("pr", "checks")
    if ($Number -gt 0) { $a += "$Number" }
    $r = Invoke-Gh $a
    # gh pr checks exits non-zero when checks are failing/pending - that is a successful
    # observation, not a script error. Surface the rollup either way.
    return [ordered]@{ ok = $true; command = "pr-checks"; status = "ok"; error = $null
        rollup = $r.stdout.Trim(); allPassing = (Test-ToolOk $r) }
}

function Cmd-AuthStatus {
    $r = Invoke-Gh @("auth", "status")
    $authed = Test-ToolOk $r
    return [ordered]@{ ok = $true; command = "auth-status"; status = $(if ($authed) { "authenticated" } else { "unreachable" })
        error = $null; detail = (($r.stdout + "`n" + $r.stderr).Trim()) }
}

function Cmd-RepoView {
    $r = Invoke-Gh @("repo", "view", "--json", "name,defaultBranchRef,url,nameWithOwner")
    if (-not (Test-ToolOk $r)) { return New-ToolError "repo-view" "gh repo view failed" $r }
    $repo = $null
    try { $repo = $r.stdout | ConvertFrom-Json } catch { }
    return [ordered]@{ ok = $true; command = "repo-view"; status = "ok"; error = $null
        defaultBranch = $(if ($repo -and $repo.defaultBranchRef) { $repo.defaultBranchRef.name } else { $null })
        url           = $(if ($repo) { $repo.url } else { $null })
        nameWithOwner = $(if ($repo) { $repo.nameWithOwner } else { $null }) }
}

function Cmd-Help {
    return [ordered]@{
        ok = $true; command = "help"; status = "ok"; error = $null
        safeCommands = $SafeCommands
        destructiveCommands = @($DestructiveCommands.Keys)
        note = "Run a subcommand as the first positional argument. Use -WhatIf to resolve the plan without executing."
    }
}

# ---------------------------------------------------------------------------
# Dispatch - single switch. Every path emits the envelope; the script never
# lets a git/gh error escape uncaught. Exit 1 only on operational error.
# ---------------------------------------------------------------------------

$cmd = $Command.ToLowerInvariant()

# Destructive tier - recognized, not implemented, performs no action.
if ($DestructiveCommands.ContainsKey($cmd)) {
    Write-Result @{ ok = $false; command = $cmd; status = "not_implemented"; error = $null; note = $DestructiveCommands[$cmd] }
    exit 0
}

$result = $null
try {
    $result = switch ($cmd) {
        "status"         { Cmd-Status }
        "head"           { Cmd-Head }
        "current-branch" { Cmd-CurrentBranch }
        "log"            { Cmd-Log }
        "push"           { Cmd-Push }
        "fetch"          { Cmd-Fetch }
        "pull"           { Cmd-Pull }
        "branch-create"  { Cmd-BranchCreate }
        "switch"         { Cmd-Switch }
        "ci-status"      { Cmd-CiStatus }
        "run-list"       { Cmd-RunList }
        "run-log-failed" { Cmd-RunLogFailed }
        "pr-create"      { Cmd-PrCreate }
        "pr-status"      { Cmd-PrView "pr-status" }
        "pr-view"        { Cmd-PrView "pr-view" }
        "pr-list"        { Cmd-PrList }
        "pr-checks"      { Cmd-PrChecks }
        "auth-status"    { Cmd-AuthStatus }
        "repo-view"      { Cmd-RepoView }
        "help"           { Cmd-Help }
        default {
            [ordered]@{ ok = $false; command = $cmd; status = "unknown_command"; error = "Unknown subcommand: $cmd. Run 'help' for the catalog." }
        }
    }
} catch {
    # Last-resort guard - no git/gh error should reach here, but a bug in a helper
    # must still surface as a clean error envelope rather than an unhandled exception.
    Write-Result @{ ok = $false; command = $cmd; status = "error"; error = "Unhandled script error: $($_.Exception.Message)" }
    exit 1
}

Write-Result $result

# Exit contract: 0 whenever the script ran correctly (including red CI and not_implemented);
# 1 only on an operational/script error (ok:false with status "error" or "unknown_command").
if ($result.ok -eq $false -and ($result.status -eq "error" -or $result.status -eq "unknown_command")) {
    exit 1
}
exit 0
