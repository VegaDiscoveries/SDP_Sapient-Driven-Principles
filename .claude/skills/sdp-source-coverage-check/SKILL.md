---
name: sdp-source-coverage-check
description: Use immediately after Phase 1/2 are drafted for a new concept cycle (mandatory step, invoked by sdp-new-concept-intake), and again as part of sdp-project-loop-prep's pre-loop sweep. Compares a tracked source design doc against its downstream phase docs and surfaces any element with no downstream coverage.
---

Do not report this skill complete unless every numbered step and all sub-steps within it have
been completed. Skipping a step and reporting completion is incorrect behavior — if any conduct
rules exist in this context, skipping a step is a conduct violation. Any time a step is
discovered to have been skipped, go back and complete the skipped step from the beginning. If
that completion attempt fails, raise the issue to the user before proceeding to any subsequent
step.

1. Run `./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-source-coverage-check" -event "start"` via the PowerShell tool.
2. Use the Read tool to read `sdp-shared/ai-skills/sdp-source-coverage-check/SKILL.md` from the
   project root — do this before anything else. If the Read fails, halt: invoke
   `/sdp-create-banner icon=error row=0 row: Status | sdp-shared/ai-skills/sdp-source-coverage-check/SKILL.md not found — skill cannot execute.`
   Do not proceed.
3. Execute every numbered step in that SKILL.md in order, completing all sub-steps of a step
   before moving to the next. Do not report this skill complete until every step and sub-step
   is done.
4. Run `./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-source-coverage-check" -event "end"` via the PowerShell tool.
