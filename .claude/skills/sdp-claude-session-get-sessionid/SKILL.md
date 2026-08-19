---
name: sdp-claude-session-get-sessionid
description: Discover this Claude Code session's own session_id via a marker round-tripped through sdp-hook-log.ps1's own logged output — no environment variable or parameter exposes session_id directly to a running session.
---

Do not report this skill complete unless every numbered step below has been completed. Skipping
a step and reporting completion is incorrect behavior — if any conduct rules exist in this
context, skipping a step is a conduct violation.

This skill is fully scriptable — there is no Level 2 SKILL.md. Steps 2-4 below are the entire
procedure.

1. Run `./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-claude-session-get-sessionid" -event "start"` via the PowerShell tool.
2. Generate a plain-ASCII marker via the PowerShell tool — mechanical value generation only, no
   judgment involved:
   ```
   "SESSION-ID-TEST-MARKER-" + [guid]::NewGuid().ToString("N").Substring(0,16)
   ```
   Read the printed value as `$marker`.
3. Run via the PowerShell tool, substituting the literal `$marker` value from step 2 verbatim
   into the command text (this exact invocation's own command text is what `sdp-hook-log.ps1`
   logs the marker under — the marker must appear as literal text here, not a variable
   reference):
   ```
   ./sdp-shared/scripts/sdp-claude-session-get-sessionid.ps1 -marker "[literal marker value]"
   ```
   Parse the single-line JSON result:
   - `status: "success"` — `session_id` holds this session's own session_id.
   - `status: "not_found"` — the marker never appeared in today's hook-log within the retry
     budget. Report this to the caller as an inability to resolve `session_id` this attempt — do
     not retry automatically beyond what the script itself already did.
   - `status: "error"` — report the `error` field verbatim to the caller. Do not retry
     automatically.
4. Run `./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-claude-session-get-sessionid" -event "end"` via the PowerShell tool.

## Constraints

- Never retry automatically beyond the script's own internal retry budget — a `not_found` or
  `error` result is reported to the caller, not silently re-attempted with a new marker.
- Never use a non-ASCII marker — confirmed corrupted somewhere in the hook-logging pipeline.
