<img src="images/SDP_DocsLogo_WithText_0700x0163.png" alt="SDP Logo" width="375">

# SDP Project Evolution

**Created:** 2026-06-18
**Status:** Research — append-only

---

## Guiding Mantra

> *"Make it Work. Make it Work Better. Make it Work Faster."*

Derived from decades of full software lifecycle experience. Each phase is a gate: the next
phase is only valid after the prior one is genuinely achieved — not assumed.

SDP assessment as of 2026-06-18: **approaching the end of "Make it Work."**
The workflow is structurally sound, validated in practice, and the session isolation model
is proven. The next two phases — Better and Faster — are now in scope.

---

## Research: Script Extraction as a Betterment and Speed Pattern

### Hypothesis

Portions of SDP that contain deterministic logic — rule-following with no LLM reasoning
required — are candidates for replacement by scripts. A skill that calls a script instead
of loading a Level 2 SKILL.md and executing it through the LLM is:

- **More deterministic:** the script does exactly what it is coded to do, every time,
  with no risk of misinterpretation, skipped steps, or conduct-rule drift
- **Faster:** script execution is sub-second; the LLM invocation path for a single
  skill costs 10–15 tool calls and multiple seconds of inference time

`sdp-tone` was identified as the proof-of-concept candidate.

---

### Current sdp-tone Invocation Cost

Every Level 1 skill that has tones enabled calls `sdp-tone` twice (start + end).
The current path for one `sdp-tone` invocation:

| Step | Tool calls |
|------|------------|
| Level 1 shim loads (Skill tool) | 1 |
| Level 1 reads SDP-Config.json | 1 |
| Level 1 reads `sdp-shared/ai-skills/sdp-tone/SKILL.md` | 1 |
| TaskCreate × 5 steps | 5 |
| TaskUpdate (in_progress + completed) × 5 | 10 |
| PowerShell Beep execution | 1 |
| **Total per invocation** | **~19 tool calls** |

A script replacement:

```powershell
# called by the Level 1 shim via the Bash/PowerShell tool
./sdp-shared/scripts/sdp-tone.ps1 -skillName "sdp-project-read-docs" -event "start"
```

| Step | Tool calls |
|------|------------|
| PowerShell tool call (script handles all logic internally) | 1 |
| **Total per invocation** | **1 tool call** |

With 10 skills × 2 invocations each per workflow run, this is a reduction from
~380 tool calls to ~20 tool calls for tone notifications alone.

---

### The Determinism Spectrum

Not all SDP skills are equal candidates. The axis that matters:
**Does this step require LLM reasoning, or is it pure rule-following over structured data?**

#### Script candidates — deterministic logic, no LLM reasoning required

| Skill | Logic type | Scriptability | Notes |
|-------|-----------|---------------|-------|
| `sdp-tone` | Config lookup → audio output | ✅ Full | JSON parse + `[console]::Beep()`. Zero reasoning. |
| `sdp-cancel-auto` | Stop a cron job | ✅ Full | Deterministic cancel. |
| `sdp-project-create-prompt` | Template fill from state.json | ✅ ~80% | Template sections are fixed; "state summary" table is a direct state.json read. |
| `sdp-project-run-prompt` | Parse sentinel → invoke skill | ✅ ~70% | Sentinel parsing is deterministic; skill invocation still needs LLM host. |
| `sdp-project-state-loop` core | Read state → branch on sentinel | ✅ ~60% | State reads and sentinel evaluation are deterministic; subagent dispatch is not. |

#### LLM-required — reasoning, judgment, or context-building

| Skill | Why LLM is required |
|-------|---------------------|
| `sdp-project-coordinator` | Makes judgment calls about next tasks, writes nuanced dispatch instructions |
| `sdp-project-worker` | Implements features — the entire point of LLM involvement |
| `sdp-project-reviewer` | Evaluates compliance, forms independent understanding |
| `sdp-project-pre-work-verify` | Searches codebase, classifies ambiguous state |
| `sdp-project-read-docs` | Loading docs into LLM context is the product — can't be scripted away |

---

### Options

#### Option A — Tactical script: sdp-tone only

Convert `sdp-tone` to `sdp-shared/scripts/sdp-tone.ps1`. The Level 1 shim drops the
skill invocation and replaces it with a single PowerShell tool call. Level 2 SKILL.md
for sdp-tone is retired.

**Pros:**
- Highest confidence candidate — logic is trivially deterministic
- Immediate, measurable speedup with zero workflow risk (tones are non-blocking)
- Validates the script pattern for the team before applying it further
- Script is testable in isolation

**Cons:**
- Solves only the symptom (tone overhead); does not address larger orchestration overhead
- Introduces a new artifact type (scripts) that needs a home and maintenance discipline

**Risk:** Very low. Tones are cosmetic. A broken script means silence, not a broken workflow.

---

#### Option B — Infrastructure scripts: sdp-tone + sdp-cancel-auto + sdp-project-create-prompt

Extend the pattern to all pure-infrastructure skills that read state and emit output
without LLM judgment.

**Pros:**
- `sdp-project-create-prompt` is a meaningful win — writing `00_prompt.txt` from a template
  is currently LLM inference over fixed structure; a script does it in milliseconds
- Each converted skill reduces context window pressure on the main session
- Establishes `sdp-shared/scripts/` as a recognized layer in the architecture

**Cons:**
- `sdp-project-create-prompt` edge cases (unusual state combinations) currently get LLM
  judgment for free; a script needs explicit handling for each case
- More surface area to maintain across platforms (PowerShell / bash portability concern)

**Risk:** Low-medium. `sdp-project-create-prompt` is on the critical path for loop dispatch;
a bug there blocks the loop. Needs thorough testing before deployment.

---

#### Option C — Script-orchestrated loop

Replace `sdp-project-state-loop` + `sdp-auto` with a PowerShell loop script. The script:
- Wakes on a configurable interval (reads `SDP-Config.json` `loopInterval`)
- Reads `state.json` and evaluates the sentinel in `sdp-docs/00_prompt.txt`
- Decides EXECUTE vs GENERATE without LLM
- Spawns a Claude Code subagent only when needed (WORKER or REVIEWER dispatch)
- Handles stuck-loop detection, `eval_cycle_attempts` tracking, and auto-push natively
- Plays tones via embedded sdp-tone logic (no skill invocation)

**Pros:**
- LLM is invoked only for work that requires reasoning — WORKER and REVIEWER sessions
- Loop overhead drops from minutes (skill load + inference) to milliseconds
- Stuck-loop detection becomes reliable (script reads counters with no risk of LLM misread)
- Auto-push and halt transitions are deterministic and auditable

**Cons:**
- Highest implementation effort of the three options
- Full script coverage of the state machine means bugs in the script can silently
  misroute the workflow — the LLM currently "sanity checks" by reading and re-stating
  state before acting; a script does not
- Platform portability: a PowerShell loop works on Windows; bash equivalent needed
  for Mac/Linux SDP users
- Debugging script orchestration failures is harder than reading LLM session output

**Risk:** Medium-high. The state machine logic in the script must be correct; there is
no LLM reasoning layer to catch edge cases. Requires a comprehensive test harness.

---

#### Option D — Hook-driven tone notifications

Use Claude Code session hooks (`tool_use` or `stop` events) to fire tone notifications
without any skill invocation at all. The hook runs a shell command directly.

**Pros:**
- Tones become truly zero-cost from the LLM's perspective — not even 1 tool call
- Decouples tone behavior from skill authoring entirely

**Cons:**
- Hooks are platform-specific (Claude Code hooks do not exist on Copilot, Gemini, etc.)
- SDP aims for multi-platform portability; hooks break that
- Hook configuration lives in `settings.json`, not in `SDP-Config.json` — splits
  the tone configuration into two places

**Risk:** Low technically, but conflicts with SDP's portability design goal.

---

### Recommendation

**Start with Option A, decide on B and C separately after the pattern is proven.**

**Rationale:**

`sdp-tone` is the zero-risk proof-of-concept. The logic is trivially correct to port
(5 steps, no branching complexity beyond config lookup), the failure mode is silence
rather than workflow corruption, and success is objectively measurable (tone plays
in under 2 seconds, 1 tool call instead of 19).

Option A proves three things before committing to larger scope:
1. That the `sdp-shared/scripts/` layer integrates cleanly with Level 1 shims
2. That PowerShell tool call permissions work as expected for script invocation
3. That the developer experience (error messages, silent fail behavior) is acceptable

**After Option A is deployed and validated:**

- Option B (`sdp-project-create-prompt`) is the next highest-value target. It is on the critical
  path for loop dispatch and is currently one of the heavier LLM invocations in the
  loop — it reads state.json, forms a structured file, and writes it. A script reduces
  this to a deterministic template fill.

- Option C (full script-orchestrated loop) deserves a separate design session. The
  payoff is large — LLM involvement drops to only WORKER and REVIEWER sessions — but
  the script correctness requirements are high enough to warrant explicit acceptance
  criteria and a test plan before authoring begins.

Option D (hooks) is not recommended given the portability trade-off.

---

### Architecture Implication

If Option A or B is adopted, `sdp-shared/` gains a `scripts/` subdirectory alongside
`ai-skills/`. This is a natural extension of the existing two-level model:

```
sdp-shared/
  ai-skills/          ← Level 2 SKILL.md files (LLM-executed procedures)
  scripts/            ← NEW: deterministic scripts (shell-executed procedures)
    sdp-tone.ps1
    sdp-tone.sh       ← bash equivalent for portability
    sdp-create-prompt.ps1   (if Option B adopted)
```

Level 1 shims gain a new invocation pattern alongside the existing skill invocation:
instead of `invoke /sdp-tone`, the shim calls the PowerShell/Bash tool with the
script path and parameters.

The two-level model is not broken — it is extended. Skills that require LLM reasoning
continue to use `sdp-shared/ai-skills/`. Skills where the LLM is doing clerical work
migrate to `sdp-shared/scripts/`.

---

*Append decisions, options considered, and outcomes below this line as they occur.*

---

## Option A Implemented — 2026-06-18

**Decision:** Option A (sdp-tone → script) adopted.

**Changes made:**

| File | Change |
|------|--------|
| `sdp-shared/scripts/sdp-tone.ps1` | Created — full tone resolution logic as a PowerShell script |
| `.claude/skills/sdp-tone/SKILL.md` | Replaced 5-step LLM procedure with 1-step script call |
| `sdp-shared/ai-skills/sdp-tone/SKILL.md` | ~~Added superseded notice; file retained for SKILLS CHECK~~ |

> **Correction — 2026-06-19:** The Level 2 SKILL.md was subsequently deleted (commit `6c43c4b`).
> The SKILLS CHECK list in the bootstrap doc references this file — that check will now fail
> until the bootstrap doc is updated to remove the Level 2 sdp-tone entry from the check.

**Invocation cost — before vs. after:**

| | Tool calls per invocation |
|-|--------------------------|
| Before (LLM path) | ~19 |
| After (script path) | 1 |

**Pattern confirmed:** The `sdp-shared/scripts/` layer is established. Level 1 shims
that wrap deterministic logic can now call scripts instead of loading Level 2 SKILL.md
procedures. Next candidates for evaluation: `sdp-project-create-prompt`, then a full assessment
of script-orchestrated loop (Option C).

---

## Temp File Design + Hybrid Pattern — 2026-06-19

Outcome of a design session on the next refactor target (`sdp-project-create-prompt`) and the
general pattern for skills with partially deterministic behaviour. Decisions below are
ready for implementation by a future agent.

---

### Temp File Design Decisions

#### Location

`.sdp-workflow/temp/phase-N/` — one subdirectory per phase, scoped to phase not workflow
root. Files are never deleted — retained permanently for debugging and history.

Add to `.gitignore`:
```
.sdp-workflow/temp/
```

#### Naming — Option N1 (adopted)

Script computes the temp file name (phase from `state.json`, skill hardcoded in script,
timestamp from system clock). Script writes the file and echoes the full path to stdout.
Script also updates `state.json → active_temp_file` for persistence and debugging.

LLM reads the path from the tool result (already in context — zero additional tool calls).
No LLM computation of name. No LLM write to `state.json` for the name.

Name format: `phase{N}-{skill}-{YYYYDDMMHHMM}.json`

Example: `phase3-sdp-create-prompt-202619061430.json`

> **Option N2 considered and rejected:** Script writes name to `state.json`, LLM reads
> `state.json` to find it. Rejected in favour of N1 — path available in tool result at
> zero cost is cleaner.

#### Format

JSON with a `_meta` header block carrying all lifecycle markers:

```json
{
  "_meta": {
    "created": "2026-19-06-1430",
    "phase": 3,
    "skill": "sdp-project-create-prompt",
    "script": "sdp-create-prompt.ps1",
    "script_status": "success | error | partial",
    "error": null,
    "llm_read": false,
    "llm_processed": false,
    "retry_count": 0
  },
  "role": "WORKER",
  "work_item": "WI-007",
  "expected_status": "PENDING",
  "sentinel": "[sdp-prompt work_item=\"WI-007\" expected_status=\"PENDING\"]",
  "section_1": "...",
  "section_2": "...",
  "section_3_table": { },
  "section_5_files": [ ],
  "summary": "State is PENDING for WI-007. Dispatching WORKER. No flags. Normal path."
}
```

LLM sets `"llm_read": true` after reading, `"llm_processed": true` after completing
reasoning and writing output. Both fields persist for history. Never overwrite prior
temp files — each invocation produces a new timestamped file.

#### Failure Handling

Three distinct failure modes:

**Mode 1 — Script fails internally (handles its own error):**
Script catches exception, writes temp file with `"script_status": "error"` and error
detail in `"error"` field. LLM reads file, sees error, enters retry logic.

**Mode 2 — Script fails externally (no temp file written):**
PowerShell cannot invoke script (path wrong, permissions, etc.). No temp file. LLM
checks context for script tool output (stderr, exit code). If error info present, use it.

**Mode 3 — No temp file, no context error info:**
Halt and report to user. Cannot determine cause without more information.

**Retry logic (applies to Modes 1 and 2 when error info is available):**
- Attempt to resolve error (fix path, check permissions, correct parameters)
- Re-run script
- `retry_count` in `_meta` increments each attempt (script reads and increments from
  prior temp file if it exists, otherwise starts at 0 in a new file)
- After 3 retries with no success: halt and surface full error history to user

#### Lifecycle Summary

| Event | Action |
|-------|--------|
| Script runs | Creates timestamped file; sets `script_status`, `error`; echoes path to stdout; updates `state.json → active_temp_file` |
| LLM reads file | Sets `llm_read: true` in `_meta` and saves |
| LLM finishes processing | Sets `llm_processed: true` in `_meta` and saves |
| Session ends | File remains — permanent debug artifact |
| Phase advances | New subdirectory; prior phase temp files untouched |
| New invocation of same skill | New timestamped file; prior file is history |

---

### `sdp-project-create-prompt` Hybrid Split (adopted design)

#### Section 4 — Option S4a (adopted)

Section 4 uses a fixed template rather than requiring the LLM to read the phase file:

`"[ROLE] session for [TASK-ID]. Task description is in [phase_file]. Invoke /sdp-[role] to begin."`

Rationale: the dispatched agent reads the phase file as Step 5 of its own role session.
Section 4 only needs to direct it, not summarise the task. Removes 1 tool call (phase file
read) and 1 reasoning step from the happy path.

For known flags (`DIAGNOSIS_BLOCKED`, `PARTIAL_COMPLIANCE_ESCALATE`): script detects these
from state files and appends structured notes to Section 4 in the temp file. LLM only
engages for edge cases the script explicitly flags.

> **Option S4b considered and not adopted for happy path:** LLM reads phase file and writes
> a natural-language task instruction. Retained as the error/flag path only.

#### Step-by-step split

| Step | Owner | Notes |
|------|-------|-------|
| Read `state.json` | Script | |
| Read phase state file | Script | |
| Determine WORKER vs REVIEWER | Script | Branch on task status |
| Compute temp file name | Script | N1 — echo to stdout |
| Fill sections 1, 2, 3, 5 | Script | Template fill from state |
| Fill section 4 | Script | Fixed template; flag-aware |
| Detect known flags | Script | Appends structured notes to temp file |
| Write temp file | Script | |
| Update `state.json → active_temp_file` | Script | |
| Write `sdp-docs/00_prompt.txt` | Script | Assembled from temp file sections |
| Update `state.json` post-write | Script | `last_session`, `active_work_item` |
| Read temp file (verify / edge case) | LLM | Only if script flagged an edge case |
| Handle edge case | LLM | Only on flag path |

**Happy path tool calls: 1** (invoke script). All file I/O handled by script.

---

### Broader Gains — Proposed for Future Implementation

#### `sdp-project-run-prompt` — sentinel parsing script

Script reads `sdp-docs/00_prompt.txt`, parses sentinel line, outputs:
`{"skill": "sdp-project-worker", "work_item": "WI-007", "expected_status": "PENDING"}`

LLM reads output from tool result (zero extra tool calls), invokes the named skill.
Saves 1 tool call + 1 reasoning step per loop iteration.

#### `sdp-project-state-loop` — decision script

Script reads `state.json` + sentinel from `00_prompt.txt` + phase state file. Evaluates
EXECUTE vs GENERATE vs HALT. Handles `eval_cycle_attempts` increment and auto-push check.
Outputs: `{"action": "EXECUTE|GENERATE|HALT", "reason": "...", "work_item": "...", "current_status": "..."}`

LLM reads output and dispatches. Removes the heaviest LLM reasoning step from the loop.
Design separately with explicit acceptance criteria before authoring begins.

#### `sdp-checks.ps1` — unified preflight checks

Single script handles all three COORDINATOR/Phase Gate preflight checks:
- GPG file exists + version matches `gpg_version` in `state.json`
- Superpowers plugin install marker check
- Full skills file list existence check (both Level 1 and Level 2 paths)

Writes structured check results to temp file. LLM reads report and only engages on failures.
Saves 8–12 tool calls at the start of every COORDINATOR and REVIEWER session.

---

### Recommended Implementation Sequence

| Order | Target | Type | Rationale |
|-------|--------|------|-----------|
| 1 | `sdp-project-create-prompt` | Hybrid (script-heavy) | Validates full hybrid pattern; highest loop value |
| 2 | `sdp-checks.ps1` | Full script | High value, low complexity, applies to three session types |
| 3 | `sdp-project-run-prompt` sentinel | Hybrid | Short skill; proves "script parses, LLM acts" cleanly |
| 4 | `sdp-project-state-loop` decision | Hybrid | Highest payoff; design session required first |

`sdp-cancel-auto` (full script, low value) can be done any time — not on critical path.

---

## Diff Against Current Skill/Script Inventory — 2026-07-21

Verified each target in the "Recommended Implementation Sequence" and "Broader Gains" sections
above against the actual `sdp-shared/scripts/` and `sdp-shared/ai-skills/` inventory in this repo.

| Target | Status | Evidence |
|--------|--------|----------|
| `sdp-project-create-prompt` hybrid split | ✅ Implemented | `sdp-shared/scripts/sdp-create-prompt.ps1` implements the design almost exactly as specified above: N1 temp-file naming (`phase{N}-sdp-create-prompt-{timestamp}.json`), a `_meta` block (`script_status`, `error`, `retry_count`), a `sdp-create-prompt-tracking.json` file carrying `active_temp_file` for retry-count persistence across invocations, and Option S4a's fixed-template Section 4. Has its own test file, `sdp-shared/scripts/tests/sdp-create-prompt.Tests.ps1`. |
| `sdp-checks.ps1` unified preflight | ✅ Implemented (renamed) | Shipped as `sdp-shared/scripts/sdp-preflight.ps1` instead of `sdp-checks.ps1`. Broader than proposed: a manifest-driven check engine reading `SDP-Workspace-Setup.json` as declarative data (GPG presence/version, all skill-pair L1+L2 existence, the sdp-tone L1-present/L2-absent invariant, scaffold/config/document-list checks) rather than a hardcoded three-check script. |
| `sdp-project-run-prompt` sentinel parsing | ✅ Implemented | `sdp-shared/scripts/sdp-run-prompt.ps1` resolves the active project from `SDP-Solution.json`, reads `sdp-docs/00_prompt.txt`, parses the sentinel, and emits a JSON result (`resolvedProject`, `skillName`, `selectionReason`) for the Level 1 skill to act on — matches the proposed split exactly. |
| `sdp-project-state-loop` decision script | ❌ Not implemented | No `.ps1` script exists for `sdp-project-state-loop` in `sdp-shared/scripts/`. `.claude/skills/sdp-project-state-loop/SKILL.md` still dispatches straight into the full Level 2 LLM procedure (`sdp-shared/ai-skills/sdp-project-state-loop/SKILL.md`) with no script call — EXECUTE/GENERATE/HALT branching, `eval_cycle_attempts` tracking, and auto-push logic are still LLM-reasoned every fire. No dedicated design doc for this was found under `~SDP-Maintenance/~docs/` — the "design session required first" this doc called for has not happened yet. Still this doc's own highest-payoff, highest-risk open item. |
| `sdp-cancel-auto` full script | ❌ Not implemented | Still a pure Level 2 LLM skill (`.claude/skills/sdp-cancel-auto/SKILL.md` → `sdp-shared/ai-skills/sdp-cancel-auto/SKILL.md`), no script. Consistent with this doc's own prioritization (lowest value, explicitly "not on critical path") — not a gap, just never picked up. |
| Temp-file / `_meta` hybrid pattern, generalized | ⚠️ Partially adopted | The `_meta`/temp-file/retry-count scheme from the 2026-06-19 design session is implemented in `sdp-create-prompt.ps1` only. It was not generalized to the other hybrid-ish scripts that exist today (`sdp-gate-review-finalize.ps1`, `sdp-gate-review-gpg-check.ps1`, `sdp-gate-review-setup.ps1`, `sdp-solution-phase-gate-review-*.ps1`) — those use their own JSON-envelope conventions (`ok`/`failures` shape) rather than this doc's `_meta` block. Whether that's an intentional divergence or an unfinished generalization is not something this doc's own history answers. |

**Net effect on the Recommended Implementation Sequence table above:** items 1–3 are done; item 4
(`sdp-project-state-loop` decision script) is the only genuinely open item from that table, and remains
gated on the design session this doc itself flagged as a prerequisite.
