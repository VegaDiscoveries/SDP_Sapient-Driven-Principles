#Requires -Module Pester

<#
.SYNOPSIS
    Pester unit tests for sdp-create-prompt.ps1

.NOTES
    Run from workspace root:
        Invoke-Pester sdp-shared/scripts/tests/sdp-create-prompt.Tests.ps1 -Output Detailed
#>

Describe "sdp-create-prompt.ps1" {

    # ---------------------------------------------------------------------------
    # Helpers — Pester 5 runs the script body during discovery, so helpers must be
    # defined in BeforeAll to exist during the run phase. scriptPath is script-scoped
    # so the Invoke-Script helper resolves it from any child block.
    # ---------------------------------------------------------------------------
    BeforeAll {
        $script:scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) "sdp-create-prompt.ps1"
        $script:pwshExe    = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName

        function Resolve-TestPath([string]$root, [string]$relative) {
            $parts = $relative -split '[/\\]' | Where-Object { $_ -ne '' }
            $result = $root
            foreach ($p in $parts) { $result = Join-Path $result $p }
            return $result
        }

        function New-TestWorkspace {
            $root = Join-Path ([System.IO.Path]::GetTempPath()) "sdp-test-$(New-Guid)"
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            # Minimal directory structure
            New-Item -ItemType Directory -Path (Resolve-TestPath $root ".sdp-workflow/sessions") -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $root "sdp-docs") -Force | Out-Null
            New-Item -ItemType Directory -Path (Resolve-TestPath $root "standards/GenericProjectGuidlines_Sections") -Force | Out-Null

            return $root
        }

        function Write-StateJson([string]$root, [hashtable]$overrides = @{}) {
            $defaults = @{
                workflow_status  = "active"
                current_phase    = 3
                active_work_item = "WI-007"
                last_session     = "004"
                active_phase_file = "sdp-docs/phase3/myproject-phase3-plan.md"
                project_name     = "TestProject"
            }
            foreach ($k in $overrides.Keys) { $defaults[$k] = $overrides[$k] }
            $defaults | ConvertTo-Json | Set-Content (Resolve-TestPath $root ".sdp-workflow/state.json") -Encoding UTF8
        }

        function Write-PhaseStateJson([string]$root, [int]$phase, [string]$workItem, [string]$status, [string[]]$flags = @()) {
            @{
                tasks = @{
                    $workItem = @{
                        status  = $status
                        flags   = $flags
                        eval_cycles = 0
                    }
                }
            } | ConvertTo-Json -Depth 5 | Set-Content (Resolve-TestPath $root ".sdp-workflow/phase${phase}_state.json") -Encoding UTF8
        }

        function Write-DocList([string]$root) {
            @(
                @{ path = "SDP_Sapient-Driven-Principles_v0.9.5.md"; name = "Bootstrap"; role = "bootstrap"; includeInReadDocs = $true }
            ) | ConvertTo-Json | Set-Content (Join-Path $root "SDP-Document-List.json") -Encoding UTF8
        }

        function Write-RegistryMd([string]$root) {
            "# Registry`n" | Set-Content (Resolve-TestPath $root ".sdp-workflow/registry.md") -Encoding UTF8
        }

        function Invoke-Script([string]$workspaceRoot) {
            $output = & $script:pwshExe -NoProfile -NonInteractive -File $script:scriptPath -workspaceRoot $workspaceRoot 2>&1
            $exitCode = $LASTEXITCODE
            $stdout = ($output | Where-Object { $_ -is [string] }) -join ""
            $result = $null
            try { $result = $stdout | ConvertFrom-Json } catch { }
            return @{ ExitCode = $exitCode; Stdout = $stdout; Result = $result }
        }

        function Remove-TestWorkspace([string]$root) {
            if ($root -and (Test-Path $root)) {
                Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Happy path - WORKER dispatch" {
        BeforeAll {
            $script:ws = New-TestWorkspace
            Write-StateJson $script:ws
            Write-PhaseStateJson $script:ws 3 "WI-007" "PENDING"
            Write-DocList $script:ws
            Write-RegistryMd $script:ws
            $script:run = Invoke-Script $script:ws
        }
        AfterAll { Remove-TestWorkspace $script:ws }

        It "exits with code 0" {
            $script:run.ExitCode | Should -Be 0
        }

        It "stdout status is success" {
            $script:run.Result.status | Should -Be "success"
        }

        It "stdout nextRole is WORKER" {
            $script:run.Result.nextRole | Should -Be "WORKER"
        }

        It "stdout workItem matches active_work_item" {
            $script:run.Result.workItem | Should -Be "WI-007"
        }

        It "temp file exists" {
            $tempPath = Resolve-TestPath $script:ws $script:run.Result.tempFile
            $tempPath | Should -Exist
        }

        It "temp file script_status is success" {
            $tempPath = Resolve-TestPath $script:ws $script:run.Result.tempFile
            $temp = Get-Content $tempPath -Raw | ConvertFrom-Json
            $temp._meta.script_status | Should -Be "success"
        }

        It "temp file contains sentinel" {
            $tempPath = Resolve-TestPath $script:ws $script:run.Result.tempFile
            $temp = Get-Content $tempPath -Raw | ConvertFrom-Json
            $temp.sentinel | Should -Match 'work_item="WI-007"'
        }

        It "temp file section_1 declares WORKER role" {
            $tempPath = Resolve-TestPath $script:ws $script:run.Result.tempFile
            $temp = Get-Content $tempPath -Raw | ConvertFrom-Json
            $temp.section_1 | Should -Match "WORKER"
        }

        It "temp file all sections populated" {
            $tempPath = Resolve-TestPath $script:ws $script:run.Result.tempFile
            $temp = Get-Content $tempPath -Raw | ConvertFrom-Json
            $temp.section_1 | Should -Not -BeNullOrEmpty
            $temp.section_2 | Should -Not -BeNullOrEmpty
            $temp.section_3 | Should -Not -BeNullOrEmpty
            $temp.section_4 | Should -Not -BeNullOrEmpty
            $temp.section_5 | Should -Not -BeNullOrEmpty
        }

        It "tracking file exists" {
            $trackingPath = Resolve-TestPath $script:ws ".sdp-workflow/temp/sdp-create-prompt-tracking.json"
            $trackingPath | Should -Exist
        }

        It "tracking file points to the temp file" {
            $trackingPath = Resolve-TestPath $script:ws ".sdp-workflow/temp/sdp-create-prompt-tracking.json"
            $tracking = Get-Content $trackingPath -Raw | ConvertFrom-Json
            $tracking.active_temp_file | Should -Be $script:run.Result.tempFile
        }

        It "tracking file state_snapshot contains workflow_status" {
            $trackingPath = Resolve-TestPath $script:ws ".sdp-workflow/temp/sdp-create-prompt-tracking.json"
            $tracking = Get-Content $trackingPath -Raw | ConvertFrom-Json
            $tracking.state_snapshot.workflow_status | Should -Be "active"
        }

        It "stdout promptFile points to 00_prompt.txt" {
            $script:run.Result.promptFile | Should -Be "sdp-docs/00_prompt.txt"
        }

        It "writes sdp-docs/00_prompt.txt" {
            $promptPath = Resolve-TestPath $script:ws "sdp-docs/00_prompt.txt"
            $promptPath | Should -Exist
        }

        It "00_prompt.txt first line equals the temp sentinel" {
            $promptPath = Resolve-TestPath $script:ws "sdp-docs/00_prompt.txt"
            $tempPath   = Resolve-TestPath $script:ws $script:run.Result.tempFile
            $temp       = Get-Content $tempPath -Raw | ConvertFrom-Json
            $firstLine  = Get-Content $promptPath -TotalCount 1
            $firstLine.Trim() | Should -Be $temp.sentinel
        }

        It "00_prompt.txt has no UTF-8 BOM (sentinel stays first-line parseable)" {
            $promptPath = Resolve-TestPath $script:ws "sdp-docs/00_prompt.txt"
            $bytes = [System.IO.File]::ReadAllBytes($promptPath)
            ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -Be $false
        }

        It "00_prompt.txt contains all five section headers" {
            # Match the ASCII prefix + title and leave the em-dash separator as a
            # wildcard so the assertion is independent of source/host encoding.
            $promptPath = Resolve-TestPath $script:ws "sdp-docs/00_prompt.txt"
            $content = Get-Content $promptPath -Raw -Encoding UTF8
            $content | Should -Match "## Section 1 .+ Role Declaration"
            $content | Should -Match "## Section 2 .+ Read First"
            $content | Should -Match "## Section 3 .+ Current State Summary"
            $content | Should -Match "## Section 4 .+ Task Instruction"
            $content | Should -Match "## Section 5 .+ Key Files"
        }

        It "00_prompt.txt section headers use the em-dash separator (U+2014)" {
            $promptPath = Resolve-TestPath $script:ws "sdp-docs/00_prompt.txt"
            $content = Get-Content $promptPath -Raw -Encoding UTF8
            $emdash = [char]0x2014
            $content.Contains("## Section 1 $emdash Role Declaration") | Should -Be $true
        }
    }

    Context "Halted workflow" {
        BeforeAll {
            $script:ws = New-TestWorkspace
            # em-dash built from its code point so this source file stays pure ASCII and
            # parses under Windows PowerShell 5.1 (no-BOM .ps1 is decoded as ANSI there).
            Write-StateJson $script:ws @{ workflow_status = "halted"; halt_reason = "Skills check failed $([char]0x2014) missing: sdp-project-worker" }
            Write-DocList $script:ws
            $script:run = Invoke-Script $script:ws
        }
        AfterAll { Remove-TestWorkspace $script:ws }

        It "exits with code 0" {
            $script:run.ExitCode | Should -Be 0
        }

        It "stdout status is halted" {
            $script:run.Result.status | Should -Be "halted"
        }

        It "stdout haltReason is populated" {
            $script:run.Result.haltReason | Should -Match "Skills check failed"
        }

        It "temp file script_status is halted" {
            $tempPath = Resolve-TestPath $script:ws $script:run.Result.tempFile
            $temp = Get-Content $tempPath -Raw | ConvertFrom-Json
            $temp._meta.script_status | Should -Be "halted"
        }

        It "temp file contains halt_reason" {
            $tempPath = Resolve-TestPath $script:ws $script:run.Result.tempFile
            $temp = Get-Content $tempPath -Raw | ConvertFrom-Json
            $temp.halt_reason | Should -Match "Skills check failed"
        }

        It "temp file has no prompt sections" {
            $tempPath = Resolve-TestPath $script:ws $script:run.Result.tempFile
            $temp = Get-Content $tempPath -Raw | ConvertFrom-Json
            $temp.section_1 | Should -BeNullOrEmpty
        }

        It "does not write sdp-docs/00_prompt.txt on halt" {
            $promptPath = Resolve-TestPath $script:ws "sdp-docs/00_prompt.txt"
            $promptPath | Should -Not -Exist
        }
    }

    Context "DIAGNOSIS_BLOCKED flag" {
        BeforeAll {
            $script:ws = New-TestWorkspace
            Write-StateJson $script:ws
            Write-PhaseStateJson $script:ws 3 "WI-007" "PENDING" @("DIAGNOSIS_BLOCKED")
            Write-DocList $script:ws
            Write-RegistryMd $script:ws
            $script:run = Invoke-Script $script:ws
        }
        AfterAll { Remove-TestWorkspace $script:ws }

        It "stdout flags contains DIAGNOSIS_BLOCKED" {
            $script:run.Result.flags | Should -Contain "DIAGNOSIS_BLOCKED"
        }

        It "temp file flags array contains DIAGNOSIS_BLOCKED" {
            $tempPath = Resolve-TestPath $script:ws $script:run.Result.tempFile
            $temp = Get-Content $tempPath -Raw | ConvertFrom-Json
            $temp.flags | Should -Contain "DIAGNOSIS_BLOCKED"
        }

        It "section_4 contains DIAGNOSIS_BLOCKED note" {
            $tempPath = Resolve-TestPath $script:ws $script:run.Result.tempFile
            $temp = Get-Content $tempPath -Raw | ConvertFrom-Json
            $temp.section_4 | Should -Match "DIAGNOSIS_BLOCKED"
        }
    }

    Context "PARTIAL_COMPLIANCE_ESCALATE flag" {
        BeforeAll {
            $script:ws = New-TestWorkspace
            Write-StateJson $script:ws
            Write-PhaseStateJson $script:ws 3 "WI-007" "PENDING" @("PARTIAL_COMPLIANCE_ESCALATE")
            Write-DocList $script:ws
            Write-RegistryMd $script:ws
            $script:run = Invoke-Script $script:ws
        }
        AfterAll { Remove-TestWorkspace $script:ws }

        It "temp file flags contains PARTIAL_COMPLIANCE_ESCALATE" {
            $tempPath = Resolve-TestPath $script:ws $script:run.Result.tempFile
            $temp = Get-Content $tempPath -Raw | ConvertFrom-Json
            $temp.flags | Should -Contain "PARTIAL_COMPLIANCE_ESCALATE"
        }

        It "section_4 contains PARTIAL_COMPLIANCE_ESCALATE note" {
            $tempPath = Resolve-TestPath $script:ws $script:run.Result.tempFile
            $temp = Get-Content $tempPath -Raw | ConvertFrom-Json
            $temp.section_4 | Should -Match "PARTIAL_COMPLIANCE_ESCALATE"
        }
    }

    Context "Missing state.json" {
        BeforeAll {
            $script:ws = New-TestWorkspace
            # Do NOT write state.json
            $script:run = Invoke-Script $script:ws
        }
        AfterAll { Remove-TestWorkspace $script:ws }

        It "exits with code 1" {
            $script:run.ExitCode | Should -Be 1
        }

        It "stdout status is error" {
            $script:run.Result.status | Should -Be "error"
        }

        It "stdout error mentions state.json" {
            $script:run.Result.error | Should -Match "state.json"
        }
    }

    Context "Missing phase state file" {
        BeforeAll {
            $script:ws = New-TestWorkspace
            Write-StateJson $script:ws  # has active_work_item = WI-007 but no phase state file
            Write-DocList $script:ws
            Write-RegistryMd $script:ws
            $script:run = Invoke-Script $script:ws
        }
        AfterAll { Remove-TestWorkspace $script:ws }

        It "exits with code 0 (degrades gracefully to COORDINATOR)" {
            $script:run.ExitCode | Should -Be 0
        }

        It "nextRole defaults to COORDINATOR when phase state file absent" {
            $script:run.Result.nextRole | Should -Be "COORDINATOR"
        }
    }

    Context "retry_count increment" {
        BeforeAll {
            $script:ws = New-TestWorkspace
            Write-StateJson $script:ws
            Write-PhaseStateJson $script:ws 3 "WI-007" "PENDING"
            Write-DocList $script:ws
            Write-RegistryMd $script:ws

            # First run - establishes tracking file with retry_count 0
            $first = Invoke-Script $script:ws

            # Simulate a prior *error* run: the script only carries forward and increments
            # retry_count across consecutive error runs (a prior success/halt resets to 0),
            # so the simulated prior temp must be marked script_status = "error".
            $tempPath = Resolve-TestPath $script:ws $first.Result.tempFile
            $temp = Get-Content $tempPath -Raw | ConvertFrom-Json
            $temp._meta.retry_count = 2
            $temp._meta.script_status = "error"
            $temp | ConvertTo-Json -Depth 10 | Set-Content $tempPath -Encoding UTF8

            # Second run - should read prior temp via tracking and increment to 3
            $script:run = Invoke-Script $script:ws
        }
        AfterAll { Remove-TestWorkspace $script:ws }

        It "new temp file retry_count is 3" {
            $tempPath = Resolve-TestPath $script:ws $script:run.Result.tempFile
            $temp = Get-Content $tempPath -Raw | ConvertFrom-Json
            $temp._meta.retry_count | Should -Be 3
        }
    }

    Context "REVIEWER dispatch (WORK_COMPLETE status)" {
        BeforeAll {
            $script:ws = New-TestWorkspace
            Write-StateJson $script:ws
            Write-PhaseStateJson $script:ws 3 "WI-007" "WORK_COMPLETE"
            Write-DocList $script:ws
            Write-RegistryMd $script:ws
            $script:run = Invoke-Script $script:ws
        }
        AfterAll { Remove-TestWorkspace $script:ws }

        It "nextRole is COORDINATOR (dispatches REVIEWER via COORDINATOR)" {
            $script:run.Result.nextRole | Should -Be "COORDINATOR"
        }

        It "section_3 next action mentions REVIEWER dispatch" {
            $tempPath = Resolve-TestPath $script:ws $script:run.Result.tempFile
            $temp = Get-Content $tempPath -Raw | ConvertFrom-Json
            $temp.section_3 | Should -Match "REVIEWER"
        }
    }
}
