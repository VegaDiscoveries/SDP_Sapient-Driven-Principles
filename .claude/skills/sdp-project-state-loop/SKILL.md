---
name: sdp-project-state-loop
description: Use when invoked by a recurring loop to check SDP session state and dispatch recovery or continuation — detects API errors and WORK_COMPLETE status.
---

Do not report this skill complete unless every numbered step and all sub-steps within it have
been completed. Skipping a step and reporting completion is incorrect behavior — if any conduct
rules exist in this context, skipping a step is a conduct violation. Any time a step is
discovered to have been skipped, go back and complete the skipped step from the beginning. If
that completion attempt fails, raise the issue to the user before proceeding to any subsequent
step.

**Project resolution:** This skill resolves its target project in Step 1b of the L2 procedure,
before any workflow file reads. Resolution priority: (1) extract `projects=` attribute from
the sentinel in `[candidate]/sdp-docs/00_prompt.txt`, where the candidate path comes from
`SDP-Solution.json` `last_active_projects[0]`; (2) fall back to `SDP-Solution.json`
`last_active_projects[0]` if the sentinel carries no `projects=`; (3) fall back to `.` (dot)
if `SDP-Solution.json` is absent or empty — preserving single-project workspace behavior. All
workflow file paths (`state.json`, phase state files, `00_prompt.txt`, session files) are
constructed under `[resolved_project]/`. See design spec Section 5.

1. Run `./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-project-state-loop" -event "start"` via the PowerShell tool.
2. Use the Read tool to read `sdp-shared/ai-skills/sdp-project-state-loop/SKILL.md` from the project
   root — do this before anything else. If the Read fails, halt and invoke
   `/sdp-create-banner icon=error row=0 row: Status | sdp-shared/ai-skills/sdp-project-state-loop/SKILL.md not found — skill cannot execute.`
3. Execute every numbered step in that SKILL.md in order, completing all sub-steps of a step
   before moving to the next. Do not report this skill complete until every step and sub-step
   is done.
4. Run `./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-project-state-loop" -event "end"` via the PowerShell tool.
