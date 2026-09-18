## Purpose

Deterministic loop guard for a recurring `/loop` session driving the solution's own phases 1-7
(Concept through Phase Readiness). Each fire: check for interactive-checkpoint conditions that
require a live user session, triage any existing halt/block or newly-discovered non-blocking
item as mechanical or judgment (mechanical: reuses Material Decision Escalation's own triggers
as the judgment anchor — anything tripping either of those, or changing scope/behavior/
acceptance criteria, is judgment; everything else is mechanical), attempt a bounded fix for
mechanical findings, then evaluate the phases-1-7 dispatch sentinel and dispatch a single
action — or stop if judgment is required. This skill never handles post-Phase-7 dispatch
(`sdp-solution-state-loop`'s exclusive job) or project-level dispatch
(`sdp-project-state-loop`'s exclusive job).

## Inputs

- Current conversation context (API error scan only — no file tools)
- `.sdp-solution-workflow/state.json` — `workflow_status`, `halt_reason`, `current_phase`,
  `phase_gate` (`status`, `gate_review_attempts`), `last_session`, and this skill's own private
  bookkeeping field `phase_loop_mechanical_resolution` (read and written across Steps 5 and 7)
- `.sdp-solution-workflow/registry.md` — Phase File column and phase-type (via the ` — `
  disambiguation-suffix convention) for the row matching `current_phase`
- `SDP-Solution.json` — `projects[]`, for the Architecture-phase web-project-type check
- Phase state file `sdp-solution-docs/[phase_file]_state.json` — the `tasks` map (keyed by
  TASK-ID per `SDP-Workspace-Setup.md`'s schema), each entry's `status`, `last_session`,
  `eval_cycles`, `eval_cycle_attempts` (this skill's own field, added alongside the existing
  ones), flags
- `sdp-solution-docs/00_solution_prompt.txt` — sentinel line only (first line read); the
  sentinel's optional 4th `model="..."` attribute, when present, is the model this skill's own
  Step 7 EXECUTE branch passes to the Agent tool for the subagent spawn
- `.sdp-solution-workflow/sessions/session-[N].md` — `Role:`/`Work Item:` fields (dispatch-file
  integrity check) and the prior session's `Phase Document:` field (to resolve which phase
  document's blockquote to check for non-blocking discoveries — see Step 4)
- `sdp-solution-docs/[phase_file]` (the phase document) — the most recently appended
  Completed/Eval/Verified blockquote's `**Issues:**` sub-heading, if present (non-blocking
  discovery consumption; Step 4)
- `SDP-Config.json` — `autoResolveHalt.evalCycleAttemptThreshold` (default 2),
  `solutionPhaseLoop.autoResolveMechanicalFindings.enabled` (default true)
- `.sdp-solution-workflow/logging/loop-logs/loop-metrics-*.jsonl` — write-only, append-only fire
  log (final step). One file per calendar day, same file `sdp-project-state-loop` and
  `sdp-solution-state-loop` already share.

## Procedure

### Step 1: API Error Pre-Check

Scan only the **most recent 10 lines** of the current conversation context for the literal
text `API Error: ` (with the colon and trailing space). If fewer than 10 lines are available,
scan all available lines.

- If found: record **action = API_RECOVERY**. Skip Steps 2-6 entirely — proceed to Step 7,
  whose API_RECOVERY branch is this action's actual handler (tone, banner, a
  coordinator-determining subagent).
- If not found: proceed to Step 2.

### Step 2: Read Solution State

1. Read `.sdp-solution-workflow/state.json`. If the file cannot be read: invoke
   `/sdp-create-banner icon=warning row=0 row: Status | .sdp-solution-workflow/state.json not found or unreadable — no dispatch.`
   Record `action = STOP`, `reason = "state.json not found or unreadable"`. Proceed to Step 8.
2. Record `workflow_status`, `halt_reason`, `current_phase`, `phase_gate.status`,
   `phase_gate.gate_review_attempts` (absent treated as 0), `last_session`.
3. If `current_phase` is `null`: this solution's phases 1-7 are either not yet started or
   already complete — either way, nothing for this loop to dispatch (post-Phase-7 dispatch is
   `sdp-solution-state-loop`'s job, not this skill's). Invoke
   `/sdp-create-banner icon=info row=0 row: Status | current_phase is null — nothing for sdp-solution-phase-state-loop to dispatch this cycle.`
   Record `action = STOP`, `reason = "current_phase is null"`. Proceed to Step 8.
4. If `workflow_status` is `"halted"`: proceed directly to Step 5 (Halt/Block Classification) —
   do not evaluate the interactive-checkpoint peek (Step 3 below) against a state that is
   already halted; that peek only matters when deciding whether a *new* dispatch is safe to
   make.

### Step 3: Interactive-Checkpoint Peek

Runs only when `workflow_status` is not `"halted"` (a halted state routes to Step 5 instead,
per Step 2 sub-step 4). Phase 1 (Concept) and Phase 3 (Expanded Concept) require a live
`/brainstorming` session between COORDINATOR and the user (bootstrap doc, "Phase 1 / Phase 3 —
Interactive Capture Mechanics"). Phase 4 (Architecture) requires a live 3-question batch
whenever the solution includes a web project type (bootstrap doc, 2026-08-23 Addition). Neither
can run unattended.

1. Read `.sdp-solution-workflow/registry.md`. Find the row whose Phase column equals
   `current_phase` exactly. Determine phase-type: the row's Phase column value equals a
   canonical name exactly, or starts with that name followed by `" — "` (the disambiguation
   convention `sdp-solution-new-concept-intake` Step 4 item 2 uses for every cycle, including a
   solution's first and only one) — never compare by exact string equality against the bare
   canonical name alone.
2. Read the phase state file `sdp-solution-docs/[phase_file]_state.json` (Phase File column
   value from the matched row, `.md` replaced by `_state.json`). Determine whether this phase
   currently has any WORKER-shaped work outstanding: the file does not exist, its `tasks` map
   has no entries at all, or at least one task's `status` is anything other than `"VERIFIED"`
   (`PENDING`, `WORK_COMPLETE`, `REJECTED`, or any other non-`VERIFIED` value all count). This
   is deliberately broader than "first-ever dispatch": the bootstrap doc's own interactive-
   capture requirement ("Phase 1 / Phase 3 — Interactive Capture Mechanics") and cookie-consent
   batch requirement ("before WORKER drafts this cycle's Architecture phase document, the
   acting session asks the user...") both apply to *every* WORKER dispatch into these phase
   types, not only the first — a REJECTED-redo WORKER dispatch still needs the same live
   session, and neither requirement is gated on dispatch order in
   `sdp-solution-phase-coordinator`'s own text. This check does not need to determine which task
   or whether WORKER specifically is next — only whether WORKER-shaped work could still be
   pending — so it stays a conservative, safe-to-over-defer signal without re-deriving
   `sdp-solution-phase-coordinator`'s own REJECTED-priority/all-VERIFIED-before-GATE_REVIEWER
   dispatch-target algorithm. If no WORKER-shaped work is outstanding (every task, if any exist,
   is `VERIFIED`): skip to Step 4 — the next dispatch, if any, is REVIEWER or GATE_REVIEWER,
   neither of which either interactive requirement applies to.
3. **WORKER-shaped work outstanding, and phase-type is Concept or Expanded-Concept:** defer.
   Invoke
   `/sdp-create-banner icon=warning row=0 row: Status | sdp-solution-phase-state-loop: [current_phase] requires an interactive /brainstorming capture session — run /sdp-solution-phase-coordinator directly to continue. No dispatch this cycle.`
   Record `action = STOP`, `reason = "[current_phase] has WORKER-shaped work outstanding and requires interactive brainstorming capture"`.
   Proceed to Step 8.
4. **WORKER-shaped work outstanding, and phase-type is Architecture, and the solution includes
   a web project type:** defer, same shape. Read `SDP-Solution.json`'s `projects[]` array. A
   project is
   treated as web-rendering if its `path` (the `sdp-project_[AppName].[Type]` folder name) ends
   in one of: `.Website`, `.Web`, `.WebApp`, `.WebFrontend`, `.Blazor`, `.Frontend` (matched
   case-insensitively against the final dot-segment). This is a conservative approximation of
   `sdp-solution-phase-coordinator`'s own agent-judgment check (no structured `type` field
   exists anywhere in this codebase — confirmed by search) — if any registered project's suffix
   doesn't match this list but is genuinely web-rendering under a different naming choice, the
   loop will incorrectly skip deferring for it; this is a known, accepted gap in the conservative
   direction only when a project's own naming deviates from the documented convention, never a
   false positive that blocks a non-web solution. Invoke
   `/sdp-create-banner icon=warning row=0 row: Status | sdp-solution-phase-state-loop: Architecture has WORKER-shaped work outstanding and requires the cookie-consent question batch (a web project type is registered) — run /sdp-solution-phase-coordinator directly to continue. No dispatch this cycle.`
   Record `action = STOP`, `reason = "Architecture has WORKER-shaped work outstanding and requires the cookie-consent interactive batch"`.
   Proceed to Step 8.
5. Neither condition applies: proceed to Step 4.

### Step 4: Non-Blocking Discovery Consumption

1. If `last_session` (from Step 2) is absent, null, or `"none"`: no prior session to consume —
   proceed to Step 5.
2. Read `.sdp-solution-workflow/sessions/session-[last_session].md` in full (a short template
   file — reading it fully, not just a line, is the same documented exception
   `sdp-project-state-loop`'s own dispatch-file integrity check already takes) — needed only to
   resolve this session's `Phase Document:` field. The session file itself is write-once by
   `sdp-solution-phase-coordinator` at solution-phase scope: WORKER, REVIEWER, and GATE_REVIEWER
   never write back to it for anything (confirmed by direct search of all three skills — none
   references the session file as a write target) — their own outcome narrative always goes to
   the phase document's Completed/Eval/Verified blockquotes instead. So `Issues:` is never
   looked for in the session file itself; read the phase document
   `sdp-solution-docs/[phase_file]` (the `Phase Document:` value just resolved) and find its
   most recently appended blockquote of **any** type — Completed, Eval, Verified, or Gate
   Verdict (`sdp-solution-phase-gate-review`'s own `> **Gate Verdict — ...**` block) — whichever
   is last in append order. Checking all four types, not just the first three, matters: since
   this loop dispatches one role at a time against an append-only document, the last blockquote
   of *any* type is always the one the session just consumed wrote — narrowing the check to
   three types would make a GATE_REVIEWER fire's last blockquote invisible to this scan, falling
   back to an older, already-consumed Completed/Eval/Verified blockquote instead and risking a
   spurious re-dispatch for an item already resolved. **If the last blockquote is a Gate
   Verdict:** treat this exactly like "no blockquote has an `**Issues:**` sub-heading" below —
   nothing to consume, proceed to Step 5. GATE_REVIEWER is never asked to report `Issues:` at all
   (see Step 7 EXECUTE sub-step 1's own scoping) — its role is a compliance verdict against fixed
   gate criteria, not surfacing new non-blocking discoveries, and its blockquote's own fixed
   verdict format has no natural place for an ad-hoc sub-heading the way WORKER/REVIEWER's
   free-form narrative blockquotes do. If the session
   file cannot be read, has no `Phase Document:` field, the phase document cannot be read, has
   no blockquote at all, or the last blockquote (of any type) has no `**Issues:**` sub-heading
   (or the sub-heading is empty): nothing to consume — proceed to Step 5.
3. For each bulleted item under that blockquote's `**Issues:**` sub-heading: classify per the
   rule in Step 5 sub-step 2 below.
4. If every item classifies as mechanical: merge these items into the mechanical-fix item list
   Step 5 sub-step 5 builds, then proceed to **Step 5 sub-step 1 first, not sub-step 5 directly**
   — sub-step 1's `phase_loop_mechanical_resolution.status == "escalated"` bullet is the only
   place a stale cap-exceeded halt from an earlier cycle gets caught, and it must not be
   bypassed just because `workflow_status` itself isn't currently `"halted"` (a human can clear
   `workflow_status` without touching `phase_loop_mechanical_resolution`, per Step 5 sub-step 1's
   own note). If sub-step 1 does not match (the common case): proceed through sub-step 3 (the
   `solutionPhaseLoop.autoResolveMechanicalFindings.enabled` kill switch — a Step-4-discovered
   item is still subject to it, same as any other mechanical item) directly to sub-step 5,
   skipping sub-step 2 (this item was already classified in sub-step 3 above) and sub-step 4
   (the halted-entry catch-all — not applicable to a content discovery, which is never a halted
   entry).
5. If any item classifies as judgment: this is a real halt, not a one-fire pause — set
   `workflow_status = "halted"` and `halt_reason = "judgment-classified discovery in
   [phase_file]'s latest blockquote Issues field: [item description]"` in
   `.sdp-solution-workflow/state.json`. Setting `workflow_status` (rather than only recording
   `action = STOP` for this one fire) is required: nothing else advances `last_session`, so a
   fire that only recorded `STOP` without halting would re-read this same blockquote and
   repeat the identical STOP on every subsequent fire forever, never surfacing as a real,
   human-visible halt the way every other halt in this skill does. Invoke
   `/sdp-create-banner icon=error row=0 row: Status | sdp-solution-phase-state-loop: [halt_reason] — judgment required, no auto-resolution attempted.`
   Record `action = STOP`, `reason = halt_reason`, `halted = true` for Step 8's metrics. Proceed
   to Step 8.

**Requesting the report:** this sub-step only ever finds something if the dispatched role was
actually asked to report non-blocking discoveries. Step 5 sub-step 5 (mechanical-fix dispatches,
which this skill authors directly) and Step 7 EXECUTE sub-step 1 (normal, coordinator-authored
dispatches) both carry an `Issues Reporting:` field for exactly this reason — see those steps.
Neither touches `sdp-solution-phase-worker`/`-reviewer`/`-gate-review` — the request rides in
the dispatch content those skills already read as ordinary task instructions, the same way
`Fix Focus:` already does (that field is also nowhere named in any of those three skills' own
text, confirmed by search, and this design already depends on it working).

### Step 5: Halt/Block Classification

Runs when `workflow_status` is `"halted"` (routed here directly by Step 2 sub-step 4 — call this
the **halted entry**), or when Step 4 sub-step 4 hands off mechanical items found in the phase
document's `**Issues:**` sub-heading (call this the **discovery entry**; `workflow_status` is never
`"halted"` on this path, since Step 2 sub-step 4 already routed a halted state away from Step 3
and Step 4 before either could run). This distinction matters for every sub-step below: a
**halted entry** means a real, already-active halt exists and this fire must not dispatch
anything — every sub-step 1 bullet reached this way ends in a full `STOP`. A **discovery entry**
means `workflow_status` is currently `"active"` and this fire is only deciding what to do about
one newly-found item — a bullet reached this way that finds it cannot act on that specific item
must still let the rest of this fire's ordinary dispatch proceed (fall through to Step 6),
rather than stopping the whole fire over something unrelated to the phase's own progress. A third
case also reaches this step: Step 4 sub-steps 1 and 2 both route here when there was no prior
session, or the phase document's latest blockquote has no `**Issues:**` sub-heading (or it's
empty) — a **no-op passthrough**, not
a discovery entry. Every sub-step below is scoped to the halted entry, the discovery entry, or
both; none of them match a no-op passthrough, so it falls through this entire step untouched and
reaches Step 6 exactly as if Step 4 had found nothing to act on — which is the correct behavior
for it.

1. **Judgment, by definition — no fix attempted:**
   - `halt_reason` traces to a Material Decision Escalation halt (the halt text names an
     unsettled external dependency or a GPG-silent architectural pattern — this is the same
     halt any `Material Decision Escalation Check` step across the phases-1-7 role skills
     already produces, unmodified). **Halted-entry only** — this bullet's condition can never be
     true on a discovery entry, since `halt_reason` is only meaningful while `workflow_status`
     is `"halted"`.
   - `halt_reason` traces to `PARTIAL_COMPLIANCE_ESCALATE` or a `DIAGNOSIS_BLOCKED`-equivalent
     condition for a solution-phase task. **Halted-entry only**, same reason as above.
   - `phase_gate.status` is `"blocked"` and the current phase's own document
     (`sdp-solution-docs/[phase_file]`) carries a `**Remediation Proposals:**` heading in its
     most recent `GATE_BLOCKED` verdict (Phase Readiness Regression — per the bootstrap doc,
     "every regression gets a human decision regardless of count"). **Halted-entry only**, same
     reason.

   Any of the three bullets above matching: invoke
   `/sdp-create-banner icon=error row=0 row: Status | sdp-solution-phase-state-loop: [halt_reason] — judgment required, no auto-resolution attempted. No dispatch this cycle.`
   Record `action = STOP`, `reason = halt_reason`, `halted = true` for Step 8's metrics. Proceed
   to Step 8.

   - `phase_loop_mechanical_resolution.status` is `"escalated"` for `current_phase` (a prior
     fire already exhausted the mechanical-fix attempt cap for this phase and halted). This
     bullet can match on **either** entry, since it does not depend on `halt_reason`:
     - **Halted entry:** the halt this status caused is still active — invoke the same banner
       and `STOP` as above, recording `halted = true` for Step 8's metrics the same way.
     - **Discovery entry:** the phase's mechanical-fix cap was already hit on an earlier cycle,
       but `workflow_status` has since been cleared by a human — this specific new item cannot
       start another mechanical-fix cycle for this phase, but that must not block the phase's
       own ordinary dispatch. Append to `auto_actions` in `.sdp-solution-workflow/state.json`:
       `{"timestamp": "[ISO timestamp]", "trigger": "mechanical discovery", "action": "deferred
       - phase already at mechanical-fix cap", "phase": "[current_phase]", "items": [the
       newly-discovered items, verbatim]}` — the only durable trace once `last_session` advances
       past this item. Invoke
       `/sdp-create-banner icon=warning row=0 row: Status | sdp-solution-phase-state-loop: [current_phase] already hit its mechanical-fix cap on an earlier cycle — new discovery deferred, not auto-fixed. Proceeding with ordinary dispatch.`
       Do **not** record an action here — proceed to Step 6 as if Step 5 had found nothing to
       act on. (`halted` stays `false` for this fire, per Step 8's default — `workflow_status`
       is not halted on a discovery entry.)
2. **Classification rule** (applied to every Step 4 discovery item): judgment = the item trips
   either Material Decision Escalation trigger (unsettled external dependency, or an
   architectural pattern with no GPG precedent), **or** its resolution would change scope,
   user-facing behavior, or acceptance criteria in any way. Mechanical = everything else, where
   exactly one resolution is already implied by settled
   `.speq`/concept/research/expanded-concept/architecture content for this cycle.
3. **(Discovery-entry only** — Step 4 sub-step 4 routes a discovery here on its way to sub-step
   5; a halted entry that missed sub-step 1 must reach sub-step 4's catch-all instead, never
   this check, since this sub-step's own `halt_reason` text below would otherwise overwrite
   whatever real halt condition already existed.**)** If
   `solutionPhaseLoop.autoResolveMechanicalFindings.enabled` is `false` in `SDP-Config.json`:
   a discovered mechanical item cannot be auto-fixed this run — set `workflow_status = "halted"`
   and `halt_reason = "solutionPhaseLoop.autoResolveMechanicalFindings disabled — mechanical
   discovery in [phase_file]'s latest blockquote requires manual review: [item description]"` in
   `.sdp-solution-workflow/state.json` (a real halt, for the same reason Step 4 sub-step 5's
   judgment path does — without halting, the same discovery would silently repeat every fire).
   Invoke
   `/sdp-create-banner icon=warning row=0 row: Status | sdp-solution-phase-state-loop: [halt_reason]`
   Record `action = STOP`, `reason = halt_reason`, `halted = true` for Step 8's metrics. Proceed
   to Step 8.
4. **Halted-entry catch-all** (**halted-entry only** — reached whenever sub-step 1 did not
   match): no bullet in sub-step 1 matched this halt's `halt_reason` or
   `phase_loop_mechanical_resolution` state. This is either an upstream halt this skill did not
   author (Material Decision Escalation, `PARTIAL_COMPLIANCE_ESCALATE`, `DIAGNOSIS_BLOCKED`, and
   Phase Readiness Regression are already excluded by sub-step 1's own three bullets — this
   covers, among others, a WORKER precondition halt such as a missing GPG file, and possibly an
   ordinary non-Phase-Readiness `GATE_BLOCKED` verdict too, if that also sets `workflow_status` —
   `sdp-solution-phase-coordinator`'s own text does not settle this either way, and this sub-step
   does not need it settled: whatever produced the halt, it lands here), or a re-detection of this skill's own
   judgment-discovery halt (Step 4 sub-step 5), kill-switch halt (sub-step 3 above), or Step 7
   REPAIR's failed-repair halt on a later fire (none of those three write a `halt_reason` shaped
   like sub-step 1's three named conditions either).

   **This skill never attempts to auto-resolve a halt it did not diagnose itself.** The only
   condition this skill ever self-diagnoses is
   `phase_loop_mechanical_resolution.status == "escalated"` (sub-step 1's own escalated bullet),
   and that condition means REVIEWER *did* run and produced a REJECTED verdict, twice — a
   content/judgment failure that no `git push` could ever fix, unlike
   `sdp-project-state-loop`'s own analogous stuck-loop trigger
   (`eval_cycle_attempts - eval_cycles >= haltThreshold`, meaning REVIEWER was *dispatched but
   never produced a verdict* — a symptom unpushed commits genuinely can cause). There is no
   condition in this skill that a `git push` could ever plausibly resolve, so no auto-push
   branch exists here at all — auto-resolving an arbitrary halted entry (this skill's own
   cap-exceeded halt, or any upstream halt of unknown cause) would risk silently clearing a
   genuinely human-gated condition, a Core Invariant #2 violation. Invoke
   `/sdp-create-banner icon=error row=0 row: Status | sdp-solution-phase-state-loop: [halt_reason] — halted, no auto-resolution attempted. Manual intervention required.`
   Record `action = STOP`, `reason = halt_reason`, `halted = true` for Step 8's metrics.
   Proceed to Step 8.
5. **Content-gap conditions** (**discovery-entry only** — every `GATE_BLOCKED` verdict sets
   `phase_gate.status` to `"blocked"`, Phase Readiness Regression or not; it is sub-step 1
   bullet 3's own `**Remediation Proposals:**`-heading check, not the status value itself, that
   scopes that bullet to Phase Readiness Regressions specifically. Whether an ordinary
   non-Phase-Readiness `GATE_BLOCKED` also sets `workflow_status = "halted"` is not settled by
   `sdp-solution-phase-coordinator`'s own text (its Step 2e item 4 is not explicit either way) —
   this sub-step does not depend on the answer: if it does, that halted entry falls through
   sub-step 1 to sub-step 4's catch-all, same as any other unmatched halt; if it does not, it
   never reaches Step 5 as a halted entry at all. Either way, every halted-entry case this skill
   can encounter is exhausted by sub-steps 1-4 above): read
   `.sdp-solution-workflow/state.json`'s `phase_loop_mechanical_resolution` field.

   - **Absent, present with `status: "resolved"`, or present for a `phase` other than
     `current_phase`:** this is a fresh mechanical-fix cycle. The third condition (a record for a
     different phase, in any status including `"escalated"`) is a **stale record, not a live
     one** — `current_phase` has advanced since that record was written (its own owning phase
     already resolved its cap or was cleared by a human and moved on), so it is overwritten by
     the fresh cycle below exactly like an absent record. Without this third condition, a
     discovery in the phase *after* one that hit `"escalated"` would match neither this branch
     nor the next (which is scoped `for current_phase`), leaving the fire's control flow
     undefined — and separately, `"escalated"` would never clear for its own phase either, since
     nothing else ever transitions it away from `"escalated"`.

     Per `SDP-Workspace-Setup.md`'s phase state file schema, `tasks` is a map keyed by TASK-ID
     (`{"tasks": {"[TASK-ID]": {"status", "eval_cycles", "last_session", "flags"}}}`) — a single
     phase can hold more than one independently-tracked task. `phase_loop_mechanical_resolution`
     must therefore identify which task this cycle targets, not only which phase. The discovery
     items themselves carry no TASK-ID (neither the session dispatch template nor the
     `**Issues:**` sub-heading does), so the task is bound by **state-file read-back after WORKER's own dispatch
     returns**, never selected at write time here — selecting which task to act on is this
     skill's own forbidden territory (Constraints), but reading back which task a dispatch that
     already happened actually touched is a plain Core Invariant 7 state read.

     Write `phase_loop_mechanical_resolution = {"phase": "[current_phase]", "task": null,
     "dispatch_session": [N], "items": [the classified mechanical items, verbatim], "attempts":
     1, "status": "fix_dispatched"}`, where `[N]` is the session number this sub-step is about to
     write below — `task` starts `null` because the specific task isn't knowable until the
     WORKER dispatch this fire creates actually runs and records its own `last_session`; Step 7's
     EXECUTE branch (dispatched later in this same fire — sub-step 5 routes straight into it, not
     a later one) spawns that WORKER, and its own sub-step 3 binds `task` once the subagent
     returns, which is also where
     `eval_cycle_attempts: 1` gets written to the now-bound task's own entry in the `tasks` map —
     not here, since which entry to write is exactly what isn't known yet at this point. That
     field is a new loop-owned field there, alongside the existing `status`/`eval_cycles`/`flags`
     fields `sdp-solution-phase-worker`/`-reviewer` already own and never touch (their own
     Constraints already disclaim writing it) — an informational mirror only; the cap check in
     sub-step 6 below compares `phase_loop_mechanical_resolution.attempts`, not this field. Write
     `.sdp-solution-workflow/sessions/session-[N].md` directly (incrementing `last_session`,
     mirroring the exception `sdp-solution-phase-coordinator` Step 2a item 4 already exercises)
     with `Role: WORKER`, `Pipeline: [only when current_phase carries a disambiguating suffix —
     the matched registry row's Phase-column text, plus the same "one of N concurrent cycles"
     sentence sdp-solution-phase-coordinator's own template uses; omit this line entirely when
     current_phase matches a canonical phase name exactly]`, `Work Item: [current_phase]`,
     `Phase Document: [phase_file]`, `Solution State File: .sdp-solution-workflow/state.json`,
     an added `Fix Focus:` field listing the items verbatim, and an `Issues Reporting:` field
     (identical text to Step 7 EXECUTE sub-step 1's own `Issues Reporting:` field — see that
     step for the exact wording). Write `sdp-solution-docs/00_solution_prompt.txt` directly with
     the phases-1-7 sentinel shape
     (`[sdp-solution-prompt current_phase="[current_phase]" expected_status="[phase_gate.status]" role="WORKER"]`)
     and the same five-section body `sdp-solution-create-prompt` writes for a WORKER dispatch,
     with both the `Fix Focus:` and `Issues Reporting:` content carried into Section 4's Task
     Instruction paragraph, alongside the copies already written into the session file above —
     this skill controls both files for a mechanical-fix dispatch, so duplicating both fields
     into the subagent's own starting prompt costs nothing and only adds reliability; WORKER's
     own Step 2 already reads the whole session file regardless (the same channel `Fix Focus:`
     has always relied on, confirmed nowhere named in `sdp-solution-phase-worker`'s own text —
     this duplication is reinforcement, not the only path either field travels through). Append to
     `auto_actions` in `.sdp-solution-workflow/state.json`: `{"timestamp": "[ISO timestamp]",
     "trigger": "mechanical discovery", "action": "mechanical fix dispatched", "phase":
     "[current_phase]", "items": [the classified items, verbatim], "attempt": 1}` — the audit
     trail for this cycle's own history, mirroring the `auto_actions` convention
     `sdp-project-state-loop`/`sdp-solution-state-loop` already use for their own automated
     actions. Invoke
     `/sdp-create-banner icon=in-progress row=0 row: Status | sdp-solution-phase-state-loop: mechanical fix attempt 1 — dispatching WORKER for [current_phase]: [items summary].`
     Record `action = EXECUTE`, `reason = "mechanical fix attempt 1"`. Proceed directly to Step
     7's EXECUTE branch (Step 6 is skipped this fire — the dispatch was just written directly).
     This is a genuinely fresh dispatch, distinct from a *retry* of an already-rejected attempt
     — this sub-step never initiates a retry itself; see sub-step 6's note on why.
   - **Present with `status: "fix_dispatched"` for `current_phase`:** a mechanical-fix cycle for
     this phase is already in flight from an earlier fire — do not start a second one. The
     newly-discovered item(s) are not merged into the in-flight cycle (a known, accepted
     limitation — a phase with a mechanical-fix cycle already running does not currently support
     folding in a second, independently-discovered item mid-cycle; parked for a future revision,
     not attempted here). This is a scheduling constraint, not a reason to stop the fire — the
     in-flight cycle still needs its own dispatches to proceed via Step 6/7. Append to
     `auto_actions` in `.sdp-solution-workflow/state.json`: `{"timestamp": "[ISO timestamp]",
     "trigger": "mechanical discovery", "action": "deferred - cycle already in flight", "phase":
     "[current_phase]", "items": [the newly-discovered items, verbatim]}` — without this, the
     item is otherwise never recorded anywhere once `last_session` advances past it; this is the
     only durable trace a human has that it was ever found. Invoke
     `/sdp-create-banner icon=warning row=0 row: Status | sdp-solution-phase-state-loop: mechanical-fix cycle already in flight for [current_phase] — newly discovered item(s) deferred, not merged this cycle.`
     Do **not** record an action here — proceed to Step 6 as if Step 5 had found nothing to act
     on, exactly as the discovery-entry branch of sub-step 1's `"escalated"` bullet does.
6. **Attempt cap check.** Applied by Step 7 EXECUTE sub-step 3, immediately after a REVIEWER
   dispatch (however it was dispatched — see that sub-step) returns with a verdict for a task
   `phase_loop_mechanical_resolution` is currently tracking. This sub-step decides the outcome
   and updates state; the caller (always Step 7 sub-step 3) records `action = EXECUTE` using the
   `reason` text produced below, then **continues through Step 7 sub-step 4 (sentinel reset) to
   Step 8** — never straight to Step 8. Step 7 sub-step 4's own "every role dispatch, every
   outcome, no exceptions" already covers this path (it is reached via sub-step 3's
   Mechanical-fix branch, one of that sub-step's two branches, both of which lead to sub-step 4);
   this sub-step's own instruction restates it because skipping the reset here specifically would
   silently break the guarantee the rest of this mechanism depends on — see the note below.

   **Why the comparison uses `phase_loop_mechanical_resolution.attempts` directly, not a
   `eval_cycle_attempts - eval_cycles` delta:** unlike `sdp-project-state-loop`'s stuck-loop
   detection — where `eval_cycle_attempts` counts REVIEWER *dispatches* and `eval_cycles` counts
   *completed* evals, so the delta measures dispatches that never produced a verdict (a
   genuine stuck signal) — every mechanical-fix REVIEWER dispatch here *does* complete with a
   verdict (`sdp-solution-phase-reviewer` increments `eval_cycles` on every verdict, REJECTED
   included), so that delta would stay constant at 0 forever and never reach the threshold.
   `phase_loop_mechanical_resolution.attempts` counts fix attempts directly and monotonically,
   so it is the correct counter for this cap.

   **Why a REJECTED-under-cap outcome does not dispatch (or even schedule) a retry itself:**
   `sdp-solution-phase-worker`'s own existing, unmodified procedure already reads a task's prior
   non-compliant Eval blockquote and treats its corrective notes as the starting point when
   redispatched against a `REJECTED` task (bootstrap doc, Implementation Loop WORKER session
   step 7 and its solution-phase mirror) — this is the ordinary REJECTED→redo cycle every SDP
   task already goes through, mechanical-fix or not. Once this sub-step increments the attempt
   counter and Step 7 sub-step 4 resets the dispatch sentinel to its stub (below), the *next*
   fire's Step 6 correctly GENERATEs and `sdp-solution-phase-coordinator` (now able to run from
   a loop fire) dispatches an ordinary WORKER redo against the `REJECTED` task on its own — no
   `Fix Focus:` field needed a second time, since the REJECTED Eval blockquote already carries
   the corrective notes WORKER's existing procedure already knows to read.

   If the dispatched task's status is `"REJECTED"` and `phase_loop_mechanical_resolution.attempts <
   autoResolveHalt.evalCycleAttemptThreshold`: increment `phase_loop_mechanical_resolution.attempts`,
   also write `eval_cycle_attempts + 1` to `tasks[phase_loop_mechanical_resolution.task]`'s own
   entry (bound by now — see Step 7 sub-step 3's binding check) to keep it in
   lockstep (informational mirror only), and leave `status: "fix_dispatched"` unchanged — the
   cycle is still open, just waiting on the ordinary REJECTED-redo path described above. Append
   to `auto_actions`: `{"timestamp": "[ISO timestamp]", "trigger": "mechanical discovery",
   "action": "mechanical fix rejected, redo pending", "phase": "[current_phase]", "attempt": [N,
   the new attempts value]}`. Invoke
   `/sdp-create-banner icon=warning row=0 row: Status | sdp-solution-phase-state-loop: mechanical fix for [current_phase] still deficient after attempt [N] — sdp-solution-phase-coordinator will dispatch a redo next cycle.`
   Produce `reason = "mechanical fix attempt [N] rejected, redo pending via
   sdp-solution-phase-coordinator"`. If the dispatched task's status is `"REJECTED"` and
   `phase_loop_mechanical_resolution.attempts >= autoResolveHalt.evalCycleAttemptThreshold`:
   this is the cap-exceeded case — append to `auto_actions`: `{"timestamp": "[ISO timestamp]",
   "trigger": "mechanical discovery", "action": "mechanical fix cap exceeded, halted", "phase":
   "[current_phase]", "attempts": [N]}`. Invoke
   `/sdp-create-banner icon=error row=0 row: Status | sdp-solution-phase-state-loop: mechanical fix for [current_phase] still deficient after [N] attempts — halting. Original problem: [items]. Attempts: [fix/eval history from the phase document's own Completed/Eval blockquotes for this cycle]. Current condition: [REJECTED, eval_cycles=[eval_cycles]].`
     Set `workflow_status = "halted"` and `halt_reason` in `.sdp-solution-workflow/state.json`
     to the same summary text. Set `phase_loop_mechanical_resolution.status = "escalated"` (the
     terminal state sub-step 1 above explicitly catches on every subsequent fire until a human
     clears the halt). Produce `reason = halt_reason`, and record `halted = true` for Step 8's
     metrics/workflow-log — cap-exceeded is always a halt. If the dispatched task's status is
     `"VERIFIED"`: the
     fix is confirmed — set `phase_loop_mechanical_resolution.status = "resolved"`. Append to
     `auto_actions`: `{"timestamp": "[ISO timestamp]", "trigger": "mechanical discovery",
     "action": "mechanical fix verified", "phase": "[current_phase]", "attempts": [final attempts
     value]}`. Invoke
     `/sdp-create-banner icon=success row=0 row: Status | sdp-solution-phase-state-loop: mechanical fix for [current_phase] verified clean — resuming normal dispatch.`
     Produce `reason = "mechanical fix verified"`.

### Step 6: Evaluate Dispatch Sentinel

Runs whenever neither Step 4 nor Step 5 recorded an action for this fire. Concretely, this
means `workflow_status` was not `"halted"` on entry (Step 2 sub-step 4), and one of: Step 4
found no `Issues:` item to consume at all; every Step 4 item classified as mechanical and Step 5
sub-step 1's `"escalated"`-status discovery-entry branch matched (cap already hit earlier,
deferred without recording an action); or Step 5 sub-step 5's `"fix_dispatched"` branch matched
(a mechanical-fix cycle for this phase is already in flight, deferred without recording an
action). Step 5 sub-step 5's fresh-cycle branch, and every halt/kill-switch/catch-all bullet
across Step 4 sub-step 5 and Step 5, all record their own action and route directly to
Step 7 or Step 8 instead of reaching here.

**Why a plain field comparison is sufficient here:** the phases-1-7 dispatch sentinel
(`sdp-solution-create-prompt`'s own documented shape) carries
only `current_phase`, `expected_status` (= `phase_gate.status`), and `role` — no per-task-status
field, so comparing only those fields cannot by itself detect a dispatched task's own status
advancing (e.g. `PENDING` to `WORK_COMPLETE`). Rather than have *this* step re-derive the
correct dispatch target from task status — which requires duplicating
`sdp-solution-phase-coordinator`'s own multi-task dispatch algorithm (REJECTED-priority over
PENDING, GATE_REVIEWER only once every task in the phase is VERIFIED, and more) — Step 7 sub-step
4 below guarantees the sentinel is *always* invalidated immediately after any dispatched role
(WORKER/REVIEWER/GATE_REVIEWER) returns, by resetting `sdp-solution-docs/00_solution_prompt.txt`
to its stub content. That means this step never has to ask "is task status implied here stale" —
a sentinel that survived past the last dispatch's return is, by construction, still accurate,
because nothing that could invalidate it happens without also triggering that reset. This is
simpler and more correct than deriving expected state independently: it prevents staleness at
the source instead of trying to detect it after the fact.

1. Read only the first line of `sdp-solution-docs/00_solution_prompt.txt`.
2. If the file cannot be read, is empty, contains the stub
   `(empty — COORDINATOR writes this after each dispatch)`, or the first line does not match
   `[sdp-solution-prompt current_phase="..." expected_status="..." role="..."]` — **optionally
   followed by a 4th attribute, ` model="..."` — its presence or absence never affects this
   validity check; a sentinel with exactly the 3 attributes above, or with those 3 plus a
   trailing `model="..."`, is equally valid**: record **action = GENERATE**. Reason: "no valid
   phases-1-7 sentinel". Proceed to Step 7.
3. Extract `current_phase`, `expected_status`, `role` from the sentinel, and `model` too when the
   4th attribute is present (leave it unset/absent otherwise — its absence is expected, not an
   error).
4. If extracted `current_phase` does not equal `current_phase` from `state.json` (Step 2):
   record **action = GENERATE**. Reason: "sentinel current_phase '[extracted]' does not match
   state.json current_phase '[actual]'". Proceed to Step 7.
5. If extracted `expected_status` does not equal `phase_gate.status` from `state.json`: record
   **action = GENERATE**. Reason: "sentinel expected_status '[extracted]' does not match
   phase_gate.status '[actual]'". Proceed to Step 7.
6. **Dispatch-file integrity check.** If `last_session` is absent, null, or `"none"`: record
   **action = REPAIR**. Reason: "sentinel has no last_session recorded — no dispatch file
   exists". Proceed to Step 7. Otherwise read
   `.sdp-solution-workflow/sessions/session-[last_session].md` in full. If it does not exist, or
   its `Role:` line does not equal the sentinel's `role`, or its `Work Item:` line does not
   equal `current_phase`: record **action = REPAIR**. Reason: "session-[last_session].md does
   not match the sentinel — Role or Work Item mismatch". Proceed to Step 7.
7. All checks passed: record **action = EXECUTE**. Reason: "sentinel valid". Proceed to Step 7.

### Step 7: Execute

Act based on the `action` recorded by Step 1, Step 4, Step 5, or Step 6.

**API_RECOVERY:**
1. Play the notification tone (non-blocking): run
   `./sdp-shared/scripts/sdp-tone.ps1 -trigger "api.error_detected"` via the PowerShell tool.
2. Invoke
   `/sdp-create-banner icon=warning row=0 row: Action | API error detected — spawning subagent to redetermine the dispatch via sdp-solution-phase-coordinator.`
3. Spawn a subagent via the Agent tool, identically to the GENERATE handler below: "You are an
   SDP workflow dispatch subagent. Invoke `sdp-solution-phase-coordinator` to determine the
   correct next phases-1-7 dispatch and write a fresh `sdp-solution-docs/00_solution_prompt.txt`.
   Do not spawn any WORKER, REVIEWER, or GATE_REVIEWER subagent yourself — stop once the
   dispatch prompt and session file are written." **Deliberately GENERATE-shaped, not a
   resume-from-sentinel:** an interrupted fire may already have completed its role dispatch and
   reset the sentinel to its stub (Step 7 sub-step 4 runs immediately once the interrupted
   subagent returns, whether or not the loop's own later steps also completed) before the API
   error actually surfaced — in which case a resume attempt would find nothing valid to resume.
   Re-determining via `sdp-solution-phase-coordinator`, exactly like GENERATE, is correct either
   way: if the prior dispatch never completed, it re-derives the same pending dispatch; if it
   did complete, it correctly advances past it. No sentinel reset needed here — this subagent
   never dispatches a role directly, so nothing invalidates what it writes.
4. After the subagent returns: invoke
   `/sdp-create-banner icon=info row=0 row: Action | sdp-solution-phase-coordinator subagent returned.`
   Proceed to Step 8.

**GENERATE:**
1. Invoke
   `/sdp-create-banner icon=in-progress row=0 row: Action | [reason from Step 6] — spawning subagent to regenerate the dispatch via sdp-solution-phase-coordinator.`
2. Spawn a subagent via the Agent tool: "You are an SDP workflow dispatch subagent. Invoke
   `sdp-solution-phase-coordinator` to determine the correct next phases-1-7 dispatch and write
   a fresh `sdp-solution-docs/00_solution_prompt.txt`. Do not spawn any WORKER, REVIEWER, or
   GATE_REVIEWER subagent yourself — stop once the dispatch prompt and session file are
   written."
3. After the subagent returns: invoke
   `/sdp-create-banner icon=info row=0 row: Action | sdp-solution-phase-coordinator subagent returned.`
   Proceed to Step 8.

**REPAIR:**
1. Invoke
   `/sdp-create-banner icon=in-progress row=0 row: Action | [reason from Step 6] — spawning subagent to repair the dispatch via sdp-solution-phase-coordinator.`
2. Spawn a subagent via the Agent tool: "You are an SDP workflow dispatch subagent. Invoke
   `sdp-solution-phase-coordinator` to complete the pending phases-1-7 dispatch. Do not take any
   other action."
3. After the subagent returns: re-read `.sdp-solution-workflow/state.json` and, if
   `last_session` now resolves to an existing, matching session file, invoke
   `/sdp-create-banner icon=success row=0 row: Action | Dispatch repaired by sdp-solution-phase-coordinator.`
   Record `halted = false`. If still not repaired: set `workflow_status = "halted"` and
   `halt_reason = "[current_phase] dispatch could not be repaired — sdp-solution-phase-coordinator returned without creating a matching session file. Manual investigation required."`
   Play the notification tone (non-blocking): run
   `./sdp-shared/scripts/sdp-tone.ps1 -trigger "halt.no_progress"` via the PowerShell tool.
   Invoke `/sdp-create-banner icon=error row=0 row: Status | Halted — dispatch repair failed. Manual investigation required.`
   Record `halted = true`. Proceed to Step 8.

**EXECUTE (mechanical-fix dispatch already written by Step 5, or a normal sentinel-valid dispatch):**
1. If this is a normal sentinel-valid dispatch (not a mechanical-fix dispatch already written
   directly by Step 5) **and the sentinel's `role` is `WORKER` or `REVIEWER` (never
   `GATE_REVIEWER`** — a gate review is a compliance verdict against fixed criteria, not a
   session that surfaces new non-blocking discoveries, and its own fixed Gate Verdict blockquote
   format has no natural place for this ad-hoc content the way WORKER/REVIEWER's free-form
   narrative blockquotes do; see Step 4 sub-step 2's own note on why a `GATE_REVIEWER` fire must
   never be asked for `Issues:` at all**): read `.sdp-solution-workflow/sessions/session-[last_session].md`
   (already confirmed to exist and match by Step 6 sub-step 6's integrity check) and append one
   field to it — `Issues Reporting: If you discover any blocker, gap, open item, or
   partial-compliance condition during this session that does not itself rise to a
   blocking/halt condition, append a "**Issues:**" sub-heading inside the Completed/Eval/
   Verified blockquote you write to conclude this session (one bullet per item: what was found,
   where, why it doesn't block). Omit this sub-heading entirely if there is nothing to report.`
   — this is the only content this skill ever adds to a coordinator-authored session file; every
   other field in it is untouched. Since Step 6 only ever reaches `EXECUTE` for a session file
   this fire has not executed before (the sentinel-reset invariant guarantees a fresh session
   file per execution — see Step 6's own note), this append happens exactly once per session
   file, with no risk of duplicating the field on a later fire. Invoke
   `/sdp-create-banner icon=in-progress row=0 row: Action | Sentinel valid ([current_phase] / [role]) — spawning subagent to execute via sdp-solution-run-prompt.`
   Spawn a subagent via the Agent tool: "You are an SDP workflow dispatch subagent. Invoke
   `sdp-solution-run-prompt` to execute the current dispatch prompt at
   `sdp-solution-docs/00_solution_prompt.txt`. Do not take any other action."
2. If this is a mechanical-fix dispatch (Step 5 already wrote the session file and prompt
   directly): spawn a subagent the same way — "Invoke `sdp-solution-run-prompt` to execute the
   current dispatch prompt at `sdp-solution-docs/00_solution_prompt.txt`. Do not take any other
   action." (Identical dispatch mechanism either way — the only difference is who authored the
   prompt file this fire.)

   **Applying the sentinel's `model` attribute (both sub-steps above):** if Step 6 sub-step 3
   extracted a `model` value from the sentinel, pass it as the Agent tool's own `model` parameter
   on whichever spawn call above fires this cycle. If no `model` attribute was present (the
   sentinel's 3-attribute form — always the case for a mechanical-fix dispatch, since Step 5 never
   writes one), spawn without specifying `model` — the subagent inherits this session's own
   model, unchanged from before this attribute existed.
3. After the subagent returns: re-read the phase state file
   (`sdp-solution-docs/[phase_file]_state.json`) — never the subagent's own text.
   - **Task-identity binding** (runs first, before the two branches below; a cheap no-op once
     bound): if `phase_loop_mechanical_resolution.phase` equals `current_phase`, its `status` is
     `"fix_dispatched"`, and its `task` is `null`: scan the phase state file's `tasks` map for the
     entry whose `last_session` equals `phase_loop_mechanical_resolution.dispatch_session`. If
     found, write that entry's TASK-ID as `phase_loop_mechanical_resolution.task` — this is the
     specific task WORKER's Step 6 (Record Completion) just wrote `last_session` into, so the
     binding is a plain state-file read-back (Core Invariant 7), never a selection of which task
     to act on. On a successful bind, also write `eval_cycle_attempts: 1` to that same task's
     entry (the informational mirror described in Step 5 sub-step 5 — this is the point that
     write was deferred to, since which entry to write is only knowable once bound). The
     matching field is `last_session` written by `sdp-solution-phase-worker` Step 6 (Record
     Completion) — if that write ever lands on the task entry under a different key than this
     scan expects, or on the phase state file's top level instead, the scan below would find no
     match; treat a miss as the disclosed degraded case in that event, not as a hard failure. If
     no entry's `last_session` matches: leave `task` as
     `null` and continue without the `eval_cycle_attempts` mirror write (there is no entry to
     target — informational only, no control-flow or cap impact). This bullet's own guard
     (`task is null`) re-evaluates every fire, so the scan itself re-runs on every subsequent
     fire too, not just this one — but a `last_session` value tied to this specific
     `dispatch_session` will never recur on any task's entry afterward (each later dispatch
     overwrites `last_session` with its own session number), so a miss here can never later
     resolve into a match. The failed-bind state is therefore effectively permanent for the rest
     of this mechanical-fix cycle, degrading the check below to `phase`-alone matching only.
   - **Determine the status to evaluate below:** if `phase_loop_mechanical_resolution.task` is
     bound (non-`null`): the relevant status is `tasks["[task]"].status` — that one task's entry,
     read directly, never any other task's. Otherwise (`task` is `null`, whether because binding
     has not yet had its first chance to run this cycle, or because it already failed and stays
     permanently unbound per the note above): on the one fire immediately after Step 5 sub-step
     5's write, exactly one task is in flight (the mechanical-fix WORKER dispatch itself), so
     reading whichever task's status just changed is unambiguous; on any later fire with `task`
     still `null`, this degrades to reading whichever task's status
     the phase state file shows having just changed — matching `phase` alone, the coarsest
     precision this check ever operates at. Call this value **the dispatched task's status** below.
   - **Mechanical-fix REVIEWER outcome detected:** `phase_loop_mechanical_resolution.phase`
     equals `current_phase`, its `status` is `"fix_dispatched"`, and the dispatched task's status
     is `"REJECTED"` or `"VERIFIED"` — this combination can only occur after a REVIEWER ran
     (WORKER never produces either status), so this fire just confirmed a mechanical-fix verify
     outcome, dispatched either directly by Step 5 sub-step 5 (the very first attempt) or by
     `sdp-solution-phase-coordinator` via the ordinary GENERATE/EXECUTE cadence (every attempt
     after that, including retries — see Step 5 sub-step 6's note on why a retry is never
     dispatched directly by this step). Apply Step 5 sub-step 6's cap-check decision now, using the dispatched
     task's status; that sub-step updates state and produces a `reason` string but does not
     itself record `action` — record **`action = EXECUTE`** here (a subagent genuinely ran this
     fire) using that `reason`. If sub-step 6's decision was cap-exceeded: also record
     `halted = true` for Step 8, per that sub-step's own instruction. **Proceed to sub-step 4** —
     the sentinel reset below applies to this branch exactly as it does to Normal dispatch; do
     not proceed to Step 8 directly from here.
   - **Normal dispatch** (everything else, including the dispatched task's status becoming
     `"WORK_COMPLETE"`, or — once `task` is bound — a REVIEWER verdict for a *different* task in
     the same phase that `phase_loop_mechanical_resolution` isn't tracking): invoke
     `/sdp-create-banner icon=info row=0 row: Action | Dispatch subagent returned — task status is now [status].`
     Proceed to sub-step 4.
4. **Reset the dispatch sentinel — every role dispatch, every outcome, no exceptions.**
   Immediately after sub-step 3 above (either branch), write
   `sdp-solution-docs/00_solution_prompt.txt` to the literal stub content
   `(empty — COORDINATOR writes this after each dispatch)`, overwriting whatever sentinel was
   there. This is what makes Step 6's plain field comparison correct (see that step's own note):
   the *next* fire's Step 6 sub-step 2 will unconditionally record GENERATE against this stub,
   dispatching `sdp-solution-phase-coordinator` (whose Step 2a text supports both manual and
   loop-fired invocation) to correctly determine whatever's actually due next —
   the same task redispatched, a different task in the same phase, REVIEWER, GATE_REVIEWER, or
   advancing `current_phase` — using its own unmodified, already-correct multi-task algorithm,
   never re-derived here. Proceed to Step 8.

**STOP:** No subagent spawned. `action` and `reason` were already recorded at the step that
triggered the stop. Proceed to Step 8.

### Step 8: Record Fire Metrics

Append exactly one JSON line to today's
`.sdp-solution-workflow/logging/loop-logs/loop-metrics-[yyyyMMdd].jsonl` file at the solution
root — the same file `sdp-project-state-loop` and `sdp-solution-state-loop` already share.

0. **Self-cancel the recurring loop on a terminal outcome.** If this fire's recorded `action` is
   `STOP` or `halted` is `true`: invoke `/sdp-cancel-auto` to stop the recurring loop. Every STOP
   or halt this skill produces — the interactive-checkpoint defer in Step 3, a judgment-classified
   discovery in Step 4, any halt in Step 5, or REPAIR's failed-repair halt in Step 7 — means a
   later fire cannot make different progress without a live session or a human resolving the
   condition; continuing to fire at the configured interval only repeats an identical, wasted STOP.
   `/sdp-cancel-auto` is the sole place cron cancellation logic (`CronList`/`CronDelete`) lives in
   SDP; this skill never duplicates that mechanism itself. If `/sdp-cancel-auto` reports no
   matching cron job: this fire was not actually running under a recurring loop (e.g. a manual
   invocation) — treat this as a normal no-op, not an error, and continue to sub-step 1.
1. Assemble:
   ```json
   {"timestamp":"[ISO 8601, e.g. via Get-Date -Format o]","scope":"solution-phase","action":"[API_RECOVERY|GENERATE|REPAIR|EXECUTE|STOP]","current_phase":"[current_phase or null]","reason":"[reason recorded for this fire, or null]","halted":[true|false],"halt_reason":"[halt_reason or null]"}
   ```
   `halted` is `true` only where a step explicitly instructed recording `halted = true` for this
   fire (every already-real or newly-set halt path in Step 4 and Step 5, and REPAIR's failed-
   repair path in Step 7). It is `false` for every other fire, including `EXECUTE`,
   `GENERATE`, and any `STOP` that did not set or confirm `workflow_status` as `"halted"` (e.g.
   `state.json` unreadable, `current_phase` is `null`, an interactive-checkpoint defer, or a
   discovery/mechanical-fix-in-flight item deferred without starting a halt).
2. Append via the PowerShell tool:
   ```
   Add-Content -Path ".sdp-solution-workflow/logging/loop-logs/loop-metrics-$(Get-Date -Format 'yyyyMMdd').jsonl" -Value '[the JSON line]' -Encoding utf8
   ```
3. If the `Add-Content` call fails: ignore the failure and continue — a metrics write failure
   must never block or halt the loop. Do not retry.
4. If `halted` is `true` for this fire: also run
   `./sdp-shared/scripts/sdp-workflow-log.ps1 -trigger "loop.stuck_halt" -role "SOLUTION_PHASE_STATE_LOOP" -workItem "[current_phase]" -outcome "HALTED" -reason "[halt_reason]"`
   via the PowerShell tool (non-blocking — ignore any failure and continue).
5. Stop. This is the final step of the fire regardless of which action was taken.

## Constraints

- Do not invoke any SDP skill directly — all dispatch is via the Agent tool (subagent), except
  the narrow, explicit session-file/prompt-file writes Step 5 sub-step 5 performs directly for a
  mechanical-fix dispatch (mirrors the same exception already granted to
  `sdp-solution-phase-coordinator`), and the single-field `Issues Reporting:` append Step 7
  EXECUTE sub-step 1 performs to an already-coordinator-written session file before a normal
  dispatch — neither invokes an SDP skill, so neither is an exception to this rule in the first
  place, but both are direct actions this skill takes without a subagent. `/sdp-cancel-auto`
  (Step 8 sub-step 0, on a `STOP` or halted outcome) genuinely is a direct skill invocation and is
  a disclosed exception: it is a cron-management utility, not a role dispatch, so it does not
  weaken the role-isolation this rule protects.
- Never touch `sdp-solution-phase-worker`, `sdp-solution-phase-reviewer`,
  `sdp-solution-phase-gate-review`, or `sdp-solution-phase-coordinator` — dispatch them exactly
  as written, via `sdp-solution-run-prompt` or a direct Agent-tool invocation naming the skill.
- Never treat a halt whose `halt_reason` traces to Material Decision Escalation,
  `PARTIAL_COMPLIANCE_ESCALATE`, `DIAGNOSIS_BLOCKED`, or a Phase Readiness Regression
  `GATE_BLOCKED` verdict as mechanical, regardless of `solutionPhaseLoop.autoResolveMechanicalFindings.enabled`.
- Never attempt more than `autoResolveHalt.evalCycleAttemptThreshold` mechanical-fix cycles for
  the same discovery before halting.
- Never parse a subagent's returned text to determine outcome — always re-read the relevant
  state or phase state file.
- Never write `pros_cons_gaps.cycle_target`, `eval_cycles`, `status`, or any other field on any
  task's entry in the phase state file's `tasks` map that `sdp-solution-phase-worker`/`-reviewer`'s
  own Constraints already claim ownership of — this skill writes only `eval_cycle_attempts`,
  scoped to the one task `phase_loop_mechanical_resolution.task` names. On
  `.sdp-solution-workflow/state.json` it writes only `phase_loop_mechanical_resolution`,
  `last_session` (mechanical-fix dispatches only), `workflow_status`/`halt_reason` (setting a
  halt only — this skill never clears a halt it did not itself set), `auto_actions` (mechanical-
  fix attempt history and deferred-item entries — see Step 5 sub-steps 1 and 5), and the
  loop-metrics/workflow-log append targets.
- Never write `phase_gate.gate_review_attempts` — this skill only reads it (Step 2, for
  informational banner/logging content — no step in this skill's own Procedure branches on it).
- Never scan more than the current conversation's most recent 10 lines for API-error detection,
  and never search files for it (mirrors `sdp-project-state-loop`'s identical constraint).
- Never read more than the first line of `sdp-solution-docs/00_solution_prompt.txt` in Step 6 —
  the dispatch-file integrity check's full read of `session-[last_session].md` is the one
  documented exception, not a license to read the prompt file in full too.
- Never leave a stale dispatch sentinel in place after a role dispatch (WORKER, REVIEWER, or
  GATE_REVIEWER — dispatched via EXECUTE) returns — always reset
  `sdp-solution-docs/00_solution_prompt.txt` to its stub content first (Step 7 sub-step 4).
  Never apply this reset after a GENERATE, REPAIR, or API_RECOVERY dispatch — all three dispatch
  `sdp-solution-phase-coordinator` itself, which is what writes the sentinel; resetting
  immediately afterward would erase what it just produced.
- Never re-derive `sdp-solution-phase-coordinator`'s own dispatch-target algorithm (which task
  in a phase to act on, REJECTED-priority, all-VERIFIED-before-GATE_REVIEWER, and so on) inside
  this skill — always let a GENERATE-dispatched `sdp-solution-phase-coordinator` session
  determine it, per Step 6's own note. This skill's dispatch decisions are limited to the
  mechanical-fix cycle's own fresh-attempt initiation (Step 5 sub-step 5) and cap check (Step 5
  sub-step 6) — nothing else.
- Never perform the Step 8 metrics write anywhere but as the final action of a fire, and never
  write it as anything other than a strict append.
- Never fabricate or guess a `model` value for an Agent-tool spawn when the sentinel carries
  none — spawn without the parameter so the subagent inherits the dispatching session's model,
  exactly as before this attribute existed.
- Never treat a sentinel's optional `model="..."` attribute as required, or its absence as an
  invalidity — Step 6's validity check accepts the sentinel with or without it.

## Outputs

- **REPAIR:** subagent spawned, outcome confirmed from a file re-read after return (session file
  match).
- **EXECUTE:** subagent spawned, outcome confirmed from the phase state file's `tasks` map after
  return (the specific task's entry once `phase_loop_mechanical_resolution.task` is bound, or the
  one task in flight beforehand); the dispatch sentinel is then unconditionally reset to its stub
  content (Step 7 sub-step 4).
- **API_RECOVERY:** subagent spawned (`sdp-solution-phase-coordinator`, identically to
  GENERATE); confirmed only by the banner reporting the subagent returned — its actual effect
  (a freshly written, correct sentinel) is confirmed by the *next* fire's Step 6 evaluating it,
  exactly like GENERATE. No sentinel reset performed here — this branch never dispatches a role
  directly, so nothing it writes needs invalidating.
- **GENERATE:** subagent spawned (`sdp-solution-phase-coordinator`); confirmed only by the
  banner reporting the subagent returned — its actual effect (a freshly written, correct
  sentinel) is confirmed by the *next* fire's Step 6 evaluating it, not by this fire re-reading
  it back.
- **STOP:** reason reported via banner; no subagent spawned.
- **Every fire ending in `STOP` or a halt:** `/sdp-cancel-auto` invoked (Step 8 sub-step 0) to stop
  the recurring loop — a no-op if no matching cron job exists.
- `.sdp-solution-workflow/state.json`: `phase_loop_mechanical_resolution` (this skill's private
  bookkeeping), `last_session` (mechanical-fix dispatches), `workflow_status`/`halt_reason` on a
  halt (never cleared by this skill), `auto_actions` (mechanical-fix attempt history and
  deferred-item entries). `phase_gate.gate_review_attempts` is read, never written, by
  this skill.
- Phase state file: `eval_cycle_attempts` (this skill's field, alongside the existing ones
  `sdp-solution-phase-worker`/`-reviewer` already own).
- `.sdp-solution-workflow/sessions/session-[N].md` and `sdp-solution-docs/00_solution_prompt.txt`
  — session file written directly in full for a mechanical-fix fresh-attempt dispatch (Step 5
  sub-step 5, including its `Issues Reporting:` field); for a normal, coordinator-authored
  dispatch, only a single `Issues Reporting:` line is appended to the already-written session
  file (Step 7 EXECUTE sub-step 1), never the rest of its content. The prompt file is both
  written directly there (mechanical-fix dispatches) and reset to its stub content after every
  `EXECUTE` role dispatch (Step 7 sub-step 4) — API_RECOVERY does not reset it, since it never
  dispatches a role directly (see API_RECOVERY's own note).
- One JSON line appended to today's `loop-metrics-*.jsonl` file every fire.
