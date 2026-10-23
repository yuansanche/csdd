# /speckit.csdd.prepare

`/speckit.specify` 之前自动运行（`before_specify` 钩子）：确保 BrownKit 证据树存在且不过期，让随后的 `enrich` 有内容可读。**一路做完；任何一步失败都不要挡住 specify，如实记录后返回。**

## 步骤

1. 判断现状：

   ```
   bash .specify/extensions/csdd/scripts/csdd-evidence.sh --plan --target .
   ```

   输出 `STATE=` 是 `none`（没有）、`partial`（做了一半）、`stale`（有证据但代码已变）、`ready`（就绪）；`CHANGED=` 是自证据基线以来变动的目录。

2. 按状态处理：
   - `ready`：什么都不做，回复一句“证据就绪，跳过”，结束。
   - 没装 brownkit（找不到 `.specify/extensions/brownkit`）：回复一句“未装 brownkit，跳过”，结束。
   - `none` 或 `partial`：范围用本次要做的事涉及的目录（specify 的描述里提到的模块；没提就取代码文件最多的前 3 个顶层模块），调用 `/speckit-csdd-discover`，并把 `--focus <目录>` 传给它。已做完的步骤它会跳过。
   - `stale`：只对 `CHANGED=` 里的目录补做：`/speckit-brownkit-scan --focus <目录>`，再 `/speckit-brownkit-discover`。BrownKit 对已有证据的合并行为本包没有验证，如果 discover 报冲突或要求 reset，不要 reset，记录后返回。

3. 做完且证据就绪，记下基线：

   ```
   bash .specify/extensions/csdd/scripts/csdd-evidence.sh --stamp --target .
   ```

4. 回复一段话：状态是什么、做了什么、范围多大、没做完的是什么。

## 约束

- 范围要小：一次最多 3 个目录。实测一个只有十几个文件的样例项目，完整 init、scan、discover 也要近 30 分钟，所以不要全仓库铺开。
- 不要伪造证据文件，不要为了让状态变成 `ready` 去手写。
- 不要问用户问题；需要用户确认的 BrownKit 默认值，按 `brownkit-config.yml` 取值并在回复里列出。
- 不要修改源码。
