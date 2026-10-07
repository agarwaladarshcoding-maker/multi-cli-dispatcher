# multi-cli-dispatcher

A skill for Claude Code (and other agents that read `SKILL.md`) that hands
large, mechanical coding steps to cheaper worker CLIs, then verifies the
result itself. The expensive model plans and checks; a free or cheap model
does the typing.

Workers supported out of the box: [opencode](https://opencode.ai),
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
cp -R multi-cli-dispatcher/skills/multi-cli-dispatcher ~/.claude/skills/
~/.claude/skills/multi-cli-dispatcher/scripts/probe 45
```

The probe prints which worker CLIs answer on your machine. Then edit
`roster.md` in the installed skill: it ships with the models and quirks
from the author's machine, and yours will differ.

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

One measured run, described in full in
[docs/stress-test.md](docs/stress-test.md): a 16-file refactor with 32
tests finished on a free opencode model in 66 seconds and passed an
independent check. The same job on agy in headless mode wrote nothing and
still exited 0, which is why the skill ignores exit codes.

What is not measured yet: the end-to-end token saving, and how reliably
the orchestrator model follows the delegation gate.

## Limits

- Tested on macOS only, with three CLIs at the versions listed in
  `roster.md`. Headless flags of these tools change often.
- Free model lanes come and go. Expect to edit the model table.
- Snapshots copy the whole workspace minus ignored files; very large
  repos will feel it.
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

## License

MIT
