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
# 宿主机与容器都限制执行时间。Bound the CLI call and the probe inside the container.
check() {
  local service=$1 description=$2 rc
  shift 2
  if timeout -k 5s 75s "${compose[@]}" exec -T "$service" timeout -k 3s 60s "$@"; then
    printf '[通过] %s：%s\n' "$service" "$description"
  else
    rc=$?
    printf '[失败] %s：%s（退出码 %d，124 表示超时）\n' "$service" "$description" "$rc" >&2
    failed=1
  fi
}
check mysql '初始化已完成且七个数据库均可见' bash -o pipefail -c \
  'test -f /var/lib/mysql/.dp-core-init-complete && MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -N -uroot -e "SHOW DATABASES" | grep -Exc "mes|qms|erp|hive_metastore|dolphinscheduler|datahub|dp_portal" | grep -x 7'
check namenode '名称节点可列出 HDFS 根目录' hdfs dfs -ls /
check datanode 'DataNode 已注册为存活节点' bash -o pipefail -c \
  'hdfs dfsadmin -report -live | grep -E "^Hostname: datanode$"'
check resourcemanager 'YARN 有 1 个 RUNNING 节点' bash -o pipefail -c \
  'yarn node -list -states RUNNING | grep -Ex "Total Nodes:[[:space:]]*1"'
check nodemanager '系统时区为上海，当前偏移为 +0800' bash -ec \
  'test "$(readlink -f /etc/localtime)" = /usr/share/zoneinfo/Asia/Shanghai && test "$(date +%z)" = +0800'
check nodemanager 'JVM 默认时区为 Asia/Shanghai' bash -o pipefail -c \
  'jrunscript -e "print(java.util.TimeZone.getDefault().getID())" | grep -x Asia/Shanghai'
check hive-metastore 'Hive 元数据库模式验证成功' schematool -dbType mysql -validate
for service in hiveserver2 gateway; do
  check "$service" '客户端环境和配置均无元数据库凭据' bash -ec \
    'test -z "${HIVE_DB_PASSWORD+x}" && test -s "$HIVE_CONF_DIR/hive-site.xml" && ! grep -Eq "javax.jdo.option.Connection|HIVE_DB_PASSWORD" "$HIVE_CONF_DIR/hive-site.xml"'
  check "$service" '经 HiveServer2 查询数据库返回 default' bash -o pipefail -c \
    'beeline --silent=true --showHeader=false --outputformat=tsv2 -u jdbc:hive2://hiveserver2:10000 -n dp -e "show databases" | grep -x default'
done
check gateway '网关可列出 HDFS 根目录' hdfs dfs -ls /
exit "$failed"
