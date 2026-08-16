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
