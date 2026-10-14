# 服务端群通知（2026-10-14）

本目录保留已上线的 OpenIM API 扩展源码、集成测试和路由补丁。群通知的显示、删除、清空及已读状态按认证账号存放在服务端；不删除 `group_request`、不代替审批、不改变群成员关系。其他管理员不受影响。

## 接口

所有接口均为 POST，沿用 OpenIM API 的 `token`、`operationID` 请求头及 `errCode/errMsg/data` 响应。账号仅取鉴权中间件，不接受调用方指定通知所有者。

| 路径 | 请求 | 返回 / 作用 |
| --- | --- | --- |
| `/group/notices/list` | `limit`（默认 20，上限 100）、`cursor` | `items`、`nextCursor`、`snapshotTime`、`revision`、`reset` |
| `/group/notices/detail` | `groupID`、`userID`、`reqTime` | 单条申请详情，供后续页的审核页面定点刷新 |
| `/group/notices/state` | `includeUnread`（默认 true） | 版本、清空/已读边界；需要时计算 `unreadCount` |
| `/group/notices/clear` | 列表返回的 `through: snapshotTime` | 单次更新账号清空边界，不遍历通知 |
| `/group/notices/delete` | `groupID`、`userID`、`reqTime`（毫秒） | 隐藏该账号的单条申请记录 |
| `/group/notices/read` | `through: snapshotTime` | 将该快照及更早通知标记已读，不审批申请 |
| `/group/notices/migrate` | `through`、`items`（每批最多 100） | 幂等迁移旧客户端本地清理记录 |

`list` 查询当前用户提交的申请以及当前管理群的申请。采用 `req_time, group_id, user_id` 倒序游标，服务端先过滤清空边界和删除标记，再取一页，不计算列表总数。群名、头像及人员公开昵称只补查当前页。已打开的审核详情不在首批时，额外定点查询这一条，保留后续页申请的审核状态更新。索引在 API 启动时幂等创建，定义见 `indexes.go`。

游标绑定账号、快照时间和可见性版本。其他设备删除/清空后，旧游标返回 `reset: true`，客户端重新取首批。清空使用列表快照时间，防止清空操作期间后来新增的申请被一起隐藏；时间边界采用服务端记录的毫秒时间。清空状态和已读状态使用 `$max`，重试旧操作不会倒退边界。

`group_notice_state` 保存每个账号的边界与版本，`group_notice_dismissal` 保存按账号、群、申请人、申请时间识别的单条隐藏记录。MongoDB 持久化，不依赖 API 进程内存。单条删除与版本通知为可重试的两个写入，失败不得当作成功；重新进入页面始终以服务器查询为准。

## 客户端

Flutter 模块：`lib/pages/contacts/group_requests/data/`。刷新只读取首批 20 条，上拉使用服务端游标。首次接入将旧本地清空/删除记录分批迁移，成功后保存迁移标记；失败允许重试，不回退到本地删除。

页面打开、恢复前台及 SDK 申请变更时刷新；前台页面每 15 秒检查可见性版本。首页每 30 秒校准群通知未读数，后台停止检查。进入页面成功加载后，标记当前快照范围已读。同步不是 WebSocket 即时广播；旧客户端仍走旧接口，需要升级客户端才能完整参与同步。Android / iOS 共用此 Dart 实现，Windows React 客户端尚未接入这组新接口。

## 安装和验证

将 `internal/api/groupnotices` 复制到目标 OpenIM 服务端同一路径，再应用 `router.patch`。该补丁基于本服务器已有 MongoDB `memberDB` 的 API 路由实现；不同版本应先核对路由上下文。

```sh
git apply --check /path/to/router.patch
git apply /path/to/router.patch
gofmt -w internal/api/groupnotices internal/api/router.go
go test ./internal/api/...
NOTICE_TEST_MONGO=mongodb://127.0.0.1:27088 go test ./internal/api/groupnotices -v -count=1
go build -o openim-api ./cmd/openim-api
```

集成测试只使用随机命名的 `notice_test_*` 数据库并在结束时清理，不能把测试地址指向生产 MongoDB。覆盖 2 万条记录、相同时间分页、账号隔离、删除、旧游标、全量清空、新申请保留、已读同步、重复迁移、取消管理员权限以及未认证请求。

## 本次发布记录

- 服务端：`124.156.151.7`，源码 `/srv/99chat-production/app/source/open-im-server/internal/api/groupnotices`。
- 仅更新并重启 `openimservice-openim-api-0.service`，服务已恢复正常；实际鉴权调用 list/state 均成功。未操作任何真实账号的清空或删除。
- 备份：`/srv/99chat-production/backups/group-notices-20261014-170734`，包含原二进制及原路由文件。回滚时替换二者并重启 API 服务；新增集合和索引可保留。
- 发布二进制 SHA-256：`8a7e85a42a1c6eb25bd7d96d45e02c070427457f04cb9c72ea3b1c25c3353035`。
- 隔离 MongoDB 测试：2 万条首批约 40ms，清空约 0.3ms；仅代表服务器本机测试，不包含公网延迟。
- Flutter 群通知、申请记录及首页申请红点相关 79 项测试通过，群通知模块静态检查通过。扩大到整个首页目录时，4 项既有页面测试因 IM 替身缺少 `currentConnectionStatus` 失败；这些测试使用 `implements HomeLogic` 替身，不经过本次实际 HomeLogic 实现，未改动该无关测试。
- 尚未进行两台真实设备联调或发布新版客户端安装包。
