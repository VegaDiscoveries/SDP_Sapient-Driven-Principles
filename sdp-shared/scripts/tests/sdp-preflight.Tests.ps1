#Requires -Module Pester

<#
.SYNOPSIS
    Pester unit tests for sdp-preflight.ps1 (Pester 5+).

.NOTES
    Run from workspace root (import v5 explicitly so the built-in 3.4 is not auto-loaded):
        Import-Module Pester -MinimumVersion 5.0 -Force
        Invoke-Pester -Path sdp-shared/scripts/tests/sdp-preflight.Tests.ps1 -Output Detailed

    Strategy:
    - Each test builds a self-contained temp workspace (manifest + optional SDP-Config.json +
      optional .sdp-workflow/state.json + the target files a check expects) and points the
      script at it with -workspaceRoot. This isolates the engine from the real repo.
    - The script is invoked in a child PowerShell via -File so exit codes and the single JSON
      stdout line are observed exactly as a skill would observe them.
    - -WhatIf is the deterministic plan hook: it resolves checks + the due-tier decision without
      reading targets or writing.
#>

Describe "sdp-preflight.ps1" {

    BeforeAll {
        $script:scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) "sdp-preflight.ps1"
        $script:pwshExe    = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName

        function Resolve-TestPath([string]$root, [string]$relative) {
            $parts = $relative -split '[/\\]' | Where-Object { $_ -ne '' }
            $result = $root
            foreach ($p in $parts) { $result = Join-Path $result $p }
            return $result
        }

        function New-TestWorkspace {
            # Every real single-project SDP workspace has a real SDP-Solution.json with
            # last_active_projects: ["."] (Solution Root Setup is mandatory) - so a minimal
            # solution marker is written here by default, keeping every existing test's
            # resolution behavior (-> SDP-Workspace-Setup.json) unchanged under the new
            # manifest-scope-resolution logic. A workspace with truly neither marker is a
            # deliberate, separately-tested edge case (Remove-Item this file after the fact).
            $root = Join-Path ([System.IO.Path]::GetTempPath()) "sdp-pf-test-$(New-Guid)"
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            '{ "schema_version": "1.0", "last_active_projects": ["."] }' |
                Set-Content (Join-Path $root "SDP-Solution.json") -Encoding UTF8
            return $root
        }

        function New-TestProjectWorkspace([string]$projectName = "sdp-project_Foo") {
            # Builds a nested sdp-project_* workspace path under a temp root, since
            # Resolve-ManifestFilename's project-segment check inspects -workspaceRoot itself,
            # not a parent. Returns @{ Root = <project subfolder>; Parent = <temp root to
            # remove on cleanup> } - the temp GUID parent, not the project subfolder itself,
            # is what Remove-TestWorkspace should be given so the whole tree is cleaned up.
            $parent = Join-Path ([System.IO.Path]::GetTempPath()) "sdp-pf-test-$(New-Guid)"
            $projectRoot = Join-Path $parent $projectName
            New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null
            return @{ Root = $projectRoot; Parent = $parent }
        }

        function Remove-TestWorkspace([string]$root) {
            if ($root -and (Test-Path $root)) { Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue }
        }

        function Write-SolutionMarker([string]$root, [string[]]$lastActiveProjects) {
            $obj = [ordered]@{ schema_version = "1.0"; last_active_projects = @($lastActiveProjects) }
            $obj | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $root "SDP-Solution.json") -Encoding UTF8
        }

        function Write-Manifest([string]$root, $checks, [string]$filename = "SDP-Workspace-Setup.json") {
            # Serialize as a JSON array regardless of element count. PowerShell's pipeline
            # unrolls single-element arrays (yielding a JSON object, not an array), so build
            # the array text explicitly: one object per check, comma-joined, wrapped in [].
            $items = @(@($checks) | ForEach-Object { $_ | ConvertTo-Json -Depth 6 -Compress })
            "[`n$($items -join ",`n")`n]" | Set-Content (Join-Path $root $filename) -Encoding UTF8
        }

        function Write-Config([string]$root, $preflightBlock) {
            $obj = @{ schema_version = "1.0" }
            if ($null -ne $preflightBlock) { $obj.preflight = $preflightBlock }
            $obj | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $root "SDP-Config.json") -Encoding UTF8
        }

        function Write-State([string]$root, $stateObj) {
            $dir = Join-Path $root ".sdp-workflow"
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $stateObj | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $dir "state.json") -Encoding UTF8
        }

        function New-File([string]$root, [string]$relative, [string]$content = "x") {
            $full = Resolve-TestPath $root $relative
            $dir = Split-Path -Parent $full
            if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            Set-Content -LiteralPath $full -Value $content -Encoding UTF8
        }

        function Invoke-Script([string[]]$arguments) {
            $output = & $script:pwshExe -NoProfile -NonInteractive -File $script:scriptPath @arguments 2>&1
            $exitCode = $LASTEXITCODE
            $stdout = ($output | Where-Object { $_ -is [string] }) -join "`n"
            $jsonLine = ($stdout -split "`n" | Where-Object { $_.Trim().StartsWith("{") } | Select-Object -Last 1)
            $result = $null
            try { $result = $jsonLine | ConvertFrom-Json } catch { }
            return @{ ExitCode = $exitCode; Stdout = $stdout; Result = $result }
        }
    }

    # -----------------------------------------------------------------------
    # -WhatIf plan mode — checks + due-tier decision, no target reads, no writes.
    # -----------------------------------------------------------------------
    Context "-WhatIf plan mode" {

        It "resolves the planned checks and marks both tiers due on a fresh workspace" {
            $ws = New-TestWorkspace
            try {
                Write-Manifest $ws @(
                    @{ type = "file-exists"; path = "A.txt"; tier = "integrity" },
                    @{ type = "dir-exists";  path = "sub";   tier = "setup" }
                )
                $run = Invoke-Script @("-workspaceRoot", $ws, "-WhatIf")
                $run.ExitCode | Should -Be 0
                $run.Result.whatIf | Should -Be $true
                $run.Result.checks.Count | Should -Be 2
                $run.Result.tiersRun | Should -Contain "integrity"
                $run.Result.tiersRun | Should -Contain "setup"
                # No target files exist, but -WhatIf must not evaluate them.
                $run.Result.failures.Count | Should -Be 0
            } finally { Remove-TestWorkspace $ws }
        }

        It "does not write a timestamp to state.json under -WhatIf" {
            $ws = New-TestWorkspace
            try {
                Write-Manifest $ws @( @{ type = "file-exists"; path = "A.txt"; tier = "setup" } )
                New-File $ws "A.txt"
                Write-State $ws @{ project = "T"; preflight = @{} }
                Invoke-Script @("-workspaceRoot", $ws, "-WhatIf") | Out-Null
                $state = Get-Content (Resolve-TestPath $ws ".sdp-workflow/state.json") -Raw | ConvertFrom-Json
                $state.preflight.PSObject.Properties.Name | Should -Not -Contain "last_setup_validation"
            } finally { Remove-TestWorkspace $ws }
        }
    }

    # -----------------------------------------------------------------------
    # Per-type validators — a passing case and a failing case each.
    # -----------------------------------------------------------------------
    Context "Check type validators" {

        It "file-exists passes when present, fails when missing" {
            $ws = New-TestWorkspace
            try {
                Write-Manifest $ws @( @{ type = "file-exists"; path = "present.txt"; tier = "integrity" } )
                New-File $ws "present.txt"
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.Result.ok | Should -Be $true

                Write-Manifest $ws @( @{ type = "file-exists"; path = "gone.txt"; tier = "integrity" } )
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.Result.ok | Should -Be $false
                $run.Result.failures | Should -Contain "file-exists:gone.txt"
            } finally { Remove-TestWorkspace $ws }
        }

        It "file-absent passes when missing, fails when present (inverted logic)" {
            $ws = New-TestWorkspace
            try {
                Write-Manifest $ws @( @{ type = "file-absent"; path = "shouldnotbe.txt"; tier = "integrity" } )
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.Result.ok | Should -Be $true

                New-File $ws "shouldnotbe.txt"
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.Result.ok | Should -Be $false
                $run.Result.failures | Should -Contain "file-absent:shouldnotbe.txt"
            } finally { Remove-TestWorkspace $ws }
        }

        It "dir-exists passes for a directory, fails when absent" {
            $ws = New-TestWorkspace
            try {
                Write-Manifest $ws @( @{ type = "dir-exists"; path = "somedir"; tier = "setup" } )
                New-Item -ItemType Directory -Path (Join-Path $ws "somedir") -Force | Out-Null
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.Result.ok | Should -Be $true

                Write-Manifest $ws @( @{ type = "dir-exists"; path = "nodir"; tier = "setup" } )
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.Result.ok | Should -Be $false
            } finally { Remove-TestWorkspace $ws }
        }

        It "skill-pair passes only when BOTH levels exist" {
            $ws = New-TestWorkspace
            try {
                Write-Manifest $ws @( @{ type = "skill-pair"; name = "sdp-demo"; tier = "integrity" } )
                New-File $ws ".claude/skills/sdp-demo/SKILL.md"
                # Only L1 present -> fail
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.Result.ok | Should -Be $false
                $run.Result.failures | Should -Contain "skill-pair:sdp-demo"
                # Add L2 -> pass
                New-File $ws "sdp-shared/ai-skills/sdp-demo/SKILL.md"
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.Result.ok | Should -Be $true
            } finally { Remove-TestWorkspace $ws }
        }

        It "json-value with filename: pattern passes when the derived file exists" {
            $ws = New-TestWorkspace
            try {
                Write-Manifest $ws @(
                    @{ type = "json-value"; file = ".sdp-workflow/state.json"; pointer = "gpg_version";
                       match = "filename:standards/GenericProjectGuidlines_{}.md"; tier = "integrity" }
                )
                Write-State $ws @{ project = "T"; gpg_version = "V1.10_20260323" }
                # No derived file yet -> fail
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.Result.ok | Should -Be $false
                # Create the derived file -> pass
                New-File $ws "standards/GenericProjectGuidlines_V1.10_20260323.md"
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.Result.ok | Should -Be $true
            } finally { Remove-TestWorkspace $ws }
        }

        It "json-value with a literal match compares the value" {
            $ws = New-TestWorkspace
            try {
                Write-Manifest $ws @(
                    @{ type = "json-value"; file = "data.json"; pointer = "schema_version";
                       match = "1.0"; tier = "setup" }
                )
                New-File $ws "data.json" '{ "schema_version": "1.0" }'
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.Result.ok | Should -Be $true

                New-File $ws "data.json" '{ "schema_version": "2.0" }'
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.Result.ok | Should -Be $false
            } finally { Remove-TestWorkspace $ws }
        }

        It "json-last-include passes when path is the last include:true entry, fails otherwise (ordering)" {
            $ws = New-TestWorkspace
            try {
                Write-Manifest $ws @(
                    @{ type = "json-last-include"; file = "doclist.json"; path = "sdp-docs/00_prompt.txt"; tier = "setup" }
                )
                # Correct ordering: prompt is the last include:true entry
                New-File $ws "doclist.json" (@(
                    @{ path = "a.md";                 includeInReadDocs = $true },
                    @{ path = "sdp-docs/00_prompt.txt"; includeInReadDocs = $true },
                    @{ path = "b.md";                 includeInReadDocs = $false }
                ) | ConvertTo-Json -Depth 4)
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.Result.ok | Should -Be $true

                # Wrong ordering: another include:true entry follows the prompt
                New-File $ws "doclist.json" (@(
                    @{ path = "sdp-docs/00_prompt.txt"; includeInReadDocs = $true },
                    @{ path = "late.md";              includeInReadDocs = $true }
                ) | ConvertTo-Json -Depth 4)
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.Result.ok | Should -Be $false
            } finally { Remove-TestWorkspace $ws }
        }
    }

    # -----------------------------------------------------------------------
    # Tier staleness gate.
    # -----------------------------------------------------------------------
    Context "Tier staleness gate" {

        It "a fresh workspace (no state timestamp) runs the tier" {
            $ws = New-TestWorkspace
            try {
                Write-Manifest $ws @( @{ type = "file-exists"; path = "A.txt"; tier = "integrity" } )
                New-File $ws "A.txt"
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.Result.tiersRun | Should -Contain "integrity"
            } finally { Remove-TestWorkspace $ws }
        }

        It "a fresh timestamp within the interval skips the tier" {
            $ws = New-TestWorkspace
            try {
                Write-Manifest $ws @( @{ type = "file-exists"; path = "A.txt"; tier = "integrity" } )
                New-File $ws "A.txt"
                Write-Config $ws @{ integrityValidationIntervalHours = 1; setupValidationIntervalHours = 24 }
                $recent = (Get-Date).AddMinutes(-5).ToString("yyyy-MM-ddTHH:mm:ss")
                Write-State $ws @{ project = "T"; preflight = @{ last_integrity_validation = $recent } }
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.Result.tiersSkipped | Should -Contain "integrity"
                $run.Result.tiersRun | Should -Not -Contain "integrity"
            } finally { Remove-TestWorkspace $ws }
        }

        It "a stale timestamp past the interval runs the tier" {
            $ws = New-TestWorkspace
            try {
                Write-Manifest $ws @( @{ type = "file-exists"; path = "A.txt"; tier = "integrity" } )
                New-File $ws "A.txt"
                Write-Config $ws @{ integrityValidationIntervalHours = 1 }
                $old = (Get-Date).AddHours(-3).ToString("yyyy-MM-ddTHH:mm:ss")
                Write-State $ws @{ project = "T"; preflight = @{ last_integrity_validation = $old } }
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.Result.tiersRun | Should -Contain "integrity"
            } finally { Remove-TestWorkspace $ws }
        }

        It "-Force runs a tier even with a fresh timestamp" {
            $ws = New-TestWorkspace
            try {
                Write-Manifest $ws @( @{ type = "file-exists"; path = "A.txt"; tier = "integrity" } )
                New-File $ws "A.txt"
                Write-Config $ws @{ integrityValidationIntervalHours = 1 }
                $recent = (Get-Date).AddMinutes(-5).ToString("yyyy-MM-ddTHH:mm:ss")
                Write-State $ws @{ project = "T"; preflight = @{ last_integrity_validation = $recent } }
                $run = Invoke-Script @("-workspaceRoot", $ws, "-Force")
                $run.Result.tiersRun | Should -Contain "integrity"
            } finally { Remove-TestWorkspace $ws }
        }

        It "interval 0 always runs the tier regardless of a fresh timestamp" {
            $ws = New-TestWorkspace
            try {
                Write-Manifest $ws @( @{ type = "file-exists"; path = "A.txt"; tier = "integrity" } )
                New-File $ws "A.txt"
                Write-Config $ws @{ integrityValidationIntervalHours = 0 }
                $recent = (Get-Date).AddMinutes(-1).ToString("yyyy-MM-ddTHH:mm:ss")
                Write-State $ws @{ project = "T"; preflight = @{ last_integrity_validation = $recent } }
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.Result.tiersRun | Should -Contain "integrity"
            } finally { Remove-TestWorkspace $ws }
        }
    }

    # -----------------------------------------------------------------------
    # Timestamp write-back.
    # -----------------------------------------------------------------------
    Context "Timestamp write-back" {

        It "advances the tier timestamp on a clean pass" {
            $ws = New-TestWorkspace
            try {
                Write-Manifest $ws @( @{ type = "file-exists"; path = "A.txt"; tier = "integrity" } )
                New-File $ws "A.txt"
                Write-State $ws @{ project = "T"; preflight = @{} }
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.Result.ok | Should -Be $true
                $state = Get-Content (Resolve-TestPath $ws ".sdp-workflow/state.json") -Raw | ConvertFrom-Json
                $state.preflight.last_integrity_validation | Should -Not -BeNullOrEmpty
            } finally { Remove-TestWorkspace $ws }
        }

        It "leaves the tier timestamp unchanged when the tier has a failure" {
            $ws = New-TestWorkspace
            try {
                Write-Manifest $ws @( @{ type = "file-exists"; path = "missing.txt"; tier = "integrity" } )
                Write-State $ws @{ project = "T"; preflight = @{} }
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.Result.ok | Should -Be $false
                $state = Get-Content (Resolve-TestPath $ws ".sdp-workflow/state.json") -Raw | ConvertFrom-Json
                $state.preflight.PSObject.Properties.Name | Should -Not -Contain "last_integrity_validation"
            } finally { Remove-TestWorkspace $ws }
        }

        It "preserves other state.json content when writing the timestamp" {
            $ws = New-TestWorkspace
            try {
                Write-Manifest $ws @( @{ type = "file-exists"; path = "A.txt"; tier = "setup" } )
                New-File $ws "A.txt"
                Write-State $ws @{ project = "KeepMe"; gpg_version = "V9.9"; preflight = @{} }
                Invoke-Script @("-workspaceRoot", $ws) | Out-Null
                $state = Get-Content (Resolve-TestPath $ws ".sdp-workflow/state.json") -Raw | ConvertFrom-Json
                $state.project | Should -Be "KeepMe"
                $state.gpg_version | Should -Be "V9.9"
                $state.preflight.last_setup_validation | Should -Not -BeNullOrEmpty
            } finally { Remove-TestWorkspace $ws }
        }
    }

    # -----------------------------------------------------------------------
    # Envelope shape + exit codes.
    # -----------------------------------------------------------------------
    Context "Envelope shape and exit codes" {

        It "emits the required keys with error null on a clean pass (exit 0)" {
            $ws = New-TestWorkspace
            try {
                Write-Manifest $ws @( @{ type = "file-exists"; path = "A.txt"; tier = "integrity" } )
                New-File $ws "A.txt"
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.ExitCode | Should -Be 0
                $run.Result.command | Should -Be "preflight"
                $run.Result.ok | Should -Be $true
                $run.Result.error | Should -BeNullOrEmpty
                $run.Result.failures.Count | Should -Be 0
                $run.Result.PSObject.Properties.Name | Should -Contain "tiersRun"
                $run.Result.PSObject.Properties.Name | Should -Contain "tiersSkipped"
                $run.Result.PSObject.Properties.Name | Should -Contain "checks"
                $run.Result.manifestUsed | Should -Be "SDP-Workspace-Setup.json"
            } finally { Remove-TestWorkspace $ws }
        }

        It "a failed check yields ok:false and populated failures but still exit 0" {
            $ws = New-TestWorkspace
            try {
                Write-Manifest $ws @( @{ type = "file-exists"; path = "missing.txt"; tier = "integrity" } )
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.ExitCode | Should -Be 0
                $run.Result.ok | Should -Be $false
                $run.Result.failures.Count | Should -BeGreaterThan 0
                $run.Result.error | Should -BeNullOrEmpty
            } finally { Remove-TestWorkspace $ws }
        }

        It "skipped tiers do not affect ok" {
            $ws = New-TestWorkspace
            try {
                # integrity check would FAIL, but its tier is fresh and skipped; setup passes.
                Write-Manifest $ws @(
                    @{ type = "file-exists"; path = "missing.txt"; tier = "integrity" },
                    @{ type = "file-exists"; path = "A.txt";       tier = "setup" }
                )
                New-File $ws "A.txt"
                Write-Config $ws @{ integrityValidationIntervalHours = 1; setupValidationIntervalHours = 0 }
                $recent = (Get-Date).AddMinutes(-1).ToString("yyyy-MM-ddTHH:mm:ss")
                Write-State $ws @{ project = "T"; preflight = @{ last_integrity_validation = $recent } }
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.Result.tiersSkipped | Should -Contain "integrity"
                $run.Result.ok | Should -Be $true
            } finally { Remove-TestWorkspace $ws }
        }
    }

    # -----------------------------------------------------------------------
    # Operational errors — exit 1, error populated, no thrown exception.
    # -----------------------------------------------------------------------
    Context "Operational errors" {

        It "missing manifest -> ok:false, error populated, exit 1" {
            $ws = New-TestWorkspace
            try {
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.ExitCode | Should -Be 1
                $run.Result.ok | Should -Be $false
                $run.Result.error | Should -Not -BeNullOrEmpty
            } finally { Remove-TestWorkspace $ws }
        }

        It "unparseable manifest -> ok:false, error populated, exit 1, no exception leak" {
            $ws = New-TestWorkspace
            try {
                Set-Content (Join-Path $ws "SDP-Workspace-Setup.json") -Value "{ not valid json " -Encoding UTF8
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.ExitCode | Should -Be 1
                $run.Result | Should -Not -BeNullOrEmpty
                $run.Result.error | Should -Not -BeNullOrEmpty
            } finally { Remove-TestWorkspace $ws }
        }

        It "present-but-unparseable state.json -> operational error, exit 1" {
            $ws = New-TestWorkspace
            try {
                Write-Manifest $ws @( @{ type = "file-exists"; path = "A.txt"; tier = "integrity" } )
                New-File $ws "A.txt"
                New-Item -ItemType Directory -Path (Join-Path $ws ".sdp-workflow") -Force | Out-Null
                Set-Content (Resolve-TestPath $ws ".sdp-workflow/state.json") -Value "{ broken " -Encoding UTF8
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.ExitCode | Should -Be 1
                $run.Result.error | Should -Not -BeNullOrEmpty
            } finally { Remove-TestWorkspace $ws }
        }
    }

    # -----------------------------------------------------------------------
    # Manifest scope resolution — which manifest file (SDP-Workspace-Setup.json
    # vs. SDP-Solution-Setup.json) applies to -workspaceRoot.
    # -----------------------------------------------------------------------
    Context "Manifest scope resolution" {

        It "resolves SDP-Workspace-Setup.json when -workspaceRoot has a sdp-project_* segment, even with a stray non-collapse SDP-Solution.json present" {
            $proj = New-TestProjectWorkspace "sdp-project_Foo"
            try {
                Write-SolutionMarker $proj.Root @("sdp-project_Foo", "sdp-project_Bar")
                Write-Manifest $proj.Root @( @{ type = "file-exists"; path = "A.txt"; tier = "integrity" } )
                New-File $proj.Root "A.txt"
                $run = Invoke-Script @("-workspaceRoot", $proj.Root)
                $run.ExitCode | Should -Be 0
                $run.Result.manifestUsed | Should -Be "SDP-Workspace-Setup.json"
                $run.Result.ok | Should -Be $true
            } finally { Remove-TestWorkspace $proj.Parent }
        }

        It "resolves SDP-Solution-Setup.json when SDP-Solution.json is present with a real multi-project last_active_projects list" {
            $ws = New-TestWorkspace
            try {
                Write-SolutionMarker $ws @("sdp-project_Foo", "sdp-project_Bar")
                Write-Manifest $ws @( @{ type = "file-exists"; path = "A.txt"; tier = "integrity" } ) "SDP-Solution-Setup.json"
                New-File $ws "A.txt"
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.ExitCode | Should -Be 0
                $run.Result.manifestUsed | Should -Be "SDP-Solution-Setup.json"
                $run.Result.ok | Should -Be $true
            } finally { Remove-TestWorkspace $ws }
        }

        It "resolves SDP-Workspace-Setup.json when SDP-Solution.json's last_active_projects is the legacy [.] collapse" {
            $ws = New-TestWorkspace
            try {
                Write-SolutionMarker $ws @(".")
                Write-Manifest $ws @( @{ type = "file-exists"; path = "A.txt"; tier = "integrity" } )
                New-File $ws "A.txt"
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.ExitCode | Should -Be 0
                $run.Result.manifestUsed | Should -Be "SDP-Workspace-Setup.json"
                $run.Result.ok | Should -Be $true
            } finally { Remove-TestWorkspace $ws }
        }

        It "operational error when neither a sdp-project_* segment nor SDP-Solution.json is present" {
            $ws = New-TestWorkspace
            try {
                Remove-Item (Join-Path $ws "SDP-Solution.json") -Force
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.ExitCode | Should -Be 1
                $run.Result.ok | Should -Be $false
                $run.Result.error | Should -Match "no manifest resolvable"
                $run.Result.manifestUsed | Should -BeNullOrEmpty
            } finally { Remove-TestWorkspace $ws }
        }

        It "missing SDP-Solution-Setup.json when workspace resolves to solution scope names the solution manifest, not the project one" {
            $ws = New-TestWorkspace
            try {
                Write-SolutionMarker $ws @("sdp-project_Foo", "sdp-project_Bar")
                # No SDP-Solution-Setup.json written.
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.ExitCode | Should -Be 1
                $run.Result.ok | Should -Be $false
                $run.Result.error | Should -Match "SDP-Solution-Setup\.json"
                $run.Result.error | Should -Not -Match "SDP-Workspace-Setup\.json"
            } finally { Remove-TestWorkspace $ws }
        }

        It "unparseable SDP-Solution.json marker -> operational error, no exception leak" {
            $ws = New-TestWorkspace
            try {
                Set-Content (Join-Path $ws "SDP-Solution.json") -Value "{ not valid json " -Encoding UTF8
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.ExitCode | Should -Be 1
                $run.Result | Should -Not -BeNullOrEmpty
                $run.Result.error | Should -Not -BeNullOrEmpty
            } finally { Remove-TestWorkspace $ws }
        }
    }

    # -----------------------------------------------------------------------
    # New check-type validators — a passing and a failing case each.
    # -----------------------------------------------------------------------
    Context "New validator types" {

        It "hook-registered passes when commandContains matches a hook step's command or args, fails when absent" {
            $ws = New-TestWorkspace
            try {
                $settings = @{
                    hooks = @{
                        SessionStart = @(
                            @{ hooks = @( @{ type = "command"; command = "powershell.exe"; args = @("-File", "sdp-project-read-docs.ps1") } ) }
                        )
                    }
                } | ConvertTo-Json -Depth 6
                New-File $ws ".claude/settings.local.json" $settings
                Write-Manifest $ws @(
                    @{ type = "hook-registered"; file = ".claude/settings.local.json"; event = "SessionStart"; commandContains = "sdp-project-read-docs"; tier = "integrity" }
                )
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.Result.ok | Should -Be $true
                $run.Result.checks[0].detail | Should -BeNullOrEmpty

                Write-Manifest $ws @(
                    @{ type = "hook-registered"; file = ".claude/settings.local.json"; event = "SessionStart"; commandContains = "not-there"; tier = "integrity" }
                )
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.Result.ok | Should -Be $false
                $run.Result.checks[0].detail | Should -Not -BeNullOrEmpty
            } finally { Remove-TestWorkspace $ws }
        }

        It "hook-registered fails cleanly when the event is absent from hooks" {
            $ws = New-TestWorkspace
            try {
                New-File $ws ".claude/settings.local.json" (@{ hooks = @{ PostToolUse = @() } } | ConvertTo-Json -Depth 6)
                Write-Manifest $ws @(
                    @{ type = "hook-registered"; file = ".claude/settings.local.json"; event = "SessionStart"; commandContains = "sdp-project-read-docs"; tier = "integrity" }
                )
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.Result.ok | Should -Be $false
                $run.Result.checks[0].detail | Should -Match "SessionStart"
            } finally { Remove-TestWorkspace $ws }
        }

        It "json-array-contains passes when the value is present in the array, fails otherwise" {
            $ws = New-TestWorkspace
            try {
                New-File $ws "settings.json" (@{ permissions = @{ allow = @("Foo(a)", "Bar(b)") } } | ConvertTo-Json -Depth 6)
                Write-Manifest $ws @(
                    @{ type = "json-array-contains"; file = "settings.json"; pointer = "permissions.allow"; value = "Foo(a)"; tier = "integrity" }
                )
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.Result.ok | Should -Be $true
                $run.Result.checks[0].detail | Should -BeNullOrEmpty

                Write-Manifest $ws @(
                    @{ type = "json-array-contains"; file = "settings.json"; pointer = "permissions.allow"; value = "Missing(x)"; tier = "integrity" }
                )
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.Result.ok | Should -Be $false
                $run.Result.checks[0].detail | Should -Not -BeNullOrEmpty
            } finally { Remove-TestWorkspace $ws }
        }

        It "json-array-contains fails cleanly when the pointer does not resolve to an array" {
            $ws = New-TestWorkspace
            try {
                New-File $ws "settings.json" (@{ permissions = @{ allow = "not-an-array" } } | ConvertTo-Json -Depth 6)
                Write-Manifest $ws @(
                    @{ type = "json-array-contains"; file = "settings.json"; pointer = "permissions.allow"; value = "Foo(a)"; tier = "integrity" }
                )
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.Result.ok | Should -Be $false
                $run.Result.checks[0].detail | Should -Match "not an array"
            } finally { Remove-TestWorkspace $ws }
        }

        It "glob-exists passes when a file matches the glob, fails when none match" {
            $ws = New-TestWorkspace
            try {
                New-File $ws "standards/GenericProjectGuidlines_V1.10_20260323.md"
                Write-Manifest $ws @(
                    @{ type = "glob-exists"; pattern = "standards/GenericProjectGuidlines_V*.md"; tier = "setup" }
                )
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.Result.ok | Should -Be $true
                $run.Result.checks[0].detail | Should -BeNullOrEmpty

                Write-Manifest $ws @(
                    @{ type = "glob-exists"; pattern = "standards/NoSuchThing_V*.md"; tier = "setup" }
                )
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.Result.ok | Should -Be $false
                $run.Result.checks[0].detail | Should -Not -BeNullOrEmpty
            } finally { Remove-TestWorkspace $ws }
        }

        It "glob-exists fails cleanly when the glob's directory portion does not exist" {
            $ws = New-TestWorkspace
            try {
                Write-Manifest $ws @(
                    @{ type = "glob-exists"; pattern = "nosuchdir/Foo_V*.md"; tier = "setup" }
                )
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.Result.ok | Should -Be $false
                $run.Result.checks[0].detail | Should -Match "directory missing"
            } finally { Remove-TestWorkspace $ws }
        }

        It "json-field-present passes on any non-null value (including false), fails when the pointer is absent" {
            $ws = New-TestWorkspace
            try {
                New-File $ws "SDP-Config.json" (@{ materialDecisionEscalation = @{ enabled = $true } } | ConvertTo-Json -Depth 6)
                Write-Manifest $ws @(
                    @{ type = "json-field-present"; file = "SDP-Config.json"; pointer = "materialDecisionEscalation.enabled"; tier = "setup" }
                )
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.Result.ok | Should -Be $true
                $run.Result.checks[0].detail | Should -BeNullOrEmpty

                # Explicitly disabled (false) is still present — must still pass, since this is a
                # presence check, not a json-value equality check.
                New-File $ws "SDP-Config.json" (@{ materialDecisionEscalation = @{ enabled = $false } } | ConvertTo-Json -Depth 6)
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.Result.ok | Should -Be $true

                # Field missing entirely -> fail.
                New-File $ws "SDP-Config.json" (@{ schema_version = "1.0" } | ConvertTo-Json -Depth 6)
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.Result.ok | Should -Be $false
                $run.Result.checks[0].detail | Should -Match "pointer not found"
            } finally { Remove-TestWorkspace $ws }
        }

        It "json-field-present fails cleanly when the target file is missing" {
            $ws = New-TestWorkspace
            try {
                Write-Manifest $ws @(
                    @{ type = "json-field-present"; file = "SDP-Config.json"; pointer = "materialDecisionEscalation.enabled"; tier = "setup" }
                )
                $run = Invoke-Script @("-workspaceRoot", $ws)
                $run.Result.ok | Should -Be $false
                $run.Result.checks[0].detail | Should -Match "file missing"
            } finally { Remove-TestWorkspace $ws }
        }
    }
}
