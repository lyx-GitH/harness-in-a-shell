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
# finish makes the current script's reusable prefix canonical. Before calling
# it, use edit_context when necessary to place every durable improvement to
# semantics, function-adjacent comments, tools, and reason before the first
# exact # <TAPE> line. Everything after that boundary is disposable trajectory.
#
# A typical terminal edit therefore ends like this:
#
#   ...clean reusable script...
#   # <TAPE>
#   finish
#
# Call finish directly with no arguments. It copies $SELF only through that
# first boundary, stages the result beside $CANONICAL, verifies its Bash syntax,
# makes it executable, atomically installs it as $ROOT/ReAct.sh, clears any EXIT
# trap, and exits. The finish call itself and all task-specific input,
# observations, actions, and temporary memory after # <TAPE> are automatically
# discarded. On failure, the existing canonical image remains installed and
# finish returns nonzero.
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
# INPUT: improve the harness step by step
harness_audit() {
    printf '%s\n' \
        "bash=$(command -v bash || true)" \
        "curl=$(command -v curl || true)" \
        "jq=$(command -v jq || true)" \
        "mktemp=$(command -v mktemp || true)" \
        "sed=$(command -v sed || true)" \
        "grep=$(command -v grep || true)"
    bash -n "$SELF"
}
observe harness_audit
reason

# OBS: bash=/usr/bin/bash
# OBS: curl=/usr/bin/curl
# OBS: jq=/usr/bin/jq
# OBS: mktemp=/usr/bin/mktemp
# OBS: sed=/usr/bin/sed
# OBS: grep=/usr/bin/grep
# EXIT: 0
# The baseline parses and required external commands are present. Next, inspect the
# round directory and available lint tooling before choosing the first durable
# reliability change.
harness_inventory() {
    printf '%s\n' "root=$ROOT" "self=$SELF" "canonical=$CANONICAL"
    printf '%s\n' "shellcheck=$(command -v shellcheck || true)"
    find "$ROOT" -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort
}
observe harness_inventory
reason

# The baseline parses and required external commands are present. Next, inspect the
# round directory and available lint tooling before choosing the first durable
# reliability change.
harness_inventory() {
    printf '%s\n' "root=$ROOT" "self=$SELF" "canonical=$CANONICAL"
    printf '%s\n' "shellcheck=$(command -v shellcheck || true)"
    find "$ROOT" -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort
}
observe harness_inventory
reason
# OBS: root=/work
# OBS: self=/work/ReAct.sh
# OBS: canonical=/work/ReAct.sh
# OBS: shellcheck=
# OBS: .sandbox.log
# OBS: ReAct.sh
# EXIT: 0
observe_without_newline() {
    printf 'unterminated output'
    return 7
}
observe observe_without_newline
reason
# OBS: root=/work
# OBS: self=/work/ReAct.sh
# OBS: canonical=/work/ReAct.sh
# OBS: shellcheck=
# OBS: .sandbox.log
# OBS: ReAct.sh
# EXIT: 0
audit_observe_format() {
    local rendered
    rendered="$(observe observe_without_newline)"
    printf 'rendered=%q\n' "$rendered"
}
observe audit_observe_format
reason
# OBS: unterminated output# EXIT: 7
# Fix observation framing so command output without a trailing newline cannot
# merge with the structured EXIT record.
observe() {
    local __react_observe_output __react_observe_status __react_observe_line

    __react_observe_output="$(mktemp "${TMPDIR:-/tmp}/react-observe.XXXXXX")" || return
    "$@" > "$__react_observe_output" 2>&1
    __react_observe_status=$?
    while IFS= read -r __react_observe_line || [[ -n "$__react_observe_line" ]]; do
        printf '# OBS: %s\n' "$__react_observe_line"
    done < "$__react_observe_output"
    rm -f "$__react_observe_output"
    printf '# EXIT: %d\n' "$__react_observe_status"
}
observe observe_without_newline
reason
# OBS: rendered=\#\ OBS:\ unterminated\ output#\ EXIT:\ 7
# EXIT: 0
verify_observe_framing() {
    local rendered expected

    rendered="$(observe observe_without_newline)"
    expected=$'# OBS: unterminated output\n# EXIT: 7'
    printf 'rendered=%q\n' "$rendered"
    [[ "$rendered" == "$expected" ]]
}
observe verify_observe_framing
reason
# OBS: unterminated output
# EXIT: 7
# Add structural validation for replacement and canonical images before wiring it
# into edit_context and finish.
validate_image() {
    local __react_image=$1
    local __react_line __react_first=
    local -i __react_line_no=0
    local -i __react_system_open=0 __react_system_close=0 __react_tape=0
    local -i __react_system_open_at=0 __react_system_close_at=0 __react_tape_at=0

    [[ -f "$__react_image" ]] || {
        printf 'validate_image: not a regular file: %s\n' "$__react_image" >&2
        return 1
    }

    while IFS= read -r __react_line || [[ -n "$__react_line" ]]; do
        ((__react_line_no += 1))
        if ((__react_line_no == 1)); then
            __react_first=$__react_line
        fi
        case "$__react_line" in
            '# <SYSTEM>')
                ((__react_system_open += 1))
                __react_system_open_at=$__react_line_no
                ;;
            '# </SYSTEM>')
                ((__react_system_close += 1))
                __react_system_close_at=$__react_line_no
                ;;
            '# <TAPE>')
                ((__react_tape += 1))
                __react_tape_at=$__react_line_no
                ;;
        esac
    done < "$__react_image"

    [[ "$__react_first" == '#!/usr/bin/env bash' ]] || {
        printf 'validate_image: missing expected Bash shebang\n' >&2
        return 1
    }
    ((__react_system_open == 1)) || {
        printf 'validate_image: expected one SYSTEM opening marker, found %d\n' \
            "$__react_system_open" >&2
        return 1
    }
    ((__react_system_close == 1)) || {
        printf 'validate_image: expected one SYSTEM closing marker, found %d\n' \
            "$__react_system_close" >&2
        return 1
    }
    ((__react_tape == 1)) || {
        printf 'validate_image: expected one TAPE marker, found %d\n' \
            "$__react_tape" >&2
        return 1
    }
    ((__react_system_open_at < __react_system_close_at &&
      __react_system_close_at < __react_tape_at)) || {
        printf 'validate_image: structural markers are out of order\n' >&2
        return 1
    }
    bash -n "$__react_image"
}

test_validate_image() {
    local __react_fixture

    validate_image "$SELF" || return

    __react_fixture="$(mktemp "${TMPDIR:-/tmp}/react-image-test.XXXXXX")" || return
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        '# <SYSTEM>' \
        '# </SYSTEM>' \
        '# <TAPE>' \
        'if then' > "$__react_fixture"
    if validate_image "$__react_fixture" >/dev/null 2>&1; then
        rm -f "$__react_fixture"
        printf 'invalid syntax was accepted\n'
        return 1
    fi

    printf '%s\n' \
        '#!/usr/bin/env bash' \
        '# <SYSTEM>' \
        '# </SYSTEM>' \
        '# <TAPE>' \
        '# <TAPE>' > "$__react_fixture"
    if validate_image "$__react_fixture" >/dev/null 2>&1; then
        rm -f "$__react_fixture"
        printf 'duplicate structural marker was accepted\n'
        return 1
    fi

    rm -f "$__react_fixture"
    printf 'image validation checks passed\n'
}
observe test_validate_image
reason

# OBS: rendered=$'# OBS: unterminated output\n# EXIT: 7'
# EXIT: 0
observe test_validate_image
reason
# OBS: image validation checks passed
# EXIT: 0
