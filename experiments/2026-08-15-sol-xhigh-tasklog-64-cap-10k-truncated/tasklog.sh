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
