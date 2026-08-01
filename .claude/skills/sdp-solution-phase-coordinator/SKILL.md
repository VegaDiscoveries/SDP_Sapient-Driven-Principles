---
name: sdp-solution-phase-coordinator
description: Run the phases-1-7 driving role for a solution — dispatch WORKER/REVIEWER/GATE_REVIEWER for the solution's own Concept-through-Phase-Readiness cycle, own the cross-project dependency ledger, and gate post-Phase-7 project dispatch. Dedicated companion to sdp-solution-coordinator, which owns shared-cross-project-task dispatch only and is never given a phases-1-7 dispatch.
---

Do not report this skill complete unless every numbered step and all sub-steps within it have
been completed. Skipping a step and reporting completion is incorrect behavior — if any conduct
rules exist in this context, skipping a step is a conduct violation. Any time a step is
discovered to have been skipped, go back and complete the skipped step from the beginning. If
that completion attempt fails, raise the issue to the user before proceeding to any subsequent
step.

**Scope:** The solution's own phases 1-7 (Concept through Phase Readiness), and the ongoing
post-Phase-7 dependency-ledger/dispatch-gating duties that follow. Does not manage
shared-cross-project *task* dispatch (tasks with a `parent` field) — that remains
`sdp-solution-coordinator`'s exclusive job.

**Solution level:** This skill operates at the solution root. All file paths are relative to
the solution root (the Claude Code working directory). No `[resolved_project]` prefix is used
except when accessing individual project state files.

1. Run `./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-solution-phase-coordinator" -event "start"` via the PowerShell tool.
2. Use the Read tool to read `sdp-shared/ai-skills/sdp-solution-phase-coordinator/SKILL.md` from
   the solution root — do this before anything else. If the Read fails, halt: invoke
   `/sdp-create-banner icon=error row=0 row: Error | sdp-shared/ai-skills/sdp-solution-phase-coordinator/SKILL.md not found — skill cannot execute.`
3. Execute every numbered step in that SKILL.md in order, completing all sub-steps of a step
   before moving to the next. Do not report this skill complete until every step and sub-step
   is done.
4. Run `./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-solution-phase-coordinator" -event "end"` via the PowerShell tool.
