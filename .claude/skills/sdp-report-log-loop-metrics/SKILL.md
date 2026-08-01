---
name: sdp-report-log-loop-metrics
description: Generate an SDP loop metrics report (time accounting, halt/interruption tables, time-flow visuals, task outcomes, phase coverage) from a selected loop-metrics-*.jsonl run file on manual invocation.
---

Do not report this skill complete unless every numbered step and all sub-steps within it have
been completed. Skipping a step and reporting completion is incorrect behavior — if any conduct
rules exist in this context, skipping a step is a conduct violation. Any time a step is
discovered to have been skipped, go back and complete the skipped step from the beginning. If
that completion attempt fails, raise the issue to the user before proceeding to any subsequent
step.

1. Run `.\sdp-shared\scripts\sdp-tone.ps1 -skillName "sdp-report-log-loop-metrics" -event "start"` via the PowerShell tool.
2. Use the Read tool to read `sdp-shared/ai-skills/sdp-report-log-loop-metrics/SKILL.md` from the project
   root — do this before anything else. If the Read fails, halt and report:
   "`sdp-shared/ai-skills/sdp-report-log-loop-metrics/SKILL.md` not found — skill cannot execute."
3. Execute every numbered step in that SKILL.md in order, completing all sub-steps of a step
   before moving to the next. Do not report this skill complete until every step and sub-step
   is done.
4. Run `.\sdp-shared\scripts\sdp-tone.ps1 -skillName "sdp-report-log-loop-metrics" -event "end"` via the PowerShell tool.
