#!/usr/bin/env bash
# 执行环境：阿里云服务器，工作目录 /opt/dataplatform。Environment: ECS repository root.
# 调用命令：bash deploy/scripts/dp-up.sh core [core...]；必需参数为分组名，目前仅支持 core。
# 前置条件：Docker Compose 可用，deploy/.env 已配置，三个自建镜像已按 README 顺序构建。
# 期望产出：八个核心服务健康后退出 0。Expected: eight healthy core services.
# 常见失败兜底：参数错误退出 2，启动或检查失败非零退出；使用 compose logs 检查具体服务。
set -euo pipefail
if (( $# == 0 )); then echo '用法：dp-up.sh core [core...]' >&2; exit 2; fi
for group in "$@"; do
  if [[ "$group" != core ]]; then echo "不支持的分组：$group" >&2; exit 2; fi
done
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
if [[ ! -f deploy/.env ]]; then echo '请先按 deploy/README.md 准备 deploy/.env。' >&2; exit 1; fi
# 等待真实健康检查，不以容器正在运行为成功。Wait for health, not merely process state.
docker compose --env-file deploy/.env -f deploy/docker-compose.yml --profile core \
  up -d --wait --wait-timeout 900
bash deploy/scripts/dp-health.sh core
