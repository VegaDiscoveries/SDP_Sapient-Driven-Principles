---
name: sdp-solution-read-docs
description: Load solution-level docs and index all registered project doc lists into agent context. Uses a three-pathway loading model: (1) solution docs from solution-root SDP-Document-List.json; (2) active project docs from the active project's SDP-Document-List.json; (3) other registered projects' doc lists indexed in context but not loaded — an in-context note is appended for multi-project tasks. Invoked internally by sdp-initialize-sdp (the SessionStart hook's actual direct target) and explicitly by solution-level skills.
---

Do not report this skill complete unless every numbered step and all sub-steps within it have
been completed. Skipping a step and reporting completion is incorrect behavior — if any conduct
rules exist in this context, skipping a step is a conduct violation. Any time a step is
discovered to have been skipped, go back and complete the skipped step from the beginning. If
that completion attempt fails, raise the issue to the user before proceeding to any subsequent
step.

**Three-pathway loading model:** This skill loads documents via three pathways — (1) solution-level
docs are loaded from `SDP-Document-List.json` at the solution root (entries with
`includeInReadDocs: true`); (2) active project docs are loaded via the active project's
`SDP-Document-List.json`, resolved from `SDP-Solution.json`; (3) other registered projects'
doc lists are indexed in context but not loaded — an in-context note is appended when
multi-project coordination would require them. See L2 SKILL.md for full procedure details.

**Optional argument — `--no-tone`:** If this skill's invocation argument contains `--no-tone`,
Steps 1 and 4 below are the "tone suppressed" branch: the tone script is not invoked at all (no
PowerShell tool call), rather than invoked and told to be quiet. This is a deliberate,
by-design conditional in this skill's own step definitions, not an agent choosing to omit a
mandated step — following Steps 1 and 4 exactly as written, including the suppressed branch, is
full completion of this skill.

1. If `--no-tone` was passed as this invocation's argument: skip this step entirely, silently —
   do not run the tone script and do not print anything in chat about skipping it. Otherwise:
   run `./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-solution-read-docs" -event "start"`
   via the PowerShell tool.
2. Use the Read tool to read `sdp-shared/ai-skills/sdp-solution-read-docs/SKILL.md` from the project
   root — do this before anything else. If the Read fails, halt and invoke
   `/sdp-create-banner icon=error row=0 row: Status | sdp-shared/ai-skills/sdp-solution-read-docs/SKILL.md not found — skill cannot execute.`
3. Execute every numbered step in that SKILL.md in order, completing all sub-steps of a step
   before moving to the next. Do not report this skill complete until every step and sub-step
   is done.
4. If `--no-tone` was passed as this invocation's argument: skip this step entirely, silently —
   do not run the tone script and do not print anything in chat about skipping it. Otherwise:
   run `./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-solution-read-docs" -event "end"` via
   the PowerShell tool.
