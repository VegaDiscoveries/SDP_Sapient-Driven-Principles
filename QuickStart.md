# Sapient Driven Principles — A Self-Driving Process for Coding — Quick Start

Condensed workspace setup reference. For the full framework overview, see [`README.md`](README.md). For the complete step-by-step procedure and file templates, see [`SDP-Workspace-Setup.md`](sdp-shared/docs/SDP-Workspace-Setup.md).

---

## Workspace Setup

> **Open Claude Code at the solution root** — the folder containing `SDP-Solution.json` and `.claude/skills/`. Opening at a project subfolder means no skills are visible and every `/sdp-*` invocation silently fails.

> **Recommended: Claude Code `auto` permission mode.** SDP issues many PowerShell-tool calls per session (COORDINATOR/WORKER/REVIEWER dispatch, preflight, tone, banners). Running under `claude --permission-mode auto` avoids per-call prompt fatigue while keeping Claude Code's background safety checks — see `README.md` Requirements for detail. Not the same as `bypassPermissions`, which SDP does not recommend.

To set up a new solution or to add SDP to an existing solution/project:

— Open the existing solution/project folder and copy the base SDP folders and files into it (`.claude/`, `sdp-shared/`, `standards/`, the bootstrap doc [SDP_Sapient-Driven-Principles_vN.N.N.md], and `SDP-Config.json`).

Then:

1. Open Claude Code at that solution root.
2. Start a new session — the session start hook fires `sdp-initialize-sdp`, which loads workspace
   context and reports that `SDP-Solution.json` is missing (or unconfigured). It stops there and
   asks what you want to do next; it does not auto-start setup on a bare first message.
3. Run `/sdp-workspace-setup` — it asks for the solution's synopsis, the project types that make
   up the solution (a solution can register more than one from the start — this is a starting
   point, not a final list), IDE preference, and the rest of the setup inputs before creating any
   folders or files, then scaffolds the full solution and initial project structure per
   `SDP-Workspace-Setup.md`.

The setup is agent-driven: `sdp-workspace-setup` walks the full two-level procedure (solution root
first, then the first project) without requiring manual file creation from the user. Full
procedure and all file templates are in [`SDP-Workspace-Setup.md`](sdp-shared/docs/SDP-Workspace-Setup.md).

### Automated Gate Check Before First Dispatch

- Session Start hook wired in `.claude/settings.local.json` (auto-invokes `sdp-initialize-sdp`, which invokes `sdp-solution-read-docs` internally)
- Superpowers plugin installed: `/plugin list`
- `git` available on PATH (required by the Superpowers plugin and by `sdp-shared/scripts/sdp-github.ps1`) — validated by preflight
- `python` available on PATH (not used by SDP itself — see `README.md` Requirements for why it's still recommended)
- All skill pairs present at both Level 1 and Level 2
- GPG file present; `gpg_version` recorded in `state.json`
- `SDP-Config.json` created at solution root
- `SDP-Solution-Setup.json` created at solution root (solution-level preflight manifest)
- `.claude/rules/sdp-core-invariants.md` present (ships as a real file — no action needed)
- `.claude/rules/sdp-agent-conduct.md` present, or explicitly skipped with the dedup-check rationale logged in the setup plan
- `PreToolUse`/`PostToolUse` async hook for `sdp-hook-log.ps1` registered in `.claude/settings.local.json`, with `sdp-hook-log-tools.json` present at `sdp-shared/scripts/script-support/`
- Permission entries present for `sdp-hook-log.ps1` and `sdp-workflow-log.ps1`
- Preflight passes: `./sdp-shared/scripts/sdp-preflight.ps1 -workspaceRoot ./[project]`

---

## Starting a New Concept Cycle in an Existing Solution

The workspace setup above only applies once — the very first Phase 1–7 cycle of a solution.
Phases 1–7 are solution-scoped, not project-scoped: they run once per solution regardless of how
many projects it has, and project assignment doesn't happen until Phase 7's own decomposition
step — never at intake time. For every concept after that, at any solution maturity, use
`/sdp-new-concept-intake` instead of repeating workspace setup. Three options:

- **Document-driven** — you already have a concept/design doc ready. Drop it (and, if it has an
  accompanying `[doc_name]_Sections/[doc_name]_TOC.md` folder — the same pattern used for the
  GPG standards doc — the whole Sections folder too) into
  `sdp-solution-docs/user-design-docs/`. Run `/sdp-new-concept-intake`. It scans the drop zone,
  groups related files, and seeds seven new rows (Concept, Research, Expanded Concept,
  Architecture, Implementation Overview, Refined Implementation Plan, Phase Readiness) into the
  **solution's own** `.sdp-solution-workflow/registry.md` — no project is chosen or confirmed at
  this point. The source document is tracked and moved to
  `sdp-solution-docs/user-design-docs/processed/` — `sdp-source-coverage-check` compares it
  against the resulting Phase 1 and Phase 3 content (Concept and Expanded Concept) before Phase 4
  (Architecture) is allowed to begin, so scope isn't silently lost in the initial scan-and-extract
  step.
- **No doc yet, but want one** — run `/brainstorming` first to develop the concept, directing it
  to save the resulting spec straight into `sdp-solution-docs/user-design-docs/` (not
  Superpowers' own default spec location) — then run `/sdp-new-concept-intake`, which picks it up
  via the document-driven path above with no extra steps.
- **Conversational** — no document, just describe the concept directly when you run
  `/sdp-new-concept-intake`. Same seven-row seeding, minus the drop-zone scan and the source
  coverage check (nothing to compare against). Still the right choice for concepts too small to
  warrant full brainstorming rigor.

Either way, this skill only seeds the registry rows and phase stubs — it hands off to normal
`/sdp-solution-coordinator` dispatch for actual Phase 1 drafting (which still runs `/brainstorming`, per
the bootstrap document's Phase 1-3 authorship exception).

---

## Before an Unattended Run

`/sdp-auto` refuses to start until solution-level Phase 7's gate has passed — phases 1–7 are
always human-gated, direct `/sdp-solution-coordinator` dispatch, with no cron job involved at any
point during that stage.

**The first time** Phase 7's gate passes for this solution, run `/sdp-solution-loop-prep` once
before starting `/sdp-auto` — triggered by (and only valid at) that Phase-7-passed transition, it
sweeps *every* registered project's freshly-decomposed registry, not just one, and hands off to
`/sdp-auto` itself once done. If a later mid-stream `/sdp-new-concept-intake` cycle re-enters
phases 1–7 (which cancels any running loop), run `/sdp-solution-loop-prep` again once that
cycle's own Phase 7 gate re-passes, before restarting the loop.

`/sdp-project-loop-prep` is the single-project, on-demand counterpart to the above — useful for a
targeted re-check of one project's own registry outside the Phase-7-passed transition, but not
the primary before-first-run step for a multi-project solution.

Both close the same gap: a coordinator's own doc-review check only covers the active/in-progress
phase; every other not-yet-complete phase gets reviewed reactively, the moment the loop reaches
it, which is exactly the kind of open decision or oversized phase that turns into a mid-run stop.
Both walk every not-yet-complete phase (across all swept projects, for `/sdp-solution-loop-prep`)
in dependency order up front and certify three things per phase before the loop ever touches it:

- **Content readiness** (`sdp-project-doc-review`, unmodified)
- **Source coverage** (`sdp-source-coverage-check`, when a tracked source document exists)
- **Right-sizing** (`sdp-phase-rightsizing-check`) — splits an oversized phase into right-sized
  sub-phases before dispatch, instead of a WORKER discovering mid-session that the phase is too
  big to finish

Neither skill suppresses a finding to avoid interrupting you — every gap, coverage miss, or
right-sizing question surfaced is a real pause, not a shortcut. That's the point: resolve it now,
once, instead of it stopping an unattended run hours in.
