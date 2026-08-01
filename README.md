# Sapient-Driven Principles (SDP)

**Autonomous Structure Is the Answer to Unsupervised Autonomy.**

SDP is a governance framework for AI-agent-driven software development, built for to allow you to design while the AI implements. Unsupervised coding agents drift from spec, lose context
across long sessions, silently re-attempt failed fixes, and let their own work go unverified.
SDP addresses this with a structured, auditable process: dedicated agent roles, machine-readable
state, mandatory independent review, and an append-only decision record — rather than a looser
set of prompting guidelines.

Website: [sdp.vegadiscoveries.com](https://sdp.vegadiscoveries.com) — by [Vega
Discoveries](https://www.vegadiscoveries.com)

---

## Why SDP

Four principles, derived from direct experience running AI-assisted development at scale:

1. **Context isolation between work and review.** An agent that performs work and then reviews
   its own work operates with confirmation bias and full context contamination. Work and review
   run in separate subagent sessions with separate context windows — always.
2. **Append-only documentation.** Nothing is deleted. Superseded decisions are struck through in
   place and the replacement appended with a date and rationale. The record of a decision having
   been made is as important as the decision itself.
3. **Parent is authoritative; section/phase files are context-optimized extracts.** Large
   documents are split into extracts agents read to conserve context, with an embedded sync rule
   keeping edits flowing in both directions.
4. **Explicit state, not prose procedures.** Every work item's status lives in a machine-readable
   state file. Agents read state before acting and write state after acting — outcomes are never
   inferred by an orchestrating agent from another agent's own returned text.

Full rationale: [Workflow Philosophy](SDP_Sapient-Driven-Principles_v1.1.0.md#workflow-philosophy)
in the bootstrap document.

---

## Core Concepts

| Concept | Summary |
|---|---|
| **Three roles, one per session** | COORDINATOR (dispatches only, never touches implementation), WORKER (implements, never evaluates its own output), REVIEWER (independently verifies, forms its own understanding of acceptance criteria *before* reading what WORKER claims to have done). A single session — even after `/clear` — may never hold more than one role; only a new subagent invocation provides real isolation. |
| **State machine** | `PENDING → WORK_COMPLETE → VERIFIED` / `REJECTED → PENDING`. Recorded per task in a `[phase]_state.json` file. `REJECTED` tasks take next-dispatch priority. |
| **Phase gates** | Every phase document passes a dedicated GATE_REVIEWER session before the next phase opens. |
| **Material Decision Escalation** | Any dispatched session, any role, is blocked from introducing an external dependency (language, library, cloud provider, third-party API, …) or an architectural pattern with no precedent in your standards doc, until a human decides. |
| **Debugging budget** | One full four-phase cycle (reproduce → isolate → diagnose → fix) per WORKER session. If the fix doesn't hold, the session stops and escalates rather than re-attempting indefinitely. |
| **Two-level skill architecture** | Every `/sdp-*` skill has a thin **Level 1** dispatcher in `.claude/skills/[name]/SKILL.md` and the full procedure in **Level 2**, `sdp-shared/ai-skills/[name]/SKILL.md`. A few skills (e.g. `sdp-tone`) are script-backed and intentionally single-level. |
| **Script vs. skill** | Deterministic, reasoning-free work (read/write JSON, play a tone, validate a manifest) is a PowerShell script in `sdp-shared/scripts/`. Anything requiring LLM judgment is a skill. Scripts are cheaper and cannot hallucinate; skills are used only where reasoning is actually required. |

---

## Requirements

- **[AI Agent]**, opened at the solution root.
- **git**, available on `PATH` — required by the Superpowers plugin integration and
  `sdp-shared/scripts/sdp-github.ps1`.
- **PowerShell** to run `sdp-shared/scripts/*.ps1` (Windows PowerShell 5.1 or cross-platform
  PowerShell 7+/`pwsh`).
- **[Superpowers plugin](https://github.com/obra/superpowers)** (recommended, not required) —
  `/plugin install superpowers@claude-plugins-official`. Supplies TDD and four-phase debugging
  discipline to WORKER sessions. If absent, WORKER applies equivalent discipline manually.
- A standards/guidelines document under `standards/` for the GPG Reading Map and gate reviews to
  reference. This repository ships with the default GenericProjectGuidlines (GPG) document
  pre-integrated (`standards/GenericProjectGuidlines_V1.10_20260323.md` and its section files).
  To use your own instead, see `sdp-standards-setup`.
- For agent-orchestrated or loop-orchestrated dispatch, run Claude Code under its `auto`
  permission mode (`claude --permission-mode auto`) rather than `bypassPermissions`.

---

## Getting Started

1. Copy this repository's contents into your new project's root folder: `.claude/`,
   `sdp-shared/`, `SDP_Sapient-Driven-Principles_v*.md`, `SDP-Config.json` — plus your own
   `standards/` doc (see Requirements above).
2. Open Your AI Agent at that folder. This folder is now the **solution root**.
3. Start a session. The `SessionStart` hook fires `sdp-initialize-sdp` automatically, prints the
   opening banner, and — finding no `SDP-Solution.json` — tells you to run workspace setup.
4. Run `/sdp-workspace-setup`. It asks six questions one at a time (solution name; what the
   solution does, who uses it, what outcome it delivers; which project types make it up; which
   IDE you're pairing with Claude Code; which standards-doc version to use), then presents the
   complete plan for your confirmation before creating anything.
5. From there, SDP walks a solution-scoped concept cycle (Concept → Research → Expanded Concept
   → Architecture → Implementation Overview → Refined Plan → Phase Readiness), decomposes the
   result into per-project work queues, and hands off to the per-project
   COORDINATOR → WORKER → REVIEWER → gate loop. Run `/sdp-auto` once that's stable to make
   dispatch fully unattended.

For the complete step-by-step walk from empty folder to a running unattended loop, see
[`sdp-shared/docs/SDP-Flowchart.md`](sdp-shared/docs/SDP-Flowchart.md).

---

## Orchestration Modes

| Mode | Who spawns the next subagent | Best for |
|---|---|---|
| **Human-gated** | COORDINATOR prints instructions; you start each subagent manually | Early projects, high ambiguity |
| **Agent-orchestrated** | COORDINATOR spawns subagents directly, reads the outcome from the state file after each returns | Well-defined task sequences |
| **Loop-orchestrated** | `/sdp-auto` starts a recurring loop that dispatches, reads state, and repeats | Sustained, unattended runs |

Start human-gated; promote once the workflow has proven stable on your project.

---

## Repository Layout

```
├── SDP_Sapient-Driven-Principles_v*.md   ← bootstrap doc — authoritative workflow procedure
├── SDP-Config.json                       ← loop interval, halt policy, CI gate, preflight timers
├── .claude/
│   ├── skills/[name]/SKILL.md            ← Level 1 — thin dispatcher per skill
│   └── rules/                            ← core invariants + conduct-rules template
├── sdp-shared/
│   ├── ai-skills/[name]/SKILL.md         ← Level 2 — full procedure per skill
│   ├── scripts/*.ps1                     ← deterministic automation (preflight, tone, gate review, logging)
│   └── docs/                             ← reference documentation (see Documentation Map below)
└── standards/                            ← default GenericProjectGuidlines (GPG) standards doc + sections
```

Created by `/sdp-workspace-setup` in your own project (not part of this distribution):
`SDP-Solution.json`, `sdp-solution-docs/`, `.sdp-solution-workflow/`, one
`sdp-project_[name]/` folder per project.

---

## Skill Catalog

All skills are invoked as `/sdp-[name]` inside Claude Code.

### Setup & Onboarding
| Skill | Purpose |
|---|---|
| `sdp-initialize-sdp` | Session-start banner and workspace-context load — fires automatically |
| `sdp-workspace-setup` | First-run scaffold: solution root, and/or a new project added to an existing solution |
| `sdp-standards-setup` | Replace the default standards reference with your own document |
| `sdp-new-concept-intake` | Register a new Phase 1–7 concept cycle mid-project, document- or conversation-driven |

### Solution-Scoped (Phases 1–7 and cross-project dispatch)
| Skill | Purpose |
|---|---|
| `sdp-solution-coordinator` | Cross-project task dispatch for work spanning 2+ projects |
| `sdp-solution-phase-coordinator` | Drives the solution's own Phases 1–7 concept cycle |
| `sdp-solution-phase-worker` / `sdp-solution-phase-reviewer` | WORKER/REVIEWER for phases 1–7 |
| `sdp-solution-phase-gate-review` | Gate review for phases 1–7 |
| `sdp-solution-worker` / `sdp-solution-reviewer` | WORKER/REVIEWER dispatch fan-out for cross-project tasks |
| `sdp-solution-read-docs` | Loads solution + active-project docs into context (three-pathway model) |
| `sdp-solution-create-prompt` / `sdp-solution-run-prompt` | Write / execute the next solution-level dispatch prompt |
| `sdp-solution-state-loop` | Recurring dispatch-gating pass for the post-Phase-7 multi-project regime |
| `sdp-solution-loop-prep` | One-time readiness sweep across every project's freshly decomposed registry |

### Project-Scoped (per-project implementation loop)
| Skill | Purpose |
|---|---|
| `sdp-project-coordinator` | Drives one project's implementation loop |
| `sdp-project-worker` / `sdp-project-reviewer` | WORKER/REVIEWER for a single project task |
| `sdp-project-gate-review` | Phase gate review for a single project |
| `sdp-project-doc-review` | Certifies a staged document before dispatch |
| `sdp-project-read-docs` | Loads solution + this project's docs into context |
| `sdp-project-create-prompt` / `sdp-project-run-prompt` | Write / execute the next project-level dispatch prompt |
| `sdp-project-state-loop` | Recurring loop-fire handler: dispatch, recovery, or continuation |
| `sdp-project-pre-work-verify` | Pre-work artifact scan before a WORKER starts a task |
| `sdp-project-loop-prep` | Targeted readiness sweep for a single project |
| `sdp-phase-rightsizing-check` | Assesses/splits a phase's task volume for unattended-dispatch fitness |
| `sdp-source-coverage-check` | Confirms every element of a tracked source doc reached the downstream phases |

### Automation & Session Management
| Skill | Purpose |
|---|---|
| `sdp-auto` | Opt in to fully unattended dispatch — starts the recurring state loop |
| `sdp-cancel-auto` | Stop the recurring state loop |
| `sdp-state-loop-start` | Validates readiness and starts the loop, priming the first dispatch |
| `sdp-claude-new-terminal` | Launch a new Claude Code terminal from a named launch profile |
| `sdp-evaluate-skill` | Evaluate a skill for deterministic-vs-agent steps and scripting opportunities |

### Reporting
| Skill | Purpose |
|---|---|
| `sdp-report-logs-combine` | Merge one day's loop/hook/workflow logs into a combined file |
| `sdp-report-log-loop-metrics` | Time accounting, halts, task outcomes from a loop-metrics run |
| `sdp-report-log-hook-metrics` | Tool-usage and session breakdowns from a hook-log run |
| `sdp-report-log-workflow-metrics` | Trigger/role/outcome breakdown from a workflow-log run |
| `sdp-report-log-combined-metrics` | Cross-source breakdown from a combined-log run |

---

## Documentation Map

| Question | Doc |
|---|---|
| Why does SDP work this way — the founding principles, roles, state machine, full procedure | `SDP_Sapient-Driven-Principles_v*.md` (this repo's root) |
| Linear walk from empty folder to a running unattended loop | [`sdp-shared/docs/SDP-Flowchart.md`](sdp-shared/docs/SDP-Flowchart.md) |
| Exact folder layout and file templates | [`sdp-shared/docs/SDP-Workspace-Setup.md`](sdp-shared/docs/SDP-Workspace-Setup.md) |
| Writing a new skill (Level 1/Level 2 pair) | [`sdp-shared/docs/SDP-Skill-Authoring.md`](sdp-shared/docs/SDP-Skill-Authoring.md) |
| Writing a new script, script-vs-skill criteria | [`sdp-shared/docs/SDP-Script-Authoring.md`](sdp-shared/docs/SDP-Script-Authoring.md) |
| Replacing the default standards document | [`sdp-shared/docs/SDP-Standards-Setup.md`](sdp-shared/docs/SDP-Standards-Setup.md) |
| Audible tone/tune events | [`sdp-shared/docs/SDP-Tone-Notifications.md`](sdp-shared/docs/SDP-Tone-Notifications.md) |
| Bootstrap document version history | [`sdp-shared/docs/SDP-Changelog.md`](sdp-shared/docs/SDP-Changelog.md) |
| Cross-project pattern tracking | [`sdp-shared/docs/SDP-Project-Evolution.md`](sdp-shared/docs/SDP-Project-Evolution.md) |

None of the `sdp-shared/docs/*.md` reference files are loaded into agent context automatically —
load them explicitly when the task calls for them.

---

## License

Licensed under the [Business Source License 1.1](LICENSE). You may use, copy, modify, and make
production use of SDP for any purpose — including commercial projects you build with it — at no
charge. The one carve-out: SDP itself (or a product whose primary value is SDP's own
orchestration/workflow functionality) may not be offered to third parties as a hosted or managed
service without a separate commercial license from Vega Discoveries.

Each version converts to the [Apache License, Version 2.0](https://www.apache.org/licenses/LICENSE-2.0)
four years after its release (Change Date for this version: **2030-07-31**). See
[`LICENSE`](LICENSE) for the complete, binding terms — this section is a summary, not a
substitute.

```
SPDX-License-Identifier: BUSL-1.1
```

See also [`DISCLAIMER.md`](DISCLAIMER.md) for risk, warranty, and liability disclosures specific
to AI-agent behavior under this Framework.

---

## Links

- Website: [sdp.vegadiscoveries.com](https://sdp.vegadiscoveries.com)
- Vega Discoveries: [www.vegadiscoveries.com](https://www.vegadiscoveries.com)
