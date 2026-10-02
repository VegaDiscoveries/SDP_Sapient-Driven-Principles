---
name: sdp-eval-and-address-phase-issues
description: Extract every open finding (unresolved gaps, open questions, gate-blocked issues,
rejected-task findings, disclosed issues) from this solution's phase documents, rate each against
a fixed 8-band doc-fix-impact scale using two independently-blind rating passes reconciled against
each other, then apply SDP-Config.json's phaseIssuePolicy.bandDisposition map to separate findings
worth fixing from findings accepted as open, producing one prioritized worklist for human review.
Never evaluates whether any WORKER/REVIEWER/GATE_REVIEWER session itself was necessary or
skippable. On manual invocation.
---

Do not report this skill complete unless every numbered step and all sub-steps within it have
been completed. Skipping a step and reporting completion is incorrect behavior — if any conduct
rules exist in this context, skipping a step is a conduct violation. Any time a step is
discovered to have been skipped, go back and complete the skipped step from the beginning. If
that completion attempt fails, raise the issue to the user before proceeding to any subsequent
step.

1. Run `.\sdp-shared\scripts\sdp-tone.ps1 -skillName "sdp-eval-and-address-phase-issues" -event "start"` via the PowerShell tool.
2. Use the Read tool to read `sdp-shared/ai-skills/sdp-eval-and-address-phase-issues/SKILL.md` from
   the project root — do this before anything else. If the Read fails, halt and report:
   "`sdp-shared/ai-skills/sdp-eval-and-address-phase-issues/SKILL.md` not found — skill cannot execute."
3. Execute every numbered step in that SKILL.md in order, completing all sub-steps of a step
   before moving to the next. Do not report this skill complete until every step and sub-step
   is done.
4. Run `.\sdp-shared\scripts\sdp-tone.ps1 -skillName "sdp-eval-and-address-phase-issues" -event "end"` via the PowerShell tool.
