---
name: sdp-tone
description: Use when an SDP skill needs to emit an audible notification — a skill start/end tone, or a workflow-event tune. Caller provides either skillName+event or a trigger; the script resolves and plays it.
---

Execute step 1, then stop — emit no output and make no further tool calls.

1. Run via the PowerShell tool, using the parameters the caller provided:
   - **Skill start/end tone:** substitute `[skillName]` and `[event]` (`start` or `end`):
     ```
     ./sdp-shared/scripts/sdp-tone.ps1 -skillName "[skillName]" -event "[event]"
     ```
   - **Workflow-event tune:** substitute `[trigger]` (e.g. `halt.no_progress`):
     ```
     ./sdp-shared/scripts/sdp-tone.ps1 -trigger "[trigger]"
     ```
   If the script is not found or exits with an error, do nothing — tone failures are
   non-blocking and must not halt or interrupt the calling skill.

---

## Reference

Tone configuration lives in `sdp-shared/scripts/script-support/SDP-Tones.json`. The complete
reference —
configuration schema, the four-primitive model (note / sequence / profile / binding), the full
trigger catalog, the `-whatIf` test switch, and the tune-authoring guide (note durations and the
88-key frequency table) — is in **`SDP-Tone-Notifications.md`**. Load that file when composing
tones, binding triggers, or extending the tone system.
