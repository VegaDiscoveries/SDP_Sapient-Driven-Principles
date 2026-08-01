---
name: sdp-project-read-docs
description: Load solution-level docs and a specified project's docs into agent context — project-scoped. Uses a two-pathway loading model: (1) solution docs from solution-root SDP-Document-List.json; (2) specified project docs from [project]/SDP-Document-List.json. Project is passed as invocation argument or resolved via three-level order. Triggered by "read-docs", "read docs", "read doc", "readdoc", "readd", "docs", or similar shorthands.
---

Do not report this skill complete unless every numbered step and all sub-steps within it have
been completed. Skipping a step and reporting completion is incorrect behavior — if any conduct
rules exist in this context, skipping a step is a conduct violation. Any time a step is
discovered to have been skipped, go back and complete the skipped step from the beginning. If
that completion attempt fails, raise the issue to the user before proceeding to any subsequent
step.

**Two-pathway loading model:** This skill loads documents via two pathways — (1) solution-level
docs are loaded from `SDP-Document-List.json` at the solution root (entries with
`includeInReadDocs: true`); (2) docs for the specified project are loaded via
`[project]/SDP-Document-List.json`. The project is passed as an invocation argument or
resolved via the three-level project resolution order (sentinel `projects=` → path extraction
→ `SDP-Solution.json` `last_active_projects[0]`). See L2 SKILL.md for full procedure details.

**Optional argument — `--no-tone`:** If this skill's invocation argument contains `--no-tone`,
Steps 1 and 4 below are the "tone suppressed" branch: the tone script is not invoked at all (no
PowerShell tool call), rather than invoked and told to be quiet. This is a deliberate, by-design
conditional in this skill's own step definitions, not an agent choosing to omit a mandated step
— following Steps 1 and 4 exactly as written, including the suppressed branch, is full
completion of this skill. `--no-tone` may appear alongside a project name in the same argument
(e.g. `sdp-project-read-docs sdp-project_foo --no-tone`) — strip the `--no-tone` token before treating
the remainder as the project argument for Step 3's "Level 0" handoff to L2 (see
`sdp-shared/ai-skills/sdp-project-read-docs/SKILL.md` Step 1).

1. If `--no-tone` was passed as (part of) this invocation's argument: skip this step entirely,
   silently — do not run the tone script and do not print anything in chat about skipping it.
   Otherwise: run `./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-project-read-docs" -event "start"`
   via the PowerShell tool.
2. Use the Read tool to read `sdp-shared/ai-skills/sdp-project-read-docs/SKILL.md` from the project
   root — do this before anything else. If the Read fails, halt by invoking:
   ```
   /sdp-create-banner icon=error row=0
   row: Error | sdp-shared/ai-skills/sdp-project-read-docs/SKILL.md not found — skill cannot execute.
   ```
3. Execute every numbered step in that SKILL.md in order, completing all sub-steps of a step
   before moving to the next. Do not report this skill complete until every step and sub-step
   is done.
4. If `--no-tone` was passed as (part of) this invocation's argument: skip this step entirely,
   silently — do not run the tone script and do not print anything in chat about skipping it.
   Otherwise: run `./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-project-read-docs" -event "end"`
   via the PowerShell tool.
