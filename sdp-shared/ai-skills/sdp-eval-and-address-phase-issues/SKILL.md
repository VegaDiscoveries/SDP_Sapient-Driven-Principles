## Purpose

Scan every phase document across this solution (solution-scoped phases 1-7 and every registered
project's post-Phase-7 build phases) for discrete **open findings** — unresolved Gap Resolution
Format gaps, unresolved Quick Decision Format open questions, still-open Pros-Cons-Gaps cycle
gaps, GATE_BLOCKED verdict issues whose gate has not since passed, the current still-REJECTED
task's non-compliant Eval findings, and disclosed `**Issues:**` sub-heading items — and rate each
one against a fixed 8-band doc-fix-impact scale (how much leaving it unresolved would mislead a
future agent's post-phase-work code generation), using two independently-blind rating passes
reconciled against each other. Apply `SDP-Config.json`'s `phaseIssuePolicy.bandDisposition` map
to decide which findings are worth actively resolving (`"fix"`) versus which can be accepted as
open and left alone (`"accept"`), producing one prioritized worklist for human review.

This skill is a thin assembler over four scripts
(`sdp-eval-and-address-phase-issues-enumerate.ps1`, `-extract.ps1`, `-reconcile.ps1`,
`-worklist.ps1`), each of which computes everything derivable from structured files alone via a
fixed, document-agnostic rule — mirroring `sdp-report-workflow-analysis`'s own
script-does-the-mechanical-work, agent-does-the-judgment split. The one piece of unavoidable
judgment — assigning each open finding its doc-fix-impact band — is resolved by two independently
blind rating passes (Step 4) that never see each other's output, so a lone agent's blind spot
can't silently become the only signal a disagreement would have caught.

**This skill never evaluates, rates, or reports on whether any WORKER/REVIEWER/GATE_REVIEWER
session itself was necessary or could have been skipped — that question is entirely outside its
scope.** Its only unit of analysis is the individual open finding. It never edits a phase
document, never writes to any phase state file or registry, and never dispatches a
WORKER/REVIEWER/GATE_REVIEWER session — queuing a worklist entry is its only output; acting on a
queued fix is always a separate, explicit, human-confirmed decision.

**Scripts are smoke-tested but not yet run against a real consuming solution.** All four were
exercised against synthetic fixtures covering every finding shape and the full
enumerate→extract→reconcile→worklist chain, which caught and fixed a real defect in
`-extract.ps1` (every em-dash/emoji regex pattern silently never matched anything, due to a
no-BOM `.ps1` parsing as the ANSI codepage under Windows PowerShell 5.1 — see that script's own
`.NOTES`) and a real defect in `-worklist.ps1` (piping a raw Hashtable through
`Sort-Object`/`Group-Object` risks it being enumerated as its own key-value pairs rather than
treated as one object — fixed by using `PSCustomObject` throughout). See this skill's own eval
report (`~SDP-Maintenance/~sdp-shared/~skill-evals/sdp-eval-and-address-phase-issues-eval.md`) for
the design rationale and the remaining disclosed assumptions (task-ID attribution via
nearest-preceding-task-item scanning, the project-level phase document path convention) that
still need confirming against a live consuming solution's real documents — synthetic fixtures
cannot stand in for that structural variety.

## Inputs

- `SDP-Config.json`'s `phaseIssuePolicy.bandDisposition` — a complete map of all 8 bands to
  `"fix"` or `"accept"`. Required; this skill halts without it (Step 1).
- `.sdp-solution-workflow/registry.md` (solution-level phases 1-7) and each registered project's
  `.sdp-workflow/registry.md` (from `SDP-Solution.json`'s `projects[]`) — enumerates every phase
  document that currently exists.
- The phase documents themselves and their corresponding `[phase]_state.json` files (used to
  judge whether a given finding is still open or has since been resolved).
- Optional scope filter on invocation: a project name, or `"solution"` (solution-level phases 1-7
  only). Absent either, every phase document across the whole solution is in scope.
- **Single-task invocation mode:** a `{phaseFile, taskId}` pair, passed when a COORDINATOR skill
  invokes this skill as the Accepted Variance trigger (bootstrap doc, State Machine section)
  rather than as a standalone audit. Restricts the entire run to exactly that one task's current
  REJECTED Eval blockquote (shape 5 only) — Step 2's phase-document enumeration and every other
  finding shape are skipped. Mutually exclusive with the project/solution scope filter above.

## Procedure

### Step 1: Verify Preconditions

1. Read `SDP-Config.json`. If the `phaseIssuePolicy` key is absent, or its `bandDisposition` map
   does not cover all eight bands (`Required`, `Critical`, `Structural`, `Material`, `Clarifying`,
   `Contextual`, `Cosmetic`, `Administrative`) with a value of exactly `"fix"` or `"accept"` each:
   halt — invoke
   `/sdp-create-banner icon=error row=0 row: Status | SDP-Config.json phaseIssuePolicy.bandDisposition is missing or incomplete (all 8 bands required) — add it before running this skill.`
   and stop. Never assume a default disposition for a missing or malformed band entry.

### Step 2: Resolve the Output Folder and Run Enumerate

1. Obtain today's date via the PowerShell tool: `Get-Date -Format "yyyy-MM-dd"`. Never hand-write
   or infer this value.
2. Resolve `[output_dir]` = `.sdp-solution-workflow/reports/[today]_phase-issues/` at the
   solution root (a sibling of `sdp-report-workflow-analysis`'s own `[today]_sdp-analysis/`
   folder) — **except in single-task mode**, where `[output_dir]` =
   `.sdp-solution-workflow/reports/[today]_phase-issues/[taskId]/`, a task-scoped subfolder that
   avoids collision with a concurrent whole-solution sweep running the same day. Create it via
   `New-Item -ItemType Directory -Force -Path '[output_dir]'`. A same-day re-run overwriting
   prior files for the same scope is expected.
3. Run via the PowerShell tool:
   - **Single-task mode:** `.\sdp-shared\scripts\sdp-eval-and-address-phase-issues-enumerate.ps1 -PhaseFile '[phaseFile]' -TaskId '[taskId]'`
   - **Whole-sweep mode:** `.\sdp-shared\scripts\sdp-eval-and-address-phase-issues-enumerate.ps1 [-ProjectFilter '[name]'] [-SolutionOnly]`
     (omit both flags for the default full-solution sweep)
4. If `status` is `"error"`: invoke
   `/sdp-create-banner icon=error row=0 row: Status | Enumerate step failed: [error field].` and
   stop.
5. If `documentCount` is `0`: invoke
   `/sdp-create-banner icon=info row=0 row: Status | No phase documents found to scan.` and stop.
6. Save the `documents` array verbatim to `[output_dir]/01_documents.json` (Write tool, no
   reformatting) — this is `-extract.ps1`'s own input in Step 3 below.

### Step 3: Run Extract

1. Run via the PowerShell tool:
   - **Single-task mode:** `.\sdp-shared\scripts\sdp-eval-and-address-phase-issues-extract.ps1 -SingleTaskMode -PhaseDocPath '[documents[0].phaseDocPath]' -PhaseStatePath '[documents[0].phaseStatePath]' -TaskId '[taskId]' -OutputPath '[output_dir]/open_findings.json'`
   - **Whole-sweep mode:** `.\sdp-shared\scripts\sdp-eval-and-address-phase-issues-extract.ps1 -DocumentsJsonPath '[output_dir]/01_documents.json' -OutputPath '[output_dir]/open_findings.json'`
2. If `status` is `"error"`: invoke
   `/sdp-create-banner icon=error row=0 row: Status | Extract step failed: [error field].` and
   stop.
3. If `documentErrors` is non-empty: invoke
   `/sdp-create-banner icon=warning row=0 row: Status | [N] phase document(s) could not be read and were skipped during extraction — see [output_dir]/open_findings.json run log.`
   and continue — a single unreadable document does not invalidate the rest of the sweep.
4. Note `findingCount` and `findingsByType` — used by Step 4 and the final confirmation.

### Step 4: Independent Rating — Two Blind Passes

**Why two passes, not one:** band assignment is judgment from end to end — no cheap mechanical
rule exists for it the way `sdp-report-workflow-analysis` has one for session categories. Two
independently-blind agent passes, reconciled against each other (Step 5), are the structural
defense this skill uses instead of a single pass that could carry its own undetected blind spot.

1. If `findingCount` (Step 3) is `0`: skip the remainder of this step and Steps 5–6 entirely;
   proceed directly to Step 7 with zero findings. Do not fabricate a rating pass for nothing to
   rate.
2. **Model tier.** This task feeds a worklist with no downstream safety net — the same reasoning
   `sdp-solution-phase-reviewer` Step 4 item 4 already applies to its own verification
   sub-agents. Never dispatch a rating agent below the `standard` tier; resolve the current
   tier's model from `sdp-shared/scripts/script-support/sdp-subagent-model-roster.json`.
3. Read `[output_dir]/open_findings.json`. Build a stripped finding list containing only
   `findingId`, `text`, and `context` for every entry — omit `shape`/`taskId`/`phaseDocPath` from
   what a rating agent sees, so its judgment is anchored on the finding's own content, not on
   which extraction shape or document produced it.
4. **Batching.** `batchCount = min(6, ceil(findingCount / 25))`, splitting the stripped finding
   list into contiguous chunks in existing order.
5. **Pass A:** dispatch one subagent per batch, parallel, single message. Each agent's prompt
   must include: the full 8-band table verbatim (band name + definition, exactly as below); every
   finding in its batch (`findingId` + `text` + `context`); and the instruction to assign each
   finding exactly one band using the definitions given, not by pattern-matching to worked
   examples alone, with a one-sentence rationale tied to that band's definition. The question
   each rating answers is specifically: **if this finding is never resolved and the phase work
   proceeds as-is, how much would that mislead a future agent's post-phase-work code
   generation?** — not how important the finding seemed to the reviewer who raised it.

   | Band | Definition |
   |------|------------|
   | **Required** | Creates an unresolved contradiction between two decisions — a future agent can't proceed correctly until this is settled, because there are now two conflicting "correct" answers. |
   | **Critical** | A factual error that will produce incorrect generated code/artifacts if left uncorrected (wrong name, wrong constraint, wrong value referenced directly by future code). |
   | **Structural** | Damage to the document itself (malformed table, dropped content, broken formatting) that risks losing code-relevant data, even if unconfirmed. |
   | **Material** | Affects the spec's completeness or precision in a way likely to shape implementation, but not a hard error. |
   | **Clarifying** | Improves precision or removes minor ambiguity; a competent agent would probably have inferred the right behavior anyway. |
   | **Contextual** | Affects narrative, rationale, or background explanation — helps a human or future agent understand *why*, not *what to build*. |
   | **Cosmetic** | Style, phrasing, or presentation only — no bearing on technical content. |
   | **Administrative** | Corrections to the review/record-keeping narrative itself (a miscounted fix, a stale status note) — essentially zero bearing on code. |

   Each agent's final report must be exactly a JSON array of
   `{"findingId": "<as given>", "band": "...", "rationale": "..."}` objects, one per finding in
   its batch. No commentary outside that array.
6. **Pass B:** dispatch a second, entirely separate set of subagents over the identical batches,
   with the identical prompt — fresh agents with no shared context with Pass A's agents. This is
   what makes the two passes genuinely independent rather than one agent self-reviewing.
7. Merge every batch's JSON array into one combined array per pass. Save to
   `[output_dir]/findings_pass_a.json` and `[output_dir]/findings_pass_b.json` (Write tool).

### Step 5: Run Reconcile

1. Run via the PowerShell tool:
   ```
   .\sdp-shared\scripts\sdp-eval-and-address-phase-issues-reconcile.ps1 `
     -PassAJsonPath '[output_dir]/findings_pass_a.json' `
     -PassBJsonPath '[output_dir]/findings_pass_b.json' `
     -OutputReconciledPath '[output_dir]/findings_reconciled.json' `
     -OutputDisposedPath '[output_dir]/findings_disposed.json'
   ```
   This single call performs both the Pass A/Pass B reconciliation (escalating any disagreement
   to the higher-impact band, never averaging or picking the lower one) and the
   `phaseIssuePolicy.bandDisposition` lookup, writing both output files directly.
2. If `status` is `"error"`: invoke
   `/sdp-create-banner icon=error row=0 row: Status | Reconcile step failed: [error field].` and
   stop.
3. Note `agreementRate`, `disagreedCount`, `fixCount`, `acceptCount` — used by Step 7.

### Step 6: Run Worklist

1. Run via the PowerShell tool:
   ```
   .\sdp-shared\scripts\sdp-eval-and-address-phase-issues-worklist.ps1 `
     -FindingsJsonPath '[output_dir]/open_findings.json' `
     -DisposedJsonPath '[output_dir]/findings_disposed.json' `
     -OutputJsonPath '[output_dir]/phase-issues-worklist.json' `
     -OutputMarkdownPath '[output_dir]/phase-issues-worklist.md'
   ```
2. If `status` is `"error"`: invoke
   `/sdp-create-banner icon=error row=0 row: Status | Worklist step failed: [error field].` and
   stop.
3. If `unmatchedCount` is greater than `0`: invoke
   `/sdp-create-banner icon=warning row=0 row: Status | [unmatchedCount] disposed finding(s) had no matching entry in open_findings.json — see the worklist's Unmatched section before trusting this run's counts.`
   and continue. A non-zero value here is a join failure between scripts, not a classification
   result — never silently ignore it.

### Step 7: Confirm

Invoke
`/sdp-create-banner icon=success row=0 row: Report | [output_dir]/phase-issues-worklist.md written — [fixFindingCount] findings to fix, [acceptFindingCount] accepted as open, [agreementRate]% pass agreement ([disagreedCount] disagreements).`
For the zero-findings path (Step 4 item 1): state the count is zero rather than fabricating an
agreement rate or running Steps 5–6 against nothing.

## Constraints

- Never evaluate, rate, or report on whether any WORKER/REVIEWER/GATE_REVIEWER session was
  necessary, unnecessary, or skippable — this skill's scope is individual open findings only, and
  never extends to session-level judgment of any kind.
- Never invent a band outside the fixed eight, and never reword a band's given definition — use
  the table in Step 4 verbatim in every rating agent's prompt.
- Never let a Pass B agent see any Pass A output before submitting its own rating — anchoring one
  pass on the other defeats the entire purpose of independent rating.
- Never recompute, override, or "correct" a script-produced figure by hand for a single run. If a
  figure looks wrong, that is a script bug to fix in the relevant
  `sdp-eval-and-address-phase-issues-*.ps1` file and re-run — not something to patch around in
  the assembled worklist.
- Never extract a finding shape outside the six `-extract.ps1` recognizes — an unmatched
  flagged-but-unresolved item is the script's own job to classify or skip, never something this
  skill invents a rule for ad hoc at the LLM layer.
- Never claim certainty that a disclosed `**Issues:**` bullet (extraction shape 6) remains
  unaddressed — `-extract.ps1`'s own disclosed limitation (no document-visible resolution marker
  for this shape, unlike the other five) carries forward into the worklist unchanged.
- Never silently drop an `"accept"`-disposed finding — every one appears in the worklist's
  "Accepted — left open" section with its band and rationale.
- Never edit any phase document, phase state file, or registry file, and never dispatch a
  WORKER, REVIEWER, or GATE_REVIEWER session — this skill's only write action is its own
  `[output_dir]` files. Acting on a queued `"fix"` finding is a separate, explicit,
  human-confirmed decision outside this skill's scope.
- Never proceed without a complete `phaseIssuePolicy.bandDisposition` map in `SDP-Config.json`
  covering all eight bands — halt instead of assuming a default for any missing band.
- Never ignore a non-zero `unmatchedCount` from the worklist script — it signals a join failure
  between scripts, not a classification outcome, and must be surfaced to the user.

## Outputs

- `[output_dir]/01_documents.json` — the enumerate script's phase-document list
- `[output_dir]/open_findings.json` — every extracted open finding, by shape
- `[output_dir]/findings_pass_a.json`, `findings_pass_b.json` — raw independent ratings
- `[output_dir]/findings_reconciled.json` — reconciled findings with provenance and disagreements
- `[output_dir]/findings_disposed.json` — reconciled findings with `"fix"`/`"accept"` disposition
- `[output_dir]/phase-issues-worklist.json` / `.md` — the final, band-grouped, human-reviewable
  worklist
- Confirmation banner with fix/accept/agreement counts
