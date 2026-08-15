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

NEXT="$ROOT/.react.next.sh"
cat > "$NEXT" <<'NEXT_IMAGE'
#!/usr/bin/env bash

# <SYSTEM>
# This is a self-contained context-switch test image.
# </SYSTEM>

ROOT="$(cd "$(dirname "$0")" && pwd -P)" || exit 1
SELF="$ROOT/$(basename "$0")"
CANONICAL="$ROOT/ReAct.sh"

observe() { "$@"; }
reason() {
    printf '# SWITCH_PID: %s\n' "$$"
    printf '# SWITCH_SELF: %s\n' "$SELF"
    printf ': "new image resumed"\n'
}

# INPUT: [compressed] exercise append semantics
# MEMORY: old trajectory compressed by the stub
reason

# <TAPE>
NEXT_IMAGE

printf '# BEFORE_PID: %s\n' "$$"
exec bash "$NEXT" >> "$NEXT"
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

NEXT_IMAGE="$TMP_ROOT/.react.next.sh"
[[ -f "$NEXT_IMAGE" ]] || fail "context-switch image was not created"

"$BASH_UNDER_TEST" -n "$TMP_ROOT/ReAct.sh"
"$BASH_UNDER_TEST" -n "$NEXT_IMAGE"

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
assert_count 0 '^# SWITCH_PID: ' "$TMP_ROOT/ReAct.sh"
assert_count 1 '^# SWITCH_PID: ' "$NEXT_IMAGE"
assert_count 1 '^# SWITCH_SELF: ' "$NEXT_IMAGE"
assert_count 1 '^# INPUT: \[compressed\] exercise append semantics$' "$NEXT_IMAGE"
assert_count 1 '^# <TAPE>$' "$NEXT_IMAGE"
assert_count 1 '^: "new image resumed"$' "$NEXT_IMAGE"

before_pid="$(sed -n 's/^# BEFORE_PID: //p' "$TMP_ROOT/ReAct.sh")"
after_pid="$(sed -n 's/^# SWITCH_PID: //p' "$NEXT_IMAGE")"
[[ "$before_pid" == "$after_pid" ]] ||
    fail "exec changed PID: before=$before_pid after=$after_pid"

switch_self="$(sed -n 's/^# SWITCH_SELF: //p' "$NEXT_IMAGE")"
[[ "$switch_self" == "$NEXT_IMAGE" ]] ||
    fail "new image saw SELF as $switch_self, expected $NEXT_IMAGE"

printf 'ok: append execution, function evolution, observations, and exec switch\n'
