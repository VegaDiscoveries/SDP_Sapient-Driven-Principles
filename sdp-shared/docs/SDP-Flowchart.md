# SDP Flowchart — A New Project, Start to Finish

| Field | Value |
|-------|-------|
| **Companion doc** | `SDP_Sapient-Driven-Principles_vN.N.N.md` |
| **File** | `SDP-Flowchart.md` |

**Purpose:** A single, linear walk through what actually happens — in order, with the skill
invoked and the artifact produced at each step — from an empty folder to a running, unattended
implementation loop. `README.md` documents SDP's concepts; `SDP_Sapient-Driven-Principles_v*.md`
is the authoritative procedure; this doc exists to answer "what happens next?" at any point in
that journey without reconstructing the sequence from either. Not loaded automatically by
`sdp-project-read-docs` — add to `SDP-Document-List.json` with `"includeInReadDocs": false` if it should
be.

---

## 1. The Whole Journey, One Diagram

```
Empty folder
   │
   ▼
Copy in SDP base files (.claude/, sdp-shared/, standards/, bootstrap doc, SDP-Config.json)
   │
   ▼
Open Claude Code at the solution root
   │  SessionStart hook fires → sdp-initialize-sdp
   │  ("SDP-Solution.json not found" — asks what you want to do next)
   ▼
/sdp-workspace-setup
   │  Q1-Q6 interview → user confirms plan → scaffolds solution root + first project(s)
   ▼
┌───────────────────────────────────────────────────────────────────────┐
│  PHASES 1-7 — solution-scoped concept cycle                           │
│  driven by /sdp-solution-phase-coordinator, human-gated only          │
│  Concept → Research → Expanded Concept → Architecture →               │
│  Implementation Overview → Refined Plan → Phase Readiness             │
│  (each phase: draft → gate review → next phase)                       │
└───────────────────────────────────────────────────────────────────────┘
   │
   ▼
Phase 7 decomposition — remaining scope split into registry.md rows,
assigned into each involved project's own .sdp-workflow/registry.md
   │
   ▼
/sdp-solution-loop-prep  (first time only — sweeps every project's fresh
registry: doc review + source coverage + right-sizing, before any dispatch)
   │
   ▼
┌───────────────────────────────────────────────────────────────────────┐
│  IMPLEMENTATION LOOP — per project, repeats per work item             │
│  driven by /sdp-project-coordinator (or /sdp-solution-coordinator for a       │
│  task that spans more than one project)                               │
│  COORDINATOR → WORKER → COORDINATOR → REVIEWER → (repeat) → GATE      │
└───────────────────────────────────────────────────────────────────────┘
   │
   ▼
/sdp-auto  — starts sdp-project-state-loop; from here dispatch is fully unattended
   │
   ▼
Repeat: /sdp-new-concept-intake seeds a fresh Phases 1-7 mini-cycle
whenever new scope shows up, at any point in the project's life
```

Everything below expands one segment of this diagram at a time, in the order a new project
actually passes through them.

---

## 2. Stage: Bringing SDP Into a Solution

| Step | Action | Detail |
|------|--------|--------|
| 1 | Copy base SDP files into the target folder | `.claude/`, `sdp-shared/`, `standards/`, `SDP_Sapient-Driven-Principles_v*.md`, `SDP-Config.json` |
| 2 | Open Claude Code at that folder | This folder is now the **solution root** — it must contain `SDP-Solution.json` and `.claude/skills/` for any `/sdp-*` skill to be visible |
| 3 | Start a session | `SessionStart` hook fires `sdp-initialize-sdp` automatically — prints the opening banner, loads workspace context via `sdp-solution-read-docs`, detects `SDP-Solution.json` is missing, and stops to ask what to do next (it does not auto-start setup on a bare first message) |
| 4 | Run `/sdp-workspace-setup` | Full two-level procedure — solution root, then the first project(s) — driven entirely by `SDP-Workspace-Setup.md`'s Setup Checklist |

**The setup interview (Q1–Q6), asked one question at a time before any file is created:**

| # | Question | Produces |
|---|----------|----------|
| Q1 | Confirm/correct a solution name derived from the root folder name | `SDP-Solution.json` `solution_name` |
| Q2–Q3 | What does this solution do, who uses it, what outcome does it deliver | Synopsis → `README.md` |
| Q4 | What project types make up the solution (API, Domain/library, Web frontend, Database, …) | `sdp-project_*` folder list, PascalCase-dotted (`sdp-project_[AppName].[Type]`) |
| Q5 | Development environment alongside Claude Code | IDE workspace file — `.sln` (Visual Studio/Rider), `.code-workspace` (VS Code), or none (agent-only) |
| Q6 | Confirm the GPG standards version present in `standards/`, or name a different one | Recorded standards version used by preflight |

The agent then runs the conduct-rules check (no user question — agent judgment: compare
`~/.claude/CLAUDE.md` and project-level conduct rules against the SDP conduct-rules template) and
presents the **complete setup plan** — solution name, synopsis, project list, IDE file, GPG
version, conduct-rules outcome — for explicit confirmation before creating anything.

**What exists after this stage:** `SDP-Solution.json` (empty `projects` initially populated),
`.sdp-solution-workflow/state.json` at `current_phase: "concept"`, `sdp-solution-docs/` stubs, one
or more `sdp-project_*/` folders each with their own `.sdp-workflow/` + `sdp-docs/` scaffold — but
**no phase content yet**. This stage runs exactly once per solution.

---

## 3. Stage: Phases 1–7 — The Solution-Scoped Concept Cycle

Every phase below runs **once per solution** (not per project) — driven by
`/sdp-solution-phase-coordinator`, always human-gated (no cron/loop dispatch during this stage),
with deliverables at `sdp-solution-docs/*.md` and tracking in
`.sdp-solution-workflow/registry.md` / `state.json`. Project identity does not exist yet — it
first appears at Phase 7's decomposition step.

```
Phase 1: Concept                                     sdp-solution-docs/01_concept.md
   │  Source-doc intake check (see below) → COORDINATOR reads the tracked source doc (if one
   │  exists for this cycle), runs /brainstorming interactively with the user, captures
   │  decisions → WORKER formalizes the document → Gate: concept review
   ▼
Phase 2: Research                                     sdp-solution-docs/02_research_findings.md
   │  Internal WORKER fan-out — one child subagent per research angle
   │  → synthesized findings, every claim sourced → Gate: research review
   ▼
Phase 3: Expanded Concept                             sdp-solution-docs/03_expanded_concept.md
   │  COORDINATOR reads 01_concept.md + 02_research_findings.md + the tracked source doc (if
   │  one exists), runs /brainstorming interactively, captures decisions → WORKER formalizes,
   │  citing every research angle → Gate: expanded concept review
   ▼
Phase 4: Architecture                                 sdp-solution-docs/04_architecture.md
   │  Pros-Cons-Gaps cycle × 2-N iterations → Gate: architecture review
   ▼
Phase 5: Implementation Overview                      sdp-solution-docs/05_implementation_overview.md
   │  Pros-Cons-Gaps cycle × 2-N iterations → Gate: implementation overview review
   ▼
Phase 6: Refined Implementation Plan                  sdp-solution-docs/06_refined_plan.md
   │  Acceptance criteria written per work item → Gate: plan review
   ▼
Phase 7: Phase Readiness                               sdp-solution-docs/07_phase_readiness.md
   │  A. Build-phase decomposition → each project's own .sdp-workflow/registry.md
   │  B. Full-lifecycle traceability audit (source doc → every phase → final plan/registry)
   │  → Gate: readiness review
   ▼
Work items exist in project registries → Implementation Loop begins (Section 5 below)
```

**Phase 1 — source-doc intake, checked first:**

| Situation | Path |
|-----------|------|
| `sdp-solution-docs/user-design-docs/processed/` already has files | Intake already happened — draft `01_concept.md` from the tracked source directly |
| Nothing there yet, user has existing docs/notes | Drop them in `sdp-solution-docs/user-design-docs/`, run `/sdp-new-concept-intake` before drafting |
| Nothing there yet, no docs but wants one developed | Run `/brainstorming`, save the result into `sdp-solution-docs/user-design-docs/`, then `/sdp-new-concept-intake` |
| Nothing there yet, wants to seed directly from conversation | Proceed conversationally — no source doc, no `sdp-source-coverage-check` for this cycle |

When a tracked source doc exists, `sdp-source-coverage-check` runs immediately after Phase 1 and
Phase 3 are drafted, comparing the source against `01_concept.md` / `03_expanded_concept.md` for
coverage — mandatory, not optional.

**Phase 1 and Phase 3 are the only interactive drafting steps in the whole cycle.** For these two
phases only, `/brainstorming` is COORDINATOR-scoped, not WORKER-scoped: COORDINATOR runs it
interactively with the user, transcribes every decision into the phase document, then dispatches
WORKER to finish and formalize the document from that captured material. Every other phase (2,
4, 5, 6, 7) dispatches WORKER non-interactively, same as an ordinary implementation task.

**Gate reviews** are always a separate GATE_REVIEWER session (`/sdp-solution-phase-gate-review`)
— same context-isolation rule as work-item review. `GATE_BLOCKED` keeps the current phase open for
another iteration; `GATE_PASSED` advances `current_phase` to the next dependency-eligible phase.

**Phase 7's traceability audit can send the cycle backward** — the one deliberate backward
transition in the whole lifecycle. If it finds a gap, GATE_REVIEWER appends a `GATE_BLOCKED`
verdict naming the earliest phase the gap originates from, with up to three remediation proposals
(each naming an exact `Target Phase:`). This always halts for a human decision — the coordinator
never picks a proposal itself. Once chosen, that phase (and every phase between it and Phase 7)
gets a genuinely fresh WORKER → REVIEWER → gate cycle before Phase Readiness re-attempts its own
gate.

---

## 4. Stage: Phase 7 Decomposition → Per-Project Registries

This is the hinge point of the whole flow — the moment "the solution" becomes "N projects each
with their own work queue."

1. Phase 7 (Responsibility A) decomposes all remaining scope into right-sized, cohesive build
   phases — bias toward more, smaller phases a single WORKER dispatch sequence can reasonably
   finish, not fewer large ones.
2. Each decomposed phase becomes a row in the owning project's own `.sdp-workflow/registry.md`,
   with a `Depends On` column and a `gpg_chapters` array on its state file (empty array is valid —
   the gate checks the field is present, not populated).
2a. For any project receiving decomposed tasks for the first time, this same step also populates
   that project's `.speq.md` and `[PROJECT]-Context.md` — empty stubs since Add-Project time —
   with the real tech stack/naming/structure/product-shape decisions already settled in
   `04_architecture.md` / `05_implementation_overview.md`. The Phase 7 gate checks both files for
   real content, no template placeholders remaining.
3. `/sdp-solution-loop-prep` runs once, the first time Phase 7's gate passes for this solution —
   it walks **every** registered project's freshly-decomposed registry, in dependency order,
   running:
   - `sdp-project-doc-review` — content readiness
   - `sdp-source-coverage-check` — when a tracked source doc exists
   - `sdp-phase-rightsizing-check` — splits anything still oversized before dispatch ever sees it
4. Only after that sweep reports clean does dispatch begin. `/sdp-project-loop-prep` is the same sweep
   scoped to a single project, for a targeted re-check outside this one-time transition.

---

## 5. Stage: The Implementation Loop (Per Task, Per Project)

This is the steady-state cycle a project spends most of its life in — repeats once per work item,
for every project, for as long as the project has open registry rows.

```
COORDINATOR session (new subagent)
   │  Preflight check → read state.json + phase state files → find next actionable task
   │  (REJECTED tasks take priority; respects Depends On)
   │  writes session-NNN.md + sdp-docs/00_prompt.txt for WORKER
   ▼
WORKER session (new subagent, isolated context)
   │  GPG check → read bootstrap + dispatch file + task + .speq contract
   │  Pre-Work Verification (scan for prior artifacts before starting)
   │  TDD + four-phase debugging discipline (Superpowers, if installed)
   │  implement → mark task [x] → append Completed blockquote
   │  state → WORK_COMPLETE
   ▼
COORDINATOR session (new subagent)
   │  reads WORK_COMPLETE from state file (never from WORKER's returned text)
   │  writes session-NNN.md + sdp-docs/00_prompt.txt for REVIEWER
   ▼
REVIEWER session (new subagent, isolated context, no shared history with WORKER)
   │  forms its own understanding of acceptance criteria BEFORE reading the Completed blockquote
   │  independently verifies — runs build/tests, checks GPG + .speq alignment
   │  appends Eval N blockquote → compliant / partially compliant / non-compliant
   ▼
   ├─ compliant / partially compliant → Verified N blockquote → state → VERIFIED
   │      └─ all tasks in phase VERIFIED → GATE_REVIEWER (Phase Gate Procedure) → next phase
   │
   └─ non-compliant → no Verified N written → state → REJECTED
          └─ COORDINATOR resets to PENDING, resets eval_cycle_attempts,
             REJECTED task takes dispatch priority next cycle
```

**Context isolation is the load-bearing rule here:** COORDINATOR never touches implementation
files; WORKER never evaluates its own output; REVIEWER forms its acceptance-criteria understanding
independently before reading what WORKER claimed. Each role is a **new subagent invocation** —
`/clear` inside an existing context does not satisfy this.

**Cross-project work items** use the same WORKER → REVIEWER shape, but dispatched by
`/sdp-solution-coordinator` instead of `/sdp-project-coordinator` — every involved project is kept in
lockstep (the cycle sync invariant: laggard projects are dispatched each cycle, none gets more
than one step ahead of its siblings), and any rejection freezes the whole cross-project task for a
human-reviewed cascade before anything resumes.

---

## 6. Stage: Choosing How Dispatch Happens

Three orchestration modes, one per solution/project via `orchestration_mode` in `state.json`.
Start at the top of this table; move down as the workflow proves stable.

| Mode | Who spawns the next subagent | Best for |
|------|------------------------------|----------|
| **Human-gated** | COORDINATOR prints instructions; user starts each subagent manually | Early projects, high ambiguity |
| **Agent-orchestrated** | COORDINATOR spawns subagents directly via the Agent tool, reads outcome from state file after return | Well-defined task sequences |
| **Loop-orchestrated** | `/sdp-auto` starts a recurring `sdp-project-state-loop`; it evaluates `sdp-docs/00_prompt.txt`, dispatches, reads state, repeats | Sustained unattended runs |

`/sdp-auto` **refuses to start until solution-level Phase 7's gate has passed** — phases 1–7 are
always human-gated dispatch, with no cron job involved at any point during that stage. Once
started, the loop handles WORKER/REVIEWER/GATE_REVIEWER dispatch, stuck-loop detection
(`eval_cycle_attempts` vs `eval_cycles`), and automatic halting on any blocking condition. Stop it
with `/sdp-cancel-auto`; resume with `/sdp-auto` after resolving whatever caused the stop.

---

## 7. Stage: Ongoing Life of the Project

A project rarely ends after one pass through Sections 3–6. Two things recur for as long as the
solution is active:

**New scope appears mid-project.** Run `/sdp-new-concept-intake` at any solution maturity —
document-driven (drop files in `sdp-solution-docs/user-design-docs/`) or conversational (describe
it directly). Either way it seeds a fresh seven-row Phases 1–7 mini-cycle into the solution's own
registry and hands off to `/sdp-solution-phase-coordinator` — never to `/sdp-solution-coordinator`
(shared cross-project task dispatch only) or project-level `/sdp-project-coordinator`. Starting this cycle
cancels any currently-running `sdp-project-state-loop`; run `/sdp-solution-loop-prep` again once this
cycle's own Phase 7 gate re-passes, before restarting `/sdp-auto`.

**Something halts.** `workflow_status: "halted"` stops all dispatch until a human resolves the
blocking condition and starts a new COORDINATOR session — COORDINATOR never attempts to resolve
the condition itself. Common causes:

| Cause | What it means | Who resolves it |
|-------|----------------|------------------|
| `DIAGNOSIS_BLOCKED` | WORKER's one-cycle debugging budget was exhausted without a fix | User reviews the Diagnosis Blocked notes, gives direction |
| `GATE_BLOCKED` | A gate review found issues (or, at Phase 7, a traceability gap) | Issues addressed within the current phase; new gate cycle. A Phase 7 gap requires picking a remediation proposal |
| Stuck-loop threshold | `eval_cycle_attempts - eval_cycles` reached the configured threshold with no progress | Loop auto-classifies cause (unpushed commits / uncommitted changes / unknown) and either auto-resolves or halts for the user |
| `SOL_CASCADE_REVIEW_NEEDED` | A cross-project task's child was rejected, possibly invalidating sibling work already done | Human confirms cascade scope before any project resumes |
| Material Decision Escalation | Any dispatched session (any role, any phase) is about to introduce an external dependency not named in `.speq`, or a pattern with no GPG precedent | User picks from the 2-4 option table the agent appends; resolution recorded in `.speq` or the phase document's Gap Resolution block |

---

## 8. Quick Reference — Trigger → Skill → Artifact

| You want to... | Run | Produces / Updates |
|-----------------|-----|---------------------|
| Bring SDP into a new or existing solution | `/sdp-workspace-setup` | `SDP-Solution.json`, solution + first project scaffold |
| Drive the Phases 1–7 concept cycle | `/sdp-solution-phase-coordinator` | `sdp-solution-docs/0N_*.md`, `.sdp-solution-workflow/registry.md` |
| Register a new concept mid-solution | `/sdp-new-concept-intake` | Seven new registry rows + phase stubs |
| Certify every project's registry before an unattended run | `/sdp-solution-loop-prep` (first time) / `/sdp-project-loop-prep` (targeted) | Doc review + source coverage + right-sizing pass |
| Drive one project's implementation loop | `/sdp-project-coordinator` | `session-NNN.md`, `sdp-docs/00_prompt.txt`, `[phase]_state.json` |
| Drive a task spanning 2+ projects | `/sdp-solution-coordinator` | Child tasks fanned out per project, cycle-synced |
| Regenerate the next dispatch prompt on demand | `/sdp-project-create-prompt` (project) / `/sdp-solution-create-prompt` (solution) | `sdp-docs/00_prompt.txt` / `sdp-solution-docs/00_solution_prompt.txt` |
| Execute whatever the current prompt says | `/sdp-project-run-prompt` (project) / `/sdp-solution-run-prompt` (solution) | Invokes the indicated skill automatically |
| Start fully unattended dispatch | `/sdp-auto` | Recurring `sdp-project-state-loop` |
| Stop the loop | `/sdp-cancel-auto` | Loop stopped |
| Generate a metrics report from logs | `/sdp-report-log-loop-metrics`, `-hook-metrics`, `-workflow-metrics`, `-combined-metrics` | `sdp-solution-docs/log-reports/*/log-report-*.md` |

---

## 9. Where to Read More

| Question | Doc |
|----------|-----|
| Why does SDP work this way — the four founding principles | `SDP_Sapient-Driven-Principles_v*.md` — Workflow Philosophy |
| Exact folder layout and file templates | `SDP-Workspace-Setup.md` |
| Full skill catalog, tier assignments, two-level architecture | `README.md` |
| Condensed setup + pre-dispatch checklist | `QuickStart.md` |
| Writing a new skill (L1/L2 pair) | `SDP-Skill-Authoring.md` |
| Writing a new script (script/hybrid tier) | `SDP-Script-Authoring.md` |
| Replacing the built-in GPG standards doc | `SDP-Standards-Setup.md` |
| Audible tone/tune events | `SDP-Tone-Notifications.md` |
| Bootstrap document version history | `SDP-Changelog.md` |
| Cross-project pattern tracking | `SDP-Project-Evolution.md` |
