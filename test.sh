#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd -P)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/harness-in-a-shell.XXXXXX")"
TMP_ROOT="$(cd "$TMP_ROOT" && pwd -P)"
BASH_UNDER_TEST="${BASH_UNDER_TEST:-/bin/bash}"
BASH_DIR="$(cd "$(dirname "$BASH_UNDER_TEST")" && pwd -P)"

cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_count() {
    local expected="$1"
    local pattern="$2"
    local file="$3"
    local actual

    actual="$(grep -c -- "$pattern" "$file" || true)"
    [[ "$actual" == "$expected" ]] ||
        fail "expected $expected matches for '$pattern' in $file; got $actual"
}

mkdir "$TMP_ROOT/bin"
cp "$PROJECT_ROOT/ReAct.sh" "$TMP_ROOT/ReAct.sh"

cat > "$TMP_ROOT/bin/curl" <<'CURL_STUB'
#!/usr/bin/env bash
cat >/dev/null
printf '{}\n'
CURL_STUB

cat > "$TMP_ROOT/bin/jq" <<'JQ_STUB'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1-}" == "-n" ]]; then
    printf '{}\n'
    exit
fi

cat >/dev/null

step=0
if [[ -f "$STUB_STATE" ]]; then
    read -r step < "$STUB_STATE"
fi

case "$step" in
    0)
        cat <<'STEP_ONE'
# STUB_STEP: 1
tool() { TOOL_STATE=v1; printf '%s\n' v1; }
observe tool
printf '# TOOL_STATE: %s\n' "$TOOL_STATE"
reason
STEP_ONE
        ;;
    1)
        cat <<'STEP_TWO'
# STUB_STEP: 2
tool() { TOOL_STATE=v2; printf '%s\n' v2; return 7; }
observe tool
printf '# TOOL_STATE: %s\n' "$TOOL_STATE"

printf '# BEFORE_PID: %s\n' "$$"
compact <<'FIRST_IMAGE'
#!/usr/bin/env bash

# <SYSTEM>
# This is the first self-contained context-switch test image.
# </SYSTEM>

ROOT="$(cd "$(dirname "$0")" && pwd -P)" || exit 1
SELF="$ROOT/$(basename "$0")"
CANONICAL="$ROOT/ReAct.sh"

observe() { "$@"; }
compact() {
    local __react_next

    __react_next="$(mktemp "$ROOT/.react.image.XXXXXX")" || return
    cat > "$__react_next" || return
    exec bash "$__react_next" >> "$__react_next"
}

reason() {
    cat <<'FIRST_CONTINUATION'
printf '# FIRST_SWITCH_PID: %s\n' "$$"
printf '# FIRST_SWITCH_SELF: %s\n' "$SELF"
compact <<'SECOND_IMAGE'
#!/usr/bin/env bash

# <SYSTEM>
# This is the second self-contained context-switch test image.
# </SYSTEM>

ROOT="$(cd "$(dirname "$0")" && pwd -P)" || exit 1
SELF="$ROOT/$(basename "$0")"
CANONICAL="$ROOT/ReAct.sh"

observe() { "$@"; }
compact() {
    local __react_next

    __react_next="$(mktemp "$ROOT/.react.image.XXXXXX")" || return
    cat > "$__react_next" || return
    exec bash "$__react_next" >> "$__react_next"
}

reason() {
    printf '# SECOND_SWITCH_PID: %s\n' "$$"
    printf '# SECOND_SWITCH_SELF: %s\n' "$SELF"
    printf ': "second image resumed"\n'
}

# INPUT: [compressed twice] exercise append semantics
# MEMORY: first compacted trajectory compressed again
reason

# <TAPE>
SECOND_IMAGE
FIRST_CONTINUATION
}

# INPUT: [compressed once] exercise append semantics
# MEMORY: original trajectory compressed by the stub
reason

# <TAPE>
FIRST_IMAGE
STEP_TWO
        ;;
    *)
        printf ': "stub complete"\n'
        ;;
esac

printf '%s\n' "$((step + 1))" > "$STUB_STATE"
JQ_STUB

chmod +x "$TMP_ROOT/bin/curl" "$TMP_ROOT/bin/jq"

"$BASH_UNDER_TEST" -n "$TMP_ROOT/ReAct.sh"

PATH="$TMP_ROOT/bin:$BASH_DIR:/usr/bin:/bin" \
OPENAI_API_KEY=stub \
STUB_STATE="$TMP_ROOT/stub-state" \
    "$BASH_UNDER_TEST" "$TMP_ROOT/ReAct.sh" "exercise append semantics" \
    >> "$TMP_ROOT/ReAct.sh"

image_count="$(find "$TMP_ROOT" -maxdepth 1 -type f -name '.react.image.*' | wc -l | tr -d ' ')"
[[ "$image_count" == 2 ]] || fail "expected two context-switch images; got $image_count"

FIRST_IMAGE="$(grep -l '^# FIRST_SWITCH_PID: ' "$TMP_ROOT"/.react.image.* || true)"
SECOND_IMAGE="$(grep -l '^# SECOND_SWITCH_PID: ' "$TMP_ROOT"/.react.image.* || true)"
[[ -n "$FIRST_IMAGE" ]] || fail "first context-switch image was not identified"
[[ -n "$SECOND_IMAGE" ]] || fail "second context-switch image was not identified"
[[ "$FIRST_IMAGE" != "$SECOND_IMAGE" ]] || fail "both compactions reused the same image"
[[ "$FIRST_IMAGE" != "$TMP_ROOT/ReAct.sh" && "$SECOND_IMAGE" != "$TMP_ROOT/ReAct.sh" ]] ||
    fail "compaction reused the currently running image"

"$BASH_UNDER_TEST" -n "$TMP_ROOT/ReAct.sh"
"$BASH_UNDER_TEST" -n "$FIRST_IMAGE"
"$BASH_UNDER_TEST" -n "$SECOND_IMAGE"

assert_count 1 '^# INPUT: exercise append semantics$' "$TMP_ROOT/ReAct.sh"
assert_count 1 '^# STUB_STEP: 1$' "$TMP_ROOT/ReAct.sh"
assert_count 1 '^# STUB_STEP: 2$' "$TMP_ROOT/ReAct.sh"
assert_count 1 '^# OBS: v1$' "$TMP_ROOT/ReAct.sh"
assert_count 1 '^# OBS: v2$' "$TMP_ROOT/ReAct.sh"
assert_count 1 '^# TOOL_STATE: v1$' "$TMP_ROOT/ReAct.sh"
assert_count 1 '^# TOOL_STATE: v2$' "$TMP_ROOT/ReAct.sh"
assert_count 1 '^# EXIT: 0$' "$TMP_ROOT/ReAct.sh"
assert_count 1 '^# EXIT: 7$' "$TMP_ROOT/ReAct.sh"
assert_count 1 '^# BEFORE_PID: ' "$TMP_ROOT/ReAct.sh"
assert_count 0 '^# FIRST_SWITCH_PID: ' "$TMP_ROOT/ReAct.sh"
assert_count 0 '^# SECOND_SWITCH_PID: ' "$TMP_ROOT/ReAct.sh"
assert_count 1 '^# FIRST_SWITCH_PID: ' "$FIRST_IMAGE"
assert_count 1 '^# FIRST_SWITCH_SELF: ' "$FIRST_IMAGE"
assert_count 0 '^# SECOND_SWITCH_PID: ' "$FIRST_IMAGE"
assert_count 1 '^# INPUT: \[compressed once\] exercise append semantics$' "$FIRST_IMAGE"
grep -q '^# <TAPE>$' "$FIRST_IMAGE" || fail "first image has no tape boundary"
assert_count 1 '^# SECOND_SWITCH_PID: ' "$SECOND_IMAGE"
assert_count 1 '^# SECOND_SWITCH_SELF: ' "$SECOND_IMAGE"
assert_count 1 '^# INPUT: \[compressed twice\] exercise append semantics$' "$SECOND_IMAGE"
assert_count 1 '^# <TAPE>$' "$SECOND_IMAGE"
assert_count 1 '^: "second image resumed"$' "$SECOND_IMAGE"

before_pid="$(sed -n 's/^# BEFORE_PID: //p' "$TMP_ROOT/ReAct.sh")"
first_pid="$(sed -n 's/^# FIRST_SWITCH_PID: //p' "$FIRST_IMAGE")"
second_pid="$(sed -n 's/^# SECOND_SWITCH_PID: //p' "$SECOND_IMAGE")"
[[ "$before_pid" == "$first_pid" && "$first_pid" == "$second_pid" ]] ||
    fail "exec changed PID: before=$before_pid first=$first_pid second=$second_pid"

first_self="$(sed -n 's/^# FIRST_SWITCH_SELF: //p' "$FIRST_IMAGE")"
second_self="$(sed -n 's/^# SECOND_SWITCH_SELF: //p' "$SECOND_IMAGE")"
[[ "$first_self" == "$FIRST_IMAGE" ]] ||
    fail "first image saw SELF as $first_self, expected $FIRST_IMAGE"
[[ "$second_self" == "$SECOND_IMAGE" ]] ||
    fail "second image saw SELF as $second_self, expected $SECOND_IMAGE"

printf 'ok: append execution, function evolution, observations, and repeated compaction\n'
