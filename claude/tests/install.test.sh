#!/usr/bin/env bash
# Single-quoted "$1" and jq $vars are passed to child shells / jq on purpose.
# shellcheck disable=SC2016
# install.test.sh — exercises claude/install.sh, scripts/claude-settings and the SessionStart hook
# against a fake HOME and a throwaway git copy of this package (so tests can add and remove repo
# items). Never touches the real ~/.claude, vault, state or dotfiles checkout.
# Run: bash claude/tests/install.test.sh
set -uo pipefail

PKG_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/claude-install-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT

# A disposable dotfiles repo holding a copy of the package
mkdir -p "$T/dotfiles"
cp -R "$PKG_SRC" "$T/dotfiles/claude"
git -C "$T/dotfiles" init -q
git -C "$T/dotfiles" config user.email test@example.com
git -C "$T/dotfiles" config user.name test
git -C "$T/dotfiles" add -A && git -C "$T/dotfiles" commit -q -m fixture
PKG="$(cd "$T/dotfiles/claude" && pwd)"   # normalised: mktemp can return a path with "//"

export HOME="$T/home"
export CLAUDE_CONFIG_DIR="$HOME/.claude"
export MEMORY_VAULT_PATH="$T/vault"
export XDG_STATE_HOME="$T/state"
export CLAUDE_BACKUP_DIR="$T/backup"
unset CLAUDE_SETTINGS_OVERLAY CLAUDE_SETTINGS_BASE DOTFILES_DENYLIST CLAUDE_SETTINGS_SYNC CLAUDE_SETTINGS_AUTOCOMMIT
mkdir -p "$HOME"

C="$CLAUDE_CONFIG_DIR"
S="$C/settings.json"
OVL="$MEMORY_VAULT_PATH/personal/claude/settings.overlay.json"
LASTGEN="$XDG_STATE_HOME/dotfiles/claude-settings.lastgen.json"
INSTALL="$PKG/install.sh"
SETTINGS="$PKG/scripts/claude-settings"
FOLDERS="agents commands rules hooks skills"

pass=0; failed=0
ok()   { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad()  { failed=$((failed + 1)); printf '  FAIL %s\n' "$1"; }
check() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
quiet() { "$@" >/dev/null 2>&1; }
section() { printf '\n%s\n' "$1"; }
canon() { jq -S 'walk(if type == "array" then sort else . end)' "$1"; }
# set_json <file> <jq args...>: edit in place (keeps the inode, mode and regular-file type)
set_json() { local f="$1" tmp; shift; tmp="$(mktemp)"; jq "$@" "$f" > "$tmp" && cat "$tmp" > "$f" && rm -f "$tmp"; }
real_dir() { [ -d "$1" ] && [ ! -L "$1" ]; }
regular_600() { [ -f "$1" ] && [ ! -L "$1" ] && [ "$(stat -f '%Lp' "$1")" = "600" ]; }

skills=("$PKG"/skills/*/)
agents=("$PKG"/agents/*.md)
rules=("$PKG"/rules/*.md)
first_skill="$(basename "${skills[0]}")"
first_agent="$(basename "${agents[0]}")"
first_rule="$(basename "${rules[0]}")"
base_allow0="$(jq -r '.permissions.allow[0]' "$PKG/settings.base.json")"

all_links_ok() {
    local f
    for f in $FOLDERS; do
        [ "$(readlink "$C/$f")" = "$PKG/$f" ] || { echo "    bad folder link: $f"; return 1; }
    done
    [ "$(readlink "$C/statusline-command.sh")" = "$PKG/statusline-command.sh" ]
}

# per_item_layout <folder>: recreate the earlier layout — a real folder of per-item links
per_item_layout() {
    local f="$1" e
    rm -f "$C/$f"
    mkdir -p "$C/$f"
    for e in "$PKG/$f"/*; do ln -s "$e" "$C/$f/$(basename "$e")"; done
}

section "fresh install, no vault"
out="$("$INSTALL" 2>"$T/err")"; rc=$?
check "exit 0" [ "$rc" -eq 0 ]
check "all five folders and the statusline linked to the package" all_links_ok
check "the claude config dir itself is a real directory" real_dir "$C"
check "settings.json is a regular file, mode 600" regular_600 "$S"
check "settings.json equals the base" [ "$(canon "$S")" = "$(canon "$PKG/settings.base.json")" ]
check "generation recorded" [ -f "$LASTGEN" ]
check "warns that the overlay is missing" grep -q 'no private overlay' "$T/err"

section "idempotence"
mtime="$(stat -f '%m' "$S")"
sleep 1
out="$("$INSTALL" 2>/dev/null)"
check "second run changes nothing" grep -q '^changed: 0$' <<<"$out"
check "settings.json not rewritten" [ "$(stat -f '%m' "$S")" = "$mtime" ]
check "--status healthy" quiet "$INSTALL" --status

section "repo additions, edits and removals take effect with no re-run"
mkdir -p "$PKG/skills/zz-new-skill"
printf -- '---\nname: zz-new-skill\ndescription: test\n---\nbody\n' > "$PKG/skills/zz-new-skill/SKILL.md"
printf -- '---\ndescription: test\n---\nbody\n' > "$PKG/agents/zz-new-agent.md"
printf '\n# edited in the repo\n' >> "$PKG/rules/$first_rule"
check "new skill visible in ~/.claude" [ -f "$C/skills/zz-new-skill/SKILL.md" ]
check "new agent visible in ~/.claude" [ -f "$C/agents/zz-new-agent.md" ]
check "edit visible in ~/.claude" grep -q 'edited in the repo' "$C/rules/$first_rule"
out="$("$INSTALL" --status 2>&1)"; rc=$?
check "--status still healthy" [ "$rc" -eq 0 ]
check "--status lists the uncommitted skill" grep -q 'uncommitted: .*zz-new-skill' <<<"$out"
check "--status lists the uncommitted agent" grep -q 'uncommitted: .*zz-new-agent.md' <<<"$out"
rm -rf "$PKG/skills/zz-new-skill" "$PKG/agents/zz-new-agent.md"
git -C "$PKG" checkout -q -- "rules/$first_rule"
check "removed skill gone from ~/.claude" [ ! -e "$C/skills/zz-new-skill" ]
check "--status quiet again once removed" bash -c '! "$1" --status 2>&1 | grep -q uncommitted' _ "$INSTALL"

section "migrating the earlier per-item layout"
for f in $FOLDERS; do per_item_layout "$f"; done
rm "$C/skills/$first_skill" && cp -R "$PKG/skills/$first_skill" "$C/skills/$first_skill"   # a materialized copy
ln -s "$PKG/skills/zz-gone" "$C/skills/zz-gone"                                            # dangling, into the package
: > "$C/skills/.DS_Store"
out="$("$INSTALL" 2>&1)"; rc=$?
check "exit 0" [ "$rc" -eq 0 ]
check "every folder is now a link" all_links_ok
check "old skills folder kept in the backup" [ -n "$(find "$CLAUDE_BACKUP_DIR" -type d -path "*/skills/$first_skill" 2>/dev/null)" ]
check "identical copy raises no 'differs' warning" bash -c '! grep -q differs <<<"$1"' _ "$out"
check "no backup inside ~/.claude" [ -z "$(find "$C" -name "$first_skill" -not -path "$C/skills/*" 2>/dev/null)" ]

section "an unmanaged item blocks only its own folder"
per_item_layout skills
mkdir -p "$C/skills/third-party-x" && echo keep > "$C/skills/third-party-x/SKILL.md"
per_item_layout rules
out="$("$INSTALL" 2>&1)"; rc=$?
check "install exits non-zero" [ "$rc" -ne 0 ]
check "names the unmanaged item" grep -q 'third-party-x' <<<"$out"
check "skills folder left as it was" real_dir "$C/skills"
check "unmanaged skill intact" [ -f "$C/skills/third-party-x/SKILL.md" ]
check "other folders still migrate in the same run" [ "$(readlink "$C/rules")" = "$PKG/rules" ]
check "--status reports the unlinked folder" bash -c '! "$1" --status >/dev/null 2>&1' _ "$INSTALL"
mv "$C/skills/third-party-x" "$T/third-party-x"
"$INSTALL" >/dev/null 2>&1; rc=$?
check "after moving it out: exit 0 and linked" [ "$rc$(readlink "$C/skills")" = "0$PKG/skills" ]

section "a local copy that differs from the repo is backed up"
per_item_layout agents
rm "$C/agents/$first_agent" && echo "local edit" > "$C/agents/$first_agent"
out="$("$INSTALL" 2>&1)"
check "linked" [ "$(readlink "$C/agents")" = "$PKG/agents" ]
check "warns that it differed" grep -q "agents/$first_agent differs" <<<"$out"
check "local version kept in the backup" grep -rqs 'local edit' "$CLAUDE_BACKUP_DIR"

section "a folder linked somewhere else is relinked"
mkdir -p "$T/elsewhere-rules" && echo x > "$T/elsewhere-rules/keep.md"
rm "$C/rules" && ln -s "$T/elsewhere-rules" "$C/rules"
"$INSTALL" >/dev/null 2>&1
check "relinked to the package" [ "$(readlink "$C/rules")" = "$PKG/rules" ]
check "the old target is untouched" [ -f "$T/elsewhere-rules/keep.md" ]
check "the old link is in the backup" [ -n "$(find "$CLAUDE_BACKUP_DIR" -type l -name rules 2>/dev/null)" ]

section "dry run changes nothing"
rm "$C/agents"
out="$("$INSTALL" --dry-run 2>/dev/null)"
check "reports the pending link" grep -q "would: link $C/agents" <<<"$out"
check "link still missing" bash -c '[ ! -e "$1" ] && [ ! -L "$1" ]' _ "$C/agents"
"$INSTALL" >/dev/null 2>&1

section "overlay merges with array union"
mkdir -p "$(dirname "$OVL")"
printf '%s\n' '{"autoMode":{"environment":["private fact"]},"permissions":{"allow":["Bash(extra:*)"]}}' > "$OVL"
"$INSTALL" >/dev/null 2>&1; rc=$?
check "install exit 0" [ "$rc" -eq 0 ]
check "overlay key present" [ "$(jq -r '.autoMode.environment[0]' "$S")" = "private fact" ]
check "overlay array item added" quiet jq -e '.permissions.allow | index("Bash(extra:*)")' "$S"
check "base array items kept" quiet jq -e --arg a "$base_allow0" '.permissions.allow | index($a)' "$S"
check "no overlay warning once present" bash -c '! "$1" status 2>&1 | grep -q "no private overlay"' _ "$SETTINGS"

section "drift Claude made is absorbed into the overlay"
set_json "$S" '.theme = "light-test"'
"$SETTINGS" sync >/dev/null 2>&1; rc=$?
check "sync exit 0" [ "$rc" -eq 0 ]
check "overlay records the change" [ "$(jq -r '.theme' "$OVL")" = "light-test" ]
check "overlay keeps its private keys" [ "$(jq -r '.autoMode.environment[0]' "$OVL")" = "private fact" ]
check "settings.json still a regular 600 file" regular_600 "$S"
check "status clean" quiet "$SETTINGS" status

section "lossy drift is refused"
cp "$OVL" "$T/ovl.before"
set_json "$S" --arg a "$base_allow0" '.permissions.allow -= [$a]'
cp "$S" "$T/live.before"
check "sync refuses" bash -c '! "$1" sync >/dev/null 2>&1' _ "$SETTINGS"
check "live left untouched" cmp -s "$S" "$T/live.before"
check "overlay left untouched" cmp -s "$OVL" "$T/ovl.before"
"$SETTINGS" apply --force >/dev/null 2>&1
check "apply --force restores the base entry" quiet jq -e --arg a "$base_allow0" '.permissions.allow | index($a)' "$S"
check "apply --force backed up the discarded live file" [ -n "$(find "$CLAUDE_BACKUP_DIR" -name settings.json)" ]

section "drift plus a changed overlay is a conflict"
set_json "$S" '.theme = "conflict-live"'
set_json "$OVL" '.tui = "conflict-overlay"'
out="$("$SETTINGS" sync 2>&1)"; rc=$?
check "sync refuses" [ "$rc" -ne 0 ]
check "names the conflict" grep -qi conflict <<<"$out"
check "status reports CONFLICT" bash -c '"$1" status 2>/dev/null | grep -q CONFLICT' _ "$SETTINGS"
"$SETTINGS" apply --force >/dev/null 2>&1

section "live file with no generation record"
rm -f "$LASTGEN"
set_json "$S" '.theme = "pre-existing"'
check "sync refuses to guess" bash -c '! "$1" sync >/dev/null 2>&1' _ "$SETTINGS"
check "live untouched" [ "$(jq -r .theme "$S")" = "pre-existing" ]
"$SETTINGS" apply --force >/dev/null 2>&1
generated_and_recorded() {
    [ -f "$LASTGEN" ] &&
        [ "$(canon "$S")" = "$("$SETTINGS" merged 2>/dev/null | jq -S 'walk(if type == "array" then sort else . end)')" ]
}
check "apply --force generates and records" generated_and_recorded

section "materialize and relink"
"$INSTALL" --materialize >/dev/null 2>&1
check "skills is now a real folder" real_dir "$C/skills"
check "copy matches the package" diff -rq "$C/skills" "$PKG/skills"
check "agents is now a real folder" real_dir "$C/agents"
check "hooks stays linked (the shell always follows links)" [ "$(readlink "$C/hooks")" = "$PKG/hooks" ]
"$INSTALL" >/dev/null 2>&1; rc=$?
check "plain install relinks the identical copies" [ "$rc" -eq 0 ]
check "every folder linked again" all_links_ok

section "SessionStart hook keeps settings in sync without anyone remembering"
HOOK="$C/hooks/claude-settings-sync.sh"
SYNC_LOG="$XDG_STATE_HOME/dotfiles/claude-settings-sync.log"
SYNC_LOCK="$XDG_STATE_HOME/dotfiles/claude-settings-sync.lock"
SYNC_STAMP="$XDG_STATE_HOME/dotfiles/claude-settings-sync.stamp"
V="$MEMORY_VAULT_PATH"
git -C "$V" init -q && git -C "$V" config user.email test@example.com && git -C "$V" config user.name test
git -C "$V" add -A && git -C "$V" commit -q -m "fixture"
log_lines() { if [ -f "$SYNC_LOG" ]; then wc -l < "$SYNC_LOG" | tr -d ' '; else echo 0; fi; }
vault_commits() { git -C "$V" rev-list --count HEAD; }
check "hook reached through the hooks folder link" bash -c '[ -f "$1" ] && [ ! -L "$1" ] && [ -L "$(dirname "$1")" ]' _ "$HOOK"
check "base registers it on SessionStart" quiet jq -e '.hooks.SessionStart[].hooks[] | select(.command == "$HOME/.claude/hooks/claude-settings-sync.sh")' "$PKG/settings.base.json"

rm -f "$SYNC_STAMP"
out="$("$HOOK")"; rc=$?
check "clean state: exit 0" [ "$rc" -eq 0 ]
check "clean state: silent" [ -z "$out" ]
check "resolves the package through the folder link (sync ran, stamp written)" [ -f "$SYNC_STAMP" ]
before="$(log_lines)"
"$HOOK" >/dev/null
check "unchanged files take the fast path (no sync run)" [ "$(log_lines)" = "$before" ]

ln -s "$PKG/hooks/claude-settings-sync.sh" "$T/per-file-hook.sh"
rm -f "$SYNC_STAMP"
"$T/per-file-hook.sh" >/dev/null
check "also resolves through a per-file link" [ -f "$SYNC_STAMP" ]
mkdir -p "$T/lonely/hooks" && cp "$PKG/hooks/claude-settings-sync.sh" "$T/lonely/hooks/"
out="$("$T/lonely/hooks/claude-settings-sync.sh")"; rc=$?
warns_not_found() { [ "$rc" -eq 0 ] && jq -e '.systemMessage | test("could not find")' <<<"$out" >/dev/null 2>&1; }
check "package not found: exit 0 but warns instead of dying silently" warns_not_found

commits="$(vault_commits)"
set_json "$S" '.theme = "hook-drift"'
out="$("$HOOK")"; rc=$?
check "drift: exit 0 and silent" [ "$rc$out" = "0" ]
check "drift: absorbed into the overlay" [ "$(jq -r .theme "$OVL")" = "hook-drift" ]
check "drift: overlay committed in the vault" [ "$(vault_commits)" -eq $((commits + 1)) ]
check "drift: commit touches only the overlay" [ "$(git -C "$V" show --name-only --format= HEAD)" = "personal/claude/settings.overlay.json" ]
check "drift: vault left clean" [ -z "$(git -C "$V" status --porcelain -- personal/claude/settings.overlay.json)" ]
check "drift: settings.json still a regular 600 file" regular_600 "$S"

set_json "$S" --arg a "$base_allow0" '.permissions.allow -= [$a]'
cp "$S" "$T/live.hook-lossy"
out="$("$HOOK")"; rc=$?
check "lossy change: exit 0 (never blocks a session)" [ "$rc" -eq 0 ]
check "lossy change: warns the user" quiet jq -e '.systemMessage | test("needs attention")' <<<"$out"
check "lossy change: warns the session" quiet jq -e '.hookSpecificOutput.hookEventName == "SessionStart" and (.hookSpecificOutput.additionalContext | length > 0)' <<<"$out"
check "lossy change: live left untouched" cmp -s "$S" "$T/live.hook-lossy"
out="$("$HOOK")"
check "lossy change: keeps warning until resolved" quiet jq -e '.systemMessage' <<<"$out"
"$SETTINGS" apply --force >/dev/null 2>&1

set_json "$S" '.theme = "while-locked"'
mkdir -p "$SYNC_LOCK"
out="$("$HOOK")"; rc=$?
check "held lock: exit 0 and silent" [ "$rc$out" = "0" ]
check "held lock: another session's sync is not duplicated" [ "$(jq -r .theme "$OVL")" != "while-locked" ]
touch -t 202001010000 "$SYNC_LOCK"
"$HOOK" >/dev/null
check "stale lock: recovered and synced" [ "$(jq -r .theme "$OVL")" = "while-locked" ]
check "lock released afterwards" [ ! -d "$SYNC_LOCK" ]

set_json "$S" '.theme = "sync-disabled"'
CLAUDE_SETTINGS_SYNC=0 "$HOOK" >/dev/null
check "CLAUDE_SETTINGS_SYNC=0 does nothing" [ "$(jq -r .theme "$OVL")" != "sync-disabled" ]
commits="$(vault_commits)"
CLAUDE_SETTINGS_AUTOCOMMIT=0 "$HOOK" >/dev/null
check "CLAUDE_SETTINGS_AUTOCOMMIT=0 still absorbs" [ "$(jq -r .theme "$OVL")" = "sync-disabled" ]
check "CLAUDE_SETTINGS_AUTOCOMMIT=0 does not commit" [ "$(vault_commits)" -eq "$commits" ]

printf '\n%d passed, %d failed\n' "$pass" "$failed"
[ "$failed" -eq 0 ]
