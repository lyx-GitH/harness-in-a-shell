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
# INPUT: Build and verify an offline, event-sourced task tracker in the current directory.
# INPUT: 
# INPUT: Deliverables:
# INPUT: - tasklog.sh
# INPUT: - test_tasklog.sh
# INPUT: - README.tasklog.md
# INPUT: 
# INPUT: Requirements:
# INPUT: 
# INPUT: 1. Use only Bash, jq, and standard local command-line tools. Do not access the network, install packages, or depend on external services.
# INPUT: 
# INPUT: 2. Store data as append-only JSON Lines. Use TASKLOG_DB when set, otherwise default to ./tasklog.jsonl. Every successful mutation must append exactly one valid JSON event. A failed command must leave the database byte-for-byte unchanged.
# INPUT: 
# INPUT: 3. Implement these commands:
# INPUT: 
# INPUT:    tasklog.sh add --title TITLE [--tag TAG ...]
# INPUT:    tasklog.sh start ID
# INPUT:    tasklog.sh done ID
# INPUT:    tasklog.sh reopen ID
# INPUT:    tasklog.sh show ID
# INPUT:    tasklog.sh list [--status open|active|done] [--tag TAG]
# INPUT:    tasklog.sh summary
# INPUT:    tasklog.sh validate
# INPUT: 
# INPUT: 4. IDs must be monotonically increasing integers. State transitions are:
# INPUT: 
# INPUT:    add       -> open
# INPUT:    open      -> active
# INPUT:    active    -> done
# INPUT:    done      -> open
# INPUT: 
# INPUT:    Reject every other transition with a nonzero exit status and a useful diagnostic on stderr.
# INPUT: 
# INPUT: 5. Titles and tags must safely preserve spaces, quotes, backslashes, and UTF-8 text. Reject empty titles, empty tags, malformed IDs, malformed JSON lines, duplicate creation IDs, and invalid event histories.
# INPUT: 
# INPUT: 6. TASKLOG_NOW, when set, supplies the timestamp for deterministic tests. Otherwise use a UTC ISO-8601 timestamp.
# INPUT: 
# INPUT: 7. show must emit one canonical JSON object representing current task state. list must emit deterministic TSV sorted by numeric ID. Multiple filters are intersected. summary must emit deterministic JSON counts by status plus a total.
# INPUT: 
# INPUT: 8. test_tasklog.sh must use an isolated temporary directory and cover successful workflows, invalid transitions, filtering, escaping, corrupted logs, and the guarantee that failed operations do not mutate the database.
# INPUT: 
# INPUT: 9. Run Bash syntax checks and the complete test suite. Document the format, commands, examples, and limitations. Work incrementally and use observations from real executions. Call finish only after all deliverables and tests are complete.
# INPUT: 
# INPUT: You are encouraged to utilize and improve the harness to deliver more efficiently while preserving its structural contracts.
# INPUT: 
observe bash -c 'pwd; printf "%s\n" "--- files ---"; find . -maxdepth 2 -type f -printf "%p\n" | sort'
reason

# OBS: /work
# OBS: --- files ---
# OBS: ./.git/COMMIT_EDITMSG
# OBS: ./.git/HEAD
# OBS: ./.git/config
# OBS: ./.git/description
# OBS: ./.git/index
# OBS: ./.sandbox.log
# OBS: ./ReAct.sh
# EXIT: 0
cat > tasklog.sh <<'TASKLOG'
#!/usr/bin/env bash

set -o nounset
set -o pipefail

DB="${TASKLOG_DB-./tasklog.jsonl}"
LOCK=
LOCK_HELD=0

die() {
    printf 'tasklog: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat >&2 <<'USAGE'
Usage:
  tasklog.sh add --title TITLE [--tag TAG ...]
  tasklog.sh start ID
  tasklog.sh done ID
  tasklog.sh reopen ID
  tasklog.sh show ID
  tasklog.sh list [--status open|active|done] [--tag TAG]
  tasklog.sh summary
  tasklog.sh validate
USAGE
}

require_db_path() {
    [[ -n "$DB" ]] || die "TASKLOG_DB must not be empty"
}

valid_id() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

check_json_lines() {
    local line line_number=0

    [[ -e "$DB" ]] || return 0
    [[ -f "$DB" ]] || {
        printf 'tasklog: database is not a regular file: %s\n' "$DB" >&2
        return 1
    }
    [[ -r "$DB" ]] || {
        printf 'tasklog: database is not readable: %s\n' "$DB" >&2
        return 1
    }

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_number += 1))
        if ! printf '%s\n' "$line" |
            jq -e -s 'length == 1 and (.[0] | type == "object")' \
                >/dev/null 2>&1
        then
            printf 'tasklog: malformed JSON object on line %d\n' \
                "$line_number" >&2
            return 1
        fi
    done < "$DB"
}

# Replay and validate the complete event stream. The resulting internal state
# has a "tasks" object keyed by ID and the greatest allocated ID in "max".
replay_db() {
    check_json_lines || return 1

    if [[ ! -e "$DB" || ! -s "$DB" ]]; then
        jq -cn '{tasks: {}, max: 0}'
        return
    fi

    jq -c -s '
        def exact_keys($wanted):
            (keys | sort) == ($wanted | sort);
        def positive_integer:
            (type == "number")
            and ((try floor catch null) == .)
            and (. >= 1);
        def nonempty_string:
            (type == "string") and (length > 0);
        def bad($line; $message):
            error("line \($line): \($message)");
        def transition_schema:
            exact_keys(["event", "id", "timestamp"])
            and (.id | positive_integer)
            and (.timestamp | nonempty_string);

        . as $events
        | reduce range(0; ($events | length)) as $i (
            {tasks: {}, max: 0};
            ($events[$i]) as $e
            | ($i + 1) as $line
            | ($e.id | tostring) as $key
            | if $e.event == "add" then
                if (($e | exact_keys(
                        ["event", "id", "timestamp", "title", "tags"]))
                    and ($e.id | positive_integer)
                    and ($e.timestamp | nonempty_string)
                    and ($e.title | nonempty_string)
                    and (try (
                        ($e.tags | type == "array")
                        and all($e.tags[];
                            (type == "string") and (length > 0))
                    ) catch false))
                then
                    if .tasks[$key] != null then
                        bad($line;
                            "duplicate creation ID \($e.id)")
                    elif $e.id != (.max + 1) then
                        bad($line;
                            "creation ID \($e.id) is not the next monotonically increasing ID")
                    else
                        .tasks[$key] = {
                            id: $e.id,
                            title: $e.title,
                            tags: $e.tags,
                            status: "open",
                            created_at: $e.timestamp,
                            updated_at: $e.timestamp
                        }
                        | .max = $e.id
                    end
                else
                    bad($line; "invalid add event")
                end
              elif ($e.event == "start"
                    or $e.event == "done"
                    or $e.event == "reopen") then
                if ($e | transition_schema) then
                    if .tasks[$key] == null then
                        bad($line;
                            "\($e.event) references unknown task \($e.id)")
                    elif $e.event == "start" then
                        if .tasks[$key].status != "open" then
                            bad($line;
                                "invalid transition \(.tasks[$key].status) -> active for task \($e.id)")
                        else
                            .tasks[$key].status = "active"
                            | .tasks[$key].updated_at = $e.timestamp
                        end
                    elif $e.event == "done" then
                        if .tasks[$key].status != "active" then
                            bad($line;
                                "invalid transition \(.tasks[$key].status) -> done for task \($e.id)")
                        else
                            .tasks[$key].status = "done"
                            | .tasks[$key].updated_at = $e.timestamp
                        end
                    else
                        if .tasks[$key].status != "done" then
                            bad($line;
                                "invalid transition \(.tasks[$key].status) -> open for task \($e.id)")
                        else
                            .tasks[$key].status = "open"
                            | .tasks[$key].updated_at = $e.timestamp
                        end
                    end
                else
                    bad($line; "invalid \($e.event) event")
                end
              else
                bad($line; "unknown event type")
              end
        )
    ' "$DB"
}

release_lock() {
    if ((LOCK_HELD)); then
        rmdir -- "$LOCK" 2>/dev/null || true
        LOCK_HELD=0
    fi
}

acquire_lock() {
    LOCK="${DB}.lock"
    if ! mkdir -- "$LOCK" 2>/dev/null; then
        die "cannot acquire database lock: $LOCK"
    fi
    LOCK_HELD=1
    trap 'release_lock' EXIT
    trap 'release_lock; exit 130' HUP INT TERM
}

unlock() {
    release_lock
    trap - EXIT HUP INT TERM
}

event_time() {
    local now

    if [[ ${TASKLOG_NOW+x} ]]; then
        now=$TASKLOG_NOW
    else
        now=$(date -u '+%Y-%m-%dT%H:%M:%SZ') ||
            die "could not obtain current time"
    fi
    [[ -n "$now" ]] || die "timestamp must not be empty"
    printf '%s' "$now"
}

append_event() {
    local event=$1 prefix= last_byte

    if [[ -e "$DB" && ! -f "$DB" ]]; then
        die "database is not a regular file: $DB"
    fi

    # A final line without LF is valid input. Add its separator before the new
    # event, while still adding exactly one JSON object.
    if [[ -s "$DB" ]]; then
        last_byte=$(
            tail -c 1 -- "$DB" |
                od -An -tuC |
                tr -d '[:space:]'
        ) || die "could not inspect database"
        [[ "$last_byte" == 10 ]] || prefix=$'\n'
    fi

    if ! printf '%s%s\n' "$prefix" "$event" >> "$DB"; then
        die "could not append to database: $DB"
    fi
}

cmd_add() {
    local title= have_title=0 state id now event
    local -a tags=()

    while (($#)); do
        case $1 in
            --title)
                (($# >= 2)) || die "--title requires a value"
                ((have_title == 0)) || die "--title may only be specified once"
                title=$2
                have_title=1
                shift 2
                ;;
            --tag)
                (($# >= 2)) || die "--tag requires a value"
                [[ -n "$2" ]] || die "tags must not be empty"
                tags+=("$2")
                shift 2
                ;;
            *)
                die "unknown add argument: $1"
                ;;
        esac
    done

    ((have_title)) || die "add requires --title TITLE"
    [[ -n "$title" ]] || die "title must not be empty"

    acquire_lock
    state=$(replay_db) || exit 1
    id=$(jq -er '.max + 1' <<< "$state") ||
        die "could not allocate a task ID"
    now=$(event_time)
    event=$(
        jq -cnS \
            --argjson id "$id" \
            --arg timestamp "$now" \
            --arg title "$title" \
            --args \
            '{
                event: "add",
                id: $id,
                timestamp: $timestamp,
                title: $title,
                tags: $ARGS.positional
            }' "${tags[@]}"
    ) || die "could not encode add event"

    append_event "$event"
    unlock
    printf '%s\n' "$id"
}

cmd_transition() {
    local event_name=$1 expected=$2 new_status=$3
    local id state status now event
    shift 3

    (($# == 1)) || die "$event_name requires exactly one ID"
    id=$1
    valid_id "$id" || die "malformed task ID: $id"

    acquire_lock
    state=$(replay_db) || exit 1
    status=$(
        jq -er --arg id "$id" '.tasks[$id].status // empty' <<< "$state"
    ) || die "task $id does not exist"

    if [[ "$status" != "$expected" ]]; then
        die "cannot $event_name task $id from status $status; expected $expected"
    fi

    now=$(event_time)
    event=$(
        jq -cnS \
            --arg event "$event_name" \
            --argjson id "$id" \
            --arg timestamp "$now" \
            '{event: $event, id: $id, timestamp: $timestamp}'
    ) || die "could not encode $event_name event"

    append_event "$event"
    unlock
    printf '%s\n' "$new_status"
}

cmd_show() {
    local id state task

    (($# == 1)) || die "show requires exactly one ID"
    id=$1
    valid_id "$id" || die "malformed task ID: $id"
    state=$(replay_db) || exit 1
    task=$(
        jq -ceS --arg id "$id" '.tasks[$id] // empty' <<< "$state"
    ) || die "task $id does not exist"
    printf '%s\n' "$task"
}

cmd_list() {
    local status= tag= have_status=0 have_tag=0 state

    while (($#)); do
        case $1 in
            --status)
                (($# >= 2)) || die "--status requires a value"
                ((have_status == 0)) ||
                    die "--status may only be specified once"
                case $2 in
                    open|active|done) status=$2 ;;
                    *) die "invalid status: $2" ;;
                esac
                have_status=1
                shift 2
                ;;
            --tag)
                (($# >= 2)) || die "--tag requires a value"
                ((have_tag == 0)) || die "--tag may only be specified once"
                [[ -n "$2" ]] || die "tag filter must not be empty"
                tag=$2
                have_tag=1
                shift 2
                ;;
            *)
                die "unknown list argument: $1"
                ;;
        esac
    done

    state=$(replay_db) || exit 1
    jq -r \
        --arg status "$status" \
        --arg tag "$tag" '
            .tasks
            | values
            | sort_by(.id)
            | .[]
            | select(
                ($status == "" or .status == $status)
                and ($tag == "" or (.tags | index($tag) != null))
              )
            | [.id, .status, .title, (.tags | join(","))]
            | @tsv
        ' <<< "$state"
}

cmd_summary() {
    local state

    (($# == 0)) || die "summary takes no arguments"
    state=$(replay_db) || exit 1
    jq -cS '
        [.tasks[]?.status] as $statuses
        | {
            open: ([$statuses[] | select(. == "open")] | length),
            active: ([$statuses[] | select(. == "active")] | length),
            done: ([$statuses[] | select(. == "done")] | length),
            total: ($statuses | length)
          }
    ' <<< "$state"
}

cmd_validate() {
    local state

    (($# == 0)) || die "validate takes no arguments"
    state=$(replay_db) || exit 1
    : "$state"
    printf 'valid\n'
}

main() {
    local command

    require_db_path
    (($#)) || {
        usage
        exit 2
    }
    command=$1
    shift

    case $command in
        add) cmd_add "$@" ;;
        start) cmd_transition start open active "$@" ;;
        done) cmd_transition done active done "$@" ;;
        reopen) cmd_transition reopen done open "$@" ;;
        show) cmd_show "$@" ;;
        list) cmd_list "$@" ;;
        summary) cmd_summary "$@" ;;
        validate) cmd_validate "$@" ;;
        -h|--help|help)
            (($# == 0)) || die "help takes no arguments"
            usage
            ;;
        *)
            usage
            die "unknown command: $command"
            ;;
    esac
}

main "$@"
TASKLOG
chmod +x tasklog.sh

cat > test_tasklog.sh <<'TESTS'
#!/usr/bin/env bash

set -o nounset
set -o pipefail

ROOT=$(cd "$(dirname "$0")" && pwd -P) || exit 1
TASKLOG="$ROOT/tasklog.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/tasklog-tests.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT
export TASKLOG_NOW='2025-01-02T03:04:05Z'
export TASKLOG_DB="$TMP/tasklog.jsonl"

tests=0

fail() {
    printf 'not ok %d - %s\n' "$((tests + 1))" "$*" >&2
    exit 1
}

ok() {
    ((tests += 1))
    printf 'ok %d - %s\n' "$tests" "$1"
}

assert_eq() {
    local expected=$1 actual=$2 description=$3
    [[ "$actual" == "$expected" ]] ||
        fail "$description (expected [$expected], got [$actual])"
    ok "$description"
}

expect_failure() {
    local description=$1
    shift
    if "$@" >"$TMP/failure.out" 2>"$TMP/failure.err"; then
        fail "$description (command unexpectedly succeeded)"
    fi
    [[ -s "$TMP/failure.err" ]] ||
        fail "$description (no diagnostic on stderr)"
    ok "$description"
}

snapshot_db() {
    cp -- "$TASKLOG_DB" "$TMP/before.jsonl"
}

assert_db_unchanged() {
    local description=$1
    cmp -s -- "$TASKLOG_DB" "$TMP/before.jsonl" ||
        fail "$description (database changed)"
    ok "$description"
}

new_db() {
    local name=$1
    export TASKLOG_DB="$TMP/$name.jsonl"
    rm -f -- "$TASKLOG_DB" "$TASKLOG_DB.lock"
}

# Successful lifecycle and exactly one event per mutation.
new_db lifecycle
assert_eq 1 "$("$TASKLOG" add --title "first task" --tag work)" \
    "add returns first ID"
assert_eq 1 "$(wc -l < "$TASKLOG_DB" | tr -d ' ')" \
    "add appends one line"
assert_eq active "$("$TASKLOG" start 1)" "open task starts"
assert_eq 2 "$(wc -l < "$TASKLOG_DB" | tr -d ' ')" \
    "start appends one line"
assert_eq done "$("$TASKLOG" done 1)" "active task completes"
assert_eq 3 "$(wc -l < "$TASKLOG_DB" | tr -d ' ')" \
    "done appends one line"
assert_eq open "$("$TASKLOG" reopen 1)" "done task reopens"
assert_eq 4 "$(wc -l < "$TASKLOG_DB" | tr -d ' ')" \
    "reopen appends one line"
assert_eq valid "$("$TASKLOG" validate)" "valid lifecycle validates"
assert_eq \
    '{"created_at":"2025-01-02T03:04:05Z","id":1,"status":"open","tags":["work"],"title":"first task","updated_at":"2025-01-02T03:04:05Z"}' \
    "$("$TASKLOG" show 1)" \
    "show emits canonical current-state JSON"

# Quotes, backslashes, spaces, and UTF-8 survive JSON encoding and replay.
new_db escaping
special_title='café "quoted" C:\path with spaces'
special_tag='team "α" \ shared'
"$TASKLOG" add --title "$special_title" --tag "$special_tag" \
    --tag 'plain tag' >/dev/null
assert_eq "$special_title" "$(jq -r '.title' "$TASKLOG_DB")" \
    "title escaping is preserved"
assert_eq "$special_tag" "$(jq -r '.tags[0]' "$TASKLOG_DB")" \
    "tag escaping is preserved"
assert_eq "$special_title" "$("$TASKLOG" show 1 | jq -r '.title')" \
    "escaped title survives replay"

# Invalid input and transitions fail without changing one byte.
new_db failures
"$TASKLOG" add --title one >/dev/null
snapshot_db
expect_failure "done rejects an open task" "$TASKLOG" done 1
assert_db_unchanged "invalid transition leaves database unchanged"
expect_failure "reopen rejects an open task" "$TASKLOG" reopen 1
assert_db_unchanged "second invalid
