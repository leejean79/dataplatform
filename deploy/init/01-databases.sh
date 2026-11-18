#!/usr/bin/env bash
# 执行环境：官方 MySQL 容器首次启动，由 docker-entrypoint 调用，工作目录不限。
# 调用命令：镜像入口自动执行 /docker-entrypoint-initdb.d/01-databases.sh，无参数。
# 前置条件：空 MySQL 数据卷，Compose 已注入七个非空密码变量。
# 期望产出：七个数据库与六个业务账号创建完成，不创建业务表。
# 常见失败兜底：非零退出码表示初始化失败；检查日志与变量，勿直接复用部分初始化的数据卷。
set -euo pipefail
: "${MYSQL_ROOT_PASSWORD:?}" "${SOURCE_DB_PASSWORD:?}" "${HIVE_DB_PASSWORD:?}" \
  "${SCHEDULER_DB_PASSWORD:?}" "${DATAHUB_DB_PASSWORD:?}" "${PORTAL_DB_PASSWORD:?}" "${CDC_DB_PASSWORD:?}"
# 禁用反斜线转义并将单引号加倍，避免密码成为 SQL。Quote passwords as SQL literals.
sql_password() { printf '%s' "$1" | sed "s/'/''/g"; }
MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql --binary-mode --protocol=socket -uroot <<SQL
SET SESSION sql_mode='NO_BACKSLASH_ESCAPES';
CREATE DATABASE mes CHARACTER SET utf8mb4;
CREATE DATABASE qms CHARACTER SET utf8mb4;
CREATE DATABASE erp CHARACTER SET utf8mb4;
CREATE DATABASE hive_metastore CHARACTER SET utf8mb4;
CREATE DATABASE dolphinscheduler CHARACTER SET utf8mb4;
CREATE DATABASE datahub CHARACTER SET utf8mb4;
CREATE DATABASE dp_portal CHARACTER SET utf8mb4;
CREATE USER 'dp_source'@'%' IDENTIFIED BY '$(sql_password "$SOURCE_DB_PASSWORD")';
CREATE USER 'hive'@'%' IDENTIFIED BY '$(sql_password "$HIVE_DB_PASSWORD")';
CREATE USER 'dolphinscheduler'@'%' IDENTIFIED BY '$(sql_password "$SCHEDULER_DB_PASSWORD")';
CREATE USER 'datahub'@'%' IDENTIFIED BY '$(sql_password "$DATAHUB_DB_PASSWORD")';
CREATE USER 'dp_portal'@'%' IDENTIFIED BY '$(sql_password "$PORTAL_DB_PASSWORD")';
CREATE USER 'dp_cdc'@'%' IDENTIFIED BY '$(sql_password "$CDC_DB_PASSWORD")';
GRANT ALL PRIVILEGES ON mes.* TO 'dp_source'@'%';
GRANT ALL PRIVILEGES ON qms.* TO 'dp_source'@'%';
GRANT ALL PRIVILEGES ON erp.* TO 'dp_source'@'%';
GRANT ALL PRIVILEGES ON hive_metastore.* TO 'hive'@'%';
GRANT ALL PRIVILEGES ON dolphinscheduler.* TO 'dolphinscheduler'@'%';
GRANT ALL PRIVILEGES ON datahub.* TO 'datahub'@'%';
GRANT ALL PRIVILEGES ON dp_portal.* TO 'dp_portal'@'%';
GRANT SELECT, SHOW VIEW ON mes.* TO 'dp_cdc'@'%';
GRANT SELECT, SHOW VIEW ON qms.* TO 'dp_cdc'@'%';
GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'dp_cdc'@'%';
SQL
# 只在全部建库、建用户及授权语句成功后标记持久卷。Mark completion only after all grants succeed.
touch /var/lib/mysql/.dp-core-init-complete
