## Purpose

Execute a SOLUTION_REVIEWER session: verify that all child project tasks have been reviewed
and reach `VERIFIED`; then perform a cross-project integration check that individual project
reviewers cannot see in isolation. Set the solution task to `SOL_VERIFIED` if all children
pass the integration check, or `SOL_REJECTED` if any child is rejected or the integration
check fails. Enter cascade detection flow on any rejection.

This skill is invoked directly by the user or by `sdp-solution-run-prompt` after
`sdp-solution-coordinator` has dispatched `SOLUTION_REVIEWER`. It operates entirely at the
solution level — it reads from `.sdp-solution-workflow/` and each project's
`.sdp-workflow/state.json`, and dispatches `sdp-project-reviewer` subagents directly per project.

**Hybrid model:** a single script,
`sdp-shared/scripts/sdp-solution-reviewer.ps1`, owns every deterministic step across three
modes — `Bootstrap` (read state, verify child preconditions, report dispatch targets),
`Confirm` (re-read child outcomes after reviewer dispatch, resolve cascade or clear the path
to the integration check), and `Finalize` (write the session outcome file and set
`SOL_VERIFIED` / `SOL_REJECTED` once the verdict is known). The LLM takes over only where
subagent dispatch or semantic judgment is structurally required: dispatching `sdp-project-reviewer`
per child (Step 2), and performing the cross-project integration check (Step 4). The verdict
and per-item integration results are passed into `Finalize` as explicit structured arguments —
the script never infers or re-derives the verdict itself, consistent with the Corrupting risk
mitigation in the eval report.

## Inputs

All paths are relative to the solution root. The script reads these directly; the LLM does
not read them on the normal path.

- `SDP-Solution.json` — provides `active_solution_task`
- `.sdp-solution-workflow/state.json` — provides the solution task entry: `status`, `children`
  list, `dispatch_mode`, `last_session`, `workflow_status`, `halt_reason`
- Each child's `[project]/[derived phase]_state.json` — authoritative status per child (the
  script tries the `[docDir]_Phases/[phase]_state.json` convention first, then falls back to
  the flat `[phase]_state.json` sibling of the phase `.md` file)
- Each child's `[project]/[child.phase_file]` — read only in Confirm mode, only when a
  rejection is detected, to extract the rejection summary

## Procedure

### Step 1: Run Script — Bootstrap Mode

Run `./sdp-shared/scripts/sdp-solution-reviewer.ps1 -Mode Bootstrap` via the PowerShell tool.

If the PowerShell tool call produces no parseable single-line JSON on stdout (regardless of
exit code): invoke
`/sdp-create-banner icon=error row=0 row: Status | Script invocation failed — no result to parse. Verify sdp-shared/scripts/sdp-solution-reviewer.ps1 is present and the permission entry in .claude/settings.local.json is registered.`
and halt.

Parse the single-line JSON result. Branch on `status`:

- **`"error"`** — Invoke `/sdp-create-banner icon=error row=0 row: Error | [error]`. Halt. (No
  state was written; this covers missing `SDP-Solution.json`, missing `active_solution_task`,
  missing state.json, and the task not being in `SOL_WORK_COMPLETE` status — a premature
  dispatch.)
- **`"halt"`** — Invoke `/sdp-create-banner icon=error row=0 row: Status | [halt_message]`.
  Halt. (The script has already written `workflow_status: "halted"` and `halt_reason` to
  `.sdp-solution-workflow/state.json` when `state_json_written` is `true`; this covers a
  missing task entry, no children listed, an unresolvable/unreadable child state file, or a
  child status that is neither `WORK_COMPLETE` nor `VERIFIED`.)
- **`"success"`** — Proceed to Step 2. The script has already corrected any stale
  `cached_status` values on the task's children in `.sdp-solution-workflow/state.json`.

### Step 2: Dispatch Project Reviewers for WORK_COMPLETE Children

Using the `children` array from the script result, identify every entry where
`needs_dispatch` is `true` (authoritative status `WORK_COMPLETE`, not yet `VERIFIED`).

1. Observe `dispatch_mode`:
   - `"synced"` (default): dispatch all eligible children in parallel as simultaneous subagents
     — one `general-purpose` subagent per project, sent in a single message.
   - `"sequenced"`: dispatch children one at a time in `children` array order; after each
     dispatch, run Step 3 (Confirm) before dispatching the next.

2. For each child being dispatched, invoke `sdp-project-reviewer` as a subagent. The subagent prompt
   must include:
   - The project path: `[child.project]`
   - The task ID: `[child.task_id]`
   - The phase file path: `[child.project]/[child.phase_file]`
   - Instruction to resolve its project from the `Project:` field in its session file (Level 1
     resolution), or from the `sdp-project_*` path segment as the fallback (Level 2)
   - Instruction to invoke `/sdp-project-reviewer` to execute the REVIEWER session

3. Await completion (all eligible dispatches if synced; the current dispatch if sequenced)
   before advancing to Step 3.

### Step 3: Run Script — Confirm Mode

Run `./sdp-shared/scripts/sdp-solution-reviewer.ps1 -Mode Confirm` via the PowerShell tool.
Same no-parseable-result handling as Step 1.

Branch on `status`:

- **`"cascade"`** — A child was rejected. The script has already: read the rejection summary
  from the child's phase file, set the solution task to `SOL_REJECTED` with the
  `SOL_CASCADE_REVIEW_NEEDED` flag, written `.sdp-solution-workflow/sessions/[session_file_written]`,
  and updated `SDP-Solution.json`. Invoke
  `/sdp-create-banner icon=error row=0 row: Status | [cascade_message]`. Terminate. Do not
  proceed to Step 4.
- **`"in_progress"`** — At least one child (per `needs_dispatch`-equivalent: `authoritative_status
  == "WORK_COMPLETE"` in the returned `children` array) has not yet been reviewed. This is the
  expected result mid-way through a `"sequenced"` dispatch. Return to Step 2 and dispatch the
  next child in order.
- **`"ready_for_integration_check"`** — All children are `VERIFIED`. Proceed to Step 4.

### Material Decision Escalation Check

Before suggesting, selecting, or introducing a language, runtime, framework, library/package (any
source/registry), IDE/tool/plugin, database/data-platform engine, cloud/hosting provider,
third-party API/service, or anything similar that is not already explicitly settled — in `.speq`
(project-scoped, from Phase 7 onward) or, pre-Phase-7, in `01_concept.md`/`03_expanded_concept.md`/
a prior resolved Material Decision Escalation record — or an architectural pattern with no GPG
precedent: stop. If `SDP-Config.json` `materialDecisionEscalation.enabled` is `true` (default), do
not proceed. Halt per the bootstrap doc's Halt Behavior Contract instead — set `workflow_status:
"halted"`, `halt_reason` naming the decision, and append a 2-4 option table (per the Gap
Resolution Format) before ending the session. See the bootstrap doc's Material Decision Escalation
section (Dispatch and Halt Contracts).

### Step 4: Cross-Project Integration Check

Perform the integration check. This check verifies concerns that individual project reviewers
cannot see in isolation. It requires reading the interface and contract artifacts across all
involved projects — this is inherently a judgment step; the script cannot perform it.

**Integration check items — evaluate each independently:**

1. **Interface contracts** — Read the relevant API definition files, endpoint handlers, and
   consumer call-sites across the involved projects. Verify that API request/response shapes
   match what the consuming project expects. Flag any shape mismatch, missing field, or
   undocumented field used by the consumer.

2. **Shared type and enum consistency** — Identify any type or enum definition used across
   more than one involved project. Read its definition in each project. Verify that names,
   values, and semantics are consistent. Flag any divergence.

3. **Error handling convention alignment** — Read error-producing paths in one project and
   error-consuming paths in the other. Verify that error shapes, status codes, and fallback
   handling conventions align across the boundary. Flag any mismatch.

4. **Integration assumptions** — Read the solution task `description` field from
   `.sdp-solution-workflow/state.json`. Identify any integration assumption stated there.
   Verify that each assumption is met by the combined implementation across all child projects.
   Flag any assumption that is not satisfied.

For each item: form a verdict — **passes** or **fails**. If it fails, document the specific
cross-project finding (which file in which project, what the discrepancy is, what the correct
behavior must be). Combine all failing-item findings into a single findings string for Step 5.

### Step 5: Run Script — Finalize Mode

Determine the overall verdict: `SOL_VERIFIED` if all four items pass; `SOL_REJECTED` if any
item fails.

Run:
```
./sdp-shared/scripts/sdp-solution-reviewer.ps1 -Mode Finalize -Verdict [SOL_VERIFIED|SOL_REJECTED] -InterfaceContracts [passes|fails] -SharedTypes [passes|fails] -ErrorHandling [passes|fails] -IntegrationAssumptions [passes|fails] -Findings "[combined finding text, or omit if all pass]"
```

Same no-parseable-result handling as Step 1. Branch on `status`:

- **`"error"`** — Invoke `/sdp-create-banner icon=error row=0 row: Error | [error]`. Halt — a
  session file may have been written but state could not be persisted; verify both files
  manually before retrying.
- **`"success"`** — The script has already written `.sdp-solution-workflow/sessions/[session_file_written]`,
  set the solution task's `status` (and `SOL_CASCADE_REVIEW_NEEDED` flag if rejected) in
  `.sdp-solution-workflow/state.json`, incremented `last_session`, and updated
  `SDP-Solution.json`. If `verdict` is `SOL_VERIFIED`, invoke
  `/sdp-create-banner icon=success row=0 row: Status | [completion_message]`. If `verdict` is
  `SOL_REJECTED`, invoke `/sdp-create-banner icon=error row=0 row: Status | [completion_message]`.
  Session ends.

## Constraints

- Only reads child authoritative status from each project's own `[phase]_state.json` file —
  never from `cached_status` in the solution task entry alone (cache is a convenience; the
  project file is authoritative). This is enforced by the script, which always re-reads the
  child state file fresh in every mode.
- Does not dispatch `sdp-project-coordinator` for any project involved in a solution task — dispatches
  `sdp-project-reviewer` directly. The `sdp-project-coordinator` role is reserved for single-project work
  (tasks with no `parent` field in their state entry).
- Does not proceed to the integration check if any child is `REJECTED` — Confirm mode's
  `"cascade"` result fully resolves the session (state, session file, `SDP-Solution.json`)
  before the LLM ever reaches Step 4.
- Does not write `SOL_VERIFIED` until all four integration check items pass.
- Never leave a `SOL_REJECTED` outcome without the `SOL_CASCADE_REVIEW_NEEDED` flag set —
  required from both a child rejection (Confirm mode) and a failed integration check
  (Finalize mode), both script-owned.
- The LLM never writes `.sdp-solution-workflow/state.json`, session files, or
  `SDP-Solution.json` directly — the script owns every write. The only LLM-supplied values
  the script accepts are the `-Verdict` and per-item integration results in Finalize mode,
  passed explicitly rather than inferred by the script.
- All file paths are relative to the solution root (the Claude Code working directory).

## Outputs

- `.sdp-solution-workflow/state.json` — solution task `status` updated to `SOL_VERIFIED` or
  `SOL_REJECTED`; `cached_status` updated for each child; `SOL_CASCADE_REVIEW_NEEDED` flag
  added if rejected; `last_session` incremented; `updated` refreshed; `workflow_status` set
  to `"halted"` if premature dispatch or a state-integrity problem is detected
- `.sdp-solution-workflow/sessions/session-NNN.md` — session outcome record (written by the
  script in the cascade path of Confirm mode, or by Finalize mode)
- `SDP-Solution.json` — `updated` field refreshed
- User notification (cascade/rejection message, or completion message on `SOL_VERIFIED`)
