# AI-Assisted Development Workflow — Tone & Tune Notifications Reference

| Field | Value |
|-------|-------|
| **Companion doc** | `SDP_Sapient-Driven-Principles_vN.N.N.md` |
| **Config file** | `sdp-shared/scripts/script-support/SDP-Tones.json` |
| **Script** | `sdp-shared/scripts/sdp-tone.ps1` |
| **Updated** | 2026-06-23 |
| **File** | `SDP-Tone-Notifications.md` |

**Purpose:** Complete reference for SDP audible notifications — the configuration model, the
trigger catalog, and a tune-authoring guide. Load this file explicitly when composing tones,
binding triggers, or extending the tone system. Not loaded automatically by `sdp-project-read-docs` —
registered in `SDP-Document-List.json` with `"includeInReadDocs": false`.

---

## Overview

`sdp-tone.ps1` plays audible notifications via `[console]::Beep`. It has two channels:

| Channel | Invocation | Resolves | Plays |
|---------|-----------|----------|-------|
| **Skill tone** | `-skillName X -event start\|end` | `assignments` → `palette` | a single tone |
| **Workflow event** | `-trigger NAME` | `events` → `sequences` (+ `profiles`) | a multi-note sequence |

All configuration lives in `sdp-shared/scripts/script-support/SDP-Tones.json`. The script is a
non-blocking
utility: any missing, malformed, or disabled lookup results in a silent `exit 0`. Tones must
never block or halt a workflow.

Set `"enabled": false` at the top of `SDP-Tones.json` to silence everything globally.

**Metrics side-effect:** every real (non-`-whatIf`) invocation that reaches a resolved
skill-tone pair or trigger lookup — resolved or not — also appends one JSON line to today's
`loop-metrics-*.jsonl` file under
`.sdp-solution-workflow/logging/loop-logs/` at the solution root (one file per calendar day,
rotating purely by date regardless of workflow action; created on first write of the day). This
brackets subagent work (skill start/end) and
workflow events (halts, milestones) independently of `sdp-project-state-loop`'s own per-fire entries in
the same file. `-whatIf` never writes to this file. A metrics write failure is silently ignored —
it must never affect tone playback or the exit code. See the bootstrap doc's Loop-orchestrated
dispatch path section and the `sdp-report-log-loop-metrics` skill, which reads a selected day's file
to produce a time-accounting and halt/task-outcome report.

---

## Conceptual Model — four primitives

| Primitive | What it is | Lives in |
|-----------|-----------|----------|
| **Note** | An atomic `{hz, ms}` tone. | `palette` |
| **Sequence** | A named, ordered list of notes (palette-id strings and/or inline `{hz,ms}`), with optional gaps. A single beep is a length-1 sequence. | `sequences` |
| **Playback profile** | *How* a sequence renders: `repeat` count + `gapMs` between repeats. | `profiles` |
| **Binding** | Maps a **trigger** (a named workflow point) to a `sequence` + a `profile`. | `events` (workflow), `assignments` (skill start/end) |

Separation of concerns: *what sound* (sequence) · *how it plays* (profile) · *where it fires*
(binding). "Siren-ness" belongs in the sequence (alternating notes); repetition belongs in the
profile. To compose a new alert you edit JSON only — no script or skill changes.

---

## `SDP-Tones.json` Schema Reference

```jsonc
{
  "enabled": true,                       // global mute when false

  "palette": [                           // atomic notes (skill start/end)
    { "id": "A", "hz": 262, "ms": 400, "character": "..." }
  ],

  "assignments": [                       // skill start/end channel
    { "sdpSkillName": "*", "useAtSkillStart": "B" },
    { "sdpSkillName": "*", "useAtSkillEnd": "F" }
  ],

  "sequences": {                         // named note series
    "<name>": {
      "gapMs": 40,                       // default gap between notes in this sequence
      "notes": [                         // each element: palette-id string OR {hz, ms[, gapMs]}
        { "hz": 523, "ms": 160 },        //   inline note
        "A",                             //   palette-id reference
        { "hz": 0, "ms": 120 }           //   hz <= 0 is a silent rest
      ]
    }
  },

  "profiles": {                          // playback behavior
    "<name>": { "repeat": 4, "gapMs": 120 }   // repeat = times sequence plays; gapMs = between repeats
  },

  "events": [                            // trigger -> sequence + profile
    { "trigger": "halt.no_progress",
      "sequence": "siren",
      "profile": "burst",                // optional; defaults to "once"
      "repeat": 6,                       // optional inline override of the profile
      "gapMs": 100,                      // optional inline override
      "enabled": true }                  // optional; defaults to true
  ]
}
```

### Resolution rules (enforced by `sdp-tone.ps1`)

1. **Channel selection.** `-trigger` present → workflow-event channel. Otherwise `-skillName`
   + `-event` → skill-tone channel. Neither → silent exit.
2. **Event lookup.** First `events` entry whose `trigger` matches **and** `enabled` is not
   `false`. Its `sequence` is looked up in `sequences`; its `profile` in `profiles` (default
   `once`). Inline `repeat`/`gapMs` on the binding override the profile.
3. **Skill lookup.** Exact `sdpSkillName` match wins; only if no exact entry exists is the
   wildcard `"*"` used. An exact entry with no tone for the requested event is silent and does
   **not** fall through to the wildcard.
4. **Note resolution.** Palette-id string → looked up in `palette`. Inline object → used
   directly. `hz <= 0` → a silent rest of `ms` milliseconds. Out-of-range Hz (outside
   37–32767) throws in `Beep` and is swallowed.
5. **Silence on any gap.** Unknown trigger, missing sequence/profile, `enabled:false` (binding
   or global), no playable notes → silent `exit 0`.

### `-whatIf` (testing without audio)

`sdp-tone.ps1 -trigger "<name>" -whatIf` (or `-skillName X -event start -whatIf`) resolves the
full playback plan and writes it as a single compact JSON line to stdout **instead of** beeping.
Use it to verify resolution logic deterministically on headless/CI machines. Example output:

```json
{"resolved":true,"channel":"event","trigger":"halt.no_progress","sequence":"siren","repeat":6,"gapMsBetweenRepeats":120,"notes":[{"hz":880,"ms":220,"gap":0},{"hz":587,"ms":220,"gap":0}]}
```

A no-op resolves to `{"resolved":false, ... ,"reason":"..."}`. Without `-whatIf` the script
writes nothing to stdout.

---

## Trigger Catalog

Each trigger has a `sdp-tone.ps1 -trigger "<name>"` invocation at its hook point in the owning
skill. Whether it sounds is governed entirely by the `events` table — enabling, silencing, or
retargeting any trigger is a JSON-only edit. An invocation with no matching/enabled `events`
entry is silent.

### Halt / stop family

| Trigger | Fires when | Hook point | Wired |
|---------|-----------|-----------|-------|
| `api.error_detected` | `sdp-project-state-loop` finds `API Error:` in the scanned context (re-sounds each pass while present) | `sdp-project-state-loop` Step 5 API_RECOVERY block | ✅ |
| `halt.no_progress` | No-progress loop: `eval_cycle_attempts − eval_cycles ≥ threshold` → Halt Evaluation halts | `sdp-project-state-loop` Halt Evaluation — all halt outcomes | ✅ |
| `halt.generic` | Any other STOP: already-halted, DIAGNOSIS_BLOCKED, PARTIAL_COMPLIANCE_ESCALATE, no active item; COORDINATOR PREFLIGHT halt | `sdp-project-state-loop` Steps 2–3 STOP points; `sdp-project-coordinator` Step 1.1 (PREFLIGHT halt) | ✅ |

### Milestone family

| Trigger | Fires when | Hook point | Wired |
|---------|-----------|-----------|-------|
| `milestone.task_verified` | REVIEWER sets a work item VERIFIED | `sdp-project-reviewer` Step 6.1 (after status write) | ✅ |
| `milestone.phase_complete` | Phase gate PASSED, COORDINATOR advances `current_phase` | `sdp-project-coordinator` Step 4.5b (after phase_gate reset) | ✅ |
| `milestone.all_complete` | Final phase passes / project complete | `sdp-project-coordinator` Step 4.5d (before all-complete report) | ✅ |
| `milestone.doc_certified` | `sdp-project-doc-review` certifies a staged doc as gate-ready | `sdp-project-doc-review` Step 4.5 (after state file write) | ✅ |

### Gate family

| Trigger | Fires when | Hook point | Wired |
|---------|-----------|-----------|-------|
| `gate.blocked` | GATE_REVIEWER writes a GATE_BLOCKED verdict | `sdp-gate-review-finalize.ps1` (project-scoped) or `sdp-solution-phase-gate-review-finalize.ps1` (solution-scoped phases 1-7), after the status write | ✅ |

### Skill boundary family

| Trigger | Fires when | Hook point | Wired |
|---------|-----------|-----------|-------|
| `skill.sdp_initialize_sdp_end` | `sdp-initialize-sdp` finishes (its Level 1 shim's only tone step) | `.claude/skills/sdp-initialize-sdp/SKILL.md` Step 3 | ✅ |

### Reachability caveat — `api.error_detected`

The tone system is skill-invoked: a sound plays only when an SDP skill actually runs.
`api.error_detected` fires when `sdp-project-state-loop` *detects* an API error in context. If the
harness halts the loop session **without running SDP code at all**, no skill runs and no tone
fires. This is an accepted limitation; no harness `Stop` hook is used.

---

## Tune-Authoring Guide

Compose sequences from these references. `[console]::Beep` accepts integer Hz in **37–32767**;
values outside that range are silently skipped.

### Note Durations at 120 BPM

At 120 BPM one beat = 500 ms. Dotted values add 50% of the base value.

| Note value | ms | Note value | ms |
|---|---|---|---|
| Whole note | 2000 | Dotted eighth note | 375 |
| Dotted half note | 1500 | Eighth note | 250 |
| Half note | 1000 | Dotted sixteenth note | 188 |
| Dotted quarter note | 750 | Sixteenth note | 125 |
| Quarter note | 500 | Thirty-second note | 63 |

### Standard 88-Key Piano — Note Frequencies (A4 = 440 Hz, equal temperament)

| Note | Hz | Note | Hz | Note | Hz | Note | Hz |
|---|---|---|---|---|---|---|---|
| A0 | 27.50 | A1 | 55.00 | A2 | 110.00 | A3 | 220.00 |
| A#0/Bb0 | 29.14 | A#1/Bb1 | 58.27 | A#2/Bb2 | 116.54 | A#3/Bb3 | 233.08 |
| B0 | 30.87 | B1 | 61.74 | B2 | 123.47 | B3 | 246.94 |
| C1 | 32.70 | C2 | 65.41 | C3 | 130.81 | C4 *(Middle C)* | 261.63 |
| C#1/Db1 | 34.65 | C#2/Db2 | 69.30 | C#3/Db3 | 138.59 | C#4/Db4 | 277.18 |
| D1 | 36.71 | D2 | 73.42 | D3 | 146.83 | D4 | 293.66 |
| D#1/Eb1 | 38.89 | D#2/Eb2 | 77.78 | D#3/Eb3 | 155.56 | D#4/Eb4 | 311.13 |
| E1 | 41.20 | E2 | 82.41 | E3 | 164.81 | E4 | 329.63 |
| F1 | 43.65 | F2 | 87.31 | F3 | 174.61 | F4 | 349.23 |
| F#1/Gb1 | 46.25 | F#2/Gb2 | 92.50 | F#3/Gb3 | 185.00 | F#4/Gb4 | 369.99 |
| G1 | 49.00 | G2 | 98.00 | G3 | 196.00 | G4 | 392.00 |
| G#1/Ab1 | 51.91 | G#2/Ab2 | 103.83 | G#3/Ab3 | 207.65 | G#4/Ab4 | 415.30 |
| | | | | | | A4 | 440.00 |
| | | | | | | A#4/Bb4 | 466.16 |
| | | | | | | B4 | 493.88 |

| Note | Hz | Note | Hz | Note | Hz | Note | Hz |
|---|---|---|---|---|---|---|---|
| C5 | 523.25 | C6 | 1046.50 | C7 | 2093.00 | C8 | 4186.01 |
| C#5/Db5 | 554.37 | C#6/Db6 | 1108.73 | C#7/Db7 | 2217.46 | | |
| D5 | 587.33 | D6 | 1174.66 | D7 | 2349.32 | | |
| D#5/Eb5 | 622.25 | D#6/Eb6 | 1244.51 | D#7/Eb7 | 2489.02 | | |
| E5 | 659.26 | E6 | 1318.51 | E7 | 2637.02 | | |
| F5 | 698.46 | F6 | 1396.91 | F7 | 2793.83 | | |
| F#5/Gb5 | 739.99 | F#6/Gb6 | 1479.98 | F#7/Gb7 | 2959.96 | | |
| G5 | 783.99 | G6 | 1567.98 | G7 | 3135.96 | | |
| G#5/Ab5 | 830.61 | G#6/Ab6 | 1661.22 | G#7/Ab7 | 3322.44 | | |
| A5 | 880.00 | A6 | 1760.00 | A7 | 3520.00 | | |
| A#5/Bb5 | 932.33 | A#6/Bb6 | 1864.66 | A#7/Bb7 | 3729.31 | | |
| B5 | 987.77 | B6 | 1975.53 | B7 | 3951.07 | | |

`[console]::Beep` takes integer Hz — round these values.

---

## How-To

**Add a tune** — add a named entry to `sequences` (notes are inline `{hz,ms}` and/or palette
ids; `hz:0` is a rest). Optionally add a `profile` if it should repeat.

**Bind a trigger to a sound** — add or edit an `events` entry: `{ "trigger": "...",
"sequence": "...", "profile": "..." }`. Reuse one sequence across many triggers freely.

**Make an alert more obnoxious** — increase the bound profile's `repeat` (or set `repeat`
inline on the binding), or point the binding at a more dissonant/longer sequence.

**Silence a trigger** — set `"enabled": false` on its `events` entry (keeps it documented), or
remove the entry. Silence everything with top-level `"enabled": false`.

**Verify a change without sound** — run `sdp-tone.ps1 -trigger "<name>" -whatIf` and inspect the
JSON plan.

**Wire a tone into a new skill** — depends on the tone type:

- *Skill start/end tones:* Handled automatically by the standard Level 1 shim (`-skillName X
  -event start` and `-event end`). No change to the Level 2 SKILL.md procedure is needed. To
  assign a non-default tone to a specific skill, add an exact-match entry to `assignments` in
  `SDP-Tones.json` — exact name beats the wildcard `"*"` and does not fall through to it.
- *Differentiating tones across a whole scope/family of skills:* `assignments` only matches
  exact skill names, not prefixes — there is no glob support. To give an entire naming family
  (e.g. every `sdp-solution-*` skill) a distinct sound from the rest, add one exact-match
  `assignments` entry per skill in that family, all pointing at the same start/end palette pair,
  and leave the `"*"` wildcard as the default for everything outside that family. Pick the
  family's palette notes to differ in both Hz *and* ms from the wildcard default — a pitch-only
  difference on a single `[console]::Beep` note is easy to miss; a duration difference makes it
  audible even half-attentively. See the `H`/`I` pair (solution-scope start/end) for a worked
  example.
- *Workflow-event tones:* Wire in the Level 2 SKILL.md at the step where the event occurs.
  Use this boilerplate exactly — the non-blocking language is required:
  ```
  Play the notification tone (non-blocking — ignore any failure and continue): run
  `.\sdp-shared\scripts\sdp-tone.ps1 -trigger "trigger.name"` via the PowerShell tool.
  ```
  Steps: (1) add the trigger to `SDP-Tones.json` `events` (config before wiring);
  (2) add the boilerplate call in the SKILL.md procedure at the correct step;
  (3) add a row to the Trigger Catalog table in this document;
  (4) verify with `-whatIf` before committing.

---

## Constraints

- `sdp-tone.ps1` requires an explicit permission entry in `.claude/settings.local.json`:
  `"PowerShell(.\\sdp-shared\\scripts\\sdp-tone.ps1 *)"`. Subagents do not inherit wildcard
  permissions — without this entry, tone calls from COORDINATOR/REVIEWER subagents are silently
  blocked. See `SDP-Script-Authoring.md`.
- The script is the sole reader of `SDP-Tones.json`. No other skill or script reads tone config.
- Append-only does not apply to `SDP-Tones.json` — it is user-editable operational config, not a
  decision record.
- `sdp-tone.ps1` also writes to today's `loop-metrics-*.jsonl` file under
  `.sdp-solution-workflow/logging/loop-logs/` (append-only, one line per real invocation) — see
  Metrics side-effect above. `sdp-project-state-loop` is the only other writer of these files; both
  append to today's file, neither reads it back.
