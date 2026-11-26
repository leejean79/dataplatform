# OPS-01-R1 修复实例查询

## 目标

`deploy/scripts/refresh-ecs-ip.sh` 能够成功查询到测试服务器的公网地址，OPS-01 中未通过的第 2 条与第 3 条验收命令全部通过。

## 前置任务

OPS-01。

## 依据的设计文档

- `docs/tasks/OPS-01-远程运维通道.md`。
- `AGENTS.md` 第 12 节与第 13 节。

## 背景

项目负责人已经在本机用同一份配置文件直接调用阿里云命令行工具做了对照，结果如下：

- 不带 `--mode AK` 参数时查询成功，实例状态为 Running，公网地址位于 `PublicIpAddress.IpAddress`，`EipAddress.IpAddress` 为空。
- 带 `--mode AK` 参数时查询失败，错误信息为 `ERROR: region can't be empty`。

因此失败的原因是脚本中的 `--mode AK` 参数，与账号权限无关。

## 实现范围

1. 修改 `deploy/scripts/refresh-ecs-ip.sh`，去掉 `aliyun ecs DescribeInstances` 命令中的 `--mode AK` 参数。访问密钥仍然只通过环境变量传给该命令。
2. 查询失败时，在原有提示之后追加输出命令行工具返回内容中的错误信息，最多输出前 3 行，并且只保留以 `ERROR` 开头的行或者包含 `Code`、`Message` 的行。不得输出完整的返回内容。
3. 更新 `deploy/README.md`“远程运维通道”一节：在主机段示例中增加 `IdentitiesOnly yes`，并且说明查询失败时如何根据错误信息排查。

## 明确不做的范围

- 不修改脚本中解析地址和更新 SSH 配置的逻辑。
- 不修改 `deploy/README.md` 中离线冒烟测试的说明，这部分属于 M0-02-R1。
- 不读取、输出或修改 `~/.dataplatform-aliyun.conf` 的内容和私钥文件。
- 不修改 `docs/` 目录。

## 验收命令

以下命令的执行环境均为项目负责人的本地电脑，工作目录为仓库根目录。合并请求中的输出必须把公网地址替换为 `<公网地址>`。

| 序号 | 命令 | 期望输出 |
| --- | --- | --- |
| 1 | `bash -n deploy/scripts/refresh-ecs-ip.sh && git diff --check` | 没有输出，退出码为 0。 |
| 2 | `bash deploy/scripts/refresh-ecs-ip.sh --dry-run; echo "退出码=$?"` | 输出实例状态为 Running、地址字段为 `PublicIpAddress.IpAddress` 以及公网地址，退出码为 0，`~/.ssh/config` 没有变化。 |
| 3 | `bash deploy/scripts/refresh-ecs-ip.sh; echo "退出码=$?"` | 输出同步结果，随后 `ssh dp-ecs hostname` 返回 `dataplatform-test-01`，退出码为 0。 |
| 4 | `ssh dp-ecs 'cd /opt/dataplatform && git rev-parse --short HEAD'` | 返回服务器上仓库当前的提交编号。 |
| 5 | `git grep -lE 'LTAI[0-9A-Za-z]{12,}\|i-[0-9a-z]{10,}\|BEGIN [A-Z ]*PRIVATE KEY-----'; echo "退出码=$?"` | 没有列出任何文件，退出码为 1。 |
| 6 | 用一个不存在的实例编号或者错误的地域做一次失败对照，具体做法写在合并请求中，不得修改项目负责人的配置文件 | 脚本以非零退出码结束，输出不超过 3 行错误信息，其中没有访问密钥和完整的返回内容。 |

## 交付物

- 修改后的 `deploy/scripts/refresh-ecs-ip.sh` 和 `deploy/README.md`。

## 已知风险与需要反馈的问题

1. 第 6 条验收需要在不改动真实配置文件的前提下制造一次失败。如果做不到，请说明原因，不要为此临时改写配置文件。
2. 如果去掉 `--mode AK` 之后查询仍然失败，请停止并且在合并请求中附上第 2 项新增的错误信息。
