---
name: sdp-new-concept-intake
description: Use when the user wants a new mini Phase 1-5 concept cycle registered mid-project — at any project maturity, not just a clean new project. Two modes — document-driven (one or more files dropped into sdp-solution-docs/user-design-docs/: scans, groups related docs, tracks the source for sdp-source-coverage-check) or conversational (user describes the concept directly, no file). Either way: confirms the target project, seeds registry.md rows and phase stubs, then hands off to normal COORDINATOR dispatch.
---

Do not report this skill complete unless every numbered step and all sub-steps within it have
been completed. Skipping a step and reporting completion is incorrect behavior — if any conduct
rules exist in this context, skipping a step is a conduct violation. Any time a step is
discovered to have been skipped, go back and complete the skipped step from the beginning. If
that completion attempt fails, raise the issue to the user before proceeding to any subsequent
step.

1. Run `./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-new-concept-intake" -event "start"` via the PowerShell tool.
2. Use the Read tool to read `sdp-shared/ai-skills/sdp-new-concept-intake/SKILL.md` from the
   project root — do this before anything else. If the Read fails, halt and invoke
   `/sdp-create-banner icon=error row=0 row: Status | sdp-shared/ai-skills/sdp-new-concept-intake/SKILL.md not found — skill cannot execute.`
3. Execute every numbered step in that SKILL.md in order, completing all sub-steps of a step
   before moving to the next. Do not report this skill complete until every step and sub-step
   is done.
4. Run `./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-new-concept-intake" -event "end"` via the PowerShell tool.
