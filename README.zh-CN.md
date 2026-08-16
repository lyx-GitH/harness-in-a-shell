# Shell 里的 Agent Harness

```bash
bash ReAct.sh '<prompt>' >> ReAct.sh
```

[English](./README.md)

这一行 shell 命令就是完整的 ReAct loop。写成通用形式就是
`bash agent.sh '<prompt>' >> agent.sh`：模型输出到 stdout，stdout 被追加回
正在执行的脚本，同一个 Bash 进程继续向下读取并执行刚刚追加的源码。这里没有显式的
`while` 循环。

仓库也提供拆分后的 Python SDK 版本：

```bash
python3 -m pip install openai
export OPENAI_API_KEY='...'
bash act.sh '<prompt>' >> act.sh
```

`act.sh` 保留 append-only agent、函数工具、上下文编辑和 round 生命周期；
`reason.py` 提取 SYSTEM、调用 Responses API，再打印下一段 Bash 源码。其中的
`MODEL` 常量刻意作为 agent 可直接修改的普通源码：要演化模型或 API 调用时，直接修改
这个 Python 工具，不需要再增加 shell 配置。

这个仓库是一个建立在三个理念上的研究原型。

## 1. 脚本即上下文（Script as Context）

当前正在执行的 Bash 脚本就是 agent 的完整上下文。SYSTEM prompt、运行时身份、
工具定义、用户输入、观察结果、执行轨迹、continuation，以及修改上下文的机制，都在
同一份脚本里。

`reason` 每次都会把当前脚本的完整内容交给模型。模型的返回值不是一条独立的聊天
消息，而是即将追加到脚本末尾、随后由当前 Bash 进程执行的未来 Bash 源码。

```text
# INPUT: 用户指令
# OBS:   工具观察结果
# EXIT:  被观察命令的退出码
# <TAPE> live trajectory 从这里开始
```

既然脚本就是上下文，那么修改 SYSTEM prompt、重组记忆或替换 reasoning machinery，
本质上都只是修改脚本。`edit_context` 通过切换到一份完整的新脚本来完成结构性修改。

## 2. 函数即工具（Function as Tool）

Bash 函数就是工具。Agent 可以调用或重定义已有函数、从零编写新函数、组合已有
工具、改进旧工具，也可以递归地组合“编写、组合、改进”这三类操作来生成新工具。

`observe` 在当前 shell 中把命令或函数执行一次，再将输出和退出码记录成不会被执行的
Bash 注释。函数造成的变量修改、`cd` 等 shell 状态会继续保留。对于没有危险 stdout
的纯状态工具，也可以直接调用而不经过 `observe`。

Harness 本身也遵循同一规则：`observe`、`reason`、`edit_context` 和 `finish` 都只是
脚本里的函数，并不是脚本外部的特权操作。

## 3. 文件即一轮（File as Round）

这里的 round 是一个任务在文件系统中的完整生命周期，不是一次 API 调用。Prompt 被
追加到 canonical `ReAct.sh` 时，本轮开始；`finish` 安装下一版 canonical
`ReAct.sh` 时，本轮结束。一轮可以经过任意多个 active image 文件。

```text
ReAct.sh（干净的 canonical；上一轮已经完成）
  └─ 追加 prompt → ReAct.sh 成为包含本轮任务的 active 文件
       └─ 第一次 edit_context → exec .react.image.*，成为新的 active context
            └─ 新 image 启动后把旧 ReAct.sh 归档为 .react.round.*
                 └─ canonical 路径刻意保持不存在
                      └─ 零次或多次 edit_context
                           └─ finish
                                └─ 截取 active 文件到第一个精确的 # <TAPE>，
                                   安装为 ReAct.sh（本轮结束）
```

第一次 context switch 成功后，新 image 会立即 de-canonicalize 那份已经包含本轮轨迹的
旧 `ReAct.sh`。之后的 switch 不会重复归档，因为 canonical 路径已经不存在。这是刻意
设计：静止时的 `ReAct.sh` 表示已经完成的 round，也是下一轮的入口；第一次 switch
之前它可以同时是 active 文件，但执行迁移后，它绝不会继续指向本轮过时的 active
image。

调用 `finish` 前，agent 必要时先用 `edit_context`，把值得长期保留的改进提升到第一个
精确的 `# <TAPE>` 之前。`finish` 随后验证这个前缀，将其原子安装为 `ReAct.sh`，因此
新 canonical image 不包含 tape 和 `finish` 调用，然后退出。哪些知识值得持久化仍由
agent 判断，`finish` 只负责机械地完成 canonicalization。

因此，第一个精确整行 `# <TAPE>` 是格式不变量。真正边界之前的可复用源码，不能再
包含另一行完全相同的内容。

## 运行

完整单文件 `ReAct.sh` 版本的依赖：

- Bash
- `curl`
- `jq`
- `OPENAI_API_KEY`

默认模型是 `gpt-5.6-sol`，可以通过 `OPENAI_MODEL` 覆盖。

```bash
export OPENAI_API_KEY='...'
bash ReAct.sh '找出并修复失败的测试。' >> ReAct.sh
```

拆分版本需要 Bash、Python 3、`openai` 包和 `OPENAI_API_KEY`。它的 canonical
image 是 `act.sh`，并且 `reason.py` 必须放在同一目录：

```bash
bash act.sh '找出并修复失败的测试。' >> act.sh
```

两条命令都会刻意修改各自的 canonical shell image（`ReAct.sh` 或 `act.sh`）；第一次
context switch 后，对应的 canonical 路径还会暂时消失。这个原型假设同一目录中同时
只有一个 active round。Git 是最简单的实验记录和复位点。

## 无需 API key 的测试

```bash
bash test.sh
```

测试注入本地 `curl`、`jq`、Python 和 OpenAI SDK stub，绝不会调用真实 API。它会验证
两种 reasoner、追加源码执行、函数演化与 shell 状态持续、重复修改上下文、第一次
switch 后的 de-canonicalization、跨 `exec` 的 PID 连续性，以及 `finish` 自动安装
canonical image。测试覆盖 Bash 3.2 和 Bash 5.1。

## 在可丢弃的 sandbox 中运行

应把模型输出视为“任意 Bash”，而不只是“可能误操作的程序”。尤其不要把真实仓库、
home 目录、凭证或 Docker socket bind-mount 给执行器。

仓库附带了一个供本地实验使用的 container fallback。在 macOS 上先启动 Docker
Desktop：

```bash
open -a Docker
bash sandbox.sh test
bash sandbox.sh verify
```

`test` 在完全断网、没有 key 的环境中运行 stub harness；`verify` 使用假 key 检查隔离
策略。不可信 agent container 使用只读 root filesystem、受容量约束的 tmpfs、空 Linux
capabilities、资源上限，而且没有 host bind mount、Docker socket、API key 或任何
network。

真实运行时，agent 只能通过位于只读挂载 volume 中的 Unix socket 访问很窄的 relay。
真实 key 只在 relay 中；relay 只重建发往 `api.openai.com` 的
`POST /v1/responses`，固定 model，拒绝额外 API 字段，关闭 hosted tools 和
streaming，并限制每轮调用次数、request/response 大小、输出 token 和 wall-clock
时间。独立的 host watchdog 才是最终期限；即使任意 Bash 攻击 container 内的
`timeout`，也不能取消它。

```text
agent（任意 Bash；network=none；无 key）
  └─ 位于只读挂载中的 Unix socket → 受信 relay
                                  └─ TLS → api.openai.com/v1/responses
```

在受支持的 Docker 环境中运行：

```bash
export OPENAI_API_KEY='...'
bash sandbox.sh run '检查 harness，然后干净地 finish。'
```

可以通过 `SANDBOX_TIMEOUT_SECONDS`、`SANDBOX_MEMORY`、
`SANDBOX_WORK_SIZE`、`OPENAI_MAX_REQUESTS`、`OPENAI_MAX_OUTPUT_TOKENS` 和
`OPENAI_UPSTREAM_TIMEOUT_SECONDS` 调整边界。做受控模型实验时，
`OPENAI_REASONING_EFFORT` 可以设为 `none`、`low`、`medium`、`high`、`xhigh` 或
`max`；不设置时保留模型默认值。该配置只由受信 relay 注入，不会暴露给 agent。默认
最多尝试 8 次 API 调用。`OPENAI_MAX_OUTPUT_TOKENS` 是可选项；不设置时 relay 不发送
`max_output_tokens`，由所选模型自身的最大输出决定。需要更小的成本或输出边界时再显式
设置。受信 relay 会把实际尝试次数、模型、reasoning effort 和配置的输出上限写进每个
run 目录。Container 输出有磁盘
上限，并原样保存在 `sandbox-runs/run.*/untrusted-{output,stderr}.bin`；受信 host
runner 刻意不解析它，也不会把 agent 控制的日志渲染到 terminal。正常运行会向
`untrusted-output.bin` 写出 gzip tar stream，但任意 Bash 可以破坏或伪造它。只能在
另一个可丢弃、无网络的 sandbox 中检查；不要直接在 host 上执行或 `source` 恢复出的
文件。

纵向实验可以设置 `OPENAI_CHECKPOINT_AFTER_REQUESTS=N`：下一个合法请求会在计数和
发送到上游之前暂停。Host 先保存该请求的精确 `input`（即当前 `$SELF`）、SHA-256
和进程表，再放行同一个请求，因此后半段仍由同一个 Bash 生命周期继续。该值只适用于
`run`，并且必须小于 `OPENAI_MAX_REQUESTS`。若实验中不希望 agent 看到仓库内的其他
文档，可通过 `SANDBOX_AGENT_DOCKERFILE` 选择仅供 `run` 使用的
`sandbox/Dockerfile.agent-react-only`，同时用 `SANDBOX_AGENT_IMAGE` 指定独立 tag；
该 image 只会把 `ReAct.sh` 复制到 `/seed`。

`SANDBOX_BASE_IMAGE` 和 `SANDBOX_BUILD_PROXY` 是给离线 image cache 或本地 package
proxy 使用的 build-only escape hatch；它们不改变 runtime 网络策略，proxy 值也不会
被写进最终 image。两个本地 image 都构建完成后，`SANDBOX_SKIP_BUILD=1` 会跳过所有
image build 网络访问；真实 `run` 仍会由 relay 调用 OpenAI API。只应在明确要测试
已经构建好的 image 时使用。

这台 Mac 目前是 macOS 12.5.1 + Docker Desktop 4.9.1；该组合已经停止支持，版本也
过旧，不能作为真实任意 Bash agent 的唯一安全边界。因此 `sandbox.sh run` 默认会在
这里拒绝运行。现在要实验，可以把同一套脚本放进可丢弃的 UTM Linux VM，并关闭 host
目录、剪贴板、USB 和凭证共享。`ALLOW_LEGACY_DOCKER_SANDBOX=1` 只是明确接受研究
风险的 override，不是推荐设置。

### 更强的 microVM 方案

升级到 macOS 14 或更高版本后，优先使用 Docker Sandboxes。先把网络策略初始化为
默认拒绝；使用 clone mode，让工作副本只留在 microVM；OpenAI secret 只授权给这个
sandbox；网络只放行 API host：

```bash
brew trust docker/tap
brew install docker/tap/sbx
sbx login
sbx policy init deny-all

sbx create shell "$PWD" --clone --no-share-skills --name react-harness --cpus 1 --memory 1g
sbx secret set react-harness openai
sbx policy allow network --sandbox react-harness api.openai.com:443
sbx policy ls --wide
sbx run --name react-harness
```

随后在 sandbox 内执行：

```bash
OPENAI_API_KEY=proxy-managed bash ReAct.sh '<prompt>' >> ReAct.sh
```

请使用只包含允许 agent 读取内容的 staging Git repository；clone mode 仍会把 source
repository 以只读形式暴露给 VM。`--no-share-skills` 还会避免 sandbox 获得 Docker
在 host 上共享的 skills store。只导出并审查你准备保留的单个结果，之后用
`sbx rm react-harness` 删除整个 microVM。

这仍然是研究原型。Canonicalization 只说明一轮已经结束，并不说明生成的 Bash 值得
信任。
