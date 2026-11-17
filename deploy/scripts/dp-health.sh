#!/usr/bin/env bash
# 执行环境：阿里云服务器，工作目录 /opt/dataplatform。Environment: ECS repository root.
# 调用命令：bash deploy/scripts/dp-health.sh core；恰好一个必需分组参数，目前仅支持 core。
# 前置条件：Docker Compose 可用，deploy/.env 已配置，core 已启动。
# 期望产出：逐项输出八个服务的状态，全部健康时退出 0。Expected: print all eight results.
# 常见失败兜底：参数错误退出 2，任何服务缺失或不健康退出 1；检查对应容器的健康日志。
set -euo pipefail
if (( $# != 1 )) || [[ "$1" != core ]]; then echo '用法：dp-health.sh core' >&2; exit 2; fi
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
if [[ ! -f deploy/.env ]]; then echo '缺少 deploy/.env。' >&2; exit 1; fi
compose=(docker compose --env-file deploy/.env -f deploy/docker-compose.yml --profile core)
failed=0
for service in mysql namenode datanode resourcemanager nodemanager hive-metastore hiveserver2 gateway; do
  if ! id=$("${compose[@]}" ps -a -q "$service") || [[ -z "$id" ]]; then
    echo "[失败] ${service}：无法找到容器。"
    failed=1
    continue
  fi
  # 主动重新执行同一项服务探测，避免使用上一个周期的健康缓存。Run a fresh readiness probe.
  if probe=$(docker inspect --format '{{index .Config.Healthcheck.Test 1}}' "$id") \
      && "${compose[@]}" exec -T "$service" bash -o pipefail -c "$probe"; then
    echo "[通过] ${service}：服务探测成功。"
  else
    echo "[失败] ${service}：服务探测失败，请检查容器日志。"
    failed=1
  fi
done
exit "$failed"
