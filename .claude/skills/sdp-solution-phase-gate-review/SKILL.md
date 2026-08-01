---
name: sdp-solution-phase-gate-review
description: Use when all tasks in the solution's current phase (1-7) are VERIFIED and a gate review is required before advancing to the next phase — runs as GATE_REVIEWER, solution-scoped, to assess the completed phase document against completeness, consistency, GPG alignment, next-phase readiness, and (Phase Readiness only) full-lifecycle traceability criteria. Never used for project-level gate reviews — see sdp-project-gate-review for those.
---

Do not report this skill complete unless every numbered step and all sub-steps within it have
been completed. Skipping a step and reporting completion is incorrect behavior — if any conduct
rules exist in this context, skipping a step is a conduct violation. Any time a step is
discovered to have been skipped, go back and complete the skipped step from the beginning. If
that completion attempt fails, raise the issue to the user before proceeding to any subsequent
step.

1. Run `./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-solution-phase-gate-review" -event "start"` via the PowerShell tool.
2. Use the Read tool to read `sdp-shared/ai-skills/sdp-solution-phase-gate-review/SKILL.md` from the
   project root — do this before anything else. If the Read fails, halt and invoke
   `/sdp-create-banner icon=error row=0 row: Status | sdp-shared/ai-skills/sdp-solution-phase-gate-review/SKILL.md not found — skill cannot execute.`
3. Execute every numbered step in that SKILL.md in order, completing all sub-steps of a step
   before moving to the next. Do not report this skill complete until every step and sub-step
   is done.
4. Run `./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-solution-phase-gate-review" -event "end"` via the PowerShell tool.
