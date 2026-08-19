<img src="images/SDP_DocsLogo_WithText_0700x0163.png" alt="SDP Logo" width="375">

# AI-Assisted Development Workflow — Workspace Setup Reference

| Field | Value |
|-------|-------|
| **Companion doc** | `SDP_Sapient-Driven-Principles_vN.N.N.md` |
| **Updated** | 2026-06-23 |
| **File** | `SDP-Workspace-Setup.md` |

**Purpose:** Complete workspace setup procedure, all file templates, and bootstrap maintenance
notes. Load this file explicitly when setting up a new workspace. Not loaded automatically by
`sdp-project-read-docs` — add to `SDP-Document-List.json` with `"includeInReadDocs": false`.

---

## Tooling Prerequisites

SDP drives its automation through PowerShell scripts under `sdp-shared/scripts/`
(`sdp-tone.ps1`, `sdp-create-prompt.ps1`), invoked by the sdp- skills via the PowerShell tool.
The following tooling must be present before first dispatch.

### PowerShell (required)

- **Windows PowerShell 5.1** (ships with Windows) **or PowerShell 7+** (`pwsh`).
- Scripts are authored **ASCII-safe** — non-ASCII characters (e.g. em-dashes) are emitted from
  code points such as `[char]0x2014`, never written as source literals. This is deliberate:
  Windows PowerShell 5.1 decodes a `.ps1` that has no byte-order mark (BOM) using the system
  ANSI codepage, which corrupts multibyte characters in the source and can break parsing. Keep
  new scripts ASCII-only (or save them with a UTF-8 BOM) so they parse under 5.1.
- Files whose first bytes are parsed positionally must be written **UTF-8 *without* BOM** —
  notably `sdp-docs/00_prompt.txt`, whose first line is the `[sdp-prompt …]` sentinel read by
  `sdp-project-state-loop`. A BOM ahead of the sentinel breaks detection and triggers a spurious
  GENERATE. The script writes this file via `[System.IO.File]::WriteAllText(..., UTF8Encoding $false)`.
- **Validated on Windows.** Cross-platform use (macOS/Linux via `pwsh`) is **not yet validated** —
  the current scripts use Windows-style path separators in `Join-Path` literals. See Bootstrap
  Open Items before attempting a non-Windows host.

### git (required)

- Required by the **Superpowers plugin** itself — it errors on a project with no git repository/
  executable available — and by `sdp-shared/scripts/sdp-github.ps1`, which shells out to `git`
  directly (status, push, pull, checkout) with no availability check of its own before this
  addition.
- [Install Git](https://git-scm.com/downloads). Confirm with `git --version`.
- Validated automatically by `sdp-preflight.ps1` (PREFLIGHT CHECK) via a `command-available` check.

### Python (anticipated — not used by SDP)

- No SDP script or skill uses Python today; SDP's own automation is 100% PowerShell.
- Install it anyway. On at least one tested workspace, an agent invoked Python to compute
  banner mask-padding math while rendering an `sdp-create-banner`/`sdp-initialize-sdp` banner —
  despite those procedures' explicit instruction that no script or tool call may generate or
  verify a banner row (see the Body Row Construction section of `sdp-initialize-sdp/SKILL.md`).
  That is a deviation from the documented procedure, not an intended dependency — the correct
  fix is the agent following the existing no-tool-call instruction. But since the deviation has
  recurred, Python is listed here defensively so a missing interpreter doesn't turn one problem
  into two.
- Not validated by `sdp-preflight.ps1` — documentation only, by design; this is anticipated
  coverage for undesired agent behavior, not a real SDP-internal dependency to enforce.

### Pester 5+ (required only to run the script test suite)

- The script unit tests in `sdp-shared/scripts/tests/` (e.g. `sdp-create-prompt.Tests.ps1`)
  require **Pester 5.0 or later**. The version bundled with Windows is **Pester 3.4**, which is
  **not** sufficient — v3 uses different assertion syntax (`Should Be` vs `Should -Be`) and
  different scoping, and will fail to run the suite.
- Install (current user, no admin required):
  ```powershell
  Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck -MinimumVersion 5.0.0
  ```
- Run (import v5 explicitly so the built-in 3.4 is not auto-loaded):
  ```powershell
  Import-Module Pester -MinimumVersion 5.0 -Force
  Invoke-Pester -Path sdp-shared/scripts/tests/sdp-create-prompt.Tests.ps1 -Output Detailed
  ```
- This is a **developer/contributor** prerequisite for running the script tests. It is **not**
  required to run the SDP workflow itself.

---

## Workspace Setup

> **Agent:** Execute this section when setting up a new workspace. Before creating any files or
> folders, complete Step 0 — collect all required inputs (solution name, synopsis via Q1–Q3,
> project types via Q4, development environment via Q5), present the complete setup plan, and
> wait for explicit user confirmation. Then execute the remaining steps in order. Replace
> `[PROJECT]` with the user-provided project name and `[SolutionName]` with the confirmed
> solution name throughout.

### Solution Root Folder Structure

Claude Code is opened at the solution root. The solution root contains all shared SDP
infrastructure, the solution-level workflow folders, and the `sdp-project_*` workflow
folders alongside the actual code project folders.

```
[Solution Root]/
│
├── README.md                                ← solution-level readme; synopsis, projects table, session start guide
├── [SolutionName].sln                       ← Visual Studio / Rider solution file (if applicable — created at setup)
├── [SolutionName].code-workspace            ← VS Code workspace file (if applicable — created at setup)
│
├── .claude/                                 ← Level 1 skills + settings.local.json (shared)
│   └── skills/
│       └── [skill-name]/SKILL.md
│
├── .sdp-solution-workflow/                  ← solution-level machine-written state
│   ├── state.json
│   ├── registry.md
│   ├── dependencies.md                      ← dependency-ledger narrative; empty stub at setup, entries appended at Phase 7 decomposition
│   ├── dependencies.json                    ← dependency-ledger machine index; `[]` stub at setup, edges appended at Phase 7 decomposition
│   ├── logging/
│   │   ├── loop-logs/                       ← one file per calendar day; gitignored
│   │   │   └── loop-metrics-yyyyMMdd.jsonl  ← append-only fire/tone log (sdp-project-state-loop + sdp-tone.ps1); rotates purely by date, independent of any workflow action; created on first write of the day
│   │   ├── hook-logs/                       ← one file per LOCAL calendar day; gitignored
│   │   │   └── hook-log-yyyyMMdd.jsonl      ← append-only PreToolUse/PostToolUse hook log (sdp-hook-log.ps1), gated per-tool by sdp-hook-log-tools.json; local date deliberately, not UTC, so report authors never translate; retention sweep runs on first write of each new day
│   │   ├── workflow-logs/                   ← one file per LOCAL calendar day; gitignored
│   │   │   └── workflow-log-yyyyMMdd.jsonl  ← append-only semantic workflow-event log (sdp-workflow-log.ps1) — the narrative/reasoning half, called directly by sdp-project-coordinator/sdp-project-worker/sdp-project-reviewer and internally by sdp-gate-review-finalize.ps1; correlates with hook-logs/ by work_item, not session_id; same retention-sweep convention
│   │   └── combined-logs/                   ← one file per calendar day; gitignored; not passively accumulated like its three siblings above — created/overwritten only when sdp-report-logs-combine is explicitly invoked for that day
│   │       └── combined-log-yyyyMMdd.jsonl  ← normalized merge of that day's loop-metrics/hook-log/workflow-log entries into one common envelope shape (sdp-report-logs-combine.ps1); read by sdp-report-log-combined-metrics
│   └── sessions/
│       └── session-NNN.md
│
├── sdp-shared/                              ← SDP framework: Level 2 skills + scripts (shared)
│   ├── ai-skills/                           ← Level 2 skill procedures — one subfolder per skill
│   │   └── [skill-name]/SKILL.md
│   ├── scripts/                             ← deterministic scripts invoked by skills or hooks; each requires a permissions.allow entry in .claude/settings.local.json
│   │   ├── sdp-tone.ps1
│   │   ├── sdp-create-prompt.ps1
│   │   ├── sdp-github.ps1
│   │   ├── sdp-preflight.ps1
│   │   ├── sdp-claude-new-terminal.ps1
│   │   ├── sdp-solution-coordinator.ps1
│   │   ├── sdp-solution-reviewer.ps1
│   │   ├── sdp-solution-create-prompt.ps1
│   │   ├── sdp-gate-review-gpg-check.ps1    ← project-scoped only, no -scope parameter
│   │   ├── sdp-gate-review-setup.ps1        ← project-scoped only, no -scope parameter
│   │   ├── sdp-gate-review-finalize.ps1     ← project-scoped only, no -scope parameter
│   │   ├── sdp-solution-phase-gate-review-gpg-check.ps1  ← solution-scoped companion; self-resolving, no -workspaceRoot
│   │   ├── sdp-solution-phase-gate-review-setup.ps1      ← solution-scoped companion; self-resolving, no -workspaceRoot
│   │   ├── sdp-solution-phase-gate-review-finalize.ps1   ← solution-scoped companion; self-resolving, no -workspaceRoot
│   │   ├── sdp-report-log-loop-metrics.ps1
│   │   ├── sdp-report-log-hook-metrics.ps1
│   │   ├── sdp-report-log-workflow-metrics.ps1
│   │   ├── sdp-report-logs-combine.ps1
│   │   ├── sdp-report-log-combined-metrics.ps1
│   │   ├── sdp-create-banner.ps1
│   │   ├── sdp-hook-log.ps1                 ← PreToolUse/PostToolUse hook target; not invoked by any skill
│   │   ├── sdp-workflow-log.ps1             ← semantic workflow-event log; invoked by sdp-project-coordinator/sdp-project-worker/sdp-project-reviewer directly and by sdp-gate-review-finalize.ps1 internally
│   │   └── script-support/                 ← data files read internally by sdp-shared/scripts/*.ps1, resolved as a sibling folder off $PSScriptRoot
│   │       ├── SDP-Tones.json               ← tone/tune config read by sdp-tone.ps1 (shared)
│   │       ├── sdp-create-banner-icons.json ← icon lookup config read by sdp-create-banner.ps1 (shared)
│   │       ├── sdp-hook-log-tools.json      ← per-tool level/logPre/logPost/includeSubagentOrigin config read by sdp-hook-log.ps1
│   │       └── sdp-report-log-loop-metrics-skills.json ← per-role (WORKER/REVIEWER/COORDINATOR/GATE_REVIEWER) skill-name alias list + tunable thresholds read by sdp-report-log-loop-metrics.ps1; append-only oldest-to-newest alias arrays so a future skill rename never breaks historical-date bucketing
│   └── tools/                               ← shared scripts and utilities
│
├── sdp-solution-docs/                       ← solution-level orchestration docs
│   ├── 00_solution_prompt.txt               ← written by sdp-solution-coordinator after each dispatch
│   ├── 00_user_notes.txt                    ← freeform notes at solution level (not agent-read)
│   ├── 01_concept.md                        ← Phase 1 — solution-scoped, never per-project (see bootstrap doc)
│   ├── 02_research_findings.md              ← Phase 2
│   ├── 03_expanded_concept.md               ← Phase 3
│   ├── 04_architecture.md                   ← Phase 4
│   ├── 05_implementation_overview.md        ← Phase 5
│   ├── 06_refined_plan.md                   ← Phase 6
│   ├── 07_phase_readiness.md                ← Phase 7 — build-phase decomposition + dependency declaration
│   ├── user-design-docs/                    ← drop zone for source design docs — read by sdp-solution-new-concept-intake
│   │   ├── README.md
│   │   └── processed/                       ← relocated here after intake; tracked reference for sdp-solution-source-coverage-check
│   │       └── README.md
│   └── log-reports/                         ← generated report output (sdp-report-log-* skills); not agent-read
│       ├── loop-metrics/
│       │   ├── log-report-loop-metrics_yyyyMMdd-HHmm.md
│       │   └── MD-to-PDF/                   ← user-maintained MD→PDF conversions, not an SDP concern
│       ├── hook-metrics/                    ← same log-report-hook-metrics_*.md + MD-to-PDF/ shape
│       ├── workflow-metrics/                ← same log-report-workflow-metrics_*.md + MD-to-PDF/ shape
│       └── combined-metrics/                ← same log-report-combined-metrics_*.md + MD-to-PDF/ shape
│
├── sol-shared/                              ← future solution-specific non-SDP content (placeholder)
│
├── standards/                               ← engineering standards — copied in at setup, read-only
│   ├── GenericProjectGuidlines_V[version].md        ← GPG parent doc (authoritative)
│   └── GenericProjectGuidlines_Sections/            ← GPG section files (agent context use)
│       ├── GenericProjectGuidlines_TOC.md
│       └── GenericProjectGuidlines_[ChapterName].md
│
├── SDP_Sapient-Driven-Principles_vX.X.X.md        ← bootstrap doc (shared)
├── SDP-Workspace-Setup.md                   ← this file (shared)
├── SDP-Skill-Authoring.md                   ← skill authoring reference (shared)
├── SDP-Script-Authoring.md                  ← script authoring reference (shared)
├── SDP-Tone-Notifications.md                ← tone/tune notification reference (shared)
├── SDP-Config.json                          ← loop/halt/preflight policy config (shared — solution root only)
├── SDP-Solution.json                        ← solution registry, active project, active task (shared)
├── SDP-Solution-Setup.json                  ← solution-level preflight manifest (shared — solution root only; read by sdp-preflight.ps1 -workspaceRoot .)
│
├── sdp-project_[AppName.API]/               ← SDP workflow for the API project
├── sdp-project_[AppName.Domain]/            ← SDP workflow for the Domain project
│
├── [AppName].API/                           ← actual code project
├── [AppName].Domain/                        ← actual code project
└── [AppName].sln                            ← solution file (if applicable)
```

> **Visual grouping:** All `sdp-project_*` folders sort together alphabetically.
> `sdp-shared/`, `sdp-solution-docs/`, and `sol-shared/` sort among them — distinguishable
> by the absence of the `_` separator. Actual code folders follow the solution's own naming
> convention and are visually distinct.

> **`SDP-Config.json` placement:** `SDP-Config.json` is at the solution root only — it is
> not per-project. `loopInterval`, `autoResolveHalt`, and `preflight` policy apply equally
> across all projects. The preflight facts (`last_setup_validation`,
> `last_integrity_validation` timestamps) remain in each project's
> `.sdp-workflow/state.json` — policy is shared; facts are per-project.

### `sdp-project_[name]/` Folder Scaffold

Each `sdp-project_[name]/` folder is fully self-contained for its own workflow state, documents,
and configuration. It contains no copies of shared framework files.

```
sdp-project_[AppName.API]/
│
├── .sdp-workflow/                           ← machine-written workflow state
│   ├── state.json
│   ├── registry.md
│   └── sessions/
│       └── session-NNN.md
│
├── sdp-docs/                                ← implementation-task material only — no phase docs
│   ├── 00_user_notes.txt
│   └── 00_prompt.txt
│
├── SDP-Workspace-Setup.json                 ← project-specific preflight manifest
├── SDP-Document-List.json                   ← project-specific document list
├── PATTERNS.md                              ← project-specific generic patterns
├── [AppName.API].speq.md                    ← tech contract (stack, naming, file structure)
├── [AppName.API]-Context.md                 ← project context doc (product identity, GPG scope)
└── shared/                                  ← future project-specific non-SDP content (placeholder)
```

> **`shared/` placeholder:** Create as an empty directory. Add a `.gitkeep` file if the
> repository requires tracked empty directories (git does not track empty folders by default).
> No content lives here during initial project setup — it is reserved for future project-specific
> files that are not SDP workflow artifacts.

---

### `SDP-Solution.json` Templates

`SDP-Solution.json` lives at the solution root. It registers all projects, records the most
recently dispatched project(s), and tracks the active solution-level task.

#### Multi-project workspace

```json
{
  "schema_version": "1.0",
  "solution_name": "[SolutionName]",
  "last_active_projects": [],
  "active_solution_task": null,
  "projects": [],
  "created": "[ISO_DATE]",
  "updated": "[ISO_DATE]"
}
```

Start with empty `projects` and `last_active_projects` arrays. Add a `projects` entry for
each `sdp-project_[name]/` folder at creation time, then set `last_active_projects` to
`["sdp-project_[AppName.xxx]"]` after registering the first project.

#### Single-project workspace

A workspace with only one project is not exempt from this convention. Create a minimal
`SDP-Solution.json` with one entry in `projects` and `last_active_projects: ["."]`
(dot — the workspace root is the project root). Skills apply the same resolution logic:
`.\.\[path]` resolves to `.\[path]` — exactly the current single-project behavior.

```json
{
  "schema_version": "1.0",
  "solution_name": "[SolutionName]",
  "last_active_projects": ["."],
  "active_solution_task": null,
  "projects": [
    {
      "name": "[ProjectName]",
      "path": ".",
      "description": "[Project description]"
    }
  ],
  "created": "[ISO_DATE]",
  "updated": "[ISO_DATE]"
}
```

No fallback logic is needed in any skill for single-project workspaces — the dot path resolves
identically to the workspace root, preserving all current single-project behavior without
special-casing.

---

## Template File Contents

**Agent:** Create the following files with exactly the content shown.

---

#### `README.md` (solution root)

```markdown
# [SolutionName]

[Synopsis — 1–3 sentences: what the solution does, who it serves, what outcome it delivers.]

---

## Projects

| Project | Path | Description |
|---------|------|-------------|
| [ProjectName] | `sdp-project_[name]/` | [one-line description] |

*Agent-maintained — mirrors `SDP-Solution.json` projects array. Agents append rows only; do not modify any other section of this file.*

---

## Starting a Session

Open Claude Code at this folder (the solution root). The session start hook loads context
automatically — no manual pre-read needed.

```text
/sdp-project-coordinator          ← start or resume workflow for the active project
/sdp-auto                 ← start automated loop mode
/sdp-project-run-prompt   ← execute current prompt in a new subagent
/sdp-solution-coordinator ← coordinate across multiple projects
```

---

## Key Documents

| Document | Purpose |
|----------|---------|
| `SDP_Sapient-Driven-Principles_v*.md` | Master workflow reference |
| `SDP-Workspace-Setup.md` | Setup procedure and file templates |
| `SDP-Solution.json` | Project registry and active state |
| `SDP-Config.json` | Loop, halt, and preflight policy |
```

---

#### `[SolutionName].sln` (Visual Studio / Rider — create only when Q5 selects Visual Studio or Rider)

```
Microsoft Visual Studio Solution File, Format Version 12.00
# Visual Studio Version 17
VisualStudioVersion = 17.0.31903.59
MinimumVisualStudioVersion = 10.0.40219.1
# Code project references will be added as projects are initialized by WORKER sessions.
Global
	GlobalSection(SolutionConfigurationPlatforms) = preSolution
		Debug|Any CPU = Debug|Any CPU
		Release|Any CPU = Release|Any CPU
	EndGlobalSection
	GlobalSection(SolutionProperties) = preSolution
		HideSolutionNode = FALSE
	EndGlobalSection
EndGlobal
```

---

#### `[SolutionName].code-workspace` (VS Code — create only when Q5 selects VS Code)

```json
{
  "folders": [
    { "path": "." }
  ],
  "settings": {},
  "extensions": {
    "recommendations": []
  }
}
```

---

#### `.sdp-workflow/state.json`
```json
{
  "project": "[PROJECT]",
  "gpg_version": "[GenericProjectGuidlines version — e.g. V1.10_20260323]",
  "adopted_patterns": [],
  "orchestration_mode": "human-gated",
  "workflow_status": "active",
  "current_phase": "concept",
  "phase_gate": { "status": "pending", "gate_eval_cycles": 0 },
  "active_work_item": null,
  "blocked": false,
  "block_reason": null,
  "last_session": null,
  "phase_readiness": { "regression_count": 0, "regressions": [] },
  "preflight": {
    "last_setup_validation": null,
    "last_integrity_validation": null
  },
  "created": "[ISO_DATE]",
  "updated": "[ISO_DATE]"
}
```

The `preflight` block holds the per-tier last-run timestamps written by `sdp-preflight.ps1`
(the only fields that script writes to `state.json`). They are machine-owned facts paired with
the user-owned policy (tier intervals) in `SDP-Config.json` `preflight`. `null` (or an absent
block) means the tier has never validated cleanly — the next preflight run treats it as due.
`sdp-preflight.ps1` advances a tier's timestamp only on a clean full pass of that tier.

`phase_readiness` records Phase 7 (Phase Readiness) backward-regression history — see the
bootstrap doc's Phase Readiness Regression Bookkeeping section. `regression_count` and
`regressions[]` start empty; COORDINATOR appends to `regressions[]` only when the user selects a
remediation proposal after a Phase Readiness `GATE_BLOCKED` verdict. Never edited by humans.

---

#### `.sdp-solution-workflow/state.json`

```json
{
  "schema_version": "1.0",
  "solution_name": "[SolutionName]",
  "workflow_status": "active",
  "halt_reason": null,
  "gpg_version": "[GenericProjectGuidlines version]",
  "current_phase": "concept",
  "phase_gate": { "status": "pending", "gate_eval_cycles": 0 },
  "phase_readiness": { "regression_count": 0, "regressions": [] },
  "last_session": 0,
  "active_solution_task": null,
  "tasks": [],
  "auto_actions": [],
  "created": "[ISO_DATE]",
  "updated": "[ISO_DATE]"
}
```

`current_phase`, `phase_gate`, `phase_readiness`, `gpg_version` are identical shape and meaning
to their project-level counterparts above — a drop-in reuse of the already-implemented shape,
read from the solution root instead of a project folder. `active_solution_task`, `tasks`,
`auto_actions` are the pre-existing shared-task-mode fields (unchanged) — both mechanisms
coexist: a solution can be mid-Phase-4 architecture work and simultaneously have an active
shared cross-project task in flight. No `dependency_ledger` pointer field is added — the ledger
lives in its own two fixed-path files (`.sdp-solution-workflow/dependencies.md`/
`dependencies.json`); `state.json` doesn't need to point at them.

---

#### `.sdp-workflow/registry.md`
```markdown
# Work Item Registry

Project: [PROJECT]
Created: [DATE]

| # | Phase | Phase File | Status | Session | Depends On |
|---|-------|-----------|--------|---------|------------|

<!-- Append rows as phases are created. Never delete rows. -->
<!-- Status: [ ] not started | [-] in progress | [x] complete -->
<!-- Task-level status is tracked by checkboxes within each phase section file -->
<!-- Session: last session ID that touched this phase -->
<!-- Depends On: phase numbers that must be [x] complete before this phase dispatches; "none" if independent -->
<!-- COORDINATOR does not dispatch tasks in phase N until all phases listed in Depends On show [x] complete -->
<!-- COORDINATOR selects the next current_phase by scanning rows for the first not-yet-complete phase whose Depends On phases are already [x] complete — not simply the next row. Row order is only the tiebreaker among equally-eligible phases; rows do not need to be pre-sorted by dependency order. -->
```

---

#### `.sdp-workflow/sessions/README.md`
```markdown
# Session Log Directory

One file per session. File name: session-NNN.md (zero-padded, sequential).
Each file is written by COORDINATOR before dispatch and appended by the
dispatched agent (WORKER or REVIEWER) when the session concludes.
```

---

#### `[doc_name]_Phase[N]_state.json` (one per phase file, created alongside the phase file)

Machine-readable task state. COORDINATOR reads these; WORKER and REVIEWER update them.
Created when the phase file is created. Never edited by humans — maintained by agents only.

```json
{
  "phase": "[Phase N — Phase Name]",
  "phase_file": "[doc_name]_Phase[N].md",
  "gpg_chapters": [],
  "last_updated": "[ISO_DATE]",
  "last_session": null,
  "tasks": {
    "[TASK-ID]": {
      "status": "PENDING",
      "eval_cycles": 0,
      "last_session": null,
      "flags": []
    }
  }
}
```

`gpg_chapters` lists the GPG chapters applicable to this phase (e.g.
`["Error Handling", "API Design"]`) — empty array is valid. Populated by COORDINATOR during
Phase 7's build-phase decomposition step for every newly decomposed phase; Phase 7's own gate
criterion checks the field is *present*, not necessarily non-empty. For the five original phases
(Concept through Refined Implementation Plan), this field is informational only — nothing reads
it before Phase 7 exists.

**Status values:** `PENDING | WORK_COMPLETE | VERIFIED | REJECTED`

**flags array:** include `"VERIFY_DURING_IMPLEMENTATION"` if the task carries that marker,
so COORDINATOR can note it in REVIEWER dispatch instructions without reading the phase file.
Include `"DIAGNOSIS_BLOCKED"` when WORKER completes a full four-phase debugging cycle,
implements the diagnosed fix, and the problem persists — signals COORDINATOR to surface the
blocked diagnosis to the user before re-dispatching rather than silently re-queuing.

**Sync check rule (COORDINATOR):** If a task has checkbox `[x]` in the phase file but
`status: "PENDING"` in the state file — flag the discrepancy to the user before dispatching.
Do not silently correct it; it indicates a session that updated one artifact but not the other.

---

#### `PATTERNS.md`

Captures `[GENERIC PATTERN]` items as they are identified during this project. Append-only.
Reviewed at project close to propose additions to the bootstrap Patterns Library.

```markdown
# Patterns Registry

Project: [PROJECT]
Bootstrap version this project started with: [VERSION]

> **⚠️ Append-only — agent instruction:** Add entries below. Do not edit or remove existing
> entries. Each entry must be added in the same session that tags a gap resolution as
> [GENERIC PATTERN]. Do not defer pattern capture to a later session.

---

## Pending Promotion

Patterns captured during this project, not yet promoted to the bootstrap Patterns Library.

<!-- PATTERN-001 will be added here by the agent when the first [GENERIC PATTERN] is tagged -->

---

## Promoted

Patterns from this project that have been added to the bootstrap Patterns Library.

| Pattern ID | Title | Bootstrap Version Promoted | Date |
|------------|-------|---------------------------|------|

```

**Agent rule:** When you tag a gap resolution as `[GENERIC PATTERN]`, append an entry to
`PATTERNS.md` in the same session using this format:

```markdown
## PATTERN-NNN: [Pattern Title]
**Source:** [doc_name].md, Gap N — [DATE]
**Context:** [What problem this pattern solves — 1-2 sentences]
**Decision:** [The reusable decision or approach — 2-4 sentences, no project-specific names]
**Reference:** [link to section file for full detail]
**Tags:** [domain tags, e.g. auth, database, rate-limiting, jwt, schema]
**Promotion status:** Pending
```

---

#### `sdp-docs/00_user_notes.txt`

User-authored project notes. The user creates and maintains this file — agents must not
modify it. Create a placeholder stub during workspace setup; the user replaces the body
with actual content.

```
# [PROJECT] — User Notes

[Add project notes here: domain context, research findings, decisions, constraints, goals.
Agents read this file for context. Do not modify this file — it is user-authored.]
```

---

#### Parent document header (embed at top of every `sdp-docs/[doc_name].md`)

The parent document opens with a status block, three separate notice blocks, and an agent
navigation section. Order matters — agents read top to bottom.

```markdown
# [Document Name]

**Date:** [DATE]
**Status:** [draft | in review | approved | ready for implementation]
**Scope:** [one-line description of what this document covers]
**Next Action:** [what happens next — e.g., "Design session to resolve blockers"]

---

> **⚠️ Sync rule — agent instruction:** This is the parent document. Each chapter has a
> corresponding section file in `[doc_name]_Sections/`. Any change made to a chapter here
> **must be mirrored in the corresponding section file**. Any change made in a section file
> must be mirrored in the corresponding chapter here. Both must remain identical in content
> for their shared sections.

---

> **Document Integrity Notice:** Deleting something from the decision record doesn't erase
> the decision — it erases the evidence that a decision was made.
>
> ⚠️ **Append-only.** Do not delete or edit existing content. Status markers and evaluations
> may be appended; ~~nothing may be removed or reworded~~ — strikethrough (`~~text~~`) is a
> valid edit technique: mark the old text as superseded in place and place the replacement
> immediately after on a new line. This preserves the decision audit trail.
> A deleted constraint looks like an unconsidered constraint to future readers.

---

> **TOC Maintenance:** The section folder contains a `[doc_name]_TOC.md` file that must stay
> in sync with the Contents list below. When you add, rename, or delete a chapter/section,
> update both the Contents list here AND the TOC file. See `[doc_name]_TOC.md` for detailed
> maintenance instructions.

---

## Source Documentation

*(Optional — include when the implementation plan references multiple spec documents. Omit
for single-source docs. Assign a short D-ID to each source; use that ID in task descriptions
to cite authority without repeating full paths.)*

| # | Document | Key Content |
|---|----------|-------------|
| D1 | `[path/to/spec.md]` | [What this document governs — one line] |
| D2 | `[path/to/erd.mermaid]` | [What this document governs — one line] |

*Task descriptions cite sources as `(D1)`, `(D2)` etc. — compact authority reference.*

---

## Design Strengths

*(Optional — include in review/analysis docs. Precedes gaps analysis. Enumerates what is
well-specified and should be implemented as-designed without modification. Signals to agents:
"these areas are solid — do not second-guess them.")*

The following design decisions are well-specified and should be implemented as-designed:

1. **[Area]** — [Why it is solid: which source documents agree, what invariants are explicit,
   what non-obvious correctness requirement is addressed]

2. **[Area]** — [Same structure]

*If a proposed approach would break any of the constraints enumerated here, it is wrong.*

---

## Quick Navigation for Future Agents

**Looking for a specific decision?** Use Ctrl+F to search:
- `[search term]` — [what it finds]
- `[search term]` — [what it finds]
- `✅ DECIDED` — all decisions with status and implementation guidance
- `CREATE TABLE` — all database schema definitions
- `[GENERIC PATTERN]` — decisions reusable across projects

**By audience:**
- **[Role/Team]** — See [Section(s)]
- **[Role/Team]** — See [Section(s)]

**Key decisions at a glance:**
- [Decision area]: [one-line summary of decision made]
- [Decision area]: [one-line summary of decision made]

---
```

---

#### Section file header (embed at top of every file in `[doc_name]_Sections/` or `[doc_name]_Phases/`)
```markdown
---
name: [Section or Phase Name]
source: [doc_name].md ([SECTION N: SECTION TITLE])
extracted: [DATE]
---

> *Section file for `[doc_name].md`*
>
> **⚠️ Sync rule — agent instruction:** This is a section file. Any change made here **must be
> mirrored in the corresponding chapter** of `[doc_name].md`. Any change made in the parent
> document's corresponding chapter must be mirrored back here. Both files must remain identical
> in content for their shared sections.
>
> **TOC Maintenance:** If this section is renamed or deleted, update both the parent document's
> Contents list AND the `[doc_name]_TOC.md` file. See the TOC file for detailed maintenance
> instructions.
>
> **⚠️ Append-only — agent instruction:** This document is an append-only record. Do not delete
> or reword existing content. New or revised guidance must be added below the content it supersedes.
> Strikethrough (`~~text~~`) is a valid edit technique — mark the old text as superseded in place
> and place the replacement immediately after on a new line. This preserves the decision audit trail.
```

---

> **Sections vs Phases — terminology:**
> - **Sections** — used for concept-through-plan documents (doc-only). Folder: `[doc_name]_Sections/`
> - **Phases** — used for implementation plan documents where each phase is a discrete unit of work. Folder: `[doc_name]_Phases/`
>
> Two separate TOC templates follow. Use the one that matches the document type.

---

#### TOC Template A — Documentation docs (Sections)
#### File: `[doc_name]_Sections/[doc_name]_TOC.md`

```markdown
# [Document Name] — Table of Contents

**Source Document:** `[doc_name].md`
**Status:** [draft | under review | approved]

---

| # | Section | Description | Audience | File | Status |
|---|---------|-------------|----------|------|--------|
| 0 | Overview | [brief description] | All | [`[doc_name]_Overview.md`]([doc_name]_Overview.md) | ⏳ Needs creation |
| 1 | [Section Name] | [brief description] | [role(s)] | [`[doc_name]_[SectionName].md`]([doc_name]_[SectionName].md) | ⏳ Needs creation |

---

## Status Column Key

| Value | Meaning |
|-------|---------|
| ⏳ Needs creation | Section defined in TOC, file not yet created |
| 🔄 In progress | File exists, content being drafted |
| ⚠️ Pending review | Content complete, gate review not yet started |
| ✅ Exists | Content complete and reviewed |
| 🔄 Archived | Section consolidated elsewhere; retained for history |

> **Section numbering:** Insert sections between existing ones using letter suffixes (`2B`) or
> decimal subdivisions (`2.5`, `2.75`). Do not renumber existing sections.

---

## Why Separate Section Files?

1. **Context efficiency** — Agents load only the relevant section, not the full document
2. **Parallel work** — Multiple agents can work on different sections without context conflicts
3. **Focused reading** — Readers find what they need without scrolling unrelated content
4. **Version control** — Section files can evolve independently
5. **Original document intact** — Parent stays pristine for printing, sharing, and archival

**When to use section files vs. the parent:**
- Agent working on a specific section → load the relevant section file only
- Need full context with cross-references → read the parent document
- Need a quick status overview → read this TOC, then navigate to sections

---

## Quick Search Guide

| You're looking for... | Go to section... |
|----------------------|------------------|
| [topic] | **#** ([Section Name]) |

*(Populate this table as sections are defined. One row per common lookup scenario.)*

---

## File Organization

```
[workspace]/
├── [doc_name].md                    (parent — authoritative source)
└── [doc_name]_Sections/
    ├── [doc_name]_TOC.md            (this file)
    ├── [doc_name]_Overview.md
    └── [doc_name]_[SectionName].md
```

*(Update this diagram when the folder structure changes.)*

---

## Maintenance Instructions — Keep This TOC in Sync

**When to update this TOC:**
- When a new section file is created or an existing section is renamed
- When a section is deleted or moved
- When chapter assignments change
- When the folder structure changes (update the File Organization diagram above)

**How to update:**

1. **Add a new row** if a section is added:
   - Add one row to the table in order
   - Include the number, name, description, audience, file link, and status
   - File name format: `[doc_name]_{SectionName}.md`
   - Use letter suffixes or decimals to insert without renumbering (`2B`, `2.5`)

2. **Update the parent document** `[doc_name].md`:
   - Any content changes made in a section file must be mirrored in the corresponding
     section of the parent document
   - The parent document is the authoritative source; section files are context-optimized extracts
   - Update the parent's Contents list to match this TOC

3. **Remove a row** if a section is removed:
   - Delete the row from this table (or mark 🔄 Archived if historically relevant)
   - Remove the corresponding entry from the parent document's Contents list
   - Delete or archive the section file from this folder

4. **Verify sync** after any edit:
   - Links: All `.md` file links in the table must match actual files in this folder
   - Parent document: The Contents list must have an entry for each row in this table
   - Quick Search Guide: Update if new sections cover common lookup topics
   - File Organization diagram: Update if folder structure changed

5. **Resolve orphaned section files** — if a file exists in this folder but has no TOC row:
   - First check the parent document: does a corresponding section exist there?
   - If **yes** — the file is a TOC omission; add the missing row to this TOC
   - If **no** — the file has no parent content; confirm with the user before deleting

**Golden rule:** Every section in the parent document must have exactly one corresponding
section file in this folder, and this TOC must list them all. If a section file exists
but is not in this TOC, it is orphaned — check the parent before acting.
```

---

#### TOC Template B — Implementation docs (Phases)
#### File: `[doc_name]_Phases/[doc_name]_TOC.md`

```markdown
# [Document Name] — Table of Contents

**Source Document:** `[doc_name].md`
**Context:** [framework / platform / relevant constraint]  **Status:** [current status]

---

| # | Phase | Description | File | WIP | Done | Eval | Eval 2 |
|---|-------|-------------|------|-----|------|------|--------|
| 0 | Overview | [brief description] | [`[doc_name]_Overview.md`]([doc_name]_Overview.md) | [ ] | [ ] | [ ] | [ ] |
| 1 | [Phase Name] | [brief description] | [`[doc_name]_[PhaseName].md`]([doc_name]_[PhaseName].md) | [ ] | [ ] | [ ] | [ ] |

---

## Status Column Key

| Marker | In WIP column | In Done / Eval / Eval 2 columns |
|--------|--------------|----------------------------------|
| `[ ]` | Work not yet started | Not yet complete |
| `[x]` | Currently active — work in progress | Complete |
| `[-]` | Was active; work finished and moved past this stage (preserves history; append-only) | Was complete but superseded (append-only) |

**Columns:**
- **WIP** — set to `[x]` when WORKER session begins; change to `[-]` when Done is marked `[x]`
- **Done** — set to `[x]` when REVIEWER session passes; implementation verified
- **Eval** — set to `[x]` when first evaluation / review cycle is complete
- **Eval 2** — set to `[x]` when second evaluation / review cycle is complete

---

## Maintenance Instructions — Keep This TOC in Sync

**When to update this TOC:**
- When a new phase file is created or an existing phase is renamed
- When a phase is deleted or moved
- When a phase is inserted between existing phases (use decimal numbering, e.g. 5.5 — do not renumber)

**How to update:**

1. **Add a new row** if a phase is added:
   - Add one row to the table in order
   - Include the phase number, name, brief description, and file link
   - File name format: `[doc_name]_{PhaseName}.md`

2. **Update the parent document** `[doc_name].md`:
   - Any content changes made in a phase file must be mirrored in the corresponding
     section of the parent document
   - The parent document is the authoritative source; phase files are context-optimized extracts
   - The parent document must contain a section named **"Implementation Task List"** — a
     named anchor that lists all phases in order and is the primary sync target for this TOC.
     Agents verifying sync check this section by name.

3. **Remove a row** if a phase is removed:
   - Delete the row from this table
   - Delete the corresponding entry from the parent document's Contents list
   - Delete the phase file from this folder

4. **Verify sync** after any edit:
   - Links: All `.md` file links in the table must match actual files in this folder
   - Parent document: The Contents list must have an entry for each row in this table

5. **Resolve orphaned phase files** — if a file exists in this folder but has no TOC row:
   - First check the parent document: does a corresponding phase exist there?
   - If **yes** — the file is a TOC omission; add the missing row to this TOC
   - If **no** — the file has no parent content; confirm with the user before deleting

**Golden rule:** Every phase in the parent document must have exactly one corresponding phase
file in this folder, and this TOC must list them all. If a phase file exists but is not in
this TOC, it is orphaned — check the parent before acting.
```

---

#### Implementation Plan — Standard Appendix Section

Every implementation plan document should include a standard Appendix section containing
three subsections. Agents create this by default when scaffolding a new implementation plan.

```markdown
## Appendix

### Open Questions / Decisions Required

| # | Question | Impact |
|---|----------|--------|
| OQ-1 | [question text] | [affected phases or tasks] |

<!-- Resolve inline: prepend "**Resolved — [decision]. [DATE].** " to the question cell -->

---

### Changelog

<!-- One entry per document version. Append only — newest entry at top. -->

- **V[N.NN] — [DATE]:** [Summary of what changed.]
  - **[Area]:** [Specific change with task ID references and rationale.]
  - **[Area]:** [Specific change.]

---

### Post-Implementation Plan

Items intentionally descoped from current implementation phases. Each entry records what
was deferred, from which task, when, and what future implementation will require.

| # | Item | Deferred From | Decision Date | Notes |
|---|------|---------------|---------------|-------|
| 1 | [Deferred item description] | [Task ID] | [DATE] | [What future implementation requires] |
```

**Project document changelog format** — use for all implementation plan and architecture docs.
Richer than the bootstrap version changelog; designed for agents reading history cold:

```markdown
- **V[N.NN] — [DATE]:** [One-line summary of the version's main change.]
  **[Decision/Area] ([OQ or task ID]):** ✅ RESOLVED — [decision made]. [Rationale in 1-2
  sentences. References to affected tasks and sections.]
  **[Decision/Area]:** [Detail of change with before/after if applicable.]
  [Additional items as needed — each a separate bold-label entry.]
```

Key elements: version + date in header; bold label per change area; task ID references;
resolution status markers (✅ RESOLVED); rationale included inline. Newest entry at top.

---

## Session Start Hook

The session start hook instructs Claude Code to invoke `sdp-initialize-sdp` automatically at the
beginning of every session. This ensures the bootstrap document and project docs are loaded
into context before the agent responds to the first user message. (`sdp-initialize-sdp` replaces
`sdp-solution-read-docs` as the SessionStart hook's direct target — that skill continues to work
unmodified for any direct invocation elsewhere; see its own `SKILL.md` Purpose section.)

### Hook Check — Agent Instruction

At workspace setup — and any time this bootstrap doc is read in an existing workspace — verify
that `.claude/settings.local.json` contains a `SessionStart` hook that invokes `sdp-initialize-sdp`.
If the hook is absent, add it before proceeding.

**To check:** Read `.claude/settings.local.json` and look for a `SessionStart` entry whose `command`
contains `sdp-initialize-sdp`.

**To add:** Merge the following into the `hooks` object in `.claude/settings.local.json`. Do not
overwrite existing hooks — add to the existing `SessionStart` array if one is present, or
create the `SessionStart` key if it does not exist.

```json
"hooks": {
  "SessionStart": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "[PSCustomObject]@{ hookSpecificOutput = [PSCustomObject]@{ hookEventName = 'SessionStart'; additionalContext = 'Before responding to any user message this session, invoke the sdp-initialize-sdp skill by running /sdp-initialize-sdp.' } } | ConvertTo-Json -Compress",
          "shell": "powershell",
          "statusMessage": "Loading project docs..."
        }
      ]
    }
  ]
}
```

This hook is project-scoped and lives in `.claude/settings.local.json`, not the user-level settings
file. It must be present in every workspace using this bootstrap workflow.

---

## Setup Checklist (Full)

Complete in order. Brief version in main bootstrap doc directs here.

Setup is two-level: first establish the solution root (steps 1–4), then add each project.

### Solution Setup

- [ ] **Step 0 — Collect setup inputs (before creating any files or folders):**
      1. Derive a preliminary solution name from the root folder name — propose it and confirm or correct.
      2. Ask Q1–Q3 to compose the synopsis: (Q1) what does this solution do, (Q2) who uses it,
         (Q3) what outcome does it deliver? Draft the synopsis text and confirm with the user before writing it.
      3. Ask Q4: what project types make up this solution? Propose the full `sdp-project_*` folder
         list using PascalCase dotted naming — `sdp-project_[AppName].[Type]` (e.g.
         `sdp-project_MyApp.API`, `sdp-project_MyApp.Domain`). Confirm with the user. This is a
         starting point, not a final list — the solution-scoped Concept and Architecture phases
         may reveal additional projects are needed; nothing here is locked in.
      4. Ask Q5: what development environment will be used alongside Claude Code?
         - Visual Studio or Rider → will create `[SolutionName].sln`
         - VS Code → will create `[SolutionName].code-workspace`
         - Agent-only → no IDE file created
         - Other → describe; agent scaffolds what it can
      5. Ask Q6: detect the GPG standards doc version present in `standards/` (e.g.
         `GenericProjectGuidlines_V1.10_20260323.md`) and explicitly ask the user to confirm this
         is the version they intend, or name a different one — a filesystem check can prove the
         file exists, not that it is the version the user wants. Ask this here, before any
         scaffolding begins — do not defer it to Step 4's infrastructure verification, which runs
         after scaffolding has already started.
      6. Present the complete setup plan (solution name, synopsis text, full project list,
         IDE file to be created or "none", and the confirmed GPG standards version from Q6) and
         wait for explicit user confirmation. The conduct-rules check (Step 1.5) runs after
         Step 1 and is reported to the user then — its outcome cannot be known yet for the "add
         to an existing solution" path, since the template it checks against isn't present at
         the solution root until Step 1 copies it.

- [ ] **Step 1 — Copy SDP framework into solution root** — copy `sdp-shared/`, `standards/`,
      `.claude/`, bootstrap docs, `SDP-Config.json` into the solution root.
      `SDP-Config.json` lives at the solution root only — do not place it inside project folders.
      Copying `sdp-shared/` brings `sdp-shared/scripts/script-support/` along with it (it is a
      subfolder of `sdp-shared/scripts/`, not a separately-created solution-workflow folder) —
      review its `SDP-Tones.json` for this new solution rather than assuming the copied file's
      tone assignments apply as-is (see the "Create `SDP-Tones.json`" checklist item below).
- [ ] **Step 1.5 — Conduct-rules check** — `.claude/rules/sdp-core-invariants.md` ships as a
      real, already-active file; no action needed. For `.claude/rules/sdp-agent-conduct.md.template`:
      1. Read `~/.claude/CLAUDE.md` (user level), if present.
      2. Read `.claude/CLAUDE.md` and any existing `.claude/rules/*.md` (project level), if present.
      3. Compare the template's rule set against what's already loaded from steps 1–2, matching
         **per rule ID** (F-1…F-22, A-1…A-4, Evidence Standards, Procedural Completeness) — not
         exact-text diff, since wording may differ while the rule is the same. This is a judgment
         call, not a deterministic script step.
      4. Classify and act:
         - **Full match** (every rule already present elsewhere) → do not create
           `sdp-agent-conduct.md`; leave the template inert.
         - **Partial match** → copy the template to `sdp-agent-conduct.md`, then remove the rules
           already covered elsewhere, keeping only the net-new ones.
         - **No match** → copy the template to `sdp-agent-conduct.md` unmodified.
      5. The `.template` file itself is left in place in every case (copy, not move) — harmless,
         since its `.template` extension excludes it from Claude Code's `.claude/rules/*.md`
         auto-load, and it remains available as a reference of the full rule set.
      6. Notify the user of the outcome — e.g. "conduct rules: already present via
         `~/.claude/CLAUDE.md`, skipped" / "conduct rules: 14 of 22 were net-new, added to
         `sdp-agent-conduct.md`" / "conduct rules: none found, added in full." No separate
         confirmation gate — this follows the same single Step 0 confirmation as Steps 2–3.5.
- [ ] **Step 2 — Create solution-level workflow folders at the solution root:**
      - `.sdp-solution-workflow/` — create with `state.json` stub, `sessions/` subfolder,
        and `logging/` with its
        four sibling subfolders — `loop-logs/`, `hook-logs/`, `workflow-logs/`, `combined-logs/` —
        all empty at setup time. The first three are created on first write by their own writer
        (`sdp-tone.ps1` / `sdp-project-state-loop` for `loop-logs/`; `sdp-hook-log.ps1` for `hook-logs/`;
        `sdp-workflow-log.ps1` for `workflow-logs/`); `combined-logs/` is created on first
        invocation of `sdp-report-logs-combine` rather than passively, since nothing writes to it until
        a user explicitly combines a day. None of the four needs manual creation here, but all
        four should exist as empty folders after this step so their presence is visually
        confirmable before first use. Also create the dependency-ledger files as empty stubs —
        `SDP-Solution-Setup.json` registers both as `file-exists` checks at the `setup` tier, so
        they must exist before the first `sdp-solution-coordinator` invocation, not just from
        Phase 7 decomposition onward: `dependencies.json` = `[]` (an empty JSON array; Phase 7
        decomposition — Task 9 Step 2b — appends real edge objects to it later) and
        `dependencies.md` = a short header (`# Dependency Ledger` plus a one-line note that
        entries are appended at Phase 7 decomposition)
      - `sdp-solution-docs/` — create with `00_solution_prompt.txt` stub (leave empty; written
        by `sdp-solution-coordinator`), `00_user_notes.txt` stub (freeform user notes), and
        `user-design-docs/` + `user-design-docs/processed/` (drop zone for source design docs —
        read by `sdp-solution-new-concept-intake`; each folder gets a README explaining its purpose, see
        `sdp-shared/ai-skills/sdp-solution-new-concept-intake/SKILL.md`)
      - `sol-shared/` — empty placeholder for future solution-specific non-SDP content. Add
        `.gitkeep` if the repository requires tracked empty directories.
- [ ] **Step 2.5 — Create `README.md` at the solution root** — use the `README.md` template
      from [Template File Contents](#template-file-contents). Write the confirmed synopsis into
      the synopsis field. Write the first project row (name, path, description) into the projects
      table for each project confirmed in Q4. This file is human-maintained after setup — agents
      append to the projects table only and do not modify any other section.

- [ ] **Step 3 — Create `SDP-Solution.json` at the solution root** — use the multi-project or
      single-project template from the [`SDP-Solution.json` Templates](#sdp-solutionjson-templates)
      section above. Set `solution_name` to the confirmed solution name from Step 0. Register all
      projects from Q4 in the `projects` array (each with `name`, `path`, and `description`).
      Leave `last_active_projects` as the empty array the template already defaults to — do not
      set it to the first project. Meaningless as a Level-3 fallback until phases 1–7 have run at
      least once (nothing routine depends on it before then). Leave `active_solution_task: null`.

- [ ] **Step 3.5 — Create IDE workspace file (based on Q5 answer from Step 0):**
      - **Visual Studio or Rider:** Create `[SolutionName].sln` using the `.sln` stub template
        from [Template File Contents](#template-file-contents). Code project references are added
        by WORKER sessions once `.csproj` files exist — do not add them at setup.
      - **VS Code:** Create `[SolutionName].code-workspace` using the `.code-workspace` template
        from [Template File Contents](#template-file-contents). The `folders` array defaults to
        `[{ "path": "." }]`; agent may append project subfolder paths as they are created.
      - **Agent-only:** Skip — no IDE file needed.
      - **Other:** Scaffold what can be inferred; note what the user must complete manually.

- [ ] **Step 4 — Verify solution infrastructure:**
      - **Create `SDP-Solution-Setup.json` manifest** — create at the solution root: the
        solution-tailored preflight check inventory read by `sdp-preflight.ps1` when invoked
        with `-workspaceRoot .`. Enumerate the sdp- skill pairs (`skill-pair`), the three
        Level-1-only fully-scriptable skills' Level 1 (`file-exists`) and Level 2
        (`file-absent`) checks — `sdp-tone`, `sdp-create-banner`, and `sdp-claude-new-terminal`
        all get both checks equally; "Level-1-only" means none of the three may ever have a
        Level 2 SKILL.md, so the drift guard applies uniformly, not to `sdp-tone` alone — plus
        their script/config files (`file-exists`), the standalone
        solution-root scripts (`file-exists`), `sdp-shared/scripts/script-support/SDP-Tones.json`,
        the Session Start hook registration (`hook-registered`), the `permissions.allow` entry
        for each script (`json-array-contains`), the Standards Sections folder's existence
        (`dir-exists`), and the `materialDecisionEscalation.enabled` field's presence in
        `SDP-Config.json` (`json-field-present` — presence only, not a specific true/false value,
        since the field is user-editable policy). Tier each entry `integrity` (drift guards) or
        `setup` (scaffold completeness). Not registered in `SDP-Document-List.json` — it is data,
        not context.
      - **Run the solution-level preflight check** — invoke (PowerShell tool):
        ```
        .\sdp-shared\scripts\sdp-preflight.ps1 -workspaceRoot .
        ```
        `-workspaceRoot .` (the solution root itself) resolves `SDP-Solution-Setup.json`, not a
        project's `SDP-Workspace-Setup.json`. One call now validates every deterministic
        solution-level precondition that was previously hand-checked item-by-item here: the
        Session Start hook registration (its command contains `sdp-initialize-sdp` — see
        [Session Start Hook](#session-start-hook) below), all sdp- skill pairs (Level 1 +
        Level 2 — sdp-project-coordinator, sdp-project-create-prompt, sdp-project-doc-review, sdp-evaluate-skill,
        sdp-project-gate-review, sdp-project-pre-work-verify, sdp-project-read-docs, sdp-project-reviewer, sdp-project-run-prompt,
        sdp-standards-setup, sdp-project-worker, the loop/automation pairs, and the solution-level
        pairs), the three Level-1-only fully-scriptable skills (`sdp-tone`,
        `sdp-claude-new-terminal`, `sdp-create-banner` and their script/config files), every
        standalone solution-root script's existence, the `permissions.allow` entry for each
        script, the Standards Sections folder's existence, and the
        `materialDecisionEscalation.enabled` field's presence in `SDP-Config.json`. Read the
        single-line JSON
        envelope it emits: if `ok` is `false`, resolve the listed `failures` (or the `error`
        field on an operational error such as a missing/unparseable manifest) before
        proceeding. The canonical check inventory lives in `SDP-Solution-Setup.json` as data —
        do not hand-re-enumerate it here. See `SDP-Script-Authoring.md` for the permission-entry
        format and the permission-failure diagnosis if a script call is unexpectedly blocked.
      - **The following remain manual** — not script-able, per `sdp-project-coordinator/SKILL.md`'s own
        precedent for these same items:
        - **Install Superpowers plugin** — run
          `/plugin install superpowers@claude-plugins-official` inside an active Claude Code
          session. Verify with `/plugin list`. Required before first WORKER session. See
          Superpowers Plugin Integration section of main bootstrap doc for per-role usage rules.
        - **Verify PowerShell & test tooling** — confirm PowerShell is available (Windows
          PowerShell 5.1 or PowerShell 7+); the sdp- skills invoke scripts under
          `sdp-shared/scripts/`. To run the script unit tests in `sdp-shared/scripts/tests/`,
          Pester 5+ is required — the Pester 3.4 bundled with Windows is not sufficient. Install
          and run commands are in the [Tooling Prerequisites](#tooling-prerequisites) section
          above. Pester is needed only for running the script tests, not for the workflow itself.
        - **Standards-doc version** — already confirmed with the user at Step 0's Q6, before
          scaffolding began; this step's `SDP-Solution-Setup.json` check only re-confirms
          *existence* (a filesystem check), not which version the user intends — that judgment
          call was already made at Q6. If the file is missing entirely (should not happen if Q6
          was answered honestly, but preflight may still catch drift): ask the user to copy the
          GPG parent doc and Sections folder into `standards/` before proceeding — do not
          continue setup until confirmed.
          **Using a custom standards doc instead of GPG?** See `SDP-Standards-Setup.md` and run
          `/sdp-standards-setup` before completing this setup step. The skill enforces doc
          location and format, scaffolds the sections folder, updates all framework file
          references, and verifies the result. Run it before adding any projects.

### Add-Project Steps

Repeat for each project added to the solution. Solution-level folders
(`.sdp-solution-workflow/`, `sdp-solution-docs/`) already exist — no changes needed to them.

- [ ] Confirm project name and one-line description with user (name becomes `sdp-project_[AppName.xxx]/`; description populates `SDP-Solution.json` `projects[].description` and the README projects table)
- [ ] Create `sdp-project_[AppName.xxx]/` at the solution root and scaffold
      project-specific files inside it per the
      [`sdp-project_[name]/` Folder Scaffold](#sdp-project_name-folder-scaffold) diagram above:
      - `.sdp-workflow/` folder (with `state.json`, `registry.md`, `sessions/`)
      - `sdp-docs/` folder (stub `00_user_notes.txt`, empty `00_prompt.txt` only — no phase
        docs; implementation-task material only, see the updated `sdp-project_[name]/` scaffold
        diagram)
      - `shared/` — empty placeholder; add `.gitkeep` if the repository tracks empty directories
      - `SDP-Workspace-Setup.json`, `SDP-Document-List.json`, `PATTERNS.md`
- [ ] Create `[doc_name]_Sections/` folder alongside each doc that has sections
- [ ] Confirm folder structure with user before proceeding
- [ ] Initialize `.sdp-workflow/state.json` with project name, current date,
      `adopted_patterns: []`, and `gpg_version: "[version]"`
- [ ] Initialize `.sdp-workflow/registry.md` (phase-level tracking; task-level tracked inline
      in phase files)
- [ ] Create `.sdp-workflow/sessions/README.md`
- [ ] Create `PATTERNS.md` with project name and bootstrap version recorded
- [ ] **Register the project in `SDP-Solution.json`** — add an entry to the `projects` array
      with `name`, `path` (relative to solution root, e.g. `"sdp-project_[AppName.xxx]"`),
      and `description`. Then set `last_active_projects` to `["sdp-project_[AppName.xxx]"]`.
- [ ] **Update `README.md` projects table** — read the current table, then append a row for
      this project (name, path as `sdp-project_[AppName.xxx]/`, one-line description). Do not
      modify any other README section. If a row exists in the table for a project no longer in
      `SDP-Solution.json`, flag it to the user before removing.
- [ ] **Review the Patterns Library section of the main bootstrap doc** — for each pattern
      relevant to this project, add its ID to `adopted_patterns` in `state.json` and note
      how it applies
- [ ] **Read `standards/GenericProjectGuidlines_TOC.md`** — note which GPG chapters are
      relevant to this project type; these will be referenced during architecture work
- [ ] Confirm project setup complete with user
- [ ] **Do not** ask which phase to start in, and **do not** create any phase document stub — a
      project no longer has phases of its own. Its `.sdp-workflow/registry.md` starts empty and
      stays empty until a future solution-level Phase 7 decomposition (the original one, or a
      later mid-stream cycle) assigns it implementation tasks.
- [ ] ~~**Create Project Context Document** — once product shape, technology stack, and key
      architectural decisions are settled (typically during early Phase 1 planning), create
      `[PROJECT]-Context.md` inside `sdp-project_[AppName.xxx]/`. Add it to the project's
      `SDP-Document-List.json` with `"role": "project"` and `"includeInReadDocs": true` so
      `sdp-project-read-docs` loads it automatically every session. Do this before dispatching the
      first WORKER session. See the Project Context Document section of the main bootstrap doc.~~
- [ ] ~~**Create `.speq` contract** — once tech stack, naming conventions, and file structure
      are settled (typically by end of Phase 1), create `[PROJECT].speq.md` inside
      `sdp-project_[AppName.xxx]/` using the template in the
      [`.speq` Contract Template](#speq-contract-template) section below. Add it to the
      project's `SDP-Document-List.json` with `"role": "contract"` and
      `"includeInReadDocs": true`. This entry must appear before `sdp-docs/00_prompt.txt` in
      the array. A session that cannot answer a naming or stack question from this file must
      pause and ask the user rather than inferring.~~

  > **Correction — 2026-07-26:** Both bullets above named a project's own "Phase 1" as the
  > creation trigger — stale language from before the solution-scoped model. Phases 1-7 now run
  > once per solution (`sdp-solution-phase-worker`); a project has no phase pipeline of its own
  > until Phase 7's decomposition assigns it tasks. Confirmed via a real halt: a project's first-
  > ever WORKER dispatch (post-Phase-7) found neither file existed, because no step in the
  > solution-scoped pipeline ever created or populated them. Split into a create-stub step (still
  > here, at Add-Project time — costs nothing, keeps `SDP-Document-List.json` ordering correct
  > from day one) and a populate-with-real-content step (moved to Phase 7 decomposition, the point
  > where tech stack/structure are actually settled and this project's identity is first real).
  > See the replacement bullets below and `sdp-solution-phase-coordinator/SKILL.md` Step 2b item 0.

- [ ] **Create Project Context Document stub** — as part of this Add-Project pass, create an
      empty `[PROJECT]-Context.md` inside `sdp-project_[AppName.xxx]/` (template placeholders
      only — see the main bootstrap doc's Project Context Document section for what it will
      eventually contain). Add it to the project's `SDP-Document-List.json` with
      `"role": "project"` and `"includeInReadDocs": true` so `sdp-project-read-docs` loads it
      every session. Population with real, settled content happens at Phase 7 decomposition (see
      below) — do not populate it here.
- [ ] **Create `.speq` contract stub** — as part of this Add-Project pass, create
      `[PROJECT].speq.md` inside `sdp-project_[AppName.xxx]/` using the template in the
      [`.speq` Contract Template](#speq-contract-template) section below, left with template
      placeholders only. Add it to the project's `SDP-Document-List.json` with
      `"role": "contract"` and `"includeInReadDocs": true`; this entry must appear before
      `sdp-docs/00_prompt.txt` in the array. Do not populate it here.
- [ ] **Populate `.speq` contract and Project Context Document at Phase 7 decomposition** —
      owned by `sdp-solution-phase-coordinator` Step 2b item 0, executed by the dispatched
      `sdp-solution-phase-worker` session: for each project receiving decomposed build-phase
      tasks for the first time, replace the stub content created above with the real tech stack,
      naming conventions, file structure, and product-shape decisions already recorded in
      `sdp-solution-docs/04_architecture.md` and `sdp-solution-docs/05_implementation_overview.md`
      (the sections applicable to that project — a solution-scoped document may cover more than
      one project). This must complete before that project's first WORKER dispatch —
      `sdp-solution-phase-gate-review`'s Phase Readiness gate checks it. A session that finds only
      template placeholders here before Phase 7 has decomposed this project is expected, not a
      defect; a session that finds them after Phase 7 has decomposed it is a gate-review miss.
- [ ] **Initialize `SDP-Document-List.json` and verify ordering** — confirm the file
      contains an entry for `sdp-docs/00_prompt.txt` with `"role": "project"` and
      `"includeInReadDocs": true`. This entry **must** be the last `"includeInReadDocs": true`
      entry in the array — entries that follow it may have `"includeInReadDocs": false`
      (registered only). Re-verify this ordering any time a new entry is added to the file.
      Purpose: ensures all other context is loaded into the agent's window before it reads
      its task instructions.
- [ ] **Create `SDP-Tones.json`** — if not already present at
      `sdp-shared/scripts/script-support/` (Step 1's framework copy may have brought one along):
      review it for this solution rather than assuming it applies as-is, or create it fresh.
      User-editable tone/tune configuration read by `sdp-tone.ps1` (palette, sequences,
      profiles, assignments, events). See `SDP-Tone-Notifications.md` for the full schema,
      trigger catalog, and a starter file to copy. Add `SDP-Tone-Notifications.md` to the
      project's `SDP-Document-List.json` with `"includeInReadDocs": false`.
- [ ] **Create/Copy `sdp-hook-log-tools.json`** — if not already present at
      `sdp-shared/scripts/script-support/` (Step 1's framework copy normally brings this along,
      since it now lives under `sdp-shared/`): copy it from the SDP framework's own reference
      copy rather than authoring fresh — unlike `SDP-Tones.json` (user-editable per solution),
      this file is a maintained, framework-wide enumeration of every known Claude Code tool
      (per-tool `level`/`logPre`/`logPost`/`includeSubagentOrigin`, plus a
      `defaultForUnlistedTools` tripwire for tools that appear later and haven't been
      classified yet). Read by `sdp-hook-log.ps1` on every `PreToolUse`/`PostToolUse` hook
      firing to decide whether a log entry is written — the hooks themselves always fire; this
      file gates the write, not the firing. Also register the `PreToolUse`/`PostToolUse` async
      hook commands for `sdp-hook-log.ps1` in `.claude/settings.local.json`'s `hooks` block if
      not already present (no matcher — fires for every tool call; `"async": true` so the
      hook's exit code/stdout can never block or influence the observed tool call):
      ```json
      "PreToolUse": [
        { "hooks": [ { "type": "command", "command": "powershell.exe",
          "args": ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
          "${CLAUDE_PROJECT_DIR}/sdp-shared/scripts/sdp-hook-log.ps1"], "async": true } ] }
      ],
      "PostToolUse": [
        { "hooks": [ { "type": "command", "command": "powershell.exe",
          "args": ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
          "${CLAUDE_PROJECT_DIR}/sdp-shared/scripts/sdp-hook-log.ps1"], "async": true } ] }
      ]
      ```
- [ ] **Create/Copy `sdp-report-log-loop-metrics-skills.json`** — if not already present at
      `sdp-shared/scripts/script-support/` (Step 1's framework copy normally brings this along):
      copy it from the SDP framework's own reference copy rather than authoring fresh — like
      `sdp-hook-log-tools.json`, this is a maintained, framework-wide file, not solution-specific
      per-run tuning. Read by `sdp-report-log-loop-metrics.ps1` at startup: per-role
      (`WORKER`/`REVIEWER`/`COORDINATOR`/`GATE_REVIEWER`) arrays of every literal skill name that
      role has ever been logged under (oldest first, current name last), plus the
      `offHoursThresholdMinutesDefault`/`unloggedGapThresholdSeconds` tunables. Whenever a skill in
      one of these four roles is renamed, append the new name to that role's array here — never
      remove or reorder an existing entry, since historical `loop-metrics-*.jsonl` files on disk
      still carry the old literal name and must keep resolving to the same canonical bucket. See
      the file's own `_doc` field for the full schema.
- [ ] **Create `SDP-Workspace-Setup.json` manifest** — create inside
      `sdp-project_[AppName.xxx]/`: the project-tailored preflight check inventory read by
      `sdp-preflight.ps1`. Genuinely project-scoped checks only: the `setup`-tier folders,
      document-list existence, and `json-last-include` ordering. Tier each entry `integrity`
      (drift guards) or `setup` (scaffold completeness).
      **Note:** Do not include `file-exists`/`skill-pair`/`json-array-contains` checks for
      `sdp-shared/`, `.claude/`, or `standards/` paths — these are solution-level concerns,
      verified by `SDP-Solution-Setup.json` (see the matching solution-root manifest item in
      the Solution Setup checklist above), not project-level manifest entries.
      Not registered in `SDP-Document-List.json` — it is data, not context.
- [ ] **Verify `preflight` blocks present** — confirm the `preflight` policy block exists in
      `SDP-Config.json` at the solution root (tier intervals) and the `preflight` facts block
      exists in `sdp-project_[AppName.xxx]/.sdp-workflow/state.json`
      (`last_setup_validation`, `last_integrity_validation`).
- [ ] ~~Notify user: project setup complete, ready to begin Phase 1~~

  > **Correction — 2026-07-27:** "ready to begin Phase 1" predates the solution-scoped model —
  > a project has no Phase 1 of its own (per the "Do not ask which phase to start in" item
  > above, already corrected). Notify user: project setup complete — `.sdp-workflow/registry.md`
  > stays empty until a future solution-level Phase 7 decomposition assigns this project
  > implementation tasks.

---

## `.speq` Contract Template

File: `[PROJECT].speq.md` inside `sdp-project_[AppName.xxx]/` (project-specific — not at solution root).

See the `.speq` Contract section of the main bootstrap doc for purpose, amendment rules, and
the boundary between `.speq` and the Project Context Document.

```markdown
# [PROJECT] — Technical Contract

| Field | Value |
|-------|-------|
| **Project** | [PROJECT] |
| **Created** | [DATE] |
| **Bootstrap** | SDP_Sapient-Driven-Principles_v[VERSION] |

> **Agent instruction:** This is the binding technical contract for all sessions. Every
> declaration here is final — do not re-derive, re-propose, or deviate without an explicit
> user-approved amendment. Amendments are append-only: apply `~~strikethrough~~` to the
> superseded row or section in place and add the replacement immediately below with a date
> and reason. Do not delete existing declarations — they are the record that a decision
> was made and later revised. If a task requires a decision not declared here, stop and
> ask the user before proceeding.

---

## Tech Stack

| Layer | Technology | Version | Notes |
|-------|-----------|---------|-------|
| | | | |

---

## Naming Conventions

| Scope | Convention | Example |
|-------|-----------|---------|
| | | |

---

## File Structure & Boundaries

| Location | Purpose | May import from | May NOT import from |
|----------|---------|----------------|---------------------|
| | | | |

---

## Data Shape

Key entity shapes that govern agent decisions. Not a full schema — just the fields and types
that affect naming, relationships, and contract design.

| Entity | Key Fields | Notes |
|--------|-----------|-------|
| | | |

---

## Settled Decisions

Decisions that are closed. Agents must not re-open or re-propose alternatives.

| ID | Decision | Rationale |
|----|---------|-----------|
| SD-1 | | |

---

## Out of Scope / Deferred

| Item | Reason | Target phase |
|------|--------|-------------|
| | | |

---

## Standing Non-Functional Requirements

> **Addition — 2026-08-11:** New section — added after a review found no way for a standing,
> cross-cutting requirement (e.g. adaptive UI layout across device sizes) to reach every
> relevant WORKER task automatically. Populated at Phase 7 decomposition
> (`sdp-solution-phase-coordinator` Step 2b item 0) alongside the rest of this template; read
> as binding acceptance-criteria input by `sdp-project-worker` Step 3.1 and
> `sdp-project-reviewer` Step 3.1.

Cross-cutting requirements that apply to every task of a given kind, not just one task's own
written description — e.g. "every customer-facing web page must be responsive across desktop/
tablet/phone" (GPG Ch. 11), or "every MAUI page must adapt across phone/tablet and orientation"
(GPG Ch. 12). A matching row is binding acceptance-criteria input in addition to a task's own
written description; it is not optional context.

| Requirement | Applies To | Rationale / GPG Reference |
|-------------|-----------|---------------------------|
| | | |
```

---

## `SDP-Config.json` Template

File: `SDP-Config.json` at the **solution root** (shared across all projects — not per-project).

User-editable configuration for SDP workflow automation. Read explicitly by `sdp-auto` and
`sdp-project-state-loop` — not registered in `SDP-Document-List.json`. Add new top-level sections
as needed; do not nest unrelated config under existing sections. Tone/tune configuration is
**not** here — it lives in `SDP-Tones.json` (see the next section).

```json
{
  "schema_version": "1.0",
  "loopInterval": {
    "notes": "Polling interval for the sdp-project-state-loop recurring job started by sdp-auto. interval_minutes sets how often the loop wakes to check workflow state and dispatch the next step. Lower values increase responsiveness but consume more API calls; 5 minutes is a reasonable default for active development.",
    "interval_minutes": 5
  },
  "autoResolveHalt": {
    "notes": "How sdp-project-state-loop responds when a REVIEWER is detected cycling without progress (eval_cycle_attempts - eval_cycles >= evalCycleAttemptThreshold). evalCycleAttemptThreshold: REVIEWER dispatch attempts before halt evaluation fires (default 2). pushOnEvalBlock: when true, auto-runs git push if unpushed commits are the detected cause and resets the counter; when false, halts with an actionable message instead.",
    "evalCycleAttemptThreshold": 2,
    "pushOnEvalBlock": true
  },
  "preflight": {
    "notes": "Max staleness per check tier for sdp-preflight.ps1 (the manifest-driven workspace check engine reading SDP-Workspace-Setup.json). Integrity = drift guards (skills/scripts/GPG), run frequently. Setup = scaffold completeness, stable. interval 0 = always run. The sdp-project-state-loop loop honors these timers; an explicit human COORDINATOR invocation may pass -Force to bypass them. The script reads this block (policy) but never writes it; the matching facts (last-run timestamps) live in .sdp-workflow/state.json.",
    "setupValidationIntervalHours": 24,
    "integrityValidationIntervalHours": 1
  },
  "materialDecisionEscalation": {
    "notes": "Gates the Material Decision Escalation rule (bootstrap doc, Dispatch and Halt Contracts section). When enabled, any dispatched session (any role) must halt rather than suggest, select, or introduce an external dependency not already named in .speq, or an architectural pattern with no GPG precedent, until the user resolves it. This field is loop-owned by policy: no skill, in any role, may write it. Changing it requires a human editing SDP-Config.json directly, outside any dispatched session.",
    "enabled": true
  },
  "tones": "Tone/tune configuration moved to SDP-Tones.json (see SDP-Tone-Notifications.md). This key is a pointer only; sdp-tone.ps1 no longer reads SDP-Config.json.",
  "newTerminalNotes": "The newTerminals array is read by sdp-claude-new-terminal.ps1. initialPrompt is passed as the positional argument to `claude` when a new terminal window is spawned; empty string launches interactive Claude Code with no initial prompt. startingDirectory sets the new window's working directory - absolute path, or relative to the solution root; empty/absent defaults to the solution root. hoursToSaveSessionHistory controls SDP-Terminal-Sessions.json retention: on every invocation the script checks each recorded pid; a process no longer running is marked status=not_running with a notRunningAt timestamp, and any not_running entry older than this many hours is deleted from the registry. Per-profile hoursToSaveSessionHistory, if present, wins; otherwise falls back to newTerminalDefaultHoursToSaveSessionHistory below; if that is also absent/invalid, the script's own last-resort default (168 hours, one week) applies. permissionMode sets the starting permission mode via `claude --permission-mode <value>`; empty string passes no flag (Claude Code's own default). See newTerminalPermissionModeOptions for the exact accepted values.",
  "newTerminalDefaultHoursToSaveSessionHistory": 168,
  "newTerminalPermissionModeOptions": "default | manual (alias for default, v2.1.200+) | acceptEdits | plan | auto | dontAsk | bypassPermissions",
  "newTerminals": [
    {
      "id": 0,
      "name": "go",
      "initialPrompt": "",
      "startingDirectory": "",
      "hoursToSaveSessionHistory": 24,
      "permissionMode": ""
    }
  ]
}
```

**Fields:**

- `loopInterval.interval_minutes` — how frequently `sdp-project-state-loop` fires when started by
  `sdp-auto`. Increase for long-running WORKER sessions; decrease for fast iteration cycles.
  Default: `5`.
- `autoResolveHalt.evalCycleAttemptThreshold` — number of REVIEWER dispatch attempts (the gap
  between `eval_cycle_attempts` and `eval_cycles`) before `sdp-project-state-loop` runs halt evaluation.
  Default: `2`.
- `autoResolveHalt.pushOnEvalBlock` — when `true`, `sdp-project-state-loop` auto-pushes if the detected
  cause of a no-progress block is unpushed commits, then resets the counter and continues; when
  `false`, it halts with an actionable message instead.
- `preflight.setupValidationIntervalHours` — max staleness (hours) for the `setup` tier of
  `sdp-preflight.ps1` (scaffold completeness). Default: `24`. `0` = always run.
- `preflight.integrityValidationIntervalHours` — max staleness (hours) for the `integrity`
  tier (drift guards: skill pairs, scripts, GPG version). Default: `1`. `0` = always run.
- `materialDecisionEscalation.enabled` — gates the Material Decision Escalation rule (see the
  bootstrap doc's Dispatch and Halt Contracts section). Default: `true`, scaffolded at workspace
  setup. Loop-owned by policy — no skill, in any role, may write this field; changing it requires
  a human editing `SDP-Config.json` directly, outside any dispatched session.
- `tones` — a pointer string only. All tone/tune configuration lives in `SDP-Tones.json`.
- `newTerminals` — array of named launch profiles read by `sdp-claude-new-terminal.ps1`. Each
  entry is selected by the script's `-terminal` parameter (matched by numeric `id` first, then by
  `name`); omitting `-terminal` selects the entry with `id: 0`. An unresolved selector, or a
  missing `id: 0` entry when none is given, is a hard error — no terminal is launched.
  - `newTerminals[].id` — numeric identifier, unique per entry. `0` is the default profile.
  - `newTerminals[].name` — string identifier, matched when `-terminal` isn't purely numeric.
  - `newTerminals[].initialPrompt` — passed as the positional argument to `claude`. Default:
    `""` (no initial prompt). Can be overridden per-invocation via the script's
    `-promptOverride` parameter regardless of which profile is selected.
  - `newTerminals[].startingDirectory` — working directory for the new window. Absolute path, or
    relative to the solution root. Default: `""` (falls back to the solution root).
  - `newTerminals[].hoursToSaveSessionHistory` — retention window for this profile's
    `SDP-Terminal-Sessions.json` entries once their process is no longer running. Default: `24`.
  - `newTerminals[].permissionMode` — starting permission mode passed as `claude
    --permission-mode <value>`. Default: `""` (no flag — Claude Code's own default). An
    unrecognized value halts the script with an error rather than being passed through
    unvalidated.
- `newTerminalNotes` — documentation-only note describing the `newTerminals` schema; not read by
  the script.
- `newTerminalPermissionModeOptions` — documentation-only note listing the exact accepted values
  for `permissionMode`; not read by the script.

---

## `SDP-Tones.json` Template

File: `sdp-shared/scripts/script-support/SDP-Tones.json` (shared across all projects — not
per-project).

User-editable tone/tune configuration. Read **only** by `sdp-shared/scripts/sdp-tone.ps1`.
Registered in `SDP-Document-List.json` companion doc `SDP-Tone-Notifications.md`
(`"includeInReadDocs": false`) — the JSON file itself is not registered. Set top-level
`"enabled": false` to silence all notifications.

The full schema, the four-primitive model (note / sequence / profile / binding), the complete
trigger catalog, the `-whatIf` test switch, and the tune-authoring guide are in
**`SDP-Tone-Notifications.md`**. Copy the starter file from there. Minimal viable skeleton:

```json
{
  "enabled": true,
  "palette": [
    { "id": "B", "hz": 330, "ms": 300, "character": "E4 - skill start" },
    { "id": "F", "hz": 523, "ms": 100, "character": "C5 - skill end" }
  ],
  "assignments": [
    { "sdpSkillName": "*", "useAtSkillStart": "B" },
    { "sdpSkillName": "*", "useAtSkillEnd": "F" }
  ],
  "sequences": {
    "siren": { "gapMs": 0, "notes": [ { "hz": 880, "ms": 220 }, { "hz": 587, "ms": 220 } ] }
  },
  "profiles": {
    "once": { "repeat": 1, "gapMs": 0 },
    "burst": { "repeat": 4, "gapMs": 120 }
  },
  "events": [
    { "trigger": "halt.no_progress", "sequence": "siren", "profile": "burst" },
    { "trigger": "halt.generic", "sequence": "siren", "profile": "burst" }
  ]
}
```

**Top-level keys:**

- `enabled` — global mute when `false`.
- `palette` — atomic `{ id, hz, ms }` tones; used by the skill start/end channel.
- `assignments` — skill start/end tone mapping (`sdpSkillName` + `useAtSkillStart`/
  `useAtSkillEnd`); exact skill match beats the `"*"` wildcard.
- `sequences` — named, ordered note series (palette-id strings and/or inline `{ hz, ms }`;
  `hz <= 0` is a silent rest); the "what".
- `profiles` — playback behavior (`repeat` + `gapMs` between repeats); the "how".
- `events` — `trigger` → `sequence` (+ optional `profile`, inline `repeat`/`gapMs`, `enabled`);
  the "where". See the trigger catalog in `SDP-Tone-Notifications.md`.

---

## Bootstrap Open Items

Items flagged for refinement before this bootstrap is used in a production workspace:

- [ ] Add sample populated `state.json` showing mid-project state
- [ ] Add `workflow.ps1` script-gated dispatch script
- [ ] Add sample completed work item (spec + work + review + status) for reference
- [x] Define dependency encoding in registry.md — resolved: Depends On column added to registry
      template; COORDINATOR checks [x] complete status before dispatching a dependent phase
- [ ] Define sync verification step — when should an agent explicitly confirm parent and section
      are in sync before starting work (e.g., at the top of every WORKER session)
- [ ] Add user samples from prior work (pending user contribution)
- [ ] Clarify: does COORDINATOR role require a separate agent, or can the user serve as COORDINATOR
      for human-gated mode?
- [x] Define what "a new session" means in the context of Claude Code — resolved: a session is a
      new subagent invocation; `/clear` does not satisfy context isolation; the session dispatch
      file is the only cross-session communication channel
- [ ] Add conflict resolution rule: what happens if REVIEWER and WORKER disagree on what a spec
      criterion requires
- [x] REVIEWER session file gap — resolved: session dispatch file read added as REVIEWER step 2;
      steps 2–10 renumbered to 3–11; re-evaluation trigger reason and flags now visible to REVIEWER

### Script Authoring and Permission Gaps

- [x] Define script authoring conventions and permission registration requirement — resolved:
      `SDP-Script-Authoring.md` documents script anatomy, output contracts, error contracts, the
      permission entry format, worked examples, and the creation checklist. Permission requirement
      discovered via production failure: Claude subagents block PowerShell tool calls without
      explicit `permissions.allow` entries in `settings.local.json` — wildcard permissions from
      the parent session do not carry over to subagents.
- [ ] Add `settings.local.json` permission verification to SKILLS CHECK in main bootstrap doc
      (steps 0b and Phase Gate step 1b) — currently SKILLS CHECK verifies script files exist but
      does not verify permission entries. Adding permission verification would catch missing entries
      at COORDINATOR startup rather than at subagent invocation time.

### Cross-Platform (macOS / Linux) Portability

- [ ] **Scripts require cross-platform validation.** SDP automation is written for
      PowerShell 7 (`pwsh`) with cross-platform compatibility in mind but has been validated
      only on Windows. Running on macOS or Linux requires `pwsh` and has not yet been validated
      end-to-end. Status by finding (per `research/SDP-PORTABILITY_cross-platform-analysis.md`):
      - **F2 — Path separators (fixed):** `sdp-create-prompt.ps1`, `sdp-preflight.ps1`, and all
        test harnesses now use `Resolve-WsPath` / `Resolve-TestPath` helpers that split on
        `[/\\]` and join per-segment — no hardcoded backslashes in path construction remain.
      - **F3 — PowerShell executable (fixed):** Test harnesses use
        `[System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName` to locate the
        running `pwsh` binary; `powershell.exe` is no longer hardcoded.
      - **F4 — Skill invocation paths (fixed):** All skill SKILL.md files and
        `settings.local.json` permission entries use forward-slash script paths
        (e.g. `./sdp-shared/scripts/sdp-tone.ps1`), accepted by PowerShell on all platforms.
      - **F5 — Tone audio (deferred):** `sdp-tone.ps1` calls `[console]::Beep(hz, ms)` which
        silently no-ops inside a `try/catch` on macOS/Linux (`pwsh`). Workflow is unaffected;
        no audio on non-Windows hosts. A cross-platform audio backend is a future improvement.
      - **F6 — Encoding (not applicable):** `pwsh` defaults to UTF-8 (no BOM); the existing
        ASCII-safe and no-BOM-write practices are correct on all platforms.

### Skill Authoring Gaps (sdp- skill catalog)

- [x] Define Claude Code skill file format — resolved: two-level Level 1/Level 2 templates
      defined in `SDP-Skill-Authoring.md`; worked example (sdp-project-pre-work-verify)
      demonstrates both levels in full
- [x] Define the sdp- skill catalog structure — resolved: Skill Authoring Pattern section
      defines the naming convention, file locations, and template structure; individual skill
      authoring follows the worked example. Full catalog enumeration (one row per sdp- skill)
      remains a forward item as skills are built out.
- [x] Define subagent spawning mechanics for skill invocation — resolved: dual-contract model
      defined in main bootstrap doc — Dispatch and Halt Contracts section. Skills read
      `orchestration_mode` from `state.json` (`"human-gated"` or `"agent-orchestrated"`) and
      follow the matching dispatch path. Context passed = session dispatch file + bootstrap doc
      path. Outcome detected by reading `[phase]_state.json` after dispatch, not by parsing
      subagent text output. `orchestration_mode` field added to `state.json` template
      (default: `"human-gated"`).
- [x] Define halt behavior in skill invocation context — resolved: Halt Behavior Contract defined
      in main bootstrap doc — Dispatch and Halt Contracts section. Halt is a named state
      transition: skill writes `workflow_status: "halted"` and `halt_reason` to `state.json`,
      prints a user-facing message, and terminates. COORDINATOR checks `workflow_status` at
      startup and does not dispatch while halted. Clearing a halt is a human action followed
      by a COORDINATOR session that resets `workflow_status` to `"active"`. `workflow_status`
      field added to `state.json` template (default: `"active"`).
- [x] Document Superpowers command interface for WORKER skill — resolved: WORKER Invocation
      Reference table in main bootstrap doc. TDD: `/test-driven-development`. Debugging:
      `/systematic-debugging`. Full 14-skill catalog with slash command names included.
