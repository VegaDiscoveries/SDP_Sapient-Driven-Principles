---
name: sdp-initialize-sdp
description: Session-start entry point -- prints a static SDP opening banner, chains to
sdp-solution-read-docs to load workspace context, examines solution/project state (or
~SDP-Maintenance framework-dev mode), and prints a closing banner summarizing what was found.
Replaces sdp-solution-read-docs as the SessionStart hook's direct target.
---

Do not report this skill complete unless every numbered step and all sub-steps within it have
been completed. Skipping a step and reporting completion is incorrect behavior — if any conduct
rules exist in this context, skipping a step is a conduct violation. Any time a step is
discovered to have been skipped, go back and complete the skipped step from the beginning. If
that completion attempt fails, raise the issue to the user before proceeding to any subsequent
step.

**Deviation from the standard shim shape:** this skill intentionally has no start-tone step —
its own opening banner (Step 1 of the Level 2 procedure) is the session's visual "welcome"
signal; a three-note "tada" tune (see the `tada` sequence in `SDP-Tones.json`, bound via the
`skill.sdp_initialize_sdp_end` trigger) plays once, at the end, rather than a single skill-tone
note at both start and end.

1. Use the Read tool to read `sdp-shared/ai-skills/sdp-initialize-sdp/SKILL.md` from the project
   root — do this before anything else. If the Read fails, halt and report:
   "`sdp-shared/ai-skills/sdp-initialize-sdp/SKILL.md` not found — skill cannot execute."
2. Execute every numbered step in that SKILL.md in order, completing all sub-steps of a step
   before moving to the next. Do not report this skill complete until every step and sub-step
   is done.
3. Run `.\sdp-shared\scripts\sdp-tone.ps1 -trigger "skill.sdp_initialize_sdp_end"` via the PowerShell tool.
