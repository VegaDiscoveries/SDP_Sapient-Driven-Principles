<img src="images/SDP_DocsLogo_WithText_0700x0163.png" alt="SDP Logo" width="375">

# AI-Assisted Development Workflow — Script Authoring Reference

| Field | Value |
|-------|-------|
| **Companion doc** | `SDP_Sapient-Driven-Principles_vN.N.N.md` |
| **Updated** | 2026-06-24 |
| **File** | `SDP-Script-Authoring.md` |

**Purpose:** Conventions, templates, and the mandatory permission registration requirement for
authoring new PowerShell scripts in the SDP workflow. Load this file explicitly when creating
or editing script files. Not loaded automatically by `sdp-project-read-docs` — add to
`SDP-Document-List.json` with `"includeInReadDocs": false`.

---

## Script vs. Skill

A script is pure, deterministic code — reads state, writes files, makes system calls. A skill
is an agent procedure — requires LLM reasoning to execute.

| Criterion | Script (`.ps1`) | Skill (`SKILL.md`) |
|-----------|----------------|-------------------|
| Execution engine | PowerShell tool call | Agent reads and follows procedure |
| Reasoning required? | No | Yes |
| Cost | Tool-call cost (cheap) | Token cost (expensive) |
| Examples | Play tone, read/write JSON, build prompt sections | Coordinate workflow, evaluate task output |
| Fails without LLM? | No | Yes |

When a task can be expressed as deterministic code, make it a script. A skill may call a script
for heavy data work — see `sdp-project-create-prompt` for this pattern.

---

## Script Location and Naming

All SDP scripts live in `sdp-shared/scripts/`. This is a solution-level directory — scripts
here serve all projects in the solution, not any single project. Do not create scripts inside
individual project folders.

**Naming:** `sdp-[name].ps1` — lowercase, hyphen-separated, `sdp-` prefix.

**Registration:** Every script must have:
1. A permission entry in `.claude/settings.local.json` — see [Permission Registration](#permission-registration) below
2. An entry in the SKILLS CHECK of the main bootstrap doc — see [Bootstrap Integration](#bootstrap-integration) below

Both must be added in the same session the script is created. Never create a script and defer
permission registration to a later session.

---

## Script Anatomy

### SYNOPSIS Block (required)

Every script opens with a PowerShell comment-based help block.

```powershell
<#
.SYNOPSIS
    [One sentence — what this script does.]

.PARAMETER workspaceRoot
    Path to the workspace root. Defaults to two levels above this script
    (sdp-shared/scripts/), matching the sdp-tone.ps1 convention.

.NOTES
    Stdout: [what this script writes to stdout — "nothing" or "single-line JSON result object"]
    Exit codes: 0 = success or non-blocking condition; 1 = blocking error
    [If non-blocking: "Exits silently under all failure conditions — [reason why]."]
#>
```

Minimum required sections: `.SYNOPSIS`, `.PARAMETER` (one per declared param), `.NOTES`
(stdout contract and exit code table). No changelog/history block belongs in this file, in the
comment-based help or anywhere else — a script states only the current, correct behavior; git
history is the audit trail for why it changed.

---

### Workspace Root Resolution

Scripts fall into two categories based on what root they need to resolve:

**Solution-root scripts** — self-resolve `$workspaceRoot` from their own location and do not
accept a caller-provided root, then read a file under that root. Some read a file directly at
the root (`SDP-Config.json`); some read a file in the `script-support/` folder, a sibling of
`sdp-shared/scripts/` itself, resolved directly off `$PSScriptRoot` rather than off
`$workspaceRoot` (`sdp-shared/scripts/script-support/SDP-Tones.json`,
`sdp-shared/scripts/script-support/sdp-create-banner-icons.json`) — the defining trait is
root self-resolution, not the file sitting literally at the top level. Examples: `sdp-tone.ps1`,
`sdp-github.ps1`, `sdp-create-banner.ps1`.

```powershell
$workspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
```

Scripts live at `sdp-shared/scripts/` — two levels below the solution root. This resolution
is correct for solution-root scripts regardless of which project is active.

**Project-scoped scripts** — read or write files inside a specific project folder
(`state.json`, `sdp-docs/00_prompt.txt`, `SDP-Workspace-Setup.json`). These scripts must
accept `-workspaceRoot` as a **required caller-provided argument**. The calling skill resolves
the active project path via the three-level order (Section 5 of the design spec) and passes it
explicitly. Examples: `sdp-preflight.ps1`, `sdp-create-prompt.ps1`.

```powershell
param(
    [string]$workspaceRoot = ""
)

if (-not $workspaceRoot) {
    $workspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
```

The fallback to `Split-Path` is retained for local test invocations. In normal workflow
operation, the calling skill always provides `-workspaceRoot .\[resolved_project]` — the
script must not resolve the project path itself.

**Mixed-root scripts** — a project-scoped script (accepts `-workspaceRoot` for its
project-level reads/writes) that also needs a solution-level resource never duplicated per
project (e.g. `standards/GenericProjectGuidlines_[version].md`) must resolve that resource
against the **solution root**, not `$workspaceRoot` — even though `$workspaceRoot` is the
active project root for everything else the script touches. Resolve the solution root the same
way solution-root scripts do (`Split-Path -Parent (Split-Path -Parent $PSScriptRoot)`), as a
second, independent variable — do not reuse `$workspaceRoot` for it, and do not assume the two
roots coincide. **Lesson (production bug, fixed 2026-07-11):**
`sdp-gate-review-gpg-check.ps1` originally joined `standards/...` against `$workspaceRoot`;
in any multi-project solution `$workspaceRoot` is `[resolved_project]` (one level below the
solution root), so the check always false-halted with "GPG file missing" even when the file
genuinely existed one directory up. See the worked example below.

```powershell
param(
    [string]$workspaceRoot = ""
)
if (-not $workspaceRoot) {
    $workspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
# Independent — do not derive this from $workspaceRoot.
$solutionRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
```

**Calling convention summary:**

| Script | `-workspaceRoot` in workflow | Resolves to |
|--------|------------------------------|-------------|
| `sdp-tone.ps1` | Not passed | Solution root (self-resolved) |
| `sdp-github.ps1` | Not passed | Solution root (self-resolved) |
| `sdp-create-banner.ps1` | Not passed | Solution root (self-resolved) |
| `sdp-report-log-loop-metrics.ps1` | Not passed | Solution root (self-resolved) |
| `sdp-report-log-hook-metrics.ps1` | Not passed | Solution root (self-resolved) |
| `sdp-report-log-workflow-metrics.ps1` | Not passed | Solution root (self-resolved) |
| `sdp-report-logs-combine.ps1` | Not passed | Solution root (self-resolved) |
| `sdp-report-log-combined-metrics.ps1` | Not passed | Solution root (self-resolved) |
| `sdp-hook-log.ps1` | Not passed | Solution root (self-resolved) |
| `sdp-workflow-log.ps1` | Not passed | Solution root (self-resolved) |
| `sdp-preflight.ps1` | Required — `.\[resolved_project]` | Active project folder |
| `sdp-create-prompt.ps1` | Required — `.\[resolved_project]` | Active project folder |
| `sdp-gate-review-gpg-check.ps1` | Required — `.\[resolved_project]` | Active project folder, **except** `standards/` — solution root (mixed-root) |
| `sdp-gate-review-setup.ps1` | Required — `.\[resolved_project]` | Active project folder |
| `sdp-gate-review-finalize.ps1` | Required — `.\[resolved_project]` | Active project folder |

---

### Parameter Conventions

| Rule | Detail |
|------|--------|
| Naming | Lowercase single-word (`-event`); camelCase multi-word (`-skillName`, `-workspaceRoot`) |
| Defaults | Non-blocking params default to empty string in `param()` |
| Validation | Validate at the top of the script immediately after params — exit or error based on severity (see Output Contract below) |

---

### Output Contract

Two categories of script, each with a different stdout contract.

**Non-blocking utility scripts** (e.g., `sdp-tone.ps1`):
- Write nothing to stdout
- Exit silently (`exit 0`) under all failure conditions — a utility failure must never block a workflow
- Use `try/catch` around all operations; swallow errors rather than surfacing them

**Agent-consumed scripts** (e.g., `sdp-create-prompt.ps1`):
- Write exactly one line to stdout: a compact JSON result object
- Use a `Write-Result` helper to enforce single-point control over stdout format
- The calling skill reads this line as structured data — never mix narrative text with the JSON line
- The result object must include a `status` field: `"success"` | `"error"` | `"halted"`

```powershell
function Write-Result([hashtable]$hash) {
    Write-Output ($hash | ConvertTo-Json -Compress -Depth 5)
}
```

---

### Error and Exit Contract

| Condition | Non-blocking utility | Agent-consumed |
|-----------|---------------------|----------------|
| Missing or invalid parameter | `exit 0` (silent) | `Write-Result @{ status = "error"; error = "..." }; exit 1` |
| Required file not found | `exit 0` (silent) | `Write-Result @{ status = "error"; error = "..." }; exit 1` |
| JSON parse failure | `exit 0` (silent) | `Write-Result @{ status = "error"; error = "..." }; exit 1` |
| Success | `exit 0` | `Write-Result @{ status = "success"; ... }; exit 0` |
| Workflow halted (expected condition) | n/a | `Write-Result @{ status = "halted"; ... }; exit 0` |

Agent-consumed scripts distinguish `exit 1` (error — skill must surface to user) from
`exit 0` with `status = "halted"` (expected workflow state — skill handles without error).

---

### File Encoding

All files written by scripts must use UTF-8 without BOM:

```powershell
Set-Content $path -Encoding UTF8
```

PowerShell 5.1 default is UTF-16 LE (with BOM). Explicit `-Encoding UTF8` is mandatory on
every `Set-Content` call in SDP scripts. When building nested objects for `ConvertTo-Json`,
always specify `-Depth` — PowerShell truncates nested objects to `"@{}"` at the default depth.

---

### `Get-Content -Raw` and `ConvertTo-Json`: strip note-properties before serializing

`Get-Content -Raw` returns a string decorated with hidden `PSPath`/`PSProvider`/`PSDrive`
note-properties, attached by the FileSystem provider. These are invisible and harmless when
the value is used in string interpolation, `-replace`, or regex matching — but if that value
(or anything derived from it) is later piped into `ConvertTo-Json`, the attached note-properties
get serialized too, including `PSProvider.ImplementingType` — a live `.NET` `Type` object whose
declared members reference their own parameter/declaring types recursively. `ConvertTo-Json`
does not error on this; it simply never returns within any reasonable timeout. This was
diagnosed live while implementing `sdp-gate-review-setup.ps1` (see its eval's Implementation
Record for the full trace) — a 40-byte fixture file was enough to reproduce an indefinite hang.

**Rule:** any script whose JSON result includes raw file content (not just a regex-extracted
substring) must cast immediately after reading:

```powershell
$content = [string](Get-Content $path -Raw -Encoding UTF8)
```

A script that only ever extracts substrings via regex (`[regex]::Match(...).Groups[1].Value`)
is unaffected — regex match results are fresh, undecorated strings regardless of the source.
The risk is specific to putting the `Get-Content` return value itself into a JSON field.

---

## Permission Registration

### Why This Is Required

Claude Code subagents do not inherit wildcard or blanket permissions from the parent session.
When a skill invokes a script via the PowerShell tool, the subagent requires an explicit
permission entry in `.claude/settings.local.json` for that specific script path. Without it,
the PowerShell tool call is blocked by the security layer — the skill halts and the workflow
stalls.

This failure is difficult to diagnose: the subagent stops without updating the phase state
file, `sdp-project-state-loop` interprets the missing update as a stuck REVIEWER cycle, and the stuck
detection logic fires rather than surfacing a permission error. In practice: without this
knowledge the root cause took dozens of failed cycles to locate.

**Rule:** Add the permission entry in the same session the script is created. Never defer it.

---

### Permission Entry Format

```json
"PowerShell(.\\sdp-shared\\scripts\\[script-name].ps1 *)"
```

The `*` allows any arguments after the script path. Double backslashes are required by JSON
string escaping. The path is relative to the workspace root.

---

### Where to Add

File: `.claude/settings.local.json` (project-scoped — not the user-level settings file).

Add to the `permissions.allow` array. If the array does not exist, create the `permissions`
object at the top level alongside `hooks` and `enabledPlugins`.

**Full file example with permission entries:**

```json
{
  "hooks": {
    "SessionStart": [ ... ]
  },
  "enabledPlugins": {
    "superpowers@claude-plugins-official": true
  },
  "permissions": {
    "allow": [
      "PowerShell(.\\sdp-shared\\scripts\\sdp-tone.ps1 *)",
      "PowerShell(.\\sdp-shared\\scripts\\sdp-create-prompt.ps1 *)"
    ]
  }
}
```

Add one entry per script. Do not use wildcards to cover multiple scripts — each explicit entry
makes the permission visible in the SKILLS CHECK and the setup checklist verification step.

---

### How to Add

1. Read `.claude/settings.local.json` using the Read tool.
2. Locate or create `permissions.allow`.
3. Append: `"PowerShell(.\\sdp-shared\\scripts\\[script-name].ps1 *)"`.
4. Write the updated file using the Write tool.
5. Re-read the file to confirm the entry is present before closing the session.

---

### Verification

Read `.claude/settings.local.json` and check the `permissions.allow` array for the script's
entry. If absent:

1. Add it per the instructions above.
2. Note the addition in the session's Completed blockquote.
3. Do not test script invocation from a subagent until the entry is confirmed present —
   testing without the entry will fail silently and is not a useful signal.

---

## Bootstrap Integration

### Preflight Manifest (`SDP-Workspace-Setup.json`)

The hand-enumerated SKILLS CHECK (bootstrap doc steps 0b, Phase Gate step 1b) is superseded.
`sdp-preflight.ps1` now drives workspace validation from `SDP-Workspace-Setup.json`. Script
existence checks that were per-project concerns are entries in that manifest.

> **Current state:** `sdp-shared/` script existence checks have been removed from the
> per-project `SDP-Workspace-Setup.json` (they are solution-root concerns, not per-project) and
> now live in the solution-level preflight manifest, `SDP-Solution-Setup.json`, at the solution
> root. `sdp-preflight.ps1` resolves which manifest to read automatically from `-workspaceRoot`
> alone — no new script parameter — via `Resolve-ManifestFilename`: a `-workspaceRoot`
> containing a `sdp-project_*` path segment resolves to `SDP-Workspace-Setup.json`;
> `-workspaceRoot .` (the solution root itself) resolves to `SDP-Solution-Setup.json`.

When adding a new **project-scoped** script (one whose existence is a per-project precondition),
add a `file-exists` entry to `SDP-Workspace-Setup.json`:

```json
{ "type": "file-exists", "path": "sdp-shared/scripts/sdp-[name].ps1", "tier": "setup" }
```

When adding a new **solution-root** script (one whose existence is a solution-wide precondition,
not tied to any single project), add a `file-exists` entry to `SDP-Solution-Setup.json` at the
solution root instead:

```json
{ "type": "file-exists", "path": "sdp-shared/scripts/sdp-[name].ps1", "tier": "setup" }
```

### Setup Checklist in `SDP-Workspace-Setup.md`

Add the new script to the "Verify script permissions" item in the Setup Checklist. That item
lists every script in `sdp-shared/scripts/` that requires a permission entry.

---

## Creation Checklist

Complete every item in the session the script is created. Do not close the session until all
items are checked.

- [ ] Script created at `sdp-shared/scripts/sdp-[name].ps1`
- [ ] SYNOPSIS block present: `.SYNOPSIS`, `.PARAMETER` (one per param), `.NOTES` (stdout and exit contract)
- [ ] No changelog/history content added anywhere in the file — current behavior only
- [ ] Workspace root category determined: solution-root (self-resolves) or project-scoped (requires `-workspaceRoot .\[resolved_project]` from caller)
- [ ] Workspace root resolved via `Split-Path` pattern; fallback retained for test invocations
- [ ] Output contract implemented: utility (nothing to stdout) or agent-consumed (single JSON line)
- [ ] Error and exit contract implemented per table above
- [ ] File writes use `-Encoding UTF8` and specify `-Depth` on `ConvertTo-Json`
- [ ] Permission entry added to `.claude/settings.local.json` `permissions.allow`
- [ ] Permission entry verified by re-reading `.claude/settings.local.json`
- [ ] If project-scoped: `file-exists` entry added to `SDP-Workspace-Setup.json`; if solution-root: name added to `SDP-Workspace-Setup.md` setup checklist permission step
- [ ] If skill-invoked: skill Level 2 SKILL.md documents the script's expected stdout format
      and how the skill branches on `status`; project-scoped scripts note the `-workspaceRoot` requirement
- [ ] If this script handles steps from an existing skill: run `/sdp-evaluate-skill [parent-skill-name]`
      to append an updated evaluation entry confirming script coverage reaches the handoff boundary

---

## Worked Example: `sdp-tone.ps1`

**Type:** Non-blocking utility

**Annotated patterns:**

| Pattern | Location | Why |
|---------|----------|-----|
| Silent exit under all failures | Top of script and every `catch` | Tone is optional notification — it must never block or halt a workflow |
| Exact match before wildcard lookup | Assignment resolution | Prevents a skill with an explicit entry (but no tone configured for an event) from accidentally inheriting the wildcard tone; an exact match with no tone field is silent and does not fall through |
| `try/catch` around `Console.Beep` | Playback | Some environments (headless, non-Windows) don't support beep — swallow the exception; the script still exits 0 |
| Config read from workspace root | `$configPath` construction | Script lives two levels below workspace root; `Split-Path -Parent (Split-Path -Parent $PSScriptRoot)` resolves correctly regardless of invocation path |

**Permission entry:**
```json
"PowerShell(.\\sdp-shared\\scripts\\sdp-tone.ps1 *)"
```

---

## Worked Example: `sdp-create-prompt.ps1`

**Type:** Agent-consumed  
**Category:** Project-scoped — calling skill must pass `-workspaceRoot .\[resolved_project]`

**Annotated patterns:**

| Pattern | Location | Why |
|---------|----------|-----|
| `Write-Result` helper | Top of script | Single control point for stdout format — ensures the calling skill always receives a compact JSON line regardless of which exit path fires |
| Halted workflow → `exit 0` with `status = "halted"` | After state read | Halted is an expected workflow condition, not a script error; calling skill branches on status rather than treating it as a failure |
| Retry count read from tracking file | Before state read | Enables the skill to detect repeated script calls without the script needing external state — the tracking file is the script's own prior-run record |
| Temp file + tracking file pattern | Output | Temp file carries the full structured data for the skill to read; tracking file carries the pointer — the skill always knows which temp file is current, even across retries |
| `-Depth` on `ConvertTo-Json` | All JSON writes | Nested objects (section content, state snapshot, flags array) require explicit depth; PowerShell's default depth truncates nested objects to `"@{}"` |
| `-workspaceRoot` required from caller | `param()` block | The script reads and writes files inside the active project — it cannot self-resolve the correct path. The calling skill (`sdp-project-create-prompt`) resolves `[resolved_project]` via the three-level order and passes it as `-workspaceRoot .\[resolved_project]`. The `Split-Path` fallback is retained for test invocations only |

**Permission entry:**
```json
"PowerShell(.\\sdp-shared\\scripts\\sdp-create-prompt.ps1 *)"
```

---

## Worked Example: `sdp-github.ps1`

**Type:** Agent-consumed

The unified git/gh interaction script. A single `switch` dispatcher over a bounded set of named
subcommands (`status`, `head`, `push`, `ci-status`, `pr-create`, …) — never a `gh "$@"`
passthrough. Its consolidation value: git/gh run as child processes of the script, so only the
one `.ps1` needs allow-listing instead of N per-command permission entries.

**Annotated patterns:**

| Pattern | Location | Why |
|---------|----------|-----|
| `switch` on a positional `$Command` | Dispatch | One self-documenting surface; `help` / no-arg lists the catalog. The destructive tier (`push-force`, `pr-merge`, …) is recognized but returns a `not_implemented` sentinel — names reserved, zero irreversible capability in v1 |
| `Invoke-Git` / `Invoke-Gh` wrappers | Tool execution | Capture stdout, stderr, and exit code; never throw. A non-zero git/gh exit or a thrown exception is surfaced in the JSON envelope (`ok:false`, `status:"error"`, `exitCode`, `stderr`) — no unhandled tool failure escapes |
| Uniform JSON envelope | `Write-Result` | Every path emits exactly one compact line: `ok`, `command`, `status`, `error` + command-specific fields. Callers branch on `status` (CI color, PR state); the exit code only distinguishes "script ran" from "script failed to run" |
| `-WhatIf` plan mode | Top of script | Resolves the intended git/gh argv to JSON without executing — a dry-run channel and the primary Pester hook (the `sdp-tone.ps1 -whatIf` precedent). Single-vector plans are normalized so PowerShell's `@(,@(...))` unrolling does not flatten them |
| Exit 0 on `red` CI | Exit contract | A red `ci-status` is a *successful observation*, not a script error — exit 0, semantics live in `status`. Exit 1 only when the script itself could not complete the operation (mirrors the `sdp-create-prompt.ps1` halted-exits-0 precedent) |
| ASCII-only source | Whole file | Windows PowerShell 5.1 parses a no-BOM `.ps1` as the ANSI codepage; a literal em-dash in a string corrupts and breaks parsing. Use ASCII hyphens in source strings (the `sdp-create-prompt.ps1` encoding lesson) |
| `ci` config block read | `Get-CiConfig` | `ci-status` reads `SDP-Config.json` `ci.enabled`; disabled/absent → `no_ci` (local-green fallback) so projects with no CI incur no gate |

**Permission entry:**
```json
"PowerShell(.\\sdp-shared\\scripts\\sdp-github.ps1 *)"
```

---

## Worked Example: `sdp-preflight.ps1`

**Type:** Agent-consumed  
**Category:** Project-scoped — calling skill must pass `-workspaceRoot .\[resolved_project]`

The manifest-driven workspace check engine. Instead of the agent making dozens of per-session
file-existence checks (and the canonical inventory being hand-copied across the bootstrap, the
coordinator skill, and the setup checklist — a divergence generator), one call validates every
deterministic precondition from a single declarative manifest (`SDP-Workspace-Setup.json`) and
emits a uniform envelope. A new *kind* of check adds one `switch` arm + one Pester case; new
*instances* of an existing type are data-only edits to the manifest, with no script change. That
is the design's maintenance contract.

**Annotated patterns:**

| Pattern | Location | Why |
|---------|----------|-----|
| Declarative manifest + generic engine | `SDP-Workspace-Setup.json` + the `Test-Check` `switch` | The check inventory lives as data, not code. The script is a fixed engine; the per-project check list is the manifest. Adding a check is a data edit, not a code edit |
| One non-throwing validator per `type` | `Test-FileExists`, `Test-SkillPair`, `Test-JsonValue`, … | Each validator returns `@{ ok; detail }`; the `Test-Check` dispatcher wraps every call in try/catch so an unexpected condition (e.g. a malformed target JSON) surfaces as `ok:false` with a detail, never an unhandled throw |
| Tier staleness gate, policy/facts split by owner | `Get-Policy` (SDP-Config.json) + `Get-StateInfo` (state.json) | Policy (tier intervals) is user-owned and only read; facts (last-run timestamps) are machine-written. The script's *only* write is the per-tier timestamp — `SDP-Config.json` is never mutated |
| Timestamp advances only on a clean tier pass | `Write-TierTimestamp`, gated by `$tierAllPass` | A tier with any failure leaves its timestamp unchanged, so the next run re-checks it. `Get-Date` is the clock (the agent has no authoritative clock — that is why the comparison lives in the script) |
| Capture-then-wrap for `ConvertFrom-Json` arrays | Manifest load | Windows PowerShell 5.1 emits a multi-element `ConvertFrom-Json` array as a *single* pipeline object; `@(Get-Content \| ConvertFrom-Json)` double-wraps. Assign to a variable first, then `@($var)`, for a correctly flat array |
| Exit 0 on found failures | Exit contract | A failed check is a *successful observation* — exit 0, the caller branches on `ok` / `failures`. Exit 1 only on an operational error (manifest missing/unparseable, state write failed). Mirrors `sdp-github.ps1` |
| `-WhatIf` plan mode | Top-of-run, after the gate decision | Resolves the check list + the due-tier decision to JSON without reading the target files or writing the timestamp — dry-run channel and the primary Pester hook |
| UTF-8 no-BOM state write, ASCII source | `Write-TierTimestamp` / whole file | The `sdp-create-prompt.ps1` encoding-hardening lesson — a BOM or ANSI round-trip corrupts the file for other readers; ASCII source parses safely under 5.1 |

The skill (`sdp-project-coordinator`) decides what to do with failures (halt per the Halt Behavior
Contract, play the halt tone, write `workflow_status`); the script does not halt the workflow or
mutate `workflow_status`. SUPERPOWERS stays an agent step — `/plugin list` is a harness command,
not a filesystem fact, so the script cannot truthfully confirm it.

**Permission entry:**
```json
"PowerShell(.\\sdp-shared\\scripts\\sdp-preflight.ps1 *)"
```

---

## Worked Example: `sdp-report-log-loop-metrics.ps1`

**Type:** Agent-consumed

Parses a solution-root `loop-metrics-*.jsonl` tone/action log and computes every part of an SDP
loop metrics report that is derivable from the jsonl alone via a fixed, dataset-agnostic rule —
the six-bucket time accounting, halt/halt-resolution/off-hours/user-interrupted interval tables,
both SVG time-flow bars, the task-by-task outcomes table, and the loop-fire breakdown. Narrative
content (root-cause analysis, gate-finding materiality, "next step" recommendations) is
explicitly out of scope — those require reading `state.json`, a phase document, or skill source,
none of which this script touches. Invoked by the `sdp-report-log-loop-metrics` skill, which supplies
the parts the script cannot.

**Annotated patterns:**

| Pattern | Location | Why |
|---------|----------|-----|
| One JSON object per line, not a single array | Load step | Each `loop-metrics-*.jsonl` file is append-only — each line is parsed independently with a `try/catch` per line so one malformed line does not fail the whole read |
| Canonical timeline built once, every total derived from it | `Build-CanonicalTimeline` | Independently re-deriving the "same" duration in more than one place is how a pairing/overlap bug hides behind an always-balancing residual bucket — building one non-overlapping partition of the full period and summing from it is the only way a discrepancy can't silently vanish into the Idle residual |
| Orphan-detection scoped to the four productive skills only | Skill start/end pairing | Applying it to bookkeeping skills (`sdp-project-state-loop`, `sdp-project-run-prompt`) that fire on routine cadence mistook normal metrics-log write-failure noise for genuine user interruption — User-interrupted is only meaningful for a skill representing real work being cut off |
| Two-pass halt-window detection (outer bound, then true resolution) | Halt windows | `state.json`'s `halted` flag only becomes observable in the log the next time some action-log entry happens to be written, which can lag well behind the real fix; the true resolution moment is the end of the last `sdp-project-coordinator` interval that started inside the outer bound |
| Skill-role aliases loaded from `script-support/sdp-report-log-loop-metrics-skills.json`, every event's `skillName` normalized to its canonical current name once, immediately after parsing | Config load (top of script) + normalization loop, before any interval/bucket logic | Hardcoding only the current literal name for each productive role (`$productiveSkills = @("sdp-project-worker", ...)`) meant re-running the report against a date from *before* a skill's rename silently dropped that skill's old-named tone events out of Productive-time bucketing (reclassified as Idle), with no error. Each role's config entry carries every name it has ever been logged under (oldest first, current last); normalizing once at load time means a historical event and a current-named event for the same role merge into one canonical bucket instead of one silently not matching. A future rename is "append a name to the JSON," not a code change |
| ASCII arrow placeholder in JSON, real glyph substituted by the skill | Title-date formatting | Mirrors the `sdp-create-prompt.ps1` / `sdp-github.ps1` ASCII-source-safe lesson — the script stays ASCII-only; the calling skill substitutes the Unicode arrow when writing markdown |
| Raw stdout JSON forbidden to be hand-corrected by the caller | `SDP-Script-Authoring.md` § Script vs. Skill precedent, enforced in the calling skill's SKILL.md | If a figure looks wrong, that's a script bug to fix and re-run — not something the calling skill patches around for one report |

**Permission entry:**
```json
"PowerShell(./sdp-shared/scripts/sdp-report-log-loop-metrics.ps1 *)"
```

---

## Worked Example: `sdp-report-log-hook-metrics.ps1`

**Type:** Agent-consumed

Companion to `sdp-report-log-loop-metrics.ps1`, built from the same template but for a
structurally different log: `hook-log-*.jsonl` is raw, already-complete per-tool-call telemetry
(no start/end pairing, no halt-window inference), so this script has no breadcrumb machinery — it
is pure grouping, counting, and (as of 2026-07-17) chart generation. Computes totals as two
composition bars (Pre/Post; subagent/main-session), a level-breakdown bar chart, a stacked
tool-usage bar chart (Pre/Post segments), a `session_id`-grouped Gantt-style timeline with
`agent_id` sub-span overlays, and a work-item breakdown bar chart. Invoked by the
`sdp-report-log-hook-metrics` skill, which supplies only a short narrative Summary — there are no
judgment-requiring breadcrumbs to resolve, unlike the loop-metrics report. Note the naming split:
the *script/skill/report* family is `hook-metrics` (matching the `loop-metrics` sibling's
convention), while the *source data* it reads stays `hook-log-*.jsonl` / `hook-logs/` — the
pre-existing writer script's own naming, unrelated to and unchanged by this report's naming.

Every table this report originally produced (2026-07-11 through 2026-07-17) is now a chart —
user direction 2026-07-17: "converting tables of data to charts and graphs." This is the one
report in the family that departs from the GFM-tables-only convention the other three still
follow; see `SDP-Skill-Authoring.md`/this script's own `.NOTES` for why a single signature hue
(reused from the combined report's hook-log color) was sufficient instead of a distinct
categorical color per row.

**Annotated patterns:**

| Pattern | Location | Why |
|---------|----------|-----|
| One JSON object per line, unparseable/timestamp-less lines counted not fabricated | Load step | Same append-only-log parsing discipline as `sdp-report-log-loop-metrics.ps1` — `anomalies.unparseableLineCount` surfaces the count rather than silently dropping or erroring on one bad line |
| `Test-Truncated` checks for a `_truncated` property rather than assuming shape | Truncation counting | `tool_input`/`tool_output` are arbitrary re-serialized JSON from `sdp-hook-log.ps1` — only a truncated field has the `_truncated`/`value` wrapper shape; every other field is checked structurally, not assumed |
| `(none)` bucket always sorted last regardless of count, and colored muted gray not the signature blue | Work-item breakdown, Level breakdown | An unattributed bucket (best-effort `work_item` resolution failed, or an unrecognized level) must never read as "just another category" by chart color or position — same rule the workflow-log/combined report companions use for their own `(none)` buckets |
| One signature hue throughout, not a distinct color per row | Every chart except the two composition bars | This report is entirely single-source (`hook-log`) — unlike Level/Role in the combined report, Tool/Work-Item/Session identity sets are unbounded, so a distinct categorical hue per row would not scale and would add no information the row's own direct label doesn't already carry |
| Session/agent Gantt timeline reuses `sdp-report-log-combined-metrics.ps1`'s Rule 1 technique exactly, including labels-on-the-right | `New-SessionGanttSvg` | That script's own alignment bug (labels on the left shifting the chart's own time-origin) was already found and fixed once — this script starts from the corrected version rather than repeating the mistake |
| Truncation surfaced as a short text list, not a fifth chart dimension | Tool Usage section | Truncation applies to only a minority of tools in most runs; a stacked segment that is zero for most rows would be visual noise, so it is called out by name instead |

**Permission entry:**
```json
"PowerShell(./sdp-shared/scripts/sdp-report-log-hook-metrics.ps1 *)"
```

---

## Worked Example: `sdp-report-log-workflow-metrics.ps1`

**Type:** Agent-consumed

Companion to `sdp-report-log-loop-metrics.ps1`, for the third sibling log:
`workflow-log-*.jsonl` is an already-semantic narrative (`reason` is free text authored at
logging time by the calling skill/script) — the report's main value is reproducing it as a
well-organized, filterable table, not resolving ambiguity the way loop-metrics does. Computes
trigger/role/outcome breakdowns, a full chronological events table, a Concerning Events table
(fixed candidate filter: outcome in `DIAGNOSIS_BLOCKED`/`GATE_BLOCKED`/`REJECTED`, or a trigger
starting with `halt.`), and work-item/phase activity tables. Invoked by the
`sdp-report-log-workflow-metrics` skill, which supplies a short narrative Summary and per-row
commentary on any Concerning Events found — using only what each row's own fields state. Same
naming split as `sdp-report-log-hook-metrics.ps1`: report family is `workflow-metrics`, source
data stays `workflow-log-*.jsonl` / `workflow-logs/`.

**Annotated patterns:**

| Pattern | Location | Why |
|---------|----------|-----|
| `Format-TableCell` escapes `\|` and collapses newlines on every free-text field | Table row builders | `reason`/`detail` are free text supplied by the logging caller (e.g. a phase-gate rejection narrative) and can legitimately contain characters that break a markdown table — every field that reaches a `*TableMarkdown` string is sanitized first, unlike the hook-log report companion where the equivalent fields are machine-generated identifiers |
| Concerning Events is a fixed filter, documented as a candidate list not a verdict | `$concerningOutcomes` + trigger-prefix check, and the script's own Methodology text | Keeps the script's output honest about what it actually determined — "worth a look," not "confirmed a problem" — so the calling skill's Constraints can forbid treating a row as diagnosed without re-deriving anything |
| "Final Outcome" is the last event with a *non-null* outcome, not simply the grouping's last event | Work Item Activity | A work item's chronologically last log entry is often an outcome-less dispatch-decision line; naively taking "last row's outcome" would silently show blank for items that actually resolved cleanly earlier in the sequence |
| `(none)` bucket always sorted last regardless of count | Role breakdown | Same rule as the hook-log report companion's work-item breakdown — an unattributed bucket must never read as the "top" row by position |

**Permission entry:**
```json
"PowerShell(./sdp-shared/scripts/sdp-report-log-workflow-metrics.ps1 *)"
```

---

## Worked Example: `sdp-report-logs-combine.ps1`

**Type:** Agent-consumed

Data-preparation companion to the three report scripts above, not a report itself: merges one
calendar day's `loop-metrics-*.jsonl`/`hook-log-*.jsonl`/`workflow-log-*.jsonl` into a single
normalized `combined-log-yyyyMMdd.jsonl` under a new sibling folder, `combined-logs/`. Unlike its
three source logs, this output is not passively accumulated by a hook or a dispatch-time call —
it is created/overwritten only when a user explicitly invokes `sdp-report-logs-combine` for a given day,
which is why it is a regenerable derived artifact (`Set-Content`-style full overwrite) rather than
an append-only log.

**Annotated patterns:**

| Pattern | Location | Why |
|---------|----------|-----|
| One common envelope shape, three independent per-source mapping functions | The three `foreach` loops over `$loopResult.entries`/`$hookResult.entries`/`$workflowResult.entries` | Each source has its own field names and, in loop-metrics' case, three distinct sub-shapes (`channel=="skill"`, `channel=="event"`, `.action` present) — normalizing each independently into one target shape (`timestamp`/`source`/`category`/`role`/`work_item`/`phase`/`event_name`/`outcome`/`reason`/`detail`/`raw`) is clearer and safer than one shared function branching internally on shape |
| `raw` field preserves the complete original entry on every envelope | `New-Envelope` | The merge must be lossless regardless of how well the normalized fields capture each source's meaning — a normalized field being `null` (e.g. hook-log has no `role`) never means the original data is gone, only that this source has no equivalent |
| Missing source file is not an error; all three missing is | Source-existence checks before the `$combined.Count -eq 0` guard | A source log not yet existing for a given day (e.g. no hook-log activity yet) is a normal, expected state — this script's job is to combine what exists, not to require all three |
| Full overwrite (`WriteAllText`), not append | Output write | The combined file is a derived, regenerable artifact keyed by date, not a source-of-truth log — re-running for the same day should recompute cleanly, not accumulate duplicate copies of the same merged data |

**Permission entry:**
```json
"PowerShell(./sdp-shared/scripts/sdp-report-logs-combine.ps1 *)"
```

---

## Worked Example: `sdp-report-log-combined-metrics.ps1`

**Type:** Agent-consumed

Fourth report script in the family, reading the already-normalized output of `sdp-report-logs-combine.ps1`
rather than a raw source log — every field it consumes (`source`, `category`, `role`, `work_item`,
`phase`, `event_name`, `outcome`, `reason`, `detail`) already traces to that script's own fixed
mapping rules, so this script does no shape-specific branching of its own except the Rule 1
timeline (below), which reads `raw.session_id`/`raw.agent_id` directly since only `hook-log`
carries those fields. Computes source/category/role/outcome/event-name breakdowns, a Concerning
Events table (same fixed filter as `sdp-report-log-workflow-metrics.ps1`, matched against
`event_name` instead of a raw `trigger` field so loop-metrics' own halt-tone triggers are caught
too), work-item activity across all three original sources, and three timeline SVGs sharing one
time axis: a session/agent Gantt-style timeline colored by source, and two binned stacked
histograms colored by event category and role respectively. (User direction, 2026-07-17: an
earlier version of this script instead produced a full chronological events table — removed
after user feedback that a 3800+-row table added no readable value at `hook-log`'s typical event
volume; the three timelines replace it.)

**Annotated patterns:**

| Pattern | Location | Why |
|---------|----------|-----|
| No re-interpretation of `raw` — only the envelope's own top-level fields are read, except Rule 1 | Whole script; `$sessionGroups`/`$agentGroups` are the one exception | Reading into `raw` elsewhere would re-introduce the three-source branching `sdp-report-logs-combine.ps1` already resolved once; Rule 1 is a deliberate, documented exception because `session_id`/`agent_id` have no equivalent in the normalized envelope at all |
| Session/agent relationship verified against real data before coding, not assumed from field names | Script `.NOTES` | Confirmed directly (2026-07-17): every `agent_id` maps to exactly one `session_id` with a contiguous own timespan, none spanning multiple sessions — the Gantt nesting logic depends on this and would silently mis-render if it didn't hold |
| Meter pattern (light track + dark fill, same hue) for session vs. subagent-active time | `New-SessionAgentTimelineSvg` | Reuses the dataviz skill's own documented "state reads across the whole bar" convention rather than inventing a new visual technique — the darker overlay is *additive* on top of the lighter track, not a separate hue, so subagent-active time reads as "more of the same source," not "a different thing happened" |
| Fixed bin COUNT, not fixed bin duration | `$timelineBinCount` (40) used by both Rule 2 and Rule 3 | User direction, 2026-07-17: a short report period must not collapse to a handful of columns under a fixed duration like "15 minutes per bin" — dividing the actual span by a constant column count gives every period the same resolution |
| "Tool" (`hook-event`) split into two shades of one hue rather than two unrelated categorical colors | `$rule2ColorMap` (`tool-pre`/`tool-post`) | Pre/Post are the same underlying category (a tool call), not two different kinds of activity — shading communicates "same thing, two directions" the way an unrelated hue pair would not |
| Concerning Events filter matches `event_name` instead of a `trigger` field | `$concerningEvents` filter | `event_name` is the unified label populated for every source (including loop-metrics' own `workflow-tone` category, whose `event_name` is the raw trigger) — matching against it, rather than a source-specific field, is what makes the filter apply uniformly across all three origins |
| `Sources` column in Work Item Activity | `$workItemActivity` | Shows which of the three original logs actually contributed a row for that work item this period — e.g. a work item with only a `hook-log` entry had tool-call activity logged but no explicit dispatch action or workflow event that period |

**Permission entry:**
```json
"PowerShell(./sdp-shared/scripts/sdp-report-log-combined-metrics.ps1 *)"
```

---

## Worked Example: `sdp-gate-review-gpg-check.ps1`

**Type:** Agent-consumed
**Category:** Project-scoped, with a mixed-root exception (see Workspace Root Resolution above)

Deterministic backend for `sdp-project-gate-review` Step 1 (GPG CHECK): reads `gpg_version` from the
active project's `state.json`, resolves the GPG standards file, and halts (writing
`workflow_status`/`halt_reason` per the Halt Behavior Contract) if it is missing.

**Annotated patterns:**

| Pattern | Location | Why |
|---------|----------|-----|
| Independent `$solutionRoot`, not derived from `$workspaceRoot` | Top of script, right after the `$workspaceRoot` fallback block | `standards/` is a solution-level resource never duplicated per project. `$workspaceRoot` is `[resolved_project]` — one directory below the solution root in any multi-project solution — so joining `standards/...` against it produced a false "file missing" halt even when the file genuinely existed one level up. Fixed 2026-07-11; reproduced against a real multi-project layout before and after. See the Mixed-root scripts note above — this is the reference case |
| `gpg_version` read from the caller's (project) `state.json`, file resolved against the solution root | Between the two `$...Root` variables | The *version string* is a per-project setting (which GPG version this project targets); the *file it names* lives at the solution root. Two different roots for two different reasons, in the same script — do not collapse them into one variable |
| Halt writes `state.json` only on the one designated failure path | `if (-not $gpgFileExists)` block | Every other error (`state.json` missing/unparseable, `gpg_version` absent) is an operational error (`exit 1`), not a Halt Behavior Contract case — only a confirmed missing/mismatched GPG file halts the workflow |
| `Set-JsonFileWithRetry` — 3 attempts with backoff | State write | A transient file-lock (e.g. a concurrent read by another session) must not corrupt or lose the halt write; retries before giving up |

**Permission entry:**
```json
"PowerShell(.\\sdp-shared\\scripts\\sdp-gate-review-gpg-check.ps1 *)"
```

---

## Worked Example: `sdp-create-banner.ps1`

**Type:** Agent-consumed

Full owner of `.claude/skills/sdp-create-banner/SKILL.md`'s procedure — an L1-only,
fully-scriptable skill (see `SDP-Skill-Authoring.md`'s Level-1-only exception). Parses the
`icon=`/`row=`/`row:` invocation-argument grammar and returns the fully assembled, border-wrapped
banner text as a single JSON field; the calling skill's only remaining step is printing that text
verbatim in its own chat turn (a script's stdout is a tool result, not assistant message text, so
this last step cannot itself be scripted).

**Annotated patterns:**

| Pattern | Location | Why |
|---------|----------|-----|
| Trigger-position tokenizing, not line-splitting | `Step 1: Tokenize` | The slash-command channel flattens newlines to spaces, so `icon=`/`row=`/`row:` directives can appear anywhere in one line, in any order — parsing must scan for trigger tokens by position, not assume one directive per line |
| `Get-TextElements` (grapheme-cluster enumeration) | Top of script | Several registered icon glyphs are surrogate-pair or base+variation-selector emoji; raw `.Length`/`.Substring()` would miscount or split a glyph mid-codepoint. `StringInfo`'s text-element enumerator treats each as the single unit the row-width math assumes |
| Ordinary string padding, no mask-overlay | `New-BannerRow` | The hand-authored (pre-script) version used a `œ`-character mask-overlay technique specifically to help an LLM avoid manual counting errors: a script has no such failure mode and computes exact padding with `.PadRight`-equivalent arithmetic directly |
| Icon registry loaded from `script-support/`, a sibling folder to the script itself | Icon Registry load | Runtime data the script consumes internally — the calling skill's L1 shim never reads it, which is the entire point of the L1-only conversion (context-cost elimination, not tool-call elimination) |
| `banner` returned directly in the JSON envelope, no file write | `Write-Result` | A file-then-Read round trip would cost the identical context tokens plus an extra tool call, for zero benefit — direct-return was the explicit design decision recorded in the skill's own eval |

**Permission entry:**
```json
"PowerShell(.\\sdp-shared\\scripts\\sdp-create-banner.ps1 *)"
```

---

## Worked Example: `sdp-hook-log.ps1`

**Type:** Non-blocking utility — hook target, not agent-invoked

Registered as an async `PreToolUse`/`PostToolUse` command hook (no matcher — fires for every tool
call) in `.claude/settings.local.json`. The mechanical half of SDP's two-channel logging system;
`sdp-workflow-log.ps1` (below) is the semantic/narrative half. Reads the hook event payload from
stdin, not from parameters — this is a hook target, never invoked directly by a skill.

**Annotated patterns:**

| Pattern | Location | Why |
|---------|----------|-----|
| Async hook, silent exit under every failure | `.NOTES`, every early `exit 0` | Async hooks have their exit code and stdout ignored by Claude Code — confirmed against the Claude Code hooks reference before writing this script — so this script can never block, deny, or influence the tool call it observes; it is a pure side-effect logger |
| Per-tool gating via external config, not hardcoded | `sdp-hook-log-tools.json` read | Which tools log, in which direction (Pre/Post), at what level, and whether subagent-originated calls count is data the config owns — keeps the logging policy editable without touching the script |
| `work_item` resolved best-effort, failure never blocks the write | `try { ... } catch { }` around the resolution block | Reads `SDP-Solution.json` → active project's `state.json` → `active_work_item`; any missing link along that chain yields `null`, not a failed log write — this is the same `work_item` key `sdp-workflow-log.ps1` uses for cross-log correlation |
| Field truncation with a `_truncated` marker | `Get-CompactField` | A single large `tool_output` (e.g. a Bash build log) must not blow out the daily file's manageability; the marker tells a report reader the field was clipped rather than silently losing data |
| One file per local calendar day, sweep on first write | Log path construction, `if (-not (Test-Path $logPath))` block | Matches `loop-logs/`'s and `workflow-log.ps1`'s established rotation shape — local time (not UTC) so a report author never needs to translate a date; the retention sweep runs exactly once per day (the first firing), not on every call |

**Permission entry:**
```json
"PowerShell(./sdp-shared/scripts/sdp-hook-log.ps1 *)"
```
Required even though a skill never calls this script via the PowerShell tool directly — the
hook's own `command: "powershell.exe"` invocation is still gated by the same allow-list
mechanism. In addition to the permission entry, this script also needs the `PreToolUse`/
`PostToolUse` hook registration itself in `.claude/settings.local.json`'s `hooks` block (no
matcher, `"async": true`) — see `SDP-Workspace-Setup.md`'s Setup Checklist for the exact JSON.

---

## Worked Example: `sdp-workflow-log.ps1`

**Type:** Non-blocking utility — agent-invoked (directly, not via a hook)

The narrative counterpart to `sdp-hook-log.ps1`: called directly by `sdp-project-coordinator`,
`sdp-project-worker`, `sdp-project-reviewer`, and internally by `sdp-gate-review-finalize.ps1` at points a hook
cannot reach, since a hook only sees `tool_name`/`tool_input`/`tool_output` and cannot capture
*why* a decision was made.

**Annotated patterns:**

| Pattern | Location | Why |
|---------|----------|-----|
| Silent no-op on missing `-trigger` or `-reason` | Top of script, before any file I/O | Non-blocking utility — a caller that forgets a required field must never halt the actual workflow; the log entry is simply not written |
| Shared trigger vocabulary with `SDP-Tones.json` | `.PARAMETER trigger` | Reuses the same named-event taxonomy (`gate.blocked`, `halt.no_progress`, etc.) as the tone system's `events` table where applicable — one shared vocabulary instead of two independently-drifting ones |
| Correlates with `hook-logs/` via `work_item`, not `session_id` | `.NOTES` | Claude Code does not expose a generic session identifier to an agent-invoked script (confirmed against the Claude Code docs before this script was written); SDP's own Role Separation invariant (one role, one work item, per session) makes `work_item` an adequate join key regardless |
| Same rotation/retention shape as `sdp-hook-log.ps1` | Log path construction | `workflow-log-<local yyyyMMdd>.jsonl`, 190-day sweep on first write of each new day — sibling folders, sibling behavior, so a report author reads both the same way |

**Permission entry:**
```json
"PowerShell(.\\sdp-shared\\scripts\\sdp-workflow-log.ps1 *)"
```
