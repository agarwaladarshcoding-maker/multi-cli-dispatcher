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

Measured on 2026-10-08 with Claude Opus 5.5 in Claude Code as the orchestrator, one run
per row. The task: add docstrings to 86 functions in 12 unrelated Python
modules and write a test file for each, with a checker that also rejects
any change to the code itself.

| Run | Output tokens | Cost | Time | Check |
| --- | --- | --- | --- | --- |
| No skill, Opus does it all | 43,108 | $1.60 | 391s | passed |
| Skill, work done by a free opencode model | 3,270 | $0.43 | 399s | passed |

That is 92% fewer output tokens and 73% lower cost for the same wall
time. It is one run of one task, so treat it as an example, not a
benchmark.

Claude loaded the skill unprompted in 3 of 4 runs on this task. To make
it dependable, name it in the prompt or add one line to the project's
`CLAUDE.md`: "Before starting any task that will write or edit 5 or more
files, load the multi-cli-dispatcher skill." (2 of 2 with that line.)

The worker's tests were nearly as strong as Opus's: with the same 150
small bugs injected into the code, the worker's suite caught 136 and the
two Opus suites caught 140 and 144.

When it does not help: on a second task where the same edit applied to
10 near-identical files, Opus wrote a generator script in 2,600 output
tokens and 30 seconds, with or without the skill. Nothing beats that, and
the skill now tells the orchestrator to script such changes itself.

Full notes, including the ways workers fail silently, are in
[docs/stress-test.md](docs/stress-test.md).

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
