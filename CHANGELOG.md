# Changelog

## [1.2.1] - 2026-10-22

### Added
- `csdd-bootstrap.sh` 支持 `codebuddy`、`dsh`（DeepSeek Harness）集成；容器内已验证文件落点与安装流程，运行时行为（agent 是否真的加载并执行）未验证。

### Changed
- 门禁自检失败的已知原因识别从 `.claude/` 扩展到 `.codebuddy/`、`.dsh/`，退出码 5。

## [1.2.0] - 2026-10-22

### Added
- 治理层安装：门禁、模板、宪章、文档，默认预演，冲突不覆盖，装完自检。
- `AGENTS.md`、`CONTRIBUTING.md` 不整份复制，只写带 `CSDD:BEGIN` 标记的中性区块。
- 第三方扩展清单（7 个 spec-kit 扩展）：整包 sha256、`extension.yml` 审计哈希、装完用 `extension list` 确认登记。
- `v-model` 按 `include` 清单过滤解压并核对目录树哈希（上游包超过 spec-kit 1.1.3 的 512 条目上限）。
- `/speckit.csdd.navigate`：新增模块前的只读导航。
- `scripts/csdd-bootstrap.sh`：一键部署（init → 装扩展 → 装治理层 → 可选装第三方扩展），不带 `--yes` 只预演。
- `cache/`：7 个第三方扩展压缩包的仓库缓存，哈希与清单一致才使用，缺失或不符才联网。
- `sync-payload.sh`、`verify-package.sh` 增加 `--repo`，单独克隆本包时也能维护 payload。

### Known issues
- `blueprint-index` 的 check 脚本需要 bash 5.2 以上。
- Claude 集成下，第三方扩展的技能文档可能被链接扫描误判为坏链接。
- 清单里的整包哈希来自 GitHub 自动生成的标签压缩包，长期字节稳定性未验证。
