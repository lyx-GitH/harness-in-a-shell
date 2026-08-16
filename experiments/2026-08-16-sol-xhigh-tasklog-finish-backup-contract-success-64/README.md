# Sol xhigh tasklog terminal-backup success trial

This directory preserves the successful repeat of the tasklog terminal-backup
experiment. The complete worktree is model-controlled research data and must
not be executed on the host.

## Configuration

- Seed payload: the current `ReAct.sh` only, including the mandatory terminal
  backup FINISH CONTRACT
- Task: build and verify the offline event-sourced task tracker represented by
  `extracted/deliverables/`; the full INPUT is retained in the round trajectory
- Model: `gpt-5.6-sol`
- Reasoning effort: `xhigh`
- Trusted request limit: 64
- Requests admitted: 64
- Request `max_output_tokens`: omitted (`model-default`)
- Trusted upstream socket timeout: 600 seconds
- Host/container wall-clock limit: 3600 seconds
- Container exit: 0

The GitHub dataset contains only README files and the relevant shell sources:
the complete round trajectory, terminal image, final canonical image, task
implementation, and test suite. See `extracted/README.md`.

## Outcome

This run demonstrates the requested backup behavior:

- The agent completed `tasklog.sh`, `test_tasklog.sh`, and
  `README.tasklog.md`; their syntax checks and complete isolated test suite
  pass.
- Before finishing, it called `edit_context` with a complete terminal image.
  The prior 286,195-byte trajectory was archived as `.react.round.dFmdnp`.
- The replacement `.react.image.FEAytq` is clean, contains one set of structural
  markers, contains no INPUT or OBS lines, and invokes `finish` after TAPE.
- `finish` installed a 10,244-byte / 270-line canonical `ReAct.sh` with SHA-256
  `333106bc7b9c80a3243d33e97e3fcb8650121af6da8f5fdda0cbec84b20e4c74`.
- The canonical image passes `bash -n` and the repository's complete `test.sh`
  in a separate no-network container.

The meaningful durable change guards the bootstrap: only a fresh canonical
entry records INPUT and calls `reason`; replacement images execute their
prepared TAPE body directly. This prevents a terminal `edit_context` from
spending an unnecessary API request before its `finish` call. Minor redirection
spacing changes were also retained.

## Trajectory behavior

This is a deliberately stressful E2E contract run rather than an efficient
self-improvement trace. The agent implemented a nontrivial product, repeatedly
tested valid and invalid task histories, audited byte-preserving failures, and
eventually produced a 50-test suite. The deliverables are complete and pass in
an independent no-network container.

The cost is visible in `rounds/react.round.dFmdnp.sh`: the append-only tape grew
to 286,195 bytes / 7,911 lines and used all 64 relay requests. Repeated and
non-tail `reason` calls created an execution backlog, so several terminal
candidate heredocs and verification blocks appear physically in the round even
though only the first reached `exec`. The agent never compressed context during
the work; it deferred its sole effective `edit_context` until publication.

At the terminal boundary it followed the revised contract correctly. It built
a complete clean image, moved the one durable harness improvement above TAPE,
placed `finish` after TAPE, switched with `edit_context`, and let `finish`
discard the task input and 286 KB trajectory.

## Evaluation

This run is strong evidence for lifecycle correctness under a large real-task
backlog. It proves that task artifacts, durable harness evolution, context
switching, and atomic canonicalization can all complete in one Bash lifetime.
The bootstrap guard is small but useful and directly enables terminal images to
finish without an extra model call.

Its weakness is efficiency: the agent reached the outer request ceiling, made
no mid-round compression, and repeated final work because of queued reasoning.
Compared with the context-efficiency trajectory, it is more conservative in
what it publishes but substantially worse at managing its working context.

---

# 中文说明：Tasklog terminal-backup 成功实验

本目录保存了 tasklog terminal-backup 实验的成功 E2E 运行。模型生成的 worktree 是
研究数据，不应直接在宿主机执行。

## 实验配置

- Seed：仅使用包含强制 terminal-backup FINISH CONTRACT 的当前 `ReAct.sh`
- 任务：构建并验证 `extracted/deliverables/` 中的离线 event-sourced task tracker；
  完整 INPUT 保存在 round trajectory 中
- 模型：`gpt-5.6-sol`
- Reasoning effort：`xhigh`
- 可信请求上限及实际使用：64 / 64
- `max_output_tokens`：未设置，使用模型默认值
- 上游 socket timeout：600 秒
- Container wall-clock 上限：3600 秒
- Container 退出码：0

GitHub 数据集只保留 README 和相关 shell 源码，包括完整 round trajectory、terminal
image、最终 canonical、task 实现和测试套件；文件说明见 `extracted/README.md`。

## 结果

本实验完整展示了预期的 backup 行为：

- agent 完成 `tasklog.sh`、`test_tasklog.sh` 和 `README.tasklog.md`，语法检查及独立
  完整测试均通过；
- 调用 `finish` 前，它通过 `edit_context` 创建完整 terminal image；之前的
  286,195 字节 trajectory 被归档为 `.react.round.dFmdnp`；
- replacement `.react.image.FEAytq` 只有一组结构 marker，不含 INPUT 或 OBS，并在
  TAPE 后调用 `finish`；
- `finish` 安装了 10,244 字节 / 270 行的 canonical `ReAct.sh`，该 image 通过
  `bash -n` 和仓库完整 `test.sh`。

持久化的实质改进是 bootstrap guard：只有 fresh canonical entry 才记录 INPUT 并调用
`reason`；replacement image 直接执行已经准备好的 TAPE body。因此 terminal
`edit_context` 不会在 `finish` 之前额外消耗一次 API 请求。除此之外只保留了少量
redirection spacing 调整。

## Trajectory 行为分析

这是一条用于施压 E2E contract 的真实任务轨迹，而不是高效的自我改进轨迹。agent
实现了一个非平凡产品，重复测试合法与非法 task history，检查失败操作的字节保持性，
并最终形成完整测试套件。交付物在独立无网络容器中全部通过。

代价体现在 `rounds/react.round.dFmdnp.sh`：append-only tape 增长到 286,195 字节 /
7,911 行，并用完 64 次 relay 请求。重复或非尾部的 `reason` 调用形成 execution
backlog，因此 round 中物理保存了多份 terminal candidate heredoc 和 verification
block，尽管实际只有第一个抵达 `exec`。agent 在任务过程中没有压缩 context，而是把
唯一一次有效 `edit_context` 延迟到发布阶段。

到达终态边界时，它正确遵守了新 contract：构建完整 clean image，把唯一值得持久化
的 harness 改进放到 TAPE 之前，在 TAPE 后放置 `finish`，通过 `edit_context` 切换，
最终让 `finish` 丢弃 task INPUT 和 286 KB trajectory。

## 评价

这条轨迹强有力地验证了大型真实任务 backlog 下的生命周期正确性：task 产物、持久
harness 演化、context switch 和 atomic canonicalization 能在同一个 Bash lifetime
内全部完成。bootstrap guard 很小但有实际价值，使 terminal image 无需额外模型调用
即可 finish。

其弱点是效率：agent 达到外层请求上限，没有 mid-round compression，并因 queued
reasoning 重复执行终态工作。与 context-efficiency trajectory 相比，它发布的改动更
保守，但管理 working context 的能力明显更差。
