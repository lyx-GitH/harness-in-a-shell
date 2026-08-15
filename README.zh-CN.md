# Shell 里的 Agent Harness

```bash
bash ReAct.sh '<prompt>' >> ReAct.sh
```

[English](./README.md)

这一行 shell 命令就是完整的 ReAct loop。写成通用形式就是
`bash agent.sh '<prompt>' >> agent.sh`：模型输出到 stdout，stdout 被追加回
正在执行的脚本，同一个 Bash 进程继续向下读取并执行刚刚追加的源码。这里没有显式的
`while` 循环。

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

依赖：

- Bash
- `curl`
- `jq`
- `OPENAI_API_KEY`

默认模型是 `gpt-5.6-sol`，可以通过 `OPENAI_MODEL` 覆盖。

```bash
export OPENAI_API_KEY='...'
bash ReAct.sh '找出并修复失败的测试。' >> ReAct.sh
```

这条命令会刻意修改 `ReAct.sh`；第一次 context switch 后，canonical 路径还会暂时
消失。这个原型假设同一目录中同时只有一个 active round。Git 是最简单的实验记录和
复位点。

## 无需 API key 的测试

```bash
bash test.sh
```

测试通过本地 `curl`/`jq` stub 验证：追加源码执行、函数演化与 shell 状态持续、重复
修改上下文、第一次 switch 后的 de-canonicalization、跨 `exec` 的 PID 连续性，以及
`finish` 自动安装 canonical `ReAct.sh`。测试覆盖 Bash 3.2 和 Bash 5.1。

这是一个刻意保持简单的研究原型，不是经过加固的 executor 或 sandbox。
