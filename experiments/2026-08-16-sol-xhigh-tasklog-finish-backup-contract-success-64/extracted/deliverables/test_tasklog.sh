#!/usr/bin/env bash

set -u
set -o pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")" && pwd -P)" || exit 1
TASKLOG="$ROOT/tasklog.sh"
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/tasklog-tests.XXXXXX")" || exit 1
OUT="$SANDBOX/stdout"
ERR="$SANDBOX/stderr"
SNAPSHOT="$SANDBOX/snapshot"
COUNT=0

cleanup() {
    rm -rf "$SANDBOX"
}
trap cleanup EXIT HUP INT TERM

fail() {
    printf 'not ok %d - %s\n' "$((COUNT + 1))" "$*" >&2
    [[ ! -s "$OUT" ]] || sed 's/^/  stdout: /' "$OUT" >&2
    [[ ! -s "$ERR" ]] || sed 's/^/  stderr: /' "$ERR" >&2
    exit 1
}

pass() {
    COUNT=$((COUNT + 1))
    printf 'ok %d - %s\n' "$COUNT" "$1"
}

run_ok() {
    : >"$OUT"
    : >"$ERR"
    bash "$TASKLOG" "$@" >"$OUT" 2>"$ERR" ||
        fail "command failed: $*"
}

expect_output() {
    local description="$1" expected="$2"
    shift 2
    run_ok "$@"
    [[ "$(cat "$OUT")" == "$expected" ]] ||
        fail "$description produced unexpected output"
    pass "$description"
}

expect_fail_unchanged() {
    local description="$1"
    shift
    cp -- "$TASKLOG_DB" "$SNAPSHOT" ||
        fail "could not snapshot database"
    : >"$OUT"
    : >"$ERR"
    if bash "$TASKLOG" "$@" >"$OUT" 2>"$ERR"; then
        fail "$description unexpectedly succeeded"
    fi
    cmp -s -- "$SNAPSHOT" "$TASKLOG_DB" ||
        fail "$description changed the database"
    [[ -s "$ERR" ]] ||
        fail "$description produced no diagnostic"
    pass "$description leaves the database unchanged"
}

WORK="$SANDBOX/work"
mkdir -p "$WORK"
export TASKLOG_DB="$WORK/events.jsonl"
export TASKLOG_NOW='2025-01-01T00:00:00Z'

expect_output "empty validation" "valid" validate
expect_output "empty summary" \
    '{"active":0,"done":0,"open":0,"total":0}' summary
expect_output "empty list" "" list
[[ ! -e "$TASKLOG_DB" ]] ||
    fail "read-only commands created the database"
pass "empty database remains absent"

title='A "quoted" \ path — café'
tag_one='red team'
tag_two='quote"slash\雪'
expect_output "first add" "1" \
    add --title "$title" --tag "$tag_one" --tag "$tag_two"

[[ "$(wc -l <"$TASKLOG_DB" | tr -d '[:space:]')" == 1 ]] ||
    fail "add did not append exactly one event"
jq -e --arg title "$title" --arg one "$tag_one" --arg two "$tag_two" '
  .type == "add"
  and .id == 1
  and .title == $title
  and .tags == [$one, $two]
  and .at == "2025-01-01T00:00:00Z"
' "$TASKLOG_DB" >"$OUT" 2>"$ERR" ||
    fail "creation event did not preserve escaped values"
pass "titles and tags preserve spaces, quotes, backslashes, and UTF-8"

run_ok show 1
shown="$(cat "$OUT")"
[[ "$shown" == "$(printf '%s\n' "$shown" | jq -cS .)" ]] ||
    fail "show output is not canonical compact JSON"
printf '%s\n' "$shown" | jq -e \
    --arg title "$title" --arg one "$tag_one" --arg two "$tag_two" '
      . == {
        created_at: "2025-01-01T00:00:00Z",
        id: 1,
        status: "open",
        tags: [$one, $two],
        title: $title,
        updated_at: "2025-01-01T00:00:00Z"
      }
    ' >"$OUT" 2>"$ERR" ||
    fail "show returned incorrect state"
pass "show emits canonical current-state JSON"

export TASKLOG_NOW='2025-01-01T01:00:00Z'
expect_output "start transition" "" start 1
export TASKLOG_NOW='2025-01-01T02:00:00Z'
expect_output "done transition" "" done 1
export TASKLOG_NOW='2025-01-01T03:00:00Z'
expect_output "reopen transition" "" reopen 1

run_ok show 1
printf '%s\n' "$(cat "$OUT")" | jq -e '
  .status == "open"
  and .created_at == "2025-01-01T00:00:00Z"
  and .updated_at == "2025-01-01T03:00:00Z"
' >"$OUT.tmp" 2>"$ERR" ||
    fail "transition replay produced the wrong state"
pass "valid transition cycle is replayed correctly"

export TASKLOG_NOW='2025-01-02T00:00:00Z'
expect_output "second add" "2" add --title "Second task" --tag work
expect_output "second task start" "" start 2
expect_output "third add" "3" add --title "Third task" --tag other
expect_output "third task start" "" start 3
expect_output "third task done" "" done 3

run_ok list
ids="$(cut -f1 "$OUT" | paste -sd, -)"
[[ "$ids" == "1,2,3" ]] ||
    fail "list was not sorted by numeric ID"
pass "list is sorted by numeric ID"

expect_output "status filter" \
    $'2\tactive\tSecond task\twork' \
    list --status active
expect_output "tag and status intersection" \
    $'2\tactive\tSecond task\twork' \
    list --tag work --status active
expect_output "empty intersected filter" "" \
    list --status done --tag work
expect_output "summary counts" \
    '{"active":1,"done":1,"open":1,"total":3}' summary

[[ "$(wc -l <"$TASKLOG_DB" | tr -d '[:space:]')" == 9 ]] ||
    fail "successful mutations did not append one line each"
jq -e . "$TASKLOG_DB" >/dev/null 2>"$ERR" ||
    fail "database contains an invalid JSON event"
pass "every successful mutation appends one valid JSON event"

expect_fail_unchanged "open-to-done transition" done 1
expect_fail_unchanged "active-to-start transition" start 2
expect_fail_unchanged "done-to-start transition" start 3
expect_fail_unchanged "unknown task transition" start 999
expect_fail_unchanged "leading-zero ID" show 01
expect_fail_unchanged "nonnumeric ID" reopen nope
expect_fail_unchanged "empty title" add --title ""
expect_fail_unchanged "empty tag" add --title x --tag ""
expect_fail_unchanged "invalid status filter" list --status waiting
expect_fail_unchanged "unknown task lookup" show 999

NO_NEWLINE="$SANDBOX/no-newline.jsonl"
printf '%s' \
    '{"at":"t1","id":1,"tags":[],"title":"one","type":"add"}' \
    >"$NO_NEWLINE"
if ! TASKLOG_DB="$NO_NEWLINE" TASKLOG_NOW=t2 \
    bash "$TASKLOG" add --title two >"$OUT" 2>"$ERR"; then
    fail "append after an unterminated JSON line failed"
fi
[[ "$(cat "$OUT")" == 2 ]] ||
    fail "wrong ID after unterminated final line"
[[ "$(wc -l <"$NO_NEWLINE" | tr -d '[:space:]')" == 2 ]] ||
    fail "unterminated final line was not separated before append"
TASKLOG_DB="$NO_NEWLINE" bash "$TASKLOG" validate >"$OUT" 2>"$ERR" ||
    fail "log with repaired line separator did not validate"
pass "valid final line without newline is safely extended"

check_corruption() {
    local description="$1" content="$2"
    local corrupt="$SANDBOX/corrupt-$COUNT.jsonl"

    printf '%s' "$content" >"$corrupt"
    cp -- "$corrupt" "$SNAPSHOT" ||
        fail "could not snapshot corrupt database"
    : >"$OUT"
    : >"$ERR"

    if TASKLOG_DB="$corrupt" bash "$TASKLOG" validate >"$OUT" 2>"$ERR"; then
        fail "$description was accepted"
    fi
    [[ -s "$ERR" ]] ||
        fail "$description produced no validation diagnostic"
    cmp -s -- "$SNAPSHOT" "$corrupt" ||
        fail "validation modified $description"

    if TASKLOG_DB="$corrupt" bash "$TASKLOG" add --title x >"$OUT" 2>"$ERR"; then
        fail "mutation accepted $description"
    fi
    cmp -s -- "$SNAPSHOT" "$corrupt" ||
        fail "failed mutation modified $description"
    pass "$description is rejected without mutation"
}

check_corruption "malformed JSON" $'{"type":"add"\n'
check_corruption "duplicate creation IDs" \
    $'{"at":"t","id":1,"tags":[],"title":"a","type":"add"}\n{"at":"t","id":1,"tags":[],"title":"b","type":"add"}\n'
check_corruption "nonmonotonic creation IDs" \
    $'{"at":"t","id":2,"tags":[],"title":"a","type":"add"}\n{"at":"t","id":1,"tags":[],"title":"b","type":"add"}\n'
check_corruption "invalid event transition" \
    $'{"at":"t","id":1,"tags":[],"title":"a","type":"add"}\n{"at":"t","id":1,"type":"done"}\n'
check_corruption "unknown transition target" \
    $'{"at":"t","id":7,"type":"start"}\n'
check_corruption "empty historical title" \
    $'{"at":"t","id":1,"tags":[],"title":"","type":"add"}\n'
check_corruption "empty historical tag" \
    $'{"at":"t","id":1,"tags":[""],"title":"a","type":"add"}\n'
check_corruption "event with extra fields" \
    $'{"at":"t","extra":true,"id":1,"tags":[],"title":"a","type":"add"}\n'

check_corruption "multiple JSON values on one line" \
    $'{"at":"t","id":1,"tags":[],"title":"a","type":"add"} {"at":"t","id":2,"tags":[],"title":"b","type":"add"}\n'
check_corruption "blank JSON line" $'\n'

DEFAULT_DIR="$SANDBOX/default"
mkdir "$DEFAULT_DIR"
if ! (
    cd "$DEFAULT_DIR" || exit 1
    unset TASKLOG_DB
    TASKLOG_NOW='2030-04-05T06:07:08Z' \
        bash "$TASKLOG" add --title default >"$OUT" 2>"$ERR"
); then
    fail "default database operation failed"
fi
[[ "$(cat "$OUT")" == 1 ]] ||
    fail "default database allocated the wrong ID"
[[ -f "$DEFAULT_DIR/tasklog.jsonl" ]] ||
    fail "default database was not created in the current directory"
pass "TASKLOG_DB defaults to ./tasklog.jsonl"

ABSENT="$SANDBOX/absent.jsonl"
rm -f "$ABSENT"
if TASKLOG_DB="$ABSENT" bash "$TASKLOG" add --title "" >"$OUT" 2>"$ERR"; then
    fail "invalid add against absent database succeeded"
fi
[[ ! -e "$ABSENT" ]] ||
    fail "failed command created an absent database"
pass "failed operation preserves an absent database"

printf '1..%d\n' "$COUNT"
