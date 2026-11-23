#!/usr/bin/env bash
# 执行环境：Hadoop 容器，工作目录 /home/dp。Environment: Hadoop container.
# 调用命令：dp-hadoop-entrypoint namenode|datanode|resourcemanager|nodemanager。
# 前置条件：只读 Hadoop 配置已挂载，/data 的命名卷可由 dp 用户写入。
# 期望产出：前台运行对应进程。Expected: run the requested daemon in foreground.
# 常见失败兜底：退出码 1 表示目录或进程失败，2 表示参数错误；查看容器日志。
set -euo pipefail
case "${1:-}" in
  namenode)
    # 仅格式化空卷，已有但不完整的数据必须人工检查。Never reformat existing data.
    if [[ ! -f /data/hdfs/name/current/VERSION ]]; then
      if [[ -n "$(ls -A /data/hdfs/name)" ]]; then
        echo '名称节点目录非空且缺少 VERSION，请检查数据卷。' >&2
        exit 1
      fi
      hdfs namenode -format -nonInteractive
    fi
    exec hdfs namenode
    ;;
  datanode) exec hdfs datanode ;;
  resourcemanager) exec yarn resourcemanager ;;
  nodemanager) exec yarn nodemanager ;;
  *) echo '参数必须为 namenode、datanode、resourcemanager 或 nodemanager。' >&2; exit 2 ;;
esac
