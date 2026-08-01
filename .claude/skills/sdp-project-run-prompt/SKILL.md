---
name: sdp-project-run-prompt
description: Use when opening a new SDP agent session and wanting to immediately execute the next workflow step without manually identifying the skill to invoke from sdp-docs/00_prompt.txt. Resolves the active project from SDP-Solution.json last_active_projects[0], then confirms it from the projects= field in the 00_prompt.txt sentinel before reading the file.
---

Do not report this skill complete unless every numbered step and all sub-steps within it have
been completed. Skipping a step and reporting completion is incorrect behavior — if any conduct
rules exist in this context, skipping a step is a conduct violation. Any time a step is
discovered to have been skipped, go back and complete the skipped step from the beginning. If
that completion attempt fails, raise the issue to the user before proceeding to any subsequent
step.

1. Run `./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-project-run-prompt" -event "start"` via the PowerShell tool.
2. Use the Read tool to read `sdp-shared/ai-skills/sdp-project-run-prompt/SKILL.md` from the project
   root — do this before anything else. If the Read fails, halt and invoke `/sdp-create-banner`
   with `icon=error row=0` and `row: Error | sdp-shared/ai-skills/sdp-project-run-prompt/SKILL.md not
   found — skill cannot execute.`
3. Execute every numbered step in that SKILL.md in order, completing all sub-steps of a step
   before moving to the next. Do not report this skill complete until every step and sub-step
   is done.
4. Run `./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-project-run-prompt" -event "end"` via the PowerShell tool.
