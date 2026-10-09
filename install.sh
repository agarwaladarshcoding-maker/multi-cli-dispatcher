#!/bin/sh
# install.sh [--uninstall]
# Installs the skill once, into ~/.agents/skills, and makes every agent on
# this machine see that one copy:
#   Gemini CLI, Codex, opencode, Muse  read ~/.agents/skills already
#   Claude Code                        gets a symlink in ~/.claude/skills
#   Antigravity (agy)                  gets an entry in ~/.gemini/config/skills.json
#                                      (it does not follow symlinks)
# Reinstalling keeps your edited roster.md.
set -eu
name=multi-cli-dispatcher
src=$(cd "$(dirname "$0")" && pwd)/skills/$name
home_skills=$HOME/.agents/skills
dest=$home_skills/$name
claude_link=$HOME/.claude/skills/$name
agy_cfg=$HOME/.gemini/config/skills.json

if [ "${1:-}" = --uninstall ]; then
  [ -L "$claude_link" ] && rm "$claude_link" && echo "removed $claude_link"
  if [ -f "$agy_cfg" ] && grep -q "\"$name\"" "$agy_cfg"; then
    echo "remove the $name entry from $agy_cfg by hand"
  fi
  [ -d "$dest" ] && rm -rf "$dest" && echo "removed $dest"
  exit 0
fi

[ -f "$src/SKILL.md" ] || { echo "install.sh: run it from a clone of the repo" >&2; exit 1; }

# 1. the one real copy, keeping a roster.md the user already edited
mkdir -p "$home_skills"
keep=
if [ -f "$dest/roster.md" ]; then keep=$(mktemp); cp "$dest/roster.md" "$keep"; fi
rm -rf "$dest"
cp -R "$src" "$dest"
chmod +x "$dest/scripts/"*
if [ -n "$keep" ]; then mv "$keep" "$dest/roster.md"; echo "kept your roster.md"; fi
echo "installed $dest  (Gemini CLI, Codex, opencode, Muse read this folder)"

# 2. Claude Code
if [ -d "$HOME/.claude" ] || command -v claude >/dev/null 2>&1; then
  mkdir -p "$HOME/.claude/skills"
  if [ -e "$claude_link" ] && [ ! -L "$claude_link" ]; then
    # outside any skills folder, or the agent would load it as a second copy
    bak=$HOME/.$name-backup-$(date +%s)
    mv "$claude_link" "$bak"
    echo "moved your old ~/.claude/skills copy to $bak"
  fi
  ln -sfn "$dest" "$claude_link"
  echo "linked  $claude_link  (Claude Code)"
fi

# 3. Antigravity
if [ -d "$HOME/.gemini/config" ] || command -v agy >/dev/null 2>&1; then
  entry="{ \"path\": \"$home_skills\", \"include_only\": [\"$name\"] }"
  if [ ! -f "$agy_cfg" ]; then
    mkdir -p "$(dirname "$agy_cfg")"
    printf '{\n  "entries": [\n    %s\n  ]\n}\n' "$entry" > "$agy_cfg"
    echo "wrote   $agy_cfg  (Antigravity)"
  elif grep -q "\"$name\"" "$agy_cfg"; then
    echo "found   $agy_cfg already lists $name  (Antigravity)"
  else
    echo "Antigravity: add this to \"entries\" in $agy_cfg:"
    echo "    $entry"
  fi
fi

echo
echo "next: run $dest/scripts/probe 45 to see which worker CLIs answer,"
echo "      then edit $dest/roster.md to match."
