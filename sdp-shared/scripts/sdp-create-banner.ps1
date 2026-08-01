<#
.SYNOPSIS
Renders a fixed-border SDP banner (top/bottom border, dynamic labeled rows, optional named
icons) from a compact icon=/row=/row: invocation argument grammar.

.DESCRIPTION
Full owner: .claude/skills/sdp-create-banner/SKILL.md (L1) — this skill has no L2 procedure
file; the L1 shim documents the invocation grammar and calls this script directly. The icon
vocabulary lives in sdp-create-banner-icons.json, next to this script.

Emits exactly one JSON object to stdout:
  { "status": "success" | "error", "error": <string|null>, "banner": <string|null> }

On success, "banner" is the fully assembled, newline-joined, border-wrapped banner text. The
caller (L1 shim) prints it verbatim inside a fenced code block as its own chat turn — this
script never writes to chat directly and never writes any file.

.PARAMETER Argument
The raw invocation argument string exactly as passed to the /sdp-create-banner skill.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Argument
)

$ErrorActionPreference = 'Stop'

function Write-Result {
    param($Status, $ErrorMessage, $Banner)
    $obj = [ordered]@{
        status = $Status
        error  = $ErrorMessage
        banner = $Banner
    }
    $obj | ConvertTo-Json -Compress -Depth 4
}

function Fail {
    param([string]$Message)
    Write-Result -Status 'error' -ErrorMessage $Message -Banner $null
    exit 0
}

# ---- Text-element (grapheme-cluster) helpers ----
# Several registered icon glyphs are supplementary-plane emoji (surrogate pairs, 2 UTF-16 code
# units) or base+variation-selector pairs (2 codepoints). Raw .Length/.Substring() indexing
# would miscount or could split a surrogate pair mid-glyph. StringInfo's text-element
# enumeration treats each such glyph as the single unit the original mask-overlay design always
# assumed ("1 character slot -> N rendered columns per the Width value"), so counting and
# wrapping stay correct without needing general Unicode width analysis of ordinary text.

function Get-TextElements {
    param([string]$Text)
    $elements = New-Object System.Collections.Generic.List[string]
    $enumerator = [System.Globalization.StringInfo]::GetTextElementEnumerator($Text)
    while ($enumerator.MoveNext()) {
        $elements.Add([string]$enumerator.GetTextElement())
    }
    # The leading comma is required: without it, PowerShell enumerates the List[string] onto
    # the pipeline, and a 0- or 1-element result collapses into $null or a bare string in the
    # caller (losing List identity, so .Count/[0] then operate on string chars, not elements).
    return ,$elements
}

try {

    # ---- Load Icon Registry ----
    # Lives in script-support/, a sibling folder to this script — see
    # Get-Content -Encoding UTF8 below re: this file's required UTF-8 BOM.

    $registryPath = Join-Path $PSScriptRoot 'script-support/sdp-create-banner-icons.json'
    if (-not (Test-Path $registryPath)) {
        Fail "sdp-create-banner: icon registry not found at '$registryPath'."
    }
    try {
        $icons = Get-Content $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Fail "sdp-create-banner: failed to parse icon registry — $($_.Exception.Message)"
    }
    $iconByName = @{}
    foreach ($i in $icons) { $iconByName[$i.name] = $i }

    # ---- Step 1: Tokenize and Parse the Invocation Argument String ----

    $buffer = $Argument
    $triggerPattern = '(?:(?<=\s)|^)(icon=|row=|row:)'
    $tokenMatches = [regex]::Matches($buffer, $triggerPattern)

    if ($tokenMatches.Count -eq 0) {
        Fail "sdp-create-banner: no row: entries found — at least one row is required."
    }

    if ($tokenMatches[0].Index -gt 0) {
        $lead = $buffer.Substring(0, $tokenMatches[0].Index).Trim()
        if ($lead.Length -gt 0) {
            Fail "sdp-create-banner: unrecognized text before the first directive: '$lead'."
        }
    }

    $directives = @()
    for ($i = 0; $i -lt $tokenMatches.Count; $i++) {
        $tokenText = $tokenMatches[$i].Groups[1].Value
        $contentStart = $tokenMatches[$i].Index + $tokenText.Length
        $contentEnd = if ($i -lt $tokenMatches.Count - 1) { $tokenMatches[$i + 1].Index } else { $buffer.Length }
        $assoc = $buffer.Substring($contentStart, $contentEnd - $contentStart).Trim()
        $directives += [pscustomobject]@{ Token = $tokenText; Position = $tokenMatches[$i].Index; Text = $assoc }
    }

    $iconDirectives = @($directives | Where-Object { $_.Token -eq 'icon=' })
    $rowEqDirectives = @($directives | Where-Object { $_.Token -eq 'row=' })
    $rowDirectives = @($directives | Where-Object { $_.Token -eq 'row:' } | Sort-Object Position)

    if ($iconDirectives.Count -gt 1) {
        Fail "sdp-create-banner: only one icon= directive is supported per invocation, found $($iconDirectives.Count)."
    }
    if ($rowEqDirectives.Count -gt 1) {
        Fail "sdp-create-banner: only one row= directive is supported per invocation, found $($rowEqDirectives.Count)."
    }
    if ($rowEqDirectives.Count -eq 1 -and $iconDirectives.Count -eq 0) {
        Fail "sdp-create-banner: row= found without a preceding icon=."
    }
    if ($rowDirectives.Count -eq 0) {
        Fail "sdp-create-banner: no row: entries found — at least one row is required."
    }

    $rows = @()
    foreach ($rd in $rowDirectives) {
        $pipeIdx = $rd.Text.IndexOf('|')
        if ($pipeIdx -lt 0) {
            Fail "sdp-create-banner: row: entry '$($rd.Text)' has no | separator — expected 'Label | Content'."
        }
        $label = $rd.Text.Substring(0, $pipeIdx).Trim()
        $rowContent = $rd.Text.Substring($pipeIdx + 1).Trim()
        $rows += [pscustomobject]@{ Label = $label; Content = $rowContent; Icon = $null }
    }

    # ---- Step 1 (icon list) + Step 2: Resolve Icon Names ----

    if ($iconDirectives.Count -eq 1) {
        $iconNames = @($iconDirectives[0].Text -split ',' | ForEach-Object { $_.Trim() })

        if ($rowEqDirectives.Count -eq 1) {
            $rowIdxRaw = @($rowEqDirectives[0].Text -split ',' | ForEach-Object { $_.Trim() })
            if ($rowIdxRaw.Count -ne $iconNames.Count) {
                Fail "sdp-create-banner: icon= and row= lists must be the same length."
            }
            $rowIdx = @()
            foreach ($r in $rowIdxRaw) {
                $n = 0
                if (-not [int]::TryParse($r, [ref]$n)) {
                    Fail "sdp-create-banner: row= contains a non-integer index '$r'."
                }
                $rowIdx += $n
            }
            $seenIdx = @{}
            foreach ($n in $rowIdx) {
                if ($seenIdx.ContainsKey($n)) {
                    Fail "sdp-create-banner: row= contains duplicate index $n."
                }
                $seenIdx[$n] = $true
            }
        } else {
            if ($iconNames.Count -gt $rows.Count) {
                Fail "sdp-create-banner: icon= has $($iconNames.Count) names but only $($rows.Count) row: entries exist to assign them to."
            }
            $rowIdx = @(0..($iconNames.Count - 1))
        }

        for ($k = 0; $k -lt $iconNames.Count; $k++) {
            $idx = $rowIdx[$k]
            if ($idx -lt 0 -or $idx -ge $rows.Count) {
                Fail "sdp-create-banner: icon row index $idx has no matching row: entry."
            }
            $name = $iconNames[$k]
            if (-not $iconByName.ContainsKey($name)) {
                $validNames = ($icons | ForEach-Object { $_.name }) -join ', '
                Fail "sdp-create-banner: unknown icon name '$name' — valid names: $validNames."
            }
            $rows[$idx].Icon = $iconByName[$name]
        }
    }

    # ---- Step 3: Apply Icons to Row Content ----

    foreach ($row in $rows) {
        if ($null -ne $row.Icon) {
            $row.Content = "$($row.Icon.glyph) $($row.Content)"
        }
    }

    # ---- Step 4: Body Row Construction ----
    # Ordinary, exact string padding/truncation — no textual mask-overlay needed here (that
    # technique existed to help an LLM avoid manual counting errors by hand; a script computes
    # exact lengths directly).

    $LABEL_WIDTH = 11
    $CONTENT_WIDTH_STANDARD = 59
    $CONTENT_WIDTH_ICON2 = 58

    function New-BannerRow {
        param([string]$Label, [string]$Content, [int]$ContentWidth)
        $labelEls = Get-TextElements $Label
        if ($labelEls.Count -gt $LABEL_WIDTH) {
            Fail "sdp-create-banner: label '$Label' exceeds the $LABEL_WIDTH-character label field width."
        }
        $labelPadded = $Label + (' ' * ($LABEL_WIDTH - $labelEls.Count))

        $contentEls = Get-TextElements $Content
        $pad = [Math]::Max(0, $ContentWidth - $contentEls.Count)
        $contentPadded = $Content + (' ' * $pad)

        return "│ $labelPadded$contentPadded │"
    }

    function Split-ContentToChunks {
        param([string]$Content, [int]$FirstWidth)
        $chunks = New-Object System.Collections.Generic.List[string]
        $remaining = $Content
        $width = $FirstWidth
        while ($true) {
            $els = Get-TextElements $remaining
            if ($els.Count -le $width) {
                $chunks.Add(($els -join ''))
                break
            }
            $breakAt = -1
            for ($p = [Math]::Min($width, $els.Count) - 1; $p -ge 0; $p--) {
                if ($els[$p] -eq ' ') { $breakAt = $p; break }
            }
            if ($breakAt -lt 0) { $breakAt = $width - 1 }
            $chunk = (($els[0..$breakAt]) -join '').TrimEnd()
            $chunks.Add($chunk)
            if ($breakAt -eq $els.Count - 1) {
                $remaining = ''
            } else {
                $rest = $els[($breakAt + 1)..($els.Count - 1)]
                $remaining = (($rest) -join '').TrimStart()
            }
            $width = $CONTENT_WIDTH_STANDARD
            if ($remaining.Length -eq 0) { break }
        }
        # See Get-TextElements above — same single-element pipeline-unrolling trap applies here.
        return ,$chunks
    }

    $builtRows = @()
    foreach ($row in $rows) {
        $contentWidth = $CONTENT_WIDTH_STANDARD
        if ($null -ne $row.Icon -and [int]$row.Icon.width -eq 2) {
            $contentWidth = $CONTENT_WIDTH_ICON2
        }
        $chunks = Split-ContentToChunks -Content $row.Content -FirstWidth $contentWidth

        $builtRows += New-BannerRow -Label $row.Label -Content $chunks[0] -ContentWidth $contentWidth
        for ($c = 1; $c -lt $chunks.Count; $c++) {
            $builtRows += New-BannerRow -Label '' -Content $chunks[$c] -ContentWidth $CONTENT_WIDTH_STANDARD
        }
    }

    # ---- Step 5.1: Assemble ----
    # Fixed border, reproduced verbatim from sdp-initialize-sdp's Closing Banner Border.

    $top = '╭─ ✦ SDP ────────────────── Sapient-Driven Principles ─────────────── ✦ ─╮'
    $bottom = '╰─ ✦ ──────────────────────────────────────────────────────────────── ✦ ─╯'

    $bannerLines = @($top) + $builtRows + @($bottom)
    $banner = $bannerLines -join "`n"

    Write-Result -Status 'success' -ErrorMessage $null -Banner $banner

} catch {
    Fail "sdp-create-banner: unexpected error — $($_.Exception.Message)"
}
