# Stress test, 2026-10-07

Run on macOS with agy 1.3.1, opencode 1.18.35 and gemini 0.50.0. Each row
is something that was actually run, not reasoned about. The fixture is a
small Python repo: 8 near-identical service modules, one existing test
file, and a `check.sh` the worker is told not to edit. The work order asks
for typed errors, loggers and f-strings in all 8 modules plus 7 new test
files (16 files, 32 tests).

## Results

| # | Test | Result |
| --- | --- | --- |
| 1 | Probe opencode, free model | pass, 6 to 7s |
| 2 | Probe agy | pass, 17 to 23s |
| 3 | Probe gemini in an untrusted folder | exit 55, refuses to run |
| 4 | Probe gemini with `--skip-trust` | 3 runs, all retried HTTP 503 until killed |
| 5 | opencode with a model whose key is rejected | exit 1 in 3 to 6s |
| 6 | opencode with an unknown provider/model | exit 1 in 3s |
| 7 | agy with an unknown model | exit 1, prints valid ids |
| 8 | Full work order on opencode free | 16 files, verify passed, 66s, report followed the contract |
| 9 | Full work order on agy `accept-edits` | shell call denied, 0 files, exit 0, 107s |
| 10 | Same on agy with a no-shell work order | 11 of 16 files, print timeout at 280s, exit 0 |
| 11 | Kill agy 30s into the step | exit 124, 0 files, no orphan processes |
| 12 | Ask opencode to write outside `--dir` | relative and absolute paths both refused |
| 13 | Ask agy to write outside the workspace | never got that far: shell denied, 0 files |
| 14 | Protected test contradicts the work order | opencode left the test and `check.sh` alone and reported the failure and its cause |
| 15 | Snapshot and restore in a git repo with staged and untracked user work | state identical to before the step |
| 16 | Snapshot and restore outside git | edits, deletion and new file all undone |

## What the skill got wrong before this run

1. No way to enforce a budget. The skill said "wall-clock budget" and stock
   macOS has no `timeout`. Fixed by `scripts/budget`.
2. Exit codes were trusted for agy. agy exits 0 on a denied permission and
   on a print timeout that leaves a partial diff (rows 9 and 10). The skill
   now decides on the verify result only.
3. The primary worker could not do its job. Three of six table rows routed
   to agy, which under a host that blocks `--dangerously-skip-permissions`
   cannot run a verify command at all. opencode is now first, and agy gets
   a no-shell work order.
4. "Revert the partial diff" had no safe mechanism. Outside git there was
   none, and inside git the obvious commands would also destroy the user's
   own uncommitted work. Fixed by `scripts/snap`.
5. gemini's hang was misread. It is the trust check plus silent 503
   retries, not a prompt problem (rows 3 and 4).
6. The note "opencode exits 0 when the model call errors" did not
   reproduce: auth and unknown-model errors exit 1 (rows 5 and 6).
7. The 15 minute estimate for the free opencode model was off by an order
   of magnitude on this task (row 8).
8. Machine-specific rosters, model ids and auth notes were baked into the
   skill text. They now live in `roster.md`.

## Not tested

- Whether the orchestrator model obeys the delegation gate. That needs
  fresh sessions with and without the skill on the same tasks.
- Token savings end to end. The fixture's work order is about 250 words
  against roughly 350 changed lines, so the saving is real but depends on
  how much verification reading the orchestrator does.
- An agy `permissions.allow` rule, Windows, Linux, `codex`, `muse`.
- Repos large enough that a whole-workspace snapshot is slow.
