# AI-Assisted Development Workflow — Skill Authoring Reference

| Field | Value |
|-------|-------|
| **Companion doc** | `SDP_Sapient-Driven-Principles_vN.N.N.md` |
| **Updated** | 2026-06-16 |
| **File** | `SDP-Skill-Authoring.md` |

**Purpose:** Templates and worked example for authoring new sdp- skills. Load this file
explicitly when creating or editing skill files. Not loaded automatically by `sdp-project-read-docs`
— add to `SDP-Document-List.json` with `"includeInReadDocs": false`.

---

## Two-Level Skill Structure

All sdp- skills follow a two-level structure. When authoring a new skill, use the templates
below — do not invent a different structure.

**Level 1** — `.claude/skills/[skill-name]/SKILL.md`
Claude Code loads this file into the session context automatically. Contains only the
meta-instruction layer: tone script calls at start and end, completion discipline enforcement,
the Level 2 read step with error handling, and a step that executes the Level 2 procedure.
Structure is identical across all skills — only the `name`, `description`, skill name in the
tone script calls, and the Level 2 file path change.

> **Note — no task-tracking tools.** Earlier versions wired `TaskCreate`/`TaskUpdate` into the
> Level 1 shim. Those tools are not available in subagent contexts (where most role shims run),
> so the wiring was removed. Completion discipline is enforced by the preamble and the execution
> step alone — do not reintroduce `ToolSearch select:TaskCreate,TaskUpdate` or Task* calls.

**Level 2** — `sdp-shared/ai-skills/[skill-name]/SKILL.md`
Read by the agent at invocation time via the Read tool. Contains the full procedure. `sdp-shared/`
is a solution-level directory — its contents are common to all projects in the solution, not
scoped to any single project. Must be completely generic — no project-specific paths, filenames,
or hardcoded values. Any parameters the procedure needs are passed via the session dispatch
file written by COORDINATOR.

### Exception: Level-1-only, fully-scriptable skills

A skill with **no judgment left in it at all** — every step is a direct script/tool
invocation with no LLM reasoning between them — skips Level 2 entirely. The Level 1 file states
explicitly that it is fully scriptable and contains the entire procedure itself (see `sdp-tone`,
`sdp-claude-new-terminal`, and `sdp-create-banner` for the three current examples). This is a
deliberate exception, not an oversight: creating a Level 2 file that just repeats the Level 1
steps verbatim would be a second file to keep in sync for zero benefit. `sdp-preflight.ps1`
enforces this as an invariant for `sdp-tone` specifically (Level 1 present, Level 2 **absent** —
a Level 2 file appearing for `sdp-tone` is itself a check failure, since it was deliberately
converted from a two-level skill to a script-only one); apply the same reasoning before adding a
Level 2 file to any other fully-scriptable skill.

---

## Convention: Chat-Facing Halt/Warning/Verdict Messages

When a skill's procedure needs to present a halt, error, warning, gate verdict, or major
state-transition confirmation to the user in chat, invoke `/sdp-create-banner` rather than
printing raw `⛔`/`⚠️`/`✅`-prefixed text directly. See `.claude/skills/sdp-create-banner/SKILL.md`
for the invocation grammar (`icon=`/`row=`/`row:`) and the icon registry pointer.

**When to reach for it:** messages that are infrequent, high-signal, and benefit from being
visually distinct from routine narration — a halt condition, a precondition failure, a gate
verdict, or a confirmation that a major state transition just occurred (a loop started, a phase
completed, a solution task reached a terminal verdict).

**When not to:** routine messages that fire on every (or nearly every) invocation of the skill —
e.g. a one-sentence "docs loaded" confirmation, a "next step identified" dispatch announcement.
Wrapping those in a banner adds visual noise and per-invocation script-call cost with no
corresponding benefit; they read fine as plain prose. Also skip it for content that's already
structured for its own medium — a markdown table, a JSON envelope meant for the next tool call,
or a blockquote written into an append-only document rather than chat — and for interactive
questions: a banner can only ever be the visual framing immediately before a separate
`AskUserQuestion` call or plain-text prompt, never a replacement for the question itself.

This convention was established by a framework-wide adoption pass (2026-07-17) that surveyed all
~31 skills against these criteria and converted 23 of them — see `SDP-Changelog.md` for the
summary and `~SDP-Maintenance/~docs/sdp-create-banner-adoption-tracker.md` for the full per-skill
record, including which skills were deliberately excluded and why. Apply the same criteria when
authoring a new skill's chat-facing messages, rather than defaulting to raw emoji-prefixed text.

---

## Level 1 Template

File: `.claude/skills/[skill-name]/SKILL.md`

````markdown
---
name: [skill-name]
description: [one-line description of what this skill does]
---

Do not report this skill complete unless every numbered step and all sub-steps within it have
been completed. Skipping a step and reporting completion is incorrect behavior — if any conduct
rules exist in this context, skipping a step is a conduct violation. Any time a step is
discovered to have been skipped, go back and complete the skipped step from the beginning. If
that completion attempt fails, raise the issue to the user before proceeding to any subsequent
step.

1. Run `.\sdp-shared\scripts\sdp-tone.ps1 -skillName "[skill-name]" -event "start"` via the PowerShell tool.
2. Use the Read tool to read `sdp-shared/ai-skills/[skill-name]/SKILL.md` from the project root —
   do this before anything else. If the Read fails, halt and report:
   "`sdp-shared/ai-skills/[skill-name]/SKILL.md` not found — skill cannot execute."
3. Execute every numbered step in that SKILL.md in order, completing all sub-steps of a step
   before moving to the next. Do not report this skill complete until every step and sub-step
   is done.
4. Run `.\sdp-shared\scripts\sdp-tone.ps1 -skillName "[skill-name]" -event "end"` via the PowerShell tool.
````

---

## Level 2 Template

> **Design-time classification:** Before writing any procedure step, apply the
> SCRIPT/LLM-ONLY/HYBRID-STEP classification from `sdp-evaluate-skill`. Steps that classify
> as fully SCRIPT should be written as PowerShell tool calls rather than LLM procedure steps
> — handle them in a script and follow `SDP-Script-Authoring.md`. Catching scripting
> candidates at design time is cheaper than retrofitting them after a skill is in use.

> **Constraint phrasing:** Phrase every `## Constraints` entry as a negative bounding rule —
> what must never happen — rather than a positive reminder of what to do. "Never ship a stub
> body" bounds the solution space; "remember to finish the implementation" is a reminder an
> agent can silently deprioritize under time or context pressure without ever technically
> violating it. SDP's own No Placeholders invariant (`sdp-core-invariants.md` #4) is written
> this way — use it as the model for every Constraints bullet in every skill.

> **No changelog/history content:** Neither template above has a Changelog or History section,
> and none should be added. A skill file states only the current, correct rule — it is read
> wholesale into an agent's live working context every time it runs, so a dated
> `Addition —`/`Correction —` block explaining a past bug sits directly upstream of the exact
> step it explains, which is confirmed to work against the rule it was meant to reinforce (see
> the bootstrap doc's Append-Only Discipline section for the incident). Git history is the audit
> trail for why a skill's rule changed. A worked example or a verbatim "do not reproduce this"
> example is fine to keep in a skill file — that's current, execution-relevant reference
> material, not history — the distinction is date-stamped incident narrative versus content an
> agent needs to execute the step correctly right now.

File: `sdp-shared/ai-skills/[skill-name]/SKILL.md`

````markdown
## Purpose

[One paragraph — what problem this skill solves and what it produces.]

## Inputs

[What the agent needs before this skill can run — phase file content, dispatch file fields,
state from a prior step. Omit this section if the skill has no prerequisites.]

## Procedure

### Step 1: [Step Title]

1. [Sub-step]
2. [Sub-step]

### Step 2: [Step Title]

[Continue for each step...]

## Constraints

- [Hard rules — ordering requirements, immutability rules, user confirmation requirements]

## Outputs

- [What this skill produces — files written, state updated, user-facing output]
````

---

## Worked Example: `sdp-project-pre-work-verify`

**Level 1** (`.claude/skills/sdp-project-pre-work-verify/SKILL.md`):

````markdown
---
name: sdp-project-pre-work-verify
description: Before starting any WORKER task, scan for prior artifacts, classify work state,
and act accordingly — preventing duplicate effort and ensuring clean resumption of interrupted
work.
---

Do not report this skill complete unless every numbered step and all sub-steps within it have
been completed. Skipping a step and reporting completion is incorrect behavior — if any conduct
rules exist in this context, skipping a step is a conduct violation. Any time a step is
discovered to have been skipped, go back and complete the skipped step from the beginning. If
that completion attempt fails, raise the issue to the user before proceeding to any subsequent
step.

1. Run `.\sdp-shared\scripts\sdp-tone.ps1 -skillName "sdp-project-pre-work-verify" -event "start"` via the PowerShell tool.
2. Use the Read tool to read `sdp-shared/ai-skills/sdp-project-pre-work-verify/SKILL.md` from the project
   root — do this before anything else. If the Read fails, halt and report:
   "`sdp-shared/ai-skills/sdp-project-pre-work-verify/SKILL.md` not found — skill cannot execute."
3. Execute every numbered step in that SKILL.md in order, completing all sub-steps of a step
   before moving to the next. Do not report this skill complete until every step and sub-step
   is done.
4. Run `.\sdp-shared\scripts\sdp-tone.ps1 -skillName "sdp-project-pre-work-verify" -event "end"` via the PowerShell tool.
````

**Level 2** (`sdp-shared/ai-skills/sdp-project-pre-work-verify/SKILL.md`):

````markdown
## Purpose

Prevent duplicate effort, detect partially-complete states, and ensure clean resumption of
interrupted work before a WORKER session begins implementation on any task.

## Inputs

- Task description from the phase file (read as part of WORKER session step 5)
- Task type — inferred from the task description

## Procedure

### Step 1: Scan for Prior Artifacts

Search the codebase, filesystem, database, and migrations for artifacts related to this task.
Scope the search to what the task type implies:

| Task type | What to search for |
|-----------|-------------------|
| Create database | Database existence, schema state, applied migration journal |
| Implement entity / class | Project source for the class files |
| Create migration | Migrations folder for timestamped migration files |
| Seed data | Target table contents or post-deploy scripts |
| Other | Infer the primary artifact from the task description and search for it |

Look specifically for partial or incomplete artifacts: a class with only some properties,
a table missing columns, a script that was partially applied.

### Step 2: Classify State

Assign exactly one classification:

| State | Definition |
|-------|------------|
| **Not Started** | No artifacts found; no evidence of prior work |
| **In Progress / Incomplete** | Artifacts exist but work is clearly partial |
| **Complete** | Task is finished and meets or exceeds all deliverables in the task description |

### Step 3: Act Based on Classification

**Not Started:** Proceed immediately. No confirmation required.

**In Progress / Incomplete:**
1. Report to the user: what artifacts were found; what appears incomplete; last observed
   state (file dates, git history if available)
2. Ask: "Should I continue from where this was left off, discard and restart, or inspect
   first?"
3. Proceed only after the user confirms
4. Document the resumption or restart choice in the Completed blockquote

**Complete:**
1. Do not re-implement the task
2. Append a note to the phase file: "Pre-work verification: task already complete as of
   [date if determinable]. No work performed."
3. Notify COORDINATOR — do not proceed to implementation

## Constraints

- Execute at the start of every WORKER session, before any implementation begins.
- Do not classify as Not Started after a shallow search — scan all artifact types implied
  by the task description before concluding nothing exists.
- Do not classify as Complete unless all deliverables in the task description are met, not
  just that some artifacts exist.
- User confirmation is required before resuming or restarting any In Progress / Incomplete
  task.
- These bullets are phrased as negative bounding rules (what must never happen) rather than
  positive reminders — see the Constraint phrasing note under the Level 2 Template above.

## Outputs

- One of three outcomes: proceed to implementation / await user confirmation / notify
  COORDINATOR of already-complete task
- For In Progress / Incomplete tasks: resumption or restart choice documented in the
  Completed blockquote
- For Complete tasks: note appended to the phase file
````

---

## Post-Authoring Baseline

After creating a new skill, run `/sdp-evaluate-skill [skill-name]` to produce the initial
evaluation report. `sdp-evaluate-skill` writes to one of two locations depending on the
target: `sdp-shared/skill-evals/[skill-name]-eval.md` for a project-authored skill (any name
not prefixed `sdp-`), or `~SDP-Maintenance/~sdp-shared/~skill-evals/[skill-name]-eval.md` for
an SDP framework skill (`sdp-` prefix) — see `sdp-evaluate-skill/SKILL.md` Step 0. This
records the scripting baseline — which steps are SCRIPT, LLM-ONLY, or HYBRID-STEP — so future
changes can track what shifted and whether scripting opportunities were introduced or resolved.
