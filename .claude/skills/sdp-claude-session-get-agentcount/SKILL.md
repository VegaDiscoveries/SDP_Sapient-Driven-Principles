---
name: sdp-claude-session-get-agentcount
description: Count distinct subagents spawned under a Claude Code session — an exact match to the platform's own cumulative-lifetime subagent-spawn count — by counting distinct agent_id values in the hook-log for that session_id.
---

Do not report this skill complete unless every numbered step below has been completed. Skipping
a step and reporting completion is incorrect behavior — if any conduct rules exist in this
context, skipping a step is a conduct violation.

This skill is fully scriptable — there is no Level 2 SKILL.md. Steps 2-4 below are the entire
procedure.

1. Run `./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-claude-session-get-agentcount" -event "start"` via the PowerShell tool.
2. If the caller already knows this session's own `session_id` (e.g. from a prior
   `sdp-claude-session-get-sessionid` call this session), run:
   ```
   ./sdp-shared/scripts/sdp-claude-session-get-agentcount.ps1 -sessionId "[known session_id]"
   ```
   Otherwise, generate a marker exactly as `sdp-claude-session-get-sessionid`'s own step 2 does
   (`"SESSION-ID-TEST-MARKER-" + [guid]::NewGuid().ToString("N").Substring(0,16)` via the
   PowerShell tool), then run, substituting the literal marker value verbatim:
   ```
   ./sdp-shared/scripts/sdp-claude-session-get-agentcount.ps1 -marker "[literal marker value]"
   ```
3. Parse the single-line JSON result:
   - `status: "success"` — `agent_count` holds the distinct subagent count for `session_id`.
   - `status: "not_found"` — self-discovery marker never appeared within the retry budget. Report
     this to the caller; do not retry automatically beyond what the script itself already did.
   - `status: "error"` — report the `error` field verbatim to the caller. Do not retry
     automatically.
4. Run `./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-claude-session-get-agentcount" -event "end"` via the PowerShell tool.

## Constraints

- Never retry automatically beyond the script's own internal retry budget.
- Never shell out to `sdp-claude-session-get-sessionid.ps1` as a nested subprocess for
  self-discovery — the script performs the marker-embed-and-poll logic inline so this exact
  top-level invocation is what Claude Code's hook system observes.
