# 收藏服务端部署方案（待批准，2026-10-05）

用户本次选择“暂不部署，先保留修复包”。下方是后续明确授权部署时使用的方案，本轮不执行生产切换。

本文件将 0001–0004 的隔离验证产物整理为可审阅的生产切换方案。**本次仅只读核验和编写方案，未执行部署、重启或配置变更。**生产切换需要用户明确批准；批准范围应包括 Chat RPC 的短暂停机、二进制和配置切换、失败回滚，以及指定测试账号的新建收藏验收。

核验时间为服务器 UTC `2026-10-04T21:08:34Z`，对应台湾时间 2026-10-05。进程 PID 是当时快照，实际执行前必须重新识别。

## 1. 已确认的运行方式

| 项目 | 当前证据 |
| --- | --- |
| 服务源码根目录 | `/www/wwwroot/chat` |
| Chat RPC | PID `222071`，可执行文件 `/www/wwwroot/chat/_output/bin/platforms/linux/amd64/chat-rpc` |
| RPC 工作目录 / 启动参数 | `/www/wwwroot/chat`；`-i 0 -c /www/wwwroot/chat/config/` |
| RPC 监听 | TCP `30300`，现场监听进程为上述 `chat-rpc` |
| RPC 二进制时间 / 启动时间 | 均为 UTC `2026-10-04T01:28:35Z` |
| RPC 输出 | `/tmp/chat-rpc.out`；服务结构化日志在 `/www/wwwroot/chat/_output/logs/` |
| RPC 父进程 | PID `222070` 的 bash，来自先前 SSH 启动脚本，父进程为 PID 1；cgroup 为 `session-228.scope` |
| Chat API | PID `205722`，`/www/wwwroot/chat/_output/bin/platforms/linux/amd64/chat-api`，监听 `10008`，独立进程 |
| 存储公开端口 | `10005`，现场由 docker-proxy 监听；不属于本次 RPC 进程切换 |
| Go 环境 | `go1.27.1 linux/amd64`；生产 `go.mod` 声明 Go `1.25.0` |

读取 RPC 父进程命令行确认：原启动脚本在加载 `config/pnvs.env`、`config/captcha.env` 后，以 `nohup` 运行以下命令，参数与当前进程一致：

```sh
cd /www/wwwroot/chat
nohup ./_output/bin/platforms/linux/amd64/chat-rpc \
  -i 0 -c /www/wwwroot/chat/config/ >> /tmp/chat-rpc.out 2>&1 &
```

该脚本没有持续拉起进程的循环。当前 RPC 不归属 systemd `.service`；已检查的 systemd/supervisor 配置位置没有发现管理当前 RPC 的配置，服务器也没有 `supervisorctl` 命令。因此以下切换沿用已核实的直接进程启动方式，没有假定存在 `systemctl restart chat-rpc` 等管理命令。

`pkg/common/startrpc/start.go:98–110` 接收 SIGTERM 并执行有 15 秒期限的 gRPC GracefulStop。应向验证后的 RPC PID 发送 TERM，等待进程和监听退出；退出超时应停止切换并调查，不自动升级为 KILL。

## 2. 当前版本与需要切换的内容

生产源码 `favorite.go`、`favorite_archive.go`、`favorite_write.go` 仍是 2026-10-02 UTC 的旧文件。运行中的 RPC 二进制存在 `RetryChatFavoriteArchive` / `runFavoriteJob` 正控制符号，但没有 `newFavoritePublicSigner`、`readFavoriteSource`、`probeFavoriteSource`、`ResolveObjectURL` 等补丁符号；`favorite.publicStorageURL` 也没有配置。上次补丁尚未加载。

按以下顺序应用到**生产源码的独立副本**：

1. `0001-favorite-public-storage-signing.patch`：公开端点独立 signer。
2. `0002-favorite-delete-replay-receipts.patch`：已持久化删除回执的顺序重放。
3. `0003-favorite-openim-object-name-resolution.patch`：聊天媒体逻辑名称解析。
4. `0004-favorite-source-error-classification.patch`：来源故障的安全分类与数字诊断。

完整范围见 [补丁说明](README.md) 和 [0004 验证说明](0004-source-diagnostics.md)。0004 不解决用户从收藏页添加图片/文件的所有可能原因；当前受控 fresh image/file 的 init、服务器本机 PUT、complete、create(uploadIDs) 均成功，尚未捕获用户实际 20056 的请求阶段。

仅合并以下无凭据配置到现有 `favorite` 段：

```yaml
favorite:
  publicStorageURL: http://8.217.191.236:10005
```

完整生产 YAML 继续保留其他字段、内部 endpoint、bucket 和凭据。示例片段不能替换整个配置。内部 MinIO client 继续执行服务端读写，公开 signer 在签名之前选用上述根端点；不能事后改签名 URL 的 host。

**本组补丁只需切换 `chat-rpc`。**补丁没有修改 Chat API 路由、HTTP DTO、protobuf 方法或消息 wire schema；公开 signer 和原件解析在 RPC 启动时由 `internal/rpc/chat/start.go:102` 初始化。`chat-api` 继续使用相同 RPC 服务和返回字段。可在 stage 额外编译 `./cmd/api/chat-api` 验证源码兼容，但本次不需要替换或重启其二进制。

## 3. 隔离 stage 与切换前验证

下面是拟执行命令，**本文件生成期间没有运行它们**。`CHAT`、`STAGE`、`PATCHES` 等变量需在同一审阅过的部署会话中明确设置；不从用户输入拼接 shell 命令。

```sh
set -e
CHAT=/www/wwwroot/chat
STAGE=$(mktemp -d /tmp/favorite-deploy-20261005.XXXXXX)
chmod 700 "$STAGE"
mkdir -p "$STAGE/source" "$STAGE/patches" "$STAGE/private-config" "$STAGE/tmp"

rsync -a \
  --exclude=/.git/ --exclude=/config/ --exclude=/logs/ \
  --exclude=/_output/ --exclude=/backup/ --exclude=/web/ \
  --exclude=/asr-proxy/ --exclude=/livekit/ --exclude='*.env' \
  "$CHAT/" "$STAGE/source/"
```

该副本包含 Go 源码及 `go:embed` 需要的包内资源，排除生产配置、环境文件、日志和运行产物。补丁文件从本项目 `server/favorites/patches/` 上传至 `$STAGE/patches/`，核对完整文件名和 SHA-256。生产 Go 文件不在此步骤中改写。

```sh
cd "$STAGE/source"
for patch in \
  0001-favorite-public-storage-signing.patch \
  0002-favorite-delete-replay-receipts.patch \
  0003-favorite-openim-object-name-resolution.patch \
  0004-favorite-source-error-classification.patch
do
  git apply --check "$STAGE/patches/$patch"
  git apply "$STAGE/patches/$patch"
done

export GOMODCACHE="$STAGE/go-mod-cache"
export GOCACHE="$STAGE/go-build-cache"
export TMPDIR="$STAGE/tmp"
go test ./internal/rpc/chat ./pkg/common/imapi -count=1
go build -o "$STAGE/chat-rpc" ./cmd/rpc/chat-rpc
go build -o "$STAGE/chat-api-compatibility-check" ./cmd/api/chat-api
sha256sum "$STAGE/chat-rpc" "$STAGE/patches/"*.patch
```

每个 `apply --check`、测试和构建都应检查退出码，任何失败立即停止。现有隔离 0004 结果是 53 项 Go 检查通过、完整 RPC 编译通过；部署 stage 应在重新读取的生产源码副本上重做，防止基线期间变化。不得为了“启动检查”提前运行新 RPC 对接生产配置：RPC 正常启动会注册服务并执行后台收藏维护任务。

配置准备也只在私有 stage 中完成：将生产 `chat-rpc-chat.yml` 复制至 `$STAGE/private-config/`，保留原内容，仅插入公开根端点字段。用 YAML 解析器检查 `favorite` 是 mapping，新增字段恰为预定值，再比较新旧解析结果，确认除此字段之外完全一致。校验只输出是否通过；不打印 YAML、环境文件、凭据或配置 diff。记录原配置文件哈希，在切换前再次比对；发现外部修改则重新准备。

## 4. 备份与审阅记录

在服务器创建权限 `0700` 的独立发布备份目录，例如 `/www/wwwroot/chat/backup/favorites-20261005-<timestamp>/`。目录名由部署时生成的固定时间戳组成，记录完整路径以供回滚；不得覆盖先前备份。

备份至少包含：

- 当前运行的 RPC 可执行文件和磁盘 RPC 文件；核对二者哈希一致后使用该文件作为回滚二进制。若不一致或 `/proc/<pid>/exe` 为 deleted，应先停止并核对发布基线。
- 原 `config/chat-rpc-chat.yml`，以及启动需要的 `pnvs.env`、`captcha.env`；这些文件只存于服务器保护目录。
- RPC 读取的 `redis.yml`、`discovery.yml`、`mongodb.yml`、`share.yml`，保留可恢复的完整配置集合。本次只切换 `chat-rpc-chat.yml`，其余文件记录哈希并保持原位。
- 经过 1→4 应用和构建的 stage 源码快照、补丁、测试结果和新二进制哈希；快照不包含生产凭据和用户日志。
- 原 PID、exe、启动参数、工作目录、监听端口、owner/mode，以及明确的启动和回滚步骤。文件值不复制到前端仓库。

当前 RPC 文件 owner/mode 为 `root:root 0755`，主 YAML 为 `root:root 0644`，两个环境文件为 `root:root 0600`。备份目录保护其内容；替换文件保留现有 owner/mode。

本方案的生产可执行切换范围是 **RPC 二进制 + 一个 YAML**。生产源码 checkout 保留原样，发布快照作为这次实际二进制的构建依据归档。发布记录必须注明此差异；下一次构建应使用归档的新源码基线或先审阅同步源码，不能从旧 checkout 直接 `go build` 并覆盖已修复二进制。

## 5. 批准后切换

1. 再次核对当前监听 30300 的 PID、`/proc/<pid>/exe`、cwd、参数和二进制哈希。要求恰为预期 Chat RPC，记录为本次 `OLD_PID`；不按名称批量停止进程，也不直接用最早快照的 PID。
2. 检查配置哈希仍等于 stage 基线；备份全部完成，新二进制和新 YAML 已通过验证。将新文件预置到目标所在的**同一目录**中的唯一临时文件，预置期间旧 RPC 继续运行。
3. 向核对后的 `OLD_PID` 发送 `kill -TERM "$OLD_PID"`，等待该 PID 和 30300 监听均退出。原代码有 15 秒 graceful stop 界限；部署等待可设 30 秒。若仍存活/监听，不覆盖文件，停止切换并调查。
4. 旧进程退出后，分别以同目录 `mv -T` 原子 rename 替换二进制和主 YAML。两文件不是跨文件的原子事务；通过“旧进程已停、新进程未启动”的窗口保证不会加载半套配置。若任一 rename 失败，在启动之前恢复两份原文件。
5. 沿用现场 env 与 nohup 参数启动一个新 RPC，记录真实新 PID。启动示例如下；所有变量须指向上述核对过的固定绝对路径。

```sh
RPC_BIN=/www/wwwroot/chat/_output/bin/platforms/linux/amd64/chat-rpc
RPC_CONFIG=/www/wwwroot/chat/config/
(
  set -a
  . /www/wwwroot/chat/config/pnvs.env
  . /www/wwwroot/chat/config/captcha.env
  set +a
  cd /www/wwwroot/chat
  exec nohup "$RPC_BIN" -i 0 -c "$RPC_CONFIG" \
    >> /tmp/chat-rpc.out 2>&1
) </dev/null &
NEW_PID=$!
```

预置与 rename 的固定目标：

| 新临时文件，名称需带本次唯一发布 ID | rename 目标 |
| --- | --- |
| `/www/wwwroot/chat/_output/bin/platforms/linux/amd64/.chat-rpc.<release-id>.new` | `/www/wwwroot/chat/_output/bin/platforms/linux/amd64/chat-rpc` |
| `/www/wwwroot/chat/config/.chat-rpc-chat.<release-id>.new.yml` | `/www/wwwroot/chat/config/chat-rpc-chat.yml` |

现场二进制和配置都位于同一 ext4 根文件系统。必须从上述目标目录内的临时文件执行 rename，而不是直接把 `/tmp` 文件跨文件系统移动当成原子切换。

6. 校验 `NEW_PID` 的 exe 和哈希等于 stage 二进制，进程参数仍为 `-i 0 -c ...`，30300 的唯一监听者为该 PID。确认没有第二个 RPC 竞争同一端口，再检查 Chat API 10008 仍可访问 RPC。
7. 先做正式鉴权 quota/list/detail/changes 只读验证；只记录 HTTP 状态、errCode、字段 shape、公开 signed URL 的 host/是否 loopback和数字诊断类别，不打印 URL/query/token/用户正文。不能用 30300 正在监听或存储 health=200 代替应用功能验收。

切换期间 Chat RPC 业务请求会短暂不可用，API 的连接重建时间也应计入验收。已有 `pending_archive` job 可能在恢复后的正常维护中继续处理；历史 `archive_failed` 不会因该补丁自动重新排队。

## 6. 批准后的功能验收边界

使用指定测试账号新建自己的小 PNG 和普通文件，经过**设备直接 PUT 公网签名 URL**→complete→create(uploadIDs)→detail→asset-access/prepare→校验下载字节大小与 SHA-256。记录每一步的状态，最终删除本次测试收藏。服务器本机 PUT 成功不能替代这项设备验证；记录删除后的租约/延迟回收遵守已有规则。

另外以本次新建的测试记录验证 single/batch delete 原 UUID 重放及混合冲突结果；必要时用指定测试消息验证归档对象映射和分类日志。现有其他用户收藏、旧失败项和真实聊天发送不属于此自动验收范围，不批量 retry、不发送 SDK 聊天消息。历史失败项待用户明确选择后手动重试。

本组补丁没有数据库迁移。0002 仍有首次并发 miss、写入完成但收据保存失败的预存窗口；0004 只将明确元数据缺失/已确认 NoSuchKey 分类为 20056。设备安装包需是本轮已修复前端版本，否则旧 block ID/旧失效媒体缓存等客户端问题仍可存在。

## 7. 回滚

出现新进程启动失败、重复监听、持续 RPC 不可达、公开 URL 仍为 loopback、确定的签名/来源策略不兼容或核心业务回归时，暂停写入验收并按以下步骤回滚：

1. 重新核对本次 `NEW_PID` 的 exe/哈希，向该新 RPC 发送 TERM，并确认 PID 和监听退出；不停止 Chat API 或其他 OpenIM 服务。
2. 从记录的保护备份目录将旧二进制和原 YAML复制到各自目标目录内的唯一临时文件，恢复原 owner/mode，核对哈希，再同目录 rename 回正式目标。两个文件恢复完成后才启动。
3. 使用第 5 节已核实的同一 env、cwd、`-i 0 -c ...` 和 nohup 方式启动旧 RPC，记录回滚后 PID；确认 30300 监听和 quota/list 的只读业务恢复。
4. 保留新 stage、二进制哈希和安全失败类别用于复查，不覆盖本次备份。归档的补丁源码不作为仍在运行的版本展示。

回滚二进制/配置不会撤销已完成的数据库写入，也不自动还原已删除的测试收藏。0002 保存的回执使用既有 BSON string 字段，没有新增 schema；旧版本仍可能恢复其原有幂等错误表现，不能把二进制回滚当作收据或数据恢复。

本次产物至此仍是**可审阅方案**。下一步可以先准备新的隔离 stage 和保护备份；生产 TERM、rename、启动及受控写入验收需在用户明确批准相应范围后执行。
