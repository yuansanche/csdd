# /speckit.csdd.verify

校验已安装的治理层是否与包内 payload 一致，并跑门禁自检。

## 步骤

1. 跑漂移检查（对比 payload 与当前仓库的同名文件）：

   ```
   bash .specify/extensions/csdd/scripts/verify-package.sh --target .
   ```

   输出会列出：一致 / 不一致 / 仓库缺失 三类。不一致的项必须交给用户判断是本地定制还是过期，**不要自动覆盖**。

2. 跑门禁：

   ```
   python3 scripts/quality_gate.py --mode bootstrap
   python3 -m unittest discover -s tests -v
   ```

3. 若目标仓库有业务代码，再跑 delivery：

   ```
   python3 scripts/quality_gate.py --mode delivery --feature specs/<feature>
   ```

   delivery 报 `checks are not configured` 属正常：说明业务检查还没接入，不是缺陷。

## 判读

- bootstrap 通过只代表治理结构与链接正确，**不代表业务正确**。
- 不要因为 delivery 失败就去改 policy；先确认是 checks 未配还是真的没通过。
