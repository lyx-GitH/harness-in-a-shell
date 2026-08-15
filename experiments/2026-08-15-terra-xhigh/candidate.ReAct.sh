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

# IMAGE VALIDATION CONTRACT
#
# validate_image silently accepts only a complete reusable Bash image: a
# readable regular file beginning with the required Bash shebang, passing Bash
# syntax validation, and containing exactly one of each immutable marker in
# SYSTEM-open, SYSTEM-close, TAPE order. It has no side effects and is the gate
# used before an image is executed or published.
validate_image() {
    local image first
    local system_open system_close tape
    local system_open_line system_close_line tape_line

    [[ $# -eq 1 && -f "$1" && -r "$1" ]] || return 1
    image="$1"

    IFS= read -r first < "$image" || return 1
    [[ "$first" == '#!/usr/bin/env bash' ]] || return 1
    bash -n "$image" || return 1

    system_open="$(grep -cxF '# <SYSTEM>' "$image" || true)"
    system_close="$(grep -cxF '# </SYSTEM>' "$image" || true)"
    tape="$(grep -cxF '# <TAPE>' "$image" || true)"
    [[ "$system_open" -eq 1 && "$system_close" -eq 1 && "$tape" -eq 1 ]] || return 1

    system_open_line="$(grep -nFx '# <SYSTEM>' "$image")"
    system_close_line="$(grep -nFx '# </SYSTEM>' "$image")"
    tape_line="$(grep -nFx '# <TAPE>' "$image")"
    system_open_line="${system_open_line%%:*}"
    system_close_line="${system_close_line%%:*}"
    tape_line="${tape_line%%:*}"

    [[ "$system_open_line" =~ ^[0-9]+$ &&
       "$system_close_line" =~ ^[0-9]+$ &&
       "$tape_line" =~ ^[0-9]+$ ]] || return 1
    (( system_open_line < system_close_line && system_close_line < tape_line ))
}

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
# The candidate is first staged beside the active image and must pass

# OBS: edit_context_validation=absent
# OBS: finish_validation=absent
# OBS: finish_syntax_check=present
# EXIT: 0
# validate_image before execution. Invalid candidates are removed and leave the
# current image running. A valid candidate is executed through a fresh sibling
# pathname, preserving append-only semantics for the active image.
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

    __react_next="$(mktemp "$ROOT/.react.image.XXXXXX")" || return 1
    if ! cat > "$__react_next"; then
        rm -f -- "$__react_next"
        return 1
    fi
    if ! validate_image "$__react_next"; then
        rm -f -- "$__react_next"
        return 1
    fi

    exec bash "$__react_next" >> "$__react_next"
}

# FINISH CONTRACT
#
# finish makes the current script's reusable prefix canonical. Before calling
# it, use edit_context when necessary to place every durable improvement to
# semantics, function-adjacent comments, tools, and reason before the first
# exact # <TAPE> line. Everything after that boundary is disposable trajectory.
#
# Call finish directly with no arguments. It copies $SELF only through that
# first boundary, stages the result beside $CANONICAL, validates the complete
# staged image with validate_image, makes it executable, atomically installs it
# as $ROOT/ReAct.sh, clears any EXIT trap, and exits. The finish call itself and
# all task-specific input, observations, actions, and temporary memory after
# # <TAPE> are automatically discarded. On failure, the existing canonical
# image remains installed, the staging file is removed, and finish returns
# nonzero.
finish() {
    local __react_final

    grep -q '^# <TAPE>$' "$SELF" || return 1
    __react_final="$(mktemp "$ROOT/.react.final.XXXXXX")" || return 1

    if ! sed -n '1,/^# <TAPE>$/p' "$SELF" > "$__react_final"; then
        rm -f -- "$__react_final"
        return 1
    fi
    if ! validate_image "$__react_final"; then
        rm -f -- "$__react_final"
        return 1
    fi
    if ! chmod +x "$__react_final"; then
        rm -f -- "$__react_final"
        return 1
    fi
    if ! mv -f -- "$__react_final" "$CANONICAL"; then
        rm -f -- "$__react_final"
        return 1
    fi

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

# <TAPE>
