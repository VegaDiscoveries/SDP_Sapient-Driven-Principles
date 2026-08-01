# SDP Core Invariants

These seven invariants govern every SDP session (COORDINATOR, WORKER, REVIEWER, and any
orchestrating/loop session) regardless of how long the session runs or how many times it
compacts. They are extracts of `SDP_Sapient-Driven-Principles_v1.1.0.md` — that document is
authoritative; this file exists so these specific rules survive session compaction, which the
bootstrap doc's own content does not. When the bootstrap doc's language for one of these
changes, mirror the edit here — same discipline as GPG chapter sections mirroring
`GenericProjectGuidlines_*.md`.

## 1. Role Separation

A single session must never perform more than one role (COORDINATOR, WORKER, REVIEWER).
REVIEWER always forms its own understanding of a task's acceptance criteria from the phase
file before reading the WORKER's Completed blockquote. WORKER never evaluates its own output
against acceptance criteria — that is REVIEWER's job, in a separate subagent invocation with no
shared conversation history. `/clear` within an existing context does not satisfy this
requirement; only a new subagent invocation does.

## 2. Halt Discipline

When `workflow_status` is `"halted"` in `state.json`, no further dispatch may occur until a
human resolves the blocking condition and triggers a new COORDINATOR session. COORDINATOR must
not attempt to resolve the blocking condition itself — that is a human action, not an agent
action.

## 3. Debugging Escalation Rule

One full four-phase debugging cycle (reproduce → isolate → diagnose → fix) is the fix budget
for a single WORKER session. If the implemented fix does not resolve the problem, do not
re-attempt. Instead, append a Diagnosis Blocked section (root cause diagnosed, fix attempted,
outcome, user decision needed), flag the task `"DIAGNOSIS_BLOCKED"`, set status to
`WORK_COMPLETE`, and end the session — COORDINATOR handles escalation to the user.

## 4. No Placeholders

All code produced in a WORKER session must be complete. Never write `TODO`, `TBD`, "implement
later", stub bodies, or incomplete implementations. If a required piece cannot be completed due
to missing information or an unresolved dependency, stop before writing placeholder code —
surface the blocker to the user and halt rather than delivering incomplete output.

## 5. Append-Only Discipline

Never delete or edit existing content in a phase document, section file, or the bootstrap doc.
Superseded content is marked with strikethrough (`~~text~~`) in place; the replacement is
appended immediately after with a date and rationale. A deleted constraint reads as an
unconsidered constraint to a future reader — the record of a decision having been made is as
important as the decision itself.

This invariant does not extend to skill files (`.claude/skills/`, `sdp-shared/ai-skills/`) or
script files (`sdp-shared/scripts/`). Those carry only current, executable instructions — never a
dated `Addition —`/`Correction —` history block recording past bugs or design rationale. Git
history is their audit trail; a skill file is read wholesale into live execution context every
run, and incident narrative sitting upstream of the step it explains has been confirmed to erode
an executing agent's confidence at exactly the wrong moment. See the bootstrap doc's Append-Only
Discipline section for the full rule.

## 6. Loop-Owned Field Discipline

`eval_cycle_attempts` in a phase state file is owned exclusively by `sdp-project-state-loop`. A dispatch
file (`session-NNN.md` or `sdp-docs/00_prompt.txt`) must never instruct WORKER or REVIEWER to
set, seed, or increment this field. The sentinel `role` field in `sdp-docs/00_prompt.txt` is
mandatory on every write — omitting it prevents `sdp-project-state-loop` from distinguishing a REVIEWER
fire from a COORDINATOR dispatch-of-REVIEWER fire, silently corrupting stuck-loop attempt
accounting.

## 7. Outcome Detection Via State File Only

After dispatching a subagent (via the Agent tool or equivalent), never parse the subagent's
returned text output to determine its outcome. Always re-read the relevant state file
(`[phase]_state.json` or `state.json`) after the subagent invocation returns — that is the
machine-readable contract; the subagent's text is for the human record only.

## 8. Skill Scope Boundary

A project-level skill (`sdp-project-*`) is never modified to add solution-level capability. When
an existing project-level skill needs a solution-scoped counterpart, a dedicated companion skill
is authored instead of adding a scope parameter or branch to the existing skill — e.g.
`sdp-solution-phase-gate-review` was authored as `sdp-project-gate-review`'s companion rather than
adding a `-scope solution|project` flag to `sdp-project-gate-review` itself. This keeps every
skill single-purpose — a dual-scope skill risks an agent applying the wrong mode mid-procedure —
and prevents an agent from reading a project-level skill and concluding it can be pointed at
solution-level work. This is a constraint on skill *authoring*, not on runtime data access: a
skill may still read files or dispatch across scope tiers where its own documented procedure
calls for it (e.g. `sdp-project-read-docs` loading solution-level docs into a project session).
