#!/usr/bin/env bash
# 执行环境：阿里云服务器，工作目录 /opt/dataplatform。Environment: ECS repository root.
# 调用命令：bash deploy/scripts/dp-down.sh core [core...]；必需参数为分组名，目前仅支持 core。
# 前置条件：Docker Compose 可用，deploy/.env 已配置。
# 期望产出：只停止 core 的八个服务，保留全部数据卷。Expected: stop core and retain volumes.
# 常见失败兜底：参数错误退出 2，Docker 失败非零退出；检查 daemon、权限与容器日志。
set -euo pipefail
if (( $# == 0 )); then echo '用法：dp-down.sh core [core...]' >&2; exit 2; fi
for group in "$@"; do
  if [[ "$group" != core ]]; then echo "不支持的分组：$group" >&2; exit 2; fi
done
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
if [[ ! -f deploy/.env ]]; then echo '缺少 deploy/.env。' >&2; exit 1; fi
# 使用 stop 而非 down，后续增加其他分组时也不会移除共享网络。Stop only named services.
docker compose --env-file deploy/.env -f deploy/docker-compose.yml --profile core stop \
  gateway hiveserver2 hive-metastore nodemanager resourcemanager datanode namenode mysql
