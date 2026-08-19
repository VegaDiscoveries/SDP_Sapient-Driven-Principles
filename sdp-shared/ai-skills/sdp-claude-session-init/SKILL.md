## Purpose

Runs as the wrapped initial prompt of a freshly-spawned terminal (e.g. via
`sdp-claude-new-terminal -promptOverride "/sdp-claude-session-init -launcherSessionId [X]
-thenRun \"[real prompt]\""`). Self-registers this new session's own `session_id` onto the
launching session's row in `SDP-Terminal-Sessions.json`, confirms a pending RESPAWN handoff in
`.sdp-solution-workflow/state.json` when one exists, then chains into whatever the caller actually
wanted this session to do. All bookkeeping steps are best-effort — none of them may ever block
reaching the real payload.

## Inputs

- `-launcherSessionId [X]` — the launching session's own `session_id`, passed in literally by the
  launcher.
- `-thenRun "[real prompt/skill text]"` — what to invoke after self-registration and handoff
  confirmation.

## Procedure

### Step 1: Discover Own session_id

1. Invoke `/sdp-claude-session-get-sessionid` (its own marker-embed-and-poll procedure). Record
   the result as `ownSessionId`.
2. If the result is `not_found` or `error`: proceed to Step 2 with `ownSessionId = null` — a
   failure to discover this session's own id must not block reaching `-thenRun` (Step 4). Steps 2
   and 3 below both degrade gracefully when `ownSessionId` is `null` (their own registry/state
   writes are simply skipped).

### Step 2: Self-Register on the Launcher's Terminal-Registry Row

1. Read `sdp-shared/scripts/script-support/SDP-Terminal-Sessions.json`.
2. Find the entry whose `launcherSessionId` field equals the passed-in `-launcherSessionId`
   value.
3. If no matching entry is found, or `ownSessionId` is `null` (from Step 1): skip the rest of this
   step — proceed to Step 3.
4. **Guard:** if the matching entry's `sessionId` field is already non-null: invoke
   `/sdp-create-banner icon=warning row=0 row: Status | sdp-claude-session-init: terminal-registry row for launcher [launcherSessionId] already has a sessionId — leaving it unchanged.`
   Do not overwrite it. Proceed to Step 3 regardless.
5. If `sessionId` is `null` (the normal case): write `ownSessionId` into that entry's `sessionId`
   field and save the file (UTF-8, no BOM). Do not modify any other entry.

### Step 3: Confirm a Pending RESPAWN Handoff

1. Read `.sdp-solution-workflow/state.json`. If unreadable, or `ownSessionId` is `null` (from
   Step 1): skip the rest of this step — proceed to Step 4.
2. Look up the entry in `auto_actions` with `action: "session_respawn"` whose
   `launcher_session_id` field equals the passed-in `-launcherSessionId` value.
3. If found and its `handoff_confirmed` field is not already `true`: set
   `handoff_confirmed: true` on that entry and save the file.
4. If no matching entry is found: this spawn was not a RESPAWN-triggered launch (or the entry
   predates this field) — skip silently, not a failure.

### Step 4: Chain to the Real Payload

1. Invoke whatever `-thenRun` named (the real prompt or skill text) as this session's next
   action.

## Constraints

- Never block reaching `-thenRun` (Step 4) over a failure in Step 1, 2, or 3 — self-registration
  and handoff confirmation are best-effort bookkeeping, not preconditions for the session's real
  work.
- Never overwrite a terminal-registry row's `sessionId` field once it is already non-null — report
  via banner and move on (see Step 2's guard).
- Matching purely by `launcherSessionId` is ambiguous if the *same* launcher session spawns more
  than one terminal before either self-registers (two rows could share the same
  `launcherSessionId` with both `sessionId` fields still `null`) — the first matching row found is
  used. Not applicable to the RESPAWN use case, where a respawning session launches exactly one
  replacement and then goes idle, so there is never more than one candidate row. Reconsider only
  if this skill is reused for a case that genuinely spawns multiple terminals from one launcher in
  quick succession.

## Outputs

- This session's own `session_id` written onto the launcher's terminal-registry row (best-effort;
  skipped on any failure along the way).
- `handoff_confirmed: true` written onto the matching `auto_actions` RESPAWN entry, if one exists
  (best-effort).
- `-thenRun` invoked as this session's next action, unconditionally.
