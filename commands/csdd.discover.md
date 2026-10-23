# /speckit.csdd.discover

为存量项目建立 BrownKit 证据树（init → scan → discover），让 `enrich` 等钩子有内容可读。**一路做完，不要在步骤之间停下来问用户。**

用户补充的范围或要求：

$ARGUMENTS

## 前提

BrownKit 的 `enrich`、`gate`、`validate` 只读证据树，不做分析。没有证据树时它们只会输出“无匹配能力”，等于没执行。证据树要靠下面三步建出来，代价从轻到重：init 轻，scan 要逐个模块读代码，discover 更重。

## 步骤

1. 看现状（只读）：

   ```
   bash .specify/extensions/csdd/scripts/csdd-evidence.sh --status --target .
   ```

   退出码 0 表示证据已就绪，直接跳到第 6 步。10 表示没就绪，继续。

2. 先把证据目录排除出 blueprint 的未覆盖检查（幂等，保留已有排除项）：

   ```
   bash .specify/extensions/csdd/scripts/csdd-evidence.sh --exclude-evidence --target .
   ```

3. 可续跑：`--status` 里 context.json 有、candidates.md 无，说明 init 做完、scan 没做；candidates.md 有而 domain-model.md 无，说明只差 discover。已做完的步骤跳过。init 发现已有 context.json 时选“continue with existing context”，**不要 reset**。

4. 依次调用 `/speckit-brownkit-init`、`/speckit-brownkit-scan`、`/speckit-brownkit-discover`（Skill 工具）。每一步的提示词里凡是“问用户”的地方，按下面处理，**不要停下来问**：
   - 优先用 `brownkit-config.yml` 里的值，其次用上面“用户补充”里的内容，再其次用 BrownKit 自己写的默认值。
   - init 里的合规范围、风险容忍度、覆盖率目标这类需要用户确认的项，直接取配置值，并在最终回复里**逐项列出你采用了什么值、来自哪里**，让用户事后纠正。
   - scan 加 `--focus` 只在用户补充里指定了目录时使用；否则全量。
   - 不要编造：某项拿不到就按 BrownKit 的规定写 `not-collected`。

5. 每一步结束后再跑一次 `--status` 核对产出，缺了就如实说缺哪个文件，不要声称完成。

6. 证据就绪后，把 enrich 钩子改为自动执行：

   ```
   bash .specify/extensions/csdd/scripts/csdd-evidence.sh --auto-enrich --target .
   ```

7. 回复里写清：做了哪几步、产出在哪、采用了哪些默认值、哪几步没做或没做完、证据树覆盖了多少文件。

## 要知道的限制

- scan 和 discover 是 agent 逐模块读代码完成的，耗时和 token 与仓库规模成正比。实测：只有十几个文件的样例项目，init 加 scan 做完后 discover 刚开始，单次会话就跑了近 1700 秒。大仓库请先用 `$ARGUMENTS` 里的 `--focus <目录>` 缩小范围，分几次跑。
- `enrich` 自己在匹配到能力后会等用户确认，这是 BrownKit 内置的，本命令改不了。
- 证据树是当时代码的快照，代码大改后需要重跑。

## 不要做

- 不要为了让 `--status` 通过而手写或伪造证据文件。
- 不要在步骤之间把“请你运行 xxx”交还给用户。
- 不要提交 `evidence/` 里含密钥的内容；scan 的 `find-secrets` 结果只记位置，不记值。
