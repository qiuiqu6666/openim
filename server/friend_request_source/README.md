# 好友申请来源元数据

## 服务端需要修改的内容

`friend_apply_source.patch` 针对 Chat 服务的 `internal/rpc/chat/friend_grant.go`，在 `sendFriendApply` 发送到 OpenIM 的申请 `ex` 中增加 `addSource: row.Source`。保留原有 `v`、`op`、`mac`；来源用于展示，签名核验及权限仍由数据库中的凭证记录决定。

客户端读取 SDK `FriendApplicationInfo.ex.addSource`，来源缺失时显示“来源未知”。后续新申请会包含来源，既有申请不会回写或伪造来源。本补丁不改申请消息、好友关系、邀请或双 ID。

## 适用位置及验证

当前服务端目录为 `/www/wwwroot/chat`。已对该目录执行 `git apply --check` 验证补丁上下文，未应用补丁或发布线上服务。服务端工作目录已有其他改动，发布时应保留这些改动并明确实际构建范围，不以本补丁替换整个源文件。

客户端 29 项解析及亮暗列表回归通过，定向静态检查通过。服务端补丁的编译、线上发布和真实收发申请验证尚未完成。

## 实施步骤

以下 Linux 命令在 Chat 服务主机执行。当前核对的代码目录是 `/www/wwwroot/chat`，Go 位于 `/usr/local/go/bin`。先把本目录的 `friend_apply_source.patch` 上传到服务器，例如 `/tmp/friend_apply_source.patch`。不要将客户端整个目录覆盖到服务端。

### 1 备份并应用补丁

```bash
set -e
cd /www/wwwroot/chat
deploy_dir=$(mktemp -d /www/wwwroot/chat/_output/friend-source-deploy.XXXXXX)
printf '本次备份目录：%s\n' "$deploy_dir"
cp -p internal/rpc/chat/friend_grant.go "$deploy_dir/friend_grant.go.before"
cp -p _output/bin/platforms/linux/amd64/chat-rpc "$deploy_dir/chat-rpc.before"
tr -d '\r' < /tmp/friend_apply_source.patch > "$deploy_dir/source.patch"
git apply --check "$deploy_dir/source.patch"
git apply "$deploy_dir/source.patch"
/usr/local/go/bin/gofmt -w internal/rpc/chat/friend_grant.go
diff -u "$deploy_dir/friend_grant.go.before" internal/rpc/chat/friend_grant.go || true
```

检查差异只增加 `addSource` 和相关排版。保存输出的备份目录路径，后续命令需要它。补丁若已应用，`git apply --check` 会失败，此时检查源码，不要重复添加字段。

修改后的发送代码如下。来源必须取服务端凭证记录的 `row.Source`，不能直接信任客户端传入的来源文字。

```go
ex, err := json.Marshal(map[string]any{
    "addSource": row.Source,

    "v":   keyID,
    "op":  row.OpID,
    "mac": friendgrant.Sign(secret, strconv.Itoa(keyID), row.OpID, row.ApplicantIMID, row.TargetIMID),
})
```

继续使用现有 `o.IM.AddFriendApply(..., string(ex))`。不需要新增接口、数据库字段或迁移，不修改签名算法，也不更换 userID。现有回调只解析 `v`、`op`、`mac`，新增 JSON 字段不参与授权判断。

### 2 测试并编译

在同一终端保留 `deploy_dir`，执行：

```bash
GOMAXPROCS=2 /usr/local/go/bin/go test -mod=readonly -p 1 ./internal/rpc/chat \
  -run '^(TestClientAddSourceOpen|TestAccountAddMatchesPublicAccount|TestParseClientAddSource|TestGrantDeniedDetected)$' -count=1
GOMAXPROCS=2 /usr/local/go/bin/go test -mod=readonly -p 1 ./pkg/common/friendgrant -count=1
GOMAXPROCS=2 /usr/local/go/bin/go build -mod=readonly -p 1 \
  -o "$deploy_dir/chat-rpc.new" ./cmd/rpc/chat-rpc
```

必须所有命令成功后再发布。以上测试覆盖已有来源及签名规则；新增字段仍需通过后面的完整申请链路验收。当前服务端目录已有其他修改，构建使用该目录的全部现有源码，发布前确认这些改动属于当前部署版本。不要执行 `git reset` 或覆盖其他文件。

### 3 发布 Chat RPC

当前核对到的运行方式为：

```text
程序：/www/wwwroot/chat/_output/bin/platforms/linux/amd64/chat-rpc
参数：-i 0 -c /www/wwwroot/chat/config/
工作目录：/www/wwwroot/chat
日志：/tmp/chat-rpc.out
监听端口：30300
```

当前未发现管理该进程的 systemd 或 supervisor 服务。发布前重新核对进程及其管理方式，进程 PID 会变化，不要照抄旧 PID。如果已有服务管理器，按该管理器发布。

手动发布时依次执行：

1. 记录正在运行的 Chat RPC 的实际参数、工作目录和环境变量；保留环境变量用于重启，避免输出其中的密钥。
2. 将编译产物复制到生产二进制旁的临时文件，保持原权限，再原子重命名替换生产二进制。不要直接覆盖正在使用的二进制文件。
3. 仅向核对过的 Chat RPC 进程发送 `SIGTERM`，等待退出。
4. 用原参数、原工作目录、原环境变量后台启动新 Chat RPC，标准输出及错误继续写入原日志位置。
5. 确认新进程持续存活、30300 端口监听，检查日志中是否有启动失败或注册失败。

本改动只需要更新 Chat RPC；Chat API、OpenIM 服务和数据库不需要因本改动重启。仅看到端口监听不代表业务验收完成。

### 4 验收新申请

使用两个测试账号完成一次授权的好友申请，不要用真实用户做发布验证。

1. 从公开聊天号、二维码或群成员等有效入口获取凭证：`POST /chat/friend-grants`。
2. 使用凭证走客户端现有好友申请流程。
3. 在接收方读取 SDK `FriendApplicationInfo.ex`，确认 JSON 包含 `addSource`，同时保留原有 `v`、`op`、`mac`。
4. 确认“新的好友”列表显示对应来源，原验证消息仍然显示，申请审核正常。

来源值与显示对应：

| addSource | 客户端显示 |
| --- | --- |
| account | 聊天号 |
| phone | 手机号 |
| email | 邮箱 |
| qrcode | 二维码 |
| link | 邀请链接 |
| card | 名片 |
| group | 群聊 |
| manage | 群管理 |

旧申请缺少字段时继续显示“来源未知”。不根据昵称、IM userID、验证消息猜来源，不回填历史记录。新申请若仍缺字段，检查是否运行了新二进制、是否经过 `sendFriendApply`，以及 SDK 返回的原始 `ex`。不要把仅验证消息或来源显示成功当作签名验证成功。

### 5 回滚

如果新服务无法启动或好友申请异常，用本次备份目录的 `chat-rpc.before` 原子替换生产二进制，停止失败的新进程，再按原参数、工作目录和环境启动旧版本，复查端口和业务。保留备份及故障日志。

需要回滚源码时，优先使用本次保存的 `source.patch` 执行 `git apply --reverse --check`，确认通过后再 `git apply --reverse`。如果该文件已经出现其他修改，先核对差异，不直接用备份覆盖，以免丢失别人的更新。

## 当前状态

截至本次文档整理：客户端完成；服务端补丁上下文检查通过；尚未应用补丁、执行服务端编译或发布线上服务。以上发布和验收步骤是待执行说明。
