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

# Second round, 2026-10-08

## Script bugs found and fixed

| # | Test | Before | After |
| --- | --- | --- | --- |
| 17 | Worker edits a file inside a nested git repo | not in `snap diff`, not restored; a nested repo with no commits made `snap save` fail | `snap save` names nested repos and skips them |
| 18 | Worker edits a gitignored file (`.env`) | not in `snap diff`, not restored | `snap diff` prints "changed but gitignored"; still not restorable |
| 19 | Global `core.hooksPath` or `commit.gpgsign` set | `snap save` ran the user's pre-commit hook and failed | hooks and signing are off for the shadow store |
| 20 | `snap save` in `$HOME` or `/` | would snapshot the whole home directory | refused |
| 21 | Step name with a space or `..` | raw git error | clear error, exit 2 |
| 22 | `snap` in a subdirectory or a git worktree | `.agents/` showed in `git status` | excluded through `git rev-parse --git-path` |
| 23 | A CLI that echoes the prompt inside its auth error | probe reported pass, because "pong" was in the prompt | the expected answer is no longer in the prompt |
| 24 | `budget 0 <cmd>` | ran with no limit | rejected |
| 25 | `budget` killed with SIGKILL | worker is orphaned | not fixable; SIGTERM and SIGINT do clean up |
| 26 | Two `snap` commands at once | `index.lock` error | documented: run them one at a time |

`budget` otherwise held up: exit codes pass through, grandchildren and a
child that ignores SIGTERM are killed, stdin is closed.

## Orchestrator runs

Claude Opus 5.5 in headless mode (`claude -p`), one run per row. Cost and
tokens are from the session's own result record.

Task A, uniform: 10 near-identical modules, same edit in each, 9 new test
files.

| Run | Delegated | Output tokens | Cost | Time |
| --- | --- | --- | --- | --- |
| Skills disabled | no | 2,667 | $0.33 | 27s |
| Skill installed, not named | no | 2,601 | $0.33 | 29s |

Both wrote a generator script. Delegating would have cost more.

Task B, varied: 12 unrelated modules (1,136 lines, 86 public functions),
a docstring for every function and a test file with 8+ tests per module.
The checker fails if any code changes apart from docstrings.

| Run | Delegated | Output tokens | Cost | Time | Tests written |
| --- | --- | --- | --- | --- | --- |
| Skills disabled | no | 43,108 | $1.60 | 391s | 169 |
| Skill installed, not named | no | 36,247 | $1.48 | 321s | 203 |
| Skill named in the prompt | yes, opencode free, one step | 3,270 | $0.43 | 399s | 311 |

A small task (rename one function) with the skill installed stayed inline,
as it should.

What this showed:

1. The saving is real on varied work and absent on uniform work.
2. With the old description the skill never triggered unless named. The
   gate's "no design choice left to the worker" ruled out exactly the work
   that pays. The description and gate were rewritten after these runs.
   See the trigger table below.
3. The 12 modules themselves were generated by the free opencode model
   through `snap` and `budget` in 293s, verified by import.

## Trigger rate

Task B prompt, skill not named. Short runs, stopped as soon as the session
either loaded the skill or began writing files itself.

| Setup | Loaded the skill |
| --- | --- |
| Old description | 0 of 1 |
| New description | 3 of 4 |
| New description plus a one-line `CLAUDE.md` rule | 2 of 2 |
| New description plus "keep your own token use low" in the prompt | 1 of 1 |
| "ALWAYS load this skill BEFORE..." description (not shipped) | 4 of 4 |

With the "ALWAYS" description a one-function rename stayed inline without
loading the skill, and uniform Task A loaded it and then scripted the
change inline as the gate says ($0.39 against $0.33 without the skill).

## Test quality

The same 150 single-point mutations (operator swaps, off-by-one constants)
applied to `lib/`, counted as caught when the module's test file fails.

| Tests written by | Caught | Lines of tests |
| --- | --- | --- |
| Opus, skills disabled | 140 (93%) | 1,259 |
| Opus, skill installed but unused | 144 (96%) | 1,461 |
| opencode free worker | 136 (90%) | 1,858 |

## Other workers on the Task B work order

| # | Worker | Result |
| --- | --- | --- |
| 27 | Three `opencode run` started together | two exited 1 in 1s with "database is locked"; started 6s apart, no lock error |
| 28 | opencode `exo-free` | "Endpoint is unavailable" after 85s, 0 files |
| 29 | gemini free tier | 4 of 12 test files, then input token quota, retried until killed at the budget |
| 30 | opencode `ling-3.1-flash-free`, `nemotron-3.5-lightning-free` | inconclusive: the machine slept during both attempts |
| 31 | `snap restore` after the partial gemini run | all 8 changed files undone |

`budget` uses `alarm`, which does not advance while the machine sleeps, so
a 480s budget spanned a longer wall-clock time in rows 29 and 30.
