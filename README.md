# dataplatform

本仓库是一个制造业数据中台原型，业务对象是传统整车制造企业。总体设计见 [docs/00-总体架构设计.md](docs/00-总体架构设计.md)，面向 Codex 的开发指令见 [AGENTS.md](AGENTS.md)。

## 目录结构

| 目录 | 内容 |
| --- | --- |
| `dp-common/` | 公共配置、常量与工具类。 |
| `dp-mock/` | 模拟数据生成程序。 |
| `dp-warehouse-offline/` | 离线数仓，包含 Spark 批量抽取和各层加工脚本。 |
| `dp-warehouse-realtime/` | 实时数仓，包含 Flink CDC 采集和 Flink 作业。 |
| `dp-quality/` | 数据质量规则的执行与结果上报。 |
| `dp-portal-server/` | Web 平台后端。 |
| `dp-portal-web/` | Web 平台前端，是独立的 npm 工程，不属于 Maven 模块。 |
| `deploy/` | Docker 编排文件、初始化脚本和各组件配置。 |
| `docs/` | 设计文档与任务卡。 |

## 构建

- **执行环境**：本地开发机，工作目录为仓库根目录。
- **调用命令**：`mvn verify`
- **前置条件**：已经安装 JDK 8 和 Maven 3.9，并且能够访问 Maven 中央仓库或其镜像。在中国大陆建议在 `~/.m2/settings.xml` 中配置阿里云镜像仓库。
- **期望产出**：六个模块全部显示 `BUILD SUCCESS`，`dp-portal-server/target/` 下生成 `dp-portal-server-1.0.0-SNAPSHOT.jar`。
- **常见失败兜底**：出现依赖无法下载的错误时，应当先检查镜像仓库配置；出现 `invalid target release` 之类的编译错误时，应当执行 `mvn -version` 确认 Maven 实际使用的 JDK 版本。
