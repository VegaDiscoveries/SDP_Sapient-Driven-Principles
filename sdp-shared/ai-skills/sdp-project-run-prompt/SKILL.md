## Purpose

Resolve the active project, read `[resolved_project]/sdp-docs/00_prompt.txt`, identify the next
SDP skill to invoke (`sdp-project-coordinator`, `sdp-project-worker`, or `sdp-project-reviewer`), and invoke it.
Eliminates the reliability gap where agents read the prompt as context but wait for an explicit
user command rather than executing its instruction.

This skill contains no workflow logic of its own — it resolves the project, reads the prompt,
and dispatches to the correct role skill.

## Inputs

- `SDP-Solution.json` — solution registry; provides `last_active_projects[0]` as the initial
  project candidate (Level 3 resolution — used because this skill is always invoked directly
  by the user, never by a formally dispatched subagent).
- `[resolved_project]/sdp-docs/00_prompt.txt` — written by COORDINATOR or `sdp-project-create-prompt`
  after every dispatch. Contains a five-section prompt with an `Invoke \`/sdp-X\`` instruction
  in Section 4. The sentinel on the first line carries the `projects=` field that confirms the
  resolved project (Level 1).

## Procedure

### Step 1: Run Script

Run `./sdp-shared/scripts/sdp-run-prompt.ps1` via the PowerShell tool. If a project path
was passed as an invocation argument, add `-project "[argument]"`. The script resolves the
active project from `SDP-Solution.json`, reads `[resolved_project]/sdp-docs/00_prompt.txt`,
parses the sentinel `projects=` attribute, scans for skill invocation instructions, and
selects Option 1 automatically for two-option prompts. Outputs single-line JSON.

### Step 2: Handle Result

- If `status` is `"error"`: invoke `/sdp-create-banner` with `icon=error row=0` and
  `row: Error | [error field]`. Halt — do not proceed to Step 3.
- If `status` is `"halted"`: invoke `/sdp-create-banner` with `icon=error row=0` and
  `row: Status | Workflow is halted — [error field]. Resolve this condition before
  proceeding.` Halt — do not proceed to Step 3.
- If `status` is `"no-prompt"`: invoke `/sdp-create-banner` with `icon=error row=0` and
  `row: Error | [error field]`. Halt — do not proceed to Step 3.

### Step 3: Announce

- If `selection_reason` is `"one-match"`: announce to the user: "Identified next step:
  `/[skill_name]` — invoking now."
- If `selection_reason` is `"two-option-auto"`: announce to the user: "Two-option prompt
  detected — automatically selecting Option 1 (recommended): `/[skill_name]`."

### Step 4: Invoke the Skill

Use the Skill tool to invoke `[skill_name]` from the script result. Pass the bare skill name
without the leading `/` (e.g., `sdp-project-coordinator`, not `/sdp-project-coordinator`). The invoked skill
takes over from this point. `sdp-project-run-prompt` has no further steps after the Skill tool call.

## Constraints

- The script reads `SDP-Solution.json` and `[resolved_project]/sdp-docs/00_prompt.txt` only —
  do not read additional files in this skill.
- Never invoke more than one skill per run. When two options are present, never select any
  option other than Option 1, and never ask the user to choose.
- Do not modify any file.
- Do not summarize the prompt content, explain the workflow state, or take any action beyond
  resolving the project, identifying, and invoking the next skill.

## Outputs

- The active project is resolved from `SDP-Solution.json` `last_active_projects[0]`, then
  confirmed (or overridden) by the `projects=` field in the prompt sentinel.
- The identified next skill is invoked via the Skill tool.
- For two-option prompts: Option 1 is selected automatically and announced to the user.
- No files written or modified.
