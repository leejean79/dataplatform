#!/usr/bin/env bash
# 执行环境：阿里云 ECS，工作目录 /opt/dataplatform。
# 调用命令：bash deploy/scripts/smoke-offline.sh，无参数。
# 前置条件：core 健康，Gateway 已按 M0-02 重建并挂载 Spark 配置。
# 期望产出：打印应用 ID、SUCCEEDED、耗时、时区及 Hive 行数 3，成功退出 0。
# 常见失败兜底：失败非零退出；保留提交日志，按应用 ID 查询 YARN 完整日志。
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
gateway=(docker compose --env-file deploy/.env -f deploy/docker-compose.yml exec -T --interactive=false gateway)
log=$(mktemp)
echo "Spark 提交日志：$log"
# 保留原始提交输出，包括失败应用的 ID。Keep submission output even on failure.
start=$SECONDS
status=0
"${gateway[@]}" spark-submit --master yarn --deploy-mode cluster --name dp-smoke-offline \
  --class OfflineSmoke /opt/spark/smoke/runner.jar 2>&1 | tee "$log" || status=$?
elapsed=$((SECONDS - start))
app=$(grep -Eo 'application_[0-9]+_[0-9]+' "$log" | tail -1) || { echo '未找到 YARN 应用 ID。' >&2; exit 1; }
echo "Application ID=$app，提交至结束耗时=${elapsed}s"
if (( status != 0 )); then
  "${gateway[@]}" yarn logs -applicationId "$app" >"$log.yarn" 2>&1 || true
  echo "YARN 日志：$log.yarn" >&2
  exit "$status"
fi
report=$("${gateway[@]}" yarn application -status "$app")
echo "$report"
grep -Eq 'Final-State[[:space:]]*:[[:space:]]*SUCCEEDED' <<<"$report"
evidence=$("${gateway[@]}" hdfs dfs -cat "/tmp/dp_smoke/$app.txt")
echo "$evidence"
# 只统计证据中的执行器。Count only executors that ran the probe.
awk '{
  for (i = 1; i <= NF; i++) {
    if ($i ~ /^executor\[[^]]+\]=/) {
      split($i, fields, /[][]/)
      if (!seen[fields[2]]++) {
        ids = ids (count ? ", " : "") fields[2]
        count++
      }
    }
  }
}
END { printf "参与时区探测的执行器数量=%d，编号=%s\n", count, ids }' <<<"$evidence"
beeline=(beeline --silent=true --showHeader=false --outputformat=tsv2 -n dp -u jdbc:hive2://hiveserver2:10000)
count=$("${gateway[@]}" "${beeline[@]}" -e 'SELECT id FROM dp_smoke.t_offline' | awk 'END { print NR }')
echo "HiveServer2 查询返回行数=$count"
[[ "$count" == 3 ]]
part=$("${gateway[@]}" "${beeline[@]}" -e 'SHOW PARTITIONS dp_smoke.t_offline')
echo "北京时间 2026-11-25 00:30 对应分区：$part"
[[ "$part" == dt=2026-11-25 ]]
echo '离线冒烟测试通过。'
