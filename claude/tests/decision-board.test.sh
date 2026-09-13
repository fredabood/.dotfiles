#!/usr/bin/env bash
# decision-board.test.sh — board.py: schema, card states, revision, render/index, harvest bookkeeping.
# Runs against throwaway copies of a synthetic fixture. Run: bash claude/tests/decision-board.test.sh
# Bash 3.2 compatible (macOS /bin/bash): no heredocs inside $( ), no associative arrays.
set -uo pipefail

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$PKG/skills/decision-board"
BOARD="$SKILL/scripts/board.py"
FIXTURE="$SKILL/tests/fixture/2026-01-15-team-offsite"
T="$(mktemp -d "${TMPDIR:-/tmp}/decision-board-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT

pass=0; failed=0; skipped=0
check() { local name="$1"; shift; if "$@"; then pass=$((pass + 1)); printf '  ok   %s\n' "$name"; else failed=$((failed + 1)); printf '  FAIL %s\n' "$name"; fi; }
skip() { skipped=$((skipped + 1)); printf '  SKIP %s\n' "$1"; }

board() { python3 "$BOARD" "$@"; }

# fresh <name>: copy the fixture into its own boards root; prints the board dir.
fresh() {
    local root="$T/$1"
    rm -rf "$root"; mkdir -p "$root"
    cp -R "$FIXTURE" "$root/"
    printf '%s/2026-01-15-team-offsite' "$root"
}

# mutate <json-file> <python statements using d>
mutate() {
    python3 -c 'import json, sys
f = sys.argv[1]
d = json.load(open(f))
exec(sys.argv[2])
open(f, "w").write(json.dumps(d, indent=2))' "$1" "$2"
}

# state_of <board-dir> <card-id>
state_of() {
    board harvest-plan "$1" | python3 -c 'import json, sys
plan = json.load(sys.stdin)
print(next(c["state"] for c in plan["cards"] if c["id"] == sys.argv[1]))' "$2"
}

# expect_invalid <name> <message-fragment> <file: agenda|answers> <python mutation>
expect_invalid() {
    local name="$1" frag="$2" which="$3" expr="$4" dir out rc
    dir="$(fresh "invalid-$pass-$failed")"
    mutate "$dir/$which.json" "$expr"
    out="$(board validate "$dir" 2>&1)"; rc=$?
    check "$name" bash -c '[ "$1" -eq 1 ] && grep -qF -- "$2" <<<"$3"' _ "$rc" "$frag" "$out"
}

AGENDA_A1='d["sections"][0]["cards"][0]'

echo "schema"
dir="$(fresh valid)"
out="$(board validate "$dir" 2>&1)"; rc=$?
check "fixture validates" test "$rc" -eq 0
check "a removed option key is reported as a stale-answer warning" grep -q "C2.choice.*stale" <<<"$out"

expect_invalid "one option is rejected" "has 1 options (need 2-4)" agenda \
    "$AGENDA_A1[\"options\"] = $AGENDA_A1[\"options\"][:1]"
expect_invalid "five options are rejected" "has 5 options (need 2-4)" agenda \
    "o = $AGENDA_A1[\"options\"]; $AGENDA_A1[\"options\"] = o + [dict(o[0], key=\"x1\"), dict(o[0], key=\"x2\")]"
expect_invalid "duplicate card id is rejected" "duplicate card id 'A1'" agenda \
    'd["sections"][1]["cards"][2]["id"] = "A1"'
expect_invalid "duplicate option key is rejected" "duplicate option key 'office'" agenda \
    "$AGENDA_A1[\"options\"][1][\"key\"] = \"office\""
expect_invalid "bad card id is rejected" "bad card id 'a1'" agenda \
    "$AGENDA_A1[\"id\"] = \"a1\""
expect_invalid "two recommended options are rejected" "2 options marked recommended" agenda \
    "$AGENDA_A1[\"options\"][0][\"recommended\"] = True"
expect_invalid "an over-long question is rejected" "q: is 201 characters (limit 200)" agenda \
    "$AGENDA_A1[\"q\"] = \"x\" * 201"
expect_invalid "an over-long note is rejected" "note: is 4001 characters (limit 4000)" answers \
    'd["cards"]["A1"]["note"] = "y" * 4001'
expect_invalid "HTML in a question is rejected" "contains HTML" agenda \
    "$AGENDA_A1[\"q\"] = \"Where? <script>alert(1)</script>\""
# The secret-shaped strings are assembled at runtime so the fixture never contains one.
expect_invalid "a 1Password reference is rejected" "1Password reference" agenda \
    "$AGENDA_A1[\"options\"][0][\"detail\"] = \"see \" + \"op\" + \"://vault/item/field\""
expect_invalid "a credential in a note is rejected" "credential assignment" answers \
    'd["cards"]["A1"]["note"] = "api" + "_key=" + "test_key_fake_for_testing_only"'
expect_invalid "an answer for a card not on the agenda is orphaned" "orphaned answer" answers \
    'd["cards"]["Z9"] = {"choice": None, "flagged": True, "rev": 1}'
expect_invalid "an answer rev ahead of its card is rejected" "only at rev 1" answers \
    'd["cards"]["A1"]["rev"] = 3'

echo "card states"
dir="$(fresh states)"
for pair in A1:decided C1:decided A2:harvested A3:changed-since-harvest A4:flagged B1:stale C2:stale B2:retired B3:untouched C3:untouched; do
    id="${pair%%:*}"; want="${pair#*:}"
    check "$id is $want" test "$(state_of "$dir" "$id")" = "$want"
done
out="$(board harvest-plan "$dir" --format text)"
check "text plan lists what to harvest" grep -q "to harvest: A1, C1" <<<"$out"
check "text plan lists open flagged cards" grep -q "open: needs discussion: A4" <<<"$out"

echo "revision"
dir="$(fresh revise)"
new="$T/revise-agenda.json"
answers_before="$(shasum "$dir/answers.json")"

cp "$dir/agenda.json" "$new"
mutate "$new" 'd["sections"][2]["cards"].append({"id": "C4", "q": "Is there a budget cap?", "decides": "What gets cut first.", "options": [{"key": "yes", "title": "Yes", "detail": "A hard number."}, {"key": "no", "title": "No", "detail": "Judged case by case."}]})'
board revise "$dir" --from "$new" >/dev/null 2>&1; rc=$?
check "adding a card is accepted" test "$rc" -eq 0
check "adding a card leaves answers.json untouched" test "$(shasum "$dir/answers.json")" = "$answers_before"
check "an added card starts untouched at rev 1" test "$(state_of "$dir" C4)" = untouched

cp "$dir/agenda.json" "$new"
mutate "$new" 'd["sections"][1]["cards"][2]["q"] = "How many days should it run?"'
board revise "$dir" --from "$new" >/dev/null 2>&1; rc=$?
check "rewording an unanswered card needs no flag" test "$rc" -eq 0

cp "$dir/agenda.json" "$new"
mutate "$new" 'd["sections"][0]["cards"][0]["q"] = "Where should the offsite be held this year?"'
out="$(board revise "$dir" --from "$new" 2>&1)"; rc=$?
check "changing an answered card without a flag is refused" bash -c '[ "$1" -eq 1 ] && grep -q "pass --bump A1" <<<"$2"' _ "$rc" "$out"
board revise "$dir" --from "$new" --keep-answer A1 >/dev/null 2>&1; rc=$?
check "--keep-answer accepts a rewording" test "$rc" -eq 0
check "a kept answer is still decided" test "$(state_of "$dir" A1)" = decided

cp "$dir/agenda.json" "$new"
mutate "$new" 'd["sections"][0]["cards"][0]["options"][2]["title"] = "Somewhere abroad, travel paid"'
board revise "$dir" --from "$new" --bump A1 >/dev/null 2>&1; rc=$?
check "--bump accepts a change of meaning" test "$rc" -eq 0
check "--bump raises the card rev" python3 -c 'import json, sys
a = json.load(open(sys.argv[1]))
sys.exit(0 if a["sections"][0]["cards"][0]["rev"] == 2 else 1)' "$dir/agenda.json"
check "a bumped card's answer goes stale" test "$(state_of "$dir" A1)" = stale

cp "$dir/agenda.json" "$new"
mutate "$new" 'd["sections"][1]["cards"].pop(2)'
out="$(board revise "$dir" --from "$new" 2>&1)"; rc=$?
check "deleting a card is refused" bash -c '[ "$1" -eq 1 ] && grep -q "retired\": true instead" <<<"$2"' _ "$rc" "$out"

cp "$dir/agenda.json" "$new"
mutate "$new" 'd["sections"][1]["cards"][2]["retired"] = True'
board revise "$dir" --from "$new" >/dev/null 2>&1; rc=$?
check "retiring a card is accepted" test "$rc" -eq 0
check "a retired card is retired" test "$(state_of "$dir" B3)" = retired

cp "$dir/agenda.json" "$new"
mutate "$new" 'd["sections"][1]["cards"][1]["retired"] = False'
board revise "$dir" --from "$new" >/dev/null 2>&1; rc=$?
check "un-retiring a card is refused" test "$rc" -eq 1

echo "render and index"
dir="$(fresh render)"
root="$(dirname "$dir")"
board render "$dir" >/dev/null
cp "$dir/BOARD.md" "$T/board-first.md"
board render "$dir" >/dev/null
check "render is byte-identical on rerun" cmp -s "$dir/BOARD.md" "$T/board-first.md"
board render "$dir" --check >/dev/null 2>&1; rc=$?
check "render --check passes when current" test "$rc" -eq 0
check "BOARD.md ticks the chosen option" grep -q '^- \[x\] \*\*A nearby retreat centre\*\*' "$dir/BOARD.md"
check "BOARD.md links a harvested card to its issue" grep -q "harvested → example/offsite#12" "$dir/BOARD.md"
check "BOARD.md shows a resolution" grep -q "Resolved in discussion" "$dir/BOARD.md"
mutate "$dir/answers.json" 'd["cards"]["A1"]["note"] = "Budget is *tight* | see https://example.com/budget_2026"'
board render "$dir" --check >/dev/null 2>&1; rc=$?
check "render --check fails after an answer edit" test "$rc" -eq 1
board render "$dir" >/dev/null
check "markdown in a note is escaped" grep -qF 'Budget is \*tight\* \| see <https://example.com/budget_2026>' "$dir/BOARD.md"

board index "$root" >/dev/null
board index "$root" --check >/dev/null 2>&1; rc=$?
check "index --check passes when current" test "$rc" -eq 0
check "index links the board" grep -qF "[2026-01-15-team-offsite](2026-01-15-team-offsite/BOARD.md)" "$root/README.md"
check "index lists harvest targets" grep -qF "example/offsite#12, example/offsite#13" "$root/README.md"
mutate "$dir/agenda.json" 'd["title"] = "Team Offsite Planning 2026"'
board index "$root" --check >/dev/null 2>&1; rc=$?
check "index --check fails after a title change" test "$rc" -eq 1

if command -v docker >/dev/null 2>&1 && docker image inspect davidanson/markdownlint-cli2:latest >/dev/null 2>&1; then
    lint="$T/lint"; mkdir -p "$lint"
    board render "$dir" >/dev/null; board index "$root" >/dev/null
    cp "$dir/BOARD.md" "$lint/BOARD.md"; cp "$root/README.md" "$lint/README.md"
    # Mirrors the rules homelab's CI enforces (.markdownlint-cli2.jsonc there).
    printf '%s\n' '{ "config": { "default": true, "MD013": false, "MD033": false, "MD041": false, "MD060": false,' \
        '"MD036": false, "MD003": false, "MD029": false, "MD028": false, "MD035": false, "MD024": { "siblings_only": true } } }' \
        > "$lint/.markdownlint-cli2.jsonc"
    out="$(docker run --rm -v "$lint:/workdir" davidanson/markdownlint-cli2:latest "*.md" 2>&1)"; rc=$?
    check "generated markdown passes markdownlint" test "$rc" -eq 0
    [ "$rc" -eq 0 ] || printf '%s\n' "$out"
else
    skip "generated markdown passes markdownlint (docker or the markdownlint-cli2 image is unavailable)"
fi

echo "init"
root="$T/init-root"; mkdir -p "$root"
cp "$FIXTURE/agenda.json" "$T/init-agenda.json"
mutate "$T/init-agenda.json" 'd["sections"][1]["cards"][0]["rev"] = 1; d["sections"][1]["cards"][1]["retired"] = False'
board init "$root/2026-01-15-team-offsite" --from "$T/init-agenda.json" >/dev/null 2>&1; rc=$?
check "init creates a board" test "$rc" -eq 0
check "init writes empty answers and harvest" bash -c 'grep -q "\"cards\": {}" "$1/answers.json" && grep -q "\"cards\": {}" "$1/harvest.json"' _ "$root/2026-01-15-team-offsite"
check "init writes BOARD.md and the index" test -f "$root/2026-01-15-team-offsite/BOARD.md" -a -f "$root/README.md"
board init "$root/2026-01-15-team-offsite" --from "$T/init-agenda.json" >/dev/null 2>&1; rc=$?
check "init refuses to overwrite a board" test "$rc" -eq 1
board init "$root/wrong-name" --from "$T/init-agenda.json" >/dev/null 2>&1; rc=$?
check "init refuses a directory not named after the board id" test "$rc" -eq 1

echo "harvest bookkeeping"
dir="$(fresh harvest)"
board mark-harvested "$dir" --cards A1,C1 --target example/offsite#20 >/dev/null 2>&1; rc=$?
check "mark-harvested records decided cards" test "$rc" -eq 0
check "a marked card is harvested" test "$(state_of "$dir" A1)" = harvested
check "a marked resolution is harvested" test "$(state_of "$dir" C1)" = harvested
check "nothing is left to harvest" bash -c 'python3 "$1" harvest-plan "$2" | python3 -c "import json,sys; sys.exit(0 if json.load(sys.stdin)[\"to_harvest\"] == [] else 1)"' _ "$BOARD" "$dir"
out="$(board harvest-plan "$dir" --format text)"
check "a second plan reports 0 to harvest" grep -q "· 0 to harvest ·" <<<"$out"
board mark-harvested "$dir" --cards A4 --target example/offsite#21 >/dev/null 2>&1; rc=$?
check "a flagged card cannot be marked" test "$rc" -eq 1
board mark-harvested "$dir" --cards B1 --target example/offsite#21 >/dev/null 2>&1; rc=$?
check "a stale card cannot be marked" test "$rc" -eq 1
board mark-harvested "$dir" --cards A1 --target "not a target" >/dev/null 2>&1; rc=$?
check "a malformed target is refused" test "$rc" -eq 1
board mark-harvested "$dir" --cards B3 --target vault:homelab/decisions/offsite.md >/dev/null 2>&1; rc=$?
check "an untouched card cannot be marked" test "$rc" -eq 1
mutate "$dir/answers.json" 'd["cards"]["A1"]["note"] = "Second thoughts."'
check "editing a harvested answer marks it changed-since-harvest" test "$(state_of "$dir" A1)" = changed-since-harvest
mutate "$dir/answers.json" 'd["cards"]["A1"]["note"] = ""; d["cards"]["A1"]["at"] = "2030-01-01T00:00:00Z"'
check "re-saving an unchanged answer keeps it harvested" test "$(state_of "$dir" A1)" = harvested

echo "harvest-apply"
# A stub gh that records every call. `issue list` returns $GH_LIST_JSON (default: no issues).
mkdir -p "$T/bin"
cat > "$T/bin/gh" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$GH_LOG"
case "$1 $2" in
    "issue list") printf '%s\n' "${GH_LIST_JSON:-[]}" ;;
    "issue create")
        n=$(( $(cat "$GH_COUNTER" 2>/dev/null || echo 40) + 1 )); echo "$n" > "$GH_COUNTER"
        echo "https://github.com/example/offsite/issues/$n" ;;
    "issue comment") echo "https://github.com/example/offsite/issues/$3#issuecomment-1" ;;
    "issue view") no_comments='{"comments": []}'; printf '%s\n' "${GH_VIEW_JSON:-$no_comments}" ;;
    *) echo "unexpected gh call: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$T/bin/gh"
export GH_LOG="$T/gh.log" GH_COUNTER="$T/gh.counter"

# harvest_repo <name>: a git repo holding the fixture board, committed. Prints the board dir.
harvest_repo() {
    local repo="$T/$1"
    rm -rf "$repo"; mkdir -p "$repo/docs/decision-boards"
    cp -R "$FIXTURE" "$repo/docs/decision-boards/"
    git -C "$repo" init -q
    git -C "$repo" add -A
    git -C "$repo" -c user.name=test -c user.email=test@example.invalid commit -q -m fixture
    printf '%s/docs/decision-boards/2026-01-15-team-offsite' "$repo"
}
apply() { PATH="$T/bin:$PATH" python3 "$BOARD" harvest-apply "$@"; }
gh_calls() { if [ -f "$GH_LOG" ]; then grep -c "$1" "$GH_LOG" || true; else echo 0; fi; }

dir="$(harvest_repo hrepo)"
drafts="$T/drafts.json"
printf '%s\n' '{"schema": "decision-board-drafts/1", "drafts": [' \
    '{"route": "issue", "cards": ["A1", "C1"], "repo": "example/offsite", "title": "Offsite: venue and facilitation", "body": "## Decision\n\nA retreat centre, with a split facilitator.", "labels": ["decision"]},' \
    '{"route": "comment", "cards": ["A3"], "issue": "example/offsite#13", "body": "The invite list changed: extended team."}' \
    ']}' > "$drafts"

bad="$T/bad-drafts.json"
printf '%s\n' '{"schema": "decision-board-drafts/1", "drafts": [{"route": "issue", "cards": ["A4"], "repo": "example/offsite", "title": "x", "body": "x"}]}' > "$bad"
out="$(apply "$dir" --drafts "$bad" --dry-run 2>&1)"; rc=$?
check "a flagged card cannot be drafted" bash -c '[ "$1" -eq 1 ] && grep -q "A4 is flagged" <<<"$2"' _ "$rc" "$out"
printf '%s\n' '{"schema": "decision-board-drafts/1", "drafts": [{"route": "issue", "cards": ["A3"], "repo": "example/offsite", "title": "x", "body": "x"}]}' > "$bad"
out="$(apply "$dir" --drafts "$bad" --dry-run 2>&1)"; rc=$?
check "a changed harvested card must be a comment on its issue" bash -c '[ "$1" -eq 1 ] && grep -q "route it as a comment" <<<"$2"' _ "$rc" "$out"
printf '%s\n' '{"schema": "decision-board-drafts/1", "drafts": [{"route": "vault", "cards": ["A1"], "path": "../escape.md", "body": "x"}]}' > "$bad"
apply "$dir" --drafts "$bad" --dry-run >/dev/null 2>&1; rc=$?
check "a vault path that climbs out is refused" test "$rc" -eq 1

harvest_before="$(shasum "$dir/harvest.json")"
rm -f "$GH_LOG"
out="$(apply "$dir" --drafts "$drafts" --dry-run 2>&1)"; rc=$?
check "dry run succeeds" test "$rc" -eq 0
check "dry run shows the marker" grep -q "decision-board: board=2026-01-15-team-offsite cards=A1,C1 hash=" <<<"$out"
check "dry run leaves harvest.json byte-identical" test "$(shasum "$dir/harvest.json")" = "$harvest_before"
check "dry run makes no gh calls" test ! -f "$GH_LOG"

mutate "$dir/answers.json" 'd["cards"]["B3"] = {"choice": "one", "note": "", "flagged": False, "rev": 1}'
out="$(apply "$dir" --drafts "$drafts" 2>&1)"; rc=$?
check "uncommitted answers are refused" bash -c '[ "$1" -eq 1 ] && grep -q "commit the answers first" <<<"$2"' _ "$rc" "$out"
git -C "$(dirname "$(dirname "$(dirname "$dir")")")" checkout -q -- .

repo_root="$T/hrepo"
mkdir -p "$repo_root/.claude/hooks"; : > "$repo_root/.claude/hooks/github-skill-gate.sh"
out="$(apply "$dir" --drafts "$drafts" --execute 2>&1)"; rc=$?
check "--execute is refused where hooks gate issue writes" bash -c '[ "$1" -eq 1 ] && grep -q "refusing --execute" <<<"$2"' _ "$rc" "$out"
out="$(apply "$dir" --drafts "$drafts" --out "$T/prepared" 2>&1)"; rc=$?
check "prepare mode prints the gh commands to run" bash -c '[ "$1" -eq 0 ] && grep -q "gh issue create --repo example/offsite" <<<"$2" && grep -q "mark-harvested" <<<"$2"' _ "$rc" "$out"
check "prepare mode only reads from GitHub" bash -c '[ -s "$1" ] && [ "$(grep -Evc "^issue (list|view) " "$1")" = 0 ]' _ "$GH_LOG"
check "prepare mode leaves harvest.json byte-identical" test "$(shasum "$dir/harvest.json")" = "$harvest_before"
check "prepared bodies carry the SHA-pinned record link" grep -q "blob/[0-9a-f]\{40\}/docs/decision-boards/2026-01-15-team-offsite/BOARD.md" "$T/prepared/draft-01.md"
check "without a GitHub remote the link falls back to the decided repo" grep -q "https://github.com/example/offsite/blob/" "$T/prepared/draft-01.md"
git -C "$repo_root" remote add origin git@github.com:example/evidence-owner.git
apply "$dir" --drafts "$drafts" --out "$T/prepared-remote" >/dev/null 2>&1
git -C "$repo_root" remote remove origin
check "the record link points at the repo that stores the board" grep -q "https://github.com/example/evidence-owner/blob/" "$T/prepared-remote/draft-01.md"
rm -rf "$repo_root/.claude"

rm -f "$GH_LOG" "$GH_COUNTER"
out="$(apply "$dir" --drafts "$drafts" --execute 2>&1)"; rc=$?
check "--execute succeeds" test "$rc" -eq 0
check "--execute creates one issue per issue draft" test "$(gh_calls '^issue create')" = 1
check "--execute posts one comment per comment draft" test "$(gh_calls '^issue comment')" = 1
check "harvested cards point at the new issue" python3 -c 'import json, sys
h = json.load(open(sys.argv[1]))["cards"]
sys.exit(0 if h["A1"]["target"] == h["C1"]["target"] == "example/offsite#41" else 1)' "$dir/harvest.json"
check "a changed card is harvested again once its update is posted" test "$(state_of "$dir" A3)" = harvested
calls_before="$(wc -l < "$GH_LOG")"
out="$(apply "$dir" --drafts "$drafts" --execute 2>&1)"; rc=$?
check "a second harvest succeeds" test "$rc" -eq 0
check "a second harvest makes zero gh calls" test "$(wc -l < "$GH_LOG")" = "$calls_before"
check "a second harvest reports the cards as already harvested" grep -q "skip: A1 already harvested → example/offsite#41" <<<"$out"

# A lost harvest.json must not produce duplicate issues: the marker on the existing issue repairs it.
git -C "$repo_root" checkout -q -- docs/decision-boards/2026-01-15-team-offsite/harvest.json
marker="$(sed -n 's/.*\(<!-- decision-board: board=2026-01-15-team-offsite cards=A1,C1 hash=[0-9a-f]* -->\).*/\1/p' "$T/prepared/draft-01.md")"
comment_marker="$(sed -n 's/.*\(<!-- decision-board: board=2026-01-15-team-offsite cards=A3 hash=[0-9a-f]* -->\).*/\1/p' "$T/prepared/draft-02.md")"
export GH_LIST_JSON="$(python3 -c 'import json, sys; print(json.dumps([{"number": 41, "body": "earlier issue\n" + sys.argv[1]}]))' "$marker")"
export GH_VIEW_JSON="$(python3 -c 'import json, sys; print(json.dumps({"comments": [{"body": "earlier update\n" + sys.argv[1]}]}))' "$comment_marker")"
rm -f "$GH_LOG"
out="$(apply "$dir" --drafts "$drafts" --execute 2>&1)"; rc=$?
check "a lost harvest record is repaired from the issue marker" bash -c '[ "$1" -eq 0 ] && grep -q "A1,C1 found in existing example/offsite#41" <<<"$2"' _ "$rc" "$out"
check "a lost harvest record is repaired from a comment marker" grep -q "A3 found in existing example/offsite#13" <<<"$out"
check "repairing creates no duplicate issue" test "$(gh_calls '^issue create')" = 0
check "repairing posts no duplicate comment" test "$(gh_calls '^issue comment')" = 0
check "the repaired card points at the existing issue" python3 -c 'import json, sys
sys.exit(0 if json.load(open(sys.argv[1]))["cards"]["A1"]["target"] == "example/offsite#41" else 1)' "$dir/harvest.json"

# A marker for an older answer is not this decision.
git -C "$repo_root" checkout -q -- docs/decision-boards/2026-01-15-team-offsite/harvest.json
mutate "$dir/answers.json" 'd["cards"]["A1"]["note"] = "Retreat, but only if it has step-free access."'
git -C "$repo_root" -c user.name=test -c user.email=test@example.invalid commit -q -am "revised answer"
rm -f "$GH_LOG" "$GH_COUNTER"
out="$(apply "$dir" --drafts "$drafts" --execute 2>&1)"; rc=$?
unset GH_LIST_JSON GH_VIEW_JSON
check "a marker for an older answer is not treated as harvested" bash -c '[ "$1" -eq 0 ] && grep -q "carries an older answer" <<<"$2"' _ "$rc" "$out"
check "the revised decision gets its own issue" test "$(gh_calls '^issue create')" = 1

dir="$(harvest_repo vrepo)"
printf '%s\n' '{"schema": "decision-board-drafts/1", "drafts": [{"route": "vault", "cards": ["C1"], "path": "homelab/decisions/offsite-facilitation.md", "body": "---\ntitle: Offsite facilitation\n---\n\nSplit facilitation."}]}' > "$T/vault-drafts.json"
MEMORY_VAULT_PATH="$T/vault" apply "$dir" --drafts "$T/vault-drafts.json" --execute >/dev/null 2>&1; rc=$?
check "a vault draft is written into the vault" bash -c '[ "$1" -eq 0 ] && grep -q "decision-board: board=2026-01-15-team-offsite cards=C1" "$2"' _ "$rc" "$T/vault/homelab/decisions/offsite-facilitation.md"
check "a vault draft records its target" python3 -c 'import json, sys
sys.exit(0 if json.load(open(sys.argv[1]))["cards"]["C1"]["target"] == "vault:homelab/decisions/offsite-facilitation.md" else 1)' "$dir/harvest.json"

echo "serve"
dir="$(fresh serve)"
log="$T/serve.log"
# wait_url <log>: print the URL a serve run announced, waiting up to 5s.
wait_url() {
    local u=""
    for _ in $(seq 1 50); do
        u="$(sed -n 's/^open *//p' "$1")"
        [ -n "$u" ] && break
        sleep 0.1
    done
    printf '%s' "$u"
}
python3 "$BOARD" serve "$dir" >"$T/default-1.log" 2>&1 &
first_pid=$!
first_url="$(wait_url "$T/default-1.log")"
python3 "$BOARD" serve "$dir" >"$T/default-2.log" 2>&1 &
second_pid=$!
second_url="$(wait_url "$T/default-2.log")"
kill -TERM "$second_pid" "$first_pid" 2>/dev/null; wait "$second_pid" "$first_pid" 2>/dev/null
expected_port="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import board; print(board.default_port("2026-01-15-team-offsite"))' "$SKILL/scripts")"
check "by default a board is served on its stable port" bash -c '[[ "$1" == "http://127.0.0.1:$2/?t="* ]]' _ "$first_url" "$expected_port"
check "a busy stable port falls back to a free one, with a warning" bash -c '[ -n "$1" ] && [[ "$1" != "http://127.0.0.1:$2/"* ]] && grep -q "port $2 is busy" "$3"' _ "$second_url" "$expected_port" "$T/default-2.log"

python3 "$BOARD" serve "$dir" --port 0 >"$log" 2>&1 &
server_pid=$!
url="$(wait_url "$log")"
check "serve prints a loopback URL with a token" bash -c '[[ "$1" =~ ^http://127\.0\.0\.1:[0-9]+/\?t=[A-Za-z0-9_-]{20,}$ ]]' _ "$url"
base="${url%%/?t=*}"; token="${url##*t=}"; hostport="${base#http://}"; port="${hostport##*:}"

code() { curl -s -o "$T/body" -w '%{http_code}' "$@"; }
put() { # put <card> <json> [extra curl args...]
    local card="$1" json="$2"; shift 2
    code -X PUT -H "X-Board-Token: $token" -H "Content-Type: application/json" --data "$json" "$@" "$base/answers/$card"
}

check "the page without a token is 403" test "$(code "$base/")" = 403
check "the page with the token is 200" test "$(code "$base/?t=$token")" = 200
check "the page makes no external requests" bash -c '! grep -Eq "(src|href)=\"(https?:)?//" "$1" && ! grep -q "fonts.googleapis" "$1"' _ "$T/body"
check "the page carries a nonce CSP" bash -c 'curl -s -D - -o /dev/null "$1" | grep -qi "content-security-policy: default-src '"'"'none'"'"'.*script-src '"'"'nonce-"' _ "$base/?t=$token"
check "a foreign Host header is 403" test "$(code -H "Host: evil.example:$port" "$base/?t=$token")" = 403
check "the API without the token header is 403" test "$(code "$base/answers")" = 403
check "the API with the token header is 200" test "$(code -H "X-Board-Token: $token" "$base/answers")" = 200
check "the API reports computed states" grep -q '"A3": "changed-since-harvest"' "$T/body"
check "a wrong token is 403" test "$(code -H "X-Board-Token: nope" "$base/agenda")" = 403
check "a PUT from a foreign Origin is 403" test "$(put B3 '{"choice":"two","note":"","flagged":false,"rev":1}' -H "Origin: https://evil.example")" = 403
check "a PUT from the page's own Origin is accepted" test "$(put B3 '{"choice":"two","note":"","flagged":false,"rev":1}' -H "Origin: http://127.0.0.1:$port")" = 200
check "the answer lands in answers.json" python3 -c 'import json, sys
a = json.load(open(sys.argv[1]))["cards"]
sys.exit(0 if a["B3"]["choice"] == "two" and a["B3"]["rev"] == 1 else 1)' "$dir/answers.json"
check "other answers are preserved" python3 -c 'import json, sys
a = json.load(open(sys.argv[1]))["cards"]
sys.exit(0 if a["A1"]["choice"] == "retreat" and a["A4"]["flagged"] else 1)' "$dir/answers.json"
board render "$dir" --check >/dev/null 2>&1; rc=$?
check "serve keeps BOARD.md in sync" test "$rc" -eq 0
check "an unknown card is 400" test "$(put Z9 '{"choice":null,"note":"","flagged":true,"rev":1}')" = 400
check "an option the card does not have is 400" test "$(put B3 '{"choice":"seven","note":"","flagged":false,"rev":1}')" = 400
check "a retired card is 400" test "$(put B2 '{"choice":"late","note":"","flagged":false,"rev":1}')" = 400
check "flagged with a choice is 400" test "$(put B3 '{"choice":"two","note":"","flagged":true,"rev":1}')" = 400
check "an unknown field is 400" test "$(put B3 '{"choice":"two","note":"","flagged":false,"rev":1,"admin":true}')" = 400
check "an answer against an old card rev is 409" test "$(put B1 '{"choice":"spring","note":"","flagged":false,"rev":1}')" = 409
# Bodies are built in variables: bash 3.2 keeps the backslashes of \" inside "$( )", which corrupts inline JSON.
confirm_body='{"choice":"spring","note":"","flagged":false,"rev":2}'
check "confirming against the current rev clears stale" test "$(put B1 "$confirm_body")" = 200
check "the confirmed card is decided" test "$(state_of "$dir" B1)" = decided
big_body="$(python3 -c 'import json; print(json.dumps({"choice": "two", "note": "x" * 20000, "flagged": False, "rev": 1}))')"
check "an oversized body is 413" test "$(put B3 "$big_body")" = 413
check "a non-JSON content type is 415" test "$(code -X PUT -H "X-Board-Token: $token" -H "Content-Type: text/plain" --data 'x' "$base/answers/B3")" = 415
cred_body="$(python3 -c 'import json; print(json.dumps({"choice": "two", "note": "pass" + "word=hunter2hunter2hunter2", "flagged": False, "rev": 1}))')"
check "a credential in a note is 400" test "$(put B3 "$cred_body")" = 400
check "an unknown path is 404" test "$(code -H "X-Board-Token: $token" "$base/etc/passwd")" = 404
check "a traversal path is 404" test "$(code --path-as-is -H "X-Board-Token: $token" "$base/../agenda.json")" = 404
check "POST is not allowed" test "$(code -X POST -H "X-Board-Token: $token" "$base/answers/B3")" = 405
mutate "$dir/answers.json" 'd["cards"]["C3"]["note"] = "Edited by hand while the page was open."'
check "a PUT after a hand edit succeeds" test "$(put A4 '{"choice":"no","note":"Talked it through.","flagged":false,"rev":1}')" = 200
check "the concurrent hand edit to another card survives" grep -q "Edited by hand while the page was open." "$dir/answers.json"
clear_body='{"choice":null,"note":"","flagged":false,"rev":1}'
check "clearing an answer is accepted" test "$(put B3 "$clear_body")" = 200
check "clearing an answer with no note removes it" bash -c '! grep -q "\"B3\"" "$1"' _ "$dir/answers.json"
mutate "$dir/answers.json" 'd["cards"]["C2"] = "broken"'
c3_body='{"choice":"advance","note":"","flagged":false,"rev":1}'
check "an invalid answers.json on disk is 409" test "$(put C3 "$c3_body")" = 409
check "an invalid answers.json on disk is not overwritten" grep -q '"broken"' "$dir/answers.json"
kill -TERM "$server_pid" 2>/dev/null; wait "$server_pid" 2>/dev/null
check "serve stops cleanly on SIGTERM" grep -q "^stopped" "$log"
check "the server is gone" bash -c '! curl -s -o /dev/null --max-time 2 "$1/"' _ "$base"

echo "no server"
dir="$(fresh by-hand)"
mutate "$dir/answers.json" 'd["cards"]["B3"] = {"choice": "one", "note": "Answered on my phone, in the GitHub editor.", "flagged": False, "rev": 1}'
board validate "$dir" >/dev/null 2>&1; rc=$?
check "a hand-edited answers.json validates" test "$rc" -eq 0
board render "$dir" >/dev/null
check "a hand-edited answer renders" grep -q "Answered on my phone" "$dir/BOARD.md"
check "a hand-edited answer counts as decided" test "$(state_of "$dir" B3)" = decided

printf '\n%d passed, %d failed, %d skipped\n' "$pass" "$failed" "$skipped"
[ "$failed" -eq 0 ]
