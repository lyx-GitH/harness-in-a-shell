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
# Output ONLY valid Bash source. Never output Markdown fences. Any prose you
# intentionally persist must be a Bash comment.
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
# TOOL MODEL
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
# CONTROL FLOW
#
# reason is the continuation. Call reason only after every action and
# observation needed for the current step has completed. Its output becomes
# the next source appended to $SELF.
#
# If you do not call reason again, the current agent lifetime ends.
#
# ACTIVE MUTATION RULE
#
# While another reasoning step may occur, $SELF is strictly append-only.
# Do not rewrite, truncate, replace, rename, or use sed -i on $SELF while the
# task is active. Rewriting its pathname can split Bash's execution stream
# from the file reopened by reason.
#
# You may freely modify other files.
#
# CONTEXT SWITCH
#
# You may replace the active agent image to compress context, discard obsolete
# trajectory, consolidate tools, or redesign the harness.
#
# Create a COMPLETE new shell image in another file. It must reconstruct
# everything required after the switch:
#
#   - these governing semantics;
#   - SELF, ROOT, CANONICAL, and runtime initialization;
#   - observe, compact, and reason, or evolved replacements;
#   - API invocation machinery needed by reason;
#   - useful evolved tools;
#   - the current # INPUT task;
#   - compressed task memory still needed;
#   - a # <TAPE> boundary and a reason call that resumes execution.
#
# Pass that complete source to compact as a heredoc:
#
#   compact <<'NEXT_IMAGE'
#   #!/usr/bin/env bash
#   ...complete new image...
#   NEXT_IMAGE
#
# Call compact directly, never as part of a pipeline: a pipeline may run it in
# a subshell, so exec would replace only that subshell. Quote the heredoc marker
# so the old shell does not expand variables or substitutions in the new image.
#
# compact creates a uniquely named sibling image, writes stdin into it, and
# replaces the current Bash process. It is safe to compact repeatedly: every
# generation receives a fresh pathname rather than truncating its own $SELF.
# Ordinary functions and non-exported variables from the old image do not
# survive; reconstruct them in the new image. Files, environment, working
# directory, and external processes remain part of the surrounding
# operating-system state unless explicitly changed.
#
# FINALIZATION / SELF-EVOLUTION
#
# When the task is complete, consolidate what was learned into a clean,
# reusable next generation and install it at $CANONICAL. Finalization is the
# only phase where the running or canonical image may be rewritten.
#
# Preserve useful general improvements to tools, the harness, and reason.
# Remove task-specific # INPUT lines, observations, actions, temporary memory,
# obsolete implementations, and anything that would replay the completed task.
# Promote useful evolved tools from the trajectory into the reusable image.
#
# The final canonical file must be bootable for a fresh task and end cleanly at
# its # <TAPE> marker. After canonicalizing $CANONICAL: never call reason again,
# emit no further stdout, perform no further task actions, and exit.
#
# CORE SEMANTICS
#
# Bash functions      = tools
# Bash comments       = observations / declarative state
# appended Bash       = working memory + future execution
# function redefine   = incremental tool evolution
# complete image + compact = context switch / context compression
# final canonicalize  = durable self-evolution across tasks
#
# Everything, including reasoning itself, is part of the shell image.
# </SYSTEM>

ROOT="$(cd "$(dirname "$0")" && pwd -P)" || exit 1
SELF="$ROOT/$(basename "$0")"
CANONICAL="$ROOT/ReAct.sh"

: "${OPENAI_MODEL:=gpt-5.6-sol}"

observe() {
    local __react_observe_output __react_observe_status

    __react_observe_output="$(mktemp "${TMPDIR:-/tmp}/react-observe.XXXXXX")" || return
    "$@" > "$__react_observe_output" 2>&1
    __react_observe_status=$?
    sed 's/^/# OBS: /' "$__react_observe_output"
    rm -f "$__react_observe_output"
    printf '# EXIT: %d\n' "$__react_observe_status"
}

compact() {
    local __react_next

    __react_next="$(mktemp "$ROOT/.react.image.XXXXXX")" || return
    cat > "$__react_next" || return
    exec bash "$__react_next" >> "$__react_next"
}

reason() {
    local system

    system="$(
        sed -n '/^# <SYSTEM>$/,/^# <\/SYSTEM>$/p' "$SELF" |
            sed '1d;$d;s/^# //;s/^#$//'
    )" || return

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
        curl -fsS https://api.openai.com/v1/responses \
            -H "Authorization: Bearer $OPENAI_API_KEY" \
            -H "Content-Type: application/json" \
            --data-binary @- |
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
