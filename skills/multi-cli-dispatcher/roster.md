# Roster

This file is per-machine. Edit it to match what `scripts/probe` reports on
yours. Versions and model ids below were observed on 2026-10-07 with
agy 1.3.1, opencode 1.18.35 and gemini 0.50.0 on macOS; expect them to
drift.

## Commands

Every command runs under `scripts/budget <seconds>` from the workspace
directory.

### opencode

```
opencode run "<prompt>" -m <provider/model> --dir <workspace>
```

- Run without `--auto`. Edits and shell work inside `--dir` and are refused
  outside it (tested with a relative and an absolute outside path).
- Can run the verify command itself.
- Auth and unknown-model errors exit 1 within seconds. A finished turn
  exits 0 whether or not the verify passed.
- List models with `opencode models`. Free models end in `-free`.
- Two `opencode run` commands started in the same second fail with
  "database is locked" and exit 1. Start parallel runs 5+ seconds apart.
- Free models differ a lot in uptime. `exo-free` answered a probe-sized
  prompt but returned "Endpoint is unavailable" on a real work order.

### agy (Antigravity)

```
agy -p "<prompt>" --model <id> --mode accept-edits --print-timeout <n>s
```

- In headless `accept-edits` mode any shell tool call is auto-denied, the
  turn ends with "no output produced", nothing is written, and the exit
  code is 0. So the work order must say: no shell, file tools only, skip
  verify. The orchestrator runs the verify.
- `--print-timeout` expiring also exits 0 and leaves a partial diff.
- `--dangerously-skip-permissions` lifts the shell limit, but hosts may
  block it. Do not retry it once refused. An allow-rule under
  `permissions.allow` in agy's `settings.json` is the scoped alternative
  (not tested here).
- An unknown model id exits 1 and prints the valid ids.
- List models with `agy models`.

### gemini

```
gemini -p "<prompt>" --skip-trust --approval-mode auto_edit
```

- Without `--skip-trust` (or `GEMINI_CLI_TRUST_WORKSPACE=true`) it exits 55
  in any folder not already trusted.
- On the free tier it retried HTTP 503 "high demand" silently until killed
  in most runs here, and on a 12-file work order it wrote 4 files and then
  hit the per-minute input token quota and retried until killed. Use it
  for small steps only, with a short budget, and treat it as a spare.

## Model table

| Step kind | Worker and model | Fallback |
| --- | --- | --- |
| Repetitive multi-file edit | `opencode` free model | `agy` `gemini-3.8-flash-high`, no-shell order |
| Bulk boilerplate | `opencode` free model | `agy` `gemini-3.8-flash-medium`, no-shell order |
| Wide read-only sweep | `opencode` free model | `gemini` default model |
| Heavy routine refactor (paid, sparing) | `agy` `gemini-3.1-pro-high`, no-shell order | `opencode` free model |

Free opencode model used here: `opencode/muse-spark-1.3-contributor-free`.

Budgets that fit the timings below: 300s for an opencode multi-file step,
600s for an agy one, 45s for any probe.

## Observed timings

Same work order each time: 8 modules edited, 8 files created, 32 tests.

| Worker | Model | Result | Time |
| --- | --- | --- | --- |
| opencode | muse-spark-1.3-contributor-free | all 16 files, verify passed | 66s |
| agy | gemini-3.8-flash-high, no-shell order | 11 of 16 files, hit print timeout | 280s |
| agy | gemini-3.8-flash-high, order with verify | 0 files, shell denied | 107s |

## User pins

Blank means use the table.

- coding:
- sweep:
- refactor:

## Off roster

Add a CLI by working out its headless command, running it once under
`scripts/budget` with a one-word prompt, and adding a section above.
