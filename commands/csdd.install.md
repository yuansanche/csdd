# /speckit.csdd.install

把 CSDD 治理层安装到当前仓库。

## 步骤

1. 确认当前目录是仓库根（存在 `.specify/integration.json`）。若不存在，先运行：

   claude 集成（默认就是技能格式，不接受 `--skills`）：

   ```
   uvx --from specify-cli==1.1.3 specify init --here --integration claude --script sh --ignore-agent-tools --non-interactive
   ```

   codex 集成（需要 `--skills`）：

   ```
   uvx --from specify-cli==1.1.3 specify init --here --integration codex --integration-options="--skills" --script sh --ignore-agent-tools --non-interactive
   ```

   其它 agent 的参数本包未验证，先看 `specify init --help`。目录非空时，非交互模式的 `specify init` 必须加 `--force` 才会合并，否则退出 1；加了之后先确认已有的 `AGENTS.md`、`README.md` 内容没被改。更省事的做法是让用户运行 `scripts/csdd-bootstrap.sh`。

2. 先预演，把输出给用户看：

   ```
   bash .specify/extensions/csdd/scripts/csdd-install.sh --target . --agent <agent>
   ```

3. 用户确认后执行：

   ```
   bash .specify/extensions/csdd/scripts/csdd-install.sh --target . --agent <agent> --apply
   ```

4. 若报冲突（退出码 3）：把冲突文件清单交给用户逐个决定，**不要自行加 `--force`**。

5. 脚本会自己跑 bootstrap 与单测；失败就停，不要手工跳过或降低规则。

## 报告要求

- 每次运行脚本后，把**退出码和脚本输出原样**告诉用户，不要概括成“遇到一点问题”。退出码含义：0 成功 / 2 目标未初始化 / 3 有冲突 / 4 自检失败。
- 本命令有写文件的副作用，只在用户明确要求安装治理层时运行，不要在其它任务里顺手调用。

## 不要做

- 不要修改 `quality-policy.json` 的 `checks` 来让门禁通过。
- 不要为了让 bootstrap 通过而删文件或改链接。
- 不要安装任何第三方扩展（那是 `/speckit.csdd.extensions` 的事）。

## 完成后仍需人工完成

- 填 `quality-policy.json` 的 `checks`：build / test / format / architecture / security。
- 建 `specs/<feature>/acceptance.json` 并更新 `.specify/feature.json`。
- 做一次故意失败试验，确认 delivery 真的阻断。
