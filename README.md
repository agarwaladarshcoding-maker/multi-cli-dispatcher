# multi-cli-dispatcher

An agent skill that hands large, mechanical coding steps to cheaper worker
CLIs, then verifies the result itself. The expensive model plans and
checks; a free or cheap model does the typing.

It is one `SKILL.md` plus three shell scripts, so any agent that reads
skills can use it. Checked on 2026-10-09, each host asked whether it could
see the installed skill:

| Host | Sees it after `install.sh` |
| --- | --- |
| Claude Code | yes |
| Antigravity (`agy`) | yes |
| Muse Code | yes |
| Codex CLI | yes |
| Gemini CLI | yes |
| opencode | yes |

Workers it can delegate to out of the box: [opencode](https://opencode.ai),
Antigravity (`agy`) and Gemini CLI.

On one measured task (docstrings and tests for 12 Python modules) it cut
the orchestrator's output tokens by 92% and the cost from $1.60 to $0.43,
with the same checker passing. On a task one script could do, it saved
nothing. Details are in [Does it work](#does-it-work).

## What it does

- Decides per step whether delegating is worth it. Small or judgment-heavy
  work stays inline; only work that is mechanical, large and checkable goes
  out.
- Writes a short work order file, runs one worker headless under a
  wall-clock budget, and reads only the tail of its log.
- Snapshots the workspace first, so a partial or wrong result is undone
  without touching your uncommitted work, in a git repo or outside one.
- Never trusts the worker's exit code or its claim of success. It reruns
  the verify command itself.
- Falls back to another worker once, then does the step inline.

## Install

```sh
git clone https://github.com/agarwaladarshcoding-maker/multi-cli-dispatcher
cd multi-cli-dispatcher && ./install.sh
```

The installer puts one copy in `~/.agents/skills/multi-cli-dispatcher`,
which Codex, Gemini CLI, opencode and Muse read already. It links that
copy into `~/.claude/skills` for Claude Code, and adds it to
`~/.gemini/config/skills.json` for Antigravity, which does not follow
symlinks. Rerun it to update: your edited `roster.md` is kept.
`./install.sh --uninstall` removes it.

Then see which workers answer on your machine, and edit `roster.md` to
match. It ships with the models and quirks from the author's machine.

```sh
~/.agents/skills/multi-cli-dispatcher/scripts/probe 45
```

Claude Code users can also install it as a plugin:

```
/plugin marketplace add agarwaladarshcoding-maker/multi-cli-dispatcher
/plugin install multi-cli-dispatcher@multi-cli-dispatcher
```

A plugin update replaces `roster.md`, so prefer `install.sh` once you
have edited it.

Requirements: `git`, `perl` and a POSIX shell (all present on macOS and
most Linux systems), plus at least one worker CLI that is logged in.

## Scripts

They are usable on their own, without the skill.

| Script | Use |
| --- | --- |
| `scripts/budget <seconds> <command...>` | Runs a command with stdin closed, kills its whole process group at the deadline, exits 124. A `timeout` for machines that lack one. |
| `scripts/snap save\|diff\|restore <step>` | Snapshot of the current directory in a shadow git store under `.agents/shadow`. Does not touch the real index or stash. |
| `scripts/probe [seconds]` | One-word prompt to each worker CLI; reports pass, fail or missing. |

## Does it work

Measured on 2026-10-08 with Claude Opus 5.5 in Claude Code (`claude -p`)
as the orchestrator, one run per row. Cost and tokens are from the
session's own result record.

### Where it pays: varied work

The task: add docstrings to 86 functions in 12 unrelated Python modules
(1,136 lines) and write a test file for each, with a checker that also
rejects any change to the code itself.

| Run | Delegated | Output tokens | Cost | Time | Tests written | Check |
| --- | --- | --- | --- | --- | --- | --- |
| Skills disabled | no | 43,108 | $1.60 | 391s | 169 | passed |
| Skill installed, not named | no | 36,247 | $1.48 | 321s | 203 | passed |
| Skill named in the prompt | yes, free opencode model | 3,270 | $0.43 | 399s | 311 | passed |

Against the first row, the delegated run used 92% fewer output tokens and
cost 73% less, in about the same wall time. It is one run of one task, so
treat it as an example, not a benchmark.

### Where it does not: uniform work

The task: the same edit applied to 10 near-identical modules, plus 9 new
test files.

| Run | Delegated | Output tokens | Cost | Time |
| --- | --- | --- | --- | --- |
| Skills disabled | no | 2,667 | $0.33 | 27s |
| Skill installed, not named | no | 2,601 | $0.33 | 29s |

Both times Opus wrote a generator script. Nothing beats that, and the
skill now tells the orchestrator to script such changes itself. A
one-function rename with the skill installed also stayed inline.

### Are the worker's tests any good

The same 150 small bugs (operator swaps, off-by-one constants) were
injected into the code, and a bug counts as caught when the module's test
file fails.

| Tests written by | Caught | Lines of tests |
| --- | --- | --- |
| Opus, skills disabled | 140 (93%) | 1,259 |
| Opus, skill installed but unused | 144 (96%) | 1,461 |
| Free opencode worker | 136 (90%) | 1,858 |

### Does the orchestrator pick it up

The second row of the first table is the catch: with the original
description the skill sat unused unless named. The description was
rewritten after those runs. Same task, skill not named in the prompt:

| Setup | Loaded the skill |
| --- | --- |
| Old description | 0 of 1 |
| Current description | 3 of 4 |
| Current description plus a one-line `CLAUDE.md` rule | 2 of 2 |

To make it dependable, name the skill in the prompt or add that line to
the project's `CLAUDE.md`: "Before starting any task that will write or
edit 5 or more files, load the multi-cli-dispatcher skill."

### Which workers held up

On real work orders of 12 to 16 files:

| Worker | Result |
| --- | --- |
| opencode, free model | 16 files in 66s, verify passed; wrote outside its directory when asked: refused |
| agy, `accept-edits` | shell call denied, 0 files, exit 0 |
| agy, no-shell work order | 11 of 16 files, timed out, exit 0 |
| gemini, free tier | 4 of 12 files, then hit its token quota and retried until killed |
| opencode `exo-free` | "Endpoint is unavailable" after 85s, 0 files |

Two of those report success while leaving the work undone or half done,
which is why the skill ignores exit codes and reruns the verify command
itself. After the partial gemini run, `snap restore` undid all 8 changed
files.

All 31 test rows, the script bugs they turned up, and what has not been
tested are in [docs/stress-test.md](docs/stress-test.md).

## Limits

- Tested on macOS only, with three worker CLIs at the versions listed in
  `roster.md`. The cost numbers above were measured with Claude Code as
  the host; other hosts load the skill but have not been benchmarked.
- Headless flags of these tools change often.
- Free model lanes come and go. Expect to edit the model table.
- Snapshots copy the whole workspace minus ignored files; very large
  repos will feel it.
- Snapshots do not cover gitignored files (a worker's change to `.env`
  is reported by `snap diff` but cannot be restored) or nested git repos
  and submodules (named by `snap save`).
- Worker CLIs send your code to their providers. Check that is acceptable
  for the repo you point them at.

## Similar projects

Delegating from one coding agent to another is a crowded idea. These solve
the same problem as MCP servers or plugins:

- [zen-mcp-server](https://github.com/BeehiveInnovations/zen-mcp-server),
  whose `clink` tool spawns other CLIs as subagents
- [claude-delegate](https://github.com/TuYv/claude-delegate) and
  [delegate-skills](https://github.com/amElnagdy/delegate-skills)
- `all-agents-mcp`, `cli-agent-mcp`, `cli-orchestrator-mcp`,
  `mcp-subagents`

This one differs in being a single skill file plus three small scripts,
with no server to run, a gate that argues against delegating by default,
and a snapshot-and-verify loop built around workers that fail silently.

## Feedback

This is v1 and I want to know where it breaks. If you try it, open an
[issue](https://github.com/agarwaladarshcoding-maker/multi-cli-dispatcher/issues/new/choose)
with what you ran, which worker, and whether it saved anything. A line from
your `.agents/task-log.md` is the most useful thing you can paste.

## License

MIT
