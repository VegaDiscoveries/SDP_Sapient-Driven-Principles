## Purpose

Execute the one-time solution-root workspace setup and/or the per-project Add-Project Steps
defined in `SDP-Workspace-Setup.md`, deterministically, instead of an agent freehanding that
1,400+ line reference document from scratch each time. This is the concrete next action for two
existing call sites that previously only pointed at prose:

- `sdp-solution-read-docs`'s halt — "`SDP-Solution.json` not found at solution root" — now
  names this skill instead of a generic "run solution setup."
- `sdp-new-concept-intake`'s Step 4 "new project" pause, which explicitly defers project
  scaffolding to whatever handles `SDP-Workspace-Setup.md`'s Add-Project Steps — this skill is
  that handler.

## Inputs

- `SDP-Solution.json` at the solution root — may be absent, or present but unpopulated (the
  shipped template: `solution_name: "[SolutionName]"`, empty `projects`/`last_active_projects`)
- `sdp-shared/docs/SDP-Workspace-Setup.md` — authoritative step-by-step checklist and file
  templates for both solution-root setup and per-project setup. Not auto-loaded by
  `sdp-project-read-docs` — this skill reads it explicitly every invocation (never assume its content
  from a prior session; it may have been amended).
- User answers to the Q0 setup-input questions (solution name, synopsis, project types, IDE)

## Procedure

### Step 0: Read the Reference Doc and Determine Mode

1. Read `sdp-shared/docs/SDP-Workspace-Setup.md` in full.
2. Check `SDP-Solution.json` at the solution root:
   - **Absent, or present with `solution_name` still the literal placeholder
     `"[SolutionName]"` and both `projects` and `last_active_projects` empty** (the shipped,
     never-configured template state): this is **first-run mode** — solution-root setup has not
     happened yet. Proceed to Step 1.
   - **Present and configured** (a real `solution_name` and at least one `projects` entry):
     solution-root setup is already done. Skip Step 1 entirely — do not re-run it, do not
     re-create `SDP-Solution.json` or the solution-level folders. Proceed directly to Step 2 for
     the new project(s) being added.

### Step 1: Solution-Root Setup (first-run mode only)

Follow `SDP-Workspace-Setup.md`'s **Setup Checklist → Solution Setup** section, in order:

1. **Collect setup inputs (Step 0 of that checklist)** — derive a preliminary solution name from
   the root folder name and propose it for confirmation; ask Q1–Q3 to compose the synopsis; ask
   Q4 for the project types (propose the full `sdp-project_*` folder list, PascalCase dotted
   naming); ask Q5 for the development environment (Visual Studio/Rider, VS Code, agent-only, or
   other); ask Q6 — detect the GPG standards doc version present in `standards/` and explicitly
   ask the user to confirm it (or name a different one) before any scaffolding begins. Present
   the complete setup plan as a banner:
   `/sdp-create-banner icon=info,info,info,info,info row=0,1,2,3,4 row: Solution | [confirmed name] row: Synopsis | [synopsis] row: Projects | [Q4 project list] row: IDE File | [IDE file to create] row: GPG Version | [confirmed Q6 version]`
   — then, as a separate, real question immediately after the banner, wait for explicit user
   confirmation. **Do not create any file or folder before this confirmation.**
2. **Verify the SDP framework is already present** — `sdp-shared/`, `standards/`, `.claude/`, the
   bootstrap doc(s), `SDP-Config.json`. (`SDP-Tones.json` is not part of this check — it is
   created during this setup, not copied in; see the "Create `SDP-Tones.json`" checklist step.)
   If any are missing: halt and tell the
   user to copy them in per `QuickStart.md`'s "Add to an existing solution" step before this
   skill can continue — this skill scaffolds workflow state and registration, not the framework
   files themselves.
3. **Conduct-rules check** — per that checklist's Step 1.5, exactly as written there (template
   vs. existing `~/.claude/CLAUDE.md` / `.claude/rules/*.md` comparison, full/partial/no-match
   classification).
4. **Create solution-level workflow folders (Step 2)** — `.sdp-solution-workflow/` (`state.json`
   stub, `sessions/`), `sdp-solution-docs/` (`00_solution_prompt.txt` stub,
   `00_user_notes.txt` stub, `user-design-docs/` + `user-design-docs/processed/` with READMEs),
   `sol-shared/` placeholder.
5. **Create `README.md` (Step 2.5)** — using that checklist's template, with the confirmed
   synopsis and the Q4 project list.
6. **Create `SDP-Solution.json` (Step 3)** — using the multi-project or single-project template,
   `solution_name` from Step 0's confirmation, all Q4 projects registered, `last_active_projects`
   set to the first project.
7. **Create the IDE workspace file (Step 3.5)** — based on the Q5 answer; skip entirely for
   agent-only.
8. **Verify solution infrastructure (Step 4):**
   - Session Start hook present in `.claude/settings.local.json` (a genuine file-presence check).
   - **SUPERPOWERS CHECK** — verify the Superpowers plugin is installed by actually running
     `/plugin list`, matching every other role skill's SUPERPOWERS CHECK (`sdp-project-coordinator`,
     `sdp-project-worker`, `sdp-project-reviewer`, `sdp-project-gate-review`). `/plugin list` is a harness command, not a
     filesystem fact — it must actually be invoked. Do not infer installation from
     `.claude/settings.local.json`'s `enabledPlugins` field (that reflects what the SDP template
     shipped/enabled, not proof the plugin package is actually installed and resolvable in this
     environment) or from any other skill in this session having worked (SDP skills are invoked
     explicitly by name and do not depend on the Superpowers plugin, so their success proves
     nothing about it). If missing: note it and continue per the other role skills' precedent —
     this does not block setup, but WORKER/REVIEWER sessions must be told to apply equivalent
     discipline manually.
   - PowerShell available; all `sdp-` skill pairs present at both levels; script permission
     entries present in `permissions.allow`; standards files (GPG or custom) present in
     `standards/`. Halt and ask the user to resolve anything missing before proceeding to Step 2
     of this skill.

### Step 2: Add-Project Steps (always — once per confirmed project)

For each project confirmed in Q4 (first-run mode) or the single new project being added
(already-configured solution, invoked directly or via `sdp-new-concept-intake`'s hand-off):
follow `SDP-Workspace-Setup.md`'s **Setup Checklist → Add-Project Steps** section verbatim, in
order — project name/description confirmation; `sdp-project_[AppName.xxx]/` folder scaffold
(`.sdp-workflow/`, `sdp-docs/` — stub `00_user_notes.txt` and empty `00_prompt.txt` only, no
phase docs; `shared/`); `SDP-Workspace-Setup.json`,
`SDP-Document-List.json`, `PATTERNS.md` creation; registration in `SDP-Solution.json`'s
`projects` array and `last_active_projects`; `README.md` projects-table row; Patterns Library
review; GPG chapter relevance note. **Do not** ask which phase to start in and **do not** create
any phase document stub — a project no longer has phases of its own; its
`.sdp-workflow/registry.md` starts and stays empty until a future solution-level Phase 7
decomposition assigns it implementation tasks. Create empty stub `[PROJECT]-Context.md` and
`[PROJECT].speq.md` files here
(template placeholders only, per `SDP-Workspace-Setup.md`'s `.speq` Contract Template),
registered in the project's `SDP-Document-List.json` — population with real, settled content is
deferred to Phase 7's build-phase decomposition (`sdp-solution-phase-coordinator` Step 2b), not
to any project-local "Phase 1," which no longer exists under the solution-scoped model.

### Step 3: Report and Hand Off

Report the created solution/project structure and confirmed IDE file (if any) to the user as a
success banner. The `Next Step` row's text depends on whether this project's `registry.md` was
just created empty by this same invocation (Step 2 always scaffolds it empty — a freshly
scaffolded project always has zero phase rows, so COORDINATOR has nothing to dispatch and would
immediately halt on first invocation):

`/sdp-create-banner icon=success,success,success,success row=0,1,2,3 row: Structure | [created solution/project structure] row: IDE File | [confirmed IDE file, if any] row: Next Step — Have Docs | Drop them in sdp-solution-docs/user-design-docs/ and run /sdp-new-concept-intake for the active project ([name]). row: Next Step — No Docs Yet | Run /brainstorming first — save the resulting doc to sdp-solution-docs/user-design-docs/ (not Superpowers' own default spec location) — then run /sdp-new-concept-intake to advance it.`

If this invocation was triggered by `sdp-new-concept-intake`'s "new project" pause, also change
`icon=success,success,success,success row=0,1,2,3` to
`icon=success,success,success,success,success row=0,1,2,3,4`
and add `row: Intake | The paused concept-intake set can now proceed since the target project
exists and is registered.` to the same invocation — do not prefix this added row with its own
`row=` fragment; the row index list was already extended to include it in the `icon=`/`row=`
directive above, and at most one `row=` directive is permitted per invocation. Do not draft
Phase 1 content and do not spawn a COORDINATOR, WORKER, or
REVIEWER subagent from within this skill — this mirrors the discipline `sdp-new-concept-intake`
already applies to itself.

## Constraints

- Never create any file or folder before Step 1's setup plan is confirmed by the user.
- Step 1 runs at most once per solution — Step 0's mode check is the only gate; never re-run
  solution-root setup once `SDP-Solution.json` is configured.
- Does not draft Phase 1/3 content and does not spawn COORDINATOR/WORKER/REVIEWER — mirrors
  `sdp-new-concept-intake`'s Step 6 discipline.
- `SDP-Workspace-Setup.md` is read explicitly every invocation (Step 0.1) — never assume its
  content from memory across sessions, since it is not auto-loaded and may have been amended.
- Framework files (`sdp-shared/`, `standards/`, `.claude/`, bootstrap doc) are a precondition
  this skill verifies, not something it creates — halt rather than scaffold them if missing.
- Create empty stub Project Context Document and `.speq` contract files during Step 2, registered
  in the project's `SDP-Document-List.json` — but never populate them with real content here;
  population happens at Phase 7's build-phase decomposition (`sdp-solution-phase-coordinator`
  Step 2b), not during Add-Project setup.
- Never include more than one `row=` directive across the invocations this skill issues in a
  single run.

## Outputs

- (first-run mode) Full solution-root scaffold: `.sdp-solution-workflow/`, `sdp-solution-docs/`,
  `sol-shared/`, `README.md`, `SDP-Solution.json`, IDE workspace file
- One or more `sdp-project_[name]/` folders, fully scaffolded and registered in
  `SDP-Solution.json` and `README.md`
- User-facing report; no subagent dispatched
