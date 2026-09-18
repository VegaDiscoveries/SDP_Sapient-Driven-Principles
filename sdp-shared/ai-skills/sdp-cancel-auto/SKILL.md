## Purpose

Cancel the running SDP auto-loop by identifying and deleting the active cron job(s) created
by `sdp-auto`. Uses `CronList` to find SDP state-loop jobs and `CronDelete` to remove them. This
is the only place in SDP that calls `CronList`/`CronDelete` — invoked directly by the user, or
automatically by `sdp-project-state-loop`, `sdp-solution-state-loop`, and
`sdp-solution-phase-state-loop` themselves whenever a fire's outcome is `STOP` or a halt (each of
those skills' own Record-the-Fire step calls this skill rather than duplicating the cancellation
mechanism).

## Procedure

### Step 1: List Active Cron Jobs

1. Call `CronList` with no arguments.
2. If the result is empty or contains no jobs: invoke
   `/sdp-create-banner icon=warning row=0 row: Status | No cron jobs are currently running — no SDP loop to stop.`
   Halt.

### Step 2: Identify SDP Loop Jobs

1. From the `CronList` results, collect all jobs whose prompt or command contains the text
   `sdp-project-state-loop` OR `sdp-solution-state-loop` OR `sdp-solution-phase-state-loop` —
   mirroring the sibling skills (`sdp-auto`, `sdp-state-loop-start`,
   `sdp-solution-new-concept-intake`), which all check the first two; this skill additionally
   recognizes the solution-phase loop so one skill stops whichever loop is actually running.
2. If no matching jobs are found: invoke
   `/sdp-create-banner icon=warning row=0 row: Status | No SDP state-loop cron jobs found in the active job list. The loop may not be running, or it was started outside this session.`
   Halt.
3. Record the `id` of each matching job, and classify each match by which text it matched:
   **phase-loop** (`sdp-solution-phase-state-loop`) or **post-phase7-loop**
   (`sdp-project-state-loop` or `sdp-solution-state-loop`). A single fire's `CronList` result
   should never contain both classes at once (`sdp-solution-phase-auto`/`sdp-auto`/
   `sdp-state-loop-start` each cancel the other class before starting their own), but record both
   flags independently regardless, so Step 3 can compose accurate guidance even in that
   unexpected case.

### Step 3: Cancel Each Matching Job

1. For each recorded job ID, call `CronDelete` with that `id`.
2. Compose the restart guidance from Step 2 sub-step 3's classification:
   - Any **phase-loop** match: include `Run /sdp-solution-phase-auto to restart it once the
     required action (brainstorming, halt resolution, etc.) is complete.`
   - Any **post-phase7-loop** match: include `Run /sdp-auto to restart post-Phase-7 dispatch.`
   - Both classes matched: include both sentences. Never fall back to a single generic
     "Run /sdp-auto to restart" — `/sdp-auto` refuses to start while phases 1-7 are active, so
     that instruction is actively wrong for a cancelled phase-loop job.
3. Invoke
   `/sdp-create-banner icon=success row=0 row: Status | sdp-cancel-auto: cancelled [N] SDP state-loop cron job(s) — IDs: [list]. [restart guidance from sub-step 2]`

## Constraints

- Never call `CronDelete` on a job whose prompt or command does not contain the text
  `sdp-project-state-loop`, `sdp-solution-state-loop`, or `sdp-solution-phase-state-loop`.
- Never report a single fixed restart command — the guidance in Step 3 sub-step 2 always matches
  the actual class(es) of job cancelled.

## Outputs

- Each matching cron job deleted via `CronDelete`.
- One confirmation message listing cancelled job IDs, count, and restart guidance matched to the
  cancelled loop's class (phase-loop vs. post-phase7-loop).
