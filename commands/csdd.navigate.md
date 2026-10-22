# /speckit.csdd.navigate

新增模块或实现前，先看清现有结构，目标是复用优先、改动最小。

## 步骤

1. 运行（只读，不写文件）：

   ```
   bash .specify/extensions/csdd/scripts/csdd-navigate.sh --target .
   ```

   把退出码和输出原样告诉用户。

2. 根据输出：
   - 没装 `blueprint-index` 或 `brownkit`：告诉用户，并提示 `/speckit.csdd.extensions` 里有安装方式。不要自行安装。
   - 地图不存在：建议用户运行 `/speckit.blueprint-index.init --from-code`，由用户决定。
   - 有 UNMAPPED、STALE 项：列给用户，不要自行 remap。

3. 在要新增的模块范围内，**读代码**找职责相近的现有实现，不要只凭文件名判断。

4. 写下复用检查结论，四选一：直接复用 / 配置 / 适配 / 无满足条件，并写明依据。

5. 若要修改已有功能，先找出实际被入口调用的那个实现，记录依据和证据等级（静态确认 / 运行时确认 / 推断 / 未知）。证据不足写“未知”。

## 要知道的限制

- 这个命令靠用户显式触发。评估里 BrownKit 的技能在没人点名时不会被自发调用，所以不要指望 agent 会自己想起来用。
- `blueprint-index` 的 `check` 是确定性漂移门禁，检查地图和代码是否对得上，不做代码检索；需要 bash 5.2 以上。
- 第 3、4 步的判断由 agent 或人完成，脚本只提供输入，不保证判断正确。

## 不要做

- 不要因为脚本输出“in sync”就认为不存在重复实现。
- 不要为了通过检查而改地图或删文件。
