
## Purpose

Accept a skill name as input, evaluate its L1 shim and L2 SKILL.md for deterministic vs.
LLM-required steps, cross-reference any prior evaluation on record, and produce a structured
recommendation report written to `[eval_dir][skill-name]-eval.md` — `[eval_dir]` depends on
whether the target is an SDP skill or a project skill; see Step 0.

Read-only except for writing the output report. Does not modify skill files, scripts, or manifests.

---

## Inputs

- **Skill name** — passed as the invocation argument; required
- `.claude/skills/[skill-name]/SKILL.md` — L1 shim
- `sdp-shared/ai-skills/[skill-name]/SKILL.md` — L2 procedure (may not exist)
- `sdp-shared/scripts/[skill-name].ps1` — existing script (may not exist)
- `SDP-Project-Evolution.md` — solution root; checked for prior evaluation context
- `~SDP-Maintenance/` — solution root; presence checked only when the target is an SDP skill
  (see Step 0)
- `[eval_dir][skill-name]-eval.md` — prior evaluation report (may not exist); `[eval_dir]`
  resolved in Step 0

---

## Procedure

### Step 0: Classify the Target Skill and Resolve the Eval Directory

SDP skills are the framework's own skills — shipped as part of this workflow system and
always named with the `sdp-` prefix. Project skills are anything else: skills a consuming
project authors for itself. The two are kept in separate eval-report locations so that
`sdp-shared/` — which is copied into every consuming project as part of adopting this
workflow — never carries the framework's own internal eval reports into a project's repo.

1. Confirm a skill name was passed as the invocation argument. If not: halt by invoking
   `/sdp-create-banner icon=error row=0 row: Status | No skill name provided. Invoke as /sdp-evaluate-skill [skill-name].`
2. Check whether `[skill-name]` starts with the literal prefix `sdp-`. If it does: this is an
   **SDP skill**. Otherwise: this is a **project skill**.
3. If it is an SDP skill: determine whether `~SDP-Maintenance` exists at the solution root —
   attempt a `Read` tool call on the bare directory path (a "file does not exist" result means
   absent, any other result means present), not a Bash/PowerShell existence check, and do not
   narrate this check in chat (no "checking for the maintenance folder now" commentary, no
   relaying the raw tool result back to the user). If absent: halt by invoking
   `/sdp-create-banner icon=error row=0 row: Status | '[skill-name]' is an SDP skill (sdp- prefix) but no Maintenance folder exists at the solution root. SDP skill evaluations only run from the SDP framework maintenance workspace.`
4. Set `[eval_dir]` for the remainder of this procedure:
   - SDP skill → `~SDP-Maintenance/~sdp-shared/~skill-evals/`
   - Project skill → `sdp-shared/skill-evals/`

### Step 1: Locate Artifacts

1. Read `.claude/skills/[skill-name]/SKILL.md`. If not found: halt by invoking
   `/sdp-create-banner icon=error row=0 row: Status | .claude/skills/[skill-name]/SKILL.md not found — no L1 shim for this skill. Verify the skill name and retry.`
2. Attempt to read `sdp-shared/ai-skills/[skill-name]/SKILL.md`. If not found: note
   "No L2 SKILL.md found — skill may be fully scripted or L1-only." Continue.
3. Check whether `sdp-shared/scripts/[skill-name].ps1` exists (attempt a Read). If it does:
   read the SYNOPSIS block and note which steps it handles. Record as `existing_script_coverage`.
   If it does not exist: record `existing_script_coverage` as none.
4. Record: `has_l1` (always true at this point), `has_l2`, `has_script`, `existing_script_coverage`.

### Step 2: Cross-Reference Prior Work

1. Read `SDP-Project-Evolution.md` at the solution root. Search for the target skill name.
   If found: extract any decisions, recommendations, or outcomes recorded for this skill.
   Note as `evolution_doc_entry` — present with summary, or absent.
2. Attempt to read `[eval_dir][skill-name]-eval.md` (`[eval_dir]` from Step 0). If it exists:
   note the most recent evaluation timestamp and verdict from the file. Record as
   `prior_eval` — present with date and verdict, or absent.
3. If both are absent: note "No prior evaluation context — proceeding with fresh analysis."
4. If either is present: note what was previously decided. Flag it as context for Step 3 —
   the classification should identify whether the current state matches, diverges from, or
   extends the prior recommendation.

### Step 3: Classify Each Step

If no L2 SKILL.md was found in Step 1: skip this step. Record classification as
`L1-Only` and proceed to Step 5 with verdict `L1-Only`.

For every numbered step and sub-step in the L2 SKILL.md, apply the four tests below in
the listed order. The first LLM-ONLY result on any test ends classification for that step —
do not continue testing remaining tests.

| # | Test | Question | Verdict if yes |
|---|------|----------|----------------|
| 1 | **Context-dependency** | Does this step require the LLM's conversation context — scan recent messages, inspect current turn output, or read agent-held state? | LLM-ONLY |
| 2 | **Judgment** | Does this step require understanding ambiguous state, forming an opinion, generating novel natural-language text, or making a decision not fully determined by structured file inputs? | LLM-ONLY |
| 3 | **Output type** | Does this step produce a subagent spawn, a Skill tool invocation, or user-facing prose that requires natural-language construction? | LLM-ONLY |
| 4 | **Input type** | Does this step consume only structured file data — JSON field reads, regex on known text patterns, path construction, boolean checks, arithmetic? | SCRIPT |

If no test produces a verdict: classify as LLM-ONLY with reason "indeterminate — defaulting to LLM-ONLY."

Record the verdict and a one-line reason for every step and sub-step.

**Parent-step verdict rule (when sub-steps exist):** After classifying all sub-steps, assign the parent step's verdict:
- All sub-steps SCRIPT → parent is `SCRIPT`
- Sub-steps are SCRIPT-leading then LLM-ONLY-trailing with no interleaving → parent is `HYBRID-STEP`
- Any other combination containing at least one LLM-ONLY → parent is `LLM-ONLY`

`HYBRID-STEP` indicates the leading sub-steps are scriptable but the step as a whole requires LLM involvement. Record SCRIPT sub-steps inside a HYBRID-STEP parent as **partial extraction candidates**.

### Step 4: Find the Handoff Boundary

1. Identify the last consecutive SCRIPT-classified step before the first LLM-ONLY step.
   This is the boundary — everything at or before it is the script's domain. The key insight:
   the script's output (JSON written to stdout or a temp file) is already in the LLM's
   context as the tool result — reading it costs zero additional tool calls.
   HYBRID-STEP counts as LLM-ONLY for boundary purposes — the boundary falls before it.
   SCRIPT sub-steps within a HYBRID-STEP are noted as partial extraction candidates; they
   are scriptable only with an explicit mid-step hand-off design.
2. Identify the boundary case:
   - **No boundary** — all steps are LLM-ONLY: note "fully LLM-required — no script boundary."
   - **Boundary at final step** — all steps are SCRIPT: note "fully scriptable."
   - **Boundary in the middle** — hybrid: note the step number where the boundary falls.
3. If an existing script already covers some steps: compare its coverage against the boundary.
   - Coverage reaches the boundary: note "existing script coverage complete."
   - Coverage stops before the boundary: note "gap — steps [N] through [M] not yet scripted."
   - Coverage extends past the boundary: note "existing script covers more than the
     deterministic boundary — verify LLM-ONLY steps are handled correctly."

### Step 5: Compute Savings and Assign Risk Tier

**Tool call savings:**
1. For each SCRIPT-classified step: count the tool calls it currently costs in the LLM path
   (each Read tool call = 1; each Write tool call = 1; JSON parsing or arithmetic = 0).
   These are **primary savings** — achievable with a standard script boundary.
2. For each HYBRID-STEP: count the tool calls in its SCRIPT-classified sub-steps separately.
   These are **partial savings** — achievable only with an explicit mid-step hand-off design.
   Do not include them in the primary savings total.
3. A script collapses all primary SCRIPT steps to 1 tool call total.
4. Primary savings per invocation = (sum of tool calls in full SCRIPT steps) - 1.
5. Identify how many times this skill is typically invoked per workflow run (e.g., sdp-tone
   is called twice per skill invocation × 10 skills = 20× per run). Multiply to estimate
   per-run savings. State any assumptions made.

**Risk tier — assign based on what a script error or wrong output would cause:**

| Tier | Condition |
|------|-----------|
| **Cosmetic** | Failure produces silence or missing output; the workflow continues without consequence |
| **Recoverable** | Failure is detectable from the tool result; LLM can fall back to performing the step manually |
| **Blocking** | The skill cannot proceed to its LLM steps without a valid script result |
| **Corrupting** | Wrong script output could cause an incorrect action — wrong dispatch, wrong status written, misrouted loop — without the LLM detecting the error |

### Step 6: Write the Evaluation Report

1. If `[eval_dir]` (from Step 0) does not exist: create it.
2. If `[eval_dir][skill-name]-eval.md` does not exist: create it with this
   header (written once, never repeated):
   ```markdown
   # Skill Evaluation: [skill-name]
   ```
3. Append a new evaluation entry using the format below. Do not edit or remove prior entries.

```markdown
## Evaluation — [YYYY-MM-DD HH:MM]

**Artifacts present:** L1: yes | L2: [yes/no] | Script: [yes — path / no]
**Prior evaluation:** [none | [date] — [verdict]]
**Evolution doc entry:** [none | [summary of what was recorded]]

### Step Classification

| Step | Description | Verdict | Reason |
|------|-------------|---------|--------|
| 1    | [brief description] | SCRIPT / LLM-ONLY / HYBRID-STEP | [one-line reason] |

### Handoff Boundary

[One sentence: where the script ends and the LLM begins, or "none — fully scriptable /
fully LLM-required."]

**Existing script coverage vs. boundary:** [complete / gap — steps N–M not yet scripted / no script]

### Savings Estimate

| Metric | Value |
|--------|-------|
| Tool calls in full SCRIPT steps (primary, current LLM path) | N |
| Tool calls in SCRIPT sub-steps of HYBRID-STEPs (partial) | N |
| Tool calls after scripting (primary) | 1 |
| Primary savings per invocation | N−1 |
| Typical invocations per workflow run | N |
| Estimated primary savings per workflow run | N tool calls |

Assumptions: [list any]

### Risk Assessment

**Tier:** [Cosmetic / Recoverable / Blocking / Corrupting]
**Reason:** [one sentence explaining what breaks on script failure or wrong output]

### Proposed Script Output Contract

[Only present if SCRIPT-classified steps exist. JSON schema for the script's stdout output.]

```json
{
  "status": "success | error",
  "error": null,
  ...fields the LLM reads to proceed...
}
```

### Proposed L2 SKILL.md Structure Post-Scripting

[Only present if verdict is Hybrid or Full-Script. Numbered steps only — no full prose.
Shows what the updated L2 would look like after the script replaces its steps.]

### Verdict

**[Full-Script | Hybrid | LLM-Only | L1-Only | Already-Complete | Extend-Existing-Script]**

### Recommendation

**[implement-now | design-session-first | no-change]**

[One paragraph rationale: why this verdict, what would be needed to implement, what the
risk/reward tradeoff is.]

### Delta from Prior Evaluation

[Only present if a prior evaluation exists. What has changed since the last evaluation —
new steps added, existing steps modified, script coverage extended, or recommendation unchanged.]
```

4. Report to user: "Evaluation complete — report written to
   `[eval_dir][skill-name]-eval.md`."

---

## Constraints

- Read-only except for creating `[eval_dir]` and writing/appending to
  `[eval_dir][skill-name]-eval.md`, where `[eval_dir]` is `sdp-shared/skill-evals/` for project
  skills or `~SDP-Maintenance/~sdp-shared/~skill-evals/` for SDP skills (see Step 0).
- Do not modify any skill file, script, or manifest.
- Do not implement any recommendation — produce analysis only.
- Never combine steps into a single verdict — classify every step and sub-step individually.
- Never omit stated assumptions when invocation frequency is estimated; savings estimates
  must count actual tool calls, not approximations.
- Never silently override a prior evaluation record — if a prior evaluation exists and the
  new classification contradicts it, note the contradiction explicitly in the Delta section.

---

## Outputs

- `[eval_dir][skill-name]-eval.md` — new file (first run) or appended entry (subsequent runs).
  `[eval_dir]` is `sdp-shared/skill-evals/` for project skills or
  `~SDP-Maintenance/~sdp-shared/~skill-evals/` for SDP skills (see Step 0). Append-only —
  prior entries are never edited or removed.
- One-sentence confirmation to the user with the report file path.
