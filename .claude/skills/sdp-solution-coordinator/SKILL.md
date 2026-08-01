---
name: sdp-solution-coordinator
description: Run a COORDINATOR session for a multi-project solution — read all involved project states, enforce the cycle sync invariant, fan out parallel subagents (one per laggard project in synced mode) or sequence dispatch, write session files with Project: field, update last_active_projects in SDP-Solution.json, detect cascades, and terminate after each dispatch. For single-project work use sdp-project-coordinator instead.
---

Do not report this skill complete unless every numbered step and all sub-steps within it have
been completed. Skipping a step and reporting completion is incorrect behavior — if any conduct
rules exist in this context, skipping a step is a conduct violation. Any time a step is
discovered to have been skipped, go back and complete the skipped step from the beginning. If
that completion attempt fails, raise the issue to the user before proceeding to any subsequent
step.

**Scope:** Cross-project solution tasks only. Does not manage single-project tasks (tasks
without a `parent` field in their state entry). Single-project orchestration is handled by
`sdp-project-coordinator`.

**Solution level:** This skill operates at the solution root. All file paths are relative to
the solution root (the Claude Code working directory). No `[resolved_project]` prefix is used
except when accessing individual project state files.

1. Run `./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-solution-coordinator" -event "start"` via the PowerShell tool.
2. Use the Read tool to read `sdp-shared/ai-skills/sdp-solution-coordinator/SKILL.md` from the
   solution root — do this before anything else. If the Read fails, halt: invoke
   `/sdp-create-banner icon=error row=0 row: Error | sdp-shared/ai-skills/sdp-solution-coordinator/SKILL.md not found — skill cannot execute.`
3. Execute every numbered step in that SKILL.md in order, completing all sub-steps of a step
   before moving to the next. Do not report this skill complete until every step and sub-step
   is done.
4. Run `./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-solution-coordinator" -event "end"` via the PowerShell tool.
