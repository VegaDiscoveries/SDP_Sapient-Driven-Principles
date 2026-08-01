## Purpose

Review current SDP workflow state, identify the next step/phase/task, and write a
complete, self-contained prompt to `[resolved_project]/sdp-docs/00_prompt.txt` that a
new agent session can use immediately — without prior context — to continue the project
correctly.

This skill does not modify workflow state, write session files, or dispatch agents.
Its sole output is `[resolved_project]/sdp-docs/00_prompt.txt`. This file is a working
file and is overwritten on each invocation — it is not append-only.

`[resolved_project]` is resolved in Step 1b using the three-level Section 5 resolution
order. All file paths in this skill use `[resolved_project]` as their root.

## How This Skill Works

The hybrid model: the LLM owns only the judgments that need conversational context;
everything deterministic is the script's.

1. **LLM — context gate (Option A).** Read the conversation and decide whether work
   has departed from normal SDP dispatch. On override: report and exit without running
   the script — `[resolved_project]/sdp-docs/00_prompt.txt` is a normal-workflow
   artifact only.
2. **Script — state read, section build, and write.** With no override, the script
   reads all state and writes `[resolved_project]/sdp-docs/00_prompt.txt` directly in
   single-option form. The section strings it produces are the final content; there is
   no LLM assembly step.
3. **LLM — rare two-option overwrite.** Only when conversational context shows the
   two-option case (same role, ambiguous specific task) does the LLM read the temp file
   and overwrite `[resolved_project]/sdp-docs/00_prompt.txt` with the two-option form.
   Otherwise the script's output stands.

Normal path tool calls: 1 (script invocation). The two-option case adds 2 (temp read +
overwrite).

## Procedure

### Step 1: Assess Context (Option A)

Read the current conversation without opening any files. Determine whether this
session has taken work in a direction that departs from normal SDP workflow dispatch:

- **No override** — conversation contains no directional signal, or signal confirms
  that the next step is a standard COORDINATOR / WORKER / REVIEWER dispatch. Proceed
  to Step 2.

- **Override detected** — user has redirected work outside normal workflow (e.g.
  ad-hoc edits, design work, skill authoring, setup tasks, or any user instruction
  that is not a workflow dispatch). In this case:
  - Report to the user what context signal was detected and why the prompt file is
    not being generated.
  - Exit the skill immediately. Do NOT invoke the script. Do NOT write
    `[resolved_project]/sdp-docs/00_prompt.txt`.

### Step 1b: Resolve Project

Resolve `[resolved_project]` using the priority order below. Use the first level that
yields a result; do not check subsequent levels.

**Level 0 — Invocation argument (user or agent).**
If a project path was passed as an argument on invocation, use it as `[resolved_project]`.
Read `SDP-Solution.json` to validate the value against the `projects` array. If it does not
match any registered entry: reject by invoking:
`/sdp-create-banner icon=error row=0 row: Status | Invocation argument '[value]' does not match any project registered in SDP-Solution.json. Available: [list]. Correct the argument and retry.`
Do not check subsequent levels.

**Level 1 — Dispatch context (authoritative for formally dispatched subagents).**
Read the current session file or prompt sentinel (if one was provided as the opening
context). If it contains a `Project:` field (session file) or a `projects=` attribute
(prompt sentinel), use that value as `[resolved_project]`. For a `projects=` list,
take the first comma-separated entry.

**Level 2 — Physical path extraction (deterministic fallback, no I/O required).**
If no `Project:` field or `projects=` attribute is present, examine the path of the
file being processed (e.g., the session file path, or a state file path). If the path
contains an `sdp-project_*` segment, that segment is `[resolved_project]`
(e.g., `sdp-project_VirtualCoinFolio.API/.sdp-workflow/sessions/session-042.md`
→ `[resolved_project]` = `sdp-project_VirtualCoinFolio.API`).
If the path contains no `sdp-project_*` segment, this is a solution-level file; no
single project applies — proceed to Level 3.

**Level 3 — Script-resolved (user-direct invocations only).**
Used only when this skill is invoked directly by the user with no dispatch context (Levels 0–2
yielded no result). Do not read `SDP-Solution.json` — proceed directly to Step 2 and invoke
the script without `-workspaceRoot`. The script reads `SDP-Solution.json` internally, resolves
`last_active_projects[0]` (falling back to the single `projects` entry when `last_active_projects`
is empty), and echoes the resolved path as `resolvedProject` in its JSON output. If the script
cannot resolve (multiple projects registered and `last_active_projects` is empty), it returns
`status: "error"` with an actionable message — surface it to the user via Step 3 error handling.

Once resolved (Level 0–2), all file paths in subsequent steps are built under `[resolved_project]/`.
For single-project workspaces where `last_active_projects` is `["."]`, paths collapse to
the workspace root — identical to legacy single-project behavior.

### Step 2: Invoke Script

Run the following command via the PowerShell tool:

```powershell
# Levels 0–2 resolved: pass the resolved project path
./sdp-shared/scripts/sdp-create-prompt.ps1 -workspaceRoot .\[resolved_project]

# Level 3 (user-direct, no prior resolution): omit -workspaceRoot; script resolves internally
./sdp-shared/scripts/sdp-create-prompt.ps1
```

(For the Levels 0–2 path, substitute the actual resolved project path for `[resolved_project]`,
e.g. `-workspaceRoot .\sdp-project_VirtualCoinFolio.API`.)

On success the script has already written `[resolved_project]/sdp-docs/00_prompt.txt`
in single-option form. Read the single-line JSON object printed to stdout. It has one
of three forms:

**Success:**
```json
{"status":"success","resolvedProject":"sdp-project_VirtualCoinFolio.API","tempFile":"<rel-path>","promptFile":"sdp-docs/00_prompt.txt","nextRole":"WORKER","workItem":"WI-007","flags":[]}
```

Valid `nextRole` values: `WORKER`, `REVIEWER`, `COORDINATOR`, `GATE_REVIEWER`. When
`nextRole` is `GATE_REVIEWER`, `workItem` is the current phase identifier (e.g.
`"06_phase2_spec"`) rather than a task ID, and `expected_status` in the sentinel is
`phase_gate.status` rather than a task status. The phase document path in Section 5 is
`sdp-docs/[workItem].md`; no phase state file is listed (gate review is document-scoped).

**Halted workflow:**
```json
{"status":"halted","tempFile":"<rel-path>","haltReason":"<reason>"}
```

**Error:**
```json
{"status":"error","tempFile":"<path-or-null>","error":"<message>"}
```

### Step 3: Handle Non-Success States

**If status is `"halted"`:**
Do NOT proceed to Step 4. Report the halt to the user by invoking:
`/sdp-create-banner icon=error row=0 row: Status | Workflow halted — [haltReason]. Resolve this condition before starting a new agent session. Once resolved, run /sdp-project-create-prompt again.`
Exit the skill.

**If status is `"error"`:**
Apply the error handling procedure below, then retry from Step 2.
Do not proceed to Step 4 until a `"success"` response is received.

#### Error Handling Procedure

**Mode 1 — Error temp file written (`tempFile` is not null):**
Read the temp file. The `_meta.error` field contains the failure detail and
`_meta.retry_count` shows the attempt number. Attempt to resolve the reported error
(e.g. check file path, verify `.sdp-workflow/` directory exists). Re-run the script.
The script reads the prior temp file via the tracking file and increments
`retry_count` automatically.

**Mode 2 — No temp file, stdout error present (`tempFile` is null, `error` has content):**
Use the error message from stdout to diagnose the issue. Attempt to resolve. Re-run
the script. Track retry count internally (no temp file to read). Same 3-retry limit.

**Mode 3 — No temp file, no error info:**
Halt immediately. Report to the user by invoking:
`/sdp-create-banner icon=error row=0 row: Status | The script could not be invoked and no error information is available — manual investigation required.`
Exit the skill.

**Retry limit:** After 3 failed attempts across Mode 1 or Mode 2, surface the full
error history to the user by invoking:
`/sdp-create-banner icon=error row=0 row: Status | Retry limit reached — 3 failed attempts across Mode 1 or Mode 2 (see error history above). Exiting without writing [resolved_project]/sdp-docs/00_prompt.txt.`
Exit without writing `[resolved_project]/sdp-docs/00_prompt.txt`.

### Step 4: Two-Option Overwrite (rare)

On a `"success"` response the script has already written
`[resolved_project]/sdp-docs/00_prompt.txt` in single-option, state-driven form. Do
nothing further unless the two-option case applies.

The two-option case applies only when conversational context and workflow state agree
on the next role but disagree on the specific task (e.g. the conversation implies a
different active work item than `state.json` records). This needs context the script
cannot see — it is the one reason to overwrite the script's output.

If it applies:
1. Read the temp file at the path given by `tempFile`. It contains `sentinel`,
   `next_role`, `flags`, `section_1`–`section_5` (pre-formatted), and the
   `section_3_table` / `section_5_files` references.
2. Overwrite `[resolved_project]/sdp-docs/00_prompt.txt` with the same five-section
   structure the script wrote (sentinel line, then `## Section 1 — Role Declaration`
   … `## Section 5 — Key Files`), but note the ambiguity in Section 3 and present both
   options in Section 4 using the Two Options block format defined in the bootstrap doc.
   Use the temp file section content verbatim for every section you are not reshaping.

This is rare — default to leaving the script's single-option output untouched.

### Step 5: Confirm

Report to the user in one sentence that `[resolved_project]/sdp-docs/00_prompt.txt` is
ready, stating who wrote it (script single-option form, or an LLM two-option overwrite)
and the next role and action identified (e.g. "WORKER — task WI-007" or "COORDINATOR —
no active work item, first run"). Do not reproduce the prompt content in the confirmation
message.

## Constraints

- Do not run the script or write `[resolved_project]/sdp-docs/00_prompt.txt` when an
  Option A override is detected.
- The script is the normal-path writer of `[resolved_project]/sdp-docs/00_prompt.txt`
  — do not re-author or rewrite it on the normal path. Overwrite it only for the
  two-option case (Step 4).
- Never substitute non-verbatim content for a temp-file section unless that section is
  being reshaped for the two-option case.
- Do not write session files, update `state.json`, or take any COORDINATOR action.
- Do not dispatch agents or invoke other skills within this skill.
- Do not read files for the Option A assessment — use only the current conversation.
- Do not reproduce the prompt content in the Step 5 confirmation message.

## Outputs

- `[resolved_project]/sdp-docs/00_prompt.txt` — complete, self-contained prompt for the
  next agent session. Written by the script in single-option form on every non-override
  success; overwritten by the LLM only for the rare two-option case. Not written when an
  Option A override is detected, nor on halt/error.
- `[resolved_project]/.sdp-workflow/temp/phase-{N}/phase{N}-sdp-create-prompt-{timestamp}.json`
  — temp file (written by script; retained permanently for debugging and as the data
  source for a two-option overwrite)
- `[resolved_project]/.sdp-workflow/temp/sdp-create-prompt-tracking.json` — tracking
  file (written by script; overwritten each run)
- One-sentence confirmation to the user: next role and action identified
