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

echo "the app client"
# A loopback stand-in for the boards API. The app's RULES live in fredabood/work
# and are tested there against the same vendored core that board.py is the source
# of; re-testing them here would write them twice and prove only that the two
# copies agree. What is tested here is board.py's client half — method, path,
# body, headers, and how a failure reads.
STUB_STATE="$T/stub.json"
STUB_LOG="$T/stub.log"
REF=offsite/2026-01-15-team-offsite

stub_state() { printf '%s\n' "$1" > "$STUB_STATE"; }
stub_reset() { : > "$STUB_LOG"; }
# stub_sent <"METHOD /path">: the first matching request, as one JSON line (empty if none).
stub_sent() {
    python3 -c 'import json, sys
for line in open(sys.argv[1]):
    r = json.loads(line)
    if r["key"] == sys.argv[2]:
        print(json.dumps(r)); break' "$STUB_LOG" "$1"
}
# content_hash <dir>: as the app computes it — sha256(agenda||answers)[:16], board.py serialization.
content_hash() {
    python3 -c 'import hashlib, json, sys
def d(p): return json.dumps(json.load(open(p)), indent=2, sort_keys=True, ensure_ascii=False) + "\n"
print(hashlib.sha256((d(sys.argv[1]) + d(sys.argv[2])).encode("utf-8")).hexdigest()[:16])' \
        "$1/agenda.json" "$1/answers.json"
}
# stub_board <ref> <content_hash> <frozen_sha|null> <drifted> [files_json]
stub_board() {
    python3 -c 'import json, sys
files = json.loads(sys.argv[6]) if len(sys.argv) > 6 else {}
state = {"log": sys.argv[1], "boards": {sys.argv[2]: {
    "files": files, "content_hash": sys.argv[3],
    "frozen_sha": None if sys.argv[4] == "null" else sys.argv[4],
    "drifted": sys.argv[5] == "true",
    "states": {"A1": "decided", "A2": "untouched"}}}}
print(json.dumps(state))' "$STUB_LOG" "$@" > "$STUB_STATE"
}
# export_files <dir>: the four documents, as the app would return them.
export_files() {
    python3 -c 'import json, sys, pathlib
d = pathlib.Path(sys.argv[1])
print(json.dumps({n: (d / n).read_text() for n in
                  ("agenda.json", "answers.json", "harvest.json", "BOARD.md")}))' "$1"
}

stub_state '{"boards": {}, "log": "'"$STUB_LOG"'"}'
python3 "$SKILL/tests/stub_api.py" "$STUB_STATE" > "$T/stub.url" 2>"$T/stub.err" &
stub_pid=$!
# `wait` after the kill, so the shell reaps it quietly instead of printing
# "Terminated" over the results.
trap 'kill "$stub_pid" 2>/dev/null; wait "$stub_pid" 2>/dev/null; rm -rf "$T"' EXIT
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$T/stub.url" ] && break; sleep 0.3; done
API="$(cat "$T/stub.url" 2>/dev/null || true)"
check "the stub API came up" bash -c 'case "$1" in http://127.0.0.1:*) exit 0;; *) exit 1;; esac' _ "$API"
export DECISION_BOARD_API="$API"

# The fixture deliberately carries a retired card and a bumped rev — it exists to
# exercise the state machine. A NEW board may carry neither, so flatten it once here.
# It matters that this comes FIRST: with the raw fixture the next check would exit 1
# on local validation and never reach the URL it claims to be testing.
NEW_AGENDA="$T/new-agenda.json"
cp "$FIXTURE/agenda.json" "$NEW_AGENDA"
mutate "$NEW_AGENDA" 'for sec in d["sections"]:
    for c in sec["cards"]:
        c["rev"] = 1
        c.pop("retired", None)'
board new --from "$FIXTURE/agenda.json" >/dev/null 2>&1; rc=$?
check "the raw fixture is refused as a new board (so the next check is not vacuous)" test "$rc" -eq 1

out="$(DECISION_BOARD_API=http://example.invalid/api board new --from "$NEW_AGENDA" 2>&1)"; rc=$?
check "a non-loopback http API is refused" test "$rc" -eq 1
check "refusing it says why" grep -q "must be https" <<<"$out"

# This repo is public, so there is no default host in it. The address comes from
# the environment or from the private vault profile, and its absence is a readable
# refusal rather than a crash or a request to nowhere.
mkdir -p "$T/novault"
out="$(DECISION_BOARD_API= MEMORY_VAULT_PATH="$T/novault" board new --from "$NEW_AGENDA" 2>&1)"; rc=$?
check "no API configured is refused" test "$rc" -eq 1
check "the refusal names the variable" grep -q "DECISION_BOARD_API" <<<"$out"
check "the refusal names the profile line" grep -q "Decision board API" <<<"$out"
check "a missing vault is not a crash" bash -c '! grep -q Traceback <<<"$1"' _ "$out"

mkdir -p "$T/vaultprofile/personal"
printf '%s\n' "## Homelab" "" "- **Decision board API**: $API" > "$T/vaultprofile/personal/profile.md"
stub_reset
mutate "$NEW_AGENDA" 'd["id"] = "2026-03-01-profile-probe"'
DECISION_BOARD_API= MEMORY_VAULT_PATH="$T/vaultprofile" board new --from "$NEW_AGENDA" >/dev/null 2>&1; rc=$?
check "the vault profile supplies the API base" test "$rc" -eq 0
check "the profile-configured call reached the stub" test -n "$(stub_sent "POST /boards")"
mutate "$NEW_AGENDA" 'd["id"] = "2026-01-15-team-offsite"'

echo "new"
stub_reset
out="$(board new --from "$NEW_AGENDA" 2>&1)"; rc=$?
check "new publishes the board" test "$rc" -eq 0
check "new reports the card count" grep -q "10 cards in 3 sections" <<<"$out"
check "new prints a URL to answer it at" grep -q "/#/boards/$REF" <<<"$out"
sent="$(stub_sent "POST /boards")"
check "new POSTs the agenda to /boards" test -n "$sent"
check "new sends application/json" grep -q '"content_type": "application/json"' <<<"$sent"
check "new writes nothing to disk" test ! -e "docs/decision-boards/2026-01-15-team-offsite"
out="$(board new --from "$NEW_AGENDA" 2>&1)"; rc=$?
check "new surfaces a 409 from the app" test "$rc" -eq 1
check "the 409 keeps the app's own message" grep -q "already exists" <<<"$out"

# Local validation runs BEFORE the request, so a bad agenda fails against the file
# you are editing with one message per problem, not as one flattened 400.
stub_reset
bad_agenda="$T/bad-agenda.json"
cp "$NEW_AGENDA" "$bad_agenda"
mutate "$bad_agenda" 'd["sections"][0]["cards"][0]["q"] = ""'
out="$(board new --from "$bad_agenda" 2>&1)"; rc=$?
check "an invalid agenda is refused locally" test "$rc" -eq 1
check "the local refusal names the file" grep -q "agenda is invalid" <<<"$out"
check "an invalid agenda is never sent" test -z "$(stub_sent "POST /boards")"
cp "$NEW_AGENDA" "$bad_agenda"
mutate "$bad_agenda" 'd["sections"][0]["cards"][0]["rev"] = 3'
out="$(board new --from "$bad_agenda" 2>&1)"; rc=$?
check "a pre-revised card is refused locally" test "$rc" -eq 1
check "the pre-revised refusal explains rev 1" grep -q "rev 1" <<<"$out"

echo "the service token"
cp "$NEW_AGENDA" "$T/tok-agenda.json"
mutate "$T/tok-agenda.json" 'd["id"] = "2026-02-01-token-probe"'
stub_reset
JIRA_GRAPH_SERVICE_TOKEN=test_only_fake_not_a_secret board new --from "$T/tok-agenda.json" >/dev/null 2>&1
sent="$(stub_sent "POST /boards")"
check "the token is sent as X-Service-Token" grep -q 'test_only_fake_not_a_secret' <<<"$sent"
stub_reset
mutate "$T/tok-agenda.json" 'd["id"] = "2026-02-02-token-probe"'
board new --from "$T/tok-agenda.json" >/dev/null 2>&1
sent="$(stub_sent "POST /boards")"
check "no token set sends no header" grep -q '"token": null' <<<"$sent"
stub_state '{"boards": {}, "log": "'"$STUB_LOG"'", "fail": {"POST /boards": [403, ""]}}'
out="$(JIRA_GRAPH_SERVICE_TOKEN=test_only_fake_not_a_secret board new --from "$T/tok-agenda.json" 2>&1)"; rc=$?
check "a 403 is a readable error, not a traceback" test "$rc" -eq 1
check "a 403 names the variable to set" grep -q "JIRA_GRAPH_SERVICE_TOKEN" <<<"$out"
check "a 403 never echoes the token" bash -c '! grep -q test_only_fake <<<"$1"' _ "$out"

echo "revise"
stub_board "$REF" 0000000000000000 null false
new="$T/revise-agenda.json"
cp "$FIXTURE/agenda.json" "$new"
stub_reset
out="$(board revise "$REF" --from "$new" --bump A1 --keep-answer A3 2>&1)"; rc=$?
check "revise succeeds" test "$rc" -eq 0
sent="$(stub_sent "POST /boards/$REF/revise")"
check "revise POSTs to the board's revise path" test -n "$sent"
check "revise sends bump" grep -q '"bump": \["A1"\]' <<<"$sent"
check "revise sends keep" grep -q '"keep": \["A3"\]' <<<"$sent"
check "revise reports what was bumped" grep -q "bumped (answer now stale): A1" <<<"$out"
check "revise reports what was kept" grep -q "kept (answer still stands): A3" <<<"$out"
check "revise says a re-freeze is needed" grep -q "does not re-freeze" <<<"$out"
stub_reset
mutate "$new" 'd["sections"][0]["cards"][0]["q"] = ""'
out="$(board revise "$REF" --from "$new" 2>&1)"; rc=$?
check "an invalid revision is refused locally" test "$rc" -eq 1
check "the invalid revision names the file" grep -q "new agenda is invalid" <<<"$out"
check "an invalid revision is never sent" test -z "$(stub_sent "POST /boards/$REF/revise")"
out="$(board revise "not-a-ref" --from "$FIXTURE/agenda.json" 2>&1)"; rc=$?
check "a malformed board ref is refused" test "$rc" -eq 1
check "the ref refusal shows the shape" grep -q "<repo>/<board-id>" <<<"$out"

echo "freeze"
frepo="$T/frepo"
rm -rf "$frepo"; mkdir -p "$frepo/docs/decision-boards"
git -C "$frepo" init -q
git -C "$frepo" -c user.name=test -c user.email=test@example.invalid commit -q --allow-empty -m init
src="$(fresh freeze-src)"
hash_before="$(content_hash "$src")"
stub_board "$REF" "$hash_before" null false "$(export_files "$src")"
stub_reset
out="$(cd "$frepo" && DECISION_BOARD_API="$API" python3 "$BOARD" freeze "$REF" 2>&1)"; rc=$?
fdir="$frepo/docs/decision-boards/2026-01-15-team-offsite"
check "freeze succeeds" test "$rc" -eq 0
check "freeze writes all four documents" test -f "$fdir/agenda.json" -a -f "$fdir/answers.json" -a -f "$fdir/harvest.json" -a -f "$fdir/BOARD.md"
check "freeze writes the export byte for byte" cmp -s "$src/agenda.json" "$fdir/agenda.json"
check "freeze regenerates the index" test -f "$frepo/docs/decision-boards/README.md"
check "freeze commits what it wrote" test -z "$(git -C "$frepo" status --porcelain)"
sent="$(stub_sent "POST /boards/$REF/freeze")"
check "freeze tells the app which commit it landed in" grep -q '"sha"' <<<"$sent"
check "freeze sends the content hash it exported" grep -q "\"content_hash\": \"$hash_before\"" <<<"$sent"
head_sha="$(git -C "$frepo" rev-parse HEAD)"
check "the recorded sha is the freeze commit" grep -q "$head_sha" <<<"$sent"
check "freeze reports the board is now git-of-record" grep -q "git-of-record" <<<"$out"

# The app moved between the export and the commit: recording the freeze would
# mark the board frozen at content that was never committed.
stub_board "$REF" "$hash_before" null false "$(export_files "$src")"
python3 -c 'import json,sys
s=json.load(open(sys.argv[1])); s["fail"]={"POST /boards/'"$REF"'/freeze": [409, "the board changed between export and commit"]}
json.dump(s, open(sys.argv[1],"w"))' "$STUB_STATE"
rm -rf "$frepo/docs/decision-boards/2026-01-15-team-offsite"
out="$(cd "$frepo" && DECISION_BOARD_API="$API" python3 "$BOARD" freeze "$REF" 2>&1)"; rc=$?
check "a 409 on freeze is surfaced" test "$rc" -eq 1
check "the 409 says to re-export" grep -q "changed between export and commit" <<<"$out"

stub_board "$REF" "$hash_before" null false "$(export_files "$src")"
nrepo="$T/nrepo"; rm -rf "$nrepo"; mkdir -p "$nrepo"
stub_reset
out="$(cd "$nrepo" && DECISION_BOARD_API="$API" python3 "$BOARD" freeze "$REF" --no-commit 2>&1)"; rc=$?
check "--no-commit writes the files" test -f "$nrepo/docs/decision-boards/2026-01-15-team-offsite/BOARD.md"
check "--no-commit records no freeze" test -z "$(stub_sent "POST /boards/$REF/freeze")"
check "--no-commit says how to record it" grep -q -- "--record" <<<"$out"
echo "harvest helpers"
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

echo "harvest bookkeeping"
hdir="$(fresh harvest)"
stub_board "$REF" "$(content_hash "$hdir")" null false "$(export_files "$hdir")"
stub_reset
out="$(board mark-harvested "$REF" --cards A1,C1 --target example/offsite#20 2>&1)"; rc=$?
check "mark-harvested succeeds" test "$rc" -eq 0
sent="$(stub_sent "POST /boards/$REF/harvest")"
check "mark-harvested POSTs to the app" test -n "$sent"
check "mark-harvested sends the cards" grep -q '"cards": \["A1", "C1"\]' <<<"$sent"
check "mark-harvested sends the target" grep -q '"target": "example/offsite#20"' <<<"$sent"
check "mark-harvested reports what it did" grep -q "marked A1, C1 → example/offsite#20" <<<"$out"

# The refusals that are still local: they are about the ARGUMENTS, and failing on
# them without a round trip keeps a typo from reaching the network.
out="$(board mark-harvested "$REF" --cards A1 --target "not a target" 2>&1)"; rc=$?
check "a malformed target is refused" test "$rc" -eq 1
check "the target refusal shows the two shapes" grep -q "owner/repo#N or vault:path.md" <<<"$out"
stub_reset
board mark-harvested "$REF" --cards A1 --target "not a target" >/dev/null 2>&1
check "a malformed target is never sent" test -z "$(stub_sent "POST /boards/$REF/harvest")"
out="$(board mark-harvested "$REF" --cards "" --target example/offsite#20 2>&1)"; rc=$?
check "no cards is refused" test "$rc" -eq 1

# --into refreshes the frozen export. It has to be explicit here rather than
# automatic from a drift banner: content_hash deliberately covers the agenda and
# answers only, so marking a card harvested never makes a board read as drifted.
marked="$(fresh harvest-into)"
python3 -c 'import json, sys
h = json.load(open(sys.argv[1] + "/harvest.json"))
h.setdefault("cards", {})["A1"] = {"target": "example/offsite#20", "hash": sys.argv[2], "at": "2026-01-20T00:00:00Z"}
open(sys.argv[1] + "/harvest.json", "w").write(json.dumps(h, indent=2, sort_keys=True, ensure_ascii=False) + "\n")' \
    "$marked" "$(python3 -c 'import hashlib, json, sys
a = json.load(open(sys.argv[1] + "/answers.json"))["cards"]["A1"]
e = {"choice": a.get("choice"), "note": a.get("note") or "", "flagged": bool(a.get("flagged")), "resolution": a.get("resolution"), "rev": a.get("rev", 1)}
print(hashlib.sha256(json.dumps(e, sort_keys=True).encode("utf-8")).hexdigest()[:16])' "$marked")"
stub_board "$REF" "$(content_hash "$marked")" null false "$(export_files "$marked")"
into="$(fresh harvest-target)"
board mark-harvested "$REF" --cards A1 --target example/offsite#20 --into "$into" >/dev/null 2>&1; rc=$?
check "--into succeeds" test "$rc" -eq 0
check "--into rewrites harvest.json from the app" grep -q "example/offsite#20" "$into/harvest.json"
check "--into leaves the card harvested" test "$(state_of "$into" A1)" = harvested

echo "the freeze gate"
# This replaces the old "commit your answers first" dirty-check, which asked a
# weaker question: a clean worktree only says nobody edited these files, not that
# they still match the board people are answering.
gdir="$(harvest_repo gaterepo)"
gate_drafts="$T/gate-drafts.json"
printf '%s\n' '{"schema": "decision-board-drafts/1", "drafts": [{"route": "issue", "cards": ["A1"], "repo": "example/offsite", "title": "x", "body": "x"}]}' > "$gate_drafts"

stub_board "$REF" "$(content_hash "$gdir")" null false "$(export_files "$gdir")"
out="$(apply "$gdir" --drafts "$gate_drafts" 2>&1)"; rc=$?
check "a never-frozen board is refused" test "$rc" -eq 1
check "the never-frozen refusal says to freeze" grep -q "has never been frozen" <<<"$out"
out="$(apply "$gdir" --drafts "$gate_drafts" --dry-run 2>&1)"; rc=$?
check "--dry-run works on a never-frozen board" test "$rc" -eq 0

stub_board "$REF" "$(content_hash "$gdir")" deadbeefdeadbeefdeadbeefdeadbeefdeadbeef true "$(export_files "$gdir")"
out="$(apply "$gdir" --drafts "$gate_drafts" 2>&1)"; rc=$?
check "a drifted board is refused" test "$rc" -eq 1
check "the drift refusal says to freeze again" grep -q "changed in the app since it was frozen" <<<"$out"

stub_board "$REF" 1111111111111111 deadbeefdeadbeefdeadbeefdeadbeefdeadbeef false "$(export_files "$gdir")"
out="$(apply "$gdir" --drafts "$gate_drafts" 2>&1)"; rc=$?
check "a directory that is not the frozen export is refused" test "$rc" -eq 1
check "the mismatch refusal names the directory" grep -q "does not match the frozen export" <<<"$out"

# freeze_stub <board-dir>: report that directory to the stub as FROZEN, at the sha
# its own repo is currently on. Every non-dry-run harvest needs this: the gate now
# asks whether these files ARE the frozen record, not merely whether git is clean.
freeze_stub() {
    local d="$1" root
    root="$(git -C "$d" rev-parse --show-toplevel)"
    stub_board "$REF" "$(content_hash "$d")" "$(git -C "$root" rev-parse HEAD)" false "$(export_files "$d")"
}

echo "harvest-apply"
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

freeze_stub "$dir"
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
freeze_stub "$dir"
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
freeze_stub "$dir"
mutate "$dir/answers.json" 'd["cards"]["A1"]["note"] = "Retreat, but only if it has step-free access."'
git -C "$repo_root" -c user.name=test -c user.email=test@example.invalid commit -q -am "revised answer"
freeze_stub "$dir"
rm -f "$GH_LOG" "$GH_COUNTER"
out="$(apply "$dir" --drafts "$drafts" --execute 2>&1)"; rc=$?
unset GH_LIST_JSON GH_VIEW_JSON
check "a marker for an older answer is not treated as harvested" bash -c '[ "$1" -eq 0 ] && grep -q "carries an older answer" <<<"$2"' _ "$rc" "$out"
check "the revised decision gets its own issue" test "$(gh_calls '^issue create')" = 1

dir="$(harvest_repo vrepo)"
freeze_stub "$dir"
printf '%s\n' '{"schema": "decision-board-drafts/1", "drafts": [{"route": "vault", "cards": ["C1"], "path": "homelab/decisions/offsite-facilitation.md", "body": "---\ntitle: Offsite facilitation\n---\n\nSplit facilitation."}]}' > "$T/vault-drafts.json"
MEMORY_VAULT_PATH="$T/vault" apply "$dir" --drafts "$T/vault-drafts.json" --execute >/dev/null 2>&1; rc=$?
check "a vault draft is written into the vault" bash -c '[ "$1" -eq 0 ] && grep -q "decision-board: board=2026-01-15-team-offsite cards=C1" "$2"' _ "$rc" "$T/vault/homelab/decisions/offsite-facilitation.md"
check "a vault draft records its target" python3 -c 'import json, sys
sys.exit(0 if json.load(open(sys.argv[1]))["cards"]["C1"]["target"] == "vault:homelab/decisions/offsite-facilitation.md" else 1)' "$dir/harvest.json"

echo "an export read on its own"
# NOT "you can still answer by hand": an edit here reaches nobody, and the next
# freeze overwrites it. What these pin is that the local readers stay honest about
# whatever bytes they are handed, and need no network — which is what makes them a
# fallback when the app is unreachable, and a parity oracle for its card states.
OFFLINE=http://127.0.0.1:1
dir="$(fresh by-hand)"
mutate "$dir/answers.json" 'd["cards"]["B3"] = {"choice": "one", "note": "Answered on my phone, in the GitHub editor.", "flagged": False, "rev": 1}'
board validate "$dir" >/dev/null 2>&1; rc=$?
check "an edited answers.json still validates" test "$rc" -eq 0
DECISION_BOARD_API="$OFFLINE" board validate "$dir" >/dev/null 2>&1; rc=$?
check "validate needs no network" test "$rc" -eq 0
board render "$dir" >/dev/null
check "the edit renders into BOARD.md" grep -q "Answered on my phone" "$dir/BOARD.md"
check "the edit counts as decided" test "$(state_of "$dir" B3)" = decided
DECISION_BOARD_API="$OFFLINE" board harvest-plan "$dir" >/dev/null 2>&1; rc=$?
check "harvest-plan needs no network" test "$rc" -eq 0
DECISION_BOARD_API="$OFFLINE" board render "$dir" --check >/dev/null 2>&1; rc=$?
check "render --check needs no network" test "$rc" -eq 0

printf '\n%d passed, %d failed, %d skipped\n' "$pass" "$failed" "$skipped"
# A suite that asserted nothing did not pass: the stub API failing to start would
# otherwise skip every check below it and still exit 0.
[ "$failed" -eq 0 ] && [ "$pass" -gt 0 ]
