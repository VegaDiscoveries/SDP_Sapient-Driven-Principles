# AI-Assisted Development Workflow — Bootstrap Document

| Field | Value |
|-------|-------|
| **Version** | 1.1.0 |
| **Patterns** | 0 |
| **Updated** | 2026-07-18 |
| **File** | `SDP_Sapient-Driven-Principles_v1.1.0.md` |

**Purpose:** When this file is read by an agent in a new workspace, it serves as complete instructions
for setting up the workspace structure and initiating the development workflow described herein.

---

## Changelog

> **Version history is in [`SDP-Changelog.md`](sdp-shared/docs/SDP-Changelog.md).**
> When incrementing the bootstrap version: add a new row at the top of the table in
> `SDP-Changelog.md` — do not add entries here.

---

## Agent Read Instructions

> **If you are an agent reading this file:** Before taking any action, check whether a
> `~SDP-Maintenance` folder exists at the solution root.
>
> **If `~SDP-Maintenance` exists:** This is the SDP framework development workspace. The user
> is working on SDP itself — improving skills, scripts, or the bootstrap doc. Do not run the
> new-project setup wizard. Confirm: "Opened SDP bootstrap workspace — ready for maintenance
> or improvements." Await the user's instruction.
>
> **If `~SDP-Maintenance` does not exist — new workspace:** Read this entire document before
> taking any action. Your first task is to execute the [Workspace Setup](#workspace-setup) section
> to scaffold the folder structure and template files. Do not begin any project work until setup
> is complete and the user has confirmed readiness. Before creating any files or folders, collect
> the following from the user — one question at a time:
> 1. Derive a preliminary solution name from the root folder name and propose it for confirmation or correction.
> 2. Ask Q1–Q3 to compose a synopsis: (Q1) what does this solution do, (Q2) who uses it,
>    (Q3) what outcome does it deliver? Draft the synopsis from the answers and confirm with the user.
> 3. Ask Q4: what project types make up this solution (e.g. API, Domain/library, Web frontend,
>    Database)? Derive and propose the full `sdp-project_*` folder list for confirmation.
>    Use PascalCase dotted naming: `sdp-project_[AppName].[Type]`.
> 4. Ask Q5: what development environment will be used alongside Claude Code — Visual Studio,
>    VS Code, Rider, agent-only, or other? Visual Studio / Rider → creates `[SolutionName].sln`;
>    VS Code → creates `[SolutionName].code-workspace`; agent-only → no IDE file created.
> 5. **[Addition — 2026-07-19]** Ask Q6: detect the GPG standards doc version present in
>    `standards/` (e.g. `GenericProjectGuidlines_V1.10_20260323.md`) and explicitly ask the user
>    to confirm this is the version they intend, or name a different one — a filesystem check can
>    prove the file exists, not that it is the version the user wants. Previously this was only a
>    manual "confirm before proceeding" note under `SDP-Workspace-Setup.md`'s later infrastructure
>    -verification step, which ran after scaffolding had already begun; this addition makes it an
>    explicit setup question asked here, before any scaffolding begins.
> ~~5.~~ **6.** Run the conduct-rules check (no user question needed — agent judgment): read
>    `~/.claude/CLAUDE.md` and any existing project-level `.claude/CLAUDE.md` / `.claude/rules/*.md`,
>    compare against `.claude/rules/sdp-agent-conduct.md.template` per rule ID, and determine whether
>    to skip activation (full match), activate with duplicates trimmed (partial match), or activate
>    in full (no match). `.claude/rules/sdp-core-invariants.md` ships as a real, already-active file
>    and needs no setup action. Full procedure in `SDP-Workspace-Setup.md`.
>
> Then present the complete setup plan — solution name, synopsis text, project list, IDE file
> to be created (or "none" for agent-only), ~~and the conduct-rules outcome from step 5~~ the
> confirmed GPG standards version from Q6, and the conduct-rules outcome from step 6 — and wait
> for explicit user confirmation before creating anything. The confirmed solution name populates
> `SDP-Solution.json`. The synopsis is written to `README.md` at the solution root. All projects
> from Q4 are scaffolded and registered simultaneously. The IDE workspace file from Q5 is created
> at the solution root.

### Version Check — Perform Before Reading Further

Before reading any further content in this file, scan the workspace root for all files matching
`SDP_Sapient-Driven-Principles_v*.md`. Extract the version number from each filename (the segment between
`_v` and `.md`). Compare them numerically — segment by segment, major.minor.patch. If any file
has a higher version number than the file currently being read, stop reading this file and switch
to the highest-versioned file found. That file is authoritative for the remainder of the session.
Do not continue processing the current file after a version switch.

### Version Change Procedure

**Version numbers are set exclusively by the user.** An agent must never change the
`| **Version** |` field for any reason — not for edits, additions, or corrections. Only a
user-initiated version number change triggers this procedure.

When the internal `| **Version** |` field in the header table does not match the version embedded
in the current filename, the user has updated the version without a corresponding filename copy.
Execute this procedure immediately upon detecting the mismatch — do not defer it:

1. Determine the new version: the value in `| **Version** |` is the target version.
2. Create a copy of the current file named `SDP_Sapient-Driven-Principles_v[NEW_VERSION].md` in the same
   directory.
3. In the copy only, update the `| **File** |` row to `SDP_Sapient-Driven-Principles_v[NEW_VERSION].md`.
   Do not modify the original file.
4. Update `SDP-Document-List.json` at the workspace root: replace any existing
   `SDP_Sapient-Driven-Principles_v*.md` entry with the new filename
   `SDP_Sapient-Driven-Principles_v[NEW_VERSION].md`.
5. The copy is now the authoritative bootstrap file for the remainder of the session. All
   subsequent reads and edits target the copy. The original file is the prior-version record and
   must not be modified.
6. Notify the user: "Detected version mismatch — created `SDP_Sapient-Driven-Principles_v[NEW_VERSION].md`
   as the authoritative copy and updated `SDP-Document-List.json`. Continuing from
   that file."

**Trigger:** A mismatch between the internal version field and the filename version is the trigger.
This is detected at first read; the procedure runs before any other action is taken.

---

## Workflow Philosophy

This workflow is built on four principles derived from direct experience with AI-assisted development:

1. **Context isolation between work and review.** An agent that performs work and then reviews its
   own work operates with confirmation bias and full context contamination. Work and review must
   occur in separate sessions with separate context windows.

2. **Append-only documentation.** No content is deleted. Superseded decisions are marked with
   strikethrough. Evaluations and verification outcomes are appended with timestamps. This preserves
   the full decision history and makes it possible to understand *why* the current state exists.

3. **Parent is authoritative; section/phase files are context-optimized extracts.** The parent
   document is the record of truth. Section and phase files are extracts that agents use to
   conserve context — reading one file instead of the full parent. Each file carries an embedded
   sync rule notice ensuring edits flow in both directions. A TOC file in each section/phase folder
   provides the authoritative chapter index, status tracking, and explicit maintenance instructions.
   Sync is enforced by rule notice, not by tooling — validated in practice on a large project.

4. **Explicit state, not prose procedures.** Work item state is machine-readable. An agent reads
   state before acting and writes state after acting. No agent infers current position from prose.

---

## Agent Roles

Three distinct roles operate in this workflow. A single session must never perform more than one role.

### COORDINATOR
- Reads `state.json` and the work item registry
- Determines the next valid action (dispatch WORKER, dispatch REVIEWER, block on rejection)
- Never touches implementation files, source code, or section files in `[doc_name]_Sections/`
  or `[doc_name]_Phases/`. Writing to early-phase docs (`sdp-solution-docs/01_concept.md`,
  ~~`sdp-solution-docs/02_expanded_concept.md`~~ [2026-07-21: stale filename — see Correction
  below] `sdp-solution-docs/03_expanded_concept.md`) and their corresponding section files when
  executing a `/brainstorming` capture session is permitted and does not constitute an
  implementation file edit. See "Phase 1 / Phase 3 — Interactive Capture Mechanics" below for how
  this capture actually happens in the solution-scoped phases-1-7 pipeline.

  > **Correction — 2026-07-21:** This bullet still named `02_expanded_concept.md` — the filename
  > from before the 2026-07-18 phase renumbering (5→7 phases) moved Expanded Concept from Phase 2
  > to Phase 3. Every other bootstrap-doc reference to this file already reads
  > `03_expanded_concept.md`; this was the one instance the renumbering task missed. See
  > `~SDP-Maintenance/~docs/phase-1-3-interactive-capture-design.md` for full rationale (found
  > while closing the related Phase 1/3 interactive-capture gap below).
- May run as a persistent orchestration loop or be invoked on demand by the user
- Writes dispatch instructions to `sessions/session-NNN.md` before handing off

### WORKER
- Receives a single work item assignment from COORDINATOR
- Reads the assigned task from the phase file — task description is the spec; states acceptance criteria explicitly before starting work
- Performs the implementation
- Appends Completed blockquote to the phase file: what was done, decisions made, deviations, build status
- Updates `[phase]_state.json` to `WORK_COMPLETE`
- Does not evaluate its own output against acceptance criteria
- Session ends after status update

### REVIEWER
- Receives a single work item assignment from COORDINATOR (a different subagent invocation than the WORKER)
- Reads the assigned task from the phase file independently — forms its own understanding of acceptance criteria without reading the Completed blockquote first
- Reads the Completed blockquote to understand what WORKER claimed to do
- Independently verifies (reads code, runs tests, checks against each criterion in the task description)
- Appends Eval N blockquote to the phase file: findings, pass/fail per criterion, specific evidence for each finding
- Updates `[phase]_state.json` to `VERIFIED` or `REJECTED` with reason
- If REJECTED: appends specific rejection context as a Scope note in the phase file for the next WORKER session
- Session ends after status update

---

## Superpowers Plugin Integration

> **Terminology — SP vs SDP**
> Throughout this document, **"Superpowers"** and **"SP"** refer to the third-party Claude
> plugin by Jesse Vincent. **"SDP"** and the `sdp-` skill prefix refer to this workflow
> system (Sapient Driven Principles). The two are independent. SP provides methodology skills
> (TDD, debugging, brainstorming, etc.) that SDP sessions invoke at defined points. SDP
> skills (~~`sdp-coordinator`~~ `sdp-project-coordinator`, ~~`sdp-worker`~~ `sdp-project-worker`, ~~`sdp-reviewer`~~ `sdp-project-reviewer`, etc.) orchestrate the workflow.
>
> **Correction — 2026-07-24:** This example list still named `sdp-reviewer` — renamed to
> `sdp-project-reviewer` as part of the `sdp-project-*` scope-prefix rename (see
> `project-scope-skill-naming-design.md`).
>
> **Correction — 2026-07-24:** This example list also still named `sdp-worker` — renamed to
> `sdp-project-worker` as part of the same `sdp-project-*` scope-prefix rename (see
> `project-scope-skill-naming-design.md`).
>
> **Correction — 2026-07-24:** This example list also still named `sdp-coordinator` — renamed to
> `sdp-project-coordinator` as the last skill in the same `sdp-project-*` scope-prefix rename
> (see `project-scope-skill-naming-design.md`).

Superpowers is a third-party Claude Code plugin (creator: Jesse Vincent; ~787k installs) that
provides composable skills enforcing structured development methodologies: TDD, four-phase
debugging, brainstorming, batched plan execution with checkpoints, and code review. It is not
a built-in Claude Code skill.

Install (one command inside an active Claude Code session):

```
/plugin install superpowers@claude-plugins-official
```

Verify installation: `/plugin list`

### Integration Policy

The Bootstrap's context isolation principle — separate sessions for work and review — governs
which Superpowers features are permitted in each role. Features that cross the work/review
boundary in a single session directly conflict with Bootstrap's structural guarantee.

| Superpowers Feature | COORDINATOR | WORKER | REVIEWER |
|---------------------|-------------|--------|----------|
| TDD (red-green-refactor) | — | ✅ Required — standing instruction | — |
| Debugging (four-phase root cause) | — | ✅ Required — standing instruction | — |
| `/verification-before-completion` | — | ✅ Required — before writing the Completed blockquote | — |
| `/execute-plan` review checkpoints | — | ⛔ Violates context isolation — prohibited | — |
| `/brainstorming` | ✅ Early phases only + capture rule | ⛔ Role mismatch | ⛔ Role mismatch |
| `/receiving-code-review` | — | ✅ Required — when a task returns from a REJECTED eval | — |
| `/dispatching-parallel-agents` | — | ⚠️ Optional — 2+ independent research reads needed | ⚠️ Optional — 2+ independent verification reads needed |
| `/requesting-code-review` | — | — | ⚠️ Optional thinking aid before dispatching verification sub-agents — formal Eval blockquote still required |
| `/finishing-a-development-branch` | ⚠️ Optional — when all tasks in the current phase are VERIFIED and the gate has passed | — | — |
| `/writing-plans` | ⛔ Conflicts with SDP phase document structure — do not use | ⛔ | ⛔ |
| `/using-git-worktrees` | — | ⛔ SDP isolation is at subagent session level; worktrees are redundant — do not use | — |
| `/subagent-driven-development` | ⛔ Redundant with SDP model — do not use | ⛔ | ⛔ |
| Auto-triggering | ⛔ Disable | ⛔ Disable | ⛔ Disable |

**Auto-triggering policy:** Superpowers skills must be invoked explicitly in all Bootstrap
sessions. Auto-triggering must be disabled or ignored. Auto-triggered skills during any
Bootstrap role session can cause agents to drift outside their constrained role.

**`/execute-plan` prohibition:** `/execute-plan` includes built-in review checkpoints in the
same session as implementation. This directly violates Bootstrap's work/review isolation. WORKER
sessions must never use `/execute-plan` review checkpoints. The COORDINATOR dispatches a
separate REVIEWER session — that is the only valid review step.

**Brainstorming capture rule:** ~~`/brainstorming` is permitted during Phase 1 (Concept) and
Phase 2 (Expanded Concept) sessions only.~~ [2026-07-18: renumbered — see Correction below]
`/brainstorming` is permitted during Phase 1 (Concept) and Phase 3 (Expanded Concept) sessions
only — Phase 2 is now "Research" (an automated fan-out, not a brainstorming session; see that
phase's entry) and is not brainstorming-eligible. All output — every decision, constraint, and design
choice surfaced — must be transcribed into the append-only phase document and its corresponding
section files before the session closes. Brainstorming output that exists only in chat history
is invisible to future agents and is not part of the audit trail.

> **Correction — 2026-07-18:** Phase renumbering (5→7 phases, this version) moved "Expanded
> Concept" from Phase 2 to Phase 3. This line is the only other bootstrap-doc reference to
> "Phase 2" as a specific ordinal that needed updating for that reason (the GPG Reading Map and
> Document Lifecycle references are handled in their own tasks).

#### Phase 1 / Phase 3 — Interactive Capture Mechanics

> **Addition — 2026-07-21:** the capture rule above states *when* `/brainstorming` is permitted
> but never stated *who* runs it or how its output reaches a WORKER dispatch in the solution-scoped
> phases-1-7 pipeline — a real gap, not just an underspecified detail: it was implemented nowhere.
> Neither `sdp-solution-phase-coordinator/SKILL.md` nor `sdp-solution-phase-worker/SKILL.md`
> contained a single mention of brainstorming before this addition, so every Phase 1 and Phase 3
> dispatch ran as a fully non-interactive WORKER task — discovered when a user testing SDP in a
> separate project expected an interactive Phase 3 session and got a silent subagent instead. See
> `~SDP-Maintenance/~docs/phase-1-3-interactive-capture-design.md` for full rationale.

The Superpowers Integration Policy table above already scopes `/brainstorming` to **COORDINATOR
only** — WORKER and REVIEWER are both "Role mismatch." The mechanism now matches that scoping:

1. Before `sdp-solution-phase-coordinator` writes a WORKER dispatch file for Phase 1 (Concept) or
   Phase 3 (Expanded Concept), it runs `/brainstorming` interactively with the user **in the
   COORDINATOR session itself** — the Role definition's carve-out above exists for exactly this.
1a. **[2026-07-21 addition]** Before opening the brainstorming session, COORDINATOR reads this
   cycle's tracked source document — the `source_document` field `sdp-new-concept-intake` writes
   to the Concept phase's state file, if this cycle was document-driven (absent for conversational
   intake, in which case this sub-step is skipped) — and brings the source file(s) under
   `sdp-solution-docs/user-design-docs/processed/` into the session, not just the derived Phase 1
   concept document. Phase 1 is a deliberate compression of the source; drafting Phase 1 or Phase 3
   from the compression alone, without the original, risks losing detail the compression already
   dropped. This is a proactive complement to `sdp-source-coverage-check`, not a replacement for
   it — that check still runs as the mandatory backstop after drafting.
1b. **[2026-07-21 addition, same day follow-up]** COORDINATOR states what it read, by name — the
   tracked source file's actual path (or "no tracked source document for this cycle" if 1a's field
   was absent), `01_concept.md`, and (Phase 3) `02_research_findings.md` — before opening the
   brainstorming conversation. A summary that only gestures at "the tracked source" without naming
   the file is insufficient: the user has no way to tell from that phrasing alone whether 1a
   actually resolved and read a file, or silently found nothing to read. Discovered when a user
   testing SDP received exactly this kind of vague confirmation and could not tell which case it
   was without inspecting raw tool-call history.
2. Every decision, constraint, and design choice the brainstorming session surfaces is transcribed
   into the phase document (`sdp-solution-docs/01_concept.md` or `03_expanded_concept.md`) —
   append-only, same as any other phase content — before the COORDINATOR session closes. This
   satisfies the capture rule's existing "must be transcribed... before the session closes"
   requirement; it was never actually enforceable before because no session ever ran
   `/brainstorming` in the first place.
3. COORDINATOR then dispatches WORKER as normal. WORKER's job for this task is to finish and
   formalize the phase document to the task's full specification **from the material COORDINATOR
   already captured** — WORKER does not originate Phase 1/3 content from nothing, but it still
   performs the actual drafting pass. This keeps Role Separation intact: COORDINATOR's exception is
   scoped to interactive capture only, not final authorship of the deliverable.

~~For Phase 3 specifically, COORDINATOR's brainstorming session brings `01_concept.md` and
`02_research_findings.md` into the conversation as the material being expanded and merged — see
the Phase 3 Mechanics entry below.~~

> **Correction — 2026-07-21 (same day, follow-up):** the line above omitted the tracked source
> document — item 1a now covers that for both phases. Restated: for Phase 3 specifically,
> COORDINATOR's brainstorming session brings `01_concept.md`, `02_research_findings.md`, and (per
> item 1a, when one exists for this cycle) the tracked source document into the conversation as
> the material being expanded and merged — see the Phase 3 Mechanics entry below.

**WORKER TDD and debugging:** These are the only Superpowers features added as standing
instructions to WORKER sessions. They are execution aids that stay entirely within the WORKER
role boundary. COORDINATOR must include them in dispatch instructions for all implementation
tasks.

### WORKER Invocation Reference

> ⚠️ **Staleness notice:** Skill names and slash command syntax are sourced from
> [github.com/obra/superpowers](https://github.com/obra/superpowers) as of 2026-06-09.
> Before authoring ~~`sdp-worker`~~ `sdp-project-worker`, verify these names are current: run
> `/plugin list` to confirm the plugin is installed, then run `/using-superpowers` (or check the
> repo) to confirm current skill names. If command names have changed, use the current names and
> update this section.
>
> **Correction — 2026-07-24:** This notice still named `sdp-worker` — renamed to
> `sdp-project-worker` as part of the `sdp-project-*` scope-prefix rename (see
> `project-scope-skill-naming-design.md`).

The plugin's default behavior is contextual auto-triggering. Bootstrap sessions disable
auto-triggering and require explicit invocation — the agent must call each skill at the correct
moment rather than waiting for it to activate.

In Claude Code, skills are invoked as slash commands following the pattern `/[skill-name]`.

| Skill | Slash command | When WORKER invokes it |
|-------|---------------|----------------------|
| Test-driven development | `/test-driven-development` | Before writing any implementation code — tests must fail (red) before implementation begins |
| Systematic debugging | `/systematic-debugging` | Before any fix attempt — four-phase root cause analysis: reproduce, isolate, diagnose, fix. One full cycle is the fix budget. If the diagnosed fix fails, apply step 10 (Debugging Escalation Rule) — document diagnosis and halt rather than re-attempting. |

**Full skill catalog** (confirmed from repo as of 2026-06-09):

| Category | Skill name | Slash command |
|----------|-----------|---------------|
| Testing | `test-driven-development` | `/test-driven-development` |
| Debugging | `systematic-debugging` | `/systematic-debugging` |
| Debugging | `verification-before-completion` | `/verification-before-completion` |
| Collaboration | `brainstorming` | `/brainstorming` |
| Collaboration | `writing-plans` | `/writing-plans` |
| Collaboration | `executing-plans` | `/executing-plans` |
| Collaboration | `dispatching-parallel-agents` | `/dispatching-parallel-agents` |
| Collaboration | `requesting-code-review` | `/requesting-code-review` |
| Collaboration | `receiving-code-review` | `/receiving-code-review` |
| Collaboration | `using-git-worktrees` | `/using-git-worktrees` |
| Collaboration | `finishing-a-development-branch` | `/finishing-a-development-branch` |
| Collaboration | `subagent-driven-development` | `/subagent-driven-development` |
| Meta | `writing-skills` | `/writing-skills` |
| Meta | `using-superpowers` | `/using-superpowers` |

Skills not listed in the table above have no Bootstrap-sanctioned use in any role session —
invoke only the skills explicitly permitted in the Integration Policy table.

---

## State Machine

Each task has exactly one state at any time, recorded in the phase state file
(`[phase]_state.json`). The phase file (checkbox + blockquotes) is the human-readable record;
the state file is the machine-readable index. Both must agree — COORDINATOR detects and flags
disagreement (e.g. checkbox `[x]` but state still `PENDING`).

Valid transitions:

```
PENDING
  └─► WORK_COMPLETE  (WORKER appends Completed blockquote + updates state file)
        └─► VERIFIED     (REVIEWER appends Eval+Verified blockquotes, outcome pass)
        └─► REJECTED     (REVIEWER appends Eval+Verified blockquotes, outcome fail)
              └─► PENDING (COORDINATOR resets; REJECTED task takes dispatch priority)
```

COORDINATOR reads all phase state files before each dispatch. A REJECTED task blocks
dispatch of new tasks in the same phase until resolved. Tasks in other phases may proceed
if they have no dependency on the rejected phase.

---

## Document Lifecycle and Phase Gates

Project documentation advances through phases. Each phase produces a document. Each document
must pass a gate (a REVIEWER session) before the next phase begins.

> **Superseded — 2026-07-18 — expanded to 7 phases.** The 5-phase diagram below is the
> pre-2026-07-18 pipeline, kept for historical reference (any project still running under
> `SDP_Sapient-Driven-Principles_v1.0.0.md` per the Version Change Procedure's "freeze on
> starting version" rule uses this shape). See `~SDP-Maintenance/~docs/phase-pipeline-expansion-design.md`
> for full rationale.
>
> ```
> Phase 1: Concept
>   └─► [Gate: concept review]
> Phase 2: Expanded Concept
>   └─► [Gate: expanded concept review]
> Phase 3: Architecture
>   └─► [Pros-cons-gaps cycle × 2-N iterations within this phase (N set by COORDINATOR)]
>   └─► [Gate: architecture review]
> Phase 4: Implementation Overview
>   └─► [Pros-cons-gaps cycle × 2-N iterations within this phase (N set by COORDINATOR)]
>   └─► [Gate: implementation overview review]
> Phase 5: Refined Implementation Plan
>   └─► [Acceptance criteria written for each work item before any work begins]
>   └─► [Gate: plan review]
>   └─► Work items created → Implementation Loop begins
> ```

**Current pipeline (v1.1.0 onward):**

```
Phase 1: Concept
  └─► [Gate: concept review]
Phase 2: Research
  └─► [Internal WORKER fan-out — one child subagent per research angle, no new agent role]
  └─► [Gate: research review]
Phase 3: Expanded Concept
  └─► [COORDINATOR-run /brainstorming capture, then WORKER formalizes — see Phase 3 entry below]
  └─► [Gate: expanded concept review]
Phase 4: Architecture
  └─► [Pros-cons-gaps cycle × 2-N iterations within this phase (N set by COORDINATOR)]
  └─► [Gate: architecture review]
Phase 5: Implementation Overview
  └─► [Pros-cons-gaps cycle × 2-N iterations within this phase (N set by COORDINATOR)]
  └─► [Gate: implementation overview review]
Phase 6: Refined Implementation Plan
  └─► [Acceptance criteria written for each work item within this plan's own explicit scope]
  └─► [Gate: plan review]
Phase 7: Phase Readiness
  └─► [Build-phase decomposition into registry.md rows]
  └─► [Full-lifecycle source-doc traceability audit — may trigger a backward current_phase
       regression to an earlier phase; see "Phase Readiness Regression Procedure" below]
  └─► [Gate: readiness review]
  └─► Work items created → Implementation Loop begins
```

> **Correction — 2026-07-20 — phases 1–7 are solution-scoped.** Every phase in the pipeline
> above runs **once per solution**, never once per project — driven by ~~`sdp-solution-coordinator`~~
> [2026-07-22: superseded — see Correction below] `sdp-solution-phase-coordinator` (a dedicated
> companion skill; `sdp-solution-coordinator` itself never reaches phases-1–7 dispatch logic — see
> `~SDP-Maintenance/~docs/solution-phase-dispatch-gap-design.md`), with
> deliverables at `sdp-solution-docs/*.md`, tracked via `.sdp-solution-workflow/registry.md` and
> `.sdp-solution-workflow/state.json`. Project-level identity first appears at Phase 7's
> decomposition step, which assigns build-phase tasks into each project's own (previously empty)
> `.sdp-workflow/registry.md`. Everything in the Implementation Loop section below this one
> continues to operate per-project, completely unchanged — that machinery only ever begins after
> Phase 7's gate passes. See
> `~SDP-Maintenance/~docs/solution-coordinator-orchestration-design.md` §2, §6 for full rationale.

> ~~**Addition — 2026-07-13 — Phase 5 sizing signal:** Phase 5's job is not limited to writing
> acceptance criteria for a single Refined Implementation Plan document — it is also where the
> project's remaining scope is decomposed into the actual build phases (Phase 6 onward) that the
> Implementation Loop will execute.~~ [2026-07-18: superseded — see Correction below]
>
> **Correction — 2026-07-18:** Build-phase decomposition responsibility moved from Phase 5 to
> the new Phase 7 (Phase Readiness) — see that phase's entry below. What follows in this
> blockquote (the rightsizing bias itself) is unchanged and now applies to Phase 7's
> decomposition step instead. When performing that decomposition, bias toward more,
> smaller, cohesive, independently-completable phases over fewer large ones. A build phase
> should represent a unit of work a single WORKER dispatch sequence can reasonably complete
> without a mid-session discovery that the scope is too large — a WORKER making that discovery
> reactively, instead of it being caught proactively during ~~Phase 5~~ Phase 7 planning, is the
> failure mode this note exists to prevent. [2026-07-18: fixed — "Phase 5" here contradicted this
> same paragraph's own opening Correction sentence above.] Create as many phase documents and
> `registry.md` rows as the
> actual scope requires; do not consolidate unrelated or oversized work into one phase for
> convenience. ~~`sdp-loop-prep`~~ `sdp-project-loop-prep`'s `sdp-phase-rightsizing-check` pass (see
> ~~`sdp-shared/ai-skills/sdp-loop-prep/SKILL.md`~~ `sdp-shared/ai-skills/sdp-project-loop-prep/SKILL.md`) is the backstop for anything that still slips
> through this signal — it is not the primary defense.
>
> **Correction — 2026-07-23:** This note's skill reference still named `sdp-loop-prep` —
> renamed to `sdp-project-loop-prep` as part of the `sdp-project-*` scope-prefix rename (see
> `project-scope-skill-naming-design.md`).

### Phase 1 — Source-Doc Intake Ownership

> **Addition — 2026-07-18:** `sdp-solution-docs/user-design-docs/` (the drop zone for
> pre-existing user design docs/notes) and the mandatory `sdp-source-coverage-check` step existed
> only in Level 2 skill files (`sdp-new-concept-intake`, `sdp-source-coverage-check`) before this
> addition — never in this section, despite this section being the authoritative parent for phase
> gates. Phase 1's bootstrap-doc entry now explicitly owns this path:
>
> 1. Check `sdp-solution-docs/user-design-docs/processed/` for existing files.
> 2. **If empty** (no intake has happened yet): proactively ask the user — "Do you have any
>    existing design docs, notes, or write-ups on this concept already? SDP can incorporate them
>    into Phase 1 rather than starting from a blank concept doc." This is a deliberate onboarding
>    moment for new users who wouldn't otherwise know document-driven intake exists.
>    - If yes: tell them where to place files (`sdp-solution-docs/user-design-docs/`) and invoke
>      `/sdp-new-concept-intake` to process them before drafting `sdp-solution-docs/01_concept.md`.
>    - If no: ~~proceed with conversational intake as today — no source doc, no behavior
>      change.~~ [2026-07-20: superseded — see Correction below]
> 3. **If files already exist in `processed/`:** intake already happened — skip the prompt, draft
>    `sdp-solution-docs/01_concept.md` from the tracked source as today.
> 4. `sdp-source-coverage-check` runs immediately after Phase 1 and Phase 3 (Concept and
>    Expanded Concept, under this version's numbering) are drafted, comparing the tracked source
>    doc against `sdp-solution-docs/01_concept.md`/`sdp-solution-docs/03_expanded_concept.md` for
>    coverage — mandatory, not optional.
>
> See `~SDP-Maintenance/~docs/phase-pipeline-expansion-design.md` §2 for full rationale.
>
> **Correction — 2026-07-20:** The struck-through "if no" branch collapsed two materially
> different situations into one — "I'll describe it live and skip document creation entirely"
> and "I don't have a doc yet but want to develop one properly" were never distinguished. It now
> branches further:
>    - **No docs, want to develop one:** run `/brainstorming` to develop the concept — direct it
>      to save the resulting spec to `sdp-solution-docs/user-design-docs/` (not Superpowers' own
>      default `docs/superpowers/specs/` location) — then invoke `/sdp-new-concept-intake`, which
>      picks it up via its existing document-driven mode exactly as if it had been hand-dropped.
>      No change to `sdp-new-concept-intake` itself was needed or made.
>    - **No docs, want to seed directly from conversation:** proceed with conversational intake
>      as before — no source doc, no coverage-check applies to this cycle. Still the right choice
>      for genuinely trivial concepts that don't warrant full brainstorming rigor.
>
> See `~SDP-Maintenance/~docs/concept-intake-brainstorm-path-design.md` for full rationale.

### Phase 2 — Research

**Trigger:** COORDINATOR dispatches a WORKER-role task for Phase 2 immediately after Phase 1's
gate passes. No new agent role — this is a WORKER session with an internal fan-out step.
Mandatory, no opt-out: Phase 2 dispatches unconditionally for every project once Phase 1's gate
passes.

**Mechanics:**

1. WORKER reads `sdp-solution-docs/01_concept.md` and derives research angles — however many are
   genuinely distinct (agent judgment; no fixed floor or ceiling).
2. WORKER populates a research-dispatch prompt (same file-based handoff pattern as
   `sdp-solution-docs/00_solution_prompt.txt`, scoped to this fan-out) specifying: the angle list,
   ~2–4 searches per angle as a starting guideline, the deliverable path
   (`sdp-solution-docs/02_research_findings.md`), and required structure (one section per angle).
3. WORKER spawns exactly one child subagent per angle via the Agent tool — no batching multiple
   angles into one child — each performing web search/fetch against its angle only, blind to
   the other angles' findings.
4. WORKER (parent) synthesizes child findings into `sdp-solution-docs/02_research_findings.md`,
   structured per angle, every material claim carrying a source URL and retrieval date.
5. WORKER appends the Completed blockquote and sets phase state to `WORK_COMPLETE` as normal —
   the existing WORKER session contract (steps 11–15 of the Implementation Loop) applies
   unchanged.

**Gate — Research review (REVIEWER session):**

- **Angle coverage:** every angle identified in step 1 has a corresponding findings section.
- **Source citation:** every material claim traces to a named, fetched source (URL + retrieval
  date).
- **Currency:** REVIEWER flags findings resting on stale sources when currency plausibly
  matters to the concept.
- **Actionability:** findings are structured so Phase 3 (Expanded Concept) can cite them
  directly by angle.

**Orchestration-mode fit:** the fan-out is entirely internal to the single WORKER session —
COORDINATOR still dispatches one WORKER task and reads one outcome from `[phase]_state.json`
afterward, same as any other phase. No new `orchestration_mode` value; does not touch Core
Invariant 7 (outcome detection via state file only) — child-subagent text is consumed only by
the parent WORKER, never read by COORDINATOR directly.

See `~SDP-Maintenance/~docs/phase-pipeline-expansion-design.md` §3 for full rationale.

### Phase 3 — Expanded Concept

> **Addition — 2026-07-21:** Phase 3 previously had no Mechanics entry at all — Phase 2 and
> Phase 7 both do. The only existing hint that Phase 3 must incorporate Phase 2's findings was
> Phase 2's own gate criterion ("Actionability: findings are structured so Phase 3 can cite them
> directly by angle"); nothing told whoever drafted Phase 3 to actually do so. See
> `~SDP-Maintenance/~docs/phase-1-3-interactive-capture-design.md` for full rationale.

**Trigger:** COORDINATOR dispatches a WORKER-role task for Phase 3 immediately after Phase 2's
gate passes.

**Mechanics:**

1. Per "Phase 1 / Phase 3 — Interactive Capture Mechanics" above, COORDINATOR reads
   `sdp-solution-docs/01_concept.md`, `sdp-solution-docs/02_research_findings.md`, and — if this
   cycle has a tracked source document (this cycle's Concept phase state file's `source_document`
   field, absent for conversational intake) — the original source file(s) under
   `sdp-solution-docs/user-design-docs/processed/`. It then runs `/brainstorming` interactively
   with the user before dispatching WORKER, bringing all of that material into the session as the
   input being expanded and merged. Every decision surfaced is transcribed into
   `sdp-solution-docs/03_expanded_concept.md` before the COORDINATOR session closes.
2. WORKER reads `01_concept.md`, `02_research_findings.md`, the tracked source document if one
   exists for this cycle, and the COORDINATOR-captured material already present in
   `03_expanded_concept.md`, then finishes drafting the expanded concept — every research angle
   from Phase 2 is addressed somewhere in the expanded concept (cited by angle, not merely
   summarized), every constraint from the brainstorming capture is reflected, and no detail
   present in the original tracked source (when one exists) is silently dropped by Phase 1's
   compression going unnoticed here too.
3. WORKER appends the Completed blockquote and sets phase state to `WORK_COMPLETE` as normal —
   the existing WORKER session contract applies unchanged.

**Gate — Expanded concept review (REVIEWER session):**

- **Research incorporation:** every angle in `02_research_findings.md` is addressed in
  `03_expanded_concept.md`, cited by angle — not silently dropped.
- **Capture fidelity:** every decision transcribed from the COORDINATOR brainstorming session
  appears in the expanded concept, unmodified in substance.
- **Source coverage:** when a tracked source doc exists (Phase 1 — Source-Doc Intake Ownership),
  `sdp-source-coverage-check` has run against this document — mandatory, not optional (see that
  section above).
- **Actionability:** the expanded concept is structured so Phase 4 (Architecture) can build
  directly on it without re-deriving decisions already made here.

### Phase 4 — Architecture

> **Addition — 2026-07-23:** Phase 4 previously had no dedicated Mechanics/Gate entry — Phase 2
> and Phase 3 both do. Added alongside Material Decision Escalation (see Dispatch and Halt
> Contracts section) after a project's Architecture phase closed a hosting-provider gap via the
> Pros-Cons-Gaps Cycle's "declared out of scope with a written rationale" path with zero user
> contact, and a separate project stalled mid-build needing external API credentials no phase had
> surfaced early. See `~SDP-Maintenance/~docs/material-decision-escalation-design.md`.

**Trigger:** COORDINATOR dispatches a WORKER-role task for Phase 4 immediately after Phase 3's
gate passes.

**Mechanics:**

1. WORKER runs the Pros-Cons-Gaps cycle (see that section below) against `01_concept.md`,
   `02_research_findings.md`, and `03_expanded_concept.md`, drafting
   `sdp-solution-docs/04_architecture.md`.
2. Any gap whose resolution would introduce an external dependency (language, runtime, framework,
   library/package, IDE/tool/plugin, database/data-platform engine, cloud/hosting provider,
   third-party API/service, or anything similar) not already named in `.speq`, or an architectural
   pattern with no GPG precedent, is subject to Material Decision Escalation (Dispatch and Halt
   Contracts section) — it cannot be closed via Deferred or declared-out-of-scope alone.
3. WORKER appends the Completed blockquote and sets phase state to `WORK_COMPLETE` as normal.

**Gate — Architecture review (REVIEWER session):**

- **External Dependency Completeness:** every dependency or component surfaced during Architecture
  is either detailed and settled in `01_concept.md`/`03_expanded_concept.md`/a prior resolved
  Material Decision Escalation record (no `.speq` exists yet at this phase — see the Material
  Decision Escalation section), or explicitly deferred with recorded user approval and a named
  target phase/task. GATE_BLOCKED if any such item is unresolved — this is the direct backstop
  against a dependency (especially one requiring credentials or an account) silently crossing the
  Architecture gate un-flagged and surfacing only mid-implementation.
- **GPG alignment:** architectural choices reference applicable GPG chapters (Ch. 1, 3, 4, 13 —
  see GPG Reading Map) or, where none apply, carry an explicit "none" GPG Reference subject to the
  GPG-silence trigger above.
- **Actionability:** the architecture document is structured so Phase 5 (Implementation Overview)
  can build directly on it without re-deriving decisions already made here.

### Phase 6 — Refined Implementation Plan (Trimmed Scope)

Unchanged from the pre-2026-07-18 Phase 5 except build-phase decomposition moves to Phase 7.
Phase 6's job: write acceptance criteria for each work item within the plan document's own
explicit scope, gated by the existing plan review. This is a removal of responsibility, not an
addition — no new mechanics.

### Phase 7 — Phase Readiness

**Trigger:** dispatched after Phase 6's plan review passes.

**Two responsibilities:**

**A. Build-phase decomposition** (moved from the pre-2026-07-18 Phase 5): decompose remaining
scope into each assigned project's own `.sdp-workflow/registry.md` rows, applying the existing
rightsizing bias (many small cohesive phases over few large ones) — mechanically identical to
what Phase 5 did before this version,
just relocated. Each newly decomposed phase's state file gains a `gpg_chapters` array (see
Stuck-Loop Detection section below for the schema) populated during this step — empty array is
valid; the Phase 7 gate criterion below checks the field is *present*, not necessarily non-empty.

> **Addition — 2026-07-26:** For every project receiving decomposed tasks for the first time,
> Build-phase decomposition also populates that project's `.speq.md` and `[PROJECT]-Context.md`
> — created as empty stubs at Add-Project time (`sdp-workspace-setup`), never populated by any
> step until now — with the real, settled tech stack/naming/structure/product-shape decisions
> already recorded in `04_architecture.md`/`05_implementation_overview.md`. See
> `sdp-solution-phase-coordinator/SKILL.md` Step 2b item 0 for the procedure, and the `.speq`
> Contract / Project Context Document sections above for the matching trigger-point correction.
> Added after a real first-WORKER-dispatch halt found neither file existed for a project that had
> already passed Phase 7 — no step in the solution-scoped pipeline owned creating or populating
> them until this addition.

**B. Full-lifecycle coverage audit:** GATE_REVIEWER reads back across every prior deliverable
and traces every feature/rule/design element forward to confirm it landed somewhere in the final
plan and decomposed registry.

- **If a tracked source doc exists** (`user-design-docs/processed/[file]`): the audit traces
  from that **original source doc**, not from `sdp-solution-docs/01_concept.md`. Every element in
  the user's original material must be traceable all the way to the final plan/registry.
- **If no source doc exists** (pure conversational intake): the audit starting point is
  `sdp-solution-docs/01_concept.md`.

Additional gate criteria, alongside the traceability check:

- **Rightsizing:** each `registry.md` row is a unit of work one WORKER dispatch sequence can
  reasonably complete.
- **Dependency ordering:** the Depends On column is complete, acyclic, and walkable.
- **Acceptance criteria completeness:** every work item across every decomposed phase has
  acceptance criteria written.
- **GPG chapter assignment:** each decomposed phase's state file has a `gpg_chapters` field
  present (see Phase 7.A above).
- **`.speq`/Context population** *(2026-07-26 addition — see Phase 7.A's Addition above)*: every
  project receiving decomposed tasks for the first time this cycle has real, settled content in
  its `.speq.md` and `[PROJECT]-Context.md` — no template placeholders remaining.
- **Dependency edge validity** *(2026-07-27 addition — pre-existing gap, closing drift against
  `sdp-solution-phase-gate-review/SKILL.md`, which already assesses this)*: every edge declared
  in `.sdp-solution-workflow/dependencies.json` references a real project + task, or, for a
  decision-only edge, a `criterion_text` that appears verbatim in the named producer task's
  acceptance criteria. An edge referencing a nonexistent project, task, or criterion text is a
  finding, same severity class as the other criteria.

**When the audit finds a gap or misalignment (Phase Readiness Regression Procedure):**

1. GATE_REVIEWER appends a `GATE_BLOCKED` verdict to `sdp-solution-docs/07_phase_readiness.md`
   identifying the earliest phase where the gap originates, with justification, and up to 3 remediation
   proposals spanning full re-phase rework to a small targeted edit. Each proposal names an
   explicit **`Target Phase:`** field — the exact `.sdp-solution-workflow/registry.md` Phase
   column value execution should return to if this proposal is chosen (see the verdict format
   below).
2. `workflow_status` → `"halted"`. COORDINATOR does not pick a proposal itself — this always
   halts for human decision. The regression counter below is purely informational and never a
   cap; every regression gets a human decision regardless of count.
3. User selects a proposal. COORDINATOR sets `current_phase` to the chosen proposal's
   `Target Phase:` value and `phase_gate.status` → `"blocked"` for that phase.
4. That phase (and every intermediate phase between it and Phase 7, in the solution's own
   `.sdp-solution-workflow/registry.md` row order) gets a genuinely fresh WORKER → REVIEWER →
   gate cycle — real re-execution, not a spot-check — before Phase Readiness re-attempts its own
   gate. No intermediate phase is skipped.

> **Addition — 2026-07-24:** Items 3-4 above left an undocumented mechanical gap: nothing said how
> COORDINATOR (or `sdp-solution-phase-coordinator`) transitions a regressed phase from the
> administrative `phase_gate.status → "blocked"` marker set in item 3 back into an actual gate
> dispatch once that phase's fresh WORKER → REVIEWER cycle (item 4) reaches all-VERIFIED. The
> `"blocked"`-branch algorithm each coordinator already had (`sdp-project-coordinator/SKILL.md` Step
> 4 sub-step 5; mirrored by `sdp-solution-phase-coordinator/SKILL.md` Step 2e) only modeled a real
> GATE_REVIEWER verdict already sitting in the phase document as a GATE_BLOCKED blockquote — it had
> no branch for this administrative case, a case that occurs on every single regression. Without a
> matching branch, the coordinator instead either re-surfaced already-selected-and-executed
> Remediation Proposals, or halted pointing at a GATE_BLOCKED blockquote that did not exist yet. The
> solution-scoped mirror compounded this: Step 2e read the fixed `sdp-solution-docs/
> 07_phase_readiness.md` path unconditionally rather than the current phase's own document — a
> permanent misread of every later `"blocked"` occurrence, for any phase, once a single regression
> had ever happened for that solution, since Append-Only Discipline never lets that file's
> Remediation Proposals heading disappear. Confirmed in a consuming project: a fully-executed
> regression left `phase_gate.status == "blocked"` on the target phase after its fresh cycle
> reached VERIFIED, and the solution coordinator re-halted on the original, already-resolved
> proposals. Fixed by adding an explicit disambiguation to both coordinators' `"blocked"` branches,
> keyed on `phase_gate.gate_review_attempts` (`0` means no real gate review has fired since
> `"blocked"` was set — the administrative case, dispatch GATE_REVIEWER exactly as a first gate;
> `>= 1` means a real verdict exists, proceed as already documented) — this counter is a reliable
> signal because a real GATE_BLOCKED verdict always leaves it `>= 1`, while only the regression
> procedure itself ever resets it to `0` against a `"blocked"` status. The solution-level mirror
> additionally now resolves the current phase's own document (`sdp-solution-docs/[NN_phase_name].md`)
> instead of a hardcoded path. See `sdp-project-coordinator/SKILL.md` Step 4 sub-step 5 and
> `sdp-solution-phase-coordinator/SKILL.md` Step 2e item 0.

**Solution-scoped since 2026-07-20:** every step above operates on the solution's own
`.sdp-solution-workflow/state.json` / `.sdp-solution-workflow/registry.md` /
`sdp-solution-docs/07_phase_readiness.md` — never a project's. This mirrors the project-level
mechanism exactly, just relocated: ~~`sdp-gate-review` (dispatched with `-scope solution`) uses
the~~ [2026-07-21: superseded — see Correction below] `sdp-solution-phase-gate-review` (a dedicated
solution-scoped skill, not a `-scope` flag on the project-level ~~`sdp-gate-review`~~
`sdp-project-gate-review`) uses the
identical Remediation Proposals verdict format, and ~~`sdp-solution-coordinator`~~
[2026-07-22: superseded — `sdp-solution-phase-coordinator`'s own copy of this logic is the one
actually reachable; see the design doc above] gains the
equivalent of ~~`sdp-coordinator`~~ `sdp-project-coordinator`'s own `"blocked"`-branch regression handling, operating on the
solution's own state file. Because phases 1–7 only ever touch solution-level documents and the
solution's own registry — no project is even assigned work yet, in the strict sense, until Phase
7's decomposition runs — a solution-level regression never needs to "re-run" project-level work.
~~`sdp-coordinator/SKILL.md`~~ `sdp-project-coordinator/SKILL.md`'s own regression-dispatch logic (its Step 4 sub-step 5 `"blocked"`
branch, added by the prior phase-pipeline-expansion work) becomes unreachable once no project's
`current_phase` ever again contains "Phase Readiness" under normal operation — existing code
going unexercised, not a defect; it remains live only for the transient migration case (see the
design doc's Section 11). See
`~SDP-Maintenance/~docs/solution-coordinator-orchestration-design.md` §3 for full rationale.

> **Correction — 2026-07-21:** the original design put a `-scope project|solution` parameter on
> ~~`sdp-gate-review`~~ `sdp-project-gate-review`'s three backend scripts rather than authoring a companion skill — the
> project-level skill was modified to also serve a solution-level need. On review this was
> found to conflict with a broader principle applied everywhere else in this design (~~`sdp-coordinator`~~ `sdp-project-coordinator`,
> ~~`sdp-worker`~~ `sdp-project-worker`, ~~`sdp-reviewer`~~ `sdp-project-reviewer` all receive zero changes for solution-scope reasons): project-level
> skills are never modified to address a solution-level problem, full stop — both to keep each
> skill single-purpose (a dual-scope skill risks an agent applying the wrong mode mid-procedure)
> and to remove any chance an agent reads ~~`sdp-gate-review`~~ `sdp-project-gate-review` and concludes it can be pointed at
> solution-level work. ~~`sdp-gate-review`~~ `sdp-project-gate-review`'s `-scope` parameter was removed entirely — it is
> project-scoped only again, exactly as before this whole design — and `sdp-solution-phase-gate-review`
> was authored as a dedicated companion, even though its content is very close to
> ~~`sdp-gate-review`~~ `sdp-project-gate-review`'s own. See
> `~SDP-Maintenance/~docs/solution-phase-dispatch-gap-design.md` for the full rationale, including
> why the equivalent WORKER/REVIEWER gap (surfaced the same week) was closed the same way with
> `sdp-solution-phase-worker`/`sdp-solution-phase-reviewer`, rather than adding solution-scope
> awareness to ~~`sdp-worker`~~ `sdp-project-worker`/~~`sdp-reviewer`~~ `sdp-project-reviewer`.

> **Correction — 2026-07-24:** This 2026-07-21 correction's own text named `sdp-reviewer` twice
> (both instances struck through above) — renamed to `sdp-project-reviewer` as part of the
> `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).
>
> **Correction — 2026-07-24:** This 2026-07-21 correction's own text also named `sdp-worker`
> twice (both instances struck through above) — renamed to `sdp-project-worker` as part of the
> same `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).

> **Correction — 2026-07-24:** The paragraph immediately above this correction chain also still
> named `sdp-gate-review` — renamed to `sdp-project-gate-review` as part of the same
> `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).
>
> **Correction — 2026-07-24:** This section (the "Solution-scoped since 2026-07-20" paragraph
> and the 2026-07-21 correction above) named `sdp-coordinator` three times — twice as prose
> referencing its Phase-Readiness regression-dispatch logic, once inside the 2026-07-21
> correction's own list of project-level skills that receive zero solution-scope changes — all
> three struck through above and renamed to `sdp-project-coordinator` as the last skill in the
> `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).

> **Correction — 2026-07-24:** This 2026-07-21 correction's own text also named `sdp-gate-review`
> four times (all instances struck through above) — renamed to `sdp-project-gate-review` as part
> of the same `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).

This is a genuine backward state transition — the first one in SDP's phase lifecycle, which
otherwise only ever advances or repeats a gate cycle in place. It reuses the existing gate
machinery (`phase_gate.status`, `GATE_BLOCKED`/`GATE_PASSED`) — the new part is that
`current_phase` itself can legitimately move backward.

**Phase Readiness Remediation Proposal verdict format** (used in place of the standard
numbered-issue-list `GATE_BLOCKED` body — see the Phase Gate Procedure section for the standard
format this extends):

```markdown
> **Gate Verdict — GATE_BLOCKED — [YYYY-MM-DD HH:MM]**
> Reviewer: session-NNN
> **Traceability gap identified — originates at [Phase Name].**
> [Description of the gap/misalignment and why it originates there.]
>
> **Remediation Proposals:**
> 1. **Target Phase:** [exact .sdp-solution-workflow/registry.md Phase column value] — [one-line
>    description of this remediation's scope, from full re-phase rework to a small targeted edit]
> 2. **Target Phase:** [exact .sdp-solution-workflow/registry.md Phase column value] — [description]
> 3. **Target Phase:** [exact .sdp-solution-workflow/registry.md Phase column value] — [description]
```

See `~SDP-Maintenance/~docs/phase-pipeline-expansion-design.md` §4, §5 for full rationale.

Pros-cons-gaps cycles happen within the architecture and overview phases. Each cycle:
1. Agent identifies pros, cons, and gaps in the current document
2. Gaps are resolved by amending the document (append new content; strikethrough superseded content)
3. Cycle repeats until no material gaps remain or cycle limit is reached
4. Gate review is a separate REVIEWER session

---

## Workspace Setup

> **Agent:** Full workspace setup procedure, folder structure diagrams, and all file templates
> are in `SDP-Workspace-Setup.md`. Load that file explicitly when setting up
> a new workspace — it is not loaded automatically by ~~`sdp-read-docs`~~ `sdp-project-read-docs`.
> `SDP-Workspace-Setup.md` covers both the solution root setup (creating `.sdp-solution-workflow/`,
> `sdp-solution-docs/`, `sol-shared/`, and `SDP-Solution.json`) and the per-project setup
> (creating `sdp-project_[name]/` and registering it in `SDP-Solution.json`).
> See the [Setup Checklist](#setup-checklist) below for gate items before first dispatch.
>
> **Correction — 2026-07-23:** This note's skill reference still named `sdp-read-docs` —
> renamed to `sdp-project-read-docs` as part of the `sdp-project-*` scope-prefix rename (see
> `project-scope-skill-naming-design.md`).

> **Solution root invariant:** Claude Code must always be opened at the **solution root** — the
> folder containing `SDP-Solution.json`, `.claude/skills/`, and `sdp-shared/`. All skills live in
> `.claude/skills/` at the solution root. Opening Claude Code at a project subfolder
> (`sdp-project_*/`) means no skills are visible and every `/sdp-*` invocation silently fails.
> If skills appear unavailable, verify the working directory contains `SDP-Solution.json`.

---

> **Standards document replacement:** To replace the built-in GPG standards reference with a
> custom standards document, use the `sdp-standards-setup` skill after workspace setup is
> complete. Full procedure, amendment rules, and migration guide are in `SDP-Standards-Setup.md`.

> **Reference documents:** Most SDP reference docs live in `sdp-shared/docs/` and are not loaded
> automatically by ~~`sdp-read-docs`~~ `sdp-project-read-docs`. Load them explicitly when needed. All are registered in
> `SDP-Document-List.json`: `SDP-Workspace-Setup.md`, `SDP-Skill-Authoring.md`,
> `SDP-Script-Authoring.md`, `SDP-Standards-Setup.md`, `SDP-Tone-Notifications.md`,
> `SDP-Changelog.md`, `SDP-Project-Evolution.md`.
>
> **Correction — 2026-07-23:** This note's skill reference still named `sdp-read-docs` —
> renamed to `sdp-project-read-docs` as part of the `sdp-project-*` scope-prefix rename (see
> `project-scope-skill-naming-design.md`).

---

#### `sdp-docs/00_prompt.txt`

Written by COORDINATOR after every dispatch, or regenerated on demand via ~~`/sdp-create-prompt`~~
`/sdp-project-create-prompt`.
Always contains the complete prompt for the next subagent (WORKER or REVIEWER).

> **Regenerating on demand:** When invoked directly by the user at the solution root,
> ~~`/sdp-create-prompt`~~ `/sdp-project-create-prompt` uses Level 3 project resolution — reading
> `last_active_projects[0]` from
> `SDP-Solution.json` — to target the active project automatically. No project argument needed.
> Do not use `/sdp-solution-create-prompt` for this — it writes
> `sdp-solution-docs/00_solution_prompt.txt`, a solution-level orchestration prompt that serves
> a different purpose and produces a different file.
In the new subagent session, invoke ~~`/sdp-run-prompt`~~ `/sdp-project-run-prompt` — it reads
this file, identifies the next skill, and invokes it automatically. No manual skill
identification required.

> **Correction — 2026-07-23:** This step's skill reference still named `sdp-run-prompt` —
> renamed to `sdp-project-run-prompt` as part of the `sdp-project-*` scope-prefix rename (see
> `project-scope-skill-naming-design.md`).

> **Correction — 2026-07-24:** This heading's prose and the "Regenerating on demand" note above
> both still named `sdp-create-prompt` — renamed to `sdp-project-create-prompt` as part of the
> `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).

COORDINATOR writes this file using a sentinel line followed by a five-section structure.

**Sentinel line (first line of the file):**

```
[sdp-prompt work_item="[active_work_item]" expected_status="[task_status]" role="[dispatch_role]"]
```

The sentinel records the `active_work_item` ID, the task's current status, and the `role` the
prompt dispatches (`WORKER`, `REVIEWER`, or `COORDINATOR`) at the time the prompt was written.
~~`sdp-state-loop`~~ `sdp-project-state-loop` reads `work_item` and `expected_status` to determine whether the prompt is
current (EXECUTE) or stale and needs regeneration (GENERATE), and reads `role` to count
`eval_cycle_attempts` against REVIEWER dispatches only — the COORDINATOR dispatch-of-REVIEWER
fire also reads `WORK_COMPLETE` status but must not consume a REVIEWER attempt (see Stuck-Loop
Detection). See ~~`sdp-create-prompt`~~ `sdp-project-create-prompt` for the exact values written.
Follow the sentinel with one
blank line before Section 1.

> **Correction — 2026-07-24:** This paragraph's skill reference still named `sdp-create-prompt`
> — renamed to `sdp-project-create-prompt` as part of the `sdp-project-*` scope-prefix rename
> (see `project-scope-skill-naming-design.md`).

> **Correction — 2026-07-24:** This paragraph's skill reference also still named `sdp-state-loop`
> — renamed to `sdp-project-state-loop` as part of the same `sdp-project-*` scope-prefix rename
> (see `project-scope-skill-naming-design.md`).

**Five sections:**

- **Section 1 — Role Declaration:** "You are acting as [ROLE] for the **[PROJECT]** project
  using the SDP workflow."
- **Section 2 — Read First:** Standard reminder that ~~sdp-read-docs~~ sdp-project-read-docs loads context automatically;
  no pre-reads needed before invoking the skill.

  > **Correction — 2026-07-23:** This bullet still named `sdp-read-docs` — renamed to
  > `sdp-project-read-docs` as part of the `sdp-project-*` scope-prefix rename (see
  > `project-scope-skill-naming-design.md`).
- **Section 3 — Current State Summary:** A table with Project, Current phase, Workflow status,
  Active work item, Last session, and Next action — values drawn from state.json at dispatch time.
- **Section 4 — Task Instruction:** One or two sentences on what this session must do, followed
  by "Invoke `/sdp-[role]` to begin."
- **Section 5 — Key Files:** Paths to `.sdp-workflow/state.json`, the new session dispatch file, and
  the phase file containing the assigned task.

During workspace setup, create this stub:

```
(empty — COORDINATOR writes this after each dispatch)
```

**Ordering rule — `SDP-Document-List.json`:** The `sdp-docs/00_prompt.txt` entry must
always be the **last** entry with `"includeInReadDocs": true` in `SDP-Document-List.json`.
This guarantees every other context file (bootstrap, project context, standards) is loaded into
the agent's context window before the task prompt is read. Re-verify this ordering any time a
new entry is added to the document list.

---

#### Session file template (`.sdp-workflow/sessions/session-NNN.md`):
```markdown
# Session NNN

Date: [DATE]
Role: [COORDINATOR | WORKER | REVIEWER]
Work Item: [WI-ID or "n/a" for COORDINATOR-only sessions]
Dispatched By: [human | coordinator-session-NNN]

## Dispatch Instructions

[Written by COORDINATOR before session begins]

## Session Outcome

[Appended by dispatched agent when session concludes]
Status transition: [FROM] → [TO]
Notes: [any notes relevant to next session]
```

---

#### Scope Tag mechanism (optional — multi-team or multi-deliverable plans)

When an implementation plan covers work owned by more than one team, or where some tasks
are explicitly out of scope for the current implementer, use scope tags inline on task items
and add an Agent Scope Instruction box at the top of the Implementation Task List.

**Inline scope tags** (append after the task ID, before the task description):

| Tag | Meaning |
|-----|---------|
| `[EXTERNAL SCOPE]` | Task is owned by another team — skip entirely |
| `[EXTERNAL SCOPE — SUPERSEDED]` | Task was owned externally and has since been superseded — skip |
| `[PARTIAL — SPLIT RESPONSIBILITY]` | Implement the in-scope portion only; the external portion is noted in the task body |
| *(no tag)* | Implement in full |

**Agent Scope Instruction box** — embed at the top of the Implementation Task List section
in the parent document. Agents must read this before executing any task:

```markdown
> **⛔ Agent Scope Instruction — Read Before Executing Any Task**
>
> This plan contains tasks tagged for external scope. Apply the following rules before
> touching any task:
>
> | Tag | Action |
> |-----|--------|
> | `[EXTERNAL SCOPE]` | **Skip entirely.** Do not implement. |
> | `[EXTERNAL SCOPE — SUPERSEDED]` | **Skip entirely.** Task no longer applies. |
> | `[PARTIAL — SPLIT RESPONSIBILITY]` | **Implement the in-scope portion only.** The external portion is noted in the task body — leave it unimplemented. |
> | *(no tag)* | **Implement in full.** |
>
> When in doubt: if the task description says "[Team] responsibility" for a step, skip that step.
```

Mirror the scope instruction box into the relevant phase section file header so an agent
reading only the phase file sees the instruction without needing to open the parent.

---

#### Task item format (within every phase section file)

Work is tracked inline in phase section files. There are no separate work item files.
Each task item in a phase section file follows this format:

```markdown
- [ ] **[TASK-ID]** `[VERIFY DURING IMPLEMENTATION]` Task description — what must be done,
  including all sub-steps, constraints, and references to source documents.
  - Sub-step 1
  - Sub-step 2

  > **Scope note ([DATE] — [TASK-ID]):** [Any scope decision or constraint clarification
  > appended after the task was written. Append-only — never edit the task description above.]

  > **Completed: [YYYY-MM-DD HH:MM]** — [What was done. Decisions made. Any deviations from
  > spec and why. Build/compile status — e.g. "dotnet build passes 0 errors, 0 warnings".]

  > **Eval 1 — [YYYY-MM-DD HH:MM]:** [Compliance assessment against task spec, criterion by
  > criterion. Each sub-step addressed explicitly. Build status confirmed.
  > Outcome: compliant / partially compliant / non-compliant.
  > If non-compliant: specific, actionable notes for the next WORKER session.]
  > **Verified 1 — [YYYY-MM-DD HH:MM]:** [Written only after a passing (compliant or partially
  > compliant) eval. Independent confirmation. What was read/run to verify. Outcome: Verified.]

  *(If Eval 1 is non-compliant: no Verified 1 is written. COORDINATOR sets state → REJECTED.
  WORKER reads the eval findings, does corrective work, appends a new Completed blockquote.
  Eval 2 + Verified 2 follow once corrected.)*

  > **Eval 2 — [YYYY-MM-DD HH:MM]:** [Re-evaluation — state trigger: describe the spec change,
  > related-task resolution, or audit finding that required this cycle. Criterion-by-criterion
  > assessment. Outcome: compliant / partially compliant / non-compliant.]
  > **Verified 2 — [YYYY-MM-DD HH:MM]:** [Same structure as Verified 1.]
```

**Flags:**
- `[VERIFY DURING IMPLEMENTATION]` — task requires runtime verification, not just code review;
  REVIEWER must execute or observe the behaviour, not just read the code
- `[x]` checkbox — set by WORKER when Completed blockquote is appended
- `[ ]` checkbox — task not yet started or returned to WORKER after a non-compliant eval

**Non-compliant eval:** REVIEWER appends a non-compliant `Eval N` blockquote with specific
findings — no `Verified N` blockquote is written until the task passes. COORDINATOR sets state
to REJECTED. WORKER reads the eval findings and appends a new `Completed` blockquote in the
next session. A new Eval + Verified cycle follows. All prior entries are preserved unchanged.

**Optional: ⚡ Deploy annotation** — For tasks where a run/deploy step is required after
implementation, append a deploy blockquote immediately after the Completed blockquote:

```markdown
  > **⚡ Deploy:** [Command or procedure to execute. Include connection strings or secret
  > references by key name — never literal values. Note what the command skips vs. executes
  > if the migration runner is context-aware (e.g., already-tracked scripts are skipped).]
```

This keeps the operational instruction co-located with the task rather than in a separate
runbook. Use only when the deploy step is non-obvious or requires a specific sequence.

### Re-evaluation Triggers

A new Eval + Verified cycle (Eval 2, Eval 3, …) is required whenever any of these occur
after the previous cycle was completed:

1. **A source document changes** in a way that could affect this task's implementation.
   The REVIEWER reads the changed spec and assesses whether the existing implementation
   still complies.

2. **A related task's resolution changes an assumption** this task depended on.
   Example: a shared schema decision was revisited, or a dependency task was re-implemented.

3. **An audit, code review, or security review raises a compliance concern** against this
   task's output — even if the previous Verified entry passed.

4. **Implementation drift is discovered** — any session (including one doing
   unrelated work) finds the as-built code diverges from an approved design,
   architecture, or plan document. Before any fix, classify the fix-direction:

   | Case | Authoritative artifact | Action |
   |------|------------------------|--------|
   | Design is the binding contract; code diverged | Design doc | Queue a **code-fix work item** — design doc unchanged |
   | Design was aspirational / never built and is genuinely superseded | As-built code | **Strikethrough-amend** the design doc (append-only) via a workflow session |
   | An active, non-append-only doc (README, `.env.example`) merely describes correct behavior stalely | Code | **Direct-edit** the doc — no work item, no append-only ceremony |

   The discovering session records the drift and its proposed classification but
   does not act on append-only design docs directly — it surfaces the
   classification to COORDINATOR, which routes case 1 as a work item and case 2
   as a strikethrough-amendment session. Case 3 needs no SDP ceremony.

**Re-evaluation format:** Add the new Eval N + Verified N pair below all prior entries.
Begin the Eval blockquote with the trigger: `Re-evaluation trigger: [describe what changed].`
No prior entry is edited or removed.

**COORDINATOR responsibility:** When dispatching a REVIEWER for a re-evaluation cycle,
include the trigger reason in the session dispatch file so the REVIEWER knows what changed
without having to infer it from the phase file history.

---

## Project Resolution Order

Every skill that reads or writes project files resolves `[resolved_project]` using this
three-level priority order. Use the first level that yields a result.

**Level 1 — Dispatch context** (authoritative for dispatched subagents).
If the opening prompt sentinel has a `projects=` attribute, or the session file has a
`Project:` field, use that value. For a `projects=` list, take the first comma-separated entry.

**Level 2 — Physical path extraction** (deterministic, no I/O required).
If no `projects=` or `Project:` is present, examine the path of the file being processed
(e.g., session file or state file path). If the path contains an `sdp-project_*` segment,
that segment is `[resolved_project]`. If no such segment is found, proceed to Level 3.

**Level 3 — `SDP-Solution.json`** (user-direct invocations only).
Read `last_active_projects` from `SDP-Solution.json` at the solution root; use the first entry
as `[resolved_project]`. This is the path taken when a user invokes a skill directly with no
session file or sentinel context (e.g., ~~`/sdp-create-prompt`~~ `/sdp-project-create-prompt` at
the solution root). If
`SDP-Solution.json` is absent at this level: halt with
`"⛔ SDP-Solution.json not found at solution root."`

For single-project workspaces where `last_active_projects` is `["."]`, paths collapse to the
workspace root — identical to legacy single-project behavior.

> **Correction — 2026-07-24:** This example still named `sdp-create-prompt` — renamed to
> `sdp-project-create-prompt` as part of the `sdp-project-*` scope-prefix rename (see
> `project-scope-skill-naming-design.md`).

---

## Implementation Loop (Per Task)

Work is tracked inline in phase section files. The `work_items/` folder model is not used —
task spec, completion notes, evaluations, and verifications all live in the phase section file
alongside the task description. This is the model validated in practice.

```
COORDINATOR session:
  0. PREFLIGHT CHECK — Resolve `[resolved_project]` using the three-level order defined in the
     Project Resolution Order section of this doc: (1) sentinel `projects=` or session file
     `Project:` field; (2) `sdp-project_*` path extraction; (3) `SDP-Solution.json` `last_active_projects[0]`.
     Then run (PowerShell tool):
     ```
     .\sdp-shared\scripts\sdp-preflight.ps1 -workspaceRoot .\[resolved_project]
     ```
     One call validates every deterministic precondition — GPG presence/version, all sdp- skill pairs
     (Level 1 + Level 2), the sdp-tone Level 1-present / Level 2-absent invariant, the
     sdp-tone.ps1 / sdp-create-prompt.ps1 / sdp-github.ps1 scripts, SDP-Tones.json, and the
     scaffold/config/document-list checks — against the SDP-Workspace-Setup.json manifest, and
     emits a JSON envelope. On `ok:false`: halt per the Halt Behavior Contract citing the
     envelope's `failures` (or `error` for a manifest-missing/unparseable operational error).
     The canonical inventory is data in the manifest, not enumerated here. Pass `-Force` to
     bypass the per-tier staleness timers for a full re-check.
     ~~GPG CHECK — Verify standards/GenericProjectGuidlines_V[version].md exists and version
     matches gpg_version in state.json. If missing or mismatched: halt, notify user, do not
     proceed until resolved.~~ (superseded — covered by the PREFLIGHT CHECK manifest)
  0a. SUPERPOWERS CHECK — Verify Superpowers plugin is installed (`/plugin list`). If missing:
      note in the session file and include in dispatch instructions: "Superpowers not installed
      — WORKER must apply TDD and four-phase debugging discipline manually." Does not block
      dispatch. (Not script-able — `/plugin list` is a harness command, not a filesystem fact;
      it stays an agent step and is non-blocking.)
  0b. ~~SKILLS CHECK — Verify that both Level 1 (`.claude/skills/[name]/SKILL.md`) and Level 2
      (`sdp-shared/ai-skills/[name]/SKILL.md`) files exist for all sdp- skills: sdp-auto,
      sdp-cancel-auto, ~~sdp-coordinator~~ sdp-project-coordinator, ~~sdp-create-prompt~~ sdp-project-create-prompt, ~~sdp-pre-work-verify~~
      sdp-project-pre-work-verify, ~~sdp-read-docs~~ sdp-project-read-docs, ~~sdp-reviewer~~ sdp-project-reviewer,
      ~~sdp-run-prompt~~ sdp-project-run-prompt, ~~sdp-state-loop~~ sdp-project-state-loop, sdp-state-loop-start, ~~sdp-worker~~ sdp-project-worker. Also verify
      `.claude/skills/sdp-tone/SKILL.md` and `sdp-shared/scripts/sdp-tone.ps1` exist, and
      that `SDP-Tones.json` exists at the workspace root (tone config read by sdp-tone.ps1).
      Also verify `sdp-shared/scripts/sdp-github.ps1` exists (the unified git/gh script;
      its `ci-status` subcommand is the CI-green gate when `SDP-Config.json` `ci.enabled` is true).
      (`sdp-shared/ai-skills/sdp-tone/SKILL.md` must **not** exist — sdp-tone was converted
      to a script; do not create a Level 2 SKILL.md for it.) If any
      file is missing: halt per the Halt Behavior Contract — set `workflow_status` to
      `"halted"`, add `halt_reason: "Skills check failed — missing: [list]"`, notify user
      with "⛔ Halted — Skills check failed: [list]. Restore missing files and run COORDINATOR
      to resume.", and terminate.~~
      Superseded — the skill/script/config inventory is now declarative data in
      `SDP-Workspace-Setup.json`, validated by the PREFLIGHT CHECK (step 0) above.

      > **Correction — 2026-07-23:** This superseded step's skill list still named
      > `sdp-pre-work-verify` — renamed to `sdp-project-pre-work-verify` as part of the
      > `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).

      > **Correction — 2026-07-23:** This superseded step's skill list also still named
      > `sdp-run-prompt` — renamed to `sdp-project-run-prompt` as part of the same
      > `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).

      > **Correction — 2026-07-23:** This superseded step's skill list also still named
      > `sdp-read-docs` — renamed to `sdp-project-read-docs` as part of the same
      > `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).

      > **Correction — 2026-07-24:** This superseded step's skill list also still named
      > `sdp-reviewer` — renamed to `sdp-project-reviewer` as part of the same
      > `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).

      > **Correction — 2026-07-24:** This superseded step's skill list also still named
      > `sdp-worker` — renamed to `sdp-project-worker` as part of the same
      > `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).

      > **Correction — 2026-07-24:** This superseded step's skill list also still named
      > `sdp-create-prompt` — renamed to `sdp-project-create-prompt` as part of the same
      > `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).

      > **Correction — 2026-07-24:** This superseded step's skill list also still named
      > `sdp-state-loop` — renamed to `sdp-project-state-loop` as part of the same
      > `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).

      > **Correction — 2026-07-24:** This superseded step's skill list also still named
      > `sdp-coordinator` — renamed to `sdp-project-coordinator` as the last skill in the same
      > `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).
  1. Read state.json and all phase state files ([phase]_state.json) — no phase file reading
     required; task status is fully visible from state files alone
  1a. Check workflow_status in state.json — if "halted": notify user of halt_reason, do not
      proceed to step 2, terminate. Do not attempt to resolve the blocking condition — that
      is a human action. Resume only after the user resolves the condition and triggers a new
      COORDINATOR session.
  1b. DOC REVIEW CHECK — For each active or in-progress phase state file, check whether the
      `sdp_doc_review` key is present and `sdp_doc_review.completed` is `true`. If any staged
      state file entry is missing the key or has `completed: false`: run ~~`sdp-doc-review`~~
      `sdp-project-doc-review` for each unreviewed doc (in document-list order) before
      dispatching any task. All pending
      doc reviews must complete before any staged doc's work is dispatched. This ensures open
      decisions and implementation blockers are locked in before WORKERs are dispatched.

      > **Correction — 2026-07-23:** This step's skill reference still named `sdp-doc-review` —
      > renamed to `sdp-project-doc-review` as part of the `sdp-project-*` scope-prefix rename
      > (see `project-scope-skill-naming-design.md`).
  2. Cross-check: for any task with checkbox [x] in a phase file but status PENDING in its
     state file — flag the discrepancy to the user before dispatching
  3. Find next actionable task: REJECTED tasks take priority; then first PENDING task in
     current phase. Before dispatching any phase, check its Depends On column in registry.md —
     do not dispatch if any listed dependency phase is not [x] complete.
     When all tasks in the current phase are VERIFIED: read `phase_gate.status` from state.json.
     If `"pending"` or `"blocked"`: dispatch GATE_REVIEWER via ~~`sdp-gate-review`~~
     `sdp-project-gate-review` (see Phase Gate
     Procedure). ~~If `"passed"`: advance `current_phase` and reset the `phase_gate` block.~~
     [2026-07-10: clarified — see Correction below] If `"passed"`: advance `current_phase` to the
     first not-yet-verified phase in `registry.md` (row order) whose Depends On phases are all
     `[x]` complete — skipping any earlier row that is dependency-blocked — and reset the
     `phase_gate` block.

     > **Correction — 2026-07-10:** "Advance `current_phase` to the next phase in `registry.md`"
     > was ambiguous and, as implemented in ~~`sdp-coordinator/SKILL.md`~~ `sdp-project-coordinator/SKILL.md`, meant the literal next
     > row — a pure sequential walk with no dependency awareness. The Depends On column was only
     > ever consulted reactively (Step 4's dependency gate) to halt dispatch of an already-current
     > phase; it was never used to select which phase becomes current next. This forced project
     > registries to be hand-ordered to match dependency order — observed directly when a user
     > had to manually reorder `registry.md` rows so a dependency phase would be reached before
     > its dependent. Phase advancement now performs dependency-eligible selection instead of a
     > blind row walk. See ~~`sdp-coordinator/SKILL.md`~~ `sdp-project-coordinator/SKILL.md` Step 4 sub-step 5 for the full procedure.

     > **Correction — 2026-07-24:** This step's skill reference still named `sdp-gate-review` —
     > renamed to `sdp-project-gate-review` as part of the `sdp-project-*` scope-prefix rename
     > (see `project-scope-skill-naming-design.md`).

     > **Correction — 2026-07-24:** The 2026-07-10 correction above named `sdp-coordinator/SKILL.md`
     > twice — both struck through above and renamed to `sdp-project-coordinator/SKILL.md` as the
     > last skill in the same `sdp-project-*` scope-prefix rename (see
     > `project-scope-skill-naming-design.md`).
  4. If the next actionable task has flag `"DIAGNOSIS_BLOCKED"` in its state file: do not
     dispatch WORKER. Read the Completed blockquote from the phase file and surface the
     blocked diagnosis to the user:
     "⛔ [TASK-ID] has a blocked diagnosis — [paste the User decision needed line from the
     Completed blockquote]. Provide direction before WORKER continues."
     Remove the `"DIAGNOSIS_BLOCKED"` flag from the task's state file only after the user
     provides direction. Then dispatch WORKER with the user's decision included in the
     session dispatch file.
  5. Write session-NNN.md with dispatch instructions: phase file path, task ID, task flags
  6. Update state.json: ~~active_task~~ [2026-07-10: field name corrected — see below]
     `active_work_item`, `active_phase_file`, `last_session`

     > **Correction — 2026-07-10:** `active_task` was stale terminology never matched by any
     > implementation — the actual field is `active_work_item` (see ~~`sdp-coordinator/SKILL.md`~~
     > `sdp-project-coordinator/SKILL.md` Step 6). Separately, `active_phase_file` — mandated by this line since the doc's
     > earliest version — was never actually written by any implementation of COORDINATOR
     > Step 6 until this correction. ~~`sdp-state-loop`~~ `sdp-project-state-loop`, `sdp-auto`, `sdp-create-prompt.ps1`, and
     > `sdp-solution-coordinator.ps1` all read this field as their primary phase-state-file
     > lookup mechanism; its absence left the automated loop unable to self-navigate a
     > project's real phase-state-file location once a project's phase file naming diverged
     > from any single hardcoded convention. ~~`sdp-coordinator/SKILL.md`~~ `sdp-project-coordinator/SKILL.md` Step 6 now writes it,
     > sourced from `registry.md`'s Phase File column — see that skill for the full procedure.

     > **Correction — 2026-07-24:** This 2026-07-10 correction's own text also named
     > `sdp-state-loop` — renamed to `sdp-project-state-loop` as part of the `sdp-project-*`
     > scope-prefix rename (see `project-scope-skill-naming-design.md`).

     > **Correction — 2026-07-24:** This 2026-07-10 correction's own text also named
     > `sdp-coordinator/SKILL.md` twice (both struck through above) — renamed to
     > `sdp-project-coordinator/SKILL.md` as the last skill in the same `sdp-project-*`
     > scope-prefix rename (see `project-scope-skill-naming-design.md`).
  6a. Write sdp-docs/00_prompt.txt — overwrite with the WORKER prompt using the five-section format
      defined in the Workspace Setup sdp-docs/00_prompt.txt template. Role = WORKER; state summary
      from state.json; Task Instruction = brief task description + "Invoke ~~/sdp-worker~~ /sdp-project-worker to begin.";
      Key Files = state.json, session-NNN.md, phase file path. The active project used here is
      `[resolved_project]` as determined by the three-level resolution order defined in the
      Project Resolution Order section of this doc (sentinel `projects=` → path extraction →
      `SDP-Solution.json` `last_active_projects[0]`). ~~`sdp-create-prompt`~~ `sdp-project-create-prompt`
      (the skill) applies the
      same resolution order when invoked directly.
  7. Notify user: "Ready to dispatch WORKER for [TASK-ID]. Open a new subagent and invoke
     ~~`/sdp-run-prompt`~~ `/sdp-project-run-prompt` — it will read `sdp-docs/00_prompt.txt` and invoke ~~`sdp-worker`~~ `sdp-project-worker` automatically."

     > **Correction — 2026-07-23:** This notify-user message still named `sdp-run-prompt` —
     > renamed to `sdp-project-run-prompt` as part of the `sdp-project-*` scope-prefix rename
     > (see `project-scope-skill-naming-design.md`).

     > **Correction — 2026-07-24:** The Task Instruction template above and this notify-user
     > message both also still named `sdp-worker` — renamed to `sdp-project-worker` as part of
     > the `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).

     > **Correction — 2026-07-24:** The Project Resolution Order paragraph above still named
     > `sdp-create-prompt` — renamed to `sdp-project-create-prompt` as part of the
     > `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).

WORKER session (new subagent invocation):
  0. GPG CHECK — Verify standards/GenericProjectGuidlines_V[version].md exists. If missing:
     halt, notify user, do not proceed.
  0a. SUPERPOWERS CHECK — Verify Superpowers plugin is installed (`/plugin list`). If installed:
      apply TDD for all implementation (tests must fail before implementation begins); apply
      four-phase root cause methodology before any fix attempt; invoke skills explicitly only —
      auto-triggering is prohibited; do NOT use /execute-plan review checkpoints under any
      circumstances. If missing: apply equivalent TDD and debugging discipline manually as
      described in the session dispatch file.
  0b. NO PLACEHOLDERS — All code produced in this session must be complete. Do not write
      TODO, TBD, "implement later", stub bodies, or incomplete implementations. If a
      required piece cannot be completed due to missing information or an unresolved
      dependency, stop before writing placeholder code — surface the blocker to the user
      and halt rather than delivering incomplete output.
  1. Read this bootstrap doc (roles, state machine)
  2. Read the session dispatch file (`sessions/session-NNN.md` — session number from state.json
     `last_session` field). Confirm role assignment. Note any flags or Superpowers instructions
     included by COORDINATOR.
  2a. Read `[PROJECT].speq.md` — confirm tech stack, naming conventions, and file structure
      for this task before forming an approach. If the task requires a decision not declared
      in the contract, stop and surface it to the user before proceeding.
  3. Read state.json — confirm assigned task ID, phase file path, and any flags
  4. If task is in architecture or design phase: read the relevant GPG section(s) before
     reading the task — note applicable GPG patterns before forming an approach
  5. Read the full phase file — task description in context of the full phase
  6. Restate what the assigned task requires before starting. Proceed without waiting for user
     confirmation unless the restatement reveals an interpretation conflict — in that case,
     pause and state the conflict explicitly.
  7. If task has a prior non-compliant Eval blockquote: read it carefully before beginning
  8. Execute Pre-Work Verification (see Pre-Work Verification Protocol below the loop)
  9. Perform work
  10. Debugging escalation rule — applies when a fix attempt was made during step 9.
      After completing one full four-phase cycle (reproduce → isolate → diagnose → fix):
      if the implemented fix does not resolve the problem, do not re-attempt. Instead,
      include a Diagnosis Blocked section at the end of the Completed blockquote:
        - Root cause diagnosed as: [finding from the diagnose phase]
        - Fix attempted: [what was implemented]
        - Outcome: [what still fails and how — specific, not "it didn't work"]
        - User decision needed: [the specific question or choice required to proceed]
      Add flag `"DIAGNOSIS_BLOCKED"` to this task's entry in [phase]_state.json.
      Set status → WORK_COMPLETE as normal. Session ends — COORDINATOR handles escalation.
  11. Mark task checkbox [x] in the phase file
  12. Append Completed blockquote (include build/compile status explicitly)
  13. Update [phase]_state.json: set task status → WORK_COMPLETE, last_session, last_updated
  14. Mirror phase file changes to parent doc per sync rule
  15. Session ends — do not proceed to evaluate own work

COORDINATOR session (new subagent invocation — or user-triggered in human-gated mode):
  0. PREFLIGHT CHECK — Resolve `[resolved_project]` using the three-level order defined in the
     Project Resolution Order section of this doc: (1) sentinel `projects=` or session file
     `Project:` field; (2) `sdp-project_*` path extraction; (3) `SDP-Solution.json` `last_active_projects[0]`.
     Then run (PowerShell tool):
     ```
     .\sdp-shared\scripts\sdp-preflight.ps1 -workspaceRoot .\[resolved_project]
     ```
     It validates every deterministic precondition (GPG presence/version, all sdp- skill pairs L1+L2, the
     sdp-tone L1-present/L2-absent invariant, the scripts, SDP-Tones.json, and the
     scaffold/config/document-list checks) against the SDP-Workspace-Setup.json manifest and emits
     a JSON envelope. On `ok:false`: halt per the Halt Behavior Contract citing the envelope's
     `failures` (or `error`). Pass `-Force` to bypass the staleness timers.
     ~~GPG CHECK — Verify standards/GenericProjectGuidlines_V[version].md exists and version
     matches gpg_version in state.json. If missing or mismatched: halt, notify user.~~
     (superseded — covered by the PREFLIGHT CHECK manifest)
  0a. SUPERPOWERS CHECK — Verify Superpowers plugin is installed (`/plugin list`). If missing:
      note in session file and include in REVIEWER dispatch instructions. Does not block dispatch.
      (Not script-able — `/plugin list` is a harness command; it stays an agent step.)
  0b. ~~SKILLS CHECK — Verify that both Level 1 (`.claude/skills/[name]/SKILL.md`) and Level 2
      (`sdp-shared/ai-skills/[name]/SKILL.md`) files exist for all sdp- skills: sdp-auto,
      sdp-cancel-auto, ~~sdp-coordinator~~ sdp-project-coordinator, ~~sdp-create-prompt~~ sdp-project-create-prompt, ~~sdp-pre-work-verify~~
      sdp-project-pre-work-verify, ~~sdp-read-docs~~ sdp-project-read-docs, ~~sdp-reviewer~~ sdp-project-reviewer,
      ~~sdp-run-prompt~~ sdp-project-run-prompt, ~~sdp-state-loop~~ sdp-project-state-loop, sdp-state-loop-start, ~~sdp-worker~~ sdp-project-worker. Also verify
      `.claude/skills/sdp-tone/SKILL.md` and `sdp-shared/scripts/sdp-tone.ps1` exist, and
      that `SDP-Tones.json` exists at the workspace root (tone config read by sdp-tone.ps1).
      Also verify `sdp-shared/scripts/sdp-github.ps1` exists (the unified git/gh script;
      its `ci-status` subcommand is the CI-green gate when `SDP-Config.json` `ci.enabled` is true).
      (`sdp-shared/ai-skills/sdp-tone/SKILL.md` must **not** exist — sdp-tone was converted
      to a script; do not create a Level 2 SKILL.md for it.) If any
      file is missing: halt per the Halt Behavior Contract — set `workflow_status` to
      `"halted"`, add `halt_reason: "Skills check failed — missing: [list]"`, notify user
      with "⛔ Halted — Skills check failed: [list]. Restore missing files and run COORDINATOR
      to resume.", and terminate.~~
      Superseded — the inventory is now declarative data in `SDP-Workspace-Setup.json`,
      validated by the PREFLIGHT CHECK (step 0) above.

      > **Correction — 2026-07-23:** This superseded step's skill list still named
      > `sdp-pre-work-verify` — renamed to `sdp-project-pre-work-verify` as part of the
      > `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).

      > **Correction — 2026-07-23:** This superseded step's skill list also still named
      > `sdp-run-prompt` — renamed to `sdp-project-run-prompt` as part of the same
      > `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).

      > **Correction — 2026-07-23:** This superseded step's skill list also still named
      > `sdp-read-docs` — renamed to `sdp-project-read-docs` as part of the same
      > `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).

      > **Correction — 2026-07-24:** This superseded step's skill list also still named
      > `sdp-reviewer` — renamed to `sdp-project-reviewer` as part of the same
      > `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).

      > **Correction — 2026-07-24:** This superseded step's skill list also still named
      > `sdp-worker` — renamed to `sdp-project-worker` as part of the same
      > `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).

      > **Correction — 2026-07-24:** This superseded step's skill list also still named
      > `sdp-create-prompt` — renamed to `sdp-project-create-prompt` as part of the same
      > `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).

      > **Correction — 2026-07-24:** This superseded step's skill list also still named
      > `sdp-state-loop` — renamed to `sdp-project-state-loop` as part of the same
      > `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).

      > **Correction — 2026-07-24:** This superseded step's skill list also still named
      > `sdp-coordinator` — renamed to `sdp-project-coordinator` as the last skill in the same
      > `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).
  0c. Check workflow_status in state.json — if "halted": notify user of halt_reason, do not
      proceed, terminate. Same rule as the dispatch COORDINATOR: resolution is a human action.
  1. Read phase state file — confirm active task status is WORK_COMPLETE
  2. Write session-NNN.md with dispatch instructions for REVIEWER (include VERIFY_DURING_IMPLEMENTATION
     flag if present — REVIEWER must execute or observe, not just read code)
  3. Update state.json: last_session
  3a. Write sdp-docs/00_prompt.txt — overwrite with the REVIEWER prompt using the five-section format
      defined in the Workspace Setup sdp-docs/00_prompt.txt template. Role = REVIEWER; state summary
      from state.json; Task Instruction = "Verify [TASK-ID] against its acceptance criteria. Invoke
      ~~/sdp-reviewer~~ /sdp-project-reviewer to begin."; Key Files = state.json, session-NNN.md, phase file path.
  4. Notify user: "Ready to dispatch REVIEWER for [TASK-ID]. Open a new subagent and invoke
     ~~`/sdp-run-prompt`~~ `/sdp-project-run-prompt` — it will read `sdp-docs/00_prompt.txt` and invoke ~~`sdp-reviewer`~~ `sdp-project-reviewer` automatically."

     > **Correction — 2026-07-23:** This notify-user message still named `sdp-run-prompt` —
     > renamed to `sdp-project-run-prompt` as part of the `sdp-project-*` scope-prefix rename
     > (see `project-scope-skill-naming-design.md`).

     > **Correction — 2026-07-24:** The Task Instruction template above and this notify-user
     > message both also still named `sdp-reviewer` — renamed to `sdp-project-reviewer` as part
     > of the `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).

REVIEWER session (new subagent invocation):
  0. GPG CHECK — Verify standards/GenericProjectGuidlines_V[version].md exists. If missing:
     halt, notify user, do not proceed.
  0a. SUPERPOWERS CHECK — Verify Superpowers plugin is installed (`/plugin list`). If installed:
      Superpowers code review may be used as a thinking aid before writing the formal Eval
      blockquote; invoke explicitly — auto-triggering is prohibited. Superpowers output does
      NOT substitute for the Bootstrap Eval blockquote — the formal criterion-by-criterion
      evaluation with explicit outcome is still required.
  1. Read this bootstrap doc (roles, state machine)
  2. Read the session dispatch file (`sessions/session-NNN.md` — session number from state.json
     `last_session` field). Confirm role assignment. Note any re-evaluation trigger reason,
     VERIFY_DURING_IMPLEMENTATION flag, or other instructions included by COORDINATOR.
  3. Read state.json — confirm assigned task ID, phase file, and flags
  4. Read the task description in the phase file — form independent understanding
     before reading the Completed blockquote
  5. Read the Completed blockquote
  6. Independently verify — run build, read code, check GPG alignment for any topic this item
     is directly affected by: read `standards/GenericProjectGuidlines_Sections/GenericProjectGuidlines_TOC.md`,
     cross-reference its section titles against this task's content, and verify alignment for
     each matching topic.
     For VERIFY_DURING_IMPLEMENTATION tasks: execute or observe the behaviour directly
     - `.speq` alignment: verify naming, stack, and structure choices in the implementation
       match `[PROJECT].speq.md`. A deviation not noted in the Completed blockquote is a finding —
       including any new external dependency introduced without a resolved Material Decision
       Escalation halt on record for it (see Dispatch and Halt Contracts section). [2026-07-23
       addition — see `~SDP-Maintenance/~docs/material-decision-escalation-design.md`.]
  7. Append Eval N blockquote (criterion-by-criterion; each sub-step addressed explicitly)
     State outcome: compliant / partially compliant / non-compliant
     If non-compliant: include specific, actionable notes for the next WORKER session
  8. If compliant or partially compliant: append Verified N blockquote — outcome: Verified
     If non-compliant: do NOT write a Verified N blockquote
     A failed eval produces corrective notes only; a new Completed + Eval + Verified cycle follows
  9. Update [phase]_state.json:
     - If compliant: status → VERIFIED, eval_cycles + 1
     - If partially compliant: status → VERIFIED, eval_cycles + 1; add flag "PARTIAL_COMPLIANCE"
       to the task's flags array. If "PARTIAL_COMPLIANCE" is already present (second consecutive
       partially compliant verdict), also add flag "PARTIAL_COMPLIANCE_ESCALATE" — COORDINATOR
       must flag this task for design review before dispatching a new WORKER session.
     - If non-compliant (no Verified written): status → REJECTED, eval_cycles + 1
  10. Mirror phase file changes to parent doc per sync rule
  11. Session ends

Repeat.
```

**Critical rule:** Work on a task and review of that task must occur in separate subagent
invocations with no shared conversation history. An agent that performs work on a task is
ineligible to evaluate or verify that task. Enforced by session role assignment, not by trust.
Context isolation is achieved by spawning a new subagent for each role — `/clear` within an
existing context does not satisfy this requirement.

### Stuck-Loop Detection

~~`sdp-state-loop`~~ `sdp-project-state-loop` tracks REVIEWER dispatch attempts per task via `eval_cycle_attempts` in the
phase state file. This field is distinct from `eval_cycles`, which counts completed evaluations
(Eval blockquote written + state updated). The gap between the two detects a REVIEWER cycling
without producing output.

**Field: `eval_cycle_attempts`**

| Field | Type | Owner | When updated |
|-------|------|-------|--------------|
| `eval_cycle_attempts` | integer | ~~`sdp-state-loop`~~ `sdp-project-state-loop` | Incremented before each REVIEWER subagent spawn — detected via the sentinel `role="REVIEWER"` field on an EXECUTE fire whose `expected_status` is `WORK_COMPLETE`. The COORDINATOR dispatch-of-REVIEWER fire (sentinel `role="COORDINATOR"`) also reads `WORK_COMPLETE` but must **not** increment. A WORKER session must never write this field. Reset to `eval_cycles` value on successful auto-push or COORDINATOR reset. |
| `eval_cycles` | integer | REVIEWER | Incremented when a completed Eval blockquote is appended and state is written. |

Initial value for both fields is 0. If absent from an existing phase state file entry, treat as 0.

**COORDINATOR dispatch-authoring guard:** A dispatch file (`session-NNN.md` or
`sdp-docs/00_prompt.txt`) must never instruct WORKER or REVIEWER to set, seed, or increment
`eval_cycle_attempts` — the field is loop-owned, and a correctly-guarded WORKER/REVIEWER will
refuse the write. Dispatch state-write instructions are limited to: WORKER → `status`,
`last_session`, `last_updated`; REVIEWER → `eval_cycles` and `status`. An "On success" / "On
FAIL" step that directs a role to set or increment `eval_cycle_attempts` is the accounting
corruption this guard prevents. The sentinel `role` field is mandatory: omitting it prevents
~~`sdp-state-loop`~~ `sdp-project-state-loop` from distinguishing a REVIEWER fire from the COORDINATOR dispatch-of-REVIEWER
fire, corrupting attempt accounting.

**Halt condition:** When `eval_cycle_attempts - eval_cycles >= evalCycleAttemptThreshold`
(default 2, configurable in `SDP-Config.json` under `autoResolveHalt.evalCycleAttemptThreshold`),
~~`sdp-state-loop`~~ `sdp-project-state-loop` runs cause evaluation after the subagent returns:

1. `git branch --show-current` + `git log origin/[branch]..HEAD --oneline` — checks for unpushed commits
2. `git status --porcelain` — checks for uncommitted changes
3. Cause classified as UNPUSHED_COMMITS, UNCOMMITTED_CHANGES, or UNKNOWN

If cause = UNPUSHED_COMMITS and `autoResolveHalt.pushOnEvalBlock` is true in `SDP-Config.json`:
~~`sdp-state-loop`~~ `sdp-project-state-loop` pushes automatically, resets `eval_cycle_attempts`, logs the action to
`auto_actions` in `state.json`, and continues the loop.

Otherwise: `workflow_status` is set to `"halted"` in `state.json` with a specific `halt_reason`
identifying the cause. The loop stops and the user is notified with an actionable message.

**COORDINATOR reset rule:** When resetting a REJECTED task back to PENDING, set
`eval_cycle_attempts` to 0 alongside the status reset. The task re-enters the work cycle
with a clean attempt counter.

> **Correction — 2026-07-24:** This "Stuck-Loop Detection" section named `sdp-state-loop` five
> times (all instances struck through above) — renamed to `sdp-project-state-loop` as part of the
> `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).

### Phase Readiness Regression Bookkeeping

> **Addition — 2026-07-18:** `eval_cycle_attempts` (per task) and `gate_review_attempts` (per
> gate) exist solely to detect an *automated loop cycling without producing output* — a
> malfunction signal. A Phase-Readiness-triggered regression (see Phase 7's entry above) is a
> deliberate, human-approved new work cycle, not a malfunction — it needs different handling.
>
> **Reset rule — scoped, not blanket:** When COORDINATOR applies a chosen remediation, it resets
> `eval_cycle_attempts`/`gate_review_attempts` to 0 **only for the specific task(s) and gate(s)
> actually receiving new work in this cycle** — the regression target phase, and every
> intermediate phase between it and Phase 7. Tasks in the target phase that the remediation does
> not touch keep their existing counts unchanged.
>
> **Never-reset regression record — solution-scoped since 2026-07-20:** the *solution's*
> `.sdp-solution-workflow/state.json` gains a `phase_readiness` block (project-level `state.json`
> retains the identical field for the transient migration case only — see the
> `~SDP-Maintenance/~docs/solution-coordinator-orchestration-design.md` §11):
>
> ```json
> "phase_readiness": {
>   "regression_count": 0,
>   "regressions": [
>     { "target_phase": "[.sdp-solution-workflow/registry.md Phase column value]", "date": "2026-07-20",
>       "chosen_remediation": "small edit", "justification": "..." }
>   ]
> }
> ```
>
> `regression_count` is a fast-access total, incremented once per regression (not per gate
> attempt). `regressions[]` is the actual diagnostic record — which phase(s) recur, informing
> the human's next remediation choice. **`state.json` is a mirror, not the primary record** —
> each regression event is appended to `sdp-solution-docs/07_phase_readiness.md` first
> (append-only); the `state.json` block is a derived, fast-access copy.

### Pre-Work Verification Protocol

Execute this before performing work on any task. Purpose: prevent duplicate effort, detect
partially-complete states, and ensure clean resumption of interrupted work.

**Step 1 — Scan for Prior Artifacts**

Search the codebase, filesystem, database, and migrations for artifacts related to this task.
Examples by task type:
- "Create database" → check for database existence, schema state, applied migration journal
- "Implement entity classes" → search project for the class files
- "Create migration" → check migrations folder for timestamped migration files
- "Seed data" → query the target table or check post-deploy scripts

Look specifically for partial or incomplete artifacts (a class with only some properties,
a table missing columns, a script that was partially applied).

**Step 2 — Classify State**

| State | Definition |
|-------|------------|
| **Not Started** | No artifacts found; no evidence of prior work |
| **In Progress / Incomplete** | Artifacts exist but work is clearly partial |
| **Complete** | Task is finished and meets or exceeds the deliverables in the task description |

**Step 3 — Act Based on State**

**Not Started:** Proceed immediately. No confirmation required.

**In Progress / Incomplete:**
- Report to the user: what artifacts were found; what appears incomplete; last observed state
  (file dates, git history if available)
- Ask: "Should I continue from where this was left off, discard and restart, or inspect first?"
- Proceed only after confirmation
- Document the resumption or restart choice in the Completed blockquote

**Complete:**
- Skip the task
- Append a note: "Pre-work verification: task already complete as of [date if determinable]. No work performed."
- Move to the next task — do not re-implement a task that is already correct

---

## Solution Dispatch Loop

`sdp-solution-coordinator` runs the cross-project counterpart to the Implementation Loop above.
It never performs work itself and never invokes ~~`sdp-coordinator`~~ `sdp-project-coordinator` for a project it dispatches
directly — it fans out to per-project WORKER/REVIEWER sessions across every project registered
to a shared solution task, in a single dispatch cycle, rather than driving one project's
Implementation Loop at a time.

**Cycle sync invariant:** every child project participating in the same cross-project (solution
-level) task is kept in lockstep. Each cycle, the coordinator identifies the "laggard" child
projects — those whose task status has fallen behind the others on the same solution task — and
dispatches only those, so no project's WORKER/REVIEWER pair is ever allowed to run more than one
step ahead of its siblings on a shared task.

```
SOLUTION_COORDINATOR session (new subagent invocation):
  0. PREFLIGHT CHECK — Run (PowerShell tool):
     ```
     .\sdp-shared\scripts\sdp-preflight.ps1 -workspaceRoot .
     ```
     `-workspaceRoot .` — the solution root itself, not a per-project path — so the script
     resolves the solution-level manifest (`SDP-Solution-Setup.json`) instead of any project's
     `SDP-Workspace-Setup.json`. One call validates every deterministic solution-level
     precondition and emits a JSON envelope. On `ok:false`: halt per the Halt Behavior Contract
     citing the envelope's `failures` (or `error` for an operational error such as a
     missing/unparseable manifest), notify the user, and terminate. The canonical inventory is
     data in `SDP-Solution-Setup.json`, not enumerated here. Pass `-Force` to bypass the
     per-tier staleness timers for a full re-check.
  1. Read `SDP-Solution.json` and `.sdp-solution-workflow/state.json` — resolve
     `active_solution_task` and the authoritative status of every registered child project.
  2. Enforce the cycle sync invariant — compute the laggard child projects for the active
     solution task.
  3. Branch on the result: a `blocked` or `cascade` condition halts all dispatch for this cycle
     (a cascade freezes the whole solution task until a human reviews it — see Cascade
     Detection); an `all_verified` result advances or completes the solution task; otherwise
     write one session dispatch file per laggard project (or a single SOLUTION_REVIEWER dispatch
     once every child has reached WORK_COMPLETE).
  4. Fan out — dispatch every laggard project's session file as a subagent: parallel (synced
     mode) or one at a time in declared order (sequenced mode), invoking ~~`sdp-worker`~~
     `sdp-project-worker` or ~~`sdp-reviewer`~~ `sdp-project-reviewer` directly for each. Never invoke ~~`sdp-coordinator`~~ `sdp-project-coordinator` for a project involved in
     a cross-project task.

     > **Correction — 2026-07-24:** This step still named `sdp-reviewer` — renamed to
     > `sdp-project-reviewer` as part of the `sdp-project-*` scope-prefix rename (see
     > `project-scope-skill-naming-design.md`).

     > **Correction — 2026-07-24:** This step also still named `sdp-worker` — renamed to
     > `sdp-project-worker` as part of the same `sdp-project-*` scope-prefix rename (see
     > `project-scope-skill-naming-design.md`).

     > **Correction — 2026-07-24:** This section's opening paragraph and this step both also
     > still named `sdp-coordinator` — both instances renamed to `sdp-project-coordinator` as
     > the last skill in the same `sdp-project-*` scope-prefix rename (see
     > `project-scope-skill-naming-design.md`).
  5. After the dispatched subagents in this cycle return: read each child project's phase state
     file to confirm the outcome — never the subagent's returned text. Note any child now ready
     for the next dispatch step (e.g., WORK_COMPLETE → REVIEWER on the next cycle).
  6. Terminate. Each invocation is exactly one dispatch cycle — do not loop internally or
     re-invoke the coordinator; further dispatch happens on the next `sdp-solution-coordinator`
     invocation.

Repeat.
```

**Critical rule:** as with the Implementation Loop, work and review of that work occur in
separate subagent invocations with no shared conversation history — enforced by session role
assignment, not by trust.

---

## Append-Only Discipline

---

> **Document Integrity Notice:** Deleting something from the decision record doesn't erase the decision — it erases the evidence that a decision was made.
>
> ⚠️ **Append-only.** Do not delete or edit existing content. Status markers and evaluations
> may be appended; ~~nothing may be removed or reworded~~ — strikethrough (`~~text~~`) is a
> valid edit technique: mark the old text as superseded in place and place the replacement
> immediately after on a new line. This preserves the decision audit trail.
> A deleted constraint looks like an unconsidered constraint to future readers.

---

Additional rules:

- **Evaluation and verification notes** are appended at the end of the relevant section with a datestamp.
- **Decisions** are appended as numbered entries with dates.
- **Exception:** Template placeholder text (e.g., `[DATE]`, `[PROJECT]`) is replaced once during
  initial setup. After setup, append-only applies.

Example of a superseded decision:

```markdown
## Decision: Database

~~Use PostgreSQL hosted on Render.~~ [2025-06-01]

> Superseded [2025-06-09]: Switched to PlanetScale (MySQL-compatible) due to connection pooling
> requirements at scale. See architecture section 3.2 for rationale.

Use PlanetScale (MySQL-compatible) with Prisma ORM. [2025-06-09]
```

> **Addition — 2026-07-22:** this section's rules — and the append-only discipline generally —
> apply to phase documents, section files, and this bootstrap doc. They do not extend to skill
> files (`.claude/skills/*/SKILL.md`, `sdp-shared/ai-skills/*/SKILL.md`) or script files
> (`sdp-shared/scripts/*.ps1`). A skill or script file is an executable procedure, not a decision
> record — it should state only the current, correct rule. It must not carry dated
> `Addition —`/`Correction —` narrative blocks documenting past bugs, incidents, or design
> rationale.
>
> This distinction was learned the hard way: a skill file that had accumulated several dated
> bug-history blocks directly above the exact procedure step those bugs occurred in was later
> confirmed, by the dispatched agent's own account, to have contributed to that agent reaching
> for a prohibited verification workaround at that step — reading "this has broken before"
> immediately before attempting the step eroded confidence in executing it unaided. A skill file
> is read wholesale into an agent's live working context every time it runs; historical narrative
> sitting upstream of the step it explains is a standing liability there in a way it is not for a
> phase document, which a future reader consults for context rather than executes as
> instructions.
>
> **What to do instead:** git history (`git log`, `git blame`, commit messages) is the audit
> trail for why a skill or script rule changed — it does not need duplicating inline. If a fuller
> write-up is wanted beyond what a commit message captures, that belongs in a location the
> maintaining project chooses; this document intentionally does not prescribe one, since the
> right location varies by project and is not itself part of the executable workflow. Concrete
> reference material that helps an agent execute a step correctly — a worked example, a verbatim
> "do not reproduce this" example — is not history and is not covered by this rule; the
> distinction is date-stamped incident narrative versus current, execution-relevant content. See
> `SDP-Skill-Authoring.md` and `SDP-Script-Authoring.md` for the required skill/script file
> structure, neither of which includes a changelog/history section.

---

## Phase Gate Procedure

Before advancing from one phase to the next, a gate review must pass.

1. **PREFLIGHT CHECK** — ~~COORDINATOR runs `sdp-shared/scripts/sdp-preflight.ps1` (PowerShell
   tool) before initiating any gate review.~~ [2026-07-18: corrected — see Correction below]
   COORDINATOR resolves `[resolved_project]` using the three-level order defined in the Project
   Resolution Order section of this doc, then runs (PowerShell tool) before initiating any gate
   review:
   ```
   .\sdp-shared\scripts\sdp-preflight.ps1 -workspaceRoot .\[resolved_project]
   ```
   One call validates every deterministic precondition
   — GPG presence/version, all sdp- skill pairs (Level 1 + Level 2), the sdp-tone
   L1-present/L2-absent invariant, the scripts, `SDP-Tones.json`, and the
   scaffold/config/document-list checks — against the `SDP-Workspace-Setup.json` manifest, and
   emits a JSON envelope. On `ok:false`: halt, notify user citing the envelope's `failures` (or
   `error`), resolve before proceeding. The canonical inventory is data in the manifest; pass
   `-Force` to bypass the staleness timers for a full re-check.
   > ~~**GPG CHECK** — COORDINATOR verifies `standards/GenericProjectGuidlines_V[version].md`
   > exists and version matches `gpg_version` in `state.json` before initiating any gate review.
   > If missing or mismatched: halt, notify user, resolve before proceeding.~~ (superseded —
   > covered by the PREFLIGHT CHECK manifest)

   > **Correction — 2026-07-18:** This step showed the `sdp-preflight.ps1` invocation as inline
   > prose with no `-workspaceRoot` argument, unlike this document's two other invocations
   > (Implementation Loop COORDINATOR session step 0, and the COORDINATOR-dispatching-REVIEWER
   > session step 0), both of which show `.\sdp-shared\scripts\sdp-preflight.ps1 -workspaceRoot
   > .\[resolved_project]` in a code block. Omitting `-workspaceRoot` left the script defaulting
   > to two levels above its own `sdp-shared/scripts/` location instead of the resolved project
   > path used everywhere else — a gate review run from a multi-project solution would silently
   > validate the wrong project's manifest. Now consistent with the other two call sites.
1a. **SUPERPOWERS CHECK** — Verify Superpowers plugin is installed (`/plugin list`). If missing:
    note in gate review session dispatch. REVIEWER may still use Superpowers code review as a
    thinking aid if installed; formal gate verdict documentation is required regardless. (Not
    script-able — `/plugin list` is a harness command; it stays an agent step.)
1b. > ~~**SKILLS CHECK** — Verify that both Level 1 (`.claude/skills/[name]/SKILL.md`) and Level 2
    > (`sdp-shared/ai-skills/[name]/SKILL.md`) files exist for all sdp- skills: sdp-auto,
    > sdp-cancel-auto, ~~sdp-coordinator~~ sdp-project-coordinator, ~~sdp-create-prompt~~ sdp-project-create-prompt, ~~sdp-pre-work-verify~~
    > sdp-project-pre-work-verify, ~~sdp-read-docs~~ sdp-project-read-docs, ~~sdp-reviewer~~ sdp-project-reviewer,
    > ~~sdp-run-prompt~~ sdp-project-run-prompt, ~~sdp-state-loop~~ sdp-project-state-loop, sdp-state-loop-start, ~~sdp-worker~~ sdp-project-worker. Also verify
    > `.claude/skills/sdp-tone/SKILL.md` and `sdp-shared/scripts/sdp-tone.ps1` exist, and that
    > `SDP-Tones.json` exists at the workspace root (tone config read by sdp-tone.ps1).
    > Also verify `sdp-shared/scripts/sdp-github.ps1` exists (the unified git/gh script;
    > its `ci-status` subcommand is the CI-green gate when `SDP-Config.json` `ci.enabled` is true).
    > (`sdp-shared/ai-skills/sdp-tone/SKILL.md` must **not** exist — sdp-tone was converted
    > to a script; do not create a Level 2 SKILL.md for it.) If any file is missing: halt, notify user,
    > resolve before proceeding.~~
    Superseded — the skill/script/config inventory is now declarative data in
    `SDP-Workspace-Setup.json`, validated by the PREFLIGHT CHECK (step 1) above.

    > **Correction — 2026-07-23:** This superseded step's skill list still named
    > `sdp-pre-work-verify` — renamed to `sdp-project-pre-work-verify` as part of the
    > `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).

    > **Correction — 2026-07-23:** This superseded step's skill list also still named
    > `sdp-run-prompt` — renamed to `sdp-project-run-prompt` as part of the same
    > `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).

    > **Correction — 2026-07-23:** This superseded step's skill list also still named
    > `sdp-read-docs` — renamed to `sdp-project-read-docs` as part of the same
    > `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).

    > **Correction — 2026-07-24:** This superseded step's skill list also still named
    > `sdp-reviewer` — renamed to `sdp-project-reviewer` as part of the same
    > `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).

    > **Correction — 2026-07-24:** This superseded step's skill list also still named
    > `sdp-worker` — renamed to `sdp-project-worker` as part of the same
    > `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).

    > **Correction — 2026-07-24:** This superseded step's skill list also still named
    > `sdp-create-prompt` — renamed to `sdp-project-create-prompt` as part of the same
    > `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).

    > **Correction — 2026-07-24:** This superseded step's skill list also still named
    > `sdp-state-loop` — renamed to `sdp-project-state-loop` as part of the same
    > `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).

    > **Correction — 2026-07-24:** This superseded step's skill list also still named
    > `sdp-coordinator` — renamed to `sdp-project-coordinator` as the last skill in the same
    > `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).
2. COORDINATOR initiates a gate review session (new subagent invocation) using the
   ~~`sdp-gate-review`~~ `sdp-project-gate-review` skill. The session dispatch file sets `role = GATE_REVIEWER`. In
   loop-orchestrated mode, COORDINATOR writes `sdp-docs/00_prompt.txt` with sentinel
   `role="GATE_REVIEWER"` and terminates — ~~`sdp-state-loop`~~ `sdp-project-state-loop` handles execution on the next fire.

   > **Correction — 2026-07-24:** This step still named `sdp-gate-review` — renamed to
   > `sdp-project-gate-review` as part of the `sdp-project-*` scope-prefix rename (see
   > `project-scope-skill-naming-design.md`).

   > **Correction — 2026-07-24:** This step also still named `sdp-state-loop` — renamed to
   > `sdp-project-state-loop` as part of the same `sdp-project-*` scope-prefix rename (see
   > `project-scope-skill-naming-design.md`).
3. GATE_REVIEWER reads the completed phase document
4. REVIEWER appends a gate verdict blockquote to the phase document using this format:
   ```markdown
   > **Gate Verdict — [GATE_PASSED | GATE_BLOCKED] — [YYYY-MM-DD HH:MM]**
   > Reviewer: session-NNN
   > [For GATE_PASSED: brief confirmation of what was verified.]
   > [For GATE_BLOCKED: numbered list of specific issues with section references and
   >  required changes before the gate can pass.]
   ```
5. ~~If GATE_BLOCKED: COORDINATOR sets `phase_gate_status: "blocked"` in state.json~~
   [2026-07-07: field name corrected — see below] If GATE_BLOCKED: `phase_gate.status` is
   `"blocked"` (written by GATE_REVIEWER via ~~`sdp-gate-review`~~ `sdp-project-gate-review`, not COORDINATOR — see
   ~~`sdp-gate-review/SKILL.md`~~ `sdp-project-gate-review/SKILL.md` Step 9); issues are addressed within the current phase; a new
   gate review cycle begins.
6. ~~If GATE_PASSED: COORDINATOR sets `phase_gate_status: "passed"` and advances `current_phase`~~
   [2026-07-07: field name corrected] If GATE_PASSED: `phase_gate.status` is `"passed"`
   (written by GATE_REVIEWER); COORDINATOR then advances `current_phase` in state.json.

   > **Correction — 2026-07-07:** `phase_gate_status` (flat) was a stale field name never
   > matched by any implementation. `sdp-create-prompt.ps1`, ~~`sdp-coordinator/SKILL.md`~~ `sdp-project-coordinator/SKILL.md`, and
   > ~~`sdp-gate-review/SKILL.md`~~ `sdp-project-gate-review/SKILL.md` all use the nested `phase_gate.status` /
   > `phase_gate.gate_eval_cycles` shape — that is the authoritative one.

   > **Correction — 2026-07-24:** Item 5's prose above and the 2026-07-07 correction's own text
   > all still named `sdp-gate-review` (three instances total, all struck through above) —
   > renamed to `sdp-project-gate-review` as part of the `sdp-project-*` scope-prefix rename
   > (see `project-scope-skill-naming-design.md`).

   > **Correction — 2026-07-24:** The 2026-07-07 correction's own text also still named
   > `sdp-coordinator/SKILL.md` — struck through above and renamed to
   > `sdp-project-coordinator/SKILL.md` as the last skill in the same `sdp-project-*`
   > scope-prefix rename (see `project-scope-skill-naming-design.md`).

Gate reviews use the same REVIEWER role and session isolation rules as work item reviews.

---

## Pros-Cons-Gaps Cycle

Used within the Architecture and Implementation Overview phases. COORDINATOR sets cycle target N
in the session dispatch file before the first cycle begins; default N=2 unless architectural
complexity warrants more. Minimum is 2 cycles.

Each cycle:
1. REVIEWER reads the current document
2. REVIEWER appends a structured evaluation including a mandatory "Unresolved gap count: N" line:
   ```markdown
   ## Pros-Cons-Gaps — Cycle N — [DATE]
   ### Pros
   - [what is well-defined and sound]
   ### Cons
   - [weaknesses in current form]
   ### Gaps
   - [missing content, unresolved decisions, unclear boundaries]
   **Unresolved gap count: N**
   ```
3. WORKER session addresses each gap using the Gap Resolution Format below
4. Cycle repeats until either: (a) the appended evaluation contains "Unresolved gap count: 0",
   OR (b) the cycle target N has been reached, whichever comes first

After the final cycle, the document goes to gate review.

**Gap resolution criteria** — a gap is considered resolved only when one of the following applies:
- A design decision, code fix, or explicit restatement has been recorded and explicitly approved
  by the user in the current or a prior session
- The gap has been explicitly migrated to the Deferred list in the document Appendix with a
  written rationale
- The gap has been explicitly declared out of scope with a written rationale

> **Addition — 2026-07-23:** A gap that trips either Material Decision Escalation trigger
> (Dispatch and Halt Contracts section — an external dependency not already named in `.speq`, or
> an architectural pattern with no GPG precedent) cannot be resolved via the Deferred or
> declared-out-of-scope bullets above alone. It must go through that escalation and reach either
> explicit user approval or an explicitly user-approved deferral before it counts as resolved. See
> `~SDP-Maintenance/~docs/material-decision-escalation-design.md`.

### Gap Resolution Format

Each identified gap is resolved using this structure. Append resolutions below the gap; never
replace the original gap text.

```markdown
### GAP N: [Gap Title] ✅ RESOLVED [GENERIC PATTERN] | [PROJECT-SPECIFIC]

**Reference:** [spec ID, work item ID, or section reference]

**The Gap:**
[What is missing or undefined — quote the relevant spec text if applicable]

**Options:**

| Option | Approach | Pros | Cons |
|--------|----------|------|------|
| **A** | [description] | [pros] | [cons] |
| **B** | [description] | [pros] | [cons] |

**Impact:**
- [What cannot be built or decided without resolving this gap]

**Decision Made:**
- **Selected:** [Option X] — [one-line summary]
- **Rationale:** [why this option over others]
- **Implementation detail:** [schema, code snippet, config, or reference to section file]
- **Assignee:** [work item ID or phase reference]
```

**Annotation tags** (append to the gap heading in place of or after the status marker):
- `✅ RESOLVED [GENERIC PATTERN]` — decision is reusable across projects; capture in `PATTERNS.md`
- `✅ RESOLVED [PROJECT-SPECIFIC]` — decision is specific to this project's constraints; do not generalize
- `✅ RESOLVED [GENERIC PATTERN] [PROJECT-SPECIFIC]` — part generic, part project-specific
- `⏳ [NEEDS DESIGN SESSION]` — gap identified, recommendation made, stakeholder decision required before resolution
- `⏳ [DEFERRED]` — gap acknowledged, resolution pushed to a later cycle with documented reason
- Both `[GENERIC PATTERN]` and `[PROJECT-SPECIFIC]` may appear together when the approach is reusable but specific values are not

### GPG Cross-Reference

When a gap resolution aligns with a GPG pattern, add a `**GPG Reference:**` line to the
Decision Made block. This proves the decision follows established standards rather than
introducing something new, and gives future agents a direct pointer to the authoritative source.

```markdown
**Decision Made:**
- **Selected:** [Option X]
- **Rationale:** [why]
- **GPG Reference:** [Chapter N — Chapter Title] → `standards/GenericProjectGuidlines_Sections/GenericProjectGuidlines_[ChapterName].md`
- **Implementation detail:** [schema, code, config]
- **Assignee:** [work item ID]
```

At the end of each phase document, include a cross-reference table mapping decisions to GPG:

```markdown
## GPG Alignment — [Document Name]

| Decision | GPG Chapter | GPG Location |
|----------|-------------|--------------|
| [decision title] | Ch. N — [Chapter Name] | `standards/GenericProjectGuidlines_Sections/GenericProjectGuidlines_[Name].md` |
```

This table serves two purposes: it confirms the decision is standards-aligned, and it gives
the next agent a targeted reading list for the relevant GPG chapters before starting work.

**Agent rule during architecture and design phases:** Before drafting any section, read the
relevant GPG chapters identified in `state.json` or the phase TOC audience column. Reference
GPG content; do not restate it. If a decision diverges from the GPG, document the divergence
explicitly and note the project-specific reason.

### Traceability IDs

Reference IDs in gap headings and decision text trace decisions back to originating requirements.
Use a consistent format for the project — examples: `P5-SVC-03`, `OQ-7`, `AC-2`. The format
does not matter; consistency within a project does. IDs allow an agent to locate the originating
spec item without reading the full document.

### Cycle Summary Table

Append this table at the end of each completed cycle to provide an at-a-glance resolution status:

```markdown
## Gap Resolution Summary — Cycle N — [DATE]

| Gap # | Title | Status | Key Resolution |
|-------|-------|--------|----------------|
| 1 | [Gap Title] | ✅ RESOLVED | [one-line summary] |
| 2 | [Gap Title] | ⏳ DEFERRED | [reason + target cycle] |
| 3 | [Gap Title] | ⚠️ BLOCKED | [blocker description] |
```

### Quick Decision Format

For decisions that don't warrant a full gap format — no options comparison needed, decision
is straightforward — use an Open Questions table with inline resolution. This is append-only
compliant: the original question is preserved and the resolution is prepended in the same cell.

```markdown
## Open Questions / Decisions Required

| # | Question | Impact |
|---|----------|--------|
| OQ-1 | **Resolved — [decision summary]. [DATE].** [Full resolution detail and rationale. References to affected tasks.] Original question: [original question text as first written] | [affected phases or tasks] |
| OQ-2 | [Unresolved question text] | [affected phases or tasks] |
```

Use the full Gap Resolution Format when:
- Multiple viable options exist and the tradeoffs need documenting
- The decision has broad architectural impact
- The decision warrants a `[GENERIC PATTERN]` tag

Use the Quick Decision Format when:
- The answer is clear once the question is asked
- The decision is scoped to a single task or phase
- No options comparison is needed

---

## Orchestration Options

Four viable approaches. Choose based on project complexity and team size.

| Mode | Coordinator | Dispatch | Best For |
|------|-------------|----------|----------|
| **Human-gated** | User reads state.json, manually spawns subagents | Manual | Early projects, high ambiguity |
| **Script-gated** | Shell script reads state.json, prints next action | Semi-auto | Repeatable projects |
| **Agent-orchestrated** | COORDINATOR agent with subagent dispatch | Automated | High-volume, well-defined items |
| **Loop-orchestrated** | ~~`sdp-state-loop`~~ `sdp-project-state-loop` recurring loop, started via `/sdp-auto` | Fully automated, time-based | Active development runs with no manual dispatch |

> **Correction — 2026-07-24:** The Loop-orchestrated row's Coordinator column still named
> `sdp-state-loop` — renamed to `sdp-project-state-loop` as part of the `sdp-project-*`
> scope-prefix rename (see `project-scope-skill-naming-design.md`).

Start with **human-gated**. Promote to script-gated once the workflow is stable.

> **Addition — 2026-07-27 — recommended Claude Code permission mode:** For agent-orchestrated and
> loop-orchestrated dispatch, run the driving Claude Code session under the CLI's official `auto`
> permission mode (`claude --permission-mode auto`) rather than the default interactive mode — SDP
> issues many PowerShell-tool calls per session and `auto` mode avoids per-call prompt fatigue
> while still applying Claude Code's background safety checks. This is distinct from
> `bypassPermissions`, which disables those checks entirely and is documented as container/VM-only
> — SDP does not recommend it. See `README.md` Requirements for detail.

**Session isolation in all modes:** Each role (COORDINATOR, WORKER, REVIEWER) runs as a separate
subagent invocation. The session dispatch file (`session-NNN.md`) is the only cross-session
communication channel — written by COORDINATOR before dispatch, read by the dispatched agent
as step 2. `/clear` within an existing context does not achieve isolation.

Script-gated dispatch (`workflow.ps1` — to be created):
- Reads state.json
- Prints current item, current state, and next expected role
- Prompts user to confirm before launch
- Spawns a new subagent with the session dispatch file as initial context
- Waits for state.json update before allowing next dispatch

---

## Dispatch and Halt Contracts

> **Skill authoring reference:** Two-level structure, Level 1 and Level 2 templates, and the
> worked example (~~`sdp-pre-work-verify`~~ `sdp-project-pre-work-verify`) are in
> `SDP-Skill-Authoring.md`.
>
> **Correction — 2026-07-23:** The worked example skill was renamed to
> `sdp-project-pre-work-verify` as part of the `sdp-project-*` scope-prefix rename (see
> `project-scope-skill-naming-design.md`).

### Subagent Spawning Contract

Skills that dispatch other roles (COORDINATOR dispatching WORKER or REVIEWER) must follow one of
three paths determined by the `orchestration_mode` field in `state.json`.

**Reading orchestration mode:** At the start of any dispatch step, read `state.json` and branch on
`orchestration_mode`:

| Value | Path |
|-------|------|
| `"human-gated"` | Print dispatch instructions and terminate; human spawns subagent manually |
| `"agent-orchestrated"` | Spawn subagent via Agent tool; read state file for outcome after return |
| `"loop-orchestrated"` | COORDINATOR writes `sdp-docs/00_prompt.txt` then terminates; `/sdp-auto` or `/sdp-state-loop-start` starts a recurring ~~`sdp-state-loop`~~ `sdp-project-state-loop` via the `loop` skill; loop handles all subsequent dispatch |

If `orchestration_mode` is absent or holds any value other than the three above, treat it as
`"human-gated"`: print the dispatch instructions and terminate without spawning.

> **Correction — 2026-07-24:** The `"loop-orchestrated"` row's Path column still named
> `sdp-state-loop` — renamed to `sdp-project-state-loop` as part of the `sdp-project-*`
> scope-prefix rename (see `project-scope-skill-naming-design.md`).

#### Human-gated dispatch path

1. Write `session-NNN.md` with complete dispatch instructions (role, task ID, phase file path, flags)
2. Update `state.json`: `last_session`, `active_work_item`
3. Print to user: "Ready to dispatch [ROLE] for [TASK-ID] — start a new subagent with
   `sessions/session-NNN.md` as the opening prompt."
4. Terminate. Do not wait for or attempt to detect the outcome.

On the next COORDINATOR invocation, read `[phase]_state.json` to determine what the dispatched
agent produced.

**Context to pass to the spawned subagent:** The session dispatch file (`session-NNN.md`) is the
only required input. It must contain: role assignment, task ID, phase file path, bootstrap doc path,
and any flags. The spawned agent reads the bootstrap doc as its first step per role session
instructions — it does not need the full bootstrap content embedded in the dispatch file.

#### Agent-orchestrated dispatch path

1. Write `session-NNN.md` with complete dispatch instructions
2. Update `state.json`: `last_session`, `active_work_item`
3. Spawn subagent via the Agent tool with prompt: content of `session-NNN.md` plus the path to this
   bootstrap doc
4. After the Agent tool returns: read `[phase]_state.json` to get the outcome
5. Continue COORDINATOR logic based on outcome (VERIFIED → next task; REJECTED → re-queue)

**Outcome detection:** The spawned agent writes its outcome to `[phase]_state.json`. The dispatching
skill reads that file after the Agent tool call returns — do not parse the subagent's text output
for the outcome. Text output is for the human record; state files are the machine-readable contract.

#### Loop-orchestrated dispatch path

1. Write `session-NNN.md` with complete dispatch instructions
2. Update `state.json`: `last_session`, `active_work_item`
3. Write `sdp-docs/00_prompt.txt` with the sentinel line and five-section prompt for the next role
4. Terminate. Do not spawn a subagent — the loop handles dispatch.

User runs `/sdp-auto` once to start the loop. On each scheduled fire, ~~`sdp-state-loop`~~ `sdp-project-state-loop`:
- Evaluates the `sdp-docs/00_prompt.txt` sentinel against current workflow state
- Spawns a subagent to execute (~~`sdp-run-prompt`~~ `sdp-project-run-prompt`) or generate
  (~~`sdp-create-prompt`~~ `sdp-project-create-prompt`) as needed

  > **Correction — 2026-07-23:** This bullet still named `sdp-run-prompt` — renamed to
  > `sdp-project-run-prompt` as part of the `sdp-project-*` scope-prefix rename (see
  > `project-scope-skill-naming-design.md`).

  > **Correction — 2026-07-24:** This bullet also still named `sdp-create-prompt` — renamed to
  > `sdp-project-create-prompt` as part of the `sdp-project-*` scope-prefix rename (see
  > `project-scope-skill-naming-design.md`).

  > **Correction — 2026-07-24:** The lead-in sentence above ("On each scheduled fire...") also
  > still named `sdp-state-loop` — renamed to `sdp-project-state-loop` as part of the same
  > `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).
- Handles both task dispatch (WORKER/REVIEWER) and gate dispatch (GATE_REVIEWER when all phase
  tasks are VERIFIED and `phase_gate.status` is `"pending"` or `"blocked"`)
- Reads `[phase]_state.json` (task dispatch) or `state.json.phase_gate.status` (gate dispatch)
  after the subagent returns to confirm the new status
- Enforces stuck-loop protection for both task and gate review attempts (`eval_cycle_attempts`
  / `gate_review_attempts`) with the same halt and auto-push logic
- Stops automatically on any blocking condition (halted workflow, DIAGNOSIS_BLOCKED,
  GATE_BLOCKED, no active item)
- ~~Appends one JSON line to `.sdp-solution-workflow/loop_metrics.jsonl` at the solution root
  after every fire~~ [2026-07-17: superseded — see below] — an append-only, gitignored record of
  `timestamp`, `project`, `action`, `work_item`, `role`, `status_before`/`status_after`, and
  `halted`/`halt_reason`. ~~`sdp-shared/scripts/sdp-tone.ps1` appends to the same file~~ on every
  real (non-`-whatIf`) tone invocation on both its channels (skill start/end and workflow-event
  triggers), bracketing subagent work independent of the loop's own per-fire entries. The
  ~~`sdp-loop-metrics-report`~~ [2026-07-17: skill renamed — see Correction below] skill reads
  ~~this file~~ on manual invocation to produce a
  time-accounting, halt/interruption, and task-outcome report — see `SDP-Workspace-Setup.md` for
  the file's place in the solution root layout.

  > **Correction — 2026-07-17:** The single fixed `loop_metrics.jsonl` file described above was
  > replaced with ~~one dated `loop-metrics-yyyyMMddHHmm.jsonl` file per "body of work," under~~
  > `.sdp-solution-workflow/logging/loop-logs/`. ~~`sdp-state-loop-start` creates a fresh file
  > each time the loop starts;~~ ~~`sdp-state-loop`~~ `sdp-project-state-loop`'s per-fire append and `sdp-tone.ps1`'s metrics
  > side-effect both always target ~~the most recently dated file in that folder~~ (the latter
  > bootstraps one itself if none exists, for tone activity outside any loop run).
  > ~~`sdp-loop-metrics-report`~~ now resolves which ~~run's~~ file to read — from the request if a
  > ~~run~~ day is named, otherwise by presenting the most recent ~~runs~~ dates for the user to
  > pick from — before invoking the script. See `SDP-Workspace-Setup.md` and
  > `SDP-Tone-Notifications.md` for the current layout and write/read contract.
  >
  > **Correction — 2026-07-17 (same day, revised):** The "body of work" / `sdp-state-loop-start`
  > trigger above was itself superseded before it shipped in any released form. Rotation is now
  > purely by calendar date, independent of any workflow action: the file is
  > `loop-metrics-yyyyMMdd.jsonl`, and both ~~`sdp-state-loop`~~ `sdp-project-state-loop`'s per-fire append and
  > `sdp-tone.ps1`'s metrics side-effect target *today's* file, creating it on first write of the
  > day. `sdp-state-loop-start` does not create or touch any metrics file — that added step was
  > removed. ~~`sdp-loop-metrics-report`~~'s picker now presents plain dates (the file naming has no
  > time component to derive a finer label from).

  > **Correction — 2026-07-24:** The two `sdp-state-loop` mentions embedded in the 2026-07-17
  > corrections above (both instances struck through above) — renamed to `sdp-project-state-loop`
  > as part of the `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).
  > The `sdp-state-loop-start` mentions in those same corrections are a different skill and are
  > left untouched.

  > **Addition — 2026-07-17 — hook-based tool-call logging:** A second, independent logging
  > mechanism now exists alongside the loop-metrics story above: `sdp-hook-log.ps1`, registered
  > as an async `PreToolUse`/`PostToolUse` hook in `.claude/settings.local.json` (no matcher —
  > fires for every tool call; gated per-tool by
  > ~~`.sdp-solution-workflow/script-support/sdp-hook-log-tools.json`~~ [2026-07-18: path
  > superseded — see Correction below] `sdp-shared/scripts/script-support/sdp-hook-log-tools.json`),
  > writes one JSON line per
  > logged event to `.sdp-solution-workflow/logging/hook-logs/hook-log-<local-yyyyMMdd>.jsonl` —
  > a sibling folder to `loop-logs/`, same one-file-per-local-calendar-day shape, but a distinct
  > data source (raw per-tool-call telemetry, not workflow-fire/tone events) with its own
  > retention sweep. The two logs are not merged and serve different readers: `loop-logs/` feeds
  > ~~`sdp-loop-metrics-report`~~'s workflow-level time accounting; `hook-logs/` is a fine-grained
  > tool-call trace, keyed by `session_id` (distinguishes concurrent Claude Code windows — hooks
  > fire per-window, not per-workflow-action) and `agent_id` (present only on calls made inside a
  > dispatched subagent, distinguishing that subagent's own tool calls from its parent session's).
  > See `SDP-Workspace-Setup.md` for the file's place in the solution root layout.

  > **Correction — 2026-07-18:** `script-support/` (holding `sdp-hook-log-tools.json`,
  > `SDP-Tones.json`, `sdp-create-banner-icons.json`, and `SDP-Terminal-Sessions.json`)
  > user-directed move: relocated from `.sdp-solution-workflow/script-support/` to
  > `sdp-shared/scripts/script-support/` — a sibling folder to the scripts that read it, rather
  > than a solution-workflow runtime folder. Every reading script (`sdp-tone.ps1`,
  > `sdp-hook-log.ps1`, `sdp-create-banner.ps1`, ~~`sdp-new-claude-terminal.ps1`~~
  > `sdp-claude-new-terminal.ps1`) now resolves it
  > directly off `$PSScriptRoot` instead of via `$workspaceRoot`. See `SDP-Changelog.md` for the
  > full list of files updated to match.

  > **Correction — 2026-07-28:** This correction's own text still named `sdp-new-claude-terminal.ps1`
  > — renamed to `sdp-claude-new-terminal.ps1` (skill rename, no behavior change). See
  > `SDP-Changelog.md` for the full list of files updated to match.

  > **Addition — 2026-07-17 — semantic workflow-event logging:** The narrative counterpart to
  > `hook-log-*.jsonl` above: `sdp-workflow-log.ps1`, called directly by ~~`sdp-coordinator`~~ `sdp-project-coordinator`
  > (dispatch decisions, halts, phase/all-complete milestones), ~~`sdp-worker`~~ `sdp-project-worker` (halts, completion
  > outcomes), and ~~`sdp-reviewer`~~ `sdp-project-reviewer` (halts, eval outcomes), and internally by
  > `sdp-gate-review-finalize.ps1` (gate verdicts) alongside its existing `sdp-tone.ps1` call —
  > not fired by a hook, since a hook only sees `tool_name`/`tool_input`/`tool_output` and cannot
  > capture *why* a decision was made. Writes one JSON line per call to
  > `.sdp-solution-workflow/logging/workflow-logs/workflow-log-<local-yyyyMMdd>.jsonl` — a third
  > sibling to `loop-logs/` and `hook-logs/`, same one-file-per-local-day shape and retention
  > sweep. Correlates with `hook-logs/` by `work_item`, not `session_id` — Claude Code does not
  > expose a session identifier to an agent-invoked script (confirmed against the Claude Code
  > docs before this script was written), but SDP's own Role Separation invariant (one role, one
  > work item, per session) makes `work_item` an adequate join key regardless. See
  > `SDP-Workspace-Setup.md` for the file's place in the solution root layout.

  > **Correction — 2026-07-17:** `sdp-loop-metrics-report` (skill — both Level 1 and Level 2 —
  > and its `sdp-shared/scripts/sdp-loop-metrics-report.ps1` script) renamed to
  > `sdp-report-log-loop-metrics` (script: `sdp-shared/scripts/sdp-report-log-loop-metrics.ps1`).
  > Naming only — no behavior change. Every struck-through `sdp-loop-metrics-report` mention in
  > the paragraph and blockquotes above refers to this skill under its new name.

  > **Correction — 2026-07-24:** The Addition above still named `sdp-reviewer` — renamed to
  > `sdp-project-reviewer` as part of the `sdp-project-*` scope-prefix rename (see
  > `project-scope-skill-naming-design.md`).

  > **Correction — 2026-07-24:** The Addition above also still named `sdp-worker` — renamed to
  > `sdp-project-worker` as part of the same `sdp-project-*` scope-prefix rename (see
  > `project-scope-skill-naming-design.md`).

  > **Correction — 2026-07-24:** The Addition above also still named `sdp-coordinator` — renamed
  > to `sdp-project-coordinator` as the last skill in the same `sdp-project-*` scope-prefix
  > rename (see `project-scope-skill-naming-design.md`).

**Outcome detection:** Same as agent-orchestrated — ~~`sdp-state-loop`~~ `sdp-project-state-loop` reads `[phase]_state.json`
after each subagent returns. Do not parse subagent text output for the outcome.

**Restarting after a STOP:** If ~~`sdp-state-loop`~~ `sdp-project-state-loop` stops (blocking condition or user ran
`/sdp-cancel-auto`), resolve the condition then run `/sdp-auto` to restart the loop.

> **Correction — 2026-07-24:** The "Outcome detection" and "Restarting after a STOP" paragraphs
> above both still named `sdp-state-loop` — renamed to `sdp-project-state-loop` as part of the
> `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).

---

### Halt Behavior Contract

A halt occurs when a skill encounters a blocking condition it cannot resolve — missing required
file, GPG version mismatch, state inconsistency requiring user decision. Halt is a named state
transition, not an unstructured stop.

**Valid `workflow_status` values:**

| Value | Meaning |
|-------|---------|
| `"active"` | Normal operation — COORDINATOR may dispatch |
| `"halted"` | Blocking condition exists — COORDINATOR must not dispatch until cleared |

#### How to halt (skill instruction)

When a blocking condition is detected:

1. Write to `state.json`: set `workflow_status` to `"halted"`, add `"halt_reason": "[one-line
   description of the blocking condition]"`, and set `"updated"` to the current ISO date.
2. ~~Print a user-facing message: "⛔ Halted — [reason]. Resolve this condition and run
   COORDINATOR to resume."~~ [2026-07-17: superseded — see Correction below]
3. Terminate. Do not proceed to any subsequent step.

> **Correction — 2026-07-17:** Step 2's raw-text form above predates this session's
> framework-wide `sdp-create-banner` adoption pass (see `SDP-Changelog.md`). The halt message is
> now delivered by invoking `/sdp-create-banner icon=error row=0 row: Status | Halted — [reason].
> Resolve this condition and run COORDINATOR to resume.` — the wording is unchanged, only the
> delivery mechanism. This is the "Halt Behavior Contract" text referenced throughout this
> document and mirrored across ~~`sdp-coordinator`~~ `sdp-project-coordinator`, ~~`sdp-worker`~~ `sdp-project-worker`, ~~`sdp-reviewer`~~ `sdp-project-reviewer`, ~~`sdp-state-loop`~~ `sdp-project-state-loop`,
> and other skills' Level 2 procedures — all were converted in the same pass (23 skills total;
> see `~SDP-Maintenance/~docs/sdp-create-banner-adoption-tracker.md` for the full list).
>
> **Correction — 2026-07-24:** This 2026-07-17 correction's own text still named `sdp-reviewer` —
> renamed to `sdp-project-reviewer` as part of the `sdp-project-*` scope-prefix rename (see
> `project-scope-skill-naming-design.md`).
>
> **Correction — 2026-07-24:** This 2026-07-17 correction's own text also still named
> `sdp-worker` — renamed to `sdp-project-worker` as part of the same `sdp-project-*`
> scope-prefix rename (see `project-scope-skill-naming-design.md`).
>
> **Correction — 2026-07-24:** This 2026-07-17 correction's own text also still named
> `sdp-state-loop` — renamed to `sdp-project-state-loop` as part of the same `sdp-project-*`
> scope-prefix rename (see `project-scope-skill-naming-design.md`).
>
> **Correction — 2026-07-24:** This 2026-07-17 correction's own text also still named
> `sdp-coordinator` — renamed to `sdp-project-coordinator` as the last skill in the same
> `sdp-project-*` scope-prefix rename (see `project-scope-skill-naming-design.md`).

#### How callers detect halt

**Human-gated:** The user sees the printed halt message and reads `state.json` to confirm the
reason. No automated detection required.

**Agent-orchestrated:** COORDINATOR reads `workflow_status` from `state.json` at the start of
every session (step 1a in the Implementation Loop). If `"halted"`, COORDINATOR notifies the user
of the halt reason and does not dispatch. It does not attempt to resolve the condition — resolution
is a human action.

#### How to clear a halt

1. User resolves the blocking condition (e.g., copies missing file, corrects version mismatch).
2. User triggers a new COORDINATOR session.
3. COORDINATOR confirms the condition is resolved, sets `workflow_status` back to `"active"`,
   clears `halt_reason`, and resumes normal dispatch.

COORDINATOR is the only role that may clear a halt. WORKER and REVIEWER sessions that detect a
blocking condition halt and terminate — they do not attempt to clear prior halts.

---

### Material Decision Escalation

> **Addition — 2026-07-23:** Added after a consuming project's Architecture and Implementation
> Overview phases ran fully autonomously, as designed, and picked a cloud hosting provider with
> zero user contact — a spec-compliant use of the Gap Resolution Criteria's "declared out of scope
> with a written rationale" closure path (see Pros-Cons-Gaps Cycle section). A related incident:
> an SDP run stopped mid-build needing an external API's credentials, discovered only when a
> downstream WORKER hit the wall directly.

**Config:** `SDP-Config.json` carries `materialDecisionEscalation.enabled`, defaulting to `true`
at workspace scaffold time (see `SDP-Workspace-Setup.md`'s `SDP-Config.json` Template). No skill,
in any role, may write this field — the same loop-owned-field discipline that already governs
`eval_cycle_attempts`. Changing it requires a human editing `SDP-Config.json` directly, outside
any dispatched session.

**Scope:** applies to `AGENT` — any dispatched session, in any role (COORDINATOR, WORKER,
REVIEWER, GATE_REVIEWER, or their solution-scoped equivalents), project- or solution-scoped — at
any phase, including phases outside the Pros-Cons-Gaps cycle and sessions dispatched after Phase
7. This is deliberately wider than "an agent selects something": it also covers a REVIEWER Eval
note recommending an alternative library, or a COORDINATOR dispatch-file aside mentioning a tool —
a mere suggestion is in scope, not only an actual commit to one.

**The materiality test.** When `materialDecisionEscalation.enabled` is `true`, either trigger below
requires escalation before the agent proceeds. Neither trigger is a judgment call — both are
mechanically checkable against `.speq` and the existing GPG Reference convention:

1. **External-dependency trigger.** AGENT is about to suggest, select, or introduce a language,
   runtime, framework, library/package (any source or registry), IDE/tool/plugin, database or
   data-platform engine, cloud/hosting provider, third-party API/service, or anything similar —
   and it is not already explicitly named in `.speq`. This covers a third-party service requiring
   an account or credentials: it is caught the moment it is first considered, not discovered
   mid-implementation with no runway to recover.
2. **GPG-silence trigger.** AGENT is about to suggest or select an architectural pattern or
   approach that is not a "dependency" but whose Gap Resolution's own GPG Reference line would be
   "none" — GPG carries no precedent for it.

**Exemption:** anything already explicitly declared in `.speq` (project-scoped, available from
Phase 7 onward) — or, for solution-scoped phases 1-6 where no `.speq` yet exists, already
explicitly settled in `01_concept.md`, `03_expanded_concept.md`, or a prior resolved Material
Decision Escalation record for this solution — is pre-approved and proceeds normally. This is why
Phase 1/3's brainstorming capture, and the routine parts of Phase 4/5's Pros-Cons-Gaps cycle, do
not trigger on every ordinary decision — only on ones not already settled.

**On trigger:** the agent does not choose. It halts per the Halt Behavior Contract above
(`workflow_status: "halted"`) — this is what makes it interrupt ~~`sdp-state-loop`~~ `sdp-project-state-loop` automatically, no
new state machine required. `halt_reason` names the decision under consideration; the agent
appends a 2–4 option table in the same shape as the Gap Resolution Format / Phase 7 Remediation
Proposals (option, trade-offs, no forced pick). For a credentials/account case, the halt explicitly
asks the user to supply or confirm how to obtain them — key-name references only, never literal
secret values, mirroring the existing ⚡ Deploy annotation convention. COORDINATOR surfaces the
halt to the user as normal. The resolution is appended to `.speq` (dependency decisions) or the
relevant phase document's Gap Resolution block (pattern decisions) — no new log file; this reuses
the existing append-only homes for the permanent record.

> **Correction — 2026-07-24:** The "On trigger" paragraph above still named `sdp-state-loop` —
> renamed to `sdp-project-state-loop` as part of the `sdp-project-*` scope-prefix rename (see
> `project-scope-skill-naming-design.md`).

**Gap Resolution Criteria cross-reference:** a gap that trips either trigger above cannot be closed
via the Deferred or declared-out-of-scope paths in the Pros-Cons-Gaps Cycle section alone — it must
go through this escalation and reach either explicit user approval or an explicitly user-approved
deferral before the gap is considered resolved.

---

## Setup Checklist

> Full setup procedure is in `SDP-Workspace-Setup.md`.
> Load that file when setting up a new workspace — it covers the complete two-level procedure:
> solution root setup first, then per-project setup.

**Solution root setup** (once per solution):
- [ ] `SDP-Solution.json` created at solution root (solution name, empty `projects` array)
- [ ] `.sdp-solution-workflow/` created with `state.json` stub and `sessions/` subfolder
- [ ] `sdp-solution-docs/` created with `00_solution_prompt.txt` and `00_user_notes.txt` stubs
- [ ] `sol-shared/` placeholder created at solution root
- [ ] `.claude/rules/sdp-core-invariants.md` present (ships as a real file — no action needed)
- [ ] `.claude/rules/sdp-agent-conduct.md` present, or explicitly skipped with the dedup-check
      rationale logged in the setup plan

**Per-project setup** (repeat for each project added to the solution):
- [ ] `sdp-project_[name]/` folder created and registered in `SDP-Solution.json` `projects` array
- [ ] `.sdp-workflow/` and `sdp-docs/` folder structure created inside `sdp-project_[name]/`
- [ ] `shared/` placeholder created inside `sdp-project_[name]/`
- [ ] Project Context Document created and added to the project's `SDP-Document-List.json`
- [ ] `.speq` contract created and added to the project's `SDP-Document-List.json`
- [ ] `SDP-Document-List.json` ordering verified (`sdp-docs/00_prompt.txt` is last `includeInReadDocs: true` entry)

**Key gates before first WORKER dispatch:**
- [ ] Session Start hook verified in `.claude/settings.local.json`
- [ ] Superpowers plugin installed and verified (`/plugin list`)
- [ ] All sdp- skills present at both Level 1 (`.claude/skills/`) and Level 2 (`sdp-shared/ai-skills/`)
      — canonical inventory is in `SDP-Workspace-Setup.json`; validated by preflight.
        Includes project skills (~~sdp-coordinator~~ sdp-project-coordinator, ~~sdp-worker~~ sdp-project-worker, ~~sdp-reviewer~~ sdp-project-reviewer, etc.),
        solution skills (sdp-solution-coordinator, sdp-solution-worker, sdp-solution-reviewer, etc.),
        and sdp-standards-setup. Run preflight to verify rather than checking this list manually.

        > **Correction — 2026-07-24:** This bullet still named `sdp-reviewer` — renamed to
        > `sdp-project-reviewer` as part of the `sdp-project-*` scope-prefix rename (see
        > `project-scope-skill-naming-design.md`).

        > **Correction — 2026-07-24:** This bullet also still named `sdp-worker` — renamed to
        > `sdp-project-worker` as part of the same `sdp-project-*` scope-prefix rename (see
        > `project-scope-skill-naming-design.md`).

        > **Correction — 2026-07-24:** This bullet also still named `sdp-coordinator` — renamed
        > to `sdp-project-coordinator` as the last skill in the same `sdp-project-*` scope-prefix
        > rename (see `project-scope-skill-naming-design.md`).
- [ ] GPG files present; `gpg_version` recorded in `state.json`
- [ ] `SDP-Config.json` created at solution root
- [ ] `git` available on PATH — validated by preflight (`command-available` check)
- [ ] `python` available on PATH — documentation-only prerequisite, not validated by preflight

> **Addition — 2026-07-27:** Cross-platform testing (a fresh, non-Windows-adjacent machine)
> surfaced `git` and `python` as prerequisites not previously declared anywhere in SDP's setup
> gates. `git` is a real, load-bearing dependency (the Superpowers plugin and
> `sdp-shared/scripts/sdp-github.ps1` both require it) and is now preflight-validated. `python`
> is not used by any SDP script or skill — it is listed defensively because an agent was observed
> reaching for it during banner rendering despite that procedure's explicit no-tool-call rule; see
> `SDP-Workspace-Setup.md` Tooling Prerequisites for the full rationale on both.

---

## Project Context Document

Project-specific decisions belong in a **Project Context Document** at the workspace root —
not in agent memory files. Agent memory is for global or cross-project knowledge. Project
documents are the authoritative source for project state.

### When to Create

~~Create `[PROJECT]-Context.md` when product shape and key architectural decisions are settled —
typically during early Phase 1 planning, before the first WORKER session is dispatched.~~ [see
2026-07-26 Correction below] Add it
to `SDP-Document-List.json` so ~~`sdp-read-docs`~~ `sdp-project-read-docs` loads it automatically at every
session start.

> **Correction — 2026-07-23:** This sentence still named `sdp-read-docs` — renamed to
> `sdp-project-read-docs` as part of the `sdp-project-*` scope-prefix rename (see
> `project-scope-skill-naming-design.md`).

> **Correction — 2026-07-26:** "Early Phase 1 planning" is the same stale single-project-era
> trigger corrected in the `.speq` Contract section above — a project has no Phase 1 of its own
> under the solution-scoped model. An empty stub is created at Add-Project time
> (`sdp-workspace-setup`); it is populated with real, settled product-shape/architecture content
> at Phase 7 decomposition (`sdp-solution-phase-coordinator` Step 2b item 0), from
> `04_architecture.md`/`05_implementation_overview.md` — still before the project's first WORKER
> session. See the `.speq` Contract section's matching correction and
> `SDP-Workspace-Setup.md`'s Add-Project Steps.

### What to Include

- **Project identity** — what the project is and who it serves
- **Product shape decisions** — settled architecture (phases, data flow, deployment model)
- **Technology stack** — chosen languages/frameworks and rationale
- **Agent/script split** — which tasks are script-deterministic, which require agent reasoning
- **GPG chapter inclusions/exclusions** — which chapters apply, which are excluded, which are conditional
- **Domain input inventory** — what each research or reference file contains and its role

### What to Exclude

- SDP workflow state → `.sdp-workflow/state.json` (machine-maintained)
- Session history → `.sdp-workflow/sessions/` (append-only log)
- Task-level decisions → phase documents in `sdp-docs/` (where they belong)
- This bootstrap procedure → `SDP_Sapient-Driven-Principles_vX.X.X.md` (not project-specific)

### Placement Rule

> **Agent instruction:** When a project-specific decision or context item is identified as
> valuable for future agent sessions, propose adding it to the Project Context Document —
> not to agent memory. If the Project Context Document does not yet exist, propose creating
> it before writing any agent memory for this project.

---

## `.speq` Contract

A single file at the workspace root that declares the binding technical decisions for all
agent sessions: tech stack and versions, naming conventions, file structure and import
boundaries, key entity shapes, and settled decisions that are not open for re-proposal.

**Purpose:** Agents stop re-deriving conventions from context or asking repeatedly. Every
naming and stack decision is declared once and referenced from every session.

**When to create:** ~~By the end of Phase 1, before any WORKER session is dispatched.
Tech stack and naming must be declared before implementation begins — an agent that infers
these from surrounding code will drift across sessions.~~

> **Correction — 2026-07-26:** "By the end of Phase 1" named a project's own Phase 1, which
> doesn't exist under the solution-scoped model — phases 1-7 run once per solution, and a
> project has no phase pipeline of its own until Phase 7's decomposition assigns it tasks.
> Confirmed via a real halt: a project's first-ever post-Phase-7 WORKER dispatch found no
> `.speq.md` at all, because no step in the solution-scoped pipeline created or populated one.
> An empty template stub is now created at Add-Project time (`sdp-workspace-setup`'s Add-Project
> Steps — costs nothing, keeps `SDP-Document-List.json` ordering correct from day one); it is
> populated with the actual settled tech stack, naming, and structure decisions at Phase 7
> decomposition (`sdp-solution-phase-coordinator` Step 2b item 0), from the already-settled
> content in `04_architecture.md`/`05_implementation_overview.md` — still strictly before that
> project's first WORKER session, just anchored to the trigger point that actually exists in the
> current pipeline instead of a phase number projects no longer have. See
> `SDP-Workspace-Setup.md`'s Add-Project Steps for the full split procedure.

Tech stack and naming must be declared before implementation begins — an agent that infers
these from surrounding code will drift across sessions.

**Amendment rule:** Append-only using strikethrough. Apply `~~strikethrough~~` to the
superseded row or section in place; add the replacement immediately below with a date and
reason. Existing declarations are never deleted — they are the record that a decision was
made and later revised.

**What belongs here vs. Project Context Document:**
- `.speq` — how it's built: stack, naming, structure, data shape, settled decisions
- Project Context Document — what it is: product identity, domain context, architectural
  shape, GPG chapter inclusions/exclusions

### `.speq` File Template

> Template is in `SDP-Workspace-Setup.md` — see the `.speq` Contract Template
> section. Create the file from that template; the contract description and amendment rules
> above govern every session that reads it.

---

## Patterns Library

Distilled reusable patterns promoted from project `PATTERNS.md` files. Each entry was validated
in at least one real project before promotion. Append-only — new entries are proposed by an agent
reviewing a completed project's `PATTERNS.md` and approved by the user before being added here.

> **Agent — new project setup:** ~~Read this section before beginning Phase 1 architecture
> work.~~ [2026-07-18: fixed — this already contradicted the Document Lifecycle table before
> this version's renumbering (architecture was Phase 3, not Phase 1); now Phase 4.] Read this
> section before beginning Phase 4 architecture work.
> For each pattern relevant to the current project, note the pattern ID in `state.json` under
> `adopted_patterns` and apply it rather than rediscovering it.

---

*No patterns promoted yet. This section grows as projects complete.*

<!-- First promotion will follow the format below:

## PATTERN-NNN: [Pattern Title]
**Validated in:** [Project name(s)]
**Context:** [What problem this pattern solves]
**Decision:** [The reusable approach — no project-specific names or values]
**Tags:** [domain tags]
**Full reference:** [link to originating project's PATTERNS.md entry, if accessible]

-->

---

## GPG Reading Map

This map tells COORDINATOR which GPG chapters to include in each session dispatch file.
WORKER reads the listed chapters before forming an implementation approach (session Step 3).
REVIEWER reads the same chapters for the task under review during the GPG alignment check
(session Step 4). All chapter files are in `standards/GenericProjectGuidlines_Sections/`.

### Always-Read by Phase

| Workflow Stage | Chapters — Always Read |
|----------------|------------------------|
| Phase 4 — Architecture | Ch. 1 Solution Structure, Ch. 3 Folder/File Organization, Ch. 4 Versioning Strategy, Ch. 13 Coding Standards |
| Phase 5 — Implementation Overview | Ch. 1 Solution Structure, Ch. 13 Coding Standards, Ch. 15 Error Handling, Ch. 16 Source Control & Commit Rules |
| Phase 6 — Refined Plan (all WORKER tasks) | Ch. 13 Coding Standards, Ch. 15 Error Handling, Ch. 16 Source Control & Commit Rules |

### Conditional — Read When Task Content Matches

| Chapter | Read When Task Involves |
|---------|-------------------------|
| Ch. 2 — Project Roles & Responsibilities | Defining team responsibilities, role assignments, or ownership boundaries |
| Ch. 5 — Authentication & Security | Auth flows, token handling, permissions, security middleware, secrets at runtime |
| Ch. 6 — Logging | Adding or modifying logging, structured log output, log levels, correlation IDs |
| Ch. 7 — Database Architecture | Schema design, migrations, table structure, indexes, relationships |
| Ch. 8 — Data Access Patterns | Repository implementation, query patterns, ORM usage, unit-of-work |
| Ch. 9 — DTO & Contract Library | DTO classes, request/response contracts, shared contract library |
| Ch. 10 — API Design & Response Envelope | API endpoint design, response shaping, HTTP conventions, versioning |
| Ch. 11 — Website (Blazor) | Blazor components, pages, layouts, client-side patterns |
| Ch. 12 — Mobile Readiness | Mobile API concerns, offline support, push notifications, mobile-specific patterns |
| Ch. 14 — Configuration & Secrets | App settings, environment-specific config, secrets management, `appsettings.json` |
| Ch. 17 — Database Seed Data Patterns | Seed data scripts, initial data population, migration seeding |

### COORDINATOR Dispatch Instruction

When writing `session-NNN.md`, include a **GPG Reading List** block listing the applicable
chapters for the task being dispatched:

```markdown
**GPG Reading List:**
- Always: [list always-read chapters for this phase]
- Conditional: [list conditional chapters whose trigger matches this task's content]
- Files: `standards/GenericProjectGuidlines_Sections/GenericProjectGuidlines_[ChapterName].md`
```

WORKER reads always-read chapters before forming an approach. Conditional chapters are read
only when the task description matches the trigger column above.

**Project scope filter:** At workspace setup, note which conditional chapters are irrelevant
to this project type (e.g., Ch. 11 Blazor for an API-only project) and record them in
`state.json` under a `gpg_excluded_chapters` array. COORDINATOR omits excluded chapters from
all dispatch files for the life of the project.

---

*End of bootstrap document. Version 1.1.0 — 2026-07-18.*
