---
name: sdp-solution-state-loop
description: Use when invoked by a recurring loop, in the 2+ project post-Phase-7 regime, to perform sdp-solution-coordinator's dispatch-gating pass — checks dependency-ledger state and dispatches or skips each project's coordinator this cycle.
---

Do not report this skill complete unless every numbered step and all sub-steps within it have
been completed. Skipping a step and reporting completion is incorrect behavior — if any conduct
rules exist in this context, skipping a step is a conduct violation. Any time a step is
discovered to have been skipped, go back and complete the skipped step from the beginning. If
that completion attempt fails, raise the issue to the user before proceeding to any subsequent
step.

**Scope:** Unlike `sdp-project-state-loop`, this skill resolves no per-project target — it operates
directly on `.sdp-solution-workflow/state.json` and `.sdp-solution-workflow/dependencies.json`
at the solution root. It is installed only in the 2+ project, post-Phase-7 regime (Task 14's
one-time cron-target pick) and contains no branching logic of its own — every fire performs
`sdp-solution-coordinator`'s dispatch-gating role (Step 2d) directly.

1. Run `./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-solution-state-loop" -event "start"` via the PowerShell tool.
2. Use the Read tool to read `sdp-shared/ai-skills/sdp-solution-state-loop/SKILL.md` from the project
   root — do this before anything else. If the Read fails, halt and invoke
   `/sdp-create-banner icon=error row=0 row: Status | sdp-shared/ai-skills/sdp-solution-state-loop/SKILL.md not found — skill cannot execute.`
3. Execute every numbered step in that SKILL.md in order, completing all sub-steps of a step
   before moving to the next. Do not report this skill complete until every step and sub-step
   is done.
4. Run `./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-solution-state-loop" -event "end"` via the PowerShell tool.
