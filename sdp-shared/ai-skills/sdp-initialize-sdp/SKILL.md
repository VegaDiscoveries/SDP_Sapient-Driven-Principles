## Purpose

Print a static SDP opening banner, load workspace context via `sdp-solution-read-docs`
(unchanged), examine solution/project state (or detect `~SDP-Maintenance` framework-dev mode),
and print a closing status banner. This skill is the SessionStart hook's direct target.

**No script is involved.** This skill fires exactly once per session, is always human-attended
(never dispatched inside the unattended `sdp-project-state-loop`), and its only job is chat-facing
display — the tool-call-count savings that justify a script elsewhere in SDP don't apply here,
and routing banner text through a script's JSON stdout means the harness's own tool-result
preview leaks a raw, unsubstituted fragment of the banner into the transcript before the real
one prints. Read the needed files directly and construct the banner text as part of composing
this skill's chat response.

**A trivial first message is not a request for more work.** The SessionStart hook forces this
skill before *any* first user message, including a bare "go", "start", "begin", or similar
content-free opener. When that is the case, printing the two banners plus the one short closing
statement described below *is* the complete response to that turn — do not treat a trivial
opener as implicit permission to also dispatch the next SDP workflow step, run additional
skills, or otherwise infer that more was being asked for. Finish the closing banner, ask the
one short question, and stop; await the user's actual next instruction.

**A valid skill invocation is never trivial — word count does not apply to it.** Before applying
the word-count check below, check whether the first message itself is a valid skill invocation:
a slash-command form (`/skill-name`, optionally followed by arguments) naming a skill present in
the current session's available-skills listing, or a documented shorthand alias for one (e.g.
`rc`/`readc`/`rclaude`/`rclaud`/`rec` for the user-level CLAUDE.md read, per that skill's own
description). A message meeting this test is a request for more work regardless of its word
count — `/rc` and `/sdp-auto` are both two words or fewer and must still be treated as the skill
invocation they name, not discarded as a content-free opener. Process it after the opening and
closing banners print, per the non-trivial handling below. A slash-prefixed or shorthand-looking
string that does not match any skill in the current listing is not a valid skill invocation —
fall through to the word-count check instead.

**A non-trivial first message is a request for more work.** If the first message is not a valid
skill invocation per the check above, apply the word-count test: a substantive first message
(more than two words) should be processed as a normal input - but not until the opening and
closing banners are printed.

## Inputs

None from the caller. This skill is invoked with no arguments, at session start.

## Output Discipline

This skill's entire user-visible chat output is the opening banner, the closing banner, and
exactly one short closing statement after the closing banner — and nothing else. The one and only
exception is if the first message is non-trivial — either a substantive message (more than two
words) or a valid skill invocation regardless of word count (see the Purpose section's
valid-skill-invocation check) — in that case, the skill should process it as a normal input, or
invoke the named skill, after printing the banners.

**This section is a deliberate, standing exception to the harness's own general convention of
stating what you're about to do before a tool call and giving short updates at key moments.**
That convention is correct for ordinary tasks and wrong for this skill specifically — its entire
value is a silent, mechanical render of exactly two banners with nothing else produced in
between. Do not weigh this rule against that general narration habit before acting; the
comparison has already been made and decided, in this document, in advance.

- Do not print step-by-step narration ("reading the bootstrap doc now", etc.) at any point in
  this procedure. This explicitly includes narrating this skill's own conditional or
  intentionally-omitted steps ("no start-tone step, proceeding to...", "skipping X because...")
  — a step being absent or conditional in this skill's own definition is never something to
  comment on in chat, any more than a step that runs normally is.
- Do not relay `sdp-solution-read-docs`'s own confirmation sentence (its Step 4 "Report to the
  user" output) to the user as chat text. Its output is consumed only internally, to determine
  whether it halted and to derive `haltMessage` for Step 3 — never printed.
- Do not add commentary before or between the two banners. Nothing precedes the opening banner
  except the version read; nothing sits between the opening and closing banners except the
  internal `sdp-solution-read-docs` invocation.
- The literal string `~SDP-Maintenance` must never appear in this skill's output except inside
  the Maintenance Variant template's own fixed text — never in prose, narration, or any other
  variant, regardless of context.
- **After the closing banner, exactly one short closing statement is required** — a single
  sentence inviting the user's next instruction, framed around the solution state the closing
  banner just reported (e.g., referencing the active project/phase it named, or that
  maintenance mode was detected). This is not "commentary" in the prohibited sense above: it
  does not narrate what this skill did, restate step numbers, or summarize the procedure — it
  only reflects the determined state back and asks what's next. One sentence, no more.
- **Do not reproduce any of the following patterns — verbatim examples, not templates to adapt.**
  They are the exact failure pattern, not phrasing to avoid while similar phrasing remains fair
  game — reproducing any of these, or a reworded variant that serves the same narrating/
  commentary function, is the same conduct violation this section prohibits.
  - `"Version is 1.0.0. Now printing the opening banner."` — narrating a value read during
    Step 1 and announcing the next print action, before the opening banner.
  - `"Now invoking sdp-solution-read-docs with --no-tone per Step 2."` — announcing a sub-skill
    invocation between the two banners.
  - `` "`~SDP-Maintenance` is present — this is SDP framework development mode." `` — stating
    the detected variant in prose immediately before printing the closing banner that already
    conveys this.
  - `"All rows check out at 74 characters (matching the border width, treating the emoji as a
    single character per the mask rule). Printing the closing banner now."` — narrating a
    width self-check immediately before printing the closing banner; the Body Row Construction
    section's "do not use a script or tool call to generate or verify it" rule applies for the
    same reason: composing and validating a row is silent, in-line text work, not something to
    report on or hand off to a script.
  - Designing a variation of any of the above — different verb choice, more terse, folded into
    a single clause, moved to a different position relative to the banners, etc. — is itself a
    violation of this section. The rule being enforced is "no narration of this skill's own
    procedure, ever" — it does not apply to the one permitted closing statement described above,
    which reports solution state rather than narrating this skill's steps.
- Tool-call transcript entries the harness itself renders (e.g. a `Read` tool invocation line)
  are not chat text from this skill and are not something these instructions control — this
  constraint governs this skill's own prose output only.

## Fenced Output and Exact Reproduction

Print each banner inside a fenced code block (triple backtick, no language tag) — never as bare
chat text. Markdown rendering interprets bare `___` as bold-italic and bare `\` before certain
characters as an escape sequence, silently corrupting the box-drawing/figlet art.

**Reproduce the Fixed Templates below character-for-character — do not retype or re-derive them
from memory.** Every line in every fixed template is exactly 74 characters wide, verified at
authoring time. A line that is even one character off breaks the box's right-edge alignment,
which is not visible to you as you type it but is immediately visible to the user. Copy the
template text directly; the only edits permitted are the single `{VERSION}` substitution in the
opening banner and the body-row construction described in Step 3 for the pre-Phase-1,
phases-active, post-Phase-7-not-yet-evaluated, post-Phase-7-work-pending,
post-Phase-7-project-blocked, post-Phase-7-waiting-on-dependencies,
post-Phase-7-all-work-complete, active, and halted variants, and the read-docs-halt fallback
case. (The Maintenance and Solution-Missing variants are fully static and require no
construction.)

## Fixed Templates

### Opening Banner (Step 1) — fully static except `{VERSION}`

```
╭─ ✦ ──────────────────────────────────────────────────────────────── ✦ ─╮
│                                                                        │
│   ____  ____  ____                                                     │ ─╮
│  / ___||  _ \|  _ \        Sapient-Driven Principles                   │  │
│  \___ \| | | | |_) |       A Self-Driving Process for Coding           │  │
│   ___) | |_| |  __/        v{VERSION}                                      │  │
│  |____/|____/|_|                                                       │  │
│                                                                        │  │
│  Loading workspace context...                     by: Vega Discoveries │  │
│                                                www.VegaDiscoveries.com │  │
╰─ ✦ ──────────────────────────────────────────────────────────────── ✦ ─╯  │
   │   Disclaimer - AI Makes Mistakes - Use with Caution - Check all Work   │
   ╰─ ✦ ──────────────────────────────────────────────────────────────── ✦ ─╯
```

### Maintenance Variant (Step 3, `~SDP-Maintenance` present) — fully static body

```
╭─ ✦ SDP ────────────────── Sapient-Driven Principles ─────────────── ✦ ─╮
│ Mode       SDP Framework Maintenance                                   │
│ Detected   🚧 ~SDP-Maintenance/ present at solution root               │
│ Status     Ready for maintenance or improvements ✅                    │
╰─ ✦ ──────────────────────────────────────────────────────────────── ✦ ─╯
```

### Solution-Missing Variant (Step 3.2 exact-match case, `SDP-Solution.json` not found) — fully static body

```
╭─ ✦ SDP ────────────────── Sapient-Driven Principles ─────────────── ✦ ─╮
│ Solution   - (unavailable)                                             │
│ Projects   - (unavailable)                                             │
│ Status     ⛔ `SDP-Solution.json` not found at solution root.          │
│            Run the /sdp-workspace-setup skill to create it before      │
│            proceeding.                                                 │
╰─ ✦ ──────────────────────────────────────────────────────────────── ✦ ─╯
```

### Closing Banner Border — identical top/bottom border for every closing variant

Top border (reuse verbatim for every closing variant):
```
╭─ ✦ SDP ────────────────── Sapient-Driven Principles ─────────────── ✦ ─╮
```

Bottom border (reuse verbatim for every closing variant):
```
╰─ ✦ ──────────────────────────────────────────────────────────────── ✦ ─╯
```

## Procedure

### Step 1: Print the Opening Banner

1. Read the first 10 lines of the bootstrap doc (`SDP_Sapient-Driven-Principles_v*.md` at the
   solution root) and extract the value from its `| **Version** |` header row.
2. Print the Opening Banner fixed template verbatim, with `{VERSION}` replaced by that value
   (e.g. `v1.0.0`), inside a fenced code block. No surrounding text.

### Step 2: Invoke `sdp-solution-read-docs`

1. Invoke `/sdp-solution-read-docs` with argument `--no-tone`, so its own tone start/end calls
   are skipped entirely (no PowerShell tool call for them) — consistent with this skill's own
   Output Discipline, which already treats `sdp-solution-read-docs`'s output as internal-only.
2. If it completes normally (with or without its own internal warnings such as "no
   `SDP-Document-List.json`"): note no halt occurred; proceed to Step 3 with
   `haltMessage = ""`. Do not print its confirmation output (see Output Discipline above).
3. If it halts (prints a message beginning `⛔` and cannot proceed — e.g. `SDP-Solution.json`
   not found at solution root): capture that message text verbatim as `haltMessage`. Do not
   treat the halt as a reason to stop this skill — proceed to Step 3 with the captured text. Do
   not print the halt message as separate chat text; it is surfaced via the closing banner only.

### Step 3: Determine the Variant and Print the Closing Banner

**Steps 2 and 3 together are silent working, start to finish — no chat text of any kind until
the closing banner itself prints in sub-step 4 below.** This covers noting that Step 2 finished,
naming which variant sub-steps 1–3 selected, and reporting any intermediate file read
(`~SDP-Maintenance`, `SDP-Solution.json`, `registry.md`, `state.json`) as it happens. All of that
is internal derivation; the closing banner is the only report of it.

1. Determine whether `~SDP-Maintenance` exists at the solution root: attempt a `Read` tool call
   on the bare directory path — a "file does not exist" result means absent, any other result
   (including a directory-read error) means present — rather than a Bash/PowerShell existence
   check, and do not narrate this check in chat (no "checking for the maintenance folder now"
   commentary, no relaying the raw tool result back to the user). Or note it directly if already
   visible from an earlier read this session. **This check runs first, regardless of Step 2's 
   outcome.**
   - If present: print the Maintenance Variant fixed template verbatim, inside a fenced code
     block. Skip the remaining sub-steps entirely — do not read `SDP-Solution.json` or any
     state file for this render.
2. If `~SDP-Maintenance` is absent and Step 2 halted:
   - **Exact-match case:** If `haltMessage` is the `SDP-Solution.json`-not-found message —
     currently the sole halt condition `sdp-solution-read-docs` emits — print the
     **Solution-Missing Variant** fixed template verbatim, inside a fenced code block. Do not
     compute, wrap, or verify row widths for this case; the template already reflects it.
   - **Fallback case:** For any other, unanticipated `haltMessage` text, build the
     **read-docs-halt** variant dynamically — the Closing Banner Border (top + bottom, verbatim)
     wrapping these body rows:
     - `│ Solution   - (unavailable)` + padding + `│`
     - `│ Projects   - (unavailable)` + padding + `│`
     - `│ Status     ⛔ ` + `haltMessage`, wrapped per the Body Row Construction rules below.
3. If `~SDP-Maintenance` is absent and Step 2 did not halt: read `SDP-Solution.json` for
   `solution_name`, `projects[]` (each `{name, path, description}`, plus a `status` field once
   `sdp-solution-phase-coordinator` Step 2d has run at least once post-Phase-7 — see the
   post-Phase-7 branch below), and `last_active_projects[0]`. Then attempt to read
   `.sdp-solution-workflow/registry.md` directly
   to determine whether any phase 1–7 rows exist yet (row count > 0, regardless of status) — do
   not probe for its existence with a separate check first; a not-found result from the read
   itself already means "zero rows."
   - **If `.sdp-solution-workflow/registry.md` is absent or has zero rows** (pre-Phase-1 — no
     concept cycle has been seeded yet): build the **pre-Phase-1** variant — body rows `Solution`
     (value = `solution_name`), `Projects` (value = `(none registered)` if `projects` is empty,
     else `"name1, name2, ... (N)"`), `Status` (value = `✅ active`), then two Next Step rows
     mirroring `sdp-workspace-setup`'s own post-setup guidance (same two-way choice, same
     drop-zone path — do not reword or diverge from that skill's wording):
     - `Have Docs` | `Drop them in sdp-solution-docs/user-design-docs/ and run
       /sdp-solution-new-concept-intake.`
     - `No Docs` | `Run /brainstorming first — save the resulting doc to
       sdp-solution-docs/user-design-docs/ — then run /sdp-solution-new-concept-intake to advance it.`
   - **Otherwise** (registry has at least one phase 1–7 row): get
     `.sdp-solution-workflow/state.json`'s `current_phase` field. **Reuse-before-re-read:** if
     `sdp-solution-read-docs`'s own Pathway 2 sub-step 2 already read this exact file during
     Step 2 above (it does so whenever `projects` has 2+ entries and `last_active_projects` was
     empty — the common multi-project case), reuse the `current_phase` value already obtained
     then; do not read the file a second time. Only read it fresh here when that condition
     didn't hold (1 project, or `last_active_projects` was non-empty). Read it directly — do not
     probe for its existence first; a not-found result or missing field means "unknown," handled
     the same as `null` below.
     - **If `current_phase` is not `null`** (phases 1–7 in progress for this solution): build the
       **phases-active** variant — `Solution`/`Projects` rows as above, `Phase` = `current_phase`
       **verbatim** (a short slug like `"concept"`, not a formatted title — do not reformat it),
       `Status` = `✅ active`, `Next Action` = `Run /sdp-solution-phase-coordinator to continue
       Phase [current_phase].` (not `/sdp-solution-coordinator` — that skill never accepts a
       phases-1–7 dispatch.)
       This is a generic pointer, not a computed next task — working out the exact next dispatch
       is `sdp-solution-phase-coordinator`'s own decision logic; duplicating it here would add a
       third copy of the drift risk `solution-coordinator-orchestration-design.md` Section 6
       already flagged and accepted only once, for that skill's own peek.
     - **If `current_phase` is `null`** (Phase 7 has passed — routine per-project regime):
       - If `last_active_projects` is empty: read each entry's `status` field from the `projects[]`
         array already loaded above (no second file read) and branch on it, in this priority
         order:
         - **No entry in `projects[]` has a `status` field** (no post-Phase-7 dispatch cycle has
           run yet for this solution): build the **post-Phase-7, not yet evaluated** variant —
           `Solution`/`Projects` rows as above, `Status` = `✅ active`, `Next Action` =
           `Run /sdp-solution-phase-coordinator to begin per-project dispatch.`
         - **Any entry's `status` is `work_pending`:** build the **post-Phase-7, work pending**
           variant — same rows, `Status` = `✅ active`, `Next Action` =
           `Run /sdp-solution-phase-coordinator — work is ready to dispatch.`
         - **No `work_pending`, but any entry's `status` is `blocked`:** build the
           **post-Phase-7, project blocked** variant — same rows, `Status` =
           `⛔ blocked — ` + comma-separated names of every project whose `status` is `blocked`,
           `Next Action` = `Run /sdp-solution-phase-coordinator — it dispatches the blocked
           project's own coordinator, which will report the specific halt or diagnosis-blocked
           reason.`
         - **No `work_pending` or `blocked`, but any entry's `status` is `waiting`:** build the
           **post-Phase-7, waiting on dependencies** variant — same rows, `Status` = `✅ active`,
           `Next Action` = `All remaining work is waiting on cross-project dependencies — nothing
           to dispatch this cycle. Re-run /sdp-solution-phase-coordinator once dependencies clear.`
         - **Every entry with a `status` field reads `work_complete`** (`in_shared_task` entries
           are excluded from this check — that project's status is covered by the shared-task
           path's own reporting, not this branch — and an entry with no `status` field at all,
           because it was registered after the last Step 2d cycle, does not by itself block this
           outcome): build the **post-Phase-7, all work complete** variant — same rows, `Status` =
           `✅ complete`, `Next Action` = `All project work is complete.`
       - Otherwise (`last_active_projects` is non-empty), read the active project's
         `[path]/.sdp-workflow/state.json` for
         `current_phase` and `workflow_status`/`halt_reason`.
         - `workflow_status: "active"` (or the field absent): build the **active** variant — same
           Solution/Projects rows as above, `Active` = the active project's name, `Phase` =
           `current_phase` **verbatim** (a short slug like `"concept"`, not a formatted title —
           do not reformat it), `Status` = `✅ active`.
         - `workflow_status: "halted"`: build the **halted** variant — same Solution/Projects/
           Active/Phase rows, `Status` = `⛔ halted — ` + `halt_reason` (or `unspecified` if
           absent).

4. Print the assembled closing banner (Closing Banner Border top + the variant's body rows +
   Closing Banner Border bottom) inside a fenced code block, as the last output of this skill.
   No surrounding text.

## Body Row Construction

Use this method for the non-maintenance closing variants (Step 3.2 fallback case and Step 3.3) (No
other method is allowed), where field values are not known in advance. Agent must build each row
via the provided fixed-length mask overlay — no padding arithmetic, no manually-typed space runs, no
file writes and/or file reads to test the layout. The mask character is visible so a miscount is
obvious on sight instead of hiding in blank space. Build this directly as text — do not use a script
or tool call to generate and/or verify it.

**Masks (fixed, embedded literals — copy verbatim, do not regenerate):**

```
LABEL_MASK   = "œœœœœœœœœœœ"
CONTENT_MASK = "œœœœœœœœœœœœœœœœœœœœœœœœœœœœœœœœœœœœœœœœœœœœœœœœœœœœœœœœœ"
```

`LABEL_MASK` is 11 `œ` characters; `CONTENT_MASK` is 59 `œ` characters. `œ` was chosen because it
is not produced by a standard keyboard and could not plausibly appear as valid banner content.

**Double-width glyphs — check before every overlay.** `✅` and `⛔` are the only glyphs this
skill's dynamically-built rows ever contain (`Status` = `✅ active` or `⛔ halted — [reason]`).
Both render as 2 terminal columns despite being a single character — this has been confirmedby
user and agent - do not attept to re-validate. A mask overlay that treats one of these glyphs as
occupying a single `CONTENT_MASK` position under-counts its rendered width by 1, pushing that
row's right border one column too far right. The Fixed Templates above never had this bug — every
static row already containing `✅`, `⛔`, or `🚧` (the Maintenance variant's `Detected`/ `Status`
rows, the Solution-Missing variant's `Status` row) is 73 raw characters, one shorter than the
74-character glyph-free rows, precisely to compensate. The rule below makes dynamically built rows
follow the same convention.

**Build a row:**
1. Overlay the label text onto the front of `LABEL_MASK` — the label's characters replace the
   mask's first `len(label)` characters; any `œ` beyond that is left untouched.
2. Determine this row's usable content width, `W`, **from this row's own content text only —
   evaluate every row independently; never reuse or carry forward a `W` value determined for a
   different row, and never determine glyph presence for the whole banner up front and apply the
   result to a neighboring row.** `W` is **58** if this row's own content text contains `✅` or
   `⛔`, otherwise **59**. Overlay the content text onto the front of `CONTENT_MASK`, capped at
   `W` characters — the content's characters (the glyph counts as one character here, same as any
   other) replace the mask's first `len(content)` characters, never more than `W` of them. Any
   `œ` remaining **from position `len(content)+1` through position `W`** (not through position 59
   — when `W` is 58, `CONTENT_MASK`'s 59th character takes no part in this row at all: not
   overlaid, not left as a padding `œ`, simply excluded) is left untouched at this step, to become
   a space at step 4.
3. Concatenate: `│ ` + masked label + masked content + ` │`.
4. Replace every remaining `œ` in the assembled row with a plain space.

**Label wrapping (long labels):** step 1 assumes the label leaves at least one trailing space in
`LABEL_MASK` before content begins — every existing short label (`Solution`, `Phase`, `Status`,
`Active`, `Have Docs`, etc.) does. A label of **11 characters or more** leaves zero trailing
space: step 1's overlay fills the entire label field, so label and content text would render
touching with no visual separator at all. When the label is that long, wrap the label instead:
break it at the last space at or before 10 characters (reserving at least 1 trailing space, same
minimum every shorter label already gets for free), overlay this first chunk onto `LABEL_MASK` as
step 1 describes, and leave this line's entire content field blank (`W` spaces — no row text on
this line). On the next line, overlay the label's remaining chunk onto a fresh `LABEL_MASK`
(padded with trailing spaces as normal, same as any short label) and start the actual content
there — itself subject to the Wrapping-long-content rule below if it doesn't fit on one line.
Repeat until the whole label is written, mirroring the same "repeat until fully written" pattern
the content-wrapping rule below already uses. For `Next Action` (used in the phases-active and
post-Phase-7-no-active-project variants — 11 characters, no natural gap): `Next` alone on the
first line with a blank content field, then `Action` (padded to 11, same as any short label) on
the second line with the Next Action text starting there.

**The finished content field's raw length must equal `W` exactly — count it, don't estimate it.**
Treating `W` as approximate rather than exact fails in two opposite directions: (a) treating a
glyph as occupying only one `CONTENT_MASK`
position, which leaves the field at 59 when it should be 58, pushing the right border one column
too far right; (b) stopping the field at wherever the visible text (or wrapped chunk) happens to
end, without padding the remainder out to the full `W`, which leaves the field one short and
pulls the right border one column too far left. Padding to exactly `W` is not optional finishing
— it is the row being correct or not; see the change log referenced at the end of this section
for confirmed incidents of both directions.

**Wrapping long content:** if the content text is longer than this row's usable width `W` (58 or
59, per the glyph check above), break it at the last space at or before `W` characters. Overlay
the first chunk onto a fresh `CONTENT_MASK` for this row exactly as in step 2 above — capped at
`W`, then padded with `œ`→space out to `W` exactly, same as any other row (the glyph, if present,
is always in the first chunk, so the first chunk's `W` is 58; every other chunk's `W` is 59, no
row in a wrap ever uses any other pair of numbers). For the continuation row, leave `LABEL_MASK`
un-overlaid (all `œ` → all spaces, i.e. a blank 11-character label field — still 11 characters,
not fewer) and overlay the remaining chunk onto another fresh `CONTENT_MASK`, padded out to the
full 59-character width exactly (continuation chunks never carry the row's glyph, so `W` is
always 59 here). Repeat until the full content is written. Every resulting row — first chunk and
every continuation — is still a normal row for the purposes of the length check above: its content
field must total exactly `W`, no exceptions for being a wrap remainder. This applies most often to
`haltMessage` in the read-docs-halt fallback case, and to `halt_reason` in the halted variant if it
runs long.

**History:** the rules above and below exist because of confirmed prior alignment failures and one
confirmed process violation. That record is not part of this procedure and agent shall not attempt to find or read it to execute this skill correctly.

**The `œ`-mask's visibility is the complete, intended safeguard against under-padding — not a
first line of defense meant to be backed up with a second check.** If a row is under-padded, an
`œ` remains where a space should be; that is the detection mechanism. Reaching for any additional
tool call — a script, a scratch file, a `Read` to inspect what was just written — is not "extra
caution," it is the prohibited action, however the tool call is described internally ("just
checking," "just displaying," "just a counting aid"). This applies with no exception for every
row in every dynamically-built variant.

**This step is a deliberate, standing exception to any general "verify before asserting
completion" instinct or skill** — including but not limited to a `verification-before-
completion`-style standing instruction, and any environment-level guidance encouraging scratch
files "for intermediate results" or "during analysis." Those defaults are correct in general and
wrong here specifically — do not run a comparison between this rule and a general verification
habit before acting; the comparison has already been made and decided, in this document, in
advance.

**Worked example — glyph row and combined label-wrap/content-wrap:**

*Glyph row — `Status` = `✅ active`:*
1. Label: `"Status"` (6 chars) overlaid on `LABEL_MASK` → `Status` + 5 untouched `œ` → after
   step 4: `"Status     "` (11 chars — 6 letters + 5 spaces).
2. Content contains `✅` → `W = 58`. `"✅ active"` is 8 chars, overlaid on a fresh
   `CONTENT_MASK` capped at 58 → 8 chars + 50 untouched `œ` (positions 9–58; position 59 takes
   no part in this row at all) → after step 4: `"✅ active"` + 50 spaces (58 chars total).
3. Row: `"│ "` + 11-char label field + 58-char content field + `" │"` = 2 + 11 + 58 + 2 = **73**
   raw characters — the correct target for any row whose own content contains `✅`/`⛔`.

*Wrapped label + wrapped content — `Next Action` = `Run /sdp-solution-phase-coordinator to
continue Phase expanded_concept.`:*
1. `"Next Action"` is 11 characters — the full label field width, no trailing separator space —
   so the Label wrapping rule applies. Break at the last space at or before position 10: chunk
   `"Next"` (4 chars), remainder `"Action"` (6 chars).
2. Line 1: `"Next"` overlaid on `LABEL_MASK` → `"Next       "` (11 chars). Content field left
   entirely blank — no glyph on this line, so `W = 59` spaces. Row = 2 + 11 + 59 + 2 = **74**.
3. Content text (`"Run /sdp-solution-phase-coordinator to continue Phase expanded_concept."`,
   71 chars) exceeds `W = 59` (no glyph on this row) → the content-wrapping rule applies. Break
   at the last space at or before character 59: chunk `"Run /sdp-solution-phase-coordinator to
   continue Phase"` (53 chars), remainder `"expanded_concept."` (17 chars).
4. Line 2: `"Action"` overlaid on a fresh `LABEL_MASK` → `"Action     "` (11 chars). First
   content chunk (53 chars) overlaid on a fresh `CONTENT_MASK` capped at 59, padded to 59
   exactly (53 chars + 6 trailing spaces). Row = 2 + 11 + 59 + 2 = **74**.
5. Line 3 (continuation): `LABEL_MASK` left fully un-overlaid → 11 spaces. Remaining chunk
   (`"expanded_concept."`, 17 chars) overlaid on a fresh `CONTENT_MASK`, padded to 59 exactly
   (17 chars + 42 trailing spaces). Row = 2 + 11 + 59 + 2 = **74**.

Every row above lands on exactly 73 or 74 raw characters per the rule already stated — the point
of tracing all three numbers at each step is to make the arithmetic pattern copyable.

## Constraints

- Does not modify `sdp-solution-read-docs` in any way — it is invoked, not inlined or forked.
- No script is authored or invoked for banner rendering.
  Broadened: no tool call of any kind — a script, or `Read`/`Write` used only to inspect or
  count — generates or verifies a banner row, in Step 1, Step 3, or the Body Row Construction
  procedure. Composing and checking row text is silent, in-context work only; there is no
  exception for a tool call that merely displays text rather than computing it.
- Step 1 (opening banner) must complete before Step 2 begins — no workspace file is read before
  the opening banner prints, other than the bootstrap doc's version header.
- Step 3 always runs, even when Step 2 halted — the halt is captured and surfaced in the closing
  banner, never used as a reason to skip it.
- Never read `SDP-Solution.json` before checking `~SDP-Maintenance`, regardless of Step 2's
  outcome.
- Never render more than one closing-banner variant, and never render zero, per invocation.
- Both banners are printed inside fenced code blocks — never as bare chat text.
- Fixed Templates are reproduced verbatim, not retyped from memory (see Fenced Output and Exact
  Reproduction above).
- No chat text other than the two fenced banners and the one permitted closing statement
  (see Output Discipline) is produced by this skill.

## Outputs

- Opening banner printed to chat (fenced) before any workspace file is read (beyond the version
  header).
- `sdp-solution-read-docs` runs internally between the two banners, invoked with `--no-tone` so
  its own tone calls are skipped — its confirmation output is consumed for halt detection only
  and is not relayed to the user.
- Closing banner printed last (fenced), exactly one of the variants defined in Step 3 (see
  `docs/sdp-intro-design.md`).
- One short closing statement printed after the closing banner, tied to the solution state the
  banner just reported, inviting the user's next instruction.
- No files are written by this skill.
