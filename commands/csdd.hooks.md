# /speckit.csdd.hooks

查看或切换扩展钩子的模式：自动（`optional: false`，spec-kit 的技能会执行并等它结束）或询问（`optional: true`，只提示）。只在用户明确要求时运行。

用户的要求：

$ARGUMENTS

## 步骤

1. 先列现状：

   ```
   bash .specify/extensions/csdd/scripts/csdd-hooks.sh --list --target .
   ```

2. 按用户要求切换，例如“specify 之后自动生成 V-Model 需求件”：

   ```
   bash .specify/extensions/csdd/scripts/csdd-hooks.sh --set after_specify speckit.v-model.requirements auto --target .
   ```

   改回只提示用 `ask`。退出码 2 表示这个钩子没注册（扩展没装），照实转述。

3. 回复里写清：改了哪一条、之后每次运行 specify 会多做什么、有什么代价（见下）。

## 切换前要知道的

- `speckit.brownkit.enrich`：只读已有证据树，没有证据时无内容可注入，自动执行等于空转；匹配到能力后它自己会等用户确认，这是 BrownKit 内置的。先用 `/speckit.csdd.discover` 建证据树。
- `speckit.v-model.requirements`：每次 specify 之后都会生成需求件，多花一轮 token；它在本项目评估里命令行为未验证。
- 自动钩子执行失败时，spec-kit 的技能会等它结束再继续，可能让 specify 卡在这一步。

## 不要做

- 不要一次把所有钩子都改成自动。
- 不要在用户没要求时改钩子模式。
