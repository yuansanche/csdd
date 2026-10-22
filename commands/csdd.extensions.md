# /speckit.csdd.extensions

按清单管理第三方扩展。**默认不安装任何组件。**

## 先看清单

```
bash .specify/extensions/csdd/scripts/csdd-extensions.sh --list
```

清单来源：`.specify/extensions/csdd/extensions.manifest.json`。每个组件记录版本、来源、SHA256、安装方式、已知风险与建议。

## 安装某个组件

```
bash .specify/extensions/csdd/scripts/csdd-extensions.sh --install <id>
```

脚本会拒绝以下情况，**不要绕过**：

- `source` 不是 https 地址，或 `sha256` 不是 64 位十六进制 → 无法固定版本，拒绝安装。
- 整包哈希不符，或 `extension.yml` 与审计记录不符 → 拒绝安装。
- 装完 `specify extension list` 里没有对应 id → 退出码 4，视为失败。

每次运行后，把退出码和脚本输出原样告诉用户。

## 必须向用户说明的背景

评估中的实测结论（只覆盖 BrownKit 一个组件，其余组件未测自发调用）：

- BrownKit 在改动类与只读发现类两类任务里**自发调用均为 0/3**；不装它的基线组同样答对。
- BrownKit 的 5 个 hook 全部 `optional: true` 且带 `prompt:`，由 agent 读配置后自行决定，**不构成不依赖 agent 自觉的强制力**。
- `blueprint-index` 的 `check` 是确定性漂移门禁，不读代码；需要 bash 5.2 或更高版本。

所以安装扩展的正当理由只有一个：**CSDD 在固定步骤显式调用它**。若没有这个调用点，装了也不会被用到。

## 不要做

- 不要为了"看起来完整"而批量安装。
- 不要在未核对 SHA256 的情况下安装。
- 不要把组件安装当成治理能力已具备的证明。
