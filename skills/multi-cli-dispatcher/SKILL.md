---
name: multi-cli-dispatcher
description: Hands big routine coding steps to free or cheap worker CLIs (opencode, agy, gemini) and verifies the result itself. Use whenever a task means writing or editing many files where each file must be read but little judgment is needed, such as tests or docstrings for many modules, type hints, framework or API migrations, bulk boilerplate, or a wide read-only sweep. Rough size is 5+ files or 150+ lines of output. Not for small edits, changes one script can make, design, or debugging.
---

# Multi CLI Dispatcher

The orchestrator does the thinking and the small work itself. Worker CLIs
get only the work that is large, mechanical, and cheap to verify. The goal
is fewer orchestrator tokens for the same quality, not delegation for its
own sake.

This skill works under any agent host that reads `SKILL.md` (Claude Code,
Antigravity, Muse, Codex, Gemini CLI, opencode). "Orchestrator" means
whichever model is reading this.

`scripts/budget`, `scripts/snap`, `scripts/probe` and `roster.md` live in
this skill's directory: the folder holding this file. If the host did not
say where that is, look in `~/.agents/skills/multi-cli-dispatcher`, then
`~/.claude/skills/multi-cli-dispatcher`. Call the scripts by their absolute
path with the shell's working directory set to the workspace, never `cd`
into the skill: `snap` snapshots whatever directory it runs in.

## Delegation gate

Delegate a step when all three hold. Otherwise do it inline.

1. Routine: the outcome can be specified up front and a competent junior
   could do it from the work order. The worker may make local choices
   (which cases to test, how to word a docstring), never design ones.
2. Large: roughly 150+ lines of output, or 5+ files, or a sweep that would
   mean reading 10+ files to answer one question.
3. Checkable: a command or a short diff review proves it worked.

Script first. If the same edit applies to every file, write a codemod or
generator script inline: that costs a few hundred tokens and beats any
worker. Delegation pays when each file needs reading and a slightly
different edit, so no script can do it: tests, docstrings, type hints,
migrations across unlike files. Measured on 12 unlike modules: inline cost
43k output tokens, delegated cost 3k (`docs/stress-test.md` in the repo).

Quick test: if the work order would be about as long as the change, do the
change inline.

Always inline, whatever the size: architecture and API design, debugging
with an unknown cause, novel algorithms, security-sensitive code, secrets
handling, UI taste, research synthesis, and final approval.

Batch before delegating. Several small related mechanical edits go into one
work order, not one step each. Per-step overhead is what eats the saving.

## Orchestrator rules

- Read whatever code is needed to plan and to verify. Targeted reads are
  cheap; a wrong work order is not.
- Write code inline whenever the gate says inline.
- Never paste whole files into a reply. One status line per delegated step.
- While a worker runs in the background, keep doing inline work on files it
  does not touch.

## Probe

Probe lazily, on the first step that passes the gate, not when the skill
loads. Run `scripts/probe 45`. It prints one line per CLI: pass, fail, or
missing. Keep the passing ones and lock that roster for the session.
Recheck only when every rostered CLI fails. If nothing passes, work inline
and say so once.

Leave the CLI you are running inside off the roster unless the roster
names a cheaper model for it: delegating to yourself on the same model
saves nothing.

A manual name like "use agy" is an override: try it first, then fall back
normally. It does not override the gate's always-inline list.

## Roster

`roster.md` holds the per-machine part: which CLIs are on the roster, the
exact headless command for each, the model to use per step kind, and the
quirks seen on this machine. Read it once, after the probe. When a listed
model id is gone, use the fastest passing sibling and update the file.

## Work order

Write it to `.agents/orders/<step>.md` in the workspace and point the
prompt at that file. Keep it short and self-contained:

- Objective, in one or two sentences.
- Workspace path. Everything the worker needs must be inside it, including
  copies of reference files: workers refuse or fail outside the workspace.
- Files to touch, listed explicitly, or "read-only". Name the files that
  must not change, the verify script and existing tests above all.
- One worked example of the pattern when the edit is repetitive.
- Exact verify command, or "no shell: skip verify" for a worker that cannot
  run commands (see `roster.md`).
- "Do the work yourself; do not call other agent CLIs or subagents."
  Workers can load skills too, this one included.
- Report contract: at most 10 lines, giving files changed, verify result,
  and anything left undone. No file contents, no narration.

## Running a step

1. Snapshot: `scripts/snap save <step>`. This works inside and outside a
   git repo and leaves the user's uncommitted work and index untouched.
   It cannot cover gitignored files or nested git repos. Save names any
   nested repos: keep the worker out of them.
2. Run the worker through `scripts/budget <seconds> <command...>` with
   output sent to `.agents/logs/<step>.log`. Run long steps in the
   background. The budget wrapper closes stdin, kills the whole process
   group on expiry, and exits 124. Do not rely on `timeout`; stock macOS
   does not have it. The budget counts awake time: if the machine sleeps
   mid-step the worker usually dies with a network error, so rerun it.
3. Read only the tail of the log (about 20 lines), never the whole log.
4. Verify, yourself: `scripts/snap diff <step>` for the list of files that
   changed, then the verify command, then targeted reads of the hunks most
   likely to be wrong. Check that no protected file is in the diff. A
   "changed but gitignored" line means the worker touched a file restore
   cannot undo (often `.env`): inspect it by hand.
5. Pass, or `scripts/snap restore <step>` and fall back.

The exit code never decides step 5. Every worker tested exits 0 in at least
one failure mode: permission denied, print timeout with a half-written
diff, or a verify command that failed. Only the verify result decides.

Parallel is allowed only for steps with disjoint file sets, one writer per
directory, each verified separately. Snapshots are whole-workspace, so a
restore undoes every parallel step since that snapshot: snapshot once
before the batch, and on a failure restore and rerun the batch in order.
Run `snap` commands one at a time; they share one index. Start parallel
workers a few seconds apart (see `roster.md`).
Dependent steps run in order, each taking its inputs from the previous
step's verified output.

## Fallback

At most two worker attempts per step, then inline.

- Timeout, empty output, zero files changed, failed verify, or contract
  violation: restore the snapshot, fix the work order if it was at fault,
  then try the next rung once.
- Missing binary or auth failure: skip that rung immediately.
- A model-level failure is not a CLI failure: try the next model on the
  same CLI before leaving it.
- Second failure: restore and do the step inline. Do not spawn the
  host's own subagents unless the user asked for them.
- A worker that reports the verify cannot pass and explains why is a
  result, not a failure. Read the reason before retrying: the work order
  may be contradictory.

## Task log

After every delegated attempt, append one line to the workspace-relative
`.agents/task-log.md`. Never rewrite or delete past lines.

`date | step | role | cli | model | seconds | result`

Result is pass, fail with reason, or fallback with the next rung named.
Inline steps are not logged.

## Guardrails

- Non-interactive entrypoints only, never a TUI.
- Never pass a skip-all-permissions flag the host or the user has refused.
  Use the scoped mode in `roster.md` instead.
- Every attempt runs under `scripts/budget`.
- Workspace is pinned. Do not assume the worker enforces that: check the
  diff for anything outside the listed files.
- A worker PASS is a claim, never proof. Ship only what the orchestrator
  observed passing.
