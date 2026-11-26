# M0-02-R1 Spark 默认资源与行数检查修订

## 目标

使 M0-02 已经合并的实现与修订后的设计一致：一个驱动程序加两个执行器能够同时分配到资源，并且离线冒烟测试的行数检查不再依赖 MapReduce。本任务卡完成之后，M0-02 的五条服务器验收命令应当全部通过。

## 前置任务

M0-02。

## 依据的设计文档

- `docs/01-环境与部署设计.md` 第 5 节末尾关于 Spark 默认资源的两段、第 7.3 节最后一条和第 9.1 节。
- `docs/tasks/M0-02-Spark接入与离线冒烟测试.md` 修订后的验收命令。

## 实现范围

1. 修改 `deploy/conf/spark/spark-defaults.conf`，把 `spark.driver.memory` 由 `1g` 改为 `512m`。其余配置项保持不变。
2. 修改 `deploy/scripts/smoke-offline.sh`，把通过 HiveServer2 执行的 `SELECT COUNT(*) FROM dp_smoke.t_offline` 改为 `SELECT id FROM dp_smoke.t_offline`，由脚本统计返回的行数并且要求等于 3。分区检查保持不变。
3. 在 `smoke-offline.sh` 中增加一项输出：本轮参与时区探测的执行器数量及其编号。数量从作业已经写入 HDFS 的时区证据中统计，不需要修改 `OfflineSmoke.scala`。该数量只输出，不作为脚本的通过条件，脚本中不得写死期望值。
4. 更新 `deploy/README.md` 中与上述两处有关的说明和命令。

## 明确不做的范围

- 不修改 `OfflineSmoke.scala`、`smoke.sql` 和网关镜像的构建文件，除非第 3 项确实无法在不修改它们的前提下实现，这种情况应当在合并请求中说明。
- 不修改 YARN 的内存配置和任何容器的内存上限。
- 不处理此前记录的非阻塞建议，包括安装包校验、镜像标签命名和依赖包预先上传到 HDFS。
- 不修改 `docs/` 目录下的任何文件。

## 验收命令

第 1 条命令的执行环境是开发者自己的运行环境。其余命令的执行环境是阿里云服务器，工作目录为 `/opt/dataplatform`，前置条件是 `core` 分组已经启动，并且网关容器已经按照最新的 `main` 分支重建。

| 序号 | 命令 | 期望输出 |
| --- | --- | --- |
| 1 | `bash -n deploy/scripts/smoke-offline.sh && git diff --check` | 没有输出，退出码为 0。 |
| 2 | `docker compose -f deploy/docker-compose.yml exec gateway spark-submit --version` | Spark 版本为 3.5.7，Scala 版本为 2.12。 |
| 3 | `bash deploy/scripts/smoke-offline.sh` | 最后一行说明测试通过，退出码为 0。输出中参与探测的执行器数量预期为 2，实际数量按照下文的规则处理。 |
| 4 | 再次执行 `bash deploy/scripts/smoke-offline.sh` | 第二次执行仍然通过。 |
| 5 | `docker compose -f deploy/docker-compose.yml exec gateway yarn application -list -appStates FINISHED` | 本轮两次冒烟测试提交的应用的最终状态均为 SUCCEEDED。历史应用保持原样，不需要清理。 |
| 6 | `docker compose -f deploy/docker-compose.yml exec gateway beeline --silent=true --showHeader=false --outputformat=tsv2 -n dp -u jdbc:hive2://hiveserver2:10000 -e "SELECT id FROM dp_smoke.t_offline"` | 输出 3 行。 |
验收证据的三条补充规则如下：

1. **应用清单的前后对照。** 在执行第 3 条命令之前，以及在执行第 6 条命令之后，各执行一次 `docker compose -f deploy/docker-compose.yml exec gateway yarn application -list -appStates ALL` 并且记录输出。合并请求中按照应用编号列出本轮新增的应用，新增的应用应当只有两个 Spark 应用，不得出现 MapReduce 类型的应用。只有这一对照能够证明第 6 条查询没有启动 MapReduce 作业。
2. **执行器数量的解释。** 现有的探测只记录实际执行过探测任务的执行器。观测到 2 个，证明两个执行器都已分配并且参与了计算。只观测到 1 个，不能据此断定 YARN 只分配了 1 个执行器。
3. **观测到 1 个执行器时的处理。** 保留脚本按照其他断言得到的退出码，在合并请求中写明“预期 2，实测 1”，并且附上该应用的容器清单作为证据，例如 `yarn logs -applicationId <应用编号> -show_application_log_info` 的输出。不得为了凑出 2 而修改资源配置，也不得把这种情况写成通过。是否通过由架构师根据证据判断。

## 交付物

- 修改后的 `deploy/conf/spark/spark-defaults.conf`、`deploy/scripts/smoke-offline.sh` 和 `deploy/README.md`。

## 已知风险与需要反馈的问题

1. 如果驱动程序在 512 MB 内存下出现内存不足，请停止工作并且附上 YARN 应用日志，由架构师决定是否改用备选方案。
2. 如果写入分区表时出现“Dynamic partition strict mode”一类的错误，请附上完整的错误信息，并且说明拟采用的配置项，由架构师确认之后再修改。
3. 如果 Spark 无法访问 Hive 3.1.3 的 Metastore，请附上完整的 `spark-submit` 输出与 YARN 应用日志，不要自行调整版本基线。
4. 请反馈每次冒烟测试从提交到结束所用的时间。
