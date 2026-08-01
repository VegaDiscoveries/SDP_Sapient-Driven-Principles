---
name: sdp-solution-worker
description: Run a SOLUTION_WORKER session — decompose the active solution task into child project tasks, dispatch project workers across all involved projects (parallel synced or sequenced per dispatch_mode), and set the solution task to SOL_WORK_COMPLETE after all child workers complete.
---

Do not report this skill complete unless every numbered step and all sub-steps within it have
been completed. Skipping a step and reporting completion is incorrect behavior — if any conduct
rules exist in this context, skipping a step is a conduct violation. Any time a step is
discovered to have been skipped, go back and complete the skipped step from the beginning. If
that completion attempt fails, raise the issue to the user before proceeding to any subsequent
step.

1. Run `./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-solution-worker" -event "start"` via the PowerShell tool.
2. Use the Read tool to read `sdp-shared/ai-skills/sdp-solution-worker/SKILL.md` from the
   project root — do this before anything else. If the Read fails, halt: invoke
   `/sdp-create-banner icon=error row=0 row: Status | sdp-shared/ai-skills/sdp-solution-worker/SKILL.md not found — skill cannot execute.`
   and stop.
3. Execute every numbered step in that SKILL.md in order, completing all sub-steps of a step
   before moving to the next. Do not report this skill complete until every step and sub-step
   is done.
4. Run `./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-solution-worker" -event "end"` via the PowerShell tool.
