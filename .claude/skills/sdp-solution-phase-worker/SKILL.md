---
name: sdp-solution-phase-worker
description: Run a WORKER session for solution-scoped phases 1-7 — load task context from the solution-level dispatch, implement the assigned phase task (including Phase 7 build-phase decomposition), and record completion. Never used for project-level tasks — see sdp-project-worker for those.
---

Do not report this skill complete unless every numbered step and all sub-steps within it have
been completed. Skipping a step and reporting completion is incorrect behavior — if any conduct
rules exist in this context, skipping a step is a conduct violation. Any time a step is
discovered to have been skipped, go back and complete the skipped step from the beginning. If
that completion attempt fails, raise the issue to the user before proceeding to any subsequent
step.

This skill is always solution-scoped — there is no project resolution step, unlike `sdp-project-worker`.
Every path resolves against the solution root.

1. Run `./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-solution-phase-worker" -event "start"` via the PowerShell tool.
2. Use the Read tool to read `sdp-shared/ai-skills/sdp-solution-phase-worker/SKILL.md` from the
   project root — do this before anything else. If the Read fails, halt and invoke
   `/sdp-create-banner icon=error row=0 row: Error | sdp-shared/ai-skills/sdp-solution-phase-worker/SKILL.md not found — skill cannot execute.`
3. Execute every numbered step in that SKILL.md in order, completing all sub-steps of a step
   before moving to the next. Do not report this skill complete until every step and sub-step
   is done.
4. Run `./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-solution-phase-worker" -event "end"` via the PowerShell tool.
