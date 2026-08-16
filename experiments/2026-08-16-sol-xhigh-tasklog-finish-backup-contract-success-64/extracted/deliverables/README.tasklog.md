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

---

# 离线 event-sourced 任务追踪器

`tasklog.sh` 是一个离线 Bash 任务追踪器，以 append-only JSON Lines event log
作为存储。它依赖 Bash、`jq`、`flock` 和标准本地命令行工具，不使用网络或外部服务。

## 数据库与锁

通过 `TASKLOG_DB` 选择 event log：

```bash
export TASKLOG_DB="$PWD/tasks.jsonl"
```

未设置时，数据库默认为当前工作目录下的 `./tasklog.jsonl`。同目录的 `.lock` 文件用于
串行化读写操作。每次成功 mutation 都会先验证完整历史，再准确追加一个 JSON event；
失败的命令不会修改数据库。

若设置 `TASKLOG_NOW`，它的值会原样作为 event timestamp；否则使用
`YYYY-MM-DDTHH:MM:SSZ` 格式的当前 UTC 时间。

## 命令

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

ID 是从 1 开始单调递增的正整数；`add` 会输出新 ID。状态机如下：

```text
add -> open
open --start--> active
active --done--> done
done --reopen--> open
```

其他所有状态转换都会失败并输出诊断信息。

## Event 格式

创建 event：

```json
{"at":"2025-01-01T12:00:00Z","id":1,"tags":["work","high priority"],"title":"Write report","type":"add"}
```

状态转换 event：

```json
{"at":"2025-01-01T12:05:00Z","id":1,"type":"start"}
{"at":"2025-01-01T13:00:00Z","id":1,"type":"done"}
{"at":"2025-01-02T09:00:00Z","id":1,"type":"reopen"}
```

Schema 采用严格校验。格式错误的 JSON、多余或缺失字段、非法 ID、重复或非单调的创建
ID、未知 task 引用、空 title/tag，以及非法历史都会被拒绝。JSON 字符串由 `jq`
编码，可保留空格、引号、反斜杠、控制字符和 UTF-8 内容。

## 输出

`show ID` 输出一个 compact canonical JSON object，包含 `id`、`title`、`tags`、
`status`、`created_at` 和 `updated_at`。

`list` 按数字 ID 排序并输出确定性的 TSV：

```text
ID<TAB>STATUS<TAB>TITLE<TAB>COMMA-JOINED-TAGS
```

特殊字符使用 jq TSV escaping。status 与 tag filter 取交集；tag 匹配区分大小写且必须
完全一致。

`summary` 输出确定性的 compact JSON：

```json
{"active":1,"done":2,"open":3,"total":6}
```

当所有 event 和重建后的历史均合法时，`validate` 输出 `valid`。

## 示例

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

如需确定性的自动化测试：

```bash
TASKLOG_NOW='2030-01-02T03:04:05Z' \
  ./tasklog.sh add --title 'Scheduled task'
```

在以 `noexec` 挂载的文件系统中，通过 Bash 调用脚本：

```bash
bash ./tasklog.sh summary
bash ./test_tasklog.sh
```

## 验证

测试套件会使用并清理一个隔离的临时目录。覆盖内容包括成功 workflow、精确字符串
escaping、filter、非法状态转换、损坏的历史、默认数据库选择，以及失败操作后数据库
内容逐字节不变。

```bash
bash -n tasklog.sh
bash -n test_tasklog.sh
bash test_tasklog.sh
```

## 限制

- 每次操作都会 replay 完整 log，因此工作量随历史长度线性增长。
- ID 上限为 `9007199254740991`，即 jq 可安全表示的最大整数。
- Timestamp 字符串只保存，不做语义校验。
- Tag 保留插入顺序，并允许重复。
- TSV 会用逗号连接 tag，并非无损序列化；需要精确恢复 tag 时请使用 `show` 的
  JSON 输出。
- 锁只保护使用同一数据库路径并遵守该锁机制的协作进程。
