#!/usr/bin/env bash
# 执行环境：Hive 或网关容器，工作目录 /home/dp。Environment: Hive/gateway container.
# 调用命令：dp-hive-entrypoint metastore|hiveserver2|gateway。
# 前置条件：Hadoop 配置与 hive-site.xml.template 已挂载，仅 metastore 需要 HIVE_DB_PASSWORD。
# 期望产出：生成仅容器内可读的配置并运行服务；已有元数据不会重复初始化。
# 常见失败兜底：退出码 1 表示数据库、模式或 HDFS 失败，2 表示参数错误；查看日志。
set -euo pipefail
case "${1:-}" in metastore|hiveserver2|gateway) ;; *) echo '无效的 Hive 服务参数。' >&2; exit 2 ;; esac
umask 077
if [[ "$1" != metastore ]]; then
  cp /etc/dp-hive/client-site.xml "$HIVE_CONF_DIR/hive-site.xml"
  if [[ "$1" == gateway ]]; then exec sleep infinity; fi
  exec hiveserver2
fi
: "${HIVE_DB_PASSWORD:?必须提供 Hive 数据库密码}"
# 密码按 XML 文本转义，不把凭据写回只读挂载目录。Escape secrets into private runtime config.
python3 - <<'RENDER'
import os
from pathlib import Path
from xml.sax.saxutils import escape
source = Path('/etc/dp-hive/hive-site.xml.template').read_text()
Path(os.environ['HIVE_CONF_DIR'], 'hive-site.xml').write_text(
    source.replace('${HIVE_DB_PASSWORD}', escape(os.environ['HIVE_DB_PASSWORD'])))
RENDER
# 连接失败直接退出；仅完全空的模式允许初始化。Connection failure must never trigger init.
table_count=$(MYSQL_PWD="$HIVE_DB_PASSWORD" mysql --protocol=TCP -h mysql -u hive -N -B \
  -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='hive_metastore'")
if [[ "$table_count" == 0 ]]; then
  schematool -dbType mysql -initSchema
else
  schematool -dbType mysql -info
fi
schematool -dbType mysql -validate
hdfs dfs -mkdir -p /tmp /user/hive/warehouse /tmp/logs
hdfs dfs -chmod 1777 /tmp /tmp/logs
exec hive --service metastore
