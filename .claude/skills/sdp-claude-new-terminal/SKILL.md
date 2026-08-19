---
name: sdp-claude-new-terminal
description: Launch a new terminal window running Claude Code using a named or numbered launch profile from SDP-Config.json's newTerminals array (initial prompt/skill, starting directory, permission mode), and record the spawned instance in SDP-Terminal-Sessions.json for later completion tracking.
---

Do not report this skill complete unless every numbered step below has been completed. Skipping
a step and reporting completion is incorrect behavior — if any conduct rules exist in this
context, skipping a step is a conduct violation.

This skill is fully scriptable — there is no Level 2 SKILL.md. Steps 2-3 below are the entire
procedure.

1. Run `./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-claude-new-terminal" -event "start"` via the PowerShell tool.
2. Run via the PowerShell tool. `SDP-Config.json`'s `newTerminals` array holds one or more named
   launch profiles (each with its own `id`, `name`, `initialPrompt`, `startingDirectory`,
   `hoursToSaveSessionHistory`, `permissionMode`):
   - If the caller (user or dispatching agent) provided an invocation argument, treat it as the
     profile selector and pass it as `-terminal` — it may be a numeric `id` (e.g. `1`) or a
     `name` (e.g. `stateLoop`). Omit `-terminal` to select `id 0`.
   - If the caller separately wants to override just the initial prompt for this one launch
     (distinct from picking a profile), also pass `-promptOverride "[override text]"`.
   - If the caller knows its own `session_id` (e.g. via a prior `sdp-claude-session-get-sessionid`
     call this session) and wants it recorded on the new instance's row for later correlation
     (e.g. a RESPAWN launch), also pass `-callerSessionId "[session_id]"`.
   ```
   ./sdp-shared/scripts/sdp-claude-new-terminal.ps1 -terminal "[optional id or name]" -promptOverride "[optional override]" -callerSessionId "[optional session_id]"
   ```
3. Parse the single-line JSON result and invoke `/sdp-create-banner` with a `Terminal` row:
   - `status: "success"` —
     `icon=success row=0 row: Terminal | Launched instance [instanceId], profile [selectedTerminalId]:[selectedTerminalName], PID [pid], via [launcher] in [resolvedDirectory].`
     Append ", with initial prompt [resolvedPrompt]" only when `resolvedPrompt` is non-empty.
     Append ", permission mode [resolvedPermissionMode]" only when `resolvedPermissionMode` is
     non-empty. Append " ([markedNotRunningCount] session(s) marked not running, [prunedCount]
     pruned)" only when `markedNotRunningCount` or `prunedCount` is greater than 0.
   - `status: "error"` —
     `icon=error row=0 row: Terminal | [error field].`
     Do not retry automatically. This covers: an unresolved `-terminal` selector (no matching
     `id`/`name` in `newTerminals`), and an unrecognized `permissionMode` value on the selected
     profile — no terminal is launched in either case.
4. Run `./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-claude-new-terminal" -event "end"` via the PowerShell tool.

## Constraints

- Never retry automatically on a `status: "error"` result — report the `error` field verbatim
  to the user instead.
