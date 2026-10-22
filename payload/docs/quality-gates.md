# 自动质量门禁

## 真实执行范围

治理检查器 `scripts/quality_gate.py` 使用 Python 3.10+ 标准库，不依赖 Java / Node。配置是 `quality-policy.json`，不是 Spec Kit 原生配置；只有调用本项目脚本时才执行。

扫描在任意目录层级排除 `node_modules`、`.venv`、`venv`、`target`、`build`、`dist`、`coverage`、缓存、报告和 Git 目录，避免把第三方 / 构建产物当项目文档。若真实业务源码使用这些目录名，接入时需显式调整扫描范围并补测试。检查器自身测试使用独立合成 fixture，不运行用户配置的真实业务命令。

| 能力 | 当前状态 |
|---|---|
| 必需治理文件存在、规则版本 / 初始化声明 | 自动已接入 |
| 本地 Markdown 文件链接存在 | 自动已接入，忽略网页与页内锚点，不校验标题锚点 |
| 模板 override 标识存在 | 自动已接入；另外用官方解析器验证实际生效 |
| 需求—任务—测试引用的结构 | delivery 自动已接入；不判断断言业务含义 |
| 配置业务命令按参数列表执行、超时和失败阻断 | 自动已接入；默认业务命令为空所以 delivery 阻断 |
| Java 格式、静态分析、架构、构建、业务测试 | 待接入真实项目 |
| 规则变更审查、例外批准、商业验收 | 人工执行；不能用脚本自批 |
| 宪章 C-11 复用评估、C-12 权威实现定位、C-13 角色权限隔离 | 人工执行，尚无自动检查：检查器不读取复用评估或定位记录，也不验证角色权限；不得宣称自动覆盖（宪章 C-03）。记录载体见 [workflow.md](workflow.md) |
| 远端分支保护 / CODEOWNERS | 待仓库管理员配置，不因文件存在而生效 |

## 两种模式

```bash
python3 scripts/quality_gate.py --mode bootstrap
python3 scripts/quality_gate.py --mode delivery --feature specs/001-feature
```

delivery 读取功能目录的 `spec.md`、`tasks.md` 和 `acceptance.json`。每个需求项必须包含唯一 id、非空验收条件、至少一个任务和测试引用；任务必须实际存在，测试文件必须存在，路径不能逃出项目。检查器不验证测试选择器是否真的对应案例，须由业务工具 / 报告核对。

当前版本必须配置 `build`、`test`、`format`、`architecture`、`security` 五类真实命令。不同语言项目自行选择工具；检查器不支持仅靠 JSON 去掉类别。确需调整不适用类别时，必须评审并同时修改检查器、规则基线和回归测试，不允许悄悄置空。

## 配置业务检查

`checks` 每项结构：

```json
{
  "id": "java-verify",
  "category": "test",
  "argv": ["./mvnw", "-B", "verify"],
  "timeout_seconds": 600
}
```

这只是接入示例；本包没有 Maven 应用和 mvnw，不能直接当成已经启用。命令以项目根目录运行，不通过 shell 字符串拼接。多个类别可有多个命令，但不要以 `echo` 或空操作充当验证。工具可覆盖多个目的时以明确的命令 / wrapper 和报告分别记录。

Java 推荐分工：格式器单一采用 google-java-format 默认模式；静态分析筛选适用规则；ArchUnit 验证实际模块；Maven / Gradle 构建并运行测试；依赖和敏感信息按团队安全工具检查。固定版本，通过试点后启用。P3C 必须核对 PMD / JDK 兼容，不全量盲开。

## CI 和远端设置

`quality` 工作流每次执行 bootstrap 和检查器自身测试。检测到业务源文件后运行 delivery，需要 `active_feature` 指向本次真实功能、`checks` 配置真实命令。示例文件不算产品。

启用远端 required status check：`quality`。设置 PR 评审，限制 bypass，新增提交后核对最新结果。CI、quality-policy、Agent 指令、宪章和验收预期修改须配置负责人评审。CODEOWNERS 需要真实账户；本包不伪造人员。

CI 工作流可以被修改，所以“配置了 CI”不代表无法绕过；规则文件和 workflow 也要受保护。远端 CI 尚未执行，本包只提供可执行工作流文件。

## 证据与例外

脚本写入 `reports/quality-report.json`，包括时间、模式、检查范围、当前 git 版本（若存在）、结果和命令结果。`reports/` 不进入源码提交。CI 将报告作为 artifact 保存。

例外记录目前由人审管理，检查器不自动绕过必跑项。将来增加豁免机制时需要范围、期限、批准者验证及负例测试。
