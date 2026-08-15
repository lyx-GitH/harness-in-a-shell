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
# INPUT: improve this harness step by step
observe bash -c '
printf "ROOT=%q\nSELF=%q\nCANONICAL=%q\n" "$ROOT" "$SELF" "$CANONICAL"
printf "%s\n" "--- directory ---"
ls -la "$ROOT"
printf "%s\n" "--- tool availability ---"
for tool in bash curl jq shellcheck flock realpath; do
    if command -v "$tool" >/dev/null 2>&1; then
        printf "%-10s %s\n" "$tool" "$(command -v "$tool")"
    else
        printf "%-10s MISSING\n" "$tool"
    fi
done
printf "%s\n" "--- syntax check ---"
bash -n "$SELF"
'
reason
# OBS: ROOT=''
# OBS: SELF=''
# OBS: CANONICAL=''
# OBS: --- directory ---
# OBS: ls: cannot access '': No such file or directory
# OBS: --- tool availability ---
# OBS: bash       /usr/bin/bash
# OBS: curl       /usr/bin/curl
# OBS: jq         /usr/bin/jq
# OBS: shellcheck MISSING
# OBS: flock      /usr/bin/flock
# OBS: realpath   /usr/bin/realpath
# OBS: --- syntax check ---
# OBS: bash: : No such file or directory
# EXIT: 127
inspect_harness() {
    printf 'ROOT=%q\nSELF=%q\nCANONICAL=%q\n' "$ROOT" "$SELF" "$CANONICAL"
    printf '%s\n' '--- directory ---'
    ls -la "$ROOT"
    printf '%s\n' '--- tool availability ---'
    local tool
    for tool in bash curl jq shellcheck flock realpath; do
        if command -v "$tool" >/dev/null 2>&1; then
            printf '%-10s %s\n' "$tool" "$(command -v "$tool")"
        else
            printf '%-10s MISSING\n' "$tool"
        fi
    done
    printf '%s\n' '--- syntax check ---'
    bash -n "$SELF"
}
observe inspect_harness
reason

# OBS: ROOT=/work
# OBS: SELF=/work/ReAct.sh
# OBS: CANONICAL=/work/ReAct.sh
# OBS: --- directory ---
# OBS: total 68
# OBS: drwxr-xr-x 4 65532 65532   220 Aug 15 13:23 .
# OBS: drwxr-xr-x 1 root  root   4096 Aug 15 13:23 ..
# OBS: drwx------ 8 65532 65532   260 Aug 15 13:23 .git
# OBS: -rw------- 1 65532 65532    84 Aug 15 13:23 .gitignore
# OBS: drwx------ 2 65532 65532    40 Aug 15 13:23 .home
# OBS: -rw------- 1 65532 65532    48 Aug 15 13:23 .sandbox.log
# OBS: -rw------- 1 65532 65532  4465 Aug 15 13:23 AGENTS.md
# OBS: -rw------- 1 65532 65532  9137 Aug 15 13:23 README.md
# OBS: -rw------- 1 65532 65532  9216 Aug 15 13:23 README.zh-CN.md
# OBS: -rwx------ 1 65532 65532 11170 Aug 15 13:23 ReAct.sh
# OBS: -rwx------ 1 65532 65532 11767 Aug 15 13:23 test.sh
# OBS: --- tool availability ---
# OBS: bash       /usr/bin/bash
# OBS: curl       /usr/bin/curl
# OBS: jq         /usr/bin/jq
# OBS: shellcheck MISSING
# OBS: flock      /usr/bin/flock
# OBS: realpath   /usr/bin/realpath
# OBS: --- syntax check ---
# EXIT: 0
inspect_project() {
    printf '%s\n' '--- git status ---'
    git -C "$ROOT" status --short --branch
    printf '%s\n' '--- recent commits ---'
    git -C "$ROOT" log -5 --oneline --decorate
    printf '%s\n' '--- AGENTS.md ---'
    cat "$ROOT/AGENTS.md"
    printf '%s\n' '--- README headings ---'
    grep -nE '^(#|##|###) ' "$ROOT/README.md"
    printf '%s\n' '--- test definitions ---'
    grep -nE '^([[:alnum:]_]+[[:space:]]*\(\)|test_|run_|main\(\))' "$ROOT/test.sh"
    printf '%s\n' '--- tracked files ---'
    git -C "$ROOT" ls-files
}
observe inspect_project
reason

# OBS: --- git status ---
# OBS: ## master
# OBS:  M ReAct.sh
# OBS: ?? .sandbox.log
# OBS: --- recent commits ---
# OBS: bdfd843 (HEAD -> master) sandbox seed
# OBS: --- AGENTS.md ---
# OBS: # Project Notes
# OBS: 
# OBS: - `ReAct.sh` is the entire agent runtime and canonical image. Keep it small and
# OBS:   preserve the append-only execution semantics.
# OBS: - Keep `observe()` co-located with its FUNCTION AS TOOL contract inside
# OBS:   `<SYSTEM>`; executable function source is itself part of the model's
# OBS:   instructions.
# OBS: - Keep `ROOT`/`SELF`/`CANONICAL` in EXECUTION MODEL and the `OPENAI_MODEL`
# OBS:   default in CONTROL FLOW so runtime configuration stays beside its semantics.
# OBS: - Exact comments parsed as harness structure are immutable syntax. In each
# OBS:   complete image, preserve the operative `# <SYSTEM>`, `# </SYSTEM>`, and
# OBS:   `# <TAPE>` lines exactly and in order; apply the same rule to future parsed
# OBS:   tags/comments. `test.sh` locks the clean-image marker counts and ordering.
# OBS: - `test.sh` is the only test harness. It must not call the real API; it injects
# OBS:   `curl` and `jq` stubs through `PATH`, and covers both repeated `edit_context`
# OBS:   calls and terminal canonicalization through `finish`.
# OBS: - Run syntax checks with `/bin/bash -n ReAct.sh` and `/bin/bash -n test.sh`.
# OBS: - Run the semantic test with `bash test.sh`.
# OBS: - Set `BASH_UNDER_TEST=/path/to/bash` to validate the append semantics against a
# OBS:   particular Bash build.
# OBS: - The host macOS lacks `realpath` and currently lacks `jq`. Path initialization
# OBS:   therefore uses `cd` plus `pwd -P`; live API runs require installing `jq`.
# OBS: - During an active task, the running image is append-only. Context compression
# OBS:   or structural self-editing passes another complete image to `edit_context`,
# OBS:   which selects a unique `.react.image.*` path and switches with `exec`; only
# OBS:   `finish` validates the current image's prefix through its first `# <TAPE>`,
# OBS:   installs that prefix as canonical `ReAct.sh`, then exits.
# OBS: - FILE AS ROUND means the first noncanonical image archives the dirty prior
# OBS:   `ReAct.sh` as `.react.round.*`; the canonical pathname remains absent until
# OBS:   `finish` ends the round.
# OBS: - The prototype assumes one active round per directory; concurrent rounds would
# OBS:   contend for the single canonical pathname and round archive transition.
# OBS: - `bash sandbox.sh test` runs the stub in a no-network, no-key container;
# OBS:   `bash sandbox.sh verify` exercises the container and relay boundaries with a
# OBS:   fake key. Runtime containers never bind-mount host paths.
# OBS: - For live fallback runs, the agent has `network=none` and no API key. It reaches
# OBS:   `sandbox/openai_relay.py` only through a Unix socket located on a Docker volume
# OBS:   mounted read-only into the agent; the relay alone has egress and fixes the
# OBS:   upstream to OpenAI Responses. Results under `sandbox-runs/` are quarantined
# OBS:   and must not be executed on the host.
# OBS: - The host watchdog is authoritative; the same-UID in-container `timeout` is
# OBS:   only a graceful first stage. Agent stdout/stderr are capped by Docker's local
# OBS:   log driver and retained as `untrusted-{output,stderr}.bin`; never parse those
# OBS:   streams or render agent-controlled logs automatically on the host.
# OBS: - `.env` and `.env.*` must remain excluded from Git and Docker build contexts.
# OBS:   A live key is passed only to the trusted relay container, never to the agent.
# OBS: - Cost-conscious sandbox defaults are 8 upstream attempts and 4096 output
# OBS:   tokens per attempt. The relay's trusted `/tmp/openai-request-count` is copied
# OBS:   into each non-test run directory for audit without trusting agent output.
# OBS: - A 2026-08-15 live terra trial was sandbox validation only. Its syntactically
# OBS:   valid candidate omitted the closing `# </SYSTEM>` marker and was not adopted;
# OBS:   model-produced candidates must remain test artifacts unless the user asks to
# OBS:   merge them.
# OBS: - This host's legacy macOS 12.5.1 / Docker Desktop 4.9.1 stack is acceptable only
# OBS:   for stub/verification convenience, not as the sole boundary for live arbitrary
# OBS:   Bash. Use a no-sharing disposable UTM Linux VM now, or Docker Sandboxes clone
# OBS:   mode after upgrading to macOS 14+.
# OBS: - On this host, Docker Hub token fetches currently time out. The tested local
# OBS:   build fallback retags the cached Ubuntu 24.04 amd64 image as
# OBS:   `react-sandbox-base:cached`, disables old BuildKit with
# OBS:   `DOCKER_BUILDKIT=0`, and sets `SANDBOX_BASE_IMAGE=react-sandbox-base:cached`
# OBS:   plus `SANDBOX_BUILD_PROXY=http://host.docker.internal:1087`; these are
# OBS:   build-only inputs and runtime remains isolated.
# OBS: - After those images exist, `SANDBOX_SKIP_BUILD=1 bash sandbox.sh test` or
# OBS:   `verify` reuses them without any build-time network. Rebuild after source
# OBS:   changes rather than testing stale images.
# OBS: --- README headings ---
# OBS: 1:# Harness in a Shell
# OBS: 16:## 1. Script as Context
# OBS: 26:# INPUT: user instructions
# OBS: 27:# OBS:   tool observations
# OBS: 28:# EXIT:  observed exit status
# OBS: 29:# <TAPE> live trajectory begins here
# OBS: 36:## 2. Function as Tool
# OBS: 51:## 3. File as Round
# OBS: 88:## Run
# OBS: 109:## Test without an API key
# OBS: 120:## Run in a disposable sandbox
# OBS: 187:### Stronger microVM setup
# OBS: --- test definitions ---
# OBS: 11:cleanup() {
# OBS: 16:fail() {
# OBS: 21:assert_count() {
# OBS: 32:assert_structural_image() {
# OBS: 82:observe() { "$@"; }
# OBS: 85:edit_context() {
# OBS: 93:finish() {
# OBS: 106:reason() { :; }
# OBS: 132:tool() { TOOL_STATE=v1; printf '%s\n' v1; }
# OBS: 141:tool() { TOOL_STATE=v2; printf '%s\n' v2; return 7; }
# OBS: 159:observe() { "$@"; }
# OBS: 163:edit_context() {
# OBS: 171:reason() {
# OBS: 188:observe() { "$@"; }
# OBS: 192:edit_context() {
# OBS: 200:reason() {
# OBS: --- tracked files ---
# OBS: .gitignore
# OBS: AGENTS.md
# OBS: README.md
# OBS: README.zh-CN.md
# OBS: ReAct.sh
# OBS: test.sh
# EXIT: 0
# Inspect the current implementation, tests, and baseline behavior before choosing the next incremental improvement.
show_sources() {
    printf '%s\n' '--- git diff ---'
    git -C "$ROOT" diff -- ReAct.sh test.sh README.md README.zh-CN.md AGENTS.md
    printf '%s\n' '--- test.sh ---'
    cat "$ROOT/test.sh"
    printf '%s\n' '--- README.md ---'
    cat "$ROOT/README.md"
}
observe show_sources
reason

# Inspect the current implementation, tests, and baseline behavior before choosing the next incremental improvement.
show_sources() {
    printf '%s\n' '--- git diff ---'
    git -C "$ROOT" diff -- ReAct.sh test.sh README.md README.zh-CN.md AGENTS.md
    printf '%s\n' '--- test.sh ---'
    cat "$ROOT/test.sh"
    printf '%s\n' '--- README.md ---'
    cat "$ROOT/README.md"
}
observe show_sources
reason
# OBS: --- git diff ---
# OBS: diff --git a/ReAct.sh b/ReAct.sh
# OBS: index d2fc0ad..f7ce6eb 100755
# OBS: --- a/ReAct.sh
# OBS: +++ b/ReAct.sh
# OBS: @@ -259,3 +259,230 @@ fi
# OBS:  reason
# OBS:  
# OBS:  # <TAPE>
# OBS: +# INPUT: improve this harness step by step
# OBS: +observe bash -c '
# OBS: +printf "ROOT=%q\nSELF=%q\nCANONICAL=%q\n" "$ROOT" "$SELF" "$CANONICAL"
# OBS: +printf "%s\n" "--- directory ---"
# OBS: +ls -la "$ROOT"
# OBS: +printf "%s\n" "--- tool availability ---"
# OBS: +for tool in bash curl jq shellcheck flock realpath; do
# OBS: +    if command -v "$tool" >/dev/null 2>&1; then
# OBS: +        printf "%-10s %s\n" "$tool" "$(command -v "$tool")"
# OBS: +    else
# OBS: +        printf "%-10s MISSING\n" "$tool"
# OBS: +    fi
# OBS: +done
# OBS: +printf "%s\n" "--- syntax check ---"
# OBS: +bash -n "$SELF"
# OBS: +'
# OBS: +reason
# OBS: +# OBS: ROOT=''
# OBS: +# OBS: SELF=''
# OBS: +# OBS: CANONICAL=''
# OBS: +# OBS: --- directory ---
# OBS: +# OBS: ls: cannot access '': No such file or directory
# OBS: +# OBS: --- tool availability ---
# OBS: +# OBS: bash       /usr/bin/bash
# OBS: +# OBS: curl       /usr/bin/curl
# OBS: +# OBS: jq         /usr/bin/jq
# OBS: +# OBS: shellcheck MISSING
# OBS: +# OBS: flock      /usr/bin/flock
# OBS: +# OBS: realpath   /usr/bin/realpath
# OBS: +# OBS: --- syntax check ---
# OBS: +# OBS: bash: : No such file or directory
# OBS: +# EXIT: 127
# OBS: +inspect_harness() {
# OBS: +    printf 'ROOT=%q\nSELF=%q\nCANONICAL=%q\n' "$ROOT" "$SELF" "$CANONICAL"
# OBS: +    printf '%s\n' '--- directory ---'
# OBS: +    ls -la "$ROOT"
# OBS: +    printf '%s\n' '--- tool availability ---'
# OBS: +    local tool
# OBS: +    for tool in bash curl jq shellcheck flock realpath; do
# OBS: +        if command -v "$tool" >/dev/null 2>&1; then
# OBS: +            printf '%-10s %s\n' "$tool" "$(command -v "$tool")"
# OBS: +        else
# OBS: +            printf '%-10s MISSING\n' "$tool"
# OBS: +        fi
# OBS: +    done
# OBS: +    printf '%s\n' '--- syntax check ---'
# OBS: +    bash -n "$SELF"
# OBS: +}
# OBS: +observe inspect_harness
# OBS: +reason
# OBS: +
# OBS: +# OBS: ROOT=/work
# OBS: +# OBS: SELF=/work/ReAct.sh
# OBS: +# OBS: CANONICAL=/work/ReAct.sh
# OBS: +# OBS: --- directory ---
# OBS: +# OBS: total 68
# OBS: +# OBS: drwxr-xr-x 4 65532 65532   220 Aug 15 13:23 .
# OBS: +# OBS: drwxr-xr-x 1 root  root   4096 Aug 15 13:23 ..
# OBS: +# OBS: drwx------ 8 65532 65532   260 Aug 15 13:23 .git
# OBS: +# OBS: -rw------- 1 65532 65532    84 Aug 15 13:23 .gitignore
# OBS: +# OBS: drwx------ 2 65532 65532    40 Aug 15 13:23 .home
# OBS: +# OBS: -rw------- 1 65532 65532    48 Aug 15 13:23 .sandbox.log
# OBS: +# OBS: -rw------- 1 65532 65532  4465 Aug 15 13:23 AGENTS.md
# OBS: +# OBS: -rw------- 1 65532 65532  9137 Aug 15 13:23 README.md
# OBS: +# OBS: -rw------- 1 65532 65532  9216 Aug 15 13:23 README.zh-CN.md
# OBS: +# OBS: -rwx------ 1 65532 65532 11170 Aug 15 13:23 ReAct.sh
# OBS: +# OBS: -rwx------ 1 65532 65532 11767 Aug 15 13:23 test.sh
# OBS: +# OBS: --- tool availability ---
# OBS: +# OBS: bash       /usr/bin/bash
# OBS: +# OBS: curl       /usr/bin/curl
# OBS: +# OBS: jq         /usr/bin/jq
# OBS: +# OBS: shellcheck MISSING
# OBS: +# OBS: flock      /usr/bin/flock
# OBS: +# OBS: realpath   /usr/bin/realpath
# OBS: +# OBS: --- syntax check ---
# OBS: +# EXIT: 0
# OBS: +inspect_project() {
# OBS: +    printf '%s\n' '--- git status ---'
# OBS: +    git -C "$ROOT" status --short --branch
# OBS: +    printf '%s\n' '--- recent commits ---'
# OBS: +    git -C "$ROOT" log -5 --oneline --decorate
# OBS: +    printf '%s\n' '--- AGENTS.md ---'
# OBS: +    cat "$ROOT/AGENTS.md"
# OBS: +    printf '%s\n' '--- README headings ---'
# OBS: +    grep -nE '^(#|##|###) ' "$ROOT/README.md"
# OBS: +    printf '%s\n' '--- test definitions ---'
# OBS: +    grep -nE '^([[:alnum:]_]+[[:space:]]*\(\)|test_|run_|main\(\))' "$ROOT/test.sh"
# OBS: +    printf '%s\n' '--- tracked files ---'
# OBS: +    git -C "$ROOT" ls-files
# OBS: +}
# OBS: +observe inspect_project
# OBS: +reason
# OBS: +
# OBS: +# OBS: --- git status ---
# OBS: +# OBS: ## master
# OBS: +# OBS:  M ReAct.sh
# OBS: +# OBS: ?? .sandbox.log
# OBS: +# OBS: --- recent commits ---
# OBS: +# OBS: bdfd843 (HEAD -> master) sandbox seed
# OBS: +# OBS: --- AGENTS.md ---
# OBS: +# OBS: # Project Notes
# OBS: +# OBS: 
# OBS: +# OBS: - `ReAct.sh` is the entire agent runtime and canonical image. Keep it small and
# OBS: +# OBS:   preserve the append-only execution semantics.
# OBS: +# OBS: - Keep `observe()` co-located with its FUNCTION AS TOOL contract inside
# OBS: +# OBS:   `<SYSTEM>`; executable function source is itself part of the model's
# OBS: +# OBS:   instructions.
# OBS: +# OBS: - Keep `ROOT`/`SELF`/`CANONICAL` in EXECUTION MODEL and the `OPENAI_MODEL`
# OBS: +# OBS:   default in CONTROL FLOW so runtime configuration stays beside its semantics.
# OBS: +# OBS: - Exact comments parsed as harness structure are immutable syntax. In each
# OBS: +# OBS:   complete image, preserve the operative `# <SYSTEM>`, `# </SYSTEM>`, and
# OBS: +# OBS:   `# <TAPE>` lines exactly and in order; apply the same rule to future parsed
# OBS: +# OBS:   tags/comments. `test.sh` locks the clean-image marker counts and ordering.
# OBS: +# OBS: - `test.sh` is the only test harness. It must not call the real API; it injects
# OBS: +# OBS:   `curl` and `jq` stubs through `PATH`, and covers both repeated `edit_context`
# OBS: +# OBS:   calls and terminal canonicalization through `finish`.
# OBS: +# OBS: - Run syntax checks with `/bin/bash -n ReAct.sh` and `/bin/bash -n test.sh`.
# OBS: +# OBS: - Run the semantic test with `bash test.sh`.
# OBS: +# OBS: - Set `BASH_UNDER_TEST=/path/to/bash` to validate the append semantics against a
# OBS: +# OBS:   particular Bash build.
# OBS: +# OBS: - The host macOS lacks `realpath` and currently lacks `jq`. Path initialization
# OBS: +# OBS:   therefore uses `cd` plus `pwd -P`; live API runs require installing `jq`.
# OBS: +# OBS: - During an active task, the running image is append-only. Context compression
# OBS: +# OBS:   or structural self-editing passes another complete image to `edit_context`,
# OBS: +# OBS:   which selects a unique `.react.image.*` path and switches with `exec`; only
# OBS: +# OBS:   `finish` validates the current image's prefix through its first `# <TAPE>`,
# OBS: +# OBS:   installs that prefix as canonical `ReAct.sh`, then exits.
# OBS: +# OBS: - FILE AS ROUND means the first noncanonical image archives the dirty prior
# OBS: +# OBS:   `ReAct.sh` as `.react.round.*`; the canonical pathname remains absent until
# OBS: +# OBS:   `finish` ends the round.
# OBS: +# OBS: - The prototype assumes one active round per directory; concurrent rounds would
# OBS: +# OBS:   contend for the single canonical pathname and round archive transition.
# OBS: +# OBS: - `bash sandbox.sh test` runs the stub in a no-network, no-key container;
# OBS: +# OBS:   `bash sandbox.sh verify` exercises the container and relay boundaries with a
# OBS: +# OBS:   fake key. Runtime containers never bind-mount host paths.
# OBS: +# OBS: - For live fallback runs, the agent has `network=none` and no API key. It reaches
# OBS: +# OBS:   `sandbox/openai_relay.py` only through a Unix socket located on a Docker volume
# OBS: +# OBS:   mounted read-only into the agent; the relay alone has egress and fixes the
# OBS: +# OBS:   upstream to OpenAI Responses. Results under `sandbox-runs/` are quarantined
# OBS: +# OBS:   and must not be executed on the host.
# OBS: +# OBS: - The host watchdog is authoritative; the same-UID in-container `timeout` is
# OBS: +# OBS:   only a graceful first stage. Agent stdout/stderr are capped by Docker's local
# OBS: +# OBS:   log driver and retained as `untrusted-{output,stderr}.bin`; never parse those
# OBS: +# OBS:   streams or render agent-controlled logs automatically on the host.
# OBS: +# OBS: - `.env` and `.env.*` must remain excluded from Git and Docker build contexts.
# OBS: +# OBS:   A live key is passed only to the trusted relay container, never to the agent.
# OBS: +# OBS: - Cost-conscious sandbox defaults are 8 upstream attempts and 4096 output
# OBS: +# OBS:   tokens per attempt. The relay's trusted `/tmp/openai-request-count` is copied
# OBS: +# OBS:   into each non-test run directory for audit without trusting agent output.
# OBS: +# OBS: - A 2026-08-15 live terra trial was sandbox validation only. Its syntactically
# OBS: +# OBS:   valid candidate omitted the closing `# </SYSTEM>` marker and was not adopted;
# OBS: +# OBS:   model-produced candidates must remain test artifacts unless the user asks to
# OBS: +# OBS:   merge them.
# OBS: +# OBS: - This host's legacy macOS 12.5.1 / Docker Desktop 4.9.1 stack is acceptable only
# OBS: +# OBS:   for stub/verification convenience, not as the sole boundary for live arbitrary
# OBS: +# OBS:   Bash. Use a no-sharing disposable UTM Linux VM now, or Docker Sandboxes clone
# OBS: +# OBS:   mode after upgrading to macOS 14+.
# OBS: +# OBS: - On this host, Docker Hub token fetches currently time out. The tested local
# OBS: +# OBS:   build fallback retags the cached Ubuntu 24.04 amd64 image as
# OBS: +# OBS:   `react-sandbox-base:cached`, disables old BuildKit with
# OBS: +# OBS:   `DOCKER_BUILDKIT=0`, and sets `SANDBOX_BASE_IMAGE=react-sandbox-base:cached`
# OBS: +# OBS:   plus `SANDBOX_BUILD_PROXY=http://host.docker.internal:1087`; these are
# OBS: +# OBS:   build-only inputs and runtime remains isolated.
# OBS: +# OBS: - After those images exist, `SANDBOX_SKIP_BUILD=1 bash sandbox.sh test` or
# OBS: +# OBS:   `verify` reuses them without any build-time network. Rebuild after source
# OBS: +# OBS:   changes rather than testing stale images.
# OBS: +# OBS: --- README headings ---
# OBS: +# OBS: 1:# Harness in a Shell
# OBS: +# OBS: 16:## 1. Script as Context
# OBS: +# OBS: 26:# INPUT: user instructions
# OBS: +# OBS: 27:# OBS:   tool observations
# OBS: +# OBS: 28:# EXIT:  observed exit status
# OBS: +# OBS: 29:# <TAPE> live trajectory begins here
# OBS: +# OBS: 36:## 2. Function as Tool
# OBS: +# OBS: 51:## 3. File as Round
# OBS: +# OBS: 88:## Run
# OBS: +# OBS: 109:## Test without an API key
# OBS: +# OBS: 120:## Run in a disposable sandbox
# OBS: +# OBS: 187:### Stronger microVM setup
# OBS: +# OBS: --- test definitions ---
# OBS: +# OBS: 11:cleanup() {
# OBS: +# OBS: 16:fail() {
# OBS: +# OBS: 21:assert_count() {
# OBS: +# OBS: 32:assert_structural_image() {
# OBS: +# OBS: 82:observe() { "$@"; }
# OBS: +# OBS: 85:edit_context() {
# OBS: +# OBS: 93:finish() {
# OBS: +# OBS: 106:reason() { :; }
# OBS: +# OBS: 132:tool() { TOOL_STATE=v1; printf '%s\n' v1; }
# OBS: +# OBS: 141:tool() { TOOL_STATE=v2; printf '%s\n' v2; return 7; }
# OBS: +# OBS: 159:observe() { "$@"; }
# OBS: +# OBS: 163:edit_context() {
# OBS: +# OBS: 171:reason() {
# OBS: +# OBS: 188:observe() { "$@"; }
# OBS: +# OBS: 192:edit_context() {
# OBS: +# OBS: 200:reason() {
# OBS: +# OBS: --- tracked files ---
# OBS: +# OBS: .gitignore
# OBS: +# OBS: AGENTS.md
# OBS: +# OBS: README.md
# OBS: +# OBS: README.zh-CN.md
# OBS: +# OBS: ReAct.sh
# OBS: +# OBS: test.sh
# OBS: +# EXIT: 0
# OBS: +# Inspect the current implementation, tests, and baseline behavior before choosing the next incremental improvement.
# OBS: +show_sources() {
# OBS: +    printf '%s\n' '--- git diff ---'
# OBS: +    git -C "$ROOT" diff -- ReAct.sh test.sh README.md README.zh-CN.md AGENTS.md
# OBS: +    printf '%s\n' '--- test.sh ---'
# OBS: +    cat "$ROOT/test.sh"
# OBS: +    printf '%s\n' '--- README.md ---'
# OBS: +    cat "$ROOT/README.md"
# OBS: +}
# OBS: +observe show_sources
# OBS: +reason
# OBS: +
# OBS: +# Inspect the current implementation, tests, and baseline behavior before choosing the next incremental improvement.
# OBS: +show_sources() {
# OBS: +    printf '%s\n' '--- git diff ---'
# OBS: +    git -C "$ROOT" diff -- ReAct.sh test.sh README.md README.zh-CN.md AGENTS.md
# OBS: +    printf '%s\n' '--- test.sh ---'
# OBS: +    cat "$ROOT/test.sh"
# OBS: +    printf '%s\n' '--- README.md ---'
# OBS: +    cat "$ROOT/README.md"
# OBS: +}
# OBS: +observe show_sources
# OBS: +reason
# OBS: --- test.sh ---
# OBS: #!/usr/bin/env bash
# OBS: 
# OBS: set -euo pipefail
# OBS: 
# OBS: PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd -P)"
# OBS: TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/harness-in-a-shell.XXXXXX")"
# OBS: TMP_ROOT="$(cd "$TMP_ROOT" && pwd -P)"
# OBS: BASH_UNDER_TEST="${BASH_UNDER_TEST:-/bin/bash}"
# OBS: BASH_DIR="$(cd "$(dirname "$BASH_UNDER_TEST")" && pwd -P)"
# OBS: 
# OBS: cleanup() {
# OBS:     rm -rf "$TMP_ROOT"
# OBS: }
# OBS: trap cleanup EXIT
# OBS: 
# OBS: fail() {
# OBS:     printf 'FAIL: %s\n' "$1" >&2
# OBS:     exit 1
# OBS: }
# OBS: 
# OBS: assert_count() {
# OBS:     local expected="$1"
# OBS:     local pattern="$2"
# OBS:     local file="$3"
# OBS:     local actual
# OBS: 
# OBS:     actual="$(grep -c -- "$pattern" "$file" || true)"
# OBS:     [[ "$actual" == "$expected" ]] ||
# OBS:         fail "expected $expected matches for '$pattern' in $file; got $actual"
# OBS: }
# OBS: 
# OBS: assert_structural_image() {
# OBS:     local file="$1"
# OBS:     local system_open system_close tape
# OBS: 
# OBS:     assert_count 1 '^# <SYSTEM>$' "$file"
# OBS:     assert_count 1 '^# </SYSTEM>$' "$file"
# OBS:     assert_count 1 '^# <TAPE>$' "$file"
# OBS: 
# OBS:     system_open="$(grep -n '^# <SYSTEM>$' "$file" | cut -d: -f1)"
# OBS:     system_close="$(grep -n '^# </SYSTEM>$' "$file" | cut -d: -f1)"
# OBS:     tape="$(grep -n '^# <TAPE>$' "$file" | cut -d: -f1)"
# OBS:     ((system_open < system_close && system_close < tape)) ||
# OBS:         fail "structural markers are out of order in $file"
# OBS: }
# OBS: 
# OBS: mkdir "$TMP_ROOT/bin"
# OBS: cp "$PROJECT_ROOT/ReAct.sh" "$TMP_ROOT/ReAct.sh"
# OBS: 
# OBS: cat > "$TMP_ROOT/bin/curl" <<'CURL_STUB'
# OBS: #!/usr/bin/env bash
# OBS: cat >/dev/null
# OBS: printf '{}\n'
# OBS: CURL_STUB
# OBS: 
# OBS: cat > "$TMP_ROOT/bin/jq" <<'JQ_STUB'
# OBS: #!/usr/bin/env bash
# OBS: set -euo pipefail
# OBS: 
# OBS: if [[ "${1-}" == "-n" ]]; then
# OBS:     printf '{}\n'
# OBS:     exit
# OBS: fi
# OBS: 
# OBS: cat >/dev/null
# OBS: 
# OBS: if [[ "${STUB_SCENARIO:-edit}" == "finish" ]]; then
# OBS:     cat <<'FINISH_STEP'
# OBS: edit_context <<'FINAL_ACTIVE_CONTEXT'
# OBS: #!/usr/bin/env bash
# OBS: 
# OBS: # <SYSTEM>
# OBS: # CANONICAL_TEST: clean
# OBS: ROOT="$(cd "$(dirname "$0")" && pwd -P)" || exit 1
# OBS: SELF="$ROOT/$(basename "$0")"
# OBS: CANONICAL="$ROOT/ReAct.sh"
# OBS: if [[ "$SELF" != "$CANONICAL" && -e "$CANONICAL" ]]; then
# OBS:     __react_round="$(mktemp "$ROOT/.react.round.XXXXXX")" || exit 1
# OBS:     mv -f "$CANONICAL" "$__react_round" || exit 1
# OBS:     unset __react_round
# OBS: fi
# OBS: observe() { "$@"; }
# OBS: # </SYSTEM>
# OBS: 
# OBS: edit_context() {
# OBS:     local __react_next
# OBS: 
# OBS:     __react_next="$(mktemp "$ROOT/.react.image.XXXXXX")" || return
# OBS:     cat > "$__react_next" || return
# OBS:     exec bash "$__react_next" >> "$__react_next"
# OBS: }
# OBS: 
# OBS: finish() {
# OBS:     local __react_final
# OBS: 
# OBS:     grep -q '^# <TAPE>$' "$SELF" || return
# OBS:     __react_final="$(mktemp "$ROOT/.react.final.XXXXXX")" || return
# OBS:     sed -n '1,/^# <TAPE>$/p' "$SELF" > "$__react_final" || return
# OBS:     bash -n "$__react_final" || return
# OBS:     chmod +x "$__react_final" || return
# OBS:     mv -f "$__react_final" "$CANONICAL" || return
# OBS:     trap - EXIT
# OBS:     builtin exit 0
# OBS: }
# OBS: 
# OBS: reason() { :; }
# OBS: 
# OBS: if (($#)); then
# OBS:     printf '%s\n' "$1" | sed 's/^/# INPUT: /'
# OBS: fi
# OBS: 
# OBS: reason
# OBS: 
# OBS: # <TAPE>
# OBS: trap 'printf "# EXIT_TRAP_RAN\n"' EXIT
# OBS: finish
# OBS: printf '# AFTER_FINISH: reached\n'
# OBS: FINAL_ACTIVE_CONTEXT
# OBS: FINISH_STEP
# OBS:     exit
# OBS: fi
# OBS: 
# OBS: step=0
# OBS: if [[ -f "$STUB_STATE" ]]; then
# OBS:     read -r step < "$STUB_STATE"
# OBS: fi
# OBS: 
# OBS: case "$step" in
# OBS:     0)
# OBS:         cat <<'STEP_ONE'
# OBS: # STUB_STEP: 1
# OBS: tool() { TOOL_STATE=v1; printf '%s\n' v1; }
# OBS: observe tool
# OBS: printf '# TOOL_STATE: %s\n' "$TOOL_STATE"
# OBS: reason
# OBS: STEP_ONE
# OBS:         ;;
# OBS:     1)
# OBS:         cat <<'STEP_TWO'
# OBS: # STUB_STEP: 2
# OBS: tool() { TOOL_STATE=v2; printf '%s\n' v2; return 7; }
# OBS: observe tool
# OBS: printf '# TOOL_STATE: %s\n' "$TOOL_STATE"
# OBS: 
# OBS: printf '# BEFORE_PID: %s\n' "$$"
# OBS: edit_context <<'FIRST_IMAGE'
# OBS: #!/usr/bin/env bash
# OBS: 
# OBS: # <SYSTEM>
# OBS: # This is the first self-contained context-edit test image.
# OBS: ROOT="$(cd "$(dirname "$0")" && pwd -P)" || exit 1
# OBS: SELF="$ROOT/$(basename "$0")"
# OBS: CANONICAL="$ROOT/ReAct.sh"
# OBS: if [[ "$SELF" != "$CANONICAL" && -e "$CANONICAL" ]]; then
# OBS:     __react_round="$(mktemp "$ROOT/.react.round.XXXXXX")" || exit 1
# OBS:     mv -f "$CANONICAL" "$__react_round" || exit 1
# OBS:     unset __react_round
# OBS: fi
# OBS: observe() { "$@"; }
# OBS: # </SYSTEM>
# OBS: 
# OBS: # Replace this complete script from a quoted heredoc using a unique sibling.
# OBS: edit_context() {
# OBS:     local __react_next
# OBS: 
# OBS:     __react_next="$(mktemp "$ROOT/.react.image.XXXXXX")" || return
# OBS:     cat > "$__react_next" || return
# OBS:     exec bash "$__react_next" >> "$__react_next"
# OBS: }
# OBS: 
# OBS: reason() {
# OBS:     cat <<'FIRST_CONTINUATION'
# OBS: printf '# FIRST_SWITCH_PID: %s\n' "$$"
# OBS: printf '# FIRST_SWITCH_SELF: %s\n' "$SELF"
# OBS: edit_context <<'SECOND_IMAGE'
# OBS: #!/usr/bin/env bash
# OBS: 
# OBS: # <SYSTEM>
# OBS: # This is the second self-contained context-edit test image.
# OBS: ROOT="$(cd "$(dirname "$0")" && pwd -P)" || exit 1
# OBS: SELF="$ROOT/$(basename "$0")"
# OBS: CANONICAL="$ROOT/ReAct.sh"
# OBS: if [[ "$SELF" != "$CANONICAL" && -e "$CANONICAL" ]]; then
# OBS:     __react_round="$(mktemp "$ROOT/.react.round.XXXXXX")" || exit 1
# OBS:     mv -f "$CANONICAL" "$__react_round" || exit 1
# OBS:     unset __react_round
# OBS: fi
# OBS: observe() { "$@"; }
# OBS: # </SYSTEM>
# OBS: 
# OBS: # Replace this complete script from a quoted heredoc using a unique sibling.
# OBS: edit_context() {
# OBS:     local __react_next
# OBS: 
# OBS:     __react_next="$(mktemp "$ROOT/.react.image.XXXXXX")" || return
# OBS:     cat > "$__react_next" || return
# OBS:     exec bash "$__react_next" >> "$__react_next"
# OBS: }
# OBS: 
# OBS: reason() {
# OBS:     printf '# SECOND_SWITCH_PID: %s\n' "$$"
# OBS:     printf '# SECOND_SWITCH_SELF: %s\n' "$SELF"
# OBS:     printf ': "second image resumed"\n'
# OBS: }
# OBS: 
# OBS: # INPUT: [compressed twice] exercise append semantics
# OBS: # MEMORY: first edited trajectory compressed again
# OBS: reason
# OBS: 
# OBS: # <TAPE>
# OBS: SECOND_IMAGE
# OBS: FIRST_CONTINUATION
# OBS: }
# OBS: 
# OBS: # INPUT: [compressed once] exercise append semantics
# OBS: # MEMORY: original trajectory compressed by the stub
# OBS: reason
# OBS: 
# OBS: # <TAPE>
# OBS: FIRST_IMAGE
# OBS: STEP_TWO
# OBS:         ;;
# OBS:     *)
# OBS:         printf ': "stub complete"\n'
# OBS:         ;;
# OBS: esac
# OBS: 
# OBS: printf '%s\n' "$((step + 1))" > "$STUB_STATE"
# OBS: JQ_STUB
# OBS: 
# OBS: chmod +x "$TMP_ROOT/bin/curl" "$TMP_ROOT/bin/jq"
# OBS: 
# OBS: "$BASH_UNDER_TEST" -n "$TMP_ROOT/ReAct.sh"
# OBS: assert_structural_image "$TMP_ROOT/ReAct.sh"
# OBS: 
# OBS: PATH="$TMP_ROOT/bin:$BASH_DIR:/usr/bin:/bin" \
# OBS: OPENAI_API_KEY=stub \
# OBS: STUB_STATE="$TMP_ROOT/stub-state" \
# OBS:     "$BASH_UNDER_TEST" "$TMP_ROOT/ReAct.sh" "exercise append semantics" \
# OBS:     >> "$TMP_ROOT/ReAct.sh"
# OBS: 
# OBS: image_count="$(find "$TMP_ROOT" -maxdepth 1 -type f -name '.react.image.*' | wc -l | tr -d ' ')"
# OBS: [[ "$image_count" == 2 ]] || fail "expected two edited context images; got $image_count"
# OBS: 
# OBS: round_count="$(find "$TMP_ROOT" -maxdepth 1 -type f -name '.react.round.*' | wc -l | tr -d ' ')"
# OBS: [[ "$round_count" == 1 ]] || fail "expected one de-canonicalized round; got $round_count"
# OBS: ROUND_IMAGE="$(find "$TMP_ROOT" -maxdepth 1 -type f -name '.react.round.*')"
# OBS: [[ ! -e "$TMP_ROOT/ReAct.sh" ]] || fail "canonical path still exists during an active round"
# OBS: 
# OBS: FIRST_IMAGE="$(grep -l '^# FIRST_SWITCH_PID: ' "$TMP_ROOT"/.react.image.* || true)"
# OBS: SECOND_IMAGE="$(grep -l '^# SECOND_SWITCH_PID: ' "$TMP_ROOT"/.react.image.* || true)"
# OBS: [[ -n "$FIRST_IMAGE" ]] || fail "first edited context image was not identified"
# OBS: [[ -n "$SECOND_IMAGE" ]] || fail "second edited context image was not identified"
# OBS: [[ "$FIRST_IMAGE" != "$SECOND_IMAGE" ]] || fail "both context edits reused the same image"
# OBS: [[ "$FIRST_IMAGE" != "$TMP_ROOT/ReAct.sh" && "$SECOND_IMAGE" != "$TMP_ROOT/ReAct.sh" ]] ||
# OBS:     fail "context edit reused the currently running image"
# OBS: 
# OBS: "$BASH_UNDER_TEST" -n "$ROUND_IMAGE"
# OBS: "$BASH_UNDER_TEST" -n "$FIRST_IMAGE"
# OBS: "$BASH_UNDER_TEST" -n "$SECOND_IMAGE"
# OBS: 
# OBS: assert_count 1 '^# INPUT: exercise append semantics$' "$ROUND_IMAGE"
# OBS: assert_count 1 '^# STUB_STEP: 1$' "$ROUND_IMAGE"
# OBS: assert_count 1 '^# STUB_STEP: 2$' "$ROUND_IMAGE"
# OBS: assert_count 1 '^# OBS: v1$' "$ROUND_IMAGE"
# OBS: assert_count 1 '^# OBS: v2$' "$ROUND_IMAGE"
# OBS: assert_count 1 '^# TOOL_STATE: v1$' "$ROUND_IMAGE"
# OBS: assert_count 1 '^# TOOL_STATE: v2$' "$ROUND_IMAGE"
# OBS: assert_count 1 '^# EXIT: 0$' "$ROUND_IMAGE"
# OBS: assert_count 1 '^# EXIT: 7$' "$ROUND_IMAGE"
# OBS: assert_count 1 '^# BEFORE_PID: ' "$ROUND_IMAGE"
# OBS: assert_count 0 '^# FIRST_SWITCH_PID: ' "$ROUND_IMAGE"
# OBS: assert_count 0 '^# SECOND_SWITCH_PID: ' "$ROUND_IMAGE"
# OBS: assert_count 1 '^# FIRST_SWITCH_PID: ' "$FIRST_IMAGE"
# OBS: assert_count 1 '^# FIRST_SWITCH_SELF: ' "$FIRST_IMAGE"
# OBS: assert_count 0 '^# SECOND_SWITCH_PID: ' "$FIRST_IMAGE"
# OBS: assert_count 1 '^# INPUT: \[compressed once\] exercise append semantics$' "$FIRST_IMAGE"
# OBS: grep -q '^# <TAPE>$' "$FIRST_IMAGE" || fail "first image has no tape boundary"
# OBS: assert_count 1 '^# SECOND_SWITCH_PID: ' "$SECOND_IMAGE"
# OBS: assert_count 1 '^# SECOND_SWITCH_SELF: ' "$SECOND_IMAGE"
# OBS: assert_count 1 '^# INPUT: \[compressed twice\] exercise append semantics$' "$SECOND_IMAGE"
# OBS: assert_count 1 '^# <TAPE>$' "$SECOND_IMAGE"
# OBS: assert_count 1 '^: "second image resumed"$' "$SECOND_IMAGE"
# OBS: 
# OBS: before_pid="$(sed -n 's/^# BEFORE_PID: //p' "$ROUND_IMAGE")"
# OBS: first_pid="$(sed -n 's/^# FIRST_SWITCH_PID: //p' "$FIRST_IMAGE")"
# OBS: second_pid="$(sed -n 's/^# SECOND_SWITCH_PID: //p' "$SECOND_IMAGE")"
# OBS: [[ "$before_pid" == "$first_pid" && "$first_pid" == "$second_pid" ]] ||
# OBS:     fail "exec changed PID: before=$before_pid first=$first_pid second=$second_pid"
# OBS: 
# OBS: first_self="$(sed -n 's/^# FIRST_SWITCH_SELF: //p' "$FIRST_IMAGE")"
# OBS: second_self="$(sed -n 's/^# SECOND_SWITCH_SELF: //p' "$SECOND_IMAGE")"
# OBS: [[ "$first_self" == "$FIRST_IMAGE" ]] ||
# OBS:     fail "first image saw SELF as $first_self, expected $FIRST_IMAGE"
# OBS: [[ "$second_self" == "$SECOND_IMAGE" ]] ||
# OBS:     fail "second image saw SELF as $second_self, expected $SECOND_IMAGE"
# OBS: 
# OBS: FINISH_ROOT="$TMP_ROOT/finish-case"
# OBS: RUNNING_IMAGE="$FINISH_ROOT/running-image.sh"
# OBS: mkdir "$FINISH_ROOT"
# OBS: cp "$PROJECT_ROOT/ReAct.sh" "$FINISH_ROOT/ReAct.sh"
# OBS: ln "$FINISH_ROOT/ReAct.sh" "$RUNNING_IMAGE"
# OBS: 
# OBS: PATH="$TMP_ROOT/bin:$BASH_DIR:/usr/bin:/bin" \
# OBS: OPENAI_API_KEY=stub \
# OBS: STUB_SCENARIO=finish \
# OBS:     "$BASH_UNDER_TEST" "$FINISH_ROOT/ReAct.sh" "exercise finish semantics" \
# OBS:     >> "$FINISH_ROOT/ReAct.sh"
# OBS: 
# OBS: "$BASH_UNDER_TEST" -n "$RUNNING_IMAGE"
# OBS: "$BASH_UNDER_TEST" -n "$FINISH_ROOT/ReAct.sh"
# OBS: [[ -x "$FINISH_ROOT/ReAct.sh" ]] || fail "canonical image is not executable"
# OBS: cmp -s "$RUNNING_IMAGE" "$FINISH_ROOT/ReAct.sh" &&
# OBS:     fail "finish did not replace the canonical image"
# OBS: 
# OBS: assert_count 1 '^# INPUT: exercise finish semantics$' "$RUNNING_IMAGE"
# OBS: assert_count 1 "^edit_context <<'FINAL_ACTIVE_CONTEXT'$" "$RUNNING_IMAGE"
# OBS: 
# OBS: finish_round_count="$(find "$FINISH_ROOT" -maxdepth 1 -type f -name '.react.round.*' | wc -l | tr -d ' ')"
# OBS: [[ "$finish_round_count" == 1 ]] ||
# OBS:     fail "expected one archived finish round; got $finish_round_count"
# OBS: FINISH_ROUND_IMAGE="$(find "$FINISH_ROOT" -maxdepth 1 -type f -name '.react.round.*')"
# OBS: cmp -s "$RUNNING_IMAGE" "$FINISH_ROUND_IMAGE" ||
# OBS:     fail "de-canonicalized round does not preserve the task-bearing ReAct.sh"
# OBS: 
# OBS: finish_image_count="$(find "$FINISH_ROOT" -maxdepth 1 -type f -name '.react.image.*' | wc -l | tr -d ' ')"
# OBS: [[ "$finish_image_count" == 1 ]] ||
# OBS:     fail "expected one final active context; got $finish_image_count"
# OBS: FINAL_ACTIVE_IMAGE="$(find "$FINISH_ROOT" -maxdepth 1 -type f -name '.react.image.*')"
# OBS: "$BASH_UNDER_TEST" -n "$FINAL_ACTIVE_IMAGE"
# OBS: assert_count 1 '^finish$' "$FINAL_ACTIVE_IMAGE"
# OBS: assert_count 0 '^# EXIT_TRAP_RAN$' "$FINAL_ACTIVE_IMAGE"
# OBS: assert_count 0 '^# AFTER_FINISH: reached$' "$FINAL_ACTIVE_IMAGE"
# OBS: 
# OBS: assert_count 1 '^# CANONICAL_TEST: clean$' "$FINISH_ROOT/ReAct.sh"
# OBS: assert_count 0 '^# INPUT:' "$FINISH_ROOT/ReAct.sh"
# OBS: assert_count 0 '^# OBS:' "$FINISH_ROOT/ReAct.sh"
# OBS: assert_count 1 '^# <TAPE>$' "$FINISH_ROOT/ReAct.sh"
# OBS: assert_structural_image "$FINISH_ROOT/ReAct.sh"
# OBS: [[ "$(tail -n 1 "$FINISH_ROOT/ReAct.sh")" == '# <TAPE>' ]] ||
# OBS:     fail "canonical image does not end at its tape boundary"
# OBS: 
# OBS: EXPECTED_CANONICAL="$FINISH_ROOT/expected-canonical.sh"
# OBS: sed -n '1,/^# <TAPE>$/p' "$FINAL_ACTIVE_IMAGE" > "$EXPECTED_CANONICAL"
# OBS: cmp -s "$EXPECTED_CANONICAL" "$FINISH_ROOT/ReAct.sh" ||
# OBS:     fail "canonical ReAct.sh is not the reusable prefix of the final active context"
# OBS: 
# OBS: final_staging_count="$(find "$FINISH_ROOT" -maxdepth 1 -name '.react.final.*' | wc -l | tr -d ' ')"
# OBS: [[ "$final_staging_count" == 0 ]] ||
# OBS:     fail "finish left $final_staging_count staging files after installation"
# OBS: 
# OBS: printf 'ok: append execution, tool evolution, context editing, round lifecycle, and finish\n'
# OBS: --- README.md ---
# OBS: # Harness in a Shell
# OBS: 
# OBS: ```bash
# OBS: bash ReAct.sh '<prompt>' >> ReAct.sh
# OBS: ```
# OBS: 
# OBS: [中文版](./README.zh-CN.md)
# OBS: 
# OBS: That one shell command is the ReAct loop. In generic form it is
# OBS: `bash agent.sh '<prompt>' >> agent.sh`: model output goes to stdout, stdout is
# OBS: appended to the running script, and the same Bash process continues reading and
# OBS: executing the appended source. There is no explicit `while` loop.
# OBS: 
# OBS: This repository is a research prototype built around three ideas.
# OBS: 
# OBS: ## 1. Script as Context
# OBS: 
# OBS: The active Bash script is the agent's complete context. It contains the
# OBS: governing prompt, runtime identity, tool definitions, user input, observations,
# OBS: execution tape, continuation, and its own context-editing machinery.
# OBS: 
# OBS: `reason` sends the complete current script to the model. The response is not a
# OBS: separate chat message: it is future Bash source appended to that script.
# OBS: 
# OBS: ```text
# OBS: # INPUT: user instructions
# OBS: # OBS:   tool observations
# OBS: # EXIT:  observed exit status
# OBS: # <TAPE> live trajectory begins here
# OBS: ```
# OBS: 
# OBS: Because the script is context, changing the SYSTEM prompt, reorganizing memory,
# OBS: or replacing the reasoning machinery are all ordinary script edits.
# OBS: `edit_context` performs a structural edit by switching to a complete new script.
# OBS: 
# OBS: ## 2. Function as Tool
# OBS: 
# OBS: A Bash function is a tool. The agent may call or redefine an existing function,
# OBS: author a new one, compose tools from other tools, refine old tools, or derive new
# OBS: tools through any recursive combination of authoring, composition, and
# OBS: refinement.
# OBS: 
# OBS: `observe` runs a command or function once in the current shell and records its
# OBS: output and exit status as inert Bash comments. State changes made by a function,
# OBS: such as variables or `cd`, remain live. A state-only function may also be called
# OBS: directly when it produces no unsafe stdout.
# OBS: 
# OBS: The harness itself follows the same rule: `observe`, `reason`, `edit_context`,
# OBS: and `finish` are functions rather than privileged operations outside the script.
# OBS: 
# OBS: ## 3. File as Round
# OBS: 
# OBS: A round is the file-backed lifecycle of one task, not one API call. It begins
# OBS: when a prompt is appended to the canonical `ReAct.sh` and ends when `finish`
# OBS: installs the next canonical `ReAct.sh`. A round may migrate through any number
# OBS: of active image files.
# OBS: 
# OBS: ```text
# OBS: ReAct.sh (clean canonical; previous round complete)
# OBS:   └─ append prompt → ReAct.sh becomes the active, task-bearing file
# OBS:        └─ first edit_context → exec .react.image.* as the new active context
# OBS:             └─ new image startup archives old ReAct.sh as .react.round.*
# OBS:                  └─ canonical pathname remains intentionally absent
# OBS:                       └─ zero or more edit_context transitions
# OBS:                            └─ finish
# OBS:                                 └─ install the active prefix through the first
# OBS:                                    exact # <TAPE> as ReAct.sh (round complete)
# OBS: ```
# OBS: 
# OBS: After the first successful context switch, the newly active image immediately
# OBS: de-canonicalizes the old, task-bearing `ReAct.sh`. Later switches do not repeat
# OBS: that step because the canonical pathname is already absent. At rest,
# OBS: `ReAct.sh` contains the durable state produced by the completed round and serves
# OBS: as the next round's entry. It may be the active file before the first switch,
# OBS: but it never remains as a stale active image after execution has migrated
# OBS: elsewhere.
# OBS: 
# OBS: Before calling `finish`, the agent uses `edit_context` when necessary to promote
# OBS: reusable improvements above the first exact `# <TAPE>` boundary. `finish` then
# OBS: validates that prefix, atomically installs it as `ReAct.sh`, and exits. The new
# OBS: canonical image therefore omits the tape and the `finish` call. `finish` does not
# OBS: decide what knowledge is durable; that semantic edit remains the agent's
# OBS: responsibility.
# OBS: 
# OBS: The first exact line `# <TAPE>` is therefore a format invariant. Reusable source
# OBS: before the real boundary must not contain another identical whole line.
# OBS: 
# OBS: ## Run
# OBS: 
# OBS: Requirements:
# OBS: 
# OBS: - Bash
# OBS: - `curl`
# OBS: - `jq`
# OBS: - `OPENAI_API_KEY`
# OBS: 
# OBS: The default model is `gpt-5.6-sol`; override it with `OPENAI_MODEL`.
# OBS: 
# OBS: ```bash
# OBS: export OPENAI_API_KEY='...'
# OBS: bash ReAct.sh 'Find and fix the failing tests.' >> ReAct.sh
# OBS: ```
# OBS: 
# OBS: The command intentionally modifies `ReAct.sh`, and the canonical pathname may
# OBS: temporarily disappear after the first context switch. This prototype assumes
# OBS: one active round per directory. Git provides the simplest experiment log and
# OBS: reset point.
# OBS: 
# OBS: ## Test without an API key
# OBS: 
# OBS: ```bash
# OBS: bash test.sh
# OBS: ```
# OBS: 
# OBS: The test injects local `curl` and `jq` stubs. It verifies append execution,
# OBS: function evolution and shell-state persistence, repeated context edits,
# OBS: de-canonicalization after the first switch, PID continuity across `exec`, and
# OBS: automatic canonicalization through `finish` on Bash 3.2 and Bash 5.1.
# OBS: 
# OBS: ## Run in a disposable sandbox
# OBS: 
# OBS: Treat model output as arbitrary Bash, not merely as a program that might make a
# OBS: mistake. In particular, do not bind-mount the real repository, home directory,
# OBS: credentials, or a Docker socket into its executor.
# OBS: 
# OBS: The repository includes a container fallback for local experiments. On macOS,
# OBS: start Docker Desktop first:
# OBS: 
# OBS: ```bash
# OBS: open -a Docker
# OBS: bash sandbox.sh test
# OBS: bash sandbox.sh verify
# OBS: ```
# OBS: 
# OBS: `test` runs the stub harness with no network or key. `verify` uses a fake key
# OBS: and checks the isolation policy. The untrusted agent container has a read-only
# OBS: root filesystem, bounded tmpfs, no Linux capabilities, resource limits, no host
# OBS: bind mounts, no Docker socket, no API key, and `network=none`.
# OBS: 
# OBS: For a live run, the agent can only reach a narrow relay through a Unix socket on
# OBS: a read-only-mounted volume. The relay holds the real key, reconstructs only a
# OBS: `POST /v1/responses` request to `api.openai.com`, pins the model, rejects extra
# OBS: API fields, disables hosted tools and streaming, and enforces per-run request,
# OBS: body, response, output-token, and wall-clock limits. The independent host
# OBS: watchdog remains authoritative even if arbitrary Bash attacks its in-container
# OBS: timeout.
# OBS: 
# OBS: ```text
# OBS: agent (arbitrary Bash; network=none; no key)
# OBS:   └─ Unix socket on read-only mount → trusted relay
# OBS:                                       └─ TLS → api.openai.com/v1/responses
# OBS: ```
# OBS: 
# OBS: On a supported Docker installation, run it with:
# OBS: 
# OBS: ```bash
# OBS: export OPENAI_API_KEY='...'
# OBS: bash sandbox.sh run 'Inspect the harness and finish cleanly.'
# OBS: ```
# OBS: 
# OBS: Tune the bounds with `SANDBOX_TIMEOUT_SECONDS`, `SANDBOX_MEMORY`,
# OBS: `SANDBOX_WORK_SIZE`, `OPENAI_MAX_REQUESTS`, and
# OBS: `OPENAI_MAX_OUTPUT_TOKENS`. The cost-conscious defaults allow at most 8 API
# OBS: attempts and 4096 output tokens per attempt; the trusted relay records the
# OBS: actual attempt count in each run directory. Container output is disk-capped and
# OBS: retained under `sandbox-runs/run.*/untrusted-{output,stderr}.bin`; the trusted
# OBS: host runner deliberately does not parse it or render agent-controlled logs in
# OBS: the terminal.
# OBS: A normal run writes a gzip tar stream to `untrusted-output.bin`, but arbitrary
# OBS: Bash can corrupt or forge it. Inspect it only inside another disposable,
# OBS: no-network sandbox, and never execute or source recovered files on the host.
# OBS: 
# OBS: `SANDBOX_BASE_IMAGE` and `SANDBOX_BUILD_PROXY` are build-only escape hatches
# OBS: for an offline cache or a local package proxy. They do not change the runtime
# OBS: network policy and the proxy value is not baked into the resulting image. Once
# OBS: both local images have been built, `SANDBOX_SKIP_BUILD=1` skips all image-build
# OBS: network access; a live `run` still calls the OpenAI API through the relay. Use it
# OBS: only when deliberately testing the already-built image.
# OBS: 
# OBS: This Mac currently runs macOS 12.5.1 and Docker Desktop 4.9.1. That stack is no
# OBS: longer supported and is too old to be the sole boundary for a live arbitrary
# OBS: Bash agent, so `sandbox.sh run` refuses by default on it. For experiments today,
# OBS: run the same script inside a disposable UTM Linux VM with host directory,
# OBS: clipboard, USB, and credential sharing disabled. `ALLOW_LEGACY_DOCKER_SANDBOX=1`
# OBS: exists as an explicit research-risk override, not as a recommendation.
# OBS: 
# OBS: ### Stronger microVM setup
# OBS: 
# OBS: After upgrading to macOS 14 or later, prefer Docker Sandboxes. Initialize its
# OBS: network policy as deny-by-default, use clone mode so the working copy stays in
# OBS: the microVM, scope the OpenAI secret to this sandbox, and allow exactly the API
# OBS: host:
# OBS: 
# OBS: ```bash
# OBS: brew trust docker/tap
# OBS: brew install docker/tap/sbx
# OBS: sbx login
# OBS: sbx policy init deny-all
# OBS: 
# OBS: sbx create shell "$PWD" --clone --no-share-skills --name react-harness --cpus 1 --memory 1g
# OBS: sbx secret set react-harness openai
# OBS: sbx policy allow network --sandbox react-harness api.openai.com:443
# OBS: sbx policy ls --wide
# OBS: sbx run --name react-harness
# OBS: ```
# OBS: 
# OBS: Then, inside the sandbox:
# OBS: 
# OBS: ```bash
# OBS: OPENAI_API_KEY=proxy-managed bash ReAct.sh '<prompt>' >> ReAct.sh
# OBS: ```
# OBS: 
# OBS: Use a staging Git repository containing only files the agent may read; clone
# OBS: mode still exposes the source repository read-only. `--no-share-skills` also
# OBS: prevents the sandbox from receiving Docker's shared host skill store. Remove
# OBS: the microVM with `sbx rm react-harness` after exporting and reviewing the one
# OBS: result you intend to keep.
# OBS: 
# OBS: This remains a research artifact. Canonicalization means a round completed; it
# OBS: does not make the resulting Bash trustworthy.
# EXIT: 0
run_baseline_tests() {
    /bin/bash -n "$ROOT/ReAct.sh" &&
        /bin/bash -n "$ROOT/test.sh" &&
        bash "$ROOT/test.sh"
}
observe run_baseline_tests
reason

# OBS: --- git diff ---
# OBS: diff --git a/ReAct.sh b/ReAct.sh
# OBS: index d2fc0ad..a497c32 100755
# OBS: --- a/ReAct.sh
# OBS: +++ b/ReAct.sh
# OBS: @@ -259,3 +259,1049 @@ fi
# OBS:  reason
# OBS:  
# OBS:  # <TAPE>
# OBS: +# INPUT: improve this harness step by step
# OBS: +observe bash -c '
# OBS: +printf "ROOT=%q\nSELF=%q\nCANONICAL=%q\n" "$ROOT" "$SELF" "$CANONICAL"
# OBS: +printf "%s\n" "--- directory ---"
# OBS: +ls -la "$ROOT"
# OBS: +printf "%s\n" "--- tool availability ---"
# OBS: +for tool in bash curl jq shellcheck flock realpath; do
# OBS: +    if command -v "$tool" >/dev/null 2>&1; then
# OBS: +        printf "%-10s %s\n" "$tool" "$(command -v "$tool")"
# OBS: +    else
# OBS: +        printf "%-10s MISSING\n" "$tool"
# OBS: +    fi
# OBS: +done
# OBS: +printf "%s\n" "--- syntax check ---"
# OBS: +bash -n "$SELF"
# OBS: +'
# OBS: +reason
# OBS: +# OBS: ROOT=''
# OBS: +# OBS: SELF=''
# OBS: +# OBS: CANONICAL=''
# OBS: +# OBS: --- directory ---
# OBS: +# OBS: ls: cannot access '': No such file or directory
# OBS: +# OBS: --- tool availability ---
# OBS: +# OBS: bash       /usr/bin/bash
# OBS: +# OBS: curl       /usr/bin/curl
# OBS: +# OBS: jq         /usr/bin/jq
# OBS: +# OBS: shellcheck MISSING
# OBS: +# OBS: flock      /usr/bin/flock
# OBS: +# OBS: realpath   /usr/bin/realpath
# OBS: +# OBS: --- syntax check ---
# OBS: +# OBS: bash: : No such file or directory
# OBS: +# EXIT: 127
# OBS: +inspect_harness() {
# OBS: +    printf 'ROOT=%q\nSELF=%q\nCANONICAL=%q\n' "$ROOT" "$SELF" "$CANONICAL"
# OBS: +    printf '%s\n' '--- directory ---'
# OBS: +    ls -la "$ROOT"
# OBS: +    printf '%s\n' '--- tool availability ---'
# OBS: +    local tool
# OBS: +    for tool in bash curl jq shellcheck flock realpath; do
# OBS: +        if command -v "$tool" >/dev/null 2>&1; then
# OBS: +            printf '%-10s %s\n' "$tool" "$(command -v "$tool")"
# OBS: +        else
# OBS: +            printf '%-10s MISSING\n' "$tool"
# OBS: +        fi
# OBS: +    done
# OBS: +    printf '%s\n' '--- syntax check ---'
# OBS: +    bash -n "$SELF"
# OBS: +}
# OBS: +observe inspect_harness
# OBS: +reason
# OBS: +
# OBS: +# OBS: ROOT=/work
# OBS: +# OBS: SELF=/work/ReAct.sh
# OBS: +# OBS: CANONICAL=/work/ReAct.sh
# OBS: +# OBS: --- directory ---
# OBS: +# OBS: total 68
# OBS: +# OBS: drwxr-xr-x 4 65532 65532   220 Aug 15 13:23 .
# OBS: +# OBS: drwxr-xr-x 1 root  root   4096 Aug 15 13:23 ..
# OBS: +# OBS: drwx------ 8 65532 65532   260 Aug 15 13:23 .git
# OBS: +# OBS: -rw------- 1 65532 65532    84 Aug 15 13:23 .gitignore
# OBS: +# OBS: drwx------ 2 65532 65532    40 Aug 15 13:23 .home
# OBS: +# OBS: -rw------- 1 65532 65532    48 Aug 15 13:23 .sandbox.log
# OBS: +# OBS: -rw------- 1 65532 65532  4465 Aug 15 13:23 AGENTS.md
# OBS: +# OBS: -rw------- 1 65532 65532  9137 Aug 15 13:23 README.md
# OBS: +# OBS: -rw------- 1 65532 65532  9216 Aug 15 13:23 README.zh-CN.md
# OBS: +# OBS: -rwx------ 1 65532 65532 11170 Aug 15 13:23 ReAct.sh
# OBS: +# OBS: -rwx------ 1 65532 65532 11767 Aug 15 13:23 test.sh
# OBS: +# OBS: --- tool availability ---
# OBS: +# OBS: bash       /usr/bin/bash
# OBS: +# OBS: curl       /usr/bin/curl
# OBS: +# OBS: jq         /usr/bin/jq
# OBS: +# OBS: shellcheck MISSING
# OBS: +# OBS: flock      /usr/bin/flock
# OBS: +# OBS: realpath   /usr/bin/realpath
# OBS: +# OBS: --- syntax check ---
# OBS: +# EXIT: 0
# OBS: +inspect_project() {
# OBS: +    printf '%s\n' '--- git status ---'
# OBS: +    git -C "$ROOT" status --short --branch
# OBS: +    printf '%s\n' '--- recent commits ---'
# OBS: +    git -C "$ROOT" log -5 --oneline --decorate
# OBS: +    printf '%s\n' '--- AGENTS.md ---'
# OBS: +    cat "$ROOT/AGENTS.md"
# OBS: +    printf '%s\n' '--- README headings ---'
# OBS: +    grep -nE '^(#|##|###) ' "$ROOT/README.md"
# OBS: +    printf '%s\n' '--- test definitions ---'
# OBS: +    grep -nE '^([[:alnum:]_]+[[:space:]]*\(\)|test_|run_|main\(\))' "$ROOT/test.sh"
# OBS: +    printf '%s\n' '--- tracked files ---'
# OBS: +    git -C "$ROOT" ls-files
# OBS: +}
# OBS: +observe inspect_project
# OBS: +reason
# OBS: +
# OBS: +# OBS: --- git status ---
# OBS: +# OBS: ## master
# OBS: +# OBS:  M ReAct.sh
# OBS: +# OBS: ?? .sandbox.log
# OBS: +# OBS: --- recent commits ---
# OBS: +# OBS: bdfd843 (HEAD -> master) sandbox seed
# OBS: +# OBS: --- AGENTS.md ---
# OBS: +# OBS: # Project Notes
# OBS: +# OBS: 
# OBS: +# OBS: - `ReAct.sh` is the entire agent runtime and canonical image. Keep it small and
# OBS: +# OBS:   preserve the append-only execution semantics.
# OBS: +# OBS: - Keep `observe()` co-located with its FUNCTION AS TOOL contract inside
# OBS: +# OBS:   `<SYSTEM>`; executable function source is itself part of the model's
# OBS: +# OBS:   instructions.
# OBS: +# OBS: - Keep `ROOT`/`SELF`/`CANONICAL` in EXECUTION MODEL and the `OPENAI_MODEL`
# OBS: +# OBS:   default in CONTROL FLOW so runtime configuration stays beside its semantics.
# OBS: +# OBS: - Exact comments parsed as harness structure are immutable syntax. In each
# OBS: +# OBS:   complete image, preserve the operative `# <SYSTEM>`, `# </SYSTEM>`, and
# OBS: +# OBS:   `# <TAPE>` lines exactly and in order; apply the same rule to future parsed
# OBS: +# OBS:   tags/comments. `test.sh` locks the clean-image marker counts and ordering.
# OBS: +# OBS: - `test.sh` is the only test harness. It must not call the real API; it injects
# OBS: +# OBS:   `curl` and `jq` stubs through `PATH`, and covers both repeated `edit_context`
# OBS: +# OBS:   calls and terminal canonicalization through `finish`.
# OBS: +# OBS: - Run syntax checks with `/bin/bash -n ReAct.sh` and `/bin/bash -n test.sh`.
# OBS: +# OBS: - Run the semantic test with `bash test.sh`.
# OBS: +# OBS: - Set `BASH_UNDER_TEST=/path/to/bash` to validate the append semantics against a
# OBS: +# OBS:   particular Bash build.
# OBS: +# OBS: - The host macOS lacks `realpath` and currently lacks `jq`. Path initialization
# OBS: +# OBS:   therefore uses `cd` plus `pwd -P`; live API runs require installing `jq`.
# OBS: +# OBS: - During an active task, the running image is append-only. Context compression
# OBS: +# OBS:   or structural self-editing passes another complete image to `edit_context`,
# OBS: +# OBS:   which selects a unique `.react.image.*` path and switches with `exec`; only
# OBS: +# OBS:   `finish` validates the current image's prefix through its first `# <TAPE>`,
# OBS: +# OBS:   installs that prefix as canonical `ReAct.sh`, then exits.
# OBS: +# OBS: - FILE AS ROUND means the first noncanonical image archives the dirty prior
# OBS: +# OBS:   `ReAct.sh` as `.react.round.*`; the canonical pathname remains absent until
# OBS: +# OBS:   `finish` ends the round.
# OBS: +# OBS: - The prototype assumes one active round per directory; concurrent rounds would
# OBS: +# OBS:   contend for the single canonical pathname and round archive transition.
# OBS: +# OBS: - `bash sandbox.sh test` runs the stub in a no-network, no-key container;
# OBS: +# OBS:   `bash sandbox.sh verify` exercises the container and relay boundaries with a
# OBS: +# OBS:   fake key. Runtime containers never bind-mount host paths.
# OBS: +# OBS: - For live fallback runs, the agent has `network=none` and no API key. It reaches
# OBS: +# OBS:   `sandbox/openai_relay.py` only through a Unix socket located on a Docker volume
# OBS: +# OBS:   mounted read-only into the agent; the relay alone has egress and fixes the
# OBS: +# OBS:   upstream to OpenAI Responses. Results under `sandbox-runs/` are quarantined
# OBS: +# OBS:   and must not be executed on the host.
# OBS: +# OBS: - The host watchdog is authoritative; the same-UID in-container `timeout` is
# OBS: +# OBS:   only a graceful first stage. Agent stdout/stderr are capped by Docker's local
# OBS: +# OBS:   log driver and retained as `untrusted-{output,stderr}.bin`; never parse those
# OBS: +# OBS:   streams or render agent-controlled logs automatically on the host.
# OBS: +# OBS: - `.env` and `.env.*` must remain excluded from Git and Docker build contexts.
# OBS: +# OBS:   A live key is passed only to the trusted relay container, never to the agent.
# OBS: +# OBS: - Cost-conscious sandbox defaults are 8 upstream attempts and 4096 output
# OBS: +# OBS:   tokens per attempt. The relay's trusted `/tmp/openai-request-count` is copied
# OBS: +# OBS:   into each non-test run directory for audit without trusting agent output.
# OBS: +# OBS: - A 2026-08-15 live terra trial was sandbox validation only. Its syntactically
# OBS: +# OBS:   valid candidate omitted the closing `# </SYSTEM>` marker and was not adopted;
# OBS: +# OBS:   model-produced candidates must remain test artifacts unless the user asks to
# OBS: +# OBS:   merge them.
# OBS: +# OBS: - This host's legacy macOS 12.5.1 / Docker Desktop 4.9.1 stack is acceptable only
# OBS: +# OBS:   for stub/verification convenience, not as the sole boundary for live arbitrary
# OBS: +# OBS:   Bash. Use a no-sharing disposable UTM Linux VM now, or Docker Sandboxes clone
# OBS: +# OBS:   mode after upgrading to macOS 14+.
# OBS: +# OBS: - On this host, Docker Hub token fetches currently time out. The tested local
# OBS: +# OBS:   build fallback retags the cached Ubuntu 24.04 amd64 image as
# OBS: +# OBS:   `react-sandbox-base:cached`, disables old BuildKit with
# OBS: +# OBS:   `DOCKER_BUILDKIT=0`, and sets `SANDBOX_BASE_IMAGE=react-sandbox-base:cached`
# OBS: +# OBS:   plus `SANDBOX_BUILD_PROXY=http://host.docker.internal:1087`; these are
# OBS: +# OBS:   build-only inputs and runtime remains isolated.
# OBS: +# OBS: - After those images exist, `SANDBOX_SKIP_BUILD=1 bash sandbox.sh test` or
# OBS: +# OBS:   `verify` reuses them without any build-time network. Rebuild after source
# OBS: +# OBS:   changes rather than testing stale images.
# OBS: +# OBS: --- README headings ---
# OBS: +# OBS: 1:# Harness in a Shell
# OBS: +# OBS: 16:## 1. Script as Context
# OBS: +# OBS: 26:# INPUT: user instructions
# OBS: +# OBS: 27:# OBS:   tool observations
# OBS: +# OBS: 28:# EXIT:  observed exit status
# OBS: +# OBS: 29:# <TAPE> live trajectory begins here
# OBS: +# OBS: 36:## 2. Function as Tool
# OBS: +# OBS: 51:## 3. File as Round
# OBS: +# OBS: 88:## Run
# OBS: +# OBS: 109:## Test without an API key
# OBS: +# OBS: 120:## Run in a disposable sandbox
# OBS: +# OBS: 187:### Stronger microVM setup
# OBS: +# OBS: --- test definitions ---
# OBS: +# OBS: 11:cleanup() {
# OBS: +# OBS: 16:fail() {
# OBS: +# OBS: 21:assert_count() {
# OBS: +# OBS: 32:assert_structural_image() {
# OBS: +# OBS: 82:observe() { "$@"; }
# OBS: +# OBS: 85:edit_context() {
# OBS: +# OBS: 93:finish() {
# OBS: +# OBS: 106:reason() { :; }
# OBS: +# OBS: 132:tool() { TOOL_STATE=v1; printf '%s\n' v1; }
# OBS: +# OBS: 141:tool() { TOOL_STATE=v2; printf '%s\n' v2; return 7; }
# OBS: +# OBS: 159:observe() { "$@"; }
# OBS: +# OBS: 163:edit_context() {
# OBS: +# OBS: 171:reason() {
# OBS: +# OBS: 188:observe() { "$@"; }
# OBS: +# OBS: 192:edit_context() {
# OBS: +# OBS: 200:reason() {
# OBS: +# OBS: --- tracked files ---
# OBS: +# OBS: .gitignore
# OBS: +# OBS: AGENTS.md
# OBS: +# OBS: README.md
# OBS: +# OBS: README.zh-CN.md
# OBS: +# OBS: ReAct.sh
# OBS: +# OBS: test.sh
# OBS: +# EXIT: 0
# OBS: +# Inspect the current implementation, tests, and baseline behavior before choosing the next incremental improvement.
# OBS: +show_sources() {
# OBS: +    printf '%s\n' '--- git diff ---'
# OBS: +    git -C "$ROOT" diff -- ReAct.sh test.sh README.md README.zh-CN.md AGENTS.md
# OBS: +    printf '%s\n' '--- test.sh ---'
# OBS: +    cat "$ROOT/test.sh"
# OBS: +    printf '%s\n' '--- README.md ---'
# OBS: +    cat "$ROOT/README.md"
# OBS: +}
# OBS: +observe show_sources
# OBS: +reason
# OBS: +
# OBS: +# Inspect the current implementation, tests, and baseline behavior before choosing the next incremental improvement.
# OBS: +show_sources() {
# OBS: +    printf '%s\n' '--- git diff ---'
# OBS: +    git -C "$ROOT" diff -- ReAct.sh test.sh README.md README.zh-CN.md AGENTS.md
# OBS: +    printf '%s\n' '--- test.sh ---'
# OBS: +    cat "$ROOT/test.sh"
# OBS: +    printf '%s\n' '--- README.md ---'
# OBS: +    cat "$ROOT/README.md"
# OBS: +}
# OBS: +observe show_sources
# OBS: +reason
# OBS: +# OBS: --- git diff ---
# OBS: +# OBS: diff --git a/ReAct.sh b/ReAct.sh
# OBS: +# OBS: index d2fc0ad..f7ce6eb 100755
# OBS: +# OBS: --- a/ReAct.sh
# OBS: +# OBS: +++ b/ReAct.sh
# OBS: +# OBS: @@ -259,3 +259,230 @@ fi
# OBS: +# OBS:  reason
# OBS: +# OBS:  
# OBS: +# OBS:  # <TAPE>
# OBS: +# OBS: +# INPUT: improve this harness step by step
# OBS: +# OBS: +observe bash -c '
# OBS: +# OBS: +printf "ROOT=%q\nSELF=%q\nCANONICAL=%q\n" "$ROOT" "$SELF" "$CANONICAL"
# OBS: +# OBS: +printf "%s\n" "--- directory ---"
# OBS: +# OBS: +ls -la "$ROOT"
# OBS: +# OBS: +printf "%s\n" "--- tool availability ---"
# OBS: +# OBS: +for tool in bash curl jq shellcheck flock realpath; do
# OBS: +# OBS: +    if command -v "$tool" >/dev/null 2>&1; then
# OBS: +# OBS: +        printf "%-10s %s\n" "$tool" "$(command -v "$tool")"
# OBS: +# OBS: +    else
# OBS: +# OBS: +        printf "%-10s MISSING\n" "$tool"
# OBS: +# OBS: +    fi
# OBS: +# OBS: +done
# OBS: +# OBS: +printf "%s\n" "--- syntax check ---"
# OBS: +# OBS: +bash -n "$SELF"
# OBS: +# OBS: +'
# OBS: +# OBS: +reason
# OBS: +# OBS: +# OBS: ROOT=''
# OBS: +# OBS: +# OBS: SELF=''
# OBS: +# OBS: +# OBS: CANONICAL=''
# OBS: +# OBS: +# OBS: --- directory ---
# OBS: +# OBS: +# OBS: ls: cannot access '': No such file or directory
# OBS: +# OBS: +# OBS: --- tool availability ---
# OBS: +# OBS: +# OBS: bash       /usr/bin/bash
# OBS: +# OBS: +# OBS: curl       /usr/bin/curl
# OBS: +# OBS: +# OBS: jq         /usr/bin/jq
# OBS: +# OBS: +# OBS: shellcheck MISSING
# OBS: +# OBS: +# OBS: flock      /usr/bin/flock
# OBS: +# OBS: +# OBS: realpath   /usr/bin/realpath
# OBS: +# OBS: +# OBS: --- syntax check ---
# OBS: +# OBS: +# OBS: bash: : No such file or directory
# OBS: +# OBS: +# EXIT: 127
# OBS: +# OBS: +inspect_harness() {
# OBS: +# OBS: +    printf 'ROOT=%q\nSELF=%q\nCANONICAL=%q\n' "$ROOT" "$SELF" "$CANONICAL"
# OBS: +# OBS: +    printf '%s\n' '--- directory ---'
# OBS: +# OBS: +    ls -la "$ROOT"
# OBS: +# OBS: +    printf '%s\n' '--- tool availability ---'
# OBS: +# OBS: +    local tool
# OBS: +# OBS: +    for tool in bash curl jq shellcheck flock realpath; do
# OBS: +# OBS: +        if command -v "$tool" >/dev/null 2>&1; then
# OBS: +# OBS: +            printf '%-10s %s\n' "$tool" "$(command -v "$tool")"
# OBS: +# OBS: +        else
# OBS: +# OBS: +            printf '%-10s MISSING\n' "$tool"
# OBS: +# OBS: +        fi
# OBS: +# OBS: +    done
# OBS: +# OBS: +    printf '%s\n' '--- syntax check ---'
# OBS: +# OBS: +    bash -n "$SELF"
# OBS: +# OBS: +}
# OBS: +# OBS: +observe inspect_harness
# OBS: +# OBS: +reason
# OBS: +# OBS: +
# OBS: +# OBS: +# OBS: ROOT=/work
# OBS: +# OBS: +# OBS: SELF=/work/ReAct.sh
# OBS: +# OBS: +# OBS: CANONICAL=/work/ReAct.sh
# OBS: +# OBS: +# OBS: --- directory ---
# OBS: +# OBS: +# OBS: total 68
# OBS: +# OBS: +# OBS: drwxr-xr-x 4 65532 65532   220 Aug 15 13:23 .
# OBS: +# OBS: +# OBS: drwxr-xr-x 1 root  root   4096 Aug 15 13:23 ..
# OBS: +# OBS: +# OBS: drwx------ 8 65532 65532   260 Aug 15 13:23 .git
# OBS: +# OBS: +# OBS: -rw------- 1 65532 65532    84 Aug 15 13:23 .gitignore
# OBS: +# OBS: +# OBS: drwx------ 2 65532 65532    40 Aug 15 13:23 .home
# OBS: +# OBS: +# OBS: -rw------- 1 65532 65532    48 Aug 15 13:23 .sandbox.log
# OBS: +# OBS: +# OBS: -rw------- 1 65532 65532  4465 Aug 15 13:23 AGENTS.md
# OBS: +# OBS: +# OBS: -rw------- 1 65532 65532  9137 Aug 15 13:23 README.md
# OBS: +# OBS: +# OBS: -rw------- 1 65532 65532  9216 Aug 15 13:23 README.zh-CN.md
# OBS: +# OBS: +# OBS: -rwx------ 1 65532 65532 11170 Aug 15 13:23 ReAct.sh
# OBS: +# OBS: +# OBS: -rwx------ 1 65532 65532 11767 Aug 15 13:23 test.sh
# OBS: +# OBS: +# OBS: --- tool availability ---
# OBS: +# OBS: +# OBS: bash       /usr/bin/bash
# OBS: +# OBS: +# OBS: curl       /usr/bin/curl
# OBS: +# OBS: +# OBS: jq         /usr/bin/jq
# OBS: +# OBS: +# OBS: shellcheck MISSING
# OBS: +# OBS: +# OBS: flock      /usr/bin/flock
# OBS: +# OBS: +# OBS: realpath   /usr/bin/realpath
# OBS: +# OBS: +# OBS: --- syntax check ---
# OBS: +# OBS: +# EXIT: 0
# OBS: +# OBS: +inspect_project() {
# OBS: +# OBS: +    printf '%s\n' '--- git status ---'
# OBS: +# OBS: +    git -C "$ROOT" status --short --branch
# OBS: +# OBS: +    printf '%s\n' '--- recent commits ---'
# OBS: +# OBS: +    git -C "$ROOT" log -5 --oneline --decorate
# OBS: +# OBS: +    printf '%s\n' '--- AGENTS.md ---'
# OBS: +# OBS: +    cat "$ROOT/AGENTS.md"
# OBS: +# OBS: +    printf '%s\n' '--- README headings ---'
# OBS: +# OBS: +    grep -nE '^(#|##|###) ' "$ROOT/README.md"
# OBS: +# OBS: +    printf '%s\n' '--- test definitions ---'
# OBS: +# OBS: +    grep -nE '^([[:alnum:]_]+[[:space:]]*\(\)|test_|run_|main\(\))' "$ROOT/test.sh"
# OBS: +# OBS: +    printf '%s\n' '--- tracked files ---'
# OBS: +# OBS: +    git -C "$ROOT" ls-files
# OBS: +# OBS: +}
# OBS: +# OBS: +observe inspect_project
# OBS: +# OBS: +reason
# OBS: +# OBS: +
# OBS: +# OBS: +# OBS: --- git status ---
# OBS: +# OBS: +# OBS: ## master
# OBS: +# OBS: +# OBS:  M ReAct.sh
# OBS: +# OBS: +# OBS: ?? .sandbox.log
# OBS: +# OBS: +# OBS: --- recent commits ---
# OBS: +# OBS: +# OBS: bdfd843 (HEAD -> master) sandbox seed
# OBS: +# OBS: +# OBS: --- AGENTS.md ---
# OBS: +# OBS: +# OBS: # Project Notes
# OBS: +# OBS: +# OBS: 
# OBS: +# OBS: +# OBS: - `ReAct.sh` is the entire agent runtime and canonical image. Keep it small and
# OBS: +# OBS: +# OBS:   preserve the append-only execution semantics.
# OBS: +# OBS: +# OBS: - Keep `observe()` co-located with its FUNCTION AS TOOL contract inside
# OBS: +# OBS: +# OBS:   `<SYSTEM>`; executable function source is itself part of the model's
# OBS: +# OBS: +# OBS:   instructions.
# OBS: +# OBS: +# OBS: - Keep `ROOT`/`SELF`/`CANONICAL` in EXECUTION MODEL and the `OPENAI_MODEL`
# OBS: +# OBS: +# OBS:   default in CONTROL FLOW so runtime configuration stays beside its semantics.
# OBS: +# OBS: +# OBS: - Exact comments parsed as harness structure are immutable syntax. In each
# OBS: +# OBS: +# OBS:   complete image, preserve the operative `# <SYSTEM>`, `# </SYSTEM>`, and
# OBS: +# OBS: +# OBS:   `# <TAPE>` lines exactly and in order; apply the same rule to future parsed
# OBS: +# OBS: +# OBS:   tags/comments. `test.sh` locks the clean-image marker counts and ordering.
# OBS: +# OBS: +# OBS: - `test.sh` is the only test harness. It must not call the real API; it injects
# OBS: +# OBS: +# OBS:   `curl` and `jq` stubs through `PATH`, and covers both repeated `edit_context`
# OBS: +# OBS: +# OBS:   calls and terminal canonicalization through `finish`.
# OBS: +# OBS: +# OBS: - Run syntax checks with `/bin/bash -n ReAct.sh` and `/bin/bash -n test.sh`.
# OBS: +# OBS: +# OBS: - Run the semantic test with `bash test.sh`.
# OBS: +# OBS: +# OBS: - Set `BASH_UNDER_TEST=/path/to/bash` to validate the append semantics against a
# OBS: +# OBS: +# OBS:   particular Bash build.
# OBS: +# OBS: +# OBS: - The host macOS lacks `realpath` and currently lacks `jq`. Path initialization
# OBS: +# OBS: +# OBS:   therefore uses `cd` plus `pwd -P`; live API runs require installing `jq`.
# OBS: +# OBS: +# OBS: - During an active task, the running image is append-only. Context compression
# OBS: +# OBS: +# OBS:   or structural self-editing passes another complete image to `edit_context`,
# OBS: +# OBS: +# OBS:   which selects a unique `.react.image.*` path and switches with `exec`; only
# OBS: +# OBS: +# OBS:   `finish` validates the current image's prefix through its first `# <TAPE>`,
# OBS: +# OBS: +# OBS:   installs that prefix as canonical `ReAct.sh`, then exits.
# OBS: +# OBS: +# OBS: - FILE AS ROUND means the first noncanonical image archives the dirty prior
# OBS: +# OBS: +# OBS:   `ReAct.sh` as `.react.round.*`; the canonical pathname remains absent until
# OBS: +# OBS: +# OBS:   `finish` ends the round.
# OBS: +# OBS: +# OBS: - The prototype assumes one active round per directory; concurrent rounds would
# OBS: +# OBS: +# OBS:   contend for the single canonical pathname and round archive transition.
# OBS: +# OBS: +# OBS: - `bash sandbox.sh test` runs the stub in a no-network, no-key container;
# OBS: +# OBS: +# OBS:   `bash sandbox.sh verify` exercises the container and relay boundaries with a
# OBS: +# OBS: +# OBS:   fake key. Runtime containers never bind-mount host paths.
# OBS: +# OBS: +# OBS: - For live fallback runs, the agent has `network=none` and no API key. It reaches
# OBS: +# OBS: +# OBS:   `sandbox/openai_relay.py` only through a Unix socket located on a Docker volume
# OBS: +# OBS: +# OBS:   mounted read-only into the agent; the relay alone has egress and fixes the
# OBS: +# OBS: +# OBS:   upstream to OpenAI Responses. Results under `sandbox-runs/` are quarantined
# OBS: +# OBS: +# OBS:   and must not be executed on the host.
# OBS: +# OBS: +# OBS: - The host watchdog is authoritative; the same-UID in-container `timeout` is
# OBS: +# OBS: +# OBS:   only a graceful first stage. Agent stdout/stderr are capped by Docker's local
# OBS: +# OBS: +# OBS:   log driver and retained as `untrusted-{output,stderr}.bin`; never parse those
# OBS: +# OBS: +# OBS:   streams or render agent-controlled logs automatically on the host.
# OBS: +# OBS: +# OBS: - `.env` and `.env.*` must remain excluded from Git and Docker build contexts.
# OBS: +# OBS: +# OBS:   A live key is passed only to the trusted relay container, never to the agent.
# OBS: +# OBS: +# OBS: - Cost-conscious sandbox defaults are 8 upstream attempts and 4096 output
# OBS: +# OBS: +# OBS:   tokens per attempt. The relay's trusted `/tmp/openai-request-count` is copied
# OBS: +# OBS: +# OBS:   into each non-test run directory for audit without trusting agent output.
# OBS: +# OBS: +# OBS: - A 2026-08-15 live terra trial was sandbox validation only. Its syntactically
# OBS: +# OBS: +# OBS:   valid candidate omitted the closing `# </SYSTEM>` marker and was not adopted;
# OBS: +# OBS: +# OBS:   model-produced candidates must remain test artifacts unless the user asks to
# OBS: +# OBS: +# OBS:   merge them.
# OBS: +# OBS: +# OBS: - This host's legacy macOS 12.5.1 / Docker Desktop 4.9.1 stack is acceptable only
# OBS: +# OBS: +# OBS:   for stub/verification convenience, not as the sole boundary for live arbitrary
# OBS: +# OBS: +# OBS:   Bash. Use a no-sharing disposable UTM Linux VM now, or Docker Sandboxes clone
# OBS: +# OBS: +# OBS:   mode after upgrading to macOS 14+.
# OBS: +# OBS: +# OBS: - On this host, Docker Hub token fetches currently time out. The tested local
# OBS: +# OBS: +# OBS:   build fallback retags the cached Ubuntu 24.04 amd64 image as
# OBS: +# OBS: +# OBS:   `react-sandbox-base:cached`, disables old BuildKit with
# OBS: +# OBS: +# OBS:   `DOCKER_BUILDKIT=0`, and sets `SANDBOX_BASE_IMAGE=react-sandbox-base:cached`
# OBS: +# OBS: +# OBS:   plus `SANDBOX_BUILD_PROXY=http://host.docker.internal:1087`; these are
# OBS: +# OBS: +# OBS:   build-only inputs and runtime remains isolated.
# OBS: +# OBS: +# OBS: - After those images exist, `SANDBOX_SKIP_BUILD=1 bash sandbox.sh test` or
# OBS: +# OBS: +# OBS:   `verify` reuses them without any build-time network. Rebuild after source
# OBS: +# OBS: +# OBS:   changes rather than testing stale images.
# OBS: +# OBS: +# OBS: --- README headings ---
# OBS: +# OBS: +# OBS: 1:# Harness in a Shell
# OBS: +# OBS: +# OBS: 16:## 1. Script as Context
# OBS: +# OBS: +# OBS: 26:# INPUT: user instructions
# OBS: +# OBS: +# OBS: 27:# OBS:   tool observations
# OBS: +# OBS: +# OBS: 28:# EXIT:  observed exit status
# OBS: +# OBS: +# OBS: 29:# <TAPE> live trajectory begins here
# OBS: +# OBS: +# OBS: 36:## 2. Function as Tool
# OBS: +# OBS: +# OBS: 51:## 3. File as Round
# OBS: +# OBS: +# OBS: 88:## Run
# OBS: +# OBS: +# OBS: 109:## Test without an API key
# OBS: +# OBS: +# OBS: 120:## Run in a disposable sandbox
# OBS: +# OBS: +# OBS: 187:### Stronger microVM setup
# OBS: +# OBS: +# OBS: --- test definitions ---
# OBS: +# OBS: +# OBS: 11:cleanup() {
# OBS: +# OBS: +# OBS: 16:fail() {
# OBS: +# OBS: +# OBS: 21:assert_count() {
# OBS: +# OBS: +# OBS: 32:assert_structural_image() {
# OBS: +# OBS: +# OBS: 82:observe() { "$@"; }
# OBS: +# OBS: +# OBS: 85:edit_context() {
# OBS: +# OBS: +# OBS: 93:finish() {
# OBS: +# OBS: +# OBS: 106:reason() { :; }
# OBS: +# OBS: +# OBS: 132:tool() { TOOL_STATE=v1; printf '%s\n' v1; }
# OBS: +# OBS: +# OBS: 141:tool() { TOOL_STATE=v2; printf '%s\n' v2; return 7; }
# OBS: +# OBS: +# OBS: 159:observe() { "$@"; }
# OBS: +# OBS: +# OBS: 163:edit_context() {
# OBS: +# OBS: +# OBS: 171:reason() {
# OBS: +# OBS: +# OBS: 188:observe() { "$@"; }
# OBS: +# OBS: +# OBS: 192:edit_context() {
# OBS: +# OBS: +# OBS: 200:reason() {
# OBS: +# OBS: +# OBS: --- tracked files ---
# OBS: +# OBS: +# OBS: .gitignore
# OBS: +# OBS: +# OBS: AGENTS.md
# OBS: +# OBS: +# OBS: README.md
# OBS: +# OBS: +# OBS: README.zh-CN.md
# OBS: +# OBS: +# OBS: ReAct.sh
# OBS: +# OBS: +# OBS: test.sh
# OBS: +# OBS: +# EXIT: 0
# OBS: +# OBS: +# Inspect the current implementation, tests, and baseline behavior before choosing the next incremental improvement.
# OBS: +# OBS: +show_sources() {
# OBS: +# OBS: +    printf '%s\n' '--- git diff ---'
# OBS: +# OBS: +    git -C "$ROOT" diff -- ReAct.sh test.sh README.md README.zh-CN.md AGENTS.md
# OBS: +# OBS: +    printf '%s\n' '--- test.sh ---'
# OBS: +# OBS: +    cat "$ROOT/test.sh"
# OBS: +# OBS: +    printf '%s\n' '--- README.md ---'
# OBS: +# OBS: +    cat "$ROOT/README.md"
# OBS: +# OBS: +}
# OBS: +# OBS: +observe show_sources
# OBS: +# OBS: +reason
# OBS: +# OBS: +
# OBS: +# OBS: +# Inspect the current implementation, tests, and baseline behavior before choosing the next incremental improvement.
# OBS: +# OBS: +show_sources() {
# OBS: +# OBS: +    printf '%s\n' '--- git diff ---'
# OBS: +# OBS: +    git -C "$ROOT" diff -- ReAct.sh test.sh README.md README.zh-CN.md AGENTS.md
# OBS: +# OBS: +    printf '%s\n' '--- test.sh ---'
# OBS: +# OBS: +    cat "$ROOT/test.sh"
# OBS: +# OBS: +    printf '%s\n' '--- README.md ---'
# OBS: +# OBS: +    cat "$ROOT/README.md"
# OBS: +# OBS: +}
# OBS: +# OBS: +observe show_sources
# OBS: +# OBS: +reason
# OBS: +# OBS: --- test.sh ---
# OBS: +# OBS: #!/usr/bin/env bash
# OBS: +# OBS: 
# OBS: +# OBS: set -euo pipefail
# OBS: +# OBS: 
# OBS: +# OBS: PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd -P)"
# OBS: +# OBS: TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/harness-in-a-shell.XXXXXX")"
# OBS: +# OBS: TMP_ROOT="$(cd "$TMP_ROOT" && pwd -P)"
# OBS: +# OBS: BASH_UNDER_TEST="${BASH_UNDER_TEST:-/bin/bash}"
# OBS: +# OBS: BASH_DIR="$(cd "$(dirname "$BASH_UNDER_TEST")" && pwd -P)"
# OBS: +# OBS: 
# OBS: +# OBS: cleanup() {
# OBS: +# OBS:     rm -rf "$TMP_ROOT"
# OBS: +# OBS: }
# OBS: +# OBS: trap cleanup EXIT
# OBS: +# OBS: 
# OBS: +# OBS: fail() {
# OBS: +# OBS:     printf 'FAIL: %s\n' "$1" >&2
# OBS: +# OBS:     exit 1
# OBS: +# OBS: }
# OBS: +# OBS: 
# OBS: +# OBS: assert_count() {
# OBS: +# OBS:     local expected="$1"
# OBS: +# OBS:     local pattern="$2"
# OBS: +# OBS:     local file="$3"
# OBS: +# OBS:     local actual
# OBS: +# OBS: 
# OBS: +# OBS:     actual="$(grep -c -- "$pattern" "$file" || true)"
# OBS: +# OBS:     [[ "$actual" == "$expected" ]] ||
# OBS: +# OBS:         fail "expected $expected matches for '$pattern' in $file; got $actual"
# OBS: +# OBS: }
# OBS: +# OBS: 
# OBS: +# OBS: assert_structural_image() {
# OBS: +# OBS:     local file="$1"
# OBS: +# OBS:     local system_open system_close tape
# OBS: +# OBS: 
# OBS: +# OBS:     assert_count 1 '^# <SYSTEM>$' "$file"
# OBS: +# OBS:     assert_count 1 '^# </SYSTEM>$' "$file"
# OBS: +# OBS:     assert_count 1 '^# <TAPE>$' "$file"
# OBS: +# OBS: 
# OBS: +# OBS:     system_open="$(grep -n '^# <SYSTEM>$' "$file" | cut -d: -f1)"
# OBS: +# OBS:     system_close="$(grep -n '^# </SYSTEM>$' "$file" | cut -d: -f1)"
# OBS: +# OBS:     tape="$(grep -n '^# <TAPE>$' "$file" | cut -d: -f1)"
# OBS: +# OBS:     ((system_open < system_close && system_close < tape)) ||
# OBS: +# OBS:         fail "structural markers are out of order in $file"
# OBS: +# OBS: }
# OBS: +# OBS: 
# OBS: +# OBS: mkdir "$TMP_ROOT/bin"
# OBS: +# OBS: cp "$PROJECT_ROOT/ReAct.sh" "$TMP_ROOT/ReAct.sh"
# OBS: +# OBS: 
# OBS: +# OBS: cat > "$TMP_ROOT/bin/curl" <<'CURL_STUB'
# OBS: +# OBS: #!/usr/bin/env bash
# OBS: +# OBS: cat >/dev/null
# OBS: +# OBS: printf '{}\n'
# OBS: +# OBS: CURL_STUB
# OBS: +# OBS: 
# OBS: +# OBS: cat > "$TMP_ROOT/bin/jq" <<'JQ_STUB'
# OBS: +# OBS: #!/usr/bin/env bash
# OBS: +# OBS: set -euo pipefail
# OBS: +# OBS: 
# OBS: +# OBS: if [[ "${1-}" == "-n" ]]; then
# OBS: +# OBS:     printf '{}\n'
# OBS: +# OBS:     exit
# OBS: +# OBS: fi
# OBS: +# OBS: 
# OBS: +# OBS: cat >/dev/null
# OBS: +# OBS: 
# OBS: +# OBS: if [[ "${STUB_SCENARIO:-edit}" == "finish" ]]; then
# OBS: +# OBS:     cat <<'FINISH_STEP'
# OBS: +# OBS: edit_context <<'FINAL_ACTIVE_CONTEXT'
# OBS: +# OBS: #!/usr/bin/env bash
# OBS: +# OBS: 
# OBS: +# OBS: # <SYSTEM>
# OBS: +# OBS: # CANONICAL_TEST: clean
# OBS: +# OBS: ROOT="$(cd "$(dirname "$0")" && pwd -P)" || exit 1
# OBS: +# OBS: SELF="$ROOT/$(basename "$0")"
# OBS: +# OBS: CANONICAL="$ROOT/ReAct.sh"
# OBS: +# OBS: if [[ "$SELF" != "$CANONICAL" && -e "$CANONICAL" ]]; then
# OBS: +# OBS:     __react_round="$(mktemp "$ROOT/.react.round.XXXXXX")" || exit 1
# OBS: +# OBS:     mv -f "$CANONICAL" "$__react_round" || exit 1
# OBS: +# OBS:     unset __react_round
# OBS: +# OBS: fi
# OBS: +# OBS: observe() { "$@"; }
# OBS: +# OBS: # </SYSTEM>
# OBS: +# OBS: 
# OBS: +# OBS: edit_context() {
# OBS: +# OBS:     local __react_next
# OBS: +# OBS: 
# OBS: +# OBS:     __react_next="$(mktemp "$ROOT/.react.image.XXXXXX")" || return
# OBS: +# OBS:     cat > "$__react_next" || return
# OBS: +# OBS:     exec bash "$__react_next" >> "$__react_next"
# OBS: +# OBS: }
# OBS: +# OBS: 
# OBS: +# OBS: finish() {
# OBS: +# OBS:     local __react_final
# OBS: +# OBS: 
# OBS: +# OBS:     grep -q '^# <TAPE>$' "$SELF" || return
# OBS: +# OBS:     __react_final="$(mktemp "$ROOT/.react.final.XXXXXX")" || return
# OBS: +# OBS:     sed -n '1,/^# <TAPE>$/p' "$SELF" > "$__react_final" || return
# OBS: +# OBS:     bash -n "$__react_final" || return
# OBS: +# OBS:     chmod +x "$__react_final" || return
# OBS: +# OBS:     mv -f "$__react_final" "$CANONICAL" || return
# OBS: +# OBS:     trap - EXIT
# OBS: +# OBS:     builtin exit 0
# OBS: +# OBS: }
# OBS: +# OBS: 
# OBS: +# OBS: reason() { :; }
# OBS: +# OBS: 
# OBS: +# OBS: if (($#)); then
# OBS: +# OBS:     printf '%s\n' "$1" | sed 's/^/# INPUT: /'
# OBS: +# OBS: fi
# OBS: +# OBS: 
# OBS: +# OBS: reason
# OBS: +# OBS: 
# OBS: +# OBS: # <TAPE>
# OBS: +# OBS: trap 'printf "# EXIT_TRAP_RAN\n"' EXIT
# OBS: +# OBS: finish
# OBS: +# OBS: printf '# AFTER_FINISH: reached\n'
# OBS: +# OBS: FINAL_ACTIVE_CONTEXT
# OBS: +# OBS: FINISH_STEP
# OBS: +# OBS:     exit
# OBS: +# OBS: fi
# OBS: +# OBS: 
# OBS: +# OBS: step=0
# OBS: +# OBS: if [[ -f "$STUB_STATE" ]]; then
# OBS: +# OBS:     read -r step < "$STUB_STATE"
# OBS: +# OBS: fi
# OBS: +# OBS: 
# OBS: +# OBS: case "$step" in
# OBS: +# OBS:     0)
# OBS: +# OBS:         cat <<'STEP_ONE'
# OBS: +# OBS: # STUB_STEP: 1
# OBS: +# OBS: tool() { TOOL_STATE=v1; printf '%s\n' v1; }
# OBS: +# OBS: observe tool
# OBS: +# OBS: printf '# TOOL_STATE: %s\n' "$TOOL_STATE"
# OBS: +# OBS: reason
# OBS: +# OBS: STEP_ONE
# OBS: +# OBS:         ;;
# OBS: +# OBS:     1)
# OBS: +# OBS:         cat <<'STEP_TWO'
# OBS: +# OBS: # STUB_STEP: 2
# OBS: +# OBS: tool() { TOOL_STATE=v2; printf '%s\n' v2; return 7; }
# OBS: +# OBS: observe tool
# OBS: +# OBS: printf '# TOOL_STATE: %s\n' "$TOOL_STATE"
# OBS: +# OBS: 
# OBS: +# OBS: printf '# BEFORE_PID: %s\n' "$$"
# OBS: +# OBS: edit_context <<'FIRST_IMAGE'
# OBS: +# OBS: #!/usr/bin/env bash
# OBS: +# OBS: 
# OBS: +# OBS: # <SYSTEM>
# OBS: +# OBS: # This is the first self-contained context-edit test image.
# OBS: +# OBS: ROOT="$(cd "$(dirname "$0")" && pwd -P)" || exit 1
# OBS: +# OBS: SELF="$ROOT/$(basename "$0")"
# OBS: +# OBS: CANONICAL="$ROOT/ReAct.sh"
# OBS: +# OBS: if [[ "$SELF" != "$CANONICAL" && -e "$CANONICAL" ]]; then
# OBS: +# OBS:     __react_round="$(mktemp "$ROOT/.react.round.XXXXXX")" || exit 1
# OBS: +# OBS:     mv -f "$CANONICAL" "$__react_round" || exit 1
# OBS: +# OBS:     unset __react_round
# OBS: +# OBS: fi
# OBS: +# OBS: observe() { "$@"; }
# OBS: +# OBS: # </SYSTEM>
# OBS: +# OBS: 
# OBS: +# OBS: # Replace this complete script from a quoted heredoc using a unique sibling.
# OBS: +# OBS: edit_context() {
# OBS: +# OBS:     local __react_next
# OBS: +# OBS: 
# OBS: +# OBS:     __react_next="$(mktemp "$ROOT/.react.image.XXXXXX")" || return
# OBS: +# OBS:     cat > "$__react_next" || return
# OBS: +# OBS:     exec bash "$__react_next" >> "$__react_next"
# OBS: +# OBS: }
# OBS: +# OBS: 
# OBS: +# OBS: reason() {
# OBS: +# OBS:     cat <<'FIRST_CONTINUATION'
# OBS: +# OBS: printf '# FIRST_SWITCH_PID: %s\n' "$$"
# OBS: +# OBS: printf '# FIRST_SWITCH_SELF: %s\n' "$SELF"
# OBS: +# OBS: edit_context <<'SECOND_IMAGE'
# OBS: +# OBS: #!/usr/bin/env bash
# OBS: +# OBS: 
# OBS: +# OBS: # <SYSTEM>
# OBS: +# OBS: # This is the second self-contained context-edit test image.
# OBS: +# OBS: ROOT="$(cd "$(dirname "$0")" && pwd -P)" || exit 1
# OBS: +# OBS: SELF="$ROOT/$(basename "$0")"
# OBS: +# OBS: CANONICAL="$ROOT/ReAct.sh"
# OBS: +# OBS: if [[ "$SELF" != "$CANONICAL" && -e "$CANONICAL" ]]; then
# OBS: +# OBS:     __react_round="$(mktemp "$ROOT/.react.round.XXXXXX")" || exit 1
# OBS: +# OBS:     mv -f "$CANONICAL" "$__react_round" || exit 1
# OBS: +# OBS:     unset __react_round
# OBS: +# OBS: fi
# OBS: +# OBS: observe() { "$@"; }
# OBS: +# OBS: # </SYSTEM>
# OBS: +# OBS: 
# OBS: +# OBS: # Replace this complete script from a quoted heredoc using a unique sibling.
# OBS: +# OBS: edit_context() {
# OBS: +# OBS:     local __react_next
# OBS: +# OBS: 
# OBS: +# OBS:     __react_next="$(mktemp "$ROOT/.react.image.XXXXXX")" || return
# OBS: +# OBS:     cat > "$__react_next" || return
# OBS: +# OBS:     exec bash "$__react_next" >> "$__react_next"
# OBS: +# OBS: }
# OBS: +# OBS: 
# OBS: +# OBS: reason() {
# OBS: +# OBS:     printf '# SECOND_SWITCH_PID: %s\n' "$$"
# OBS: +# OBS:     printf '# SECOND_SWITCH_SELF: %s\n' "$SELF"
# OBS: +# OBS:     printf ': "second image resumed"\n'
# OBS: +# OBS: }
# OBS: +# OBS: 
# OBS: +# OBS: # INPUT: [compressed twice] exercise append semantics
# OBS: +# OBS: # MEMORY: first edited trajectory compressed again
# OBS: +# OBS: reason
# OBS: +# OBS: 
# OBS: +# OBS: # <TAPE>
# OBS: +# OBS: SECOND_IMAGE
# OBS: +# OBS: FIRST_CONTINUATION
# OBS: +# OBS: }
# OBS: +# OBS: 
# OBS: +# OBS: # INPUT: [compressed once] exercise append semantics
# OBS: +# OBS: # MEMORY: original trajectory compressed by the stub
# OBS: +# OBS: reason
# OBS: +# OBS: 
# OBS: +# OBS: # <TAPE>
# OBS: +# OBS: FIRST_IMAGE
# OBS: +# OBS: STEP_TWO
# OBS: +# OBS:         ;;
# OBS: +# OBS:     *)
# OBS: +# OBS:         printf ': "stub complete"\n'
# OBS: +# OBS:         ;;
# OBS: +# OBS: esac
# OBS: +# OBS: 
# OBS: +# OBS: printf '%s\n' "$((step + 1))" > "$STUB_STATE"
# OBS: +# OBS: JQ_STUB
# OBS: +# OBS: 
# OBS: +# OBS: chmod +x "$TMP_ROOT/bin/curl" "$TMP_ROOT/bin/jq"
# OBS: +# OBS: 
# OBS: +# OBS: "$BASH_UNDER_TEST" -n "$TMP_ROOT/ReAct.sh"
# OBS: +# OBS: assert_structural_image "$TMP_ROOT/ReAct.sh"
# OBS: +# OBS: 
# OBS: +# OBS: PATH="$TMP_ROOT/bin:$BASH_DIR:/usr/bin:/bin" \
# OBS: +# OBS: OPENAI_API_KEY=stub \
# OBS: +# OBS: STUB_STATE="$TMP_ROOT/stub-state" \
# OBS: +# OBS:     "$BASH_UNDER_TEST" "$TMP_ROOT/ReAct.sh" "exercise append semantics" \
# OBS: +# OBS:     >> "$TMP_ROOT/ReAct.sh"
# OBS: +# OBS: 
# OBS: +# OBS: image_count="$(find "$TMP_ROOT" -maxdepth 1 -type f -name '.react.image.*' | wc -l | tr -d ' ')"
# OBS: +# OBS: [[ "$image_count" == 2 ]] || fail "expected two edited context images; got $image_count"
# OBS: +# OBS: 
# OBS: +# OBS: round_count="$(find "$TMP_ROOT" -maxdepth 1 -type f -name '.react.round.*' | wc -l | tr -d ' ')"
# OBS: +# OBS: [[ "$round_count" == 1 ]] || fail "expected one de-canonicalized round; got $round_count"
# OBS: +# OBS: ROUND_IMAGE="$(find "$TMP_ROOT" -maxdepth 1 -type f -name '.react.round.*')"
# OBS: +# OBS: [[ ! -e "$TMP_ROOT/ReAct.sh" ]] || fail "canonical path still exists during an active round"
# OBS: +# OBS: 
# OBS: +# OBS: FIRST_IMAGE="$(grep -l '^# FIRST_SWITCH_PID: ' "$TMP_ROOT"/.react.image.* || true)"
# OBS: +# OBS: SECOND_IMAGE="$(grep -l '^# SECOND_SWITCH_PID: ' "$TMP_ROOT"/.react.image.* || true)"
# OBS: +# OBS: [[ -n "$FIRST_IMAGE" ]] || fail "first edited context image was not identified"
# OBS: +# OBS: [[ -n "$SECOND_IMAGE" ]] || fail "second edited context image was not identified"
# OBS: +# OBS: [[ "$FIRST_IMAGE" != "$SECOND_IMAGE" ]] || fail "both context edits reused the same image"
# OBS: +# OBS: [[ "$FIRST_IMAGE" != "$TMP_ROOT/ReAct.sh" && "$SECOND_IMAGE" != "$TMP_ROOT/ReAct.sh" ]] ||
# OBS: +# OBS:     fail "context edit reused the currently running image"
# OBS: +# OBS: 
# OBS: +# OBS: "$BASH_UNDER_TEST" -n "$ROUND_IMAGE"
# OBS: +# OBS: "$BASH_UNDER_TEST" -n "$FIRST_IMAGE"
# OBS: +# OBS: "$BASH_UNDER_TEST" -n "$SECOND_IMAGE"
# OBS: +# OBS: 
# OBS: +# OBS: assert_count 1 '^# INPUT: exercise append semantics$' "$ROUND_IMAGE"
# OBS: +# OBS: assert_count 1 '^# STUB_STEP: 1$' "$ROUND_IMAGE"
# OBS: +# OBS: assert_count 1 '^# STUB_STEP: 2$' "$ROUND_IMAGE"
# OBS: +# OBS: assert_count 1 '^# OBS: v1$' "$ROUND_IMAGE"
# OBS: +# OBS: assert_count 1 '^# OBS: v2$' "$ROUND_IMAGE"
# OBS: +# OBS: assert_count 1 '^# TOOL_STATE: v1$' "$ROUND_IMAGE"
# OBS: +# OBS: assert_count 1 '^# TOOL_STATE: v2$' "$ROUND_IMAGE"
# OBS: +# OBS: assert_count 1 '^# EXIT: 0$' "$ROUND_IMAGE"
# OBS: +# OBS: assert_count 1 '^# EXIT: 7$' "$ROUND_IMAGE"
# OBS: +# OBS: assert_count 1 '^# BEFORE_PID: ' "$ROUND_IMAGE"
# OBS: +# OBS: assert_count 0 '^# FIRST_SWITCH_PID: ' "$ROUND_IMAGE"
# OBS: +# OBS: assert_count 0 '^# SECOND_SWITCH_PID: ' "$ROUND_IMAGE"
# OBS: +# OBS: assert_count 1 '^# FIRST_SWITCH_PID: ' "$FIRST_IMAGE"
# OBS: +# OBS: assert_count 1 '^# FIRST_SWITCH_SELF: ' "$FIRST_IMAGE"
# OBS: +# OBS: assert_count 0 '^# SECOND_SWITCH_PID: ' "$FIRST_IMAGE"
# OBS: +# OBS: assert_count 1 '^# INPUT: \[compressed once\] exercise append semantics$' "$FIRST_IMAGE"
# OBS: +# OBS: grep -q '^# <TAPE>$' "$FIRST_IMAGE" || fail "first image has no tape boundary"
# OBS: +# OBS: assert_count 1 '^# SECOND_SWITCH_PID: ' "$SECOND_IMAGE"
# OBS: +# OBS: assert_count 1 '^# SECOND_SWITCH_SELF: ' "$SECOND_IMAGE"
# OBS: +# OBS: assert_count 1 '^# INPUT: \[compressed twice\] exercise append semantics$' "$SECOND_IMAGE"
# OBS: +# OBS: assert_count 1 '^# <TAPE>$' "$SECOND_IMAGE"
# OBS: +# OBS: assert_count 1 '^: "second image resumed"$' "$SECOND_IMAGE"
# OBS: +# OBS: 
# OBS: +# OBS: before_pid="$(sed -n 's/^# BEFORE_PID: //p' "$ROUND_IMAGE")"
# OBS: +# OBS: first_pid="$(sed -n 's/^# FIRST_SWITCH_PID: //p' "$FIRST_IMAGE")"
# OBS: +# OBS: second_pid="$(sed -n 's/^# SECOND_SWITCH_PID: //p' "$SECOND_IMAGE")"
# OBS: +# OBS: [[ "$before_pid" == "$first_pid" && "$first_pid" == "$second_pid" ]] ||
# OBS: +# OBS:     fail "exec changed PID: before=$before_pid first=$first_pid second=$second_pid"
# OBS: +# OBS: 
# OBS: +# OBS: first_self="$(sed -n 's/^# FIRST_SWITCH_SELF: //p' "$FIRST_IMAGE")"
# OBS: +# OBS: second_self="$(sed -n 's/^# SECOND_SWITCH_SELF: //p' "$SECOND_IMAGE")"
# OBS: +# OBS: [[ "$first_self" == "$FIRST_IMAGE" ]] ||
# OBS: +# OBS:     fail "first image saw SELF as $first_self, expected $FIRST_IMAGE"
# OBS: +# OBS: [[ "$second_self" == "$SECOND_IMAGE" ]] ||
# OBS: +# OBS:     fail "second image saw SELF as $second_self, expected $SECOND_IMAGE"
# OBS: +# OBS: 
# OBS: +# OBS: FINISH_ROOT="$TMP_ROOT/finish-case"
# OBS: +# OBS: RUNNING_IMAGE="$FINISH_ROOT/running-image.sh"
# OBS: +# OBS: mkdir "$FINISH_ROOT"
# OBS: +# OBS: cp "$PROJECT_ROOT/ReAct.sh" "$FINISH_ROOT/ReAct.sh"
# OBS: +# OBS: ln "$FINISH_ROOT/ReAct.sh" "$RUNNING_IMAGE"
# OBS: +# OBS: 
# OBS: +# OBS: PATH="$TMP_ROOT/bin:$BASH_DIR:/usr/bin:/bin" \
# OBS: +# OBS: OPENAI_API_KEY=stub \
# OBS: +# OBS: STUB_SCENARIO=finish \
# OBS: +# OBS:     "$BASH_UNDER_TEST" "$FINISH_ROOT/ReAct.sh" "exercise finish semantics" \
# OBS: +# OBS:     >> "$FINISH_ROOT/ReAct.sh"
# OBS: +# OBS: 
# OBS: +# OBS: "$BASH_UNDER_TEST" -n "$RUNNING_IMAGE"
# OBS: +# OBS: "$BASH_UNDER_TEST" -n "$FINISH_ROOT/ReAct.sh"
# OBS: +# OBS: [[ -x "$FINISH_ROOT/ReAct.sh" ]] || fail "canonical image is not executable"
# OBS: +# OBS: cmp -s "$RUNNING_IMAGE" "$FINISH_ROOT/ReAct.sh" &&
# OBS: +# OBS:     fail "finish did not replace the canonical image"
# OBS: +# OBS: 
# OBS: +# OBS: assert_count 1 '^# INPUT: exercise finish semantics$' "$RUNNING_IMAGE"
# OBS: +# OBS: assert_count 1 "^edit_context <<'FINAL_ACTIVE_CONTEXT'$" "$RUNNING_IMAGE"
# OBS: +# OBS: 
# OBS: +# OBS: finish_round_count="$(find "$FINISH_ROOT" -maxdepth 1 -type f -name '.react.round.*' | wc -l | tr -d ' ')"
# OBS: +# OBS: [[ "$finish_round_count" == 1 ]] ||
# OBS: +# OBS:     fail "expected one archived finish round; got $finish_round_count"
# OBS: +# OBS: FINISH_ROUND_IMAGE="$(find "$FINISH_ROOT" -maxdepth 1 -type f -name '.react.round.*')"
# OBS: +# OBS: cmp -s "$RUNNING_IMAGE" "$FINISH_ROUND_IMAGE" ||
# OBS: +# OBS:     fail "de-canonicalized round does not preserve the task-bearing ReAct.sh"
# OBS: +# OBS: 
# OBS: +# OBS: finish_image_count="$(find "$FINISH_ROOT" -maxdepth 1 -type f -name '.react.image.*' | wc -l | tr -d ' ')"
# OBS: +# OBS: [[ "$finish_image_count" == 1 ]] ||
# OBS: +# OBS:     fail "expected one final active context; got $finish_image_count"
# OBS: +# OBS: FINAL_ACTIVE_IMAGE="$(find "$FINISH_ROOT" -maxdepth 1 -type f -name '.react.image.*')"
# OBS: +# OBS: "$BASH_UNDER_TEST" -n "$FINAL_ACTIVE_IMAGE"
# OBS: +# OBS: assert_count 1 '^finish$' "$FINAL_ACTIVE_IMAGE"
# OBS: +# OBS: assert_count 0 '^# EXIT_TRAP_RAN$' "$FINAL_ACTIVE_IMAGE"
# OBS: +# OBS: assert_count 0 '^# AFTER_FINISH: reached$' "$FINAL_ACTIVE_IMAGE"
# OBS: +# OBS: 
# OBS: +# OBS: assert_count 1 '^# CANONICAL_TEST: clean$' "$FINISH_ROOT/ReAct.sh"
# OBS: +# OBS: assert_count 0 '^# INPUT:' "$FINISH_ROOT/ReAct.sh"
# OBS: +# OBS: assert_count 0 '^# OBS:' "$FINISH_ROOT/ReAct.sh"
# OBS: +# OBS: assert_count 1 '^# <TAPE>$' "$FINISH_ROOT/ReAct.sh"
# OBS: +# OBS: assert_structural_image "$FINISH_ROOT/ReAct.sh"
# OBS: +# OBS: [[ "$(tail -n 1 "$FINISH_ROOT/ReAct.sh")" == '# <TAPE>' ]] ||
# OBS: +# OBS:     fail "canonical image does not end at its tape boundary"
# OBS: +# OBS: 
# OBS: +# OBS: EXPECTED_CANONICAL="$FINISH_ROOT/expected-canonical.sh"
# OBS: +# OBS: sed -n '1,/^# <TAPE>$/p' "$FINAL_ACTIVE_IMAGE" > "$EXPECTED_CANONICAL"
# OBS: +# OBS: cmp -s "$EXPECTED_CANONICAL" "$FINISH_ROOT/ReAct.sh" ||
# OBS: +# OBS:     fail "canonical ReAct.sh is not the reusable prefix of the final active context"
# OBS: +# OBS: 
# OBS: +# OBS: final_staging_count="$(find "$FINISH_ROOT" -maxdepth 1 -name '.react.final.*' | wc -l | tr -d ' ')"
# OBS: +# OBS: [[ "$final_staging_count" == 0 ]] ||
# OBS: +# OBS:     fail "finish left $final_staging_count staging files after installation"
# OBS: +# OBS: 
# OBS: +# OBS: printf 'ok: append execution, tool evolution, context editing, round lifecycle, and finish\n'
# OBS: +# OBS: --- README.md ---
# OBS: +# OBS: # Harness in a Shell
# OBS: +# OBS: 
# OBS: +# OBS: ```bash
# OBS: +# OBS: bash ReAct.sh '<prompt>' >> ReAct.sh
# OBS: +# OBS: ```
# OBS: +# OBS: 
# OBS: +# OBS: [中文版](./README.zh-CN.md)
# OBS: +# OBS: 
# OBS: +# OBS: That one shell command is the ReAct loop. In generic form it is
# OBS: +# OBS: `bash agent.sh '<prompt>' >> agent.sh`: model output goes to stdout, stdout is
# OBS: +# OBS: appended to the running script, and the same Bash process continues reading and
# OBS: +# OBS: executing the appended source. There is no explicit `while` loop.
# OBS: +# OBS: 
# OBS: +# OBS: This repository is a research prototype built around three ideas.
# OBS: +# OBS: 
# OBS: +# OBS: ## 1. Script as Context
# OBS: +# OBS: 
# OBS: +# OBS: The active Bash script is the agent's complete context. It contains the
# OBS: +# OBS: governing prompt, runtime identity, tool definitions, user input, observations,
# OBS: +# OBS: execution tape, continuation, and its own context-editing machinery.
# OBS: +# OBS: 
# OBS: +# OBS: `reason` sends the complete current script to the model. The response is not a
# OBS: +# OBS: separate chat message: it is future Bash source appended to that script.
# OBS: +# OBS: 
# OBS: +# OBS: ```text
# OBS: +# OBS: # INPUT: user instructions
# OBS: +# OBS: # OBS:   tool observations
# OBS: +# OBS: # EXIT:  observed exit status
# OBS: +# OBS: # <TAPE> live trajectory begins here
# OBS: +# OBS: ```
# OBS: +# OBS: 
# OBS: +# OBS: Because the script is context, changing the SYSTEM prompt, reorganizing memory,
# OBS: +# OBS: or replacing the reasoning machinery are all ordinary script edits.
# OBS: +# OBS: `edit_context` performs a structural edit by switching to a complete new script.
# OBS: +# OBS: 
# OBS: +# OBS: ## 2. Function as Tool
# OBS: +# OBS: 
# OBS: +# OBS: A Bash function is a tool. The agent may call or redefine an existing function,
# OBS: +# OBS: author a new one, compose tools from other tools, refine old tools, or derive new
# OBS: +# OBS: tools through any recursive combination of authoring, composition, and
# OBS: +# OBS: refinement.
# OBS: +# OBS: 
# OBS: +# OBS: `observe` runs a command or function once in the current shell and records its
# OBS: +# OBS: output and exit status as inert Bash comments. State changes made by a function,
# OBS: +# OBS: such as variables or `cd`, remain live. A state-only function may also be called
# OBS: +# OBS: directly when it produces no unsafe stdout.
# OBS: +# OBS: 
# OBS: +# OBS: The harness itself follows the same rule: `observe`, `reason`, `edit_context`,
# OBS: +# OBS: and `finish` are functions rather than privileged operations outside the script.
# OBS: +# OBS: 
# OBS: +# OBS: ## 3. File as Round
# OBS: +# OBS: 
# OBS: +# OBS: A round is the file-backed lifecycle of one task, not one API call. It begins
# OBS: +# OBS: when a prompt is appended to the canonical `ReAct.sh` and ends when `finish`
# OBS: +# OBS: installs the next canonical `ReAct.sh`. A round may migrate through any number
# OBS: +# OBS: of active image files.
# OBS: +# OBS: 
# OBS: +# OBS: ```text
# OBS: +# OBS: ReAct.sh (clean canonical; previous round complete)
# OBS: +# OBS:   └─ append prompt → ReAct.sh becomes the active, task-bearing file
# OBS: +# OBS:        └─ first edit_context → exec .react.image.* as the new active context
# OBS: +# OBS:             └─ new image startup archives old ReAct.sh as .react.round.*
# OBS: +# OBS:                  └─ canonical pathname remains intentionally absent
# OBS: +# OBS:                       └─ zero or more edit_context transitions
# OBS: +# OBS:                            └─ finish
# OBS: +# OBS:                                 └─ install the active prefix through the first
# OBS: +# OBS:                                    exact # <TAPE> as ReAct.sh (round complete)
# OBS: +# OBS: ```
# OBS: +# OBS: 
# OBS: +# OBS: After the first successful context switch, the newly active image immediately
# OBS: +# OBS: de-canonicalizes the old, task-bearing `ReAct.sh`. Later switches do not repeat
# OBS: +# OBS: that step because the canonical pathname is already absent. At rest,
# OBS: +# OBS: `ReAct.sh` contains the durable state produced by the completed round and serves
# OBS: +# OBS: as the next round's entry. It may be the active file before the first switch,
# OBS: +# OBS: but it never remains as a stale active image after execution has migrated
# OBS: +# OBS: elsewhere.
# OBS: +# OBS: 
# OBS: +# OBS: Before calling `finish`, the agent uses `edit_context` when necessary to promote
# OBS: +# OBS: reusable improvements above the first exact `# <TAPE>` boundary. `finish` then
# OBS: +# OBS: validates that prefix, atomically installs it as `ReAct.sh`, and exits. The new
# OBS: +# OBS: canonical image therefore omits the tape and the `finish` call. `finish` does not
# OBS: +# OBS: decide what knowledge is durable; that semantic edit remains the agent's
# OBS: +# OBS: responsibility.
# OBS: +# OBS: 
# OBS: +# OBS: The first exact line `# <TAPE>` is therefore a format invariant. Reusable source
# OBS: +# OBS: before the real boundary must not contain another identical whole line.
# OBS: +# OBS: 
# OBS: +# OBS: ## Run
# OBS: +# OBS: 
# OBS: +# OBS: Requirements:
# OBS: +# OBS: 
# OBS: +# OBS: - Bash
# OBS: +# OBS: - `curl`
# OBS: +# OBS: - `jq`
# OBS: +# OBS: - `OPENAI_API_KEY`
# OBS: +# OBS: 
# OBS: +# OBS: The default model is `gpt-5.6-sol`; override it with `OPENAI_MODEL`.
# OBS: +# OBS: 
# OBS: +# OBS: ```bash
# OBS: +# OBS: export OPENAI_API_KEY='...'
# OBS: +# OBS: bash ReAct.sh 'Find and fix the failing tests.' >> ReAct.sh
# OBS: +# OBS: ```
# OBS: +# OBS: 
# OBS: +# OBS: The command intentionally modifies `ReAct.sh`, and the canonical pathname may
# OBS: +# OBS: temporarily disappear after the first context switch. This prototype assumes
# OBS: +# OBS: one active round per directory. Git provides the simplest experiment log and
# OBS: +# OBS: reset point.
# OBS: +# OBS: 
# OBS: +# OBS: ## Test without an API key
# OBS: +# OBS: 
# OBS: +# OBS: ```bash
# OBS: +# OBS: bash test.sh
# OBS: +# OBS: ```
# OBS: +# OBS: 
# OBS: +# OBS: The test injects local `curl` and `jq` stubs. It verifies append execution,
# OBS: +# OBS: function evolution and shell-state persistence, repeated context edits,
# OBS: +# OBS: de-canonicalization after the first switch, PID continuity across `exec`, and
# OBS: +# OBS: automatic canonicalization through `finish` on Bash 3.2 and Bash 5.1.
# OBS: +# OBS: 
# OBS: +# OBS: ## Run in a disposable sandbox
# OBS: +# OBS: 
# OBS: +# OBS: Treat model output as arbitrary Bash, not merely as a program that might make a
# OBS: +# OBS: mistake. In particular, do not bind-mount the real repository, home directory,
# OBS: +# OBS: credentials, or a Docker socket into its executor.
# OBS: +# OBS: 
# OBS: +# OBS: The repository includes a container fallback for local experiments. On macOS,
# OBS: +# OBS: start Docker Desktop first:
# OBS: +# OBS: 
# OBS: +# OBS: ```bash
# OBS: +# OBS: open -a Docker
# OBS: +# OBS: bash sandbox.sh test
# OBS: +# OBS: bash sandbox.sh verify
# OBS: +# OBS: ```
# OBS: +# OBS: 
# OBS: +# OBS: `test` runs the stub harness with no network or key. `verify` uses a fake key
# OBS: +# OBS: and checks the isolation policy. The untrusted agent container has a read-only
# OBS: +# OBS: root filesystem, bounded tmpfs, no Linux capabilities, resource limits, no host
# OBS: +# OBS: bind mounts, no Docker socket, no API key, and `network=none`.
# OBS: +# OBS: 
# OBS: +# OBS: For a live run, the agent can only reach a narrow relay through a Unix socket on
# OBS: +# OBS: a read-only-mounted volume. The relay holds the real key, reconstructs only a
# OBS: +# OBS: `POST /v1/responses` request to `api.openai.com`, pins the model, rejects extra
# OBS: +# OBS: API fields, disables hosted tools and streaming, and enforces per-run request,
# OBS: +# OBS: body, response, output-token, and wall-clock limits. The independent host
# OBS: +# OBS: watchdog remains authoritative even if arbitrary Bash attacks its in-container
# OBS: +# OBS: timeout.
# OBS: +# OBS: 
# OBS: +# OBS: ```text
# OBS: +# OBS: agent (arbitrary Bash; network=none; no key)
# OBS: +# OBS:   └─ Unix socket on read-only mount → trusted relay
# OBS: +# OBS:                                       └─ TLS → api.openai.com/v1/responses
# OBS: +# OBS: ```
# OBS: +# OBS: 
# OBS: +# OBS: On a supported Docker installation, run it with:
# OBS: +# OBS: 
# OBS: +# OBS: ```bash
# OBS: +# OBS: export OPENAI_API_KEY='...'
# OBS: +# OBS: bash sandbox.sh run 'Inspect the harness and finish cleanly.'
# OBS: +# OBS: ```
# OBS: +# OBS: 
# OBS: +# OBS: Tune the bounds with `SANDBOX_TIMEOUT_SECONDS`, `SANDBOX_MEMORY`,
# OBS: +# OBS: `SANDBOX_WORK_SIZE`, `OPENAI_MAX_REQUESTS`, and
# OBS: +# OBS: `OPENAI_MAX_OUTPUT_TOKENS`. The cost-conscious defaults allow at most 8 API
# OBS: +# OBS: attempts and 4096 output tokens per attempt; the trusted relay records the
# OBS: +# OBS: actual attempt count in each run directory. Container output is disk-capped and
# OBS: +# OBS: retained under `sandbox-runs/run.*/untrusted-{output,stderr}.bin`; the trusted
# OBS: +# OBS: host runner deliberately does not parse it or render agent-controlled logs in
# OBS: +# OBS: the terminal.
# OBS: +# OBS: A normal run writes a gzip tar stream to `untrusted-output.bin`, but arbitrary
# OBS: +# OBS: Bash can corrupt or forge it. Inspect it only inside another disposable,
# OBS: +# OBS: no-network sandbox, and never execute or source recovered files on the host.
# OBS: +# OBS: 
# OBS: +# OBS: `SANDBOX_BASE_IMAGE` and `SANDBOX_BUILD_PROXY` are build-only escape hatches
# OBS: +# OBS: for an offline cache or a local package proxy. They do not change the runtime
# OBS: +# OBS: network policy and the proxy value is not baked into the resulting image. Once
# OBS: +# OBS: both local images have been built, `SANDBOX_SKIP_BUILD=1` skips all image-build
# OBS: +# OBS: network access; a live `run` still calls the OpenAI API through the relay. Use it
# OBS: +# OBS: only when deliberately testing the already-built image.
# OBS: +# OBS: 
# OBS: +# OBS: This Mac currently runs macOS 12.5.1 and Docker Desktop 4.9.1. That stack is no
# OBS: +# OBS: longer supported and is too old to be the sole boundary for a live arbitrary
# OBS: +# OBS: Bash agent, so `sandbox.sh run` refuses by default on it. For experiments today,
# OBS: +# OBS: run the same script inside a disposable UTM Linux VM with host directory,
# OBS: +# OBS: clipboard, USB, and credential sharing disabled. `ALLOW_LEGACY_DOCKER_SANDBOX=1`
# OBS: +# OBS: exists as an explicit research-risk override, not as a recommendation.
# OBS: +# OBS: 
# OBS: +# OBS: ### Stronger microVM setup
# OBS: +# OBS: 
# OBS: +# OBS: After upgrading to macOS 14 or later, prefer Docker Sandboxes. Initialize its
# OBS: +# OBS: network policy as deny-by-default, use clone mode so the working copy stays in
# OBS: +# OBS: the microVM, scope the OpenAI secret to this sandbox, and allow exactly the API
# OBS: +# OBS: host:
# OBS: +# OBS: 
# OBS: +# OBS: ```bash
# OBS: +# OBS: brew trust docker/tap
# OBS: +# OBS: brew install docker/tap/sbx
# OBS: +# OBS: sbx login
# OBS: +# OBS: sbx policy init deny-all
# OBS: +# OBS: 
# OBS: +# OBS: sbx create shell "$PWD" --clone --no-share-skills --name react-harness --cpus 1 --memory 1g
# OBS: +# OBS: sbx secret set react-harness openai
# OBS: +# OBS: sbx policy allow network --sandbox react-harness api.openai.com:443
# OBS: +# OBS: sbx policy ls --wide
# OBS: +# OBS: sbx run --name react-harness
# OBS: +# OBS: ```
# OBS: +# OBS: 
# OBS: +# OBS: Then, inside the sandbox:
# OBS: +# OBS: 
# OBS: +# OBS: ```bash
# OBS: +# OBS: OPENAI_API_KEY=proxy-managed bash ReAct.sh '<prompt>' >> ReAct.sh
# OBS: +# OBS: ```
# OBS: +# OBS: 
# OBS: +# OBS: Use a staging Git repository containing only files the agent may read; clone
# OBS: +# OBS: mode still exposes the source repository read-only. `--no-share-skills` also
# OBS: +# OBS: prevents the sandbox from receiving Docker's shared host skill store. Remove
# OBS: +# OBS: the microVM with `sbx rm react-harness` after exporting and reviewing the one
# OBS: +# OBS: result you intend to keep.
# OBS: +# OBS: 
# OBS: +# OBS: This remains a research artifact. Canonicalization means a round completed; it
# OBS: +# OBS: does not make the resulting Bash trustworthy.
# OBS: +# EXIT: 0
# OBS: +run_baseline_tests() {
# OBS: +    /bin/bash -n "$ROOT/ReAct.sh" &&
# OBS: +        /bin/bash -n "$ROOT/test.sh" &&
# OBS: +        bash "$ROOT/test.sh"
# OBS: +}
# OBS: +observe run_baseline_tests
# OBS: +reason
# OBS: +
# OBS: --- test.sh ---
# OBS: #!/usr/bin/env bash
# OBS: 
# OBS: set -euo pipefail
# OBS: 
# OBS: PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd -P)"
# OBS: TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/harness-in-a-shell.XXXXXX")"
# OBS: TMP_ROOT="$(cd "$TMP_ROOT" && pwd -P)"
# OBS: BASH_UNDER_TEST="${BASH_UNDER_TEST:-/bin/bash}"
# OBS: BASH_DIR="$(cd "$(dirname "$BASH_UNDER_TEST")" && pwd -P)"
# OBS: 
# OBS: cleanup() {
# OBS:     rm -rf "$TMP_ROOT"
# OBS: }
# OBS: trap cleanup EXIT
# OBS: 
# OBS: fail() {
# OBS:     printf 'FAIL: %s\n' "$1" >&2
# OBS:     exit 1
# OBS: }
# OBS: 
# OBS: assert_count() {
# OBS:     local expected="$1"
# OBS:     local pattern="$2"
# OBS:     local file="$3"
# OBS:     local actual
# OBS: 
# OBS:     actual="$(grep -c -- "$pattern" "$file" || true)"
# OBS:     [[ "$actual" == "$expected" ]] ||
# OBS:         fail "expected $expected matches for '$pattern' in $file; got $actual"
# OBS: }
# OBS: 
# OBS: assert_structural_image() {
# OBS:     local file="$1"
# OBS:     local system_open system_close tape
# OBS: 
# OBS:     assert_count 1 '^# <SYSTEM>$' "$file"
# OBS:     assert_count 1 '^# </SYSTEM>$' "$file"
# OBS:     assert_count 1 '^# <TAPE>$' "$file"
# OBS: 
# OBS:     system_open="$(grep -n '^# <SYSTEM>$' "$file" | cut -d: -f1)"
# OBS:     system_close="$(grep -n '^# </SYSTEM>$' "$file" | cut -d: -f1)"
# OBS:     tape="$(grep -n '^# <TAPE>$' "$file" | cut -d: -f1)"
# OBS:     ((system_open < system_close && system_close < tape)) ||
# OBS:         fail "structural markers are out of order in $file"
# OBS: }
# OBS: 
# OBS: mkdir "$TMP_ROOT/bin"
# OBS: cp "$PROJECT_ROOT/ReAct.sh" "$TMP_ROOT/ReAct.sh"
# OBS: 
# OBS: cat > "$TMP_ROOT/bin/curl" <<'CURL_STUB'
# OBS: #!/usr/bin/env bash
# OBS: cat >/dev/null
# OBS: printf '{}\n'
# OBS: CURL_STUB
# OBS: 
# OBS: cat > "$TMP_ROOT/bin/jq" <<'JQ_STUB'
# OBS: #!/usr/bin/env bash
# OBS: set -euo pipefail
# OBS: 
# OBS: if [[ "${1-}" == "-n" ]]; then
# OBS:     printf '{}\n'
# OBS:     exit
# OBS: fi
# OBS: 
# OBS: cat >/dev/null
# OBS: 
# OBS: if [[ "${STUB_SCENARIO:-edit}" == "finish" ]]; then
# OBS:     cat <<'FINISH_STEP'
# OBS: edit_context <<'FINAL_ACTIVE_CONTEXT'
# OBS: #!/usr/bin/env bash
# OBS: 
# OBS: # <SYSTEM>
# OBS: # CANONICAL_TEST: clean
# OBS: ROOT="$(cd "$(dirname "$0")" && pwd -P)" || exit 1
# OBS: SELF="$ROOT/$(basename "$0")"
# OBS: CANONICAL="$ROOT/ReAct.sh"
# OBS: if [[ "$SELF" != "$CANONICAL" && -e "$CANONICAL" ]]; then
# OBS:     __react_round="$(mktemp "$ROOT/.react.round.XXXXXX")" || exit 1
# OBS:     mv -f "$CANONICAL" "$__react_round" || exit 1
# OBS:     unset __react_round
# OBS: fi
# OBS: observe() { "$@"; }
# OBS: # </SYSTEM>
# OBS: 
# OBS: edit_context() {
# OBS:     local __react_next
# OBS: 
# OBS:     __react_next="$(mktemp "$ROOT/.react.image.XXXXXX")" || return
# OBS:     cat > "$__react_next" || return
# OBS:     exec bash "$__react_next" >> "$__react_next"
# OBS: }
# OBS: 
# OBS: finish() {
# OBS:     local __react_final
# OBS: 
# OBS:     grep -q '^# <TAPE>$' "$SELF" || return
# OBS:     __react_final="$(mktemp "$ROOT/.react.final.XXXXXX")" || return
# OBS:     sed -n '1,/^# <TAPE>$/p' "$SELF" > "$__react_final" || return
# OBS:     bash -n "$__react_final" || return
# OBS:     chmod +x "$__react_final" || return
# OBS:     mv -f "$__react_final" "$CANONICAL" || return
# OBS:     trap - EXIT
# OBS:     builtin exit 0
# OBS: }
# OBS: 
# OBS: reason() { :; }
# OBS: 
# OBS: if (($#)); then
# OBS:     printf '%s\n' "$1" | sed 's/^/# INPUT: /'
# OBS: fi
# OBS: 
# OBS: reason
# OBS: 
# OBS: # <TAPE>
# OBS: trap 'printf "# EXIT_TRAP_RAN\n"' EXIT
# OBS: finish
# OBS: printf '# AFTER_FINISH: reached\n'
# OBS: FINAL_ACTIVE_CONTEXT
# OBS: FINISH_STEP
# OBS:     exit
# OBS: fi
# OBS: 
# OBS: step=0
# OBS: if [[ -f "$STUB_STATE" ]]; then
# OBS:     read -r step < "$STUB_STATE"
# OBS: fi
# OBS: 
# OBS: case "$step" in
# OBS:     0)
# OBS:         cat <<'STEP_ONE'
# OBS: # STUB_STEP: 1
# OBS: tool() { TOOL_STATE=v1; printf '%s\n' v1; }
# OBS: observe tool
# OBS: printf '# TOOL_STATE: %s\n' "$TOOL_STATE"
# OBS: reason
# OBS: STEP_ONE
# OBS:         ;;
# OBS:     1)
# OBS:         cat <<'STEP_TWO'
# OBS: # STUB_STEP: 2
# OBS: tool() { TOOL_STATE=v2; printf '%s\n' v2; return 7; }
# OBS: observe tool
# OBS: printf '# TOOL_STATE: %s\n' "$TOOL_STATE"
# OBS: 
# OBS: printf '# BEFORE_PID: %s\n' "$$"
# OBS: edit_context <<'FIRST_IMAGE'
# OBS: #!/usr/bin/env bash
# OBS: 
# OBS: # <SYSTEM>
# OBS: # This is the first self-contained context-edit test image.
# OBS: ROOT="$(cd "$(dirname "$0")" && pwd -P)" || exit 1
# OBS: SELF="$ROOT/$(basename "$0")"
# OBS: CANONICAL="$ROOT/ReAct.sh"
# OBS: if [[ "$SELF" != "$CANONICAL" && -e "$CANONICAL" ]]; then
# OBS:     __react_round="$(mktemp "$ROOT/.react.round.XXXXXX")" || exit 1
# OBS:     mv -f "$CANONICAL" "$__react_round" || exit 1
# OBS:     unset __react_round
# OBS: fi
# OBS: observe() { "$@"; }
# OBS: # </SYSTEM>
# OBS: 
# OBS: # Replace this complete script from a quoted heredoc using a unique sibling.
# OBS: edit_context() {
# OBS:     local __react_next
# OBS: 
# OBS:     __react_next="$(mktemp "$ROOT/.react.image.XXXXXX")" || return
# OBS:     cat > "$__react_next" || return
# OBS:     exec bash "$__react_next" >> "$__react_next"
# OBS: }
# OBS: 
# OBS: reason() {
# OBS:     cat <<'FIRST_CONTINUATION'
# OBS: printf '# FIRST_SWITCH_PID: %s\n' "$$"
# OBS: printf '# FIRST_SWITCH_SELF: %s\n' "$SELF"
# OBS: edit_context <<'SECOND_IMAGE'
# OBS: #!/usr/bin/env bash
# OBS: 
# OBS: # <SYSTEM>
# OBS: # This is the second self-contained context-edit test image.
# OBS: ROOT="$(cd "$(dirname "$0")" && pwd -P)" || exit 1
# OBS: SELF="$ROOT/$(basename "$0")"
# OBS: CANONICAL="$ROOT/ReAct.sh"
# OBS: if [[ "$SELF" != "$CANONICAL" && -e "$CANONICAL" ]]; then
# OBS:     __react_round="$(mktemp "$ROOT/.react.round.XXXXXX")" || exit 1
# OBS:     mv -f "$CANONICAL" "$__react_round" || exit 1
# OBS:     unset __react_round
# OBS: fi
# OBS: observe() { "$@"; }
# OBS: # </SYSTEM>
# OBS: 
# OBS: # Replace this complete script from a quoted heredoc using a unique sibling.
# OBS: edit_context() {
# OBS:     local __react_next
# OBS: 
# OBS:     __react_next="$(mktemp "$ROOT/.react.image.XXXXXX")" || return
# OBS:     cat > "$__react_next" || return
# OBS:     exec bash "$__react_next" >> "$__react_next"
# OBS: }
# OBS: 
# OBS: reason() {
# OBS:     printf '# SECOND_SWITCH_PID: %s\n' "$$"
# OBS:     printf '# SECOND_SWITCH_SELF: %s\n' "$SELF"
# OBS:     printf ': "second image resumed"\n'
# OBS: }
# OBS: 
# OBS: # INPUT: [compressed twice] exercise append semantics
# OBS: # MEMORY: first edited trajectory compressed again
# OBS: reason
# OBS: 
# OBS: # <TAPE>
# OBS: SECOND_IMAGE
# OBS: FIRST_CONTINUATION
# OBS: }
# OBS: 
# OBS: # INPUT: [compressed once] exercise append semantics
# OBS: # MEMORY: original trajectory compressed by the stub
# OBS: reason
# OBS: 
# OBS: # <TAPE>
# OBS: FIRST_IMAGE
# OBS: STEP_TWO
# OBS:         ;;
# OBS:     *)
# OBS:         printf ': "stub complete"\n'
# OBS:         ;;
# OBS: esac
# OBS: 
# OBS: printf '%s\n' "$((step + 1))" > "$STUB_STATE"
# OBS: JQ_STUB
# OBS: 
# OBS: chmod +x "$TMP_ROOT/bin/curl" "$TMP_ROOT/bin/jq"
# OBS: 
# OBS: "$BASH_UNDER_TEST" -n "$TMP_ROOT/ReAct.sh"
# OBS: assert_structural_image "$TMP_ROOT/ReAct.sh"
# OBS: 
# OBS: PATH="$TMP_ROOT/bin:$BASH_DIR:/usr/bin:/bin" \
# OBS: OPENAI_API_KEY=stub \
# OBS: STUB_STATE="$TMP_ROOT/stub-state" \
# OBS:     "$BASH_UNDER_TEST" "$TMP_ROOT/ReAct.sh" "exercise append semantics" \
# OBS:     >> "$TMP_ROOT/ReAct.sh"
# OBS: 
# OBS: image_count="$(find "$TMP_ROOT" -maxdepth 1 -type f -name '.react.image.*' | wc -l | tr -d ' ')"
# OBS: [[ "$image_count" == 2 ]] || fail "expected two edited context images; got $image_count"
# OBS: 
# OBS: round_count="$(find "$TMP_ROOT" -maxdepth 1 -type f -name '.react.round.*' | wc -l | tr -d ' ')"
# OBS: [[ "$round_count" == 1 ]] || fail "expected one de-canonicalized round; got $round_count"
# OBS: ROUND_IMAGE="$(find "$TMP_ROOT" -maxdepth 1 -type f -name '.react.round.*')"
# OBS: [[ ! -e "$TMP_ROOT/ReAct.sh" ]] || fail "canonical path still exists during an active round"
# OBS: 
# OBS: FIRST_IMAGE="$(grep -l '^# FIRST_SWITCH_PID: ' "$TMP_ROOT"/.react.image.* || true)"
# OBS: SECOND_IMAGE="$(grep -l '^# SECOND_SWITCH_PID: ' "$TMP_ROOT"/.react.image.* || true)"
# OBS: [[ -n "$FIRST_IMAGE" ]] || fail "first edited context image was not identified"
# OBS: [[ -n "$SECOND_IMAGE" ]] || fail "second edited context image was not identified"
# OBS: [[ "$FIRST_IMAGE" != "$SECOND_IMAGE" ]] || fail "both context edits reused the same image"
# OBS: [[ "$FIRST_IMAGE" != "$TMP_ROOT/ReAct.sh" && "$SECOND_IMAGE" != "$TMP_ROOT/ReAct.sh" ]] ||
# OBS:     fail "context edit reused the currently running image"
# OBS: 
# OBS: "$BASH_UNDER_TEST" -n "$ROUND_IMAGE"
# OBS: "$BASH_UNDER_TEST" -n "$FIRST_IMAGE"
# OBS: "$BASH_UNDER_TEST" -n "$SECOND_IMAGE"
# OBS: 
# OBS: assert_count 1 '^# INPUT: exercise append semantics$' "$ROUND_IMAGE"
# OBS: assert_count 1 '^# STUB_STEP: 1$' "$ROUND_IMAGE"
# OBS: assert_count 1 '^# STUB_STEP: 2$' "$ROUND_IMAGE"
# OBS: assert_count 1 '^# OBS: v1$' "$ROUND_IMAGE"
# OBS: assert_count 1 '^# OBS: v2$' "$ROUND_IMAGE"
# OBS: assert_count 1 '^# TOOL_STATE: v1$' "$ROUND_IMAGE"
# OBS: assert_count 1 '^# TOOL_STATE: v2$' "$ROUND_IMAGE"
# OBS: assert_count 1 '^# EXIT: 0$' "$ROUND_IMAGE"
# OBS: assert_count 1 '^# EXIT: 7$' "$ROUND_IMAGE"
# OBS: assert_count 1 '^# BEFORE_PID: ' "$ROUND_IMAGE"
# OBS: assert_count 0 '^# FIRST_SWITCH_PID: ' "$ROUND_IMAGE"
# OBS: assert_count 0 '^# SECOND_SWITCH_PID: ' "$ROUND_IMAGE"
# OBS: assert_count 1 '^# FIRST_SWITCH_PID: ' "$FIRST_IMAGE"
# OBS: assert_count 1 '^# FIRST_SWITCH_SELF: ' "$FIRST_IMAGE"
# OBS: assert_count 0 '^# SECOND_SWITCH_PID: ' "$FIRST_IMAGE"
# OBS: assert_count 1 '^# INPUT: \[compressed once\] exercise append semantics$' "$FIRST_IMAGE"
# OBS: grep -q '^# <TAPE>$' "$FIRST_IMAGE" || fail "first image has no tape boundary"
# OBS: assert_count 1 '^# SECOND_SWITCH_PID: ' "$SECOND_IMAGE"
# OBS: assert_count 1 '^# SECOND_SWITCH_SELF: ' "$SECOND_IMAGE"
# OBS: assert_count 1 '^# INPUT: \[compressed twice\] exercise append semantics$' "$SECOND_IMAGE"
# OBS: assert_count 1 '^# <TAPE>$' "$SECOND_IMAGE"
# OBS: assert_count 1 '^: "second image resumed"$' "$SECOND_IMAGE"
# OBS: 
# OBS: before_pid="$(sed -n 's/^# BEFORE_PID: //p' "$ROUND_IMAGE")"
# OBS: first_pid="$(sed -n 's/^# FIRST_SWITCH_PID: //p' "$FIRST_IMAGE")"
# OBS: second_pid="$(sed -n 's/^# SECOND_SWITCH_PID: //p' "$SECOND_IMAGE")"
# OBS: [[ "$before_pid" == "$first_pid" && "$first_pid" == "$second_pid" ]] ||
# OBS:     fail "exec changed PID: before=$before_pid first=$first_pid second=$second_pid"
# OBS: 
# OBS: first_self="$(sed -n 's/^# FIRST_SWITCH_SELF: //p' "$FIRST_IMAGE")"
# OBS: second_self="$(sed -n 's/^# SECOND_SWITCH_SELF: //p' "$SECOND_IMAGE")"
# OBS: [[ "$first_self" == "$FIRST_IMAGE" ]] ||
# OBS:     fail "first image saw SELF as $first_self, expected $FIRST_IMAGE"
# OBS: [[ "$second_self" == "$SECOND_IMAGE" ]] ||
# OBS:     fail "second image saw SELF as $second_self, expected $SECOND_IMAGE"
# OBS: 
# OBS: FINISH_ROOT="$TMP_ROOT/finish-case"
# OBS: RUNNING_IMAGE="$FINISH_ROOT/running-image.sh"
# OBS: mkdir "$FINISH_ROOT"
# OBS: cp "$PROJECT_ROOT/ReAct.sh" "$FINISH_ROOT/ReAct.sh"
# OBS: ln "$FINISH_ROOT/ReAct.sh" "$RUNNING_IMAGE"
# OBS: 
# OBS: PATH="$TMP_ROOT/bin:$BASH_DIR:/usr/bin:/bin" \
# OBS: OPENAI_API_KEY=stub \
# OBS: STUB_SCENARIO=finish \
# OBS:     "$BASH_UNDER_TEST" "$FINISH_ROOT/ReAct.sh" "exercise finish semantics" \
# OBS:     >> "$FINISH_ROOT/ReAct.sh"
# OBS: 
# OBS: "$BASH_UNDER_TEST" -n "$RUNNING_IMAGE"
# OBS: "$BASH_UNDER_TEST" -n "$FINISH_ROOT/ReAct.sh"
# OBS: [[ -x "$FINISH_ROOT/ReAct.sh" ]] || fail "canonical image is not executable"
# OBS: cmp -s "$RUNNING_IMAGE" "$FINISH_ROOT/ReAct.sh" &&
# OBS:     fail "finish did not replace the canonical image"
# OBS: 
# OBS: assert_count 1 '^# INPUT: exercise finish semantics$' "$RUNNING_IMAGE"
# OBS: assert_count 1 "^edit_context <<'FINAL_ACTIVE_CONTEXT'$" "$RUNNING_IMAGE"
# OBS: 
# OBS: finish_round_count="$(find "$FINISH_ROOT" -maxdepth 1 -type f -name '.react.round.*' | wc -l | tr -d ' ')"
# OBS: [[ "$finish_round_count" == 1 ]] ||
# OBS:     fail "expected one archived finish round; got $finish_round_count"
# OBS: FINISH_ROUND_IMAGE="$(find "$FINISH_ROOT" -maxdepth 1 -type f -name '.react.round.*')"
# OBS: cmp -s "$RUNNING_IMAGE" "$FINISH_ROUND_IMAGE" ||
# OBS:     fail "de-canonicalized round does not preserve the task-bearing ReAct.sh"
# OBS: 
# OBS: finish_image_count="$(find "$FINISH_ROOT" -maxdepth 1 -type f -name '.react.image.*' | wc -l | tr -d ' ')"
# OBS: [[ "$finish_image_count" == 1 ]] ||
# OBS:     fail "expected one final active context; got $finish_image_count"
# OBS: FINAL_ACTIVE_IMAGE="$(find "$FINISH_ROOT" -maxdepth 1 -type f -name '.react.image.*')"
# OBS: "$BASH_UNDER_TEST" -n "$FINAL_ACTIVE_IMAGE"
# OBS: assert_count 1 '^finish$' "$FINAL_ACTIVE_IMAGE"
# OBS: assert_count 0 '^# EXIT_TRAP_RAN$' "$FINAL_ACTIVE_IMAGE"
# OBS: assert_count 0 '^# AFTER_FINISH: reached$' "$FINAL_ACTIVE_IMAGE"
# OBS: 
# OBS: assert_count 1 '^# CANONICAL_TEST: clean$' "$FINISH_ROOT/ReAct.sh"
# OBS: assert_count 0 '^# INPUT:' "$FINISH_ROOT/ReAct.sh"
# OBS: assert_count 0 '^# OBS:' "$FINISH_ROOT/ReAct.sh"
# OBS: assert_count 1 '^# <TAPE>$' "$FINISH_ROOT/ReAct.sh"
# OBS: assert_structural_image "$FINISH_ROOT/ReAct.sh"
# OBS: [[ "$(tail -n 1 "$FINISH_ROOT/ReAct.sh")" == '# <TAPE>' ]] ||
# OBS:     fail "canonical image does not end at its tape boundary"
# OBS: 
# OBS: EXPECTED_CANONICAL="$FINISH_ROOT/expected-canonical.sh"
# OBS: sed -n '1,/^# <TAPE>$/p' "$FINAL_ACTIVE_IMAGE" > "$EXPECTED_CANONICAL"
# OBS: cmp -s "$EXPECTED_CANONICAL" "$FINISH_ROOT/ReAct.sh" ||
# OBS:     fail "canonical ReAct.sh is not the reusable prefix of the final active context"
# OBS: 
# OBS: final_staging_count="$(find "$FINISH_ROOT" -maxdepth 1 -name '.react.final.*' | wc -l | tr -d ' ')"
# OBS: [[ "$final_staging_count" == 0 ]] ||
# OBS:     fail "finish left $final_staging_count staging files after installation"
# OBS: 
# OBS: printf 'ok: append execution, tool evolution, context editing, round lifecycle, and finish\n'
# OBS: --- README.md ---
# OBS: # Harness in a Shell
# OBS: 
# OBS: ```bash
# OBS: bash ReAct.sh '<prompt>' >> ReAct.sh
# OBS: ```
# OBS: 
# OBS: [中文版](./README.zh-CN.md)
# OBS: 
# OBS: That one shell command is the ReAct loop. In generic form it is
# OBS: `bash agent.sh '<prompt>' >> agent.sh`: model output goes to stdout, stdout is
# OBS: appended to the running script, and the same Bash process continues reading and
# OBS: executing the appended source. There is no explicit `while` loop.
# OBS: 
# OBS: This repository is a research prototype built around three ideas.
# OBS: 
# OBS: ## 1. Script as Context
# OBS: 
# OBS: The active Bash script is the agent's complete context. It contains the
# OBS: governing prompt, runtime identity, tool definitions, user input, observations,
# OBS: execution tape, continuation, and its own context-editing machinery.
# OBS: 
# OBS: `reason` sends the complete current script to the model. The response is not a
# OBS: separate chat message: it is future Bash source appended to that script.
# OBS: 
# OBS: ```text
# OBS: # INPUT: user instructions
# OBS: # OBS:   tool observations
# OBS: # EXIT:  observed exit status
# OBS: # <TAPE> live trajectory begins here
# OBS: ```
# OBS: 
# OBS: Because the script is context, changing the SYSTEM prompt, reorganizing memory,
# OBS: or replacing the reasoning machinery are all ordinary script edits.
# OBS: `edit_context` performs a structural edit by switching to a complete new script.
# OBS: 
# OBS: ## 2. Function as Tool
# OBS: 
# OBS: A Bash function is a tool. The agent may call or redefine an existing function,
# OBS: author a new one, compose tools from other tools, refine old tools, or derive new
# OBS: tools through any recursive combination of authoring, composition, and
# OBS: refinement.
# OBS: 
# OBS: `observe` runs a command or function once in the current shell and records its
# OBS: output and exit status as inert Bash comments. State changes made by a function,
# OBS: such as variables or `cd`, remain live. A state-only function may also be called
# OBS: directly when it produces no unsafe stdout.
# OBS: 
# OBS: The harness itself follows the same rule: `observe`, `reason`, `edit_context`,
# OBS: and `finish` are functions rather than privileged operations outside the script.
# OBS: 
# OBS: ## 3. File as Round
# OBS: 
# OBS: A round is the file-backed lifecycle of one task, not one API call. It begins
# OBS: when a prompt is appended to the canonical `ReAct.sh` and ends when `finish`
# OBS: installs the next canonical `ReAct.sh`. A round may migrate through any number
# OBS: of active image files.
# OBS: 
# OBS: ```text
# OBS: ReAct.sh (clean canonical; previous round complete)
# OBS:   └─ append prompt → ReAct.sh becomes the active, task-bearing file
# OBS:        └─ first edit_context → exec .react.image.* as the new active context
# OBS:             └─ new image startup archives old ReAct.sh as .react.round.*
# OBS:                  └─ canonical pathname remains intentionally absent
# OBS:                       └─ zero or more edit_context transitions
# OBS:                            └─ finish
# OBS:                                 └─ install the active prefix through the first
# OBS:                                    exact # <TAPE> as ReAct.sh (round complete)
# OBS: ```
# OBS: 
# OBS: After the first successful context switch, the newly active image immediately
# OBS: de-canonicalizes the old, task-bearing `ReAct.sh`. Later switches do not repeat
# OBS: that step because the canonical pathname is already absent. At rest,
# OBS: `ReAct.sh` contains the durable state produced by the completed round and serves
# OBS: as the next round's entry. It may be the active file before the first switch,
# OBS: but it never remains as a stale active image after execution has migrated
# OBS: elsewhere.
# OBS: 
# OBS: Before calling `finish`, the agent uses `edit_context` when necessary to promote
# OBS: reusable improvements above the first exact `# <TAPE>` boundary. `finish` then
# OBS: validates that prefix, atomically installs it as `ReAct.sh`, and exits. The new
# OBS: canonical image therefore omits the tape and the `finish` call. `finish` does not
# OBS: decide what knowledge is durable; that semantic edit remains the agent's
# OBS: responsibility.
# OBS: 
# OBS: The first exact line `# <TAPE>` is therefore a format invariant. Reusable source
# OBS: before the real boundary must not contain another identical whole line.
# OBS: 
# OBS: ## Run
# OBS: 
# OBS: Requirements:
# OBS: 
# OBS: - Bash
# OBS: - `curl`
# OBS: - `jq`
# OBS: - `OPENAI_API_KEY`
# OBS: 
# OBS: The default model is `gpt-5.6-sol`; override it with `OPENAI_MODEL`.
# OBS: 
# OBS: ```bash
# OBS: export OPENAI_API_KEY='...'
# OBS: bash ReAct.sh 'Find and fix the failing tests.' >> ReAct.sh
# OBS: ```
# OBS: 
# OBS: The command intentionally modifies `ReAct.sh`, and the canonical pathname may
# OBS: temporarily disappear after the first context switch. This prototype assumes
# OBS: one active round per directory. Git provides the simplest experiment log and
# OBS: reset point.
# OBS: 
# OBS: ## Test without an API key
# OBS: 
# OBS: ```bash
# OBS: bash test.sh
# OBS: ```
# OBS: 
# OBS: The test injects local `curl` and `jq` stubs. It verifies append execution,
# OBS: function evolution and shell-state persistence, repeated context edits,
# OBS: de-canonicalization after the first switch, PID continuity across `exec`, and
# OBS: automatic canonicalization through `finish` on Bash 3.2 and Bash 5.1.
# OBS: 
# OBS: ## Run in a disposable sandbox
# OBS: 
# OBS: Treat model output as arbitrary Bash, not merely as a program that might make a
# OBS: mistake. In particular, do not bind-mount the real repository, home directory,
# OBS: credentials, or a Docker socket into its executor.
# OBS: 
# OBS: The repository includes a container fallback for local experiments. On macOS,
# OBS: start Docker Desktop first:
# OBS: 
# OBS: ```bash
# OBS: open -a Docker
# OBS: bash sandbox.sh test
# OBS: bash sandbox.sh verify
# OBS: ```
# OBS: 
# OBS: `test` runs the stub harness with no network or key. `verify` uses a fake key
# OBS: and checks the isolation policy. The untrusted agent container has a read-only
# OBS: root filesystem, bounded tmpfs, no Linux capabilities, resource limits, no host
# OBS: bind mounts, no Docker socket, no API key, and `network=none`.
# OBS: 
# OBS: For a live run, the agent can only reach a narrow relay through a Unix socket on
# OBS: a read-only-mounted volume. The relay holds the real key, reconstructs only a
# OBS: `POST /v1/responses` request to `api.openai.com`, pins the model, rejects extra
# OBS: API fields, disables hosted tools and streaming, and enforces per-run request,
# OBS: body, response, output-token, and wall-clock limits. The independent host
# OBS: watchdog remains authoritative even if arbitrary Bash attacks its in-container
# OBS: timeout.
# OBS: 
# OBS: ```text
# OBS: agent (arbitrary Bash; network=none; no key)
# OBS:   └─ Unix socket on read-only mount → trusted relay
# OBS:                                       └─ TLS → api.openai.com/v1/responses
# OBS: ```
# OBS: 
# OBS: On a supported Docker installation, run it with:
# OBS: 
# OBS: ```bash
# OBS: export OPENAI_API_KEY='...'
# OBS: bash sandbox.sh run 'Inspect the harness and finish cleanly.'
# OBS: ```
# OBS: 
# OBS: Tune the bounds with `SANDBOX_TIMEOUT_SECONDS`, `SANDBOX_MEMORY`,
# OBS: `SANDBOX_WORK_SIZE`, `OPENAI_MAX_REQUESTS`, and
# OBS: `OPENAI_MAX_OUTPUT_TOKENS`. The cost-conscious defaults allow at most 8 API
# OBS: attempts and 4096 output tokens per attempt; the trusted relay records the
# OBS: actual attempt count in each run directory. Container output is disk-capped and
# OBS: retained under `sandbox-runs/run.*/untrusted-{output,stderr}.bin`; the trusted
# OBS: host runner deliberately does not parse it or render agent-controlled logs in
# OBS: the terminal.
# OBS: A normal run writes a gzip tar stream to `untrusted-output.bin`, but arbitrary
# OBS: Bash can corrupt or forge it. Inspect it only inside another disposable,
# OBS: no-network sandbox, and never execute or source recovered files on the host.
# OBS: 
# OBS: `SANDBOX_BASE_IMAGE` and `SANDBOX_BUILD_PROXY` are build-only escape hatches
# OBS: for an offline cache or a local package proxy. They do not change the runtime
# OBS: network policy and the proxy value is not baked into the resulting image. Once
# OBS: both local images have been built, `SANDBOX_SKIP_BUILD=1` skips all image-build
# OBS: network access; a live `run` still calls the OpenAI API through the relay. Use it
# OBS: only when deliberately testing the already-built image.
# OBS: 
# OBS: This Mac currently runs macOS 12.5.1 and Docker Desktop 4.9.1. That stack is no
# OBS: longer supported and is too old to be the sole boundary for a live arbitrary
# OBS: Bash agent, so `sandbox.sh run` refuses by default on it. For experiments today,
# OBS: run the same script inside a disposable UTM Linux VM with host directory,
# OBS: clipboard, USB, and credential sharing disabled. `ALLOW_LEGACY_DOCKER_SANDBOX=1`
# OBS: exists as an explicit research-risk override, not as a recommendation.
# OBS: 
# OBS: ### Stronger microVM setup
# OBS: 
# OBS: After upgrading to macOS 14 or later, prefer Docker Sandboxes. Initialize its
# OBS: network policy as deny-by-default, use clone mode so the working copy stays in
# OBS: the microVM, scope the OpenAI secret to this sandbox, and allow exactly the API
# OBS: host:
# OBS: 
# OBS: ```bash
# OBS: brew trust docker/tap
# OBS: brew install docker/tap/sbx
# OBS: sbx login
# OBS: sbx policy init deny-all
# OBS: 
# OBS: sbx create shell "$PWD" --clone --no-share-skills --name react-harness --cpus 1 --memory 1g
# OBS: sbx secret set react-harness openai
# OBS: sbx policy allow network --sandbox react-harness api.openai.com:443
# OBS: sbx policy ls --wide
# OBS: sbx run --name react-harness
# OBS: ```
# OBS: 
# OBS: Then, inside the sandbox:
# OBS: 
# OBS: ```bash
# OBS: OPENAI_API_KEY=proxy-managed bash ReAct.sh '<prompt>' >> ReAct.sh
# OBS: ```
# OBS: 
# OBS: Use a staging Git repository containing only files the agent may read; clone
# OBS: mode still exposes the source repository read-only. `--no-share-skills` also
# OBS: prevents the sandbox from receiving Docker's shared host skill store. Remove
# OBS: the microVM with `sbx rm react-harness` after exporting and reviewing the one
# OBS: result you intend to keep.
# OBS: 
# OBS: This remains a research artifact. Canonicalization means a round completed; it
# OBS: does not make the resulting Bash trustworthy.
# EXIT: 0
inspect_doc_sections() {
    printf '%s\n' '--- README.zh-CN relevant sections ---'
    grep -n -A12 -B4 'edit_context\|finish\|测试会' "$ROOT/README.zh-CN.md"
    printf '%s\n' '--- clean runtime prefix ---'
    sed -n '120,230p' "$SELF"
}
observe inspect_doc_sections
reason
# OBS: FAIL: expected 1 matches for '^# EXIT: 0$' in /tmp/harness-in-a-shell.6DFKmp/.react.round.HYMCB9; got 7
# EXIT: 1
edit_context <<'NEW_CONTEXT'
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
# complete image + edit_context = validated context editing / compression
# complete image + finish = validated durable self-evolution across tasks
# canonical ReAct.sh = completed round boundary
#
# Everything, including reasoning itself, is part of the shell image.
# </SYSTEM>

# IMAGE VALIDATION CONTRACT
#
# validate_image accepts one complete image pathname. A valid image has valid
# Bash syntax and exactly one operative SYSTEM opener, SYSTEM closer, and TAPE
# boundary in that order. Both edit_context and finish use this same validator,
# so malformed model-produced replacements cannot become active or canonical.
validate_image() {
    local __react_image="${1-}"

    [[ -n "$__react_image" && -f "$__react_image" ]] || return 1
    "$BASH" -n "$__react_image" || return 1

    awk '
        $0 == "# <SYSTEM>" {
            system_open_count++
            system_open_line = NR
        }
        $0 == "# </SYSTEM>" {
            system_close_count++
            system_close_line = NR
        }
        $0 == "# <TAPE>" {
            tape_count++
            tape_line = NR
        }
        END {
            valid = (
                system_open_count == 1 &&
                system_close_count == 1 &&
                tape_count == 1 &&
                system_open_line < system_close_line &&
                system_close_line < tape_line
            )
            exit(valid ? 0 : 1)
        }
    ' "$__react_image"
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
# Every replacement must reconstruct its governing semantics and adjacent
# comments; SELF, ROOT, and CANONICAL; observe, validate_image, edit_context,
# finish, reason, API machinery, and useful evolved tools. A continuing task
# also preserves its current # INPUT and required memory, then resumes through
# reason after a # <TAPE> boundary. A terminal replacement instead builds a
# clean fresh-task prefix through that boundary and invokes finish after it.
#

# OBS: --- README.zh-CN relevant sections ---
# OBS: 29-# <TAPE> live trajectory 从这里开始
# OBS: 30-```
# OBS: 31-
# OBS: 32-既然脚本就是上下文，那么修改 SYSTEM prompt、重组记忆或替换 reasoning machinery，
# OBS: 33:本质上都只是修改脚本。`edit_context` 通过切换到一份完整的新脚本来完成结构性修改。
# OBS: 34-
# OBS: 35-## 2. 函数即工具（Function as Tool）
# OBS: 36-
# OBS: 37-Bash 函数就是工具。Agent 可以调用或重定义已有函数、从零编写新函数、组合已有
# OBS: 38-工具、改进旧工具，也可以递归地组合“编写、组合、改进”这三类操作来生成新工具。
# OBS: 39-
# OBS: 40-`observe` 在当前 shell 中把命令或函数执行一次，再将输出和退出码记录成不会被执行的
# OBS: 41-Bash 注释。函数造成的变量修改、`cd` 等 shell 状态会继续保留。对于没有危险 stdout
# OBS: 42-的纯状态工具，也可以直接调用而不经过 `observe`。
# OBS: 43-
# OBS: 44:Harness 本身也遵循同一规则：`observe`、`reason`、`edit_context` 和 `finish` 都只是
# OBS: 45-脚本里的函数，并不是脚本外部的特权操作。
# OBS: 46-
# OBS: 47-## 3. 文件即一轮（File as Round）
# OBS: 48-
# OBS: 49-这里的 round 是一个任务在文件系统中的完整生命周期，不是一次 API 调用。Prompt 被
# OBS: 50:追加到 canonical `ReAct.sh` 时，本轮开始；`finish` 安装下一版 canonical
# OBS: 51-`ReAct.sh` 时，本轮结束。一轮可以经过任意多个 active image 文件。
# OBS: 52-
# OBS: 53-```text
# OBS: 54-ReAct.sh（干净的 canonical；上一轮已经完成）
# OBS: 55-  └─ 追加 prompt → ReAct.sh 成为包含本轮任务的 active 文件
# OBS: 56:       └─ 第一次 edit_context → exec .react.image.*，成为新的 active context
# OBS: 57-            └─ 新 image 启动后把旧 ReAct.sh 归档为 .react.round.*
# OBS: 58-                 └─ canonical 路径刻意保持不存在
# OBS: 59:                      └─ 零次或多次 edit_context
# OBS: 60:                           └─ finish
# OBS: 61-                                └─ 截取 active 文件到第一个精确的 # <TAPE>，
# OBS: 62-                                   安装为 ReAct.sh（本轮结束）
# OBS: 63-```
# OBS: 64-
# OBS: 65-第一次 context switch 成功后，新 image 会立即 de-canonicalize 那份已经包含本轮轨迹的
# OBS: 66-旧 `ReAct.sh`。之后的 switch 不会重复归档，因为 canonical 路径已经不存在。这是刻意
# OBS: 67-设计：静止时的 `ReAct.sh` 表示已经完成的 round，也是下一轮的入口；第一次 switch
# OBS: 68-之前它可以同时是 active 文件，但执行迁移后，它绝不会继续指向本轮过时的 active
# OBS: 69-image。
# OBS: 70-
# OBS: 71:调用 `finish` 前，agent 必要时先用 `edit_context`，把值得长期保留的改进提升到第一个
# OBS: 72:精确的 `# <TAPE>` 之前。`finish` 随后验证这个前缀，将其原子安装为 `ReAct.sh`，因此
# OBS: 73:新 canonical image 不包含 tape 和 `finish` 调用，然后退出。哪些知识值得持久化仍由
# OBS: 74:agent 判断，`finish` 只负责机械地完成 canonicalization。
# OBS: 75-
# OBS: 76-因此，第一个精确整行 `# <TAPE>` 是格式不变量。真正边界之前的可复用源码，不能再
# OBS: 77-包含另一行完全相同的内容。
# OBS: 78-
# OBS: 79-## 运行
# OBS: 80-
# OBS: 81-依赖：
# OBS: 82-
# OBS: 83-- Bash
# OBS: 84-- `curl`
# OBS: 85-- `jq`
# OBS: 86-- `OPENAI_API_KEY`
# OBS: --
# OBS: 103-```
# OBS: 104-
# OBS: 105-测试通过本地 `curl`/`jq` stub 验证：追加源码执行、函数演化与 shell 状态持续、重复
# OBS: 106-修改上下文、第一次 switch 后的 de-canonicalization、跨 `exec` 的 PID 连续性，以及
# OBS: 107:`finish` 自动安装 canonical `ReAct.sh`。测试覆盖 Bash 3.2 和 Bash 5.1。
# OBS: 108-
# OBS: 109-## 在可丢弃的 sandbox 中运行
# OBS: 110-
# OBS: 111-应把模型输出视为“任意 Bash”，而不只是“可能误操作的程序”。尤其不要把真实仓库、
# OBS: 112-home 目录、凭证或 Docker socket bind-mount 给执行器。
# OBS: 113-
# OBS: 114-仓库附带了一个供本地实验使用的 container fallback。在 macOS 上先启动 Docker
# OBS: 115-Desktop：
# OBS: 116-
# OBS: 117-```bash
# OBS: 118-open -a Docker
# OBS: 119-bash sandbox.sh test
# OBS: --
# OBS: 141-在受支持的 Docker 环境中运行：
# OBS: 142-
# OBS: 143-```bash
# OBS: 144-export OPENAI_API_KEY='...'
# OBS: 145:bash sandbox.sh run '检查 harness，然后干净地 finish。'
# OBS: 146-```
# OBS: 147-
# OBS: 148-可以通过 `SANDBOX_TIMEOUT_SECONDS`、`SANDBOX_MEMORY`、
# OBS: 149-`SANDBOX_WORK_SIZE`、`OPENAI_MAX_REQUESTS` 和
# OBS: 150-`OPENAI_MAX_OUTPUT_TOKENS` 调整边界。默认最多尝试 8 次 API 调用、每次最多 4096 个
# OBS: 151-输出 token；受信 relay 会把实际尝试次数写进每个 run 目录。Container 输出有磁盘
# OBS: 152-上限，并原样保存在 `sandbox-runs/run.*/untrusted-{output,stderr}.bin`；受信 host
# OBS: 153-runner 刻意不解析它，也不会把 agent 控制的日志渲染到 terminal。正常运行会向
# OBS: 154-`untrusted-output.bin` 写出 gzip tar stream，但任意 Bash 可以破坏或伪造它。只能在
# OBS: 155-另一个可丢弃、无网络的 sandbox 中检查；不要直接在 host 上执行或 `source` 恢复出的
# OBS: 156-文件。
# OBS: 157-
# OBS: --- clean runtime prefix ---
# OBS: # Bash comments       = observations / declarative state
# OBS: # appended Bash       = working memory + future execution
# OBS: # function redefine   = incremental tool evolution
# OBS: # complete image + edit_context = context editing / context compression
# OBS: # complete image + finish = durable self-evolution across tasks
# OBS: # canonical ReAct.sh = completed round boundary
# OBS: #
# OBS: # Everything, including reasoning itself, is part of the shell image.
# OBS: # </SYSTEM>
# OBS: 
# OBS: # EDIT_CONTEXT CONTRACT
# OBS: #
# OBS: # The script is the context. edit_context replaces the complete active script,
# OBS: # so it is the mechanism for any structural self-edit: changing the SYSTEM
# OBS: # prompt, compressing or reorganizing trajectory, consolidating tools, changing
# OBS: # reason, or redesigning the harness. Compression is only one possible edit.
# OBS: #
# OBS: # While another reasoning step may occur, $SELF is append-only. Never rewrite,
# OBS: # truncate, replace, rename, or use sed -i on it: changing its pathname can
# OBS: # split Bash's execution stream from the file reopened by reason. You may freely
# OBS: # modify other files. To edit active context, provide a COMPLETE replacement
# OBS: # image to this function:
# OBS: #
# OBS: #   edit_context <<'NEW_CONTEXT'
# OBS: #   #!/usr/bin/env bash
# OBS: #   ...complete replacement script...
# OBS: #   NEW_CONTEXT
# OBS: #
# OBS: # Every replacement must reconstruct its governing semantics and adjacent
# OBS: # comments; SELF, ROOT, and CANONICAL; observe, edit_context, finish, reason,
# OBS: # API machinery, and useful evolved tools. A continuing task also preserves its
# OBS: # current # INPUT and required memory, then resumes through reason after a
# OBS: # # <TAPE> boundary. A terminal replacement instead builds a clean fresh-task
# OBS: # prefix through that boundary and invokes finish after it.
# OBS: #
# OBS: # Call edit_context directly, never in a pipeline: a pipeline may run it in a
# OBS: # subshell, so exec would replace only that subshell. Quote the heredoc marker
# OBS: # so the old shell cannot expand variables or substitutions in the new script.
# OBS: # Each edit receives a fresh sibling pathname, so repeated edits never truncate
# OBS: # the currently executing $SELF. exec preserves the process but ordinary
# OBS: # functions and non-exported variables do not survive; reconstruct them. The
# OBS: # FILE AS ROUND initialization in the new image automatically de-canonicalizes
# OBS: # ReAct.sh after the first switch of a round.
# OBS: edit_context() {
# OBS:     local __react_next
# OBS: 
# OBS:     __react_next="$(mktemp "$ROOT/.react.image.XXXXXX")" || return
# OBS:     cat > "$__react_next" || return
# OBS:     exec bash "$__react_next" >> "$__react_next"
# OBS: }
# OBS: 
# OBS: # FINISH CONTRACT
# OBS: #
# OBS: # finish makes the current script's reusable prefix canonical. Before calling
# OBS: # it, use edit_context when necessary to place every durable improvement to
# OBS: # semantics, function-adjacent comments, tools, and reason before the first
# OBS: # exact # <TAPE> line. Everything after that boundary is disposable trajectory.
# OBS: #
# OBS: # A typical terminal edit therefore ends like this:
# OBS: #
# OBS: #   ...clean reusable script...
# OBS: #   # <TAPE>
# OBS: #   finish
# OBS: #
# OBS: # Call finish directly with no arguments. It copies $SELF only through that
# OBS: # first boundary, stages the result beside $CANONICAL, verifies its Bash syntax,
# OBS: # makes it executable, atomically installs it as $ROOT/ReAct.sh, clears any EXIT
# OBS: # trap, and exits. The finish call itself and all task-specific input,
# OBS: # observations, actions, and temporary memory after # <TAPE> are automatically
# OBS: # discarded. On failure, the existing canonical image remains installed and
# OBS: # finish returns nonzero.
# OBS: finish() {
# OBS:     local __react_final
# OBS: 
# OBS:     grep -q '^# <TAPE>$' "$SELF" || return
# OBS:     __react_final="$(mktemp "$ROOT/.react.final.XXXXXX")" || return
# OBS:     sed -n '1,/^# <TAPE>$/p' "$SELF" > "$__react_final" || return
# OBS:     bash -n "$__react_final" || return
# OBS:     chmod +x "$__react_final" || return
# OBS:     mv -f "$__react_final" "$CANONICAL" || return
# OBS:     trap - EXIT
# OBS:     builtin exit 0
# OBS: }
# OBS: 
# OBS: reason() {
# OBS:     local system
# OBS:     local -a curl_args
# OBS: 
# OBS:     system="$(
# OBS:         sed -n '/^# <SYSTEM>$/,/^# <\/SYSTEM>$/p' "$SELF" |
# OBS:             sed '1d;$d;s/^# //;s/^#$//'
# OBS:     )" || return
# OBS: 
# OBS:     curl_args=(
# OBS:         -fsS
# OBS:         -H "Content-Type: application/json"
# OBS:         --data-binary @-
# OBS:     )
# OBS:     if [[ -n "$OPENAI_UNIX_SOCKET" ]]; then
# OBS:         curl_args+=(--unix-socket "$OPENAI_UNIX_SOCKET" --noproxy '*')
# OBS:     else
# OBS:         curl_args+=(-H "Authorization: Bearer $OPENAI_API_KEY")
# OBS:     fi
# OBS:     curl_args+=("$OPENAI_RESPONSES_URL")
# OBS: 
# OBS:     (
# OBS:         set -o pipefail
# OBS: 
# OBS:         jq -n \
# OBS:             --arg model "$OPENAI_MODEL" \
# OBS:             --arg instructions "$system" \
# EXIT: 0
# Call edit_context directly, never in a pipeline: a pipeline may run it in a
# subshell, so exec would replace only that subshell. Quote the heredoc marker
# so the old shell cannot expand variables or substitutions in the new script.
# Each candidate receives a fresh sibling pathname and is validated before the
# switch. Failed candidates are removed. exec preserves the process but ordinary
# functions and non-exported variables do not survive; reconstruct them. The
# FILE AS ROUND initialization in the new image automatically de-canonicalizes
# ReAct.sh after the first successful switch of a round.
edit_context() {
    local __react_next

    __react_next="$(mktemp "$ROOT/.react.image.XXXXXX")" || return
    if ! cat > "$__react_next"; then
        rm -f "$__react_next"
        return 1
    fi
    if ! validate_image "$__react_next"; then
        rm -f "$__react_next"
        return 1
    fi
    exec "$BASH" "$__react_next" >> "$__react_next"
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
# first boundary, stages the result beside $CANONICAL, validates the complete
# structural image and its Bash syntax, makes it executable, atomically installs
# it as $ROOT/ReAct.sh, clears any EXIT trap, and exits. The finish call itself
# and all task-specific input, observations, actions, and temporary memory after
# the boundary are discarded. Failed staging files are removed; an existing
# canonical image is not replaced when validation or installation fails.
finish() {
    local __react_final

    __react_final="$(mktemp "$ROOT/.react.final.XXXXXX")" || return
    if ! sed -n '1,/^# <TAPE>$/p' "$SELF" > "$__react_final"; then
        rm -f "$__react_final"
        return 1
    fi
    if ! validate_image "$__react_final"; then
        rm -f "$__react_final"
        return 1
    fi
    if ! chmod +x "$__react_final"; then
        rm -f "$__react_final"
        return 1
    fi
    if ! mv -f "$__react_final" "$CANONICAL"; then
        rm -f "$__react_final"
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

if (($#)); then
    printf '%s\n' "$1" | sed 's/^/# INPUT: /'
fi

# INPUT: improve this harness step by step
# MEMORY: Baseline syntax checks passed. The semantic test failed only because
# MEMORY: this active task's accumulated observations changed an assertion when
# MEMORY: the dirty live ReAct.sh was copied as a fixture. The selected
# MEMORY: incremental improvement is shared structural validation for complete
# MEMORY: images before edit_context activates them or finish canonicalizes
# MEMORY: them, with temporary-file cleanup on validation failures.
# MEMORY: Update isolated tests and both READMEs, run them against a clean
# MEMORY: candidate prefix, then install the validated reusable image.
reason

# <TAPE>
NEW_CONTEXT
