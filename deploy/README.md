# 核心组环境与 Spark 接入（M0-01、M0-02）

本目录实现 MySQL、NameNode、DataNode、ResourceManager、NodeManager、Hive Metastore、HiveServer2 和作业提交网关共八个服务。网关提供 Hadoop、Hive 和 Spark 3.5.7（Scala 2.12）客户端。正式设计见 `docs/01-环境与部署设计.md`。

## 1. 准备服务器

以下操作由项目负责人在阿里云 Ubuntu 22.04、x86、8 核、32 GB 内存、200 GB 云盘的服务器执行。服务器安全组只开放 SSH，容器端口均绑定到服务器的 `127.0.0.1`。

安装命令在服务器任意目录执行，需要 sudo 权限和外网连接，预期安装 Docker Engine 与 Compose 插件。失败时检查软件源、网络及是否存在冲突的旧版 Docker 软件包；命令以非零状态退出时不要继续部署。

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl git
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu jammy stable' | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo docker version
sudo docker compose version
```

后续命令要求当前账号已经具有 Docker 权限。可由管理员配置 docker 用户组后重新登录，或者以具备 Docker 权限的管理员账号操作。Compose 需要支持 `up --wait`，推荐使用当前 Docker 官方软件源提供的版本。

## 2. 克隆仓库与配置变量

在服务器任意目录执行以下命令，需要 GitHub 读取权限及 `/opt` 写入权限，预期检出已合并的 main 分支。克隆失败时检查仓库权限与网络；已经存在仓库时在原仓库检出对应分支，不要覆盖已有目录。

```bash
sudo git clone --branch main https://github.com/leejean79/dataplatform.git /opt/dataplatform
sudo chown -R "$(id -u):$(id -g)" /opt/dataplatform
cd /opt/dataplatform
git rev-parse HEAD
```

合并前验收时，先从待审 PR 取得编号与完整提交 SHA，在准备环境文件之前执行以下命令。命令会检出该 PR 的提交。若 SHA 校验失败，请停止验收并核对审查版本。合并后的长期部署第 7 项逐一核对五个端口均存在且只监听回环地址。第 8 项在最后一次显式深度检查结束、服务稳定后单独采样。在同一验收记录中注明深度检查结束时间、采样时间、两者间隔以及当时的负载，再附上八个容器的完整输出。

```bash
date --iso-8601=seconds
docker stats --no-stream
```

直接使用上面的 main 分支。

```bash
PR_NUMBER=输入待审编号
EXPECTED_SHA=输入待审提交的完整SHA
git fetch origin "refs/pull/${PR_NUMBER}/head" &&
  test "$(git rev-parse FETCH_HEAD)" = "$EXPECTED_SHA" &&
  git switch --detach "$EXPECTED_SHA"
```

在验收记录中附上实际提交 SHA，再准备环境文件。

```bash
git rev-parse HEAD
cp -n deploy/.env.example deploy/.env
chmod 600 deploy/.env
```

编辑 `deploy/.env`，替换全部示例密码。模板中的密码仅用于示例，文件已被 Git 忽略。含 `$`、`#` 或空格的值应按 Compose 的环境文件语法使用单引号，值中的单引号使用 `\'` 转义。不要使用 `source deploy/.env`，因为它不是 Shell 脚本。

镜像选择为 Temurin `8u512-b09-jdk-jammy`、MySQL `8.0.46`、Hadoop `3.3.6`、Hive `3.1.3` 和 MySQL Connector/J `8.0.33`。自建镜像名称、基础镜像和发行包下载地址均可在 `.env` 中替换。MySQL 8.0.46 是官方 8.0 发布说明列出的最终版本，仍遵守本项目的 8.0 基线，不在本任务内调整版本线。

版本依据：[Temurin 官方镜像清单](https://github.com/docker-library/official-images/blob/master/library/eclipse-temurin)、[MySQL 8.0 发布说明](https://dev.mysql.com/doc/relnotes/mysql/8.0/en/)。标签能否从服务器拉取仍需实际验证。

## 3. 构建镜像

以下命令均在服务器 `/opt/dataplatform` 执行，前提是 `.env` 已配置、Docker 可用且可下载镜像和安装包。预期生成三个自建镜像并拉取 MySQL。失败时检查构建日志与下载地址，替换为可访问的镜像源后重新构建；不要把安装包提交到仓库。

```bash
docker compose --env-file deploy/.env -f deploy/docker-compose.yml --profile core config --quiet
docker compose --env-file deploy/.env -f deploy/docker-compose.yml build namenode
docker compose --env-file deploy/.env -f deploy/docker-compose.yml build hive-metastore
docker compose --env-file deploy/.env -f deploy/docker-compose.yml build gateway
docker compose --env-file deploy/.env -f deploy/docker-compose.yml pull mysql
```

必须依次构建：Hive 基于第一步构建的 Hadoop 镜像，网关基于第二步构建的 Hive 镜像。Gateway 构建时检查 Spark SQL 的版本与 Scala 二进制版本。

Hadoop 和 Hive 的默认发行包地址是 Apache 官方归档站，MySQL 驱动来自 Maven 中央仓库。在受限网络下，应在 `.env` 中设置已同步的阿里云镜像地址及可访问的下载地址。此时构建仍需能访问基础镜像的软件源；本任务未实测阿里云网络。

## 4. 启动、健康检查与停止

以下命令均在服务器 `/opt/dataplatform` 执行，前提是上一步的镜像已经构建成功。预期八个服务通过检查，停止再启动后仍能使用原数据。参数错误退出码为 2，服务失败为非零退出码；排查方式见第 6 节。

```bash
bash deploy/scripts/dp-up.sh core
bash deploy/scripts/dp-health.sh core
bash deploy/scripts/dp-down.sh core
bash deploy/scripts/dp-up.sh core
bash deploy/scripts/dp-health.sh core
```

`dp-up.sh` 和 `dp-down.sh` 接收一个或多个分组参数，目前只接受 `core`；`dp-health.sh` 恰好接收一个 `core` 参数。启动最多等待 900 秒，按服务依赖顺序等待健康检查，不会自动构建镜像。停止脚本只停止八个服务，不删除容器、网络或命名卷。

Compose 每 20 秒使用 SQL、HTTP 或 TCP 探测就绪状态，MySQL 须同时满足七个库可见且数据卷中存在初始化完成标记。只有建库、创建账号和全部授权均成功后脚本才写入该标记，DataNode 需在 NameNode 注册。启动脚本在所有服务就绪后调用一次深度检查。也可以手动运行 `dp-health.sh core` 查看 HDFS、YARN、Hive 查询、凭据隔离和 NodeManager 系统与 JVM 时区的实际检查结果。每项容器命令限时 60 秒，失败后脚本继续检查并汇总退出状态。

M0-01 在服务器记录 NodeManager 时区检查输出、CPU、实际内存占用及容器是否发生 OOM。M0-02 再验证 YARN cluster 模式的 driver、executor 和 Spark SQL 会话时区，并用北京时间 00:30 的固定时间点核对分区日期。日期偏移属于待验证风险。

首次启动仅在空的 NameNode 卷中格式化 HDFS；非空且缺少 VERSION 的卷会拒绝启动。Hive 仅在元数据库中没有任何表时初始化模式，已有模式必须通过检查与验证，数据库连接失败不会触发初始化。初始化只创建基础设施元数据，不创建业务表。

## 5. 验收与访问

任务卡 `docs/tasks/M0-01-核心组环境.md` 中的八项验收全部在阿里云服务器 `/opt/dataplatform` 执行。本段命令需要八个服务已启动，预期能列出 HDFS、看到一个 RUNNING 节点、看到 `default` 数据库并输出容器资源信息；失败时返回非零状态或缺少预期结果，应按第 6 节排查。

```bash
docker compose -f deploy/docker-compose.yml exec gateway hdfs dfs -ls /
docker compose -f deploy/docker-compose.yml exec gateway yarn node -list
docker compose -f deploy/docker-compose.yml exec gateway beeline -u jdbc:hive2://hiveserver2:10000 -e 'show databases'
ss -ltnp | grep -E ':(3306|9870|8088|10000|10002)[[:space:]]'
```

直接使用 `-f deploy/docker-compose.yml` 时，Compose 会从编排文件目录读取 `deploy/.env`；脚本显式使用 `--env-file`。验收还必须包含停止再启动检查。端口监听地址只能为 `127.0.0.1`，不能出现 `0.0.0.0`。全部核心服务的内存上限合计为 12.5 GiB，实际占用须以服务器的 `docker stats` 为准。

在本地电脑任意目录执行以下命令，替换账号与地址，需要 SSH 权限、本地端口空闲且服务器服务健康，预期保持隧道连接；失败时检查 SSH 权限或更换冒号左侧的本地端口。

```bash
ssh -N -L 9870:127.0.0.1:9870 -L 8088:127.0.0.1:8088 -L 10002:127.0.0.1:10002 <用户名>@<服务器地址>
```

随后在浏览器访问 `http://127.0.0.1:9870`、`http://127.0.0.1:8088` 和 `http://127.0.0.1:10002`。

## 6. 排查与数据保留

在服务器 `/opt/dataplatform` 执行下列命令，需要 Docker 权限及现有容器，预期输出服务状态、最近日志与探测记录。失败时检查 Docker daemon、仓库目录和环境变量文件。

```bash
docker compose -f deploy/docker-compose.yml --profile core ps -a
docker compose -f deploy/docker-compose.yml logs --tail=100 hive-metastore hiveserver2
docker compose -f deploy/docker-compose.yml logs --tail=100 mysql namenode nodemanager
docker inspect --format '{{json .State.Health}}' "$(docker compose -f deploy/docker-compose.yml ps -q hive-metastore)"
```

- 镜像拉取失败时检查 `.env` 中的完整标签和镜像仓库地址；下载失败时检查对应 URL。
- Hive 依赖冲突目前只按设计替换 Guava。出现其他冲突时保留完整日志并反馈架构师，不自行调整版本基线。
- MySQL 首次初始化失败时，官方入口可能已留下部分数据。修改密码或初始化脚本后不会自动修复已有卷，应先备份并由负责人判断恢复方式。
- 修改 `.env` 的密码不会修改已有数据库账号密码，必须先在数据库中同步变更，再重建相关容器。
- HDFS 使用 `dp_namenode` 与 `dp_datanode`，MySQL 使用 `dp_mysql`，YARN 使用 `dp_yarn_local` 与 `dp_yarn_logs`。必须成套保留 HDFS 的两个卷，不能只重建其中一个。

本任务不提供删除数据卷的脚本。阿里云验收、Hive 兼容性、重启幂等性和实际内存占用在执行前均不能视为已通过。

旧版本初始化的 MySQL 卷没有完成标记，升级后会显示不健康。合并前验收请使用新环境。保留旧数据时，应先核验七个库、六个账号及初始化脚本列出的每项授权，再由负责人补记完成状态。

## 7. 在阿里云验证 Spark 离线链路

在服务器 `/opt/dataplatform` 执行。前提是 M0-01 核心组健康，当前检出待验收的 M0-02 提交。已有部署请把模板中的 `SPARK_VERSION`、`SPARK_DOWNLOAD_URL` 加入现有 `deploy/.env`，并更新 `GATEWAY_IMAGE` 标签，保留已有密码和镜像源。首次构建需要能够下载对应的 Hadoop 3 版 Spark 发行包。

```bash
git rev-parse HEAD
docker compose --env-file deploy/.env -f deploy/docker-compose.yml build gateway
docker compose --env-file deploy/.env -f deploy/docker-compose.yml up -d --no-deps --wait gateway
docker compose -f deploy/docker-compose.yml exec gateway spark-submit --version
docker compose -f deploy/docker-compose.yml exec gateway yarn application -list -appStates ALL
bash deploy/scripts/smoke-offline.sh && bash deploy/scripts/smoke-offline.sh
docker compose -f deploy/docker-compose.yml exec gateway yarn application -list -appStates FINISHED
docker compose -f deploy/docker-compose.yml exec gateway /opt/hive/bin/beeline --silent=true --showHeader=false --outputformat=tsv2 -n dp -u jdbc:hive2://hiveserver2:10000 -e "SELECT id FROM dp_smoke.t_offline"
docker compose -f deploy/docker-compose.yml exec gateway yarn application -list -appStates ALL
```

脚本只重建专用测试表 `dp_smoke.t_offline`，请串行执行。SQL 文件打包在 Gateway 的 Scala 提交入口中，由远程 driver 执行。Gateway 随作业分发镜像内的 Hive 客户端依赖，YARN 将其解压至应用工作目录，driver 通过 Metastore 服务名访问元数据。

每次验收应记录独立的 Application ID、最终状态、耗时、driver 与参与探测的 executor JVM 的实际时区、Spark SQL 会话时区、HiveServer2 查询行数与唯一分区。两次都应返回 0、状态 SUCCEEDED、行数 3，分区为 `dt=2026-11-25`（输入为北京时间当日 00:30，即 UTC 前一日 16:30）。

脚本在客户端统计 HiveServer2 返回的数据行。请对比两份完整应用清单，确认只新增了本轮两个 Spark 应用，并记录其编号。

驱动程序申请 512 MB，两个执行器各申请 1 GB 内存和 1 核。计入开销并取整后，三个容器分别占用 1024、1536、1536 MB，合计 4096 MB。脚本输出实际参与时区探测的执行器数量和编号。如果只观测到一个，请保留脚本退出码，并附上该应用的容器清单供审查。若提交失败，脚本保留 spark-submit 完整输出，并在取得应用 ID 后导出 YARN 日志。如果仍无法访问 Hive 3.1.3 Metastore，请在合并请求中附完整错误与应用日志，由架构师评审版本或配置变更。

## 远程运维通道

项目负责人在本机 macOS 安装阿里云命令行工具 `aliyun`，确保 Python 3 和 OpenSSH 可用，并为查询账号授予 ECS 的 DescribeInstances 只读权限。

负责人手动准备仅自己可读写（权限为 600）的 `~/.dataplatform-aliyun.conf`。该文件使用 Shell 变量赋值语法，示例如下。

```bash
ALIYUN_ACCESS_KEY_ID='<访问密钥标识>'
ALIYUN_ACCESS_KEY_SECRET='<访问密钥秘密>'
ALIYUN_REGION='<地域>'
ECS_INSTANCE_ID='<实例编号>'
```

负责人还需在 `~/.ssh/config` 中准备独立的主机段，并预先确认服务器的 SSH 主机指纹。

```sshconfig
Host dp-ecs
    HostName <公网地址>
    User <登录用户>
    IdentityFile <本机私钥路径>
    IdentitiesOnly yes
```

在本地仓库根目录执行 `bash deploy/scripts/refresh-ecs-ip.sh --dry-run`，确认实例运行状态和当前公网地址后，再执行 `bash deploy/scripts/refresh-ecs-ip.sh`。后者同步已有主机段的 HostName 并执行 `ssh dp-ecs hostname`。查询、配置校验或连接失败时脚本返回非零；请保留 SSH 错误并停止后续远程操作。提交验收输出前将公网地址替换为 `<公网地址>`。

查询失败时，脚本会在提示后保留最多三行经过筛选的 CLI 错误。若提示地域为空，请核对地域参数并确认调用未指定 `--mode AK`；若错误码表明访问被拒绝，请核对账号的 `ecs:DescribeInstances` 权限。提交排查记录时仅附脱敏后的错误行。
