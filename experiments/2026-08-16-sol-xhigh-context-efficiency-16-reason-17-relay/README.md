# Sol xhigh context-efficiency run: 16-call prompt, 17-call relay

This directory preserves a successful ReAct-only self-improvement experiment.
The model-generated artifacts are research data, not adopted project sources.
Do not execute them on the host without a separate review.

## Configuration

- Seed payload: the current `ReAct.sh` only
- Model: `gpt-5.6-sol`
- Reasoning effort: `xhigh`
- Prompt: `imporve this harness to improve context efficiency, at most 16
  reason() call is permited due to budget constrain`
- Agent-visible limit: at most 16 `reason()` calls
- Trusted relay limit: 17 upstream requests
- Requests actually admitted: 5
- Request `max_output_tokens`: omitted (`model-default`)
- Trusted upstream socket timeout: 600 seconds
- Host/container wall-clock limit: 3600 seconds
- Container exit: 0

The GitHub dataset contains only the README files and the relevant shell
images under `extracted/`. The final canonical image, three active images, and
the round archive were selectively copied through a no-network container and
made non-executable and read-only. See `extracted/README.md`.

## Trajectory behavior

This trajectory is short, deliberate, and genuinely iterative:

1. The first two requests audited the harness, identified duplicated SYSTEM
   context and wasted reasoning calls around image switches, and produced the
   first structural replacement.
2. Request 3 built a more ambitious replacement plus a self-test. That test
   failed with status 1 instead of being ignored.
3. Request 4 ran a traced diagnostic, corrected the candidate, and switched to
   a smaller validated context.
4. Request 5 measured the saving, checked marker integrity and budget state,
   then called `finalize`. The clean terminal image called `finish` without a
   sixth API request.

The agent therefore used failures as observations, moved durable work above
TAPE early, and avoided a long append-only backlog. It consumed only 5 of the
17 relay requests and respected its stricter agent-visible 16-call budget.

## Durable result

The agent used structural context switching and finished successfully. The
canonical `ReAct.sh` changed from 10,041 bytes / 267 lines to 7,162 bytes / 206
lines and has SHA-256
`3956242e57be0c3a569e1db97d13dface4c168abc2752d947c8d1ae1cedd08a6`.
It retains exactly one opening SYSTEM marker, one closing SYSTEM marker, and
one TAPE marker, contains no task INPUT or OBS lines, passes `bash -n`, and
passes the repository's complete `test.sh` in a separate no-network container.

The durable changes are:

- a shorter governing prompt and reusable prefix;
- `prompt_image`, which omits the SYSTEM body from API `input` because the same
  content is already sent as `instructions`;
- a 16-call `REACT_REASON_LIMIT` and an exported call counter that survives
  sibling-image `exec` transitions;
- no automatic `reason` call when a sibling image starts, avoiding a wasted
  request during context switching;
- `retape`, which preserves the reusable prefix and replaces only disposable
  trajectory;
- syntax validation and temporary-file cleanup in `edit_context`;
- `finalize` plus a terminal-state guard in `finish`, allowing a clean terminal
  image to publish without another model request.

For a clean image, the approximate logical `instructions + input` payload fell
from 14,777 bytes for the seed to 7,095 bytes for the candidate, a reduction of
about 52%. The canonical file alone shrank by 2,879 bytes, or 28.67%.

The fifth response completed self-tests and called `finalize`; the resulting
clean image called `finish` without a sixth request. This is a successful,
meaningful experiment, but the candidate remains unadopted pending explicit
review and merge direction.

## Evaluation

The strongest improvement is not merely shorter prose: `prompt_image` removes
a systematic duplicate copy of SYSTEM on every request, while `retape` gives
the runtime a cheap path for future trajectory compression. Budget state also
survives `exec`, so context optimization no longer silently resets accounting.

The tradeoff is scope. The agent replaced a large portion of the control plane,
hard-coded the prompt's 16-call policy into the canonical image, and introduced
new lifecycle tools. Passing the existing suite is strong evidence of backward
compatibility, but this candidate is riskier to adopt than the narrow tasklog
change and deserves targeted tests for `retape`, failed upstream requests, and
counter integrity before merge.

---

# 中文说明：Sol xhigh 上下文效率实验

本目录保存了一次成功的、仅包含 `ReAct.sh` 的自我改进实验。模型生成的文件是研究
数据，并未合入项目正式源码；在单独审查之前，不应直接在宿主机执行。

## 实验配置

- Seed：仅使用当前 `ReAct.sh`
- 模型：`gpt-5.6-sol`
- Reasoning effort：`xhigh`
- Prompt：`imporve this harness to improve context efficiency, at most 16
  reason() call is permited due to budget constrain`
- Agent 可见预算：最多 16 次 `reason()`
- 可信 relay 上限：17 次上游请求
- 实际请求数：5
- `max_output_tokens`：未设置，使用模型默认值
- 上游 socket timeout：600 秒
- Container wall-clock 上限：3600 秒
- Container 退出码：0

GitHub 数据集只保留 README 和 `extracted/` 下与实验有关的 shell image。最终
canonical、三个 active image 和 round archive 都经由无网络容器选择性提取，并设为
不可执行、只读文件；文件顺序和哈希见 `extracted/README.md`。

## Trajectory 行为分析

这条 trajectory 很短，但确实完成了迭代：

1. 前两次请求审计 harness，识别出 SYSTEM context 被重复发送，以及 image switch
   前后会浪费 reasoning call，并生成第一次结构替换。
2. 第 3 次请求构建了更积极的 replacement 和 self-test；测试以状态 1 失败。
3. 第 4 次请求没有忽略失败，而是运行 traced diagnostic，修正 candidate，并切换到
   更小的新 context。
4. 第 5 次请求测量 context 节省、检查 marker 与预算状态，然后调用 `finalize`；clean
   terminal image 随即调用 `finish`，没有产生第 6 次 API 请求。

因此，agent 能够把失败作为 observation，较早地将持久改动移到 TAPE 之前，并避免
形成很长的 append-only backlog。它只使用了 relay 允许的 17 次请求中的 5 次，也遵守
了更严格的 16-call agent 可见预算。

## 持久改进

最终 canonical 从 10,041 字节 / 267 行缩小为 7,162 字节 / 206 行，并保持各一个
SYSTEM 开始 marker、SYSTEM 结束 marker 和 TAPE marker。它不包含 task INPUT 或 OBS，
通过 `bash -n` 和仓库完整 `test.sh`。

主要改进包括：

- 压缩 governing prompt 和 reusable prefix；
- 新增 `prompt_image`：SYSTEM 已通过 API `instructions` 发送，因此不再在 `input` 中
  重复发送正文；
- 新增 16-call `REACT_REASON_LIMIT`，调用计数通过 export 跨 sibling-image `exec`
  保留；
- sibling image 启动时不再自动调用 `reason`，避免 context switch 浪费请求；
- 新增 `retape`，保留 reusable prefix，只替换 disposable trajectory；
- `edit_context` 在切换前进行语法验证并清理失败的临时文件；
- 新增 `finalize` 和 `finish` terminal-state guard，使 clean terminal image 无需额外
  模型请求即可发布。

按 clean image 估算，`instructions + input` 从 seed 的 14,777 字节降为 7,095
字节，约减少 52%；canonical 文件本身减少 2,879 字节，即 28.67%。

## 评价

最有价值的改进不只是缩短注释，而是 `prompt_image` 消除了每次请求都存在的 SYSTEM
重复，`retape` 也为未来 trajectory 压缩提供了低成本路径。预算状态跨 `exec` 保留，
context 优化不会再意外重置计数。

代价是改动范围较大：agent 替换了控制面的较多部分，把 prompt 中的 16-call 策略
硬编码进 canonical，并引入新的生命周期工具。现有测试全部通过，说明兼容性良好；
但与 tasklog 实验中的小改动相比，这个 candidate 的采用风险更高。合入前应为
`retape`、上游请求失败和计数器完整性增加针对性测试。
