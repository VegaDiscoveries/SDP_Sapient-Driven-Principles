---
name: sdp-auto
description: Explicit per-session opt-in to auto-advance the SDP workflow — verifies the workflow is active and unblocked, starts a recurring state-loop, and dispatches the immediate next step.
---

Do not report this skill complete unless every numbered step and all sub-steps within it have
been completed. Skipping a step and reporting completion is incorrect behavior — if any conduct
rules exist in this context, skipping a step is a conduct violation. Any time a step is
discovered to have been skipped, go back and complete the skipped step from the beginning. If
that completion attempt fails, raise the issue to the user before proceeding to any subsequent
step.

1. Run `./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-auto" -event "start"` via the PowerShell tool.
2. Use the Read tool to read `sdp-shared/ai-skills/sdp-auto/SKILL.md` from the project
   root — do this before anything else. If the Read fails, invoke `/sdp-create-banner` with
   icon=error and the row below, then halt:
   `icon=error row=0 row: Status | sdp-shared/ai-skills/sdp-auto/SKILL.md not found — skill cannot execute.`
3. Execute every numbered step in that SKILL.md in order, completing all sub-steps of a step
   before moving to the next. Do not report this skill complete until every step and sub-step
   is done.
4. Run `./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-auto" -event "end"` via the PowerShell tool.
