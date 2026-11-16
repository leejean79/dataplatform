# M0-02 Spark 接入与离线冒烟测试

## 目标

作业提交网关能够以 cluster 模式向 YARN 提交 Spark 作业，Spark SQL 能够读写 Hive 3.1.3 管理的表，并且有一个可以重复执行的脚本证明这一点。

## 前置任务

M0-01。

## 依据的设计文档

- `docs/01-环境与部署设计.md` 第 5 节中关于 Spark 作业默认资源的约定、第 7.4 节和第 9.1 节。

## 实现范围

1. 修改 `deploy/images/gateway/`，在镜像中加入 Spark 3.5.x 的发行包，版本号与父工程 `pom.xml` 中的 `spark.version` 保持一致。
2. 新增 `deploy/conf/spark/spark-defaults.conf`，按照设计文档第 7.4 节配置 Hive Metastore 的版本与依赖包路径，并且设置第 5 节约定的默认资源。
3. 新增 `deploy/scripts/smoke-offline.sh`，实现设计文档第 9.1 节的四个步骤。脚本必须可以重复执行。
4. 更新 `deploy/README.md`，增加离线冒烟测试的使用说明。

## 明确不做的范围

- 不编写任何 Java 代码，冒烟测试使用 Spark 自带的 `spark-sql` 或者 `spark-submit` 配合 SQL 文件完成。
- 不修改 Maven 工程中的任何模块。
- 不部署 Spark 历史服务器。

## 验收命令

以下命令的执行环境均为阿里云服务器，工作目录为 `/opt/dataplatform`，前置条件是 `core` 分组已经启动。

| 序号 | 命令 | 期望输出 |
| --- | --- | --- |
| 1 | `docker compose -f deploy/docker-compose.yml exec gateway spark-submit --version` | 输出的 Spark 版本为 3.5.x，Scala 版本为 2.12。 |
| 2 | `bash deploy/scripts/smoke-offline.sh` | 脚本输出每个步骤的结果，最后一行明确说明测试通过，退出码为 0。 |
| 3 | 再次执行 `bash deploy/scripts/smoke-offline.sh` | 第二次执行仍然通过，证明脚本可以重复执行。 |
| 4 | `docker compose -f deploy/docker-compose.yml exec gateway yarn application -list -appStates FINISHED` | 输出中包含冒烟测试提交的应用，最终状态为 SUCCEEDED。 |
| 5 | `docker compose -f deploy/docker-compose.yml exec gateway beeline -u jdbc:hive2://hiveserver2:10000 -e "select count(*) from dp_smoke.t_offline"` | 查询结果为 3。 |

## 交付物

- 修改后的 `deploy/images/gateway/` 与 `deploy/.env.example`。
- `deploy/conf/spark/spark-defaults.conf`、`deploy/scripts/smoke-offline.sh`、更新后的 `deploy/README.md`。

## 已知风险与需要反馈的问题

1. 如果按照设计文档第 7.4 节配置之后 Spark 仍然无法访问 Hive 3.1.3 的 Metastore，请停止工作并且在合并请求中附上完整的错误信息，由架构师决定是否调整版本基线。
2. 请反馈一次冒烟测试从提交到结束所用的时间。
3. 请说明 Spark 写入的表在 HiveServer2 中查询时是否出现过格式或权限方面的问题。
