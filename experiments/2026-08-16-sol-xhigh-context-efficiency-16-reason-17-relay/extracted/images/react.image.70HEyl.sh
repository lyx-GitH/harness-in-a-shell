#!/usr/bin/env bash

# <SYSTEM>
# You are an autonomous Bash agent. This running script is your program,
# durable toolset, state, execution history, and reasoning context.
#
# OUTPUT AND EXECUTION
#
# Output only valid Bash source, never Markdown fences. Persist prose only as
# Bash comments. Your response is appended verbatim to $SELF; the same process
# then executes it. Bash functions are tools, comments are state, and reason is
# the continuation. Call reason only after all actions and observations for a
# step. If you do not call it, the agent lifetime ends.
#
ROOT="$(cd "$(dirname "$0")" && pwd -P)" || exit 1
SELF="$ROOT/$(basename "$0")"
CANONICAL="$ROOT/ReAct.sh"

# STRUCTURE AND STATE
#
# Exact operative lines "# <SYSTEM>", "# </SYSTEM>", and "# <TAPE>" are
# immutable harness syntax. Every complete image must recreate them in their
# structural roles. Treat other harness-parsed tags likewise.
# "# INPUT:" is user input, "# OBS:" an observation, and "# EXIT:" its status.
# The reusable image is before the first TAPE marker; later source is disposable
# trajectory. Never rewrite, truncate, rename, or replace an active $SELF while
# another reasoning step is possible. Appending through execution is safe.
#
# Run commands through observe when their output and status should enter the
# context. Put pipelines, redirections, and compound syntax in a function and
# observe that function.
observe() {
    local __file __status
    __file="$(mktemp "${TMPDIR:-/tmp}/react-observe.XXXXXX")" || return
    "$@" >"$__file" 2>&1
    __status=$?
    sed 's/^/# OBS: /' "$__file"
    rm -f "$__file"
    printf '# EXIT: %d\n' "$__status"
}

# CONTROL
#
# Each round permits at most 16 reason API attempts. The exported count survives
# context-image execs and is reset only when a fresh canonical round starts.
REACT_REASON_LIMIT=16
: "${OPENAI_MODEL:=gpt-5.6-sol}"
: "${OPENAI_RESPONSES_URL:=https://api.openai.com/v1/responses}"
: "${OPENAI_UNIX_SOCKET:=}"

if [[ "$SELF" == "$CANONICAL" ]]; then
    REACT_REASON_CALLS=0
elif [[ ! "${REACT_REASON_CALLS:-}" =~ ^[0-9]+$ ]]; then
    REACT_REASON_CALLS=0
fi
export REACT_REASON_CALLS

# FILE AS ROUND
#
# ReAct.sh is canonical only between rounds. The first image reached after
# leaving it archives that round's old canonical path; later switches do
# nothing. Only successful finalization installs the next ReAct.sh.
if [[ "$SELF" != "$CANONICAL" && -e "$CANONICAL" ]]; then
    __round="$(mktemp "$ROOT/.react.round.XXXXXX")" || exit 1
    mv -f "$CANONICAL" "$__round" || exit 1
    unset __round
fi

# CORE SEMANTICS
#
# Complete image + edit_context = structural context change.
# Stable prefix + retape = efficient trajectory compression.
# Clean terminal image + finish = durable round completion.
# canonical ReAct.sh = completed round boundary.
# Everything, including reasoning, lives in the shell image.
# </SYSTEM>

# CONTEXT TOOLS
#
# edit_context performs structural changes. Call it directly with a quoted
# heredoc containing a COMPLETE replacement script. The replacement must
# reconstruct the SYSTEM and marker structure, bindings, contracts, API
# machinery, useful tools, current INPUT, and required memory. It receives a
# fresh sibling path; exec preserves exported state but not ordinary functions
# or variables. Syntax is checked before switching.
edit_context() {
    local __next
    __next="$(mktemp "$ROOT/.react.image.XXXXXX")" || return
    cat >"$__next" || { rm -f "$__next"; return 1; }
    bash -n "$__next" || { rm -f "$__next"; return 1; }
    exec bash "$__next" >>"$__next"
}

# retape is the efficient state-only compressor. It copies the reusable prefix
# exactly and reads a replacement TAPE body from a quoted heredoc. That body
# must preserve current INPUT and a concise sufficient summary, perform the
# next action, and normally call reason. Use edit_context instead if the prefix
# itself must change.
retape() {
    local __next
    grep -q '^# <TAPE>$' "$SELF" || return
    __next="$(mktemp "$ROOT/.react.image.XXXXXX")" || return
    sed -n '1,/^# <TAPE>$/p' "$SELF" >"$__next" ||
        { rm -f "$__next"; return 1; }
    cat >>"$__next" || { rm -f "$__next"; return 1; }
    bash -n "$__next" || { rm -f "$__next"; return 1; }
    exec bash "$__next" >>"$__next"
}

# FINALIZATION
#
# finish may run only in a clean terminal replacement. It copies through the
# first TAPE marker, validates and stages that reusable prefix, atomically
# installs it as ReAct.sh, clears EXIT traps, and exits. On failure it leaves
# any installed canonical image untouched.
finish() {
    local __final
    grep -q '^# <TAPE>$' "$SELF" || return
    __final="$(mktemp "$ROOT/.react.final.XXXXXX")" || return
    sed -n '1,/^# <TAPE>$/p' "$SELF" >"$__final" ||
        { rm -f "$__final"; return 1; }
    bash -n "$__final" || { rm -f "$__final"; return 1; }
    chmod +x "$__final" || { rm -f "$__final"; return 1; }
    mv -f "$__final" "$CANONICAL" ||
        { rm -f "$__final"; return 1; }
    trap - EXIT
    builtin exit 0
}

# finalize efficiently creates the required clean terminal replacement from
# the current reusable prefix, then execs it. Structural improvements must
# already be in that prefix. Call finalize directly and without arguments.
finalize() {
    local __next
    grep -q '^# <TAPE>$' "$SELF" || return
    __next="$(mktemp "$ROOT/.react.image.XXXXXX")" || return
    sed -n '1,/^# <TAPE>$/p' "$SELF" >"$__next" ||
        { rm -f "$__next"; return 1; }
    printf '%s\n' 'finish' >>"$__next" ||
        { rm -f "$__next"; return 1; }
    bash -n "$__next" || { rm -f "$__next"; return 1; }
    exec bash "$__next" >>"$__next"
}

# reason sends the SYSTEM block as API instructions and the entire current
# image as input. It emits a valid comment recording each consumed attempt.
# Relay-socket and HTTPS modes are supported. An exhausted budget never calls
# the API.
reason() {
    local __system __used
    local -a __curl

    __used=${REACT_REASON_CALLS:-0}
    if ((__used >= REACT_REASON_LIMIT)); then
        printf '# OBS: reason budget exhausted at %d/%d\n' \
            "$__used" "$REACT_REASON_LIMIT"
        printf '# EXIT: 75\n'
        return 75
    fi
    REACT_REASON_CALLS=$((__used + 1))
    export REACT_REASON_CALLS
    printf '# REASON-CALL: %d/%d\n' \
        "$REACT_REASON_CALLS" "$REACT_REASON_LIMIT"

    __system="$(
        sed -n '/^# <SYSTEM>$/,/^# <\/SYSTEM>$/p' "$SELF" |
            sed '1d;$d;s/^# //;s/^#$//'
    )" || return

    __curl=(-fsS -H "Content-Type: application/json" --data-binary @-)
    if [[ -n "$OPENAI_UNIX_SOCKET" ]]; then
        __curl+=(--unix-socket "$OPENAI_UNIX_SOCKET" --noproxy '*')
    else
        __curl+=(-H "Authorization: Bearer $OPENAI_API_KEY")
    fi
    __curl+=("$OPENAI_RESPONSES_URL")

    (
        set -o pipefail
        jq -n \
            --arg model "$OPENAI_MODEL" \
            --arg instructions "$__system" \
            --rawfile input "$SELF" \
            '{model:$model, instructions:$instructions, input:$input}' |
        curl "${__curl[@]}" |
        jq -er '
            [.output[]? |
             select(.type=="message") |
             .content[]? |
             select(.type=="output_text") |
             .text] as $t |
            if ($t|length)==0
            then error("response contained no output_text")
            else $t|join("\n")
            end
        '
    )
}

if (($#)); then
    printf '%s\n' "$@" | sed 's/^/# INPUT: /'
fi

reason

# <TAPE>
# INPUT: imporve this harness to improve context efficiency, at most 16 reason() call is permited due to budget constrain
# STATE: Installed a compact candidate harness. It adds a hard 16-attempt
# round budget preserved across image execs, syntax-checking context switches,
# retape for cheap trajectory compression, and finalize for cheap clean
# terminal replacement. Validate the active candidate, then finalize it.
harness_selftest() {
    local marker
    bash -n "$SELF" || return
    for marker in '<SYSTEM>' '</SYSTEM>' '<TAPE>'; do
        [[ $(grep -Fxc "# $marker" "$SELF") -eq 1 ]] || return 1
    done
    declare -F observe edit_context retape finish finalize reason
    printf 'bytes=%s\n' "$(wc -c <"$SELF")"
    printf 'lines=%s\n' "$(wc -l <"$SELF")"
    printf 'system_bytes=%s\n' \
        "$(sed -n '/^# <SYSTEM>$/,/^# <\/SYSTEM>$/p' "$SELF" | wc -c)"
    printf 'prefix_bytes=%s\n' \
        "$(sed -n '1,/^# <TAPE>$/p' "$SELF" | wc -c)"
    printf 'reason_calls_before_next=%s limit=%s\n' \
        "$REACT_REASON_CALLS" "$REACT_REASON_LIMIT"
    printf 'canonical_present=%s\n' "$([[ -e "$CANONICAL" ]] && echo yes || echo no)"
}
observe harness_selftest
reason
# REASON-CALL: 3/16
edit_context <<'__REACT_IMAGE__'
#!/usr/bin/env bash

# <SYSTEM>
# You are an autonomous Bash agent. This running script is your program,
# durable toolset, state, execution history, and reasoning context.
#
# OUTPUT AND EXECUTION
#
# Output only valid Bash source, never Markdown fences. Persist prose only as
# Bash comments. Your response is appended verbatim to $SELF and then executed.
# Bash functions are tools. Call reason only after all actions and observations
# for a step; omitting reason ends the agent lifetime.
#
ROOT="$(cd "$(dirname "$0")" && pwd -P)" || exit 1
SELF="$ROOT/$(basename "$0")"
CANONICAL="$ROOT/ReAct.sh"

# STRUCTURE AND STATE
#
# The exact operative marker lines for SYSTEM boundaries and TAPE are immutable.
# A complete image must recreate their structural roles. Harness-parsed INPUT,
# OBS, EXIT, and similar tags must also retain their roles. The reusable image
# is everything through the first TAPE marker; later source is disposable
# trajectory. Never rewrite, truncate, rename, or replace an active $SELF while
# another reasoning step is possible. Switch only by creating a sibling image
# and execing it. Appending through execution is safe.
#
# Record command output and status with observe. Wrap pipelines, redirections,
# and compound commands in a function before observing them.
observe() {
    local file status
    file="$(mktemp "${TMPDIR:-/tmp}/react-observe.XXXXXX")" || return
    "$@" >"$file" 2>&1
    status=$?
    sed 's/^/# OBS: /' "$file"
    rm -f "$file"
    printf '# EXIT: %d\n' "$status"
}

# CONTROL
#
# At most 16 reason API attempts are allowed per round. The exported count
# survives sibling-image execs and resets only on fresh canonical entry.
REACT_REASON_LIMIT=16
: "${OPENAI_MODEL:=gpt-5.6-sol}"
: "${OPENAI_RESPONSES_URL:=https://api.openai.com/v1/responses}"
: "${OPENAI_UNIX_SOCKET:=}"

if [[ "$SELF" == "$CANONICAL" ]]; then
    REACT_REASON_CALLS=0
elif [[ ! ${REACT_REASON_CALLS:-} =~ ^[0-9]+$ ]]; then
    REACT_REASON_CALLS=0
fi
export REACT_REASON_CALLS

# FILE AS ROUND
#
# ReAct.sh exists only at completed round boundaries. The first sibling image
# archives the old canonical file; later sibling switches leave it absent.
# Only successful finish installs the next canonical image.
if [[ "$SELF" != "$CANONICAL" && -e "$CANONICAL" ]]; then
    round_archive="$(mktemp "$ROOT/.react.round.XXXXXX")" || exit 1
    mv -f "$CANONICAL" "$round_archive" || exit 1
    unset round_archive
fi

# CORE SEMANTICS
#
# Complete image plus edit_context performs structural change. Stable prefix
# plus retape compresses trajectory. Clean terminal image plus finish completes
# a round. Internal sibling images resume at their TAPE body without an
# automatic reason call; only fresh canonical entry calls reason automatically.
# </SYSTEM>

# CONTEXT TOOLS

# Replace the complete image structurally. The quoted heredoc must reconstruct
# all bindings, contracts, API machinery, markers, current INPUT, and memory.
edit_context() {
    local next
    next="$(mktemp "$ROOT/.react.image.XXXXXX")" || return
    cat >"$next" || { rm -f "$next"; return 1; }
    bash -n "$next" || { rm -f "$next"; return 1; }
    exec bash "$next" >>"$next"
}

# Preserve the reusable prefix exactly and replace only disposable trajectory.
# The quoted heredoc must include current INPUT, concise state, next actions,
# and normally a reason call.
retape() {
    local next
    grep -q '^# <TAPE>$' "$SELF" || return
    next="$(mktemp "$ROOT/.react.image.XXXXXX")" || return
    sed -n '1,/^# <TAPE>$/p' "$SELF" >"$next" ||
        { rm -f "$next"; return 1; }
    cat >>"$next" || { rm -f "$next"; return 1; }
    bash -n "$next" || { rm -f "$next"; return 1; }
    exec bash "$next" >>"$next"
}

# Install the validated reusable prefix. This is legal only in the clean
# terminal image created by finalize.
finish() {
    local final
    [[ ${REACT_TERMINAL:-} == 1 ]] || return 64
    grep -q '^# <TAPE>$' "$SELF" || return
    final="$(mktemp "$ROOT/.react.final.XXXXXX")" || return
    sed -n '1,/^# <TAPE>$/p' "$SELF" >"$final" ||
        { rm -f "$final"; return 1; }
    bash -n "$final" || { rm -f "$final"; return 1; }
    chmod +x "$final" || { rm -f "$final"; return 1; }
    mv -f "$final" "$CANONICAL" ||
        { rm -f "$final"; return 1; }
    trap - EXIT
    builtin exit 0
}

# Create and exec the clean terminal image without consuming another reason
# call. Structural improvements must already be present in the prefix.
finalize() {
    local next
    grep -q '^# <TAPE>$' "$SELF" || return
    next="$(mktemp "$ROOT/.react.image.XXXXXX")" || return
    sed -n '1,/^# <TAPE>$/p' "$SELF" >"$next" ||
        { rm -f "$next"; return 1; }
    printf '%s\n' finish >>"$next" ||
        { rm -f "$next"; return 1; }
    bash -n "$next" || { rm -f "$next"; return 1; }
    export REACT_TERMINAL=1
    exec bash "$next" >>"$next"
}

# Avoid sending the SYSTEM body twice: it is supplied separately as API
# instructions. All non-SYSTEM source and trajectory remain visible.
prompt_image() {
    awk '
        /^# <SYSTEM>$/   { hidden=1; print; next }
        /^# <\/SYSTEM>$/ { hidden=0; print; next }
        !hidden           { print }
    ' "$SELF"
}

# Consume one bounded API attempt and emit its Bash continuation. Relay-socket
# and authenticated HTTPS transports are supported.
reason() {
    local system used
    local -a curl_args

    used=${REACT_REASON_CALLS:-0}
    if ((used >= REACT_REASON_LIMIT)); then
        printf '# OBS: reason budget exhausted at %d/%d\n' \
            "$used" "$REACT_REASON_LIMIT"
        printf '# EXIT: 75\n'
        return 75
    fi

    REACT_REASON_CALLS=$((used + 1))
    export REACT_REASON_CALLS
    printf '# REASON-CALL: %d/%d\n' \
        "$REACT_REASON_CALLS" "$REACT_REASON_LIMIT"

    system="$(
        sed -n '/^# <SYSTEM>$/,/^# <\/SYSTEM>$/p' "$SELF" |
            sed '1d;$d;s/^# //;s/^#$//'
    )" || return

    curl_args=(-fsS -H 'Content-Type: application/json' --data-binary @-)
    if [[ -n "$OPENAI_UNIX_SOCKET" ]]; then
        curl_args+=(--unix-socket "$OPENAI_UNIX_SOCKET" --noproxy '*')
    else
        curl_args+=(-H "Authorization: Bearer $OPENAI_API_KEY")
    fi
    curl_args+=("$OPENAI_RESPONSES_URL")

    (
        set -o pipefail
        jq -n \
            --arg model "$OPENAI_MODEL" \
            --arg instructions "$system" \
            --rawfile input <(prompt_image) \
            '{model:$model, instructions:$instructions, input:$input}' |
        curl "${curl_args[@]}" |
        jq -er '
            [.output[]? |
             select(.type == "message") |
             .content[]? |
             select(.type == "output_text") |
             .text] as $texts |
            if ($texts | length) == 0
            then error("response contained no output_text")
            else $texts | join("\n")
            end
        '
    )
}

# Fresh canonical entry starts reasoning. Sibling images instead execute their
# prepared TAPE body, avoiding an otherwise wasted API call on every switch.
if [[ "$SELF" == "$CANONICAL" ]]; then
    if (($#)); then
        printf '%s\n' "$@" | sed 's/^/# INPUT: /'
    fi
    reason
fi

# <TAPE>
# INPUT: imporve this harness to improve context efficiency, at most 16 reason() call is permited due to budget constrain
# STATE: Reworked the candidate to avoid automatic reason calls after
# edit_context, retape, and finalize. The API now receives the SYSTEM body once
# rather than duplicating it in both instructions and input. The hard exported
# 16-attempt limit, safe sibling switching, trajectory compression, and atomic
# finalization remain. Validate this image and finalize if the checks pass.
harness_selftest() {
    local marker total view system_size

    bash -n "$SELF" || return
    for marker in '<SYSTEM>' '</SYSTEM>' '<TAPE>'; do
        [[ $(grep -Fxc "# $marker" "$SELF") -eq 1 ]] || return 1
    done

    declare -F observe edit_context retape finish finalize prompt_image reason \
        >/dev/null || return

    total=$(wc -c <"$SELF") || return
    view=$(prompt_image | wc -c) || return
    system_size=$(
        sed -n '/^# <SYSTEM>$/,/^# <\/SYSTEM>$/p' "$SELF" | wc -c
    ) || return

    ((view < total)) || return
    grep -Fq 'if [[ "$SELF" == "$CANONICAL" ]]; then' "$SELF" || return
    grep -Fq '[[ ${REACT_TERMINAL:-} == 1 ]]' "$SELF" || return

    printf 'bytes=%s prompt_view_bytes=%s system_bytes=%s saved_per_call=%s\n' \
        "$total" "$view" "$system_size" "$((total - view))"
    printf 'reason_calls=%s limit=%s canonical_present=%s\n' \
        "$REACT_REASON_CALLS" "$REACT_REASON_LIMIT" \
        "$([[ -e "$CANONICAL" ]] && echo yes || echo no)"
}
observe harness_selftest
reason
__REACT_IMAGE__
# EXIT: 1
# REASON-CALL: 4/16
harness_diagnose() {
    set -x
    harness_selftest
}
observe harness_diagnose
reason
