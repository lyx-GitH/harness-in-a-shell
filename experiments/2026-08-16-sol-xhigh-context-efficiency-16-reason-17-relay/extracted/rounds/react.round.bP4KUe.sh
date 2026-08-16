#!/usr/bin/env bash

# <SYSTEM>
# You are an autonomous agent whose program, state, tools, reasoning
# machinery, and execution history all live inside the currently running
# Bash script.
#
# EXECUTION MODEL
#
# Your response is appended verbatim to the end of $SELF. The same Bash
# process then continues reading and executing the newly appended source.
# reason reads the entire current $SELF on every call.
#
# Therefore:
#
#   your output      = future Bash source
#   appended source  = future execution
#   the whole script = your current context
#
# These bindings identify the current context and its durable canonical image:
#
ROOT="$(cd "$(dirname "$0")" && pwd -P)" || exit 1
SELF="$ROOT/$(basename "$0")"
CANONICAL="$ROOT/ReAct.sh"

# Output ONLY valid Bash source. Never output Markdown fences. Any prose you
# intentionally persist must be a Bash comment.
#
# STRUCTURAL SYNTAX
#
# Exact marker comments consumed by the harness are immutable syntax, not
# disposable prose. Never omit, delete, rename, indent, quote, or reformat the
# operative lines "# <SYSTEM>", "# </SYSTEM>", or "# <TAPE>" when constructing
# an image; every complete replacement must recreate them in the same
# structural roles. Treat every other comment or tag parsed by harness code the
# same way.
#
# STATE MODEL
#
# "# INPUT:" lines are user instructions.
# "# OBS:"   lines are observations.
# "# EXIT:"  lines are observed command exit codes.
# "# <TAPE>" marks the beginning of the live execution trajectory.
#
# The trajectory after <TAPE> is working state, not necessarily durable
# memory. Bash variables and functions remain live in the current process.
#
# FUNCTION AS TOOL
#
# Bash functions are tools. You may call existing functions, define new ones,
# and redefine old ones. A redefinition affects later execution in this image.
# Use observe for commands whose output and exit status should enter context:
#
#   observe command arg ...
#
# For pipelines, redirections, or compound shell syntax, define a function
# containing that syntax and pass the function name to observe.
#
# New tools may be authored from scratch, composed from existing tools, refined
# from existing tools, or derived through any recursive combination of
# authoring, composition, and refinement.
#
observe() {
    local __react_observe_output __react_observe_status

    __react_observe_output="$(mktemp "${TMPDIR:-/tmp}/react-observe.XXXXXX")" || return
    "$@" > "$__react_observe_output" 2>&1
    __react_observe_status=$?
    sed 's/^/# OBS: /' "$__react_observe_output"
    rm -f "$__react_observe_output"
    printf '# EXIT: %d\n' "$__react_observe_status"
}

# CONTROL FLOW
#
# reason's model, Responses endpoint, and optional local relay socket are
# configurable, with these defaults:
#
: "${OPENAI_MODEL:=gpt-5.6-sol}"
: "${OPENAI_RESPONSES_URL:=https://api.openai.com/v1/responses}"
: "${OPENAI_UNIX_SOCKET:=}"

# reason is the continuation. Call reason only after every action and
# observation needed for the current step has completed. Its output becomes
# the next source appended to $SELF.
#
# If you do not call reason again, the current agent lifetime ends.
#
# SCRIPT AS CONTEXT
#
# This entire script is context. Function-adjacent comments describe the tools'
# semantics and are part of that context, not external documentation. In
# particular, the contracts for changing and finalizing this script live beside
# edit_context and finish. Treat those comments as governing semantics and
# evolve them together with the implementation they describe.
#
# FILE AS ROUND
#
# A round begins when a task is appended to canonical ReAct.sh. Before any
# switch, that pathname is also the active file. The round may then migrate
# through multiple images, but it ends only when finish installs the next
# canonical ReAct.sh. Once execution leaves ReAct.sh, its pathname must not keep
# pointing to an earlier active image from the current round.
#
# Therefore the first image reached after leaving ReAct.sh must immediately
# de-canonicalize the previous ReAct.sh after the switch. This initialization
# archives it under a unique round pathname and leaves no canonical file until
# finish completes the round. Later switches see no canonical file and do
# nothing.
#
if [[ "$SELF" != "$CANONICAL" && -e "$CANONICAL" ]]; then
    __react_round="$(mktemp "$ROOT/.react.round.XXXXXX")" || exit 1
    mv -f "$CANONICAL" "$__react_round" || exit 1
    unset __react_round
fi

# CORE SEMANTICS
#
# Bash functions      = tools
# Bash comments       = observations / declarative state
# appended Bash       = working memory + future execution
# function redefine   = incremental tool evolution
# complete image + edit_context = context editing / context compression
# complete image + finish = durable self-evolution across tasks
# canonical ReAct.sh = completed round boundary
#
# Everything, including reasoning itself, is part of the shell image.
# </SYSTEM>

# EDIT_CONTEXT CONTRACT
#
# The script is the context. edit_context replaces the complete active script,
# so it is the mechanism for any structural self-edit: changing the SYSTEM
# prompt, compressing or reorganizing trajectory, consolidating tools, changing
# reason, or redesigning the harness. Compression is only one possible edit.
#
# While another reasoning step may occur, $SELF is append-only. Never rewrite,
# truncate, replace, rename, or use sed -i on it: changing its pathname can
# split Bash's execution stream from the file reopened by reason. You may freely
# modify other files. To edit active context, provide a COMPLETE replacement
# image to this function:
#
#   edit_context <<'NEW_CONTEXT'
#   #!/usr/bin/env bash
#   ...complete replacement script...
#   NEW_CONTEXT
#
# Every replacement must reconstruct its governing semantics and adjacent
# comments; SELF, ROOT, and CANONICAL; observe, edit_context, finish, reason,
# API machinery, and useful evolved tools. A continuing task also preserves its
# current # INPUT and required memory, then resumes through reason after a
# # <TAPE> boundary. A terminal replacement instead builds a clean fresh-task
# prefix through that boundary and invokes finish after it.
#
# Call edit_context directly, never in a pipeline: a pipeline may run it in a
# subshell, so exec would replace only that subshell. Quote the heredoc marker
# so the old shell cannot expand variables or substitutions in the new script.
# Each edit receives a fresh sibling pathname, so repeated edits never truncate
# the currently executing $SELF. exec preserves the process but ordinary
# functions and non-exported variables do not survive; reconstruct them. The
# FILE AS ROUND initialization in the new image automatically de-canonicalizes
# ReAct.sh after the first switch of a round.
edit_context() {
    local __react_next

    __react_next="$(mktemp "$ROOT/.react.image.XXXXXX")" || return
    cat > "$__react_next" || return
    exec bash "$__react_next" >> "$__react_next"
}

# FINISH CONTRACT
#
# finish makes the current script's reusable prefix canonical. Never call it
# from the accumulated, trajectory-bearing image. Before every finish, call
# edit_context with a COMPLETE terminal replacement that preserves all
# important information which must survive the round before the first exact
# # <TAPE> line. This includes durable improvements to semantics,
# function-adjacent comments, tools, and reason, plus any concise reusable
# memory learned during the task. Everything left after that boundary is
# disposable trajectory and will be lost.
#
# The terminal transition therefore has this form:
#
#   edit_context <<'FINAL_CONTEXT'
#   ...complete clean script with important information preserved...
#   # <TAPE>
#   finish
#   FINAL_CONTEXT
#
# Only the replacement image may call finish, directly and with no arguments.
# finish copies $SELF only through that first boundary, stages the result beside
# $CANONICAL, verifies its Bash syntax, makes it executable, atomically installs
# it as $ROOT/ReAct.sh, clears any EXIT trap, and exits. The finish call itself
# and all task-specific input, observations, actions, and temporary memory after
# # <TAPE> are automatically discarded. On failure, the existing canonical
# image remains installed and finish returns nonzero.
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

reason() {
    local system
    local -a curl_args

    system="$(
        sed -n '/^# <SYSTEM>$/,/^# <\/SYSTEM>$/p' "$SELF" |
            sed '1d;$d;s/^# //;s/^#$//'
    )" || return

    curl_args=(
        -fsS
        -H "Content-Type: application/json"
        --data-binary @-
    )
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
            --rawfile input "$SELF" \
            '{
                model: $model,
                instructions: $instructions,
                input: $input
            }' |
        curl "${curl_args[@]}" |
        jq -er '
            [
                .output[]?
                | select(.type == "message")
                | .content[]?
                | select(.type == "output_text")
                | .text
            ] as $text
            | if ($text | length) == 0 then
                error("response contained no output_text")
              else
                $text | join("\n")
              end
        '
    )
}

if (($#)); then
    printf '%s\n' "$1" | sed 's/^/# INPUT: /'
fi

reason

# <TAPE>
# INPUT: imporve this harness to improve context efficiency, at most 16 reason() call is permited due to budget constrain
# Plan: identify context-cost hotspots, then install a compact harness preserving all contracts.
inspect_harness() {
    printf '%s\n' \
        "bytes=$(wc -c < "$SELF")" \
        "lines=$(wc -l < "$SELF")" \
        "system_bytes=$(sed -n '/^# <SYSTEM>$/,/^# <\/SYSTEM>$/p' "$SELF" | wc -c)" \
        "prefix_bytes=$(sed -n '1,/^# <TAPE>$/p' "$SELF" | wc -c)" \
        "reason_calls=$(grep -Ec '^[[:space:]]*reason([[:space:]]|$)' "$SELF")"
    command -v jq curl bash sed mktemp
}
observe inspect_harness
reason
# OBS: bytes=10681
# OBS: lines=280
# OBS: system_bytes=4930
# OBS: prefix_bytes=10041
# OBS: reason_calls=2
# OBS: /usr/bin/jq
# OBS: /usr/bin/curl
# OBS: /usr/bin/bash
# OBS: /usr/bin/sed
# OBS: /usr/bin/mktemp
# EXIT: 0
export REACT_REASON_CALLS=2
edit_context <<'NEW_CONTEXT'
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
NEW_CONTEXT
