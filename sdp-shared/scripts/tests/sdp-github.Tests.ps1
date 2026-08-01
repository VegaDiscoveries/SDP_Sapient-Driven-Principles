#Requires -Module Pester

<#
.SYNOPSIS
    Pester unit tests for sdp-github.ps1

.NOTES
    Run from workspace root:
        Invoke-Pester sdp-shared/scripts/tests/sdp-github.Tests.ps1 -Output Detailed

    Strategy:
    - -WhatIf plan assertions are the primary deterministic hook: they resolve the intended
      git/gh invocation per subcommand without executing anything.
    - The ci block (disabled/absent) path is tested by pointing -workspaceRoot at a temp
      workspace with a controlled SDP-Config.json.
    - Error-capture / unreachable / auth paths shadow git and gh with shim .cmd files placed
      on a temp dir that is prepended to PATH for the invocation. The shims return a chosen
      exit code so we can assert the script captures the failure in the envelope and never
      throws an unhandled exception.
#>

Describe "sdp-github.ps1" {

    BeforeAll {
        $script:scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) "sdp-github.ps1"
        $script:pwshExe    = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName

        function New-TestWorkspace {
            $root = Join-Path ([System.IO.Path]::GetTempPath()) "sdp-gh-test-$(New-Guid)"
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            return $root
        }

        function Write-CiConfig([string]$root, $ciBlock) {
            $obj = @{ schema_version = "1.0" }
            if ($null -ne $ciBlock) { $obj.ci = $ciBlock }
            $obj | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $root "SDP-Config.json") -Encoding UTF8
        }

        function Remove-TestWorkspace([string]$root) {
            if ($root -and (Test-Path $root)) { Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue }
        }

        # Invoke the script in a child PowerShell via -File. Optional $shimDir is prepended to
        # the child's PATH (the child inherits the parent process environment) so shadowed
        # git/gh shims take precedence over the real tools. PATH is restored afterward.
        function Invoke-Script([string[]]$arguments, [string]$shimDir = "") {
            $savedPath = $env:PATH
            try {
                if ($shimDir) { $env:PATH = "$shimDir$([System.IO.Path]::PathSeparator)$env:PATH" }
                $output = & $script:pwshExe -NoProfile -NonInteractive -File $script:scriptPath @arguments 2>&1
                $exitCode = $LASTEXITCODE
            } finally {
                $env:PATH = $savedPath
            }
            $stdout = ($output | Where-Object { $_ -is [string] }) -join "`n"
            $result = $null
            # The envelope is the last JSON line emitted.
            $jsonLine = ($stdout -split "`n" | Where-Object { $_.Trim().StartsWith("{") } | Select-Object -Last 1)
            try { $result = $jsonLine | ConvertFrom-Json } catch { }
            return @{ ExitCode = $exitCode; Stdout = $stdout; Result = $result }
        }

        # Build a shim directory with git.cmd / gh.cmd that echo a chosen line to the chosen
        # stream and exit with a chosen code.
        function New-ShimDir([hashtable]$shims) {
            # $shims: @{ git = @{ exit = 1; stdout = ""; stderr = "boom" }; gh = @{...} }
            $dir = Join-Path ([System.IO.Path]::GetTempPath()) "sdp-gh-shim-$(New-Guid)"
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $isWin = $IsWindows -ne $false
            foreach ($name in $shims.Keys) {
                $cfg = $shims[$name]
                $exitCode = if ($null -ne $cfg.exit) { $cfg.exit } else { 0 }
                if ($isWin) {
                    $lines = @("@echo off")
                    if ($cfg.stdout) { $lines += "echo $($cfg.stdout)" }
                    if ($cfg.stderr) { $lines += "echo $($cfg.stderr) 1>&2" }
                    $lines += "exit /b $exitCode"
                    ($lines -join "`r`n") | Set-Content (Join-Path $dir "$name.cmd") -Encoding ASCII
                } else {
                    $lines = @("#!/bin/sh")
                    if ($cfg.stdout) { $lines += "printf '%s\n' '$($cfg.stdout)'" }
                    if ($cfg.stderr) { $lines += "printf '%s\n' '$($cfg.stderr)' >&2" }
                    $lines += "exit $exitCode"
                    $shimPath = Join-Path $dir $name
                    ($lines -join "`n") | Set-Content $shimPath -Encoding UTF8
                    & chmod +x $shimPath
                }
            }
            return $dir
        }
    }

    # -----------------------------------------------------------------------
    # -WhatIf plan mode — the deterministic hook. No git/gh execution.
    # -----------------------------------------------------------------------
    Context "-WhatIf plan mode" {

        It "push plan resolves to a single git push origin HEAD vector" {
            $run = Invoke-Script @("push", "-WhatIf")
            $run.ExitCode | Should -Be 0
            $run.Result.status | Should -Be "plan"
            $run.Result.command | Should -Be "push"
            # plan is a list with one vector; join its elements to assert content
            ($run.Result.plan[0] -join " ") | Should -Be "git push origin HEAD"
        }

        It "status plan resolves to git status porcelain" {
            $run = Invoke-Script @("status", "-WhatIf")
            ($run.Result.plan[0] -join " ") | Should -Match "git status"
        }

        It "ci-status plan resolves to the three-step gate (rev-parse, run list, run watch)" {
            $run = Invoke-Script @("ci-status", "-WhatIf")
            $run.Result.status | Should -Be "plan"
            $run.Result.plan.Count | Should -Be 3
            ($run.Result.plan[0] -join " ") | Should -Match "rev-parse HEAD"
            ($run.Result.plan[1] -join " ") | Should -Match "run list"
            ($run.Result.plan[2] -join " ") | Should -Match "run watch"
        }

        It "pr-create plan includes --base when -Base is supplied" {
            $run = Invoke-Script @("pr-create", "-Title", "T", "-Body", "B", "-Base", "main", "-WhatIf")
            ($run.Result.plan[0] -join " ") | Should -Match "--base main"
        }

        It "unknown subcommand under -WhatIf reports unknown_command (exit 0, no execution)" {
            $run = Invoke-Script @("bogus", "-WhatIf")
            $run.ExitCode | Should -Be 0
            $run.Result.status | Should -Be "unknown_command"
        }
    }

    # -----------------------------------------------------------------------
    # Envelope shape — required keys; error null on success.
    # -----------------------------------------------------------------------
    Context "Envelope shape" {

        It "help emits ok/command/status/error keys with error null" {
            $run = Invoke-Script @("help")
            $run.ExitCode | Should -Be 0
            $run.Result.ok | Should -Be $true
            $run.Result.command | Should -Be "help"
            $run.Result.status | Should -Be "ok"
            $run.Result.error | Should -BeNullOrEmpty
        }

        It "help lists the v1 safe subcommands and the destructive tier names" {
            $run = Invoke-Script @("help")
            $run.Result.safeCommands | Should -Contain "ci-status"
            $run.Result.safeCommands | Should -Contain "push"
            $run.Result.destructiveCommands | Should -Contain "pr-merge"
        }
    }

    # -----------------------------------------------------------------------
    # ci block disabled / absent -> ci-status returns no_ci.
    # -----------------------------------------------------------------------
    Context "ci-status with ci block disabled or absent" {

        It "ci.enabled false -> no_ci, exit 0" {
            $ws = New-TestWorkspace
            try {
                Write-CiConfig $ws @{ enabled = $false; provider = "github-actions"; waitTimeoutSeconds = 600 }
                $run = Invoke-Script @("ci-status", "-workspaceRoot", $ws)
                $run.ExitCode | Should -Be 0
                $run.Result.status | Should -Be "no_ci"
                $run.Result.error | Should -BeNullOrEmpty
            } finally { Remove-TestWorkspace $ws }
        }

        It "ci block absent -> no_ci, exit 0" {
            $ws = New-TestWorkspace
            try {
                Write-CiConfig $ws $null
                $run = Invoke-Script @("ci-status", "-workspaceRoot", $ws)
                $run.ExitCode | Should -Be 0
                $run.Result.status | Should -Be "no_ci"
            } finally { Remove-TestWorkspace $ws }
        }

        It "ci-status -WhatIf reports ciEnabled false when disabled" {
            $ws = New-TestWorkspace
            try {
                Write-CiConfig $ws @{ enabled = $false }
                $run = Invoke-Script @("ci-status", "-workspaceRoot", $ws, "-WhatIf")
                $run.Result.ciEnabled | Should -Be $false
            } finally { Remove-TestWorkspace $ws }
        }
    }

    # -----------------------------------------------------------------------
    # Destructive tier — not_implemented sentinel, no action, exit 0.
    # -----------------------------------------------------------------------
    Context "Destructive tier sentinels" {

        It "pr-merge returns not_implemented and performs no action (exit 0)" {
            $run = Invoke-Script @("pr-merge")
            $run.ExitCode | Should -Be 0
            $run.Result.ok | Should -Be $false
            $run.Result.status | Should -Be "not_implemented"
            $run.Result.error | Should -BeNullOrEmpty
            $run.Result.note | Should -Not -BeNullOrEmpty
        }

        It "push-force returns not_implemented" {
            $run = Invoke-Script @("push-force")
            $run.Result.status | Should -Be "not_implemented"
        }

        It "branch-delete returns not_implemented" {
            $run = Invoke-Script @("branch-delete")
            $run.Result.status | Should -Be "not_implemented"
        }
    }

    # -----------------------------------------------------------------------
    # Error capture — shadowed git/gh returning non-zero produces a clean
    # error envelope (ok:false, status:error, populated error/stderr/exitCode)
    # and NO thrown exception.
    # -----------------------------------------------------------------------
    Context "Error capture via shadowed git/gh" {

        It "shadowed git exit 1 on 'head' -> ok:false status:error exitCode:1, exit 1" {
            $shim = New-ShimDir @{ git = @{ exit = 1; stderr = "fatal: boom" } }
            try {
                $run = Invoke-Script @("head") $shim
                $run.Result.ok | Should -Be $false
                $run.Result.status | Should -Be "error"
                $run.Result.error | Should -Not -BeNullOrEmpty
                $run.Result.exitCode | Should -Be 1
                $run.Result.stderr | Should -Match "boom"
                $run.ExitCode | Should -Be 1
            } finally { Remove-TestWorkspace $shim }
        }

        It "no thrown exception leaks to stdout (envelope is valid JSON)" {
            $shim = New-ShimDir @{ git = @{ exit = 1; stderr = "fatal: boom" } }
            try {
                $run = Invoke-Script @("status") $shim
                # Result parsed from a clean JSON line means no raw exception text broke it.
                $run.Result | Should -Not -BeNullOrEmpty
                $run.Result.status | Should -Be "error"
            } finally { Remove-TestWorkspace $shim }
        }

        It "shadowed gh auth failure on ci-status -> unreachable (exit 0)" {
            $ws = New-TestWorkspace
            $shim = New-ShimDir @{ gh = @{ exit = 1; stderr = "not logged in" } }
            try {
                Write-CiConfig $ws @{ enabled = $true; provider = "github-actions"; waitTimeoutSeconds = 600 }
                $run = Invoke-Script @("ci-status", "-workspaceRoot", $ws) $shim
                $run.ExitCode | Should -Be 0
                $run.Result.status | Should -Be "unreachable"
                $run.Result.error | Should -BeNullOrEmpty
            } finally { Remove-TestWorkspace $ws; Remove-TestWorkspace $shim }
        }
    }
}
