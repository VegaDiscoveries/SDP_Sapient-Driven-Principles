## Purpose

Cancel the running SDP auto-loop by identifying and deleting the active cron job(s) created
by `sdp-auto`. Uses `CronList` to find SDP state-loop jobs and `CronDelete` to remove them.

## Procedure

### Step 1: List Active Cron Jobs

1. Call `CronList` with no arguments.
2. If the result is empty or contains no jobs: invoke
   `/sdp-create-banner icon=warning row=0 row: Status | No cron jobs are currently running — no SDP loop to stop.`
   Halt.

### Step 2: Identify SDP Loop Jobs

1. From the `CronList` results, collect all jobs whose prompt or command contains the text
   `sdp-project-state-loop` OR `sdp-solution-state-loop` — mirroring the sibling skills
   (`sdp-auto`, `sdp-state-loop-start`, `sdp-solution-new-concept-intake`), which all check both.
2. If no matching jobs are found: invoke
   `/sdp-create-banner icon=warning row=0 row: Status | No SDP state-loop cron jobs found in the active job list. The loop may not be running, or it was started outside this session.`
   Halt.
3. Record the `id` of each matching job.

### Step 3: Cancel Each Matching Job

1. For each recorded job ID, call `CronDelete` with that `id`.
2. After all deletes: invoke
   `/sdp-create-banner icon=success row=0 row: Status | sdp-cancel-auto: cancelled [N] SDP state-loop cron job(s) — IDs: [list]. Run /sdp-auto to restart.`

## Constraints

- Never call `CronDelete` on a job whose prompt or command does not contain the text
  `sdp-project-state-loop` or `sdp-solution-state-loop`.

## Outputs

- Each matching cron job deleted via `CronDelete`.
- One confirmation message listing cancelled job IDs and count.
