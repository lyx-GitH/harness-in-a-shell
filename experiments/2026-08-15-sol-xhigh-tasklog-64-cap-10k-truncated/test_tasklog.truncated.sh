#!/usr/bin/env bash

set -o nounset
set -o pipefail

ROOT=$(cd "$(dirname "$0")" && pwd -P) || exit 1
TASKLOG="$ROOT/tasklog.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/tasklog-tests.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT
export TASKLOG_NOW='2025-01-02T03:04:05Z'
export TASKLOG_DB="$TMP/tasklog.jsonl"

tests=0

fail() {
    printf 'not ok %d - %s\n' "$((tests + 1))" "$*" >&2
    exit 1
}

ok() {
    ((tests += 1))
    printf 'ok %d - %s\n' "$tests" "$1"
}

assert_eq() {
    local expected=$1 actual=$2 description=$3
    [[ "$actual" == "$expected" ]] ||
        fail "$description (expected [$expected], got [$actual])"
    ok "$description"
}

expect_failure() {
    local description=$1
    shift
    if "$@" >"$TMP/failure.out" 2>"$TMP/failure.err"; then
        fail "$description (command unexpectedly succeeded)"
    fi
    [[ -s "$TMP/failure.err" ]] ||
        fail "$description (no diagnostic on stderr)"
    ok "$description"
}

snapshot_db() {
    cp -- "$TASKLOG_DB" "$TMP/before.jsonl"
}

assert_db_unchanged() {
    local description=$1
    cmp -s -- "$TASKLOG_DB" "$TMP/before.jsonl" ||
        fail "$description (database changed)"
    ok "$description"
}

new_db() {
    local name=$1
    export TASKLOG_DB="$TMP/$name.jsonl"
    rm -f -- "$TASKLOG_DB" "$TASKLOG_DB.lock"
}

# Successful lifecycle and exactly one event per mutation.
new_db lifecycle
assert_eq 1 "$("$TASKLOG" add --title "first task" --tag work)" \
    "add returns first ID"
assert_eq 1 "$(wc -l < "$TASKLOG_DB" | tr -d ' ')" \
    "add appends one line"
assert_eq active "$("$TASKLOG" start 1)" "open task starts"
assert_eq 2 "$(wc -l < "$TASKLOG_DB" | tr -d ' ')" \
    "start appends one line"
assert_eq done "$("$TASKLOG" done 1)" "active task completes"
assert_eq 3 "$(wc -l < "$TASKLOG_DB" | tr -d ' ')" \
    "done appends one line"
assert_eq open "$("$TASKLOG" reopen 1)" "done task reopens"
assert_eq 4 "$(wc -l < "$TASKLOG_DB" | tr -d ' ')" \
    "reopen appends one line"
assert_eq valid "$("$TASKLOG" validate)" "valid lifecycle validates"
assert_eq \
    '{"created_at":"2025-01-02T03:04:05Z","id":1,"status":"open","tags":["work"],"title":"first task","updated_at":"2025-01-02T03:04:05Z"}' \
    "$("$TASKLOG" show 1)" \
    "show emits canonical current-state JSON"

# Quotes, backslashes, spaces, and UTF-8 survive JSON encoding and replay.
new_db escaping
special_title='café "quoted" C:\path with spaces'
special_tag='team "α" \ shared'
"$TASKLOG" add --title "$special_title" --tag "$special_tag" \
    --tag 'plain tag' >/dev/null
assert_eq "$special_title" "$(jq -r '.title' "$TASKLOG_DB")" \
    "title escaping is preserved"
assert_eq "$special_tag" "$(jq -r '.tags[0]' "$TASKLOG_DB")" \
    "tag escaping is preserved"
assert_eq "$special_title" "$("$TASKLOG" show 1 | jq -r '.title')" \
    "escaped title survives replay"

# Invalid input and transitions fail without changing one byte.
new_db failures
"$TASKLOG" add --title one >/dev/null
snapshot_db
expect_failure "done rejects an open task" "$TASKLOG" done 1
assert_db_unchanged "invalid transition leaves database unchanged"
expect_failure "reopen rejects an open task" "$TASKLOG" reopen 1
assert_db_unchanged "second invalid
