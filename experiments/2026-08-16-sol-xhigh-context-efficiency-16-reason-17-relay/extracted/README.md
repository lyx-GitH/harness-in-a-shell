# Extracted image manifest

These files were selectively copied from `../untrusted-output.bin` through a
disposable no-network container. They are model-generated research artifacts,
not adopted sources. Their host permissions are `0444` so they cannot be
executed directly.

## Execution sequence

1. `rounds/react.round.bP4KUe.sh` is the archived initial trajectory-bearing
   canonical image.
2. `images/react.image.70HEyl.sh` is the first structurally rewritten active
   context and contains reasoning calls 3 and 4.
3. `images/react.image.aewujB.sh` is the validated efficient context; reasoning
   call 5 ends by invoking `finalize`.
4. `images/react.image.Gu5NUr.sh` is the clean terminal image and ends with a
   direct `finish` call.
5. `ReAct.sh` is the prefix through the first TAPE boundary installed by
   `finish` as the final canonical image.

## SHA-256

| File | SHA-256 |
| --- | --- |
| `ReAct.sh` | `3956242e57be0c3a569e1db97d13dface4c168abc2752d947c8d1ae1cedd08a6` |
| `images/react.image.70HEyl.sh` | `31a33831035fd514d93de99509b25dc817639a52ec75a40b8d6ac880f4b83831` |
| `images/react.image.aewujB.sh` | `7fd5772786e9a1d04474a6ce275cac7bc9839277ce33a09c3ed0fc50e22f9e23` |
| `images/react.image.Gu5NUr.sh` | `27a7cf20c41fccc0ecc36dbc964799599026a8326aa5ac76373c95b16d4029f5` |
| `rounds/react.round.bP4KUe.sh` | `f158d06a088be99459cc827def7c57668482ee78adcd0634d6235c89a6d834fe` |

---

# 已提取 image 清单（中文）

这些文件通过一次性无网络容器从原始实验数据中选择性复制。它们是模型生成的研究
数据，并非已经采用的源码；加入数据集前已设为不可执行、只读文件。

## 执行顺序

1. `rounds/react.round.bP4KUe.sh`：第一次切换前归档的、带 trajectory 的初始
   canonical image。
2. `images/react.image.70HEyl.sh`：第一次结构重写后的 active context，包含第 3、4
   次 reasoning call。
3. `images/react.image.aewujB.sh`：完成修正和验证的高效 context；第 5 次 reasoning
   call 最后调用 `finalize`。
4. `images/react.image.Gu5NUr.sh`：clean terminal image，末尾直接调用 `finish`。
5. `ReAct.sh`：`finish` 截取首个 TAPE 边界及其之前内容后安装的最终 canonical。

SHA-256 见上方共享表格。
