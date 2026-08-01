---
name: sdp-standards-setup
description: Use when a consumer of SDP wants to replace the default GPG (GenericProjectGuidlines) standards doc with their own standards document — enforces doc location, versioning, and format; scaffolds the sections folder, TOC, and section files; generates an interactive reading map cross-referencing GPG chapters; and updates all SDP framework files via fresh search-and-replace with a sanity check pass.
---

Do not report this skill complete unless every numbered step and all sub-steps within it have
been completed. Skipping a step and reporting completion is incorrect behavior — if any conduct
rules exist in this context, skipping a step is a conduct violation. Any time a step is
discovered to have been skipped, go back and complete the skipped step from the beginning. If
that completion attempt fails, raise the issue to the user before proceeding to any subsequent
step.

**Scope:** Solution-root operation only. This skill modifies SDP framework files — skills,
scripts, manifests, and the bootstrap doc — to replace all references to the default GPG
standards doc with the consumer's standards doc. Run once per solution when substituting a
custom standards doc. The original GPG doc must remain in `standards/` for Phase 3
cross-referencing; this is verified in Phase 1 and blocks execution if missing.

1. Run `./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-standards-setup" -event "start"` via the PowerShell tool.
2. Use the Read tool to read `sdp-shared/ai-skills/sdp-standards-setup/SKILL.md` from the
   project root — do this before anything else. If the Read fails, halt and invoke
   `/sdp-create-banner icon=error row=0 row: Status | sdp-shared/ai-skills/sdp-standards-setup/SKILL.md not found — skill cannot execute.`
3. Execute every numbered step in that SKILL.md in order, completing all sub-steps of a step
   before moving to the next. Do not report this skill complete until every step and sub-step
   is done.
4. Run `./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-standards-setup" -event "end"` via the PowerShell tool.
