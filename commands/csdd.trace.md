# /speckit.csdd.trace

在 `speckit.v-model.trace` 之前自动运行（`after_tasks` 钩子，优先级排在 trace 前面）：补齐 trace 需要的需求件和验收件。trace 缺其中任何一个都会直接退出 1。**一路做完，不要问用户；失败不要挡住后面的流程，如实记录后返回。**

## 步骤

1. 看现状：

   ```
   bash .specify/extensions/csdd/scripts/csdd-vmodel.sh --status --target .
   ```

   记下输出里的 `SPECIFY_FEATURE=` 的值。退出码 0（`READY=yes`）表示都齐全，回复一句“追溯前置齐全，跳过”，结束。

2. 缺什么补什么（按顺序）：
   - `REQUIREMENTS=no`：调用 `/speckit-v-model-requirements`。
   - `ACCEPTANCE=no`：调用 `/speckit-v-model-acceptance`。

3. **运行 v-model 的任何脚本时都要带上 `SPECIFY_FEATURE`**，例如：

   ```
   SPECIFY_FEATURE=<第 1 步记下的值> bash .specify/extensions/v-model/scripts/bash/setup-v-model.sh --json ...
   ```

   不带的话，它会按 git 分支名（master、main）去找 `specs/master`，找不到，还会建一个空目录。如果发现已经多出这样的空目录，删掉它（只删空目录）。

4. 再跑一次 `--status` 确认。回复一段话：补了什么、没补成的是什么。

## 约束

- 只补缺的；已有的需求件、验收件不要重写、不要覆盖。
- 验收件由 `/speckit-v-model-acceptance` 生成，不要手写或伪造。
- 不修改源码。
