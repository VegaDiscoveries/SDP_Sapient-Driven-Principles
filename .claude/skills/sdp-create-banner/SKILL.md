---
name: sdp-create-banner
description: Render a runtime SDP status/error banner (fixed top/bottom border, dynamic labeled rows, optional named icons) from caller-supplied label/content pairs — used by any SDP skill that needs to display a mid-process banner. Not used for the session-opening banner (sdp-initialize-sdp owns that).
---

This skill has no L2 procedure file — `sdp-shared/scripts/sdp-create-banner.ps1` does all
tokenizing, icon resolution, and row/border construction. Everything needed to invoke this
skill is below; nothing else needs to be read first.

1. Run via the PowerShell tool, passing the invocation argument string verbatim:
   ```
   ./sdp-shared/scripts/sdp-create-banner.ps1 -Argument '[the invocation argument]'
   ```
   Prefer a single-quoted PowerShell string for `-Argument` (avoids `$`/backtick expansion in
   row content). If the content itself contains a literal single quote, double it (`''`).
2. If the script fails to run at all (not found, threw before emitting JSON): halt — report
   "⛔ sdp-create-banner: script did not run — [error]." to the user. Do not proceed.
3. Parse the script's JSON stdout: `{ "status": "success"|"error", "error": <string|null>, "banner": <string|null> }`.
   - `status: "error"` — halt: report `"⛔ " + error` to the user verbatim. Do not print a banner.
   - `status: "success"` — print `banner` verbatim inside a fenced code block (triple backtick,
     no language tag — bare chat text corrupts the box-drawing characters). This is the skill's
     only output; no surrounding commentary before or after it.

## Invocation Argument Grammar

Directives are found anywhere in the argument string, not by line — the slash-command channel
flattens newlines to spaces — so `icon=`, `row=`, and `row:` may appear in any order.

- **`row:`** — one row: `Label | Content`, split on the first `|`, both trimmed. One `row:` per
  row; as many as needed. Supply content full and un-wrapped — the script wraps it itself.
  Row order = the position of each `row:` trigger in the argument string, left to right.
  - **Blank-separator row:** `row: |` (empty label, empty content — just the `|` is required)
    renders as a full-width blank line inside the border, with no label/content text. Use it to
    visually separate a status row from a following row that needs to stand out — e.g. a
    confirmation question placed after a summary row, so it doesn't read as more passive status.
    A blank row still occupies a row index like any other — account for it when combining with
    `row=` (see below).
- **`icon=`** — a comma-separated list of icon names (see Icon Registry below). At most one
  `icon=` per invocation.
  - Paired with **`row=`** (comma-separated 0-based row indices, same length as `icon=`,
    matched positionally — first name ↔ first index): explicit row assignment.
  - Without `row=`: icons assign positionally, one per row, starting at row 0.
- Icons apply to a row's content only, never its label.
- Row content must not itself contain the literal sequences ` icon=`, ` row=`, or ` row:`
  (space-prefixed) — the script would misread it as a new directive boundary.

**Examples** (validated against the script):
```
icon=error row=0
row: Error | This is not the SDP Maintenance project. Unable to continue.
```
```
row: Solution | SDP-Website
row: Projects | SDPWebsite.Web, SDPWebsite.API, SDPWebsite.DB (3)
row: Phase | expanded_concept
row: Status | ✅ active
row: Next Action | Run /sdp-solution-phase-coordinator to continue Phase expanded_concept.
```
Positional fallback and order independence together, on one line, exactly as the slash-command
channel delivers it:
```
row: Status|Really bad things going on! row: Info|Not sure how bad it gets. icon=critical,warning
```
Blank-separator row setting off a trailing question (icon= row=0 still targets the first row —
the blank row and the question row that follow it are unaffected):
```
icon=success row=0
row: Conversion | Converted to .md — 14 headings detected, 6 tables preserved.
row: |
row: Confirm | Does this conversion look acceptable, or are there fidelity issues to flag?
```

## Icon Registry

Valid icon names, glyphs, and meanings live in
`sdp-shared/scripts/script-support/sdp-create-banner-icons.json`
— the script's own runtime data file, and the single source of truth (the script reads it
internally; nothing here duplicates it). Read that file directly when composing a new `icon=`
invocation and unsure of the exact name — do not embed its contents in this shim, which is read
on every invocation of this skill; the whole point of the script conversion was eliminating that
per-invocation cost.
An unknown icon name halts with the script's error message, which lists every valid name.

## Constraints

- This skill never renders the session-opening banner — that remains `sdp-initialize-sdp`'s
  responsibility.
- No file is written or modified by this skill or by the script.
- Never pass more than one `icon=` directive per invocation, and never apply an icon to a row's
  label — icons apply only to a row's content.
- Never allow row content to contain the literal sequences ` icon=`, ` row=`, or ` row:`
  (space-prefixed) — the script would misread it as a new directive boundary.
- Never embed the icon registry JSON's contents into this skill file — read
  `sdp-shared/scripts/script-support/sdp-create-banner-icons.json` directly when composing
  an `icon=` invocation.
