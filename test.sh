#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd -P)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/harness-in-a-shell.XXXXXX")"
TMP_ROOT="$(cd "$TMP_ROOT" && pwd -P)"
BASH_UNDER_TEST="${BASH_UNDER_TEST:-/bin/bash}"
BASH_DIR="$(cd "$(dirname "$BASH_UNDER_TEST")" && pwd -P)"
PYTHON_UNDER_TEST="${PYTHON_UNDER_TEST:-python3}"

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

assert_structural_image() {
    local file="$1"
    local system_open system_close tape

    assert_count 1 '^# <SYSTEM>$' "$file"
    assert_count 1 '^# </SYSTEM>$' "$file"
    assert_count 1 '^# <TAPE>$' "$file"

    system_open="$(grep -n '^# <SYSTEM>$' "$file" | cut -d: -f1)"
    system_close="$(grep -n '^# </SYSTEM>$' "$file" | cut -d: -f1)"
    tape="$(grep -n '^# <TAPE>$' "$file" | cut -d: -f1)"
    ((system_open < system_close && system_close < tape)) ||
        fail "structural markers are out of order in $file"
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

if [[ "${STUB_SCENARIO:-edit}" == "finish" ]]; then
    cat <<'FINISH_STEP'
edit_context <<'FINAL_ACTIVE_CONTEXT'
#!/usr/bin/env bash

# <SYSTEM>
# CANONICAL_TEST: clean
ROOT="$(cd "$(dirname "$0")" && pwd -P)" || exit 1
SELF="$ROOT/$(basename "$0")"
CANONICAL="$ROOT/ReAct.sh"
if [[ "$SELF" != "$CANONICAL" && -e "$CANONICAL" ]]; then
    __react_round="$(mktemp "$ROOT/.react.round.XXXXXX")" || exit 1
    mv -f "$CANONICAL" "$__react_round" || exit 1
    unset __react_round
fi
observe() { "$@"; }
# </SYSTEM>

edit_context() {
    local __react_next

    __react_next="$(mktemp "$ROOT/.react.image.XXXXXX")" || return
    cat > "$__react_next" || return
    exec bash "$__react_next" >> "$__react_next"
}

finish() {
    local __react_final

    grep -q '^# <TAPE>$' "$SELF" || return
    __react_final="$(mktemp "$ROOT/.react.final.XXXXXX")" || return
    sed -n '1,/^# <TAPE>$/p' "$SELF" > "$__react_final" || return
    bash -n "$__react_final" || return
    chmod +x "$__react_final" || return
    mv -f "$__react_final" "$CANONICAL" || return
    trap - EXIT
    builtin exit 0
}

reason() { :; }

if (($#)); then
    printf '%s\n' "$1" | sed 's/^/# INPUT: /'
fi

reason

# <TAPE>
trap 'printf "# EXIT_TRAP_RAN\n"' EXIT
finish
printf '# AFTER_FINISH: reached\n'
FINAL_ACTIVE_CONTEXT
FINISH_STEP
    exit
fi

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
edit_context <<'FIRST_IMAGE'
#!/usr/bin/env bash

# <SYSTEM>
# This is the first self-contained context-edit test image.
ROOT="$(cd "$(dirname "$0")" && pwd -P)" || exit 1
SELF="$ROOT/$(basename "$0")"
CANONICAL="$ROOT/ReAct.sh"
if [[ "$SELF" != "$CANONICAL" && -e "$CANONICAL" ]]; then
    __react_round="$(mktemp "$ROOT/.react.round.XXXXXX")" || exit 1
    mv -f "$CANONICAL" "$__react_round" || exit 1
    unset __react_round
fi
observe() { "$@"; }
# </SYSTEM>

# Replace this complete script from a quoted heredoc using a unique sibling.
edit_context() {
    local __react_next

    __react_next="$(mktemp "$ROOT/.react.image.XXXXXX")" || return
    cat > "$__react_next" || return
    exec bash "$__react_next" >> "$__react_next"
}

reason() {
    cat <<'FIRST_CONTINUATION'
printf '# FIRST_SWITCH_PID: %s\n' "$$"
printf '# FIRST_SWITCH_SELF: %s\n' "$SELF"
edit_context <<'SECOND_IMAGE'
#!/usr/bin/env bash

# <SYSTEM>
# This is the second self-contained context-edit test image.
ROOT="$(cd "$(dirname "$0")" && pwd -P)" || exit 1
SELF="$ROOT/$(basename "$0")"
CANONICAL="$ROOT/ReAct.sh"
if [[ "$SELF" != "$CANONICAL" && -e "$CANONICAL" ]]; then
    __react_round="$(mktemp "$ROOT/.react.round.XXXXXX")" || exit 1
    mv -f "$CANONICAL" "$__react_round" || exit 1
    unset __react_round
fi
observe() { "$@"; }
# </SYSTEM>

# Replace this complete script from a quoted heredoc using a unique sibling.
edit_context() {
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
# MEMORY: first edited trajectory compressed again
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
assert_structural_image "$TMP_ROOT/ReAct.sh"

PATH="$TMP_ROOT/bin:$BASH_DIR:/usr/bin:/bin" \
OPENAI_API_KEY=stub \
STUB_STATE="$TMP_ROOT/stub-state" \
    "$BASH_UNDER_TEST" "$TMP_ROOT/ReAct.sh" "exercise append semantics" \
    >> "$TMP_ROOT/ReAct.sh"

image_count="$(find "$TMP_ROOT" -maxdepth 1 -type f -name '.react.image.*' | wc -l | tr -d ' ')"
[[ "$image_count" == 2 ]] || fail "expected two edited context images; got $image_count"

round_count="$(find "$TMP_ROOT" -maxdepth 1 -type f -name '.react.round.*' | wc -l | tr -d ' ')"
[[ "$round_count" == 1 ]] || fail "expected one de-canonicalized round; got $round_count"
ROUND_IMAGE="$(find "$TMP_ROOT" -maxdepth 1 -type f -name '.react.round.*')"
[[ ! -e "$TMP_ROOT/ReAct.sh" ]] || fail "canonical path still exists during an active round"

FIRST_IMAGE="$(grep -l '^# FIRST_SWITCH_PID: ' "$TMP_ROOT"/.react.image.* || true)"
SECOND_IMAGE="$(grep -l '^# SECOND_SWITCH_PID: ' "$TMP_ROOT"/.react.image.* || true)"
[[ -n "$FIRST_IMAGE" ]] || fail "first edited context image was not identified"
[[ -n "$SECOND_IMAGE" ]] || fail "second edited context image was not identified"
[[ "$FIRST_IMAGE" != "$SECOND_IMAGE" ]] || fail "both context edits reused the same image"
[[ "$FIRST_IMAGE" != "$TMP_ROOT/ReAct.sh" && "$SECOND_IMAGE" != "$TMP_ROOT/ReAct.sh" ]] ||
    fail "context edit reused the currently running image"

"$BASH_UNDER_TEST" -n "$ROUND_IMAGE"
"$BASH_UNDER_TEST" -n "$FIRST_IMAGE"
"$BASH_UNDER_TEST" -n "$SECOND_IMAGE"

assert_count 1 '^# INPUT: exercise append semantics$' "$ROUND_IMAGE"
assert_count 1 '^# STUB_STEP: 1$' "$ROUND_IMAGE"
assert_count 1 '^# STUB_STEP: 2$' "$ROUND_IMAGE"
assert_count 1 '^# OBS: v1$' "$ROUND_IMAGE"
assert_count 1 '^# OBS: v2$' "$ROUND_IMAGE"
assert_count 1 '^# TOOL_STATE: v1$' "$ROUND_IMAGE"
assert_count 1 '^# TOOL_STATE: v2$' "$ROUND_IMAGE"
assert_count 1 '^# EXIT: 0$' "$ROUND_IMAGE"
assert_count 1 '^# EXIT: 7$' "$ROUND_IMAGE"
assert_count 1 '^# BEFORE_PID: ' "$ROUND_IMAGE"
assert_count 0 '^# FIRST_SWITCH_PID: ' "$ROUND_IMAGE"
assert_count 0 '^# SECOND_SWITCH_PID: ' "$ROUND_IMAGE"
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

before_pid="$(sed -n 's/^# BEFORE_PID: //p' "$ROUND_IMAGE")"
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

FINISH_ROOT="$TMP_ROOT/finish-case"
RUNNING_IMAGE="$FINISH_ROOT/running-image.sh"
mkdir "$FINISH_ROOT"
cp "$PROJECT_ROOT/ReAct.sh" "$FINISH_ROOT/ReAct.sh"
ln "$FINISH_ROOT/ReAct.sh" "$RUNNING_IMAGE"

PATH="$TMP_ROOT/bin:$BASH_DIR:/usr/bin:/bin" \
OPENAI_API_KEY=stub \
STUB_SCENARIO=finish \
    "$BASH_UNDER_TEST" "$FINISH_ROOT/ReAct.sh" "exercise finish semantics" \
    >> "$FINISH_ROOT/ReAct.sh"

"$BASH_UNDER_TEST" -n "$RUNNING_IMAGE"
"$BASH_UNDER_TEST" -n "$FINISH_ROOT/ReAct.sh"
[[ -x "$FINISH_ROOT/ReAct.sh" ]] || fail "canonical image is not executable"
cmp -s "$RUNNING_IMAGE" "$FINISH_ROOT/ReAct.sh" &&
    fail "finish did not replace the canonical image"

assert_count 1 '^# INPUT: exercise finish semantics$' "$RUNNING_IMAGE"
assert_count 1 "^edit_context <<'FINAL_ACTIVE_CONTEXT'$" "$RUNNING_IMAGE"

finish_round_count="$(find "$FINISH_ROOT" -maxdepth 1 -type f -name '.react.round.*' | wc -l | tr -d ' ')"
[[ "$finish_round_count" == 1 ]] ||
    fail "expected one archived finish round; got $finish_round_count"
FINISH_ROUND_IMAGE="$(find "$FINISH_ROOT" -maxdepth 1 -type f -name '.react.round.*')"
cmp -s "$RUNNING_IMAGE" "$FINISH_ROUND_IMAGE" ||
    fail "de-canonicalized round does not preserve the task-bearing ReAct.sh"

finish_image_count="$(find "$FINISH_ROOT" -maxdepth 1 -type f -name '.react.image.*' | wc -l | tr -d ' ')"
[[ "$finish_image_count" == 1 ]] ||
    fail "expected one final active context; got $finish_image_count"
FINAL_ACTIVE_IMAGE="$(find "$FINISH_ROOT" -maxdepth 1 -type f -name '.react.image.*')"
"$BASH_UNDER_TEST" -n "$FINAL_ACTIVE_IMAGE"
assert_count 1 '^finish$' "$FINAL_ACTIVE_IMAGE"
assert_count 0 '^# EXIT_TRAP_RAN$' "$FINAL_ACTIVE_IMAGE"
assert_count 0 '^# AFTER_FINISH: reached$' "$FINAL_ACTIVE_IMAGE"

assert_count 1 '^# CANONICAL_TEST: clean$' "$FINISH_ROOT/ReAct.sh"
assert_count 0 '^# INPUT:' "$FINISH_ROOT/ReAct.sh"
assert_count 0 '^# OBS:' "$FINISH_ROOT/ReAct.sh"
assert_count 1 '^# <TAPE>$' "$FINISH_ROOT/ReAct.sh"
assert_structural_image "$FINISH_ROOT/ReAct.sh"
[[ "$(tail -n 1 "$FINISH_ROOT/ReAct.sh")" == '# <TAPE>' ]] ||
    fail "canonical image does not end at its tape boundary"

EXPECTED_CANONICAL="$FINISH_ROOT/expected-canonical.sh"
sed -n '1,/^# <TAPE>$/p' "$FINAL_ACTIVE_IMAGE" > "$EXPECTED_CANONICAL"
cmp -s "$EXPECTED_CANONICAL" "$FINISH_ROOT/ReAct.sh" ||
    fail "canonical ReAct.sh is not the reusable prefix of the final active context"

final_staging_count="$(find "$FINISH_ROOT" -maxdepth 1 -name '.react.final.*' | wc -l | tr -d ' ')"
[[ "$final_staging_count" == 0 ]] ||
    fail "finish left $final_staging_count staging files after installation"

"$BASH_UNDER_TEST" -n "$PROJECT_ROOT/act.sh"
assert_structural_image "$PROJECT_ROOT/act.sh"
"$PYTHON_UNDER_TEST" - "$PROJECT_ROOT/reason.py" <<'PYTHON_SYNTAX'
import sys
from pathlib import Path

path = Path(sys.argv[1])
compile(path.read_bytes(), str(path), "exec")
PYTHON_SYNTAX

REASON_STUB_ROOT="$TMP_ROOT/reason-stub"
mkdir -p "$REASON_STUB_ROOT/openai"
cat > "$REASON_STUB_ROOT/openai/__init__.py" <<'OPENAI_STUB'
import json
import os
from pathlib import Path
from types import SimpleNamespace


class Responses:
    def create(self, **request):
        Path(os.environ["REASON_CAPTURE"]).write_text(
            json.dumps(request),
            encoding="utf-8",
        )
        return SimpleNamespace(output_text=': "reason.py SDK stub"')


class OpenAI:
    def __init__(self):
        self.responses = Responses()
OPENAI_STUB

REASON_CAPTURE="$TMP_ROOT/reason-request.json"
REASON_OUTPUT="$TMP_ROOT/reason-output.sh"
PYTHONPATH="$REASON_STUB_ROOT" \
REASON_CAPTURE="$REASON_CAPTURE" \
    "$PYTHON_UNDER_TEST" "$PROJECT_ROOT/reason.py" "$PROJECT_ROOT/act.sh" \
    > "$REASON_OUTPUT"

[[ "$(cat "$REASON_OUTPUT")" == ': "reason.py SDK stub"' ]] ||
    fail "reason.py did not emit the SDK response as shell source"
"$PYTHON_UNDER_TEST" - "$REASON_CAPTURE" "$PROJECT_ROOT/act.sh" <<'REQUEST_ASSERTIONS'
import json
import sys
from pathlib import Path

request = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
source = Path(sys.argv[2]).read_text(encoding="utf-8")
assert request["model"] == "gpt-5"
assert request["input"] == source
assert "You are an autonomous agent" in request["instructions"]
assert 'ROOT="$(cd "$(dirname "$0")" && pwd -P)" || exit 1' in request["instructions"]
assert "# <SYSTEM>" not in request["instructions"].splitlines()
assert "# </SYSTEM>" not in request["instructions"].splitlines()
REQUEST_ASSERTIONS

ACT_ROOT="$TMP_ROOT/act-case"
ACT_BIN="$ACT_ROOT/bin"
mkdir -p "$ACT_BIN"
cp "$PROJECT_ROOT/act.sh" "$PROJECT_ROOT/reason.py" "$ACT_ROOT/"
cat > "$ACT_BIN/python3" <<'PYTHON_STUB'
#!/usr/bin/env bash
set -euo pipefail

[[ "$#" == 2 && "$1" == */reason.py && "$2" == */act.sh ]]
step=0
if [[ -f "$ACT_STUB_STATE" ]]; then
    read -r step < "$ACT_STUB_STATE"
fi

case "$step" in
    0)
        cat <<'FIRST_STEP'
# ACT_STUB_STEP: 1
act_tool() { printf '%s\n' "python split tool"; return 9; }
observe act_tool
reason
FIRST_STEP
        ;;
    1)
        cat <<'SECOND_STEP'
# ACT_STUB_STEP: 2
: "python split complete"
SECOND_STEP
        ;;
    *)
        exit 1
        ;;
esac

printf '%s\n' "$((step + 1))" > "$ACT_STUB_STATE"
PYTHON_STUB
chmod +x "$ACT_BIN/python3"

PATH="$ACT_BIN:$BASH_DIR:/usr/bin:/bin" \
ACT_STUB_STATE="$ACT_ROOT/stub-state" \
    "$BASH_UNDER_TEST" "$ACT_ROOT/act.sh" "exercise Python split" \
    >> "$ACT_ROOT/act.sh"

"$BASH_UNDER_TEST" -n "$ACT_ROOT/act.sh"
assert_structural_image "$ACT_ROOT/act.sh"
assert_count 1 '^# INPUT: exercise Python split$' "$ACT_ROOT/act.sh"
assert_count 1 '^# ACT_STUB_STEP: 1$' "$ACT_ROOT/act.sh"
assert_count 1 '^# ACT_STUB_STEP: 2$' "$ACT_ROOT/act.sh"
assert_count 1 '^# OBS: python split tool$' "$ACT_ROOT/act.sh"
assert_count 1 '^# EXIT: 9$' "$ACT_ROOT/act.sh"

printf 'ok: Bash and Python reasoners, append execution, tool evolution, context editing, round lifecycle, and finish\n'
