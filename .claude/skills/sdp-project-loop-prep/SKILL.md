---
name: sdp-project-loop-prep
description: Use before starting an unattended sdp-auto / sdp-state-loop-start run, or whenever the user wants every not-yet-complete phase certified ahead of time instead of reactively mid-loop. Walks registry.md in dependency order running sdp-project-doc-review, sdp-solution-source-coverage-check, and sdp-phase-rightsizing-check against every not-yet-[x] phase, then reports readiness.
---

Do not report this skill complete unless every numbered step and all sub-steps within it have
been completed. Skipping a step and reporting completion is incorrect behavior — if any conduct
rules exist in this context, skipping a step is a conduct violation. Any time a step is
discovered to have been skipped, go back and complete the skipped step from the beginning. If
that completion attempt fails, raise the issue to the user before proceeding to any subsequent
step.

1. Run `./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-project-loop-prep" -event "start"` via the PowerShell tool.
2. Use the Read tool to read `sdp-shared/ai-skills/sdp-project-loop-prep/SKILL.md` from the project
   root — do this before anything else. If the Read fails, halt by invoking
   `/sdp-create-banner icon=error row=0 row: Status | sdp-shared/ai-skills/sdp-project-loop-prep/SKILL.md
   not found — skill cannot execute.`
3. Execute every numbered step in that SKILL.md in order, completing all sub-steps of a step
   before moving to the next. Do not report this skill complete until every step and sub-step
   is done.
4. Run `./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-project-loop-prep" -event "end"` via the PowerShell tool.
