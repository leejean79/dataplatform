#!/usr/bin/env bash
# 执行环境：项目负责人的 macOS 本机，工作目录为仓库根目录。
# 调用命令：bash deploy/scripts/refresh-ecs-ip.sh [--dry-run]；可选参数仅查询地址。
# 前置条件：已安装 aliyun、python3 和 ssh，负责人已按 README 准备凭据及 dp-ecs 主机段。
# 期望产出：输出实例状态及地址；正式模式还会更新 HostName 并输出远程主机名。
# 常见失败兜底：参数错误返回 2；配置或查询失败返回非零，SSH 失败保留原退出码与日志。
set +x
set -euo pipefail
case "$#:${1:-}" in 0:|1:--dry-run) ;; *) echo '用法：refresh-ecs-ip.sh [--dry-run]' >&2; exit 2 ;; esac
conf="$HOME/.dataplatform-aliyun.conf"
if [[ ! -f "$conf" || "$(stat -f '%Lp' "$conf")" != 600 ]]; then
  echo '需要权限为 600 的 ~/.dataplatform-aliyun.conf。' >&2
  exit 1
fi
# 凭据只在查询子进程中加载，不进入命令行或 SSH 环境。Scope credentials to the query.
result=$(
  source "$conf" >/dev/null 2>&1
  : "${ALIYUN_ACCESS_KEY_ID:?}" "${ALIYUN_ACCESS_KEY_SECRET:?}" "${ALIYUN_REGION:?}" "${ECS_INSTANCE_ID:?}"
  ALIBABA_CLOUD_ACCESS_KEY_ID="$ALIYUN_ACCESS_KEY_ID" \
  ALIBABA_CLOUD_ACCESS_KEY_SECRET="$ALIYUN_ACCESS_KEY_SECRET" \
    aliyun ecs DescribeInstances --mode AK --region "$ALIYUN_REGION" --RegionId "$ALIYUN_REGION" \
      --InstanceIds "[\"$ECS_INSTANCE_ID\"]" 2>/dev/null
) || { echo '实例查询失败，请检查本地配置及只读查询权限。' >&2; exit 1; }
address=$(printf '%s' "$result" | python3 -c '
import ipaddress, json, sys
try:
    instance, = json.load(sys.stdin)["Instances"]["Instance"]
    if instance["Status"] != "Running":
        sys.exit("实例不处于运行状态。")
    regular = instance.get("PublicIpAddress", {}).get("IpAddress", [])
    field = "PublicIpAddress.IpAddress" if regular else "EipAddress.IpAddress"
    ip = regular[0] if regular else instance.get("EipAddress", {}).get("IpAddress")
    if not ip:
        sys.exit("运行中的实例没有公网地址。")
    print(ipaddress.IPv4Address(ip))
    print("实例状态：Running；地址字段：" + field, file=sys.stderr)
except (ValueError, TypeError, KeyError, AttributeError):
    sys.exit("无法解析单实例查询结果或 IPv4 地址。")
')
echo "公网地址：$address"
[[ ${1:-} != --dry-run ]] || exit 0

# 按段替换唯一的 HostName，保留其他字节与权限。Replace only the selected address.
python3 - "$HOME/.ssh/config" "$address" <<'PY'
import os, re, sys, tempfile
from pathlib import Path
path = Path(sys.argv[1]).resolve(strict=True)
original = path.read_bytes()
lines = original.splitlines(keepends=True)
active = False
blocks = 0
indices = []
for i, line in enumerate(lines):
    directive = re.match(rb'^\s*(Host|Match)(?:\s*=\s*|\s+)([^#\r\n]*)', line, re.I)
    if directive:
        active = directive[1].lower() == b'host' and directive[2].strip() == b'dp-ecs'
        blocks += int(active)
    elif active and re.match(rb'^\s*HostName(?:\s|=)', line, re.I):
        indices.append(i)
if blocks != 1 or len(indices) != 1:
    sys.exit("需要唯一的 Host dp-ecs 主机段及一行 HostName。")
i = indices[0]
pattern = rb'^(\s*HostName(?:\s*=\s*|\s+))("[^"]+"|[^\s#]+)([ \t]*(?:#[^\r\n]*)?\r?\n?)\Z'
m = re.match(pattern, lines[i], re.I)
if not m:
    sys.exit("无法识别 HostName 行，请人工核对。")
lines[i] = m[1] + sys.argv[2].encode("ascii") + m[3]
updated = b"".join(lines)
if updated != original:
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as tmp:
        try:
            tmp.write(updated)
            tmp.flush()
            os.fchmod(tmp.fileno(), path.stat().st_mode & 0o777)
            os.replace(tmp.name, path)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
print("dp-ecs 的 HostName 已与实例公网地址同步。")
PY
exec ssh dp-ecs hostname
