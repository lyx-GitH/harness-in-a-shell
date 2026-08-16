# Offline event-sourced task tracker

`tasklog.sh` is an offline Bash task tracker backed by an append-only JSON
Lines event log. It requires Bash, `jq`, `flock`, and standard local command
line tools. It does not use a network or external service.

## Database and locking

Set `TASKLOG_DB` to choose the event log:

```bash
export TASKLOG_DB="$PWD/tasks.jsonl"
```

When it is unset, the database is `./tasklog.jsonl` relative to the current
working directory. A sibling `.lock` file serializes readers and writers.
Every successful mutation appends exactly one JSON event after validating the
complete prior history. Failed commands do not alter the database.

If `TASKLOG_NOW` is set, its value is used verbatim as the event timestamp.
Otherwise a current UTC timestamp in `YYYY-MM-DDTHH:MM:SSZ` form is used.

## Commands

```text
tasklog.sh add --title TITLE [--tag TAG ...]
tasklog.sh start ID
tasklog.sh done ID
tasklog.sh reopen ID
tasklog.sh show ID
tasklog.sh list [--status open|active|done] [--tag TAG]
tasklog.sh summary
tasklog.sh validate
```

IDs are positive, monotonically increasing integers. `add` prints the new ID.
The state machine is:

```text
add -> open
open --start--> active
active --done--> done
done --reopen--> open
```

All other transitions fail with a diagnostic.

## Event format

Creation event:

```json
{"at":"2025-01-01T12:00:00Z","id":1,"tags":["work","high priority"],"title":"Write report","type":"add"}
```

Transition events:

```json
{"at":"2025-01-01T12:05:00Z","id":1,"type":"start"}
{"at":"2025-01-01T13:00:00Z","id":1,"type":"done"}
{"at":"2025-01-02T09:00:00Z","id":1,"type":"reopen"}
```

Schemas are strict. Malformed JSON, extra or missing fields, invalid IDs,
duplicate or nonmonotonic creation IDs, unknown task references, empty titles
or tags, and invalid histories are rejected. JSON strings are encoded with
`jq`, preserving spaces, quotes, backslashes, control characters, and UTF-8.

## Output

`show ID` emits one compact canonical JSON object containing `id`, `title`,
`tags`, `status`, `created_at`, and `updated_at`.

`list` emits deterministic TSV sorted by numeric ID:

```text
ID<TAB>STATUS<TAB>TITLE<TAB>COMMA-JOINED-TAGS
```

jq TSV escaping is applied to special characters. Status and tag filters are
intersected. Tag matching is exact and case-sensitive.

`summary` emits deterministic compact JSON:

```json
{"active":1,"done":2,"open":3,"total":6}
```

`validate` prints `valid` when every event and the reconstructed history are
valid.

## Example

```bash
export TASKLOG_DB="$PWD/tasks.jsonl"
./tasklog.sh add --title 'Prepare "release" notes' --tag work --tag 'v 2'
./tasklog.sh start 1
./tasklog.sh show 1
./tasklog.sh list --status active --tag work
./tasklog.sh done 1
./tasklog.sh summary
./tasklog.sh validate
```

For deterministic automation:

```bash
TASKLOG_NOW='2030-01-02T03:04:05Z' \
  ./tasklog.sh add --title 'Scheduled task'
```

On a filesystem mounted `noexec`, invoke scripts through Bash:

```bash
bash ./tasklog.sh summary
bash ./test_tasklog.sh
```

## Verification

The test suite uses and removes an isolated temporary directory. It covers
successful workflows, exact string escaping, filters, invalid transitions,
corrupt histories, default database selection, and byte-for-byte preservation
after failures.

```bash
bash -n tasklog.sh
bash -n test_tasklog.sh
bash test_tasklog.sh
```

## Limitations

- Every operation replays the full log, so work grows linearly with history.
- IDs stop at `9007199254740991`, jq's largest safely represented integer.
- Timestamp strings are stored without semantic validation.
- Tags retain insertion order and may repeat.
- TSV comma-joins tags and is not a lossless tag serialization; use `show` JSON
  when exact tag recovery matters.
- Locking protects cooperating processes that use the same database path.
