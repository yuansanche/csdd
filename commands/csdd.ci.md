# /speckit.csdd.ci

为项目搭建或补全 CI。只在用户明确要求时运行。

## 步骤

1. 看项目现有 CI：`.github/workflows/`、`.gitlab-ci.yml`、`Jenkinsfile`。已有就在它基础上改，不要另起一套。
2. CSDD 已装的 `.github/workflows/quality.yml` 会跑 `python3 scripts/quality_gate.py --mode ci`。先确认它存在；没有就说明并停下，让用户先运行 `/speckit.csdd.install`。
3. 项目的构建、测试、格式、架构、安全命令，写进 `quality-policy.json` 的 `checks`。命令从项目现有脚本或 `detect-stack.sh` 的输出里找，找不到的写“未知”，不要编。
4. 装了 `blueprint-index` 且 CI 机器的 bash 不低于 5.2 时，可以加一步 `bash .specify/extensions/blueprint-index/scripts/bash/blueprint-state.sh check`。GitHub 托管的 ubuntu 镜像自带的 bash 版本没有在本包里验证，先查再加。
5. 把改动作为文件差异给用户看，由用户决定是否提交。

## 不要做

- 不要为了让 CI 通过而删掉 `checks` 或放宽 `required_categories`。
- 不要提交任何密钥；CI 里用到的凭据只写成仓库 secrets 的名字。
