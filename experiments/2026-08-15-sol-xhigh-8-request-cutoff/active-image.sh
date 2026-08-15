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
