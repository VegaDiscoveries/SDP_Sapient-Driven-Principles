<img src="sdp-shared/docs/images/SDP_DocsLogo_WithText_0700x0163.png" alt="SDP Logo" width="375">

# — A Self-Driving Process for Coding

A structured multi-agent development workflow methodology for AI-assisted software development, built on Claude Code. It is not a library or an agent framework — it requires no additional runtime dependencies beyond Claude Code, a couple of standard developer tools, and one optional plugin. It converts a single AI agent session into a disciplined, multi-role, multi-session pipeline — COORDINATOR, WORKER, and REVIEWER — each operating in strict context isolation. The framework governs how work is assigned, tracked, executed, reviewed, and recorded across any number of sessions.

**Audience:** Solo developers or small teams using Claude Code to manage complex, multi-service architectures across multiple agent sessions. If your task fits in a single session, this framework adds overhead that won't pay off.

**New here?** Skip straight to [`QuickStart.md`](QuickStart.md) for workspace setup instructions.

---

## Requirements

- **Claude Code** (the CLI)
- **PowerShell** — Windows PowerShell 5.1 (built-in) or PowerShell 7+ on all platforms. PowerShell 7+ is recommended and required on macOS and Linux. [Install PowerShell](https://github.com/PowerShell/PowerShell/releases/latest).
- **git** — required by the Superpowers plugin itself (it errors on a project with no git available) and by `sdp-shared/scripts/sdp-github.ps1`. [Install Git](https://git-scm.com/downloads).
- **Python** — not used by any SDP script or skill today (SDP's own automation is 100% PowerShell). Install it anyway: on at least one tested workspace, an agent was observed invoking Python to compute banner-padding math while rendering an `sdp-create-banner`/`sdp-initialize-sdp` banner, despite those procedures' explicit instruction that no script or tool call may generate or verify a banner row. That's a deviation from the documented procedure, not a real SDP dependency — but since it has recurred, Python is listed here so a missing interpreter doesn't compound it.
- **Superpowers plugin** — install inside a Claude Code session:
  `/plugin install superpowers@claude-plugins-official`

**Recommended Claude Code mode:** run SDP sessions — especially agent-orchestrated and loop-orchestrated (`/sdp-auto`) dispatch — under Claude Code's official `auto` permission mode (`claude --permission-mode auto`, or `"permissions": {"defaultMode": "auto"}` in `settings.json`). SDP issues many PowerShell-tool calls per session; `auto` mode avoids per-call prompt fatigue while still applying Claude Code's background safety checks. This is distinct from `bypassPermissions`, which disables those checks entirely and is documented as container/VM-only — SDP does not recommend `bypassPermissions`.

---

## Core Concepts

### Agent Roles

Three distinct roles operate in the workflow. A single session must never perform more than one role.

| Role | Responsibility |
|------|---------------|
| **COORDINATOR** | Reads state, determines next action, dispatches WORKER or REVIEWER, writes session files |
| **WORKER** | Implements a single assigned task, appends a Completed blockquote, updates state to `WORK_COMPLETE` |
| **REVIEWER** | Independently verifies WORKER output against acceptance criteria, appends Eval + Verified blockquotes, updates state to `VERIFIED` or `REJECTED` |

### State Machine

Each task transitions through formal states recorded in `[phase]_state.json`:

```
PENDING
  └─► WORK_COMPLETE  (WORKER completes task)
        └─► VERIFIED     (REVIEWER passes)
        └─► REJECTED     (REVIEWER fails)
              └─► PENDING (COORDINATOR resets; REJECTED tasks take priority)
```

Every role transition happens in a new subagent invocation. The only cross-session communication channel is files on disk:

```
COORDINATOR session
    │ writes session-NNN.md + sdp-docs/00_prompt.txt, updates state.json
    ▼
WORKER session  ← new subagent, isolated context window
    │ implements work, appends Completed blockquote
    │ writes WORK_COMPLETE to [phase]_state.json
    ▼
COORDINATOR session  ← new invocation, reads state from disk
    │ writes session-NNN.md + sdp-docs/00_prompt.txt for REVIEWER
    ▼
REVIEWER session  ← new subagent, isolated context window
    │ verifies independently, appends Eval blockquote
    │ writes VERIFIED or REJECTED to [phase]_state.json
    ▼
(next COORDINATOR session reads outcome from disk — repeat)
```

### Key Principles

- **Append-only documentation** — Code shows what was built; it does not show what alternatives were considered and why they were rejected. Strikethrough for superseded content and dated evaluations appended in place make rationale permanently available to any agent or human, regardless of how many sessions have elapsed.
- **Context isolation** — An agent that implements a feature and then reviews it has its full prior reasoning in context; self-review produces approval, not evaluation. Work and review are enforced in separate subagent invocations with no shared conversation history. `/clear` does not satisfy this requirement.
- **Explicit machine-readable state** — Without state files, each new session re-derives its position from documentation prose and may reach a different conclusion than the prior session. State files make the status of every work item a fact the agent reads, not a conclusion it draws.
- **Parent is authoritative; section/phase files are context-optimized extracts** — Large project documents are decomposed into focused files agents read for their specific task. This prevents context overload and keeps append-only document growth from becoming a practical constraint on agent sessions.

---

## Multi-Project Coordination (Solution Layer)

The solution layer extends the three-role workflow across multiple independent projects that make up a single deliverable — an API, a website, a shared library, a database schema, and so on. A single task at the solution level fans out to coordinated child tasks across every involved project and cannot close until all of them pass both individual and cross-project review.

### When to Use It

`/sdp-solution-coordinator` is the universal entry point for all tasks. Describe what needs to be done — the coordinator reads the registered projects and determines which are involved. If the work touches one project, one child task is created and dispatched; if it touches several, they fan out in parallel. No upfront decision about task scope is required. The only task type choice is mechanical: a **project task** (`sdp-project-coordinator`) is used when `sdp-solution-coordinator` determines the work is confined to one project and the solution orchestration overhead is not warranted; a **solution task** spans two or more projects and carries cross-project sync, cascade detection, and an integration check.

### Project Tasks vs. Solution Tasks

| Aspect | Solution task | Project task |
|--------|---------------|--------------|
| State machine | SOL\_PENDING → SOL\_WORK\_COMPLETE → SOL\_VERIFIED | PENDING → WORK\_COMPLETE → VERIFIED |
| Task decomposition | `sdp-solution-worker` creates child tasks in each involved project's phase file | Task exists in one project's phase file |
| Dispatch | Parallel subagents per project (synced mode) or ordered one at a time (sequenced mode) | One project, one role at a time |
| Coordinator role | `sdp-solution-coordinator` reads all child states, enforces the sync invariant, and fans out | `sdp-project-coordinator` resolves and dispatches one project |
| Rejection handling | Any rejection freezes the entire solution task — all projects halt pending cascade review | REVIEWER rejects; COORDINATOR resets that task |
| Final review | Solution reviewer adds a cross-project integration check after all individual reviews pass | Per-project reviewer verifies implementation |

### Cycle Sync Invariant

The solution coordinator enforces a sync step across all involved projects on every invocation. It identifies the laggard — the project with the lowest status — and only dispatches projects that have not yet reached that level. No project can advance past the current sync point while others lag behind. In `synced` mode (the default), all laggard projects are dispatched in parallel. In `sequenced` mode, they are dispatched one at a time in declared order, for cases where one project's implementation must precede another's.

### Cascade Detection

When any child project is rejected, the solution coordinator sets a `SOL_CASCADE_REVIEW_NEEDED` flag and freezes all dispatch — including projects that have already passed their own review. A rejection in one project (e.g., the API changes its response shape) can invalidate work already completed in another project (e.g., the website that consumes it). The freeze requires a human to confirm the cascade scope before any project resumes. Projects that passed do not automatically roll back — the human decides what needs revisiting before clearing the flag.

### Cross-Project Integration Check

Once all child projects reach `VERIFIED` individually, the solution reviewer performs a second pass that no per-project reviewer can perform in isolation:

- **Error handling alignment** — error shapes, status codes, and fallback conventions are consistent across the boundary
- **Integration assumptions** — assumptions stated in the solution task description are met by the combined implementation
- **Interface contracts** — API request/response shapes match what consuming projects expect
- **Shared type and enum consistency** — types and enums used across projects are defined identically

A failure on any item sets the solution task to `SOL_REJECTED` and triggers cascade detection, even if every individual project review passed.

### Architectural Boundary

The `parent` field in a task's state entry is the boundary marker. Tasks created by `sdp-solution-worker` carry a `parent` field; tasks created by `sdp-project-coordinator` do not. `sdp-solution-coordinator` dispatches `sdp-project-worker` and `sdp-project-reviewer` directly for solution-managed tasks — `sdp-project-coordinator` is bypassed entirely and reserved for single-project work only.

---

## Repository Structure

```
SapientDrivenPrinciples-AI_Workflow_Bootstrap_Project/
├── .claude/
│   ├── rules/                   # Compaction-durable rules (sdp-core-invariants.md, sdp-agent-conduct.md.template)
│   └── skills/                  # Level 1 skill shims
├── .sdp-solution-workflow/
│   ├── state.json               # Solution-level workflow state
│   ├── logging/                 # Append-only JSONL logs, one file per local calendar day, gitignored
│   │   ├── loop-logs/           # Workflow-level fire/tone events (sdp-project-state-loop + sdp-tone.ps1)
│   │   ├── hook-logs/           # Fine-grained PreToolUse/PostToolUse tool-call trace (sdp-hook-log.ps1)
│   │   ├── workflow-logs/       # Semantic dispatch/eval/gate-verdict narrative log (sdp-workflow-log.ps1)
│   │   └── combined-logs/       # Normalized per-day merge of the above three (sdp-report-logs-combine)
│   └── sessions/                # Session records (append-only)
├── docs/                        # Legacy scratch notes (design specs now live in sdp-shared/docs/)
├── research/                    # Legacy scratch notes (research docs now live in sdp-shared/docs/)
├── sdp-shared/
│   ├── ai-skills/               # Level 2 skill implementations
│   ├── docs/                    # Shared reference docs (setup, authoring guides, changelog)
│   ├── scripts/                 # PowerShell automation scripts + Pester tests
│   │   └── script-support/      # Data files read internally by sdp-shared/scripts/*.ps1
│   │       ├── SDP-Tones.json               # Audible notification configuration
│   │       ├── sdp-create-banner-icons.json # Icon registry for sdp-create-banner.ps1
│   │       ├── sdp-hook-log-tools.json      # Per-tool level/logPre/logPost/includeSubagentOrigin config for sdp-hook-log.ps1
│   │       └── SDP-Terminal-Sessions.json   # Registry of spawned Claude Code terminal instances (POC)
│   └── skill-evals/             # Per-skill deterministic-vs-LLM evaluation reports
├── sdp-solution-docs/           # Solution-level dispatch prompts and user notes
│   └── user-design-docs/        # Drop zone for sdp-solution-new-concept-intake (+ processed/ archive)
├── sol-shared/                  # Placeholder for cross-project shared assets
├── standards/                   # Generic project guidelines (GPG reference)
├── SDP-Config.json              # Workflow configuration
├── SDP-Document-List.json       # Documents loaded by sdp-project-read-docs
├── SDP-Solution.json            # Multi-project registry
├── SDP-Solution-Setup.json      # Solution-level preflight validation manifest
├── SDP_Sapient-Driven-Principles_v*.md # Master bootstrap document (versioned)
└── [SolutionName].code-workspace # VS Code workspace file (if applicable)
```

`sdp-shared/docs/` holds: `SDP-Changelog.md`, `SDP-Flowchart.md`, `SDP-Project-Evolution.md`,
`SDP-Script-Authoring.md`, `SDP-Skill-Authoring.md`, `SDP-Standards-Setup.md`,
`SDP-Tone-Notifications.md`, and `SDP-Workspace-Setup.md`.

`sdp-preflight.ps1` auto-detects which manifest to validate against from `-workspaceRoot` alone:
`SDP-Solution-Setup.json` (shown above) for the solution root, or `SDP-Workspace-Setup.json` —
a separate, per-project manifest — inside each `sdp-project_[name]/` folder.

### Two-Level Skill Architecture

Every SDP skill is implemented as a Level 1 / Level 2 pair:

- **Level 1** (`.claude/skills/[name]/SKILL.md`) — shim that runs the tone, reads the Level 2 implementation, and dispatches to it
- **Level 2** (`sdp-shared/ai-skills/[name]/SKILL.md`) — full skill procedure; portable and testable independently of any project's `.claude/` folder

**Why split?** Claude Code loads every file under `.claude/skills/` into the skill catalog at session start. A four-step L1 shim costs negligible context; a full procedure in L1 would pre-load detail across the entire skill library that most sessions never need. L2 lives in `sdp-shared/` — shared infrastructure that every project in the solution references without duplication — so updating a procedure means editing one L2 file while L1 shims stay unchanged. L2 can also be read and executed directly without the `.claude/` wrapper, making it independently testable.

**The shim as an enforcement mechanism.** The structure of L1 is deliberate. Step 2 requires the agent to explicitly read the L2 file before taking any action — the full procedure must be loaded and acknowledged, not assumed from memory or inferred. Step 3 mandates executing every numbered step in L2 in order, completing all sub-steps before advancing. Combined with the conduct preamble at the top of every L1 file, this creates a sequential checklist the agent is required to work through one item at a time. In practice, agents left to their own judgment will sometimes skip steps they consider repetitive, low-value, or unlikely to change the outcome. The shim eliminates that judgment call: every step is required, every time, and skipping one is a conduct violation.

### Script Execution: A Third Tier - Deterministic Execution Layer

Not every skill step requires LLM reasoning. Steps that read structured state, fill fixed templates, or evaluate deterministic conditions are candidates for script execution — the LLM is an expensive and variable executor for work that has no judgment component.

The axis that determines tier assignment: **does this step require LLM reasoning, or is it pure rule-following over structured data?**

| Tier | Location | When used |
|------|----------|-----------|
| **Script** | `sdp-shared/scripts/` | Zero reasoning required — config lookups, template fills, sentinel parsing, preflight checks |
| **Hybrid** | Script + `sdp-shared/ai-skills/` | Partially deterministic — script handles structured sections, LLM engages only on flagged edge cases |
| **LLM-only** | `sdp-shared/ai-skills/` | Reasoning, judgment, or context-building — coordinator, worker, reviewer |

The L1 shim is the routing point. For script-tier skills it invokes the PowerShell tool directly. For LLM-tier skills it reads Level 2 SKILL.md and delegates. For hybrid skills it does both in sequence.

**Why it matters — tool call cost:**

`sdp-tone` was the first conversion. As an LLM skill it required ~19 tool calls per invocation (skill load, task creation, step execution, task updates). As a script it requires 1. With tones firing at the start and end of every skill across a workflow run, the reduction is approximately 380 tool calls to 20 for tone notifications alone.

**Why it matters — context window preservation:**

Every tool call a script replaces is one fewer message of intermediate reasoning, file reads, and task management output in the orchestrating session's context window. In a coordinator session spanning multiple dispatch cycles, mechanical steps done by the LLM accumulate as noise; the same steps done by a script leave only the tool result. A context window consumed by clerical work reaches compaction sooner and has less capacity available for the judgment-heavy work that actually requires it — coordinator decisions, gate reviews, cascade assessments. Scripts keep the context budget where it belongs.

**The hybrid pattern:**

Some skills are partially deterministic. `sdp-project-create-prompt` is the primary example: reading `state.json`, filling the prompt's five sections from fixed templates, and writing `00_prompt.txt` are all deterministic — flag edge cases are not. The hybrid design splits these cleanly:

- The script handles all deterministic work and writes a structured JSON temp file containing the filled sections and a `_meta` block (`script_status`, `error`, `retry_count`, `llm_read`, `llm_processed`)
- The script echoes the temp file path to stdout — the LLM reads it from the tool result at zero additional tool calls
- The LLM only engages if the script flags an edge case it cannot resolve deterministically

The temp file is both the handoff point between tiers and a permanent debug artifact — one timestamped file per invocation, never deleted, retained in `.sdp-workflow/temp/phase-N/`.

**Current skill tier assignments:**

| Skill | Tier | Basis |
|-------|------|-------|
| `sdp-tone` | Script | Config lookup + audio output — zero reasoning |
| `sdp-claude-new-terminal` | Script | Config lookup + process spawn + registry write — zero reasoning; no Level 2 SKILL.md |
| `sdp-create-banner` | Script | Tokenizing, icon resolution, and row/border construction are fully deterministic — zero reasoning; no Level 2 SKILL.md |
| `sdp-project-create-prompt` | Hybrid | Template fill is deterministic; flag combinations require judgment |
| `sdp-project-run-prompt` | Hybrid | Sentinel parsing is deterministic; skill invocation requires LLM host |
| `sdp-project-coordinator` | LLM-only | Judgment calls on next task, nuanced dispatch instructions |
| `sdp-project-worker` | LLM-only | Implementation — the entire point of LLM involvement |
| `sdp-project-reviewer` | LLM-only | Independent evaluation, compliance assessment |
| `sdp-project-read-docs` | LLM-only | Loading docs into LLM context is the product — cannot be scripted away |
| `sdp-solution-coordinator` | Hybrid | State reads, sync-invariant enforcement, and session file writes are deterministic; dispatching subagents and reading their outcomes require an LLM host |
| `sdp-solution-reviewer` | Hybrid | Precondition checks, outcome confirmation, and state finalization are deterministic; dispatching reviewers and the cross-project integration check require judgment |
| `sdp-solution-create-prompt` | Hybrid | State reads are deterministic; `role`/`projects` exist only in the invoking coordinator's conversation context |
| `sdp-project-gate-review` | Hybrid (multi-boundary) | Three script blocks bracket two LLM-judgment phases — see below. Project-scoped only. |
| `sdp-solution-phase-gate-review` | Hybrid (multi-boundary) | Solution-scoped companion to `sdp-project-gate-review` — identical three-script-bracket pattern, always resolves the solution root, no `-scope` parameter needed (there is only one scope) |
| `sdp-solution-phase-worker` | LLM-only | Implementation of a solution-scoped phases 1-7 task — the same reasoning `sdp-project-worker` provides, at solution scope |
| `sdp-solution-phase-reviewer` | LLM-only | Independent evaluation of a solution-scoped phases 1-7 task — the same reasoning `sdp-project-reviewer` provides, at solution scope |

Most hybrid skills split into one script-then-LLM handoff. `sdp-project-gate-review` is the framework's
first **multi-boundary hybrid**: the phase-gate procedure has two distinct points requiring
reasoning — the independent four-criterion document assessment, and the pass/block verdict —
so it needed three script blocks (GPG check, dispatch/document setup, state finalization)
rather than one. The verdict is passed into the finalize script as an explicit argument, never
inferred by the script, since a wrong `phase_gate.status` write would silently advance a phase
that should have been blocked.

### Skills Inventory

**Project skills** — operate within a single `[resolved_project]` folder:

| Skill | Purpose |
|-------|---------|
| `sdp-auto` | Opt-in to automated loop mode for the current session |
| `sdp-cancel-auto` | Stop the running state loop |
| `sdp-project-coordinator` | COORDINATOR session — read state, check gates, dispatch WORKER or REVIEWER |
| `sdp-project-create-prompt` | Write `sdp-docs/00_prompt.txt` with sentinel and five-section dispatch prompt |
| `sdp-project-doc-review` | Review phase documents before tasks are dispatched (locks open decisions) |
| `sdp-evaluate-skill` | Evaluate an existing skill for deterministic vs. LLM-required steps and write a scripting-opportunity report — `sdp-shared/skill-evals/` for project-authored skills, `~SDP-Maintenance/~sdp-shared/~skill-evals/` for SDP framework skills |
| `sdp-project-gate-review` | GATE_REVIEWER session — phase gate verdict before advancing to next phase |
| `sdp-project-loop-prep` | Pre-loop readiness sweep — walks every not-yet-complete phase in dependency order running `sdp-project-doc-review`, `sdp-solution-source-coverage-check`, and `sdp-phase-rightsizing-check`, so gaps surface before `/sdp-auto` starts instead of mid-run |
| `sdp-claude-new-terminal` | Launch a new terminal window running Claude Code from a named/numbered launch profile in `SDP-Config.json`; record the instance in `SDP-Terminal-Sessions.json` |
| `sdp-solution-new-concept-intake` | Register a new mini Phase 1–5 concept cycle mid-project — document-driven (drop zone) or conversational (no file) |
| `sdp-phase-rightsizing-check` | Assess a phase's task volume for unattended-dispatch fitness; propose and, on approval, execute a `registry.md` split into right-sized sub-phases |
| `sdp-project-pre-work-verify` | Scan for prior artifacts, classify state, and act before any task begins |
| `sdp-project-run-prompt` | Read `sdp-docs/00_prompt.txt` and invoke the indicated skill automatically |
| `sdp-solution-source-coverage-check` | Compare a tracked source design doc against its downstream phase docs; surface any element with no downstream coverage |
| `sdp-standards-setup` | Replace the default GPG standards doc with a custom standards doc — enforces structure, scaffolds section files and TOC, generates a reading map, and updates all framework file references |
| `sdp-project-state-loop` | Recurring loop — evaluates sentinel, dispatches next subagent, detects stuck loops |
| `sdp-state-loop-start` | Initialize and start the recurring state loop |
| `sdp-workspace-setup` | First-run (or add-project) scaffolding — solution-root setup and/or per-project folder structure, driven by `SDP-Workspace-Setup.md`'s Setup Checklist |

**Solution skills** — operate at the solution root across multiple projects:

| Skill | Purpose |
|-------|---------|
| `sdp-initialize-sdp` | `SessionStart` hook target — prints the opening/closing banners, invokes `sdp-solution-read-docs` internally, and detects framework-maintenance vs. normal mode |
| `sdp-solution-coordinator` | Read all child project states, enforce cycle sync invariant, fan out workers to laggard projects or dispatch solution reviewer when all reach `WORK_COMPLETE`; detect cascades; terminate after each cycle |
| `sdp-solution-worker` | Decompose a solution task into child project tasks and dispatch project workers across involved projects (parallel in synced mode, sequential in sequenced mode) |
| `sdp-solution-reviewer` | Dispatch project reviewers across all child projects; run cross-project integration check when all reach `VERIFIED`; enter cascade detection on any rejection |
| `sdp-solution-create-prompt` | Write `sdp-solution-docs/00_solution_prompt.txt` for the next solution session — either a shared cross-project task, or a phases-1-7 dispatch (`current_phase`/`phase_gate`-driven) |
| `sdp-solution-run-prompt` | Read the solution prompt and invoke the indicated skill automatically |
| `sdp-solution-read-docs` | Load solution-root docs and active project docs; index other registered project doc lists in context; invoked internally by `sdp-initialize-sdp`, the actual `SessionStart` hook target |
| `sdp-solution-phase-worker` | WORKER session for a solution-scoped phases 1-7 task (Concept through Phase Readiness, including Phase 7's build-phase decomposition) — dispatched by `sdp-solution-phase-coordinator` Step 2a; never used for project-level tasks |
| `sdp-solution-phase-reviewer` | REVIEWER session for a solution-scoped phases 1-7 task — same dispatch path as `sdp-solution-phase-worker`; never used for project-level tasks |
| `sdp-solution-phase-gate-review` | GATE_REVIEWER session for a solution-scoped phases 1-7 gate — dedicated companion to `sdp-project-gate-review`, used exclusively for phases 1-7; `sdp-project-gate-review` itself is never given a solution-level dispatch |

**Shared** — invoked from both project and solution flows:

| Skill | Purpose |
|-------|---------|
| `sdp-project-worker` | WORKER session — implement assigned task, update state to WORK\_COMPLETE; dispatched by `sdp-project-coordinator` for single-project tasks and directly by `sdp-solution-worker`/`sdp-solution-reviewer` for solution-managed *shared cross-project tasks*. Never given a phases-1-7 dispatch — that is `sdp-solution-phase-worker`'s exclusive job, a separate mechanism from the shared-task dispatch described here. |
| `sdp-project-reviewer` | REVIEWER session — independently verify task against acceptance criteria; same dual-dispatch pattern as `sdp-project-worker`, same phases-1-7 exclusion — see `sdp-solution-phase-reviewer` |
| `sdp-project-read-docs` | Load solution docs and a specified project's docs into agent context; project-scoped, invoked explicitly in subagent dispatch instructions. Use `sdp-solution-read-docs` when active project auto-resolution or multi-project indexing is needed. |
| `sdp-tone` | Emit audible start/end/event tones via `sdp-tone.ps1`; called by every skill at both levels |
| `sdp-create-banner` | Render a fixed-border status/error banner from caller-supplied label/content pairs via `sdp-create-banner.ps1`; called by any SDP skill needing a mid-process banner |

**Reporting** — on-demand log/metrics reports, solution-root scoped (manual invocation, no `[resolved_project]` involved):

| Skill | Purpose |
|-------|---------|
| `sdp-report-log-loop-metrics` | Generate a loop-metrics report (time accounting, halt/off-hours tables, task outcomes) from a selected `loop-metrics-*.jsonl` file |
| `sdp-report-log-hook-metrics` | Generate a hook-log report (tool-usage/session/level/work-item charts) from a selected `hook-log-*.jsonl` file |
| `sdp-report-log-workflow-metrics` | Generate a workflow-log report (trigger/role/outcome breakdowns, Concerning Events) from a selected `workflow-log-*.jsonl` file |
| `sdp-report-logs-combine` | Data-prep step (not a report) — merge one day's `loop-metrics`/`hook-log`/`workflow-log` jsonl into a single normalized `combined-log-yyyyMMdd.jsonl` |
| `sdp-report-log-combined-metrics` | Generate a combined-metrics report from a selected `combined-log-*.jsonl` file — depends on `sdp-report-logs-combine`'s output already existing for the target day |

### PowerShell Scripts

| Script | Purpose |
|--------|---------|
| `sdp-create-banner.ps1` | Tokenizes the invocation grammar, resolves icons against `sdp-create-banner-icons.json`, and constructs the bordered banner text |
| `sdp-create-prompt.ps1` | Writes `sdp-docs/00_prompt.txt` deterministically (UTF-8 no-BOM, sentinel line, five sections) |
| `sdp-gate-review-finalize.ps1` | Applies the GATE_REVIEWER's verdict (passed as an explicit argument, never inferred) to `phase_gate` state, plays the blocked-gate tone, and returns the templated user report. Project-scoped only, no `-scope` parameter. |
| `sdp-gate-review-gpg-check.ps1` | Verifies the GPG standards file exists for the active project; writes the Halt Behavior Contract state on failure. Project-scoped only. |
| `sdp-gate-review-setup.ps1` | Reads the dispatch file and phase document, strips prior Gate Verdict blockquotes for independent assessment, and surfaces prior blocked issues for re-gate cycles. Project-scoped only. |
| `sdp-solution-phase-gate-review-finalize.ps1` | Solution-scoped companion to `sdp-gate-review-finalize.ps1` — same contract, self-resolves the solution root, no `-workspaceRoot`/`-scope` parameter needed |
| `sdp-solution-phase-gate-review-gpg-check.ps1` | Solution-scoped companion to `sdp-gate-review-gpg-check.ps1` |
| `sdp-solution-phase-gate-review-setup.ps1` | Solution-scoped companion to `sdp-gate-review-setup.ps1` |
| `sdp-report-logs-combine.ps1` | Merges one calendar day's `loop-metrics`/`hook-log`/`workflow-log` jsonl files into a single normalized `combined-log-yyyyMMdd.jsonl` under `combined-logs/` |
| `sdp-github.ps1` | CI status checking and git operations (commit, push, PR creation) |
| `sdp-hook-log.ps1` | Async `PreToolUse`/`PostToolUse` hook target; appends raw per-tool-call telemetry to `hook-logs/`, gated per-tool by `sdp-hook-log-tools.json` |
| `sdp-report-log-combined-metrics.ps1` | Reads a selected `combined-logs/combined-log-*.jsonl` file and produces the source/category/role/outcome breakdown and chronological event report spanning all three original logs |
| `sdp-report-log-hook-metrics.ps1` | Reads a selected `hook-logs/hook-log-*.jsonl` file and produces the tool-usage/session/level/work-item breakdown report |
| `sdp-report-log-loop-metrics.ps1` | Reads a selected `loop-logs/loop-metrics-*.jsonl` file and produces the time-accounting/halt/task-outcome report |
| `sdp-report-log-workflow-metrics.ps1` | Reads a selected `workflow-logs/workflow-log-*.jsonl` file and produces the trigger/role/outcome breakdown and chronological event report |
| `sdp-claude-new-terminal.ps1` | Spawns a new Claude Code terminal window from a named launch profile; tracks the instance in `SDP-Terminal-Sessions.json` |
| `sdp-preflight.ps1` | Manifest-driven workspace validation; emits JSON envelope with pass/fail per check |
| `sdp-run-prompt.ps1` | Resolves the active project, reads `sdp-docs/00_prompt.txt`, and emits the next skill to invoke as JSON |
| `sdp-solution-coordinator.ps1` | Reads all child project states, enforces the cycle sync invariant, and writes session dispatch files |
| `sdp-solution-create-prompt.ps1` | Reads `SDP-Solution.json` and solution workflow state for `sdp-solution-create-prompt`'s dispatch prompt template |
| `sdp-solution-reviewer.ps1` | Verifies child preconditions, confirms reviewer outcomes, resolves cascades, and finalizes the solution task verdict |
| `sdp-tone.ps1` | Plays audible tone sequences for workflow events (Windows only — silently skips on macOS/Linux); also appends to `loop-logs/` on every real invocation |
| `sdp-workflow-log.ps1` | Called directly by `sdp-project-coordinator`/`sdp-project-worker`/`sdp-project-reviewer`/`sdp-gate-review-finalize.ps1`; appends semantic workflow-decision events to `workflow-logs/` |

---

## Orchestration Modes

| Mode | How It Works | Best For |
|------|-------------|----------|
| **Human-gated** | COORDINATOR prints dispatch instructions; user manually spawns each subagent | Early projects, high ambiguity |
| **Agent-orchestrated** | COORDINATOR spawns subagents directly via Agent tool | Well-defined task sequences |
| **Loop-orchestrated** | `/sdp-auto` starts `sdp-project-state-loop` on a recurring schedule; loop evaluates sentinel and dispatches automatically | Active development runs with no manual dispatch |

Start with **human-gated**. The sentinel-based loop (`loop-orchestrated`) is the fully automated path — `sdp-project-state-loop` evaluates `sdp-docs/00_prompt.txt` on each fire, dispatches the next subagent, reads state after return, and halts automatically on blocking conditions.

---

## Workspace Setup

> **Open Claude Code at the solution root** — the folder containing `SDP-Solution.json` and `.claude/skills/`. Opening at a project subfolder means no skills are visible and every `/sdp-*` invocation silently fails.

For the condensed step-by-step setup instructions and pre-dispatch gate checklist, see [`QuickStart.md`](QuickStart.md). Full procedure, folder diagrams, and file templates are in [`SDP-Workspace-Setup.md`](sdp-shared/docs/SDP-Workspace-Setup.md).

---

## Standards Document

SDP ships with the GenericProjectGuidlines (GPG) as its built-in standards reference. Four consumer scenarios apply:

| Scenario | When | Action |
|----------|------|--------|
| **A — Use GPG as-is** | The default | No action — GPG is pre-integrated. Proceed to workspace setup. |
| **B — Edit the existing doc to fit your needs and patterns** | You want to keep GPG's structure but tailor chapter content to your project | Edit the chapter directly in the parent doc and mirror the edit to the corresponding section file — no skill re-run required for content-only changes. See Amendment Rules in `SDP-Standards-Setup.md`. |
| **C — Replace with a structured custom doc** | Your doc has identifiable chapters (H1 or H2 headings) | Run `/sdp-standards-setup` |
| **D — Replace with a flat or minimally-structured doc** | Narrative or loosely-structured doc; sections don't map cleanly to GPG topics | Run `/sdp-standards-setup` — Phase 3 will have more gaps; the skill generates stub prose for uncovered topics and asks you to review before writing |

**What `/sdp-standards-setup` automates:** structural enforcement (location, version string, Markdown format), section file scaffolding, TOC generation, cross-reference reading map generation against GPG chapters, fresh-search replacement of all framework file references (skill files, scripts, manifests, bootstrap doc), a sanity check pass, and a verification report. User input is required at two points: chapter confirmation (Phase 1) and reading map review (Phase 3).

**After setup**, each project's `state.json` carries a `standards_version` field whose value is the version key segment of your standards doc filename. Preflight validates that a matching file exists in `standards/` — a mismatch halts the COORDINATOR. When you release a new version of your standards doc, rename the file to include the new version key, update `standards_version` in each project's `state.json`, and run preflight to confirm.

Full procedure, amendment rules, and migration guide for existing solutions: [`SDP-Standards-Setup.md`](sdp-shared/docs/SDP-Standards-Setup.md).

---

## Project Resolution Order

Every skill resolves `[resolved_project]` using three levels in priority order:

1. **Dispatch context** — sentinel `projects=` attribute or session file `Project:` field
2. **Physical path extraction** — `sdp-project_*` segment in the current file path
3. **`SDP-Solution.json`** — `last_active_projects[0]` (user-direct invocations only)

---

## Starting a Session

There are two ways a Phase 1-7 concept cycle gets started, and one required step before any
extended unattended run:

- **New solution** — a fresh session's prompt drives workspace setup (Q1–Q5 interview), which
  scaffolds the solution root (`.sdp-solution-workflow/state.json` starts at
  `current_phase: "concept"`) and the initial project(s). The first `/sdp-solution-phase-coordinator`
  invocation drives Phase 1 (Concept) drafting: `sdp-solution-phase-coordinator` itself runs
  `/brainstorming` interactively with the user before dispatching WORKER, then
  `sdp-solution-phase-worker` formalizes the phase document from what was captured — per the
  bootstrap doc's Phase 1/3 authorship exception (`/brainstorming` is COORDINATOR-scoped only; see
  "Phase 1 / Phase 3 — Interactive Capture Mechanics"). This is a one-time path — it only applies
  to a solution's very first concept cycle.
- **New concept in an existing solution** — run `/sdp-solution-new-concept-intake` at any solution
  maturity. Document-driven: drop one or more source docs in
  `sdp-solution-docs/user-design-docs/` first. Conversational: just describe the concept — no
  file needed. Either way it seeds seven new rows (Concept through Phase Readiness) into the
  **solution's own** `.sdp-solution-workflow/registry.md` and hands off to
  `/sdp-solution-phase-coordinator` dispatch — never to `/sdp-solution-coordinator` (shared-task
  dispatch only) or project-level `/sdp-project-coordinator`.
- **Before starting `/sdp-auto` for an extended unattended run** — the first time solution-level
  Phase 7's gate passes, run `/sdp-solution-loop-prep` once; it sweeps every registered project's
  freshly-decomposed registry (not just one) and hands off to `/sdp-auto` itself. `/sdp-project-loop-prep`
  is the single-project, on-demand counterpart — useful for a targeted re-check outside that
  transition, but not the primary before-first-run step for a multi-project solution. Either way,
  the walk certifies content readiness, source coverage, and right-sizing up front, so gaps
  surface before the run starts instead of stopping it hours in.

```
# Drive phases 1-7 (Concept through Phase Readiness) - use during that stage
/sdp-solution-phase-coordinator

# Shared cross-project task dispatch only - not for phases 1-7
/sdp-solution-coordinator

# Register a new concept cycle mid-solution (document-driven or conversational)
/sdp-solution-new-concept-intake

# Certify every project's registry the first time Phase 7 passes (or a targeted single-project check)
/sdp-solution-loop-prep
/sdp-project-loop-prep

# Start automated loop mode
/sdp-auto

# In a new subagent, execute the current solution-level prompt
/sdp-solution-run-prompt

# Regenerate the solution-level dispatch prompt on demand
/sdp-solution-create-prompt

# Stop the loop
/sdp-cancel-auto
```

The `sdp-initialize-sdp` skill runs automatically at every session start via a `SessionStart` hook — it prints the opening/closing banners and invokes `sdp-solution-read-docs` internally, so no manual pre-read is needed.

---

## Document Lifecycle

```
Phase 1: Concept                 → Gate
Phase 2: Research                → Gate
Phase 3: Expanded Concept        → Gate
Phase 4: Architecture            → Pros-Cons-Gaps (≥2 cycles) → Gate
Phase 5: Implementation Overview → Pros-Cons-Gaps (≥2 cycles) → Gate
Phase 6: Refined Plan            → Acceptance criteria written → Gate
Phase 7: Phase Readiness         → Build-phase decomposition → Gate → Implementation Loop
```

Phases 1-7 are **solution-scoped, not project-scoped** — they run once per solution, driven by
`/sdp-solution-phase-coordinator`, with deliverables at `sdp-solution-docs/*.md` and tracking in
`.sdp-solution-workflow/registry.md`/`state.json`. Project-level identity first appears at Phase
7's decomposition step, which assigns build-phase tasks into each involved project's own
`.sdp-workflow/registry.md` — the Implementation Loop referenced above operates per-project from
that point on, completely unchanged.

Each gate is a separate GATE_REVIEWER session: `sdp-solution-phase-gate-review` for every phases-1-7
gate (always solution-scoped — this skill has no project-level mode). `sdp-project-gate-review` is
project-scoped only — it handles a project's own build-phase gates after Phase 7, and the
legacy case of a project-level "Phase Readiness" gate on a solution still mid-migration to this
model. No phase advances without a `GATE_PASSED` verdict appended to the phase document and
recorded in state.

**This cycle is repeatable, not one-time.** `/sdp-solution-new-concept-intake` seeds a fresh Phase 1-7
mini-cycle into the solution's own registry, at any solution maturity — the same gate/review
machinery above runs against those rows exactly as it did for the first cycle. Phase 7's own
decomposition step carries an explicit sizing signal: decompose remaining scope into as many
cohesive, right-sized build phases as the work actually requires, rather than defaulting to
fewer, larger ones — `sdp-phase-rightsizing-check` is the backstop for anything that still slips
through.

---

## Is It Effective?

**Operational evidence:** In an overnight run, the workflow operated fully unattended, with every role transition handled by an intermediate COORDINATOR and no human involvement.

| Metric | Value |
|---|---|
| Unattended duration | 3.5+ hours |
| Loop fires | 37 |
| Agent sessions | 13 |
| Work items completed (VERIFIED) | 6 |
| Orchestrating session context at end | ~550K / 1M tokens (~55%) |

Subagent sessions each run in their own independent context windows and are not reflected in the context figure above. The 13 agent sessions comprised an initial COORDINATOR plus six complete WORKER / REVIEWER cycles, one per verified work item.

The workflow's state-on-disk architecture means context compaction is not a termination event. When a session's context is compacted, the loop fires again and reads current state from disk — the same files a fresh session would read. Context limits alone will not stop a well-structured workload; the binding constraint becomes the operational halt conditions described in Structural Limitations.

**Development evidence:** The changelog documents ten versions of bug fixes, all traceable to specific observed failures. The `eval_cycle_attempts` guard was added after COORDINATOR agents were observed writing loop-owned fields in dispatch files. The sentinel-based loop dispatch replaced an idle-loop condition that was actually occurring. This is a framework that has been used, broken, and corrected — not only designed.

**What remains unresolved:** Whether the framework produces better software outcomes than unstructured AI development at equivalent token cost. How it performs on workloads substantially different from the one observed (higher rejection rates, more complex debugging tasks). Whether the quality benefits of role isolation outweigh the overhead on smaller or medium-complexity projects.

---

## When to Consider

- Multi-session projects where work cannot complete in a single agent context — the state machine provides continuity, and compaction tolerance means context limits do not cap total workload size.
- Projects where decision audit trails have lasting value: compliance requirements, complex architectural choices, work involving multiple stakeholders or future maintainers.
- Projects with established standards to align against — the GPG alignment mechanism and `.speq` contract pay off when there is something declared to align to.
- Situations where review independence matters and a human reviewer is not available per task.
- Sustained autonomous operation — the framework has demonstrated reliable unattended operation across multi-hour runs with multiple verified work cycles and no human intervention between role transitions.

## When Not to Consider

- Budget-sensitive contexts without a cost estimate — token spend per session is non-trivial and compounds across many sessions. Run a cost estimate before committing the framework to a long project.
- Exploratory or spike work — the phase-gated, append-only model conflicts with high-iteration, discard-often exploration. The workflow assumes enough clarity to write phase documents with acceptance criteria before work begins.
- macOS/Linux environments where PowerShell 7+ is not installed and the user is unwilling to install it.
- Single-session tasks or quick fixes — the three-role cycle adds overhead that exceeds the task scope.

---

## Structural Limitations

**PowerShell 7+ required on macOS/Linux.** Windows ships with PowerShell 5.1 and works out of the box. macOS and Linux require PowerShell 7+ (install from [github.com/PowerShell/PowerShell](https://github.com/PowerShell/PowerShell/releases/latest)). All scripts are cross-platform except `sdp-tone.ps1`, which silently skips audio on non-Windows platforms — workflow operation is unaffected.

**Direct edits outside the workflow are untracked.** The workflow does not prevent direct edits. Those changes won't be reflected in state files, session records, or phase document evaluation history. COORDINATOR detects state/checkbox disagreements during normal operation, but detection requires the workflow to be running. An extended bypass period can let untracked edits diverge significantly from what state files report.

**Halt conditions require human resolution.** Several conditions stop the loop and require a human decision before it resumes: stuck-loop detection exceeding the attempt threshold, `DIAGNOSIS_BLOCKED` tasks, `GATE_BLOCKED` phase gate verdicts, and any condition that sets `workflow_status` to `"halted"`. These are intentional stops. Resolution time ranges from minutes (a user decision unblocks a `DIAGNOSIS_BLOCKED` task) to hours (a `GATE_BLOCKED` verdict identifying real architectural gaps may require substantive design work). Monitoring unattended runs for halt conditions is advisable for long workloads.

**External plugin dependency with acknowledged staleness risk.** The framework depends on the Superpowers plugin for TDD and debugging methodology enforcement. The bootstrap document explicitly warns that skill names may have changed since its reference date and requires a live verification check before every session. A plugin interface change without a corresponding bootstrap update can cause silent failures — a particular risk in overnight unattended runs.

---

## Append-Only Discipline

No content is ever deleted. Superseded decisions use strikethrough in place and a replacement appended immediately after:

```markdown
~~Use PostgreSQL hosted on Render.~~ [2026-01-15]

> Superseded [2026-02-03]: Switched to PlanetScale due to connection pooling requirements.

Use PlanetScale (MySQL-compatible) with Prisma ORM. [2026-02-03]
```

Template placeholder text (`[DATE]`, `[PROJECT]`) is replaced once during initial setup. After that, append-only applies to all files.

---

## Superpowers Plugin Integration

The [Superpowers plugin](https://github.com/obra/superpowers) provides TDD, systematic debugging, brainstorming, and other structured development skills. Install it once:

```
/plugin install superpowers@claude-plugins-official
```

| Feature | COORDINATOR | WORKER | REVIEWER |
|---------|-------------|--------|----------|
| Auto-triggering | ⛔ Disable | ⛔ Disable | ⛔ Disable |
| `/brainstorming` | ✅ Early phases only | ⛔ Role mismatch | ⛔ Role mismatch |
| `/execute-plan` review checkpoints | — | ⛔ Prohibited | — |
| Systematic debugging | — | ✅ Required | — |
| TDD | — | ✅ Required | — |

**Auto-triggering must be disabled** in all Bootstrap sessions. Superpowers skills are invoked explicitly only.

---

## Technical Notes

- **Encoding**: UTF-8 without BOM for all prompt sentinel files; input files read with `-Encoding UTF8` to avoid codepage corruption on Windows
- **Platform**: Windows (PowerShell 5.1+), macOS, Linux (PowerShell 7+ required on macOS/Linux)
- **Session isolation**: New subagent invocation per role, not `/clear` in an existing context
- **State files**: JSON (`state.json`, `[phase]_state.json`) — machine-readable; phase files (`.md` checkboxes + blockquotes) are the human-readable record; both must agree
- **Testing**: Pester suite in `sdp-shared/scripts/tests/` covers prompt generation, BOM handling, sentinel correctness, and halt paths
- **Version management**: Bootstrap doc version in filename and internal `| **Version** |` field must match; mismatch triggers automatic copy + rename procedure

---

## Key Reference Files

| File | Purpose |
|------|---------|
| `standards/GenericProjectGuidlines_V*.md` | Generic project guidelines reference (GPG) |
| `sdp-shared/docs/SDP-Changelog.md` | Bootstrap document version history |
| `sdp-shared/docs/SDP-Flowchart.md` | Stage-by-stage walk through a new project's lifecycle, start to finish |
| `sdp-shared/docs/SDP-Project-Evolution.md` | Cross-project pattern and evolution tracking reference |
| `sdp-shared/docs/SDP-Script-Authoring.md` | Script anatomy, encoding rules, permission registration |
| `sdp-shared/docs/SDP-Skill-Authoring.md` | How to write L1 + L2 skill pairs |
| `sdp-shared/docs/SDP-Standards-Setup.md` | Standards doc replacement procedure, amendment rules, migration guide |
| `sdp-shared/docs/SDP-Tone-Notifications.md` | Audible notification reference (palettes, sequences, events) |
| `sdp-shared/docs/SDP-Workspace-Setup.md` | Full setup procedure with folder diagrams and file templates |
| `SDP_Sapient-Driven-Principles_v1.1.1.md` | Master bootstrap — complete workflow reference |
