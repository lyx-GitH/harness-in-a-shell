#!/usr/bin/env bash

set -u
set -o pipefail

DB="${TASKLOG_DB:-./tasklog.jsonl}"
LOCK="${DB}.lock"
MAX_ID=9007199254740991

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
    exit 2
}

die() {
    printf 'tasklog: %s\n' "$*" >&2
    exit 1
}

STATE_JQ='
def exact_keys($wanted):
  (keys | sort) == ($wanted | sort);

def valid_id:
  type == "number"
  and . == floor
  and . > 0
  and . <= 9007199254740991;

reduce .[] as $event (
  {tasks: {}, last_id: 0, line: 0, error: null};

  .line += 1
  | if .error != null then
      .
    elif ($event | type) != "object" then
      .error = "line \(.line): event must be a JSON object"
    elif (($event.type? | type) != "string") then
      .error = "line \(.line): event type must be a string"
    elif $event.type == "add" then
      if (($event | exact_keys(["at", "id", "tags", "title", "type"])) | not) then
        .error = "line \(.line): add event has an invalid schema"
      elif (($event.id | valid_id) | not) then
        .error = "line \(.line): invalid creation ID"
      elif ($event.at | type) != "string" then
        .error = "line \(.line): timestamp must be a string"
      elif (($event.title | type) != "string" or ($event.title | length) == 0) then
        .error = "line \(.line): title must be a nonempty string"
      elif (($event.tags | type) != "array"
             or (all($event.tags[]; type == "string" and length > 0) | not)) then
        .error = "line \(.line): tags must be nonempty strings"
      else
        ($event.id | tostring) as $key
        | if .tasks[$key] != null then
            .error = "line \(.line): duplicate creation ID \($event.id)"
          elif $event.id <= .last_id then
            .error = "line \(.line): creation IDs must be strictly increasing"
          else
            .tasks[$key] = {
              id: $event.id,
              title: $event.title,
              tags: $event.tags,
              status: "open",
              created_at: $event.at,
              updated_at: $event.at
            }
            | .last_id = $event.id
          end
      end
    elif ($event.type == "start"
          or $event.type == "done"
          or $event.type == "reopen") then
      if (($event | exact_keys(["at", "id", "type"])) | not) then
        .error = "line \(.line): transition event has an invalid schema"
      elif (($event.id | valid_id) | not) then
        .error = "line \(.line): invalid transition ID"
      elif ($event.at | type) != "string" then
        .error = "line \(.line): timestamp must be a string"
      else
        ($event.id | tostring) as $key
        | if .tasks[$key] == null then
            .error = "line \(.line): transition references unknown task \($event.id)"
          else
            (if $event.type == "start" then
               {expected: "open", next: "active"}
             elif $event.type == "done" then
               {expected: "active", next: "done"}
             else
               {expected: "done", next: "open"}
             end) as $transition
            | if .tasks[$key].status != $transition.expected then
                .error = "line \(.line): invalid \($event.type) transition for task \($event.id) from \(.tasks[$key].status)"
              else
                .tasks[$key].status = $transition.next
                | .tasks[$key].updated_at = $event.at
              end
          end
      end
    else
      .error = "line \(.line): unknown event type \($event.type)"
    end
)
| if .error != null then
    error(.error)
  else
    del(.line, .error)
  end
'

lock_db() {
    local mode="$1"

    if ! exec 9>>"$LOCK"; then
        die "cannot open lock file: $LOCK"
    fi
    if [[ "$mode" == "exclusive" ]]; then
        flock -x 9 || die "cannot lock database"
    else
        flock -s 9 || die "cannot lock database"
    fi
}

load_state() {
    local tmp line parsed result
    local line_number=0

    tmp="$(mktemp "${TMPDIR:-/tmp}/tasklog-state.XXXXXX")" ||
        return 1

    if [[ -e "$DB" && ! -f "$DB" ]]; then
        printf 'tasklog: database is not a regular file: %s\n' "$DB" >&2
        rm -f "$tmp"
        return 1
    fi

    if [[ -f "$DB" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            line_number=$((line_number + 1))
            if ! parsed="$(
                printf '%s\n' "$line" |
                    jq -e -c -s '
                        if length == 1 then
                            .[0]
                        else
                            error("expected exactly one JSON value")
                        end
                    ' 2>/dev/null
            )"; then
                printf 'tasklog: malformed JSON on line %d\n' "$line_number" >&2
                rm -f "$tmp"
                return 1
            fi
            printf '%s\n' "$parsed" >>"$tmp" || {
                rm -f "$tmp"
                return 1
            }
        done <"$DB"
    fi

    if ! result="$(jq -s -c "$STATE_JQ" "$tmp" 2>&1)"; then
        printf 'tasklog: invalid event history: %s\n' "$result" >&2
        rm -f "$tmp"
        return 1
    fi

    rm -f "$tmp"
    printf '%s\n' "$result"
}

normalize_id() {
    local raw="$1"

    [[ "$raw" =~ ^[1-9][0-9]*$ ]] || return 1
    jq -enr --arg raw "$raw" --argjson maximum "$MAX_ID" '
      ($raw | tonumber) as $id
      | select($id > 0 and $id <= $maximum)
      | select(($id | tostring) == $raw)
      | $id
    ' 2>/dev/null
}

timestamp() {
    if [[ ${TASKLOG_NOW+x} ]]; then
        printf '%s' "$TASKLOG_NOW"
    else
        date -u '+%Y-%m-%dT%H:%M:%SZ'
    fi
}

append_event() {
    local event="$1" original_size=0 existed=0 last_byte='' prefix=''

    if [[ -e "$DB" ]]; then
        existed=1
        original_size="$(wc -c <"$DB")" ||
            die "could not inspect database size"
        if ((original_size > 0)); then
            last_byte="$(tail -c 1 -- "$DB" | od -An -tu1 | tr -d '[:space:]')" ||
                die "could not inspect database terminator"
            [[ "$last_byte" == "10" ]] || prefix=$'\n'
        fi
    fi

    if ! printf '%s%s\n' "$prefix" "$event" >>"$DB"; then
        if ((existed)); then
            truncate -s "$original_size" -- "$DB" 2>/dev/null || true
        else
            rm -f -- "$DB"
        fi
        die "could not append event to database"
    fi
}

command_add() {
    local title='' title_seen=0 tag tags_json state next now event
    local -a tags=()

    while (($#)); do
        case "$1" in
            --title)
                (($# >= 2)) || usage
                ((title_seen == 0)) || die "--title may only be supplied once"
                title="$2"
                title_seen=1
                shift 2
                ;;
            --tag)
                (($# >= 2)) || usage
                tag="$2"
                [[ -n "$tag" ]] || die "tag must not be empty"
                tags+=("$tag")
                shift 2
                ;;
            *)
                die "unknown add argument: $1"
                ;;
        esac
    done

    ((title_seen == 1)) || die "add requires --title"
    [[ -n "$title" ]] || die "title must not be empty"

    lock_db exclusive
    state="$(load_state)" || exit 1
    next="$(jq -er '.last_id + 1' <<<"$state")" ||
        die "could not allocate an ID"
    ((next <= MAX_ID)) || die "ID space exhausted"

    tags_json='[]'
    for tag in "${tags[@]}"; do
        tags_json="$(jq -cn \
            --argjson tags "$tags_json" \
            --arg tag "$tag" \
            '$tags + [$tag]')" || die "could not encode tag"
    done

    now="$(timestamp)" || die "could not obtain timestamp"
    event="$(jq -cnS \
        --arg at "$now" \
        --argjson id "$next" \
        --arg title "$title" \
        --argjson tags "$tags_json" \
        '{type:"add", id:$id, at:$at, title:$title, tags:$tags}')" ||
        die "could not encode event"

    append_event "$event"
    printf '%s\n' "$next"
}

command_transition() {
    local kind="$1" expected="$2" id raw_id state key current now event
    shift 2
    (($# == 1)) || usage

    raw_id="$1"
    id="$(normalize_id "$raw_id")" ||
        die "malformed ID: $raw_id"

    lock_db exclusive
    state="$(load_state)" || exit 1
    key="$id"
    current="$(jq -r --arg key "$key" '.tasks[$key].status // empty' <<<"$state")" ||
        die "could not inspect task"
    [[ -n "$current" ]] || die "no such task: $id"
    [[ "$current" == "$expected" ]] ||
        die "cannot $kind task $id from status $current; expected $expected"

    now="$(timestamp)" || die "could not obtain timestamp"
    event="$(jq -cnS \
        --arg type "$kind" \
        --arg at "$now" \
        --argjson id "$id" \
        '{type:$type, id:$id, at:$at}')" ||
        die "could not encode event"

    append_event "$event"
}

command_show() {
    local id raw_id state task
    (($# == 1)) || usage

    raw_id="$1"
    id="$(normalize_id "$raw_id")" ||
        die "malformed ID: $raw_id"

    lock_db shared
    state="$(load_state)" || exit 1
    if ! task="$(jq -ceS --arg key "$id" '
        if .tasks[$key] == null then empty else .tasks[$key] end
      ' <<<"$state")"; then
        die "no such task: $id"
    fi
    [[ -n "$task" ]] || die "no such task: $id"
    printf '%s\n' "$task"
}

command_list() {
    local status='' status_seen=0 tag='' tag_seen=0 state

    while (($#)); do
        case "$1" in
            --status)
                (($# >= 2)) || usage
                ((status_seen == 0)) ||
                    die "--status may only be supplied once"
                case "$2" in
                    open|active|done) status="$2" ;;
                    *) die "invalid status: $2" ;;
                esac
                status_seen=1
                shift 2
                ;;
            --tag)
                (($# >= 2)) || usage
                ((tag_seen == 0)) || die "--tag may only be supplied once"
                [[ -n "$2" ]] || die "tag must not be empty"
                tag="$2"
                tag_seen=1
                shift 2
                ;;
            *)
                die "unknown list argument: $1"
                ;;
        esac
    done

    lock_db shared
    state="$(load_state)" || exit 1
    jq -er \
        --arg status "$status" \
        --arg tag "$tag" '
          .tasks
          | to_entries
          | map(.value)
          | sort_by(.id)
          | .[]
          | select(($status == "" or .status == $status)
                   and ($tag == "" or (.tags | index($tag)) != null))
          | [.id, .status, .title, (.tags | join(","))]
          | @tsv
        ' <<<"$state"
    case $? in
        0|4) return 0 ;;
        *) return 1 ;;
    esac
}

command_summary() {
    local state

    (($# == 0)) || usage
    lock_db shared
    state="$(load_state)" || exit 1
    jq -cS '
      [.tasks[]?.status] as $statuses
      | {
          open: ([$statuses[] | select(. == "open")] | length),
          active: ([$statuses[] | select(. == "active")] | length),
          done: ([$statuses[] | select(. == "done")] | length),
          total: ($statuses | length)
        }
    ' <<<"$state"
}

command_validate() {
    local state

    (($# == 0)) || usage
    lock_db shared
    state="$(load_state)" || exit 1
    : "$state"
    printf 'valid\n'
}

(($# > 0)) || usage
command_name="$1"
shift

case "$command_name" in
    add) command_add "$@" ;;
    start) command_transition start open "$@" ;;
    done) command_transition done active "$@" ;;
    reopen) command_transition reopen done "$@" ;;
    show) command_show "$@" ;;
    list) command_list "$@" ;;
    summary) command_summary "$@" ;;
    validate) command_validate "$@" ;;
    *) usage ;;
esac
