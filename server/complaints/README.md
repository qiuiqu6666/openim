# 聊天投诉服务端与后台

后台显示更新：投诉列表与详情均展示投诉人昵称及 ID、被投诉人昵称及 ID、群名称及群 ID。当前页按 ID 批量读取最新资料，用户昵称优先读取 OpenIM 用户目录，业务库资料作为回退；不改写历史投诉身份。已用真实历史群投诉验证双方昵称与群名，并通过投诉及 Admin API race 测试、后台构建。此次仅更新 Admin API，部署与备份记录位于 `/home/ubuntu/complaint-names-20261015/`。

2026-10-15 已更新服务器的 Chat API 与 Admin API。后台入口为「运营管理 → 聊天投诉」。超级管理员可直接查看；其他管理员需要在「后台账号与权限」中授予「聊天投诉」权限。未修改普通意见反馈的数据结构或既有消息处理链路。

本目录保存新增 Go 模块、API 适配、Vue 页面、测试与 `integration.patch`。补丁对应服务器 Chat 仓库的现有路由、依赖初始化、公开用户 ID 转换和后台导航，应用前检查当前源代码差异，不能覆盖其他开发变更。

## 接口

| 接口 | 鉴权 | 内容 |
| --- | --- | --- |
| POST `/complaints/c2c` | 用户 chatToken | 单聊投诉 |
| POST `/complaints/group` | 用户 chatToken | 群聊投诉 |
| POST `/complaints/search` | 管理员及 complaints 权限 | 筛选、分页 |
| POST `/complaints/detail` | 同上 | 说明、截图元数据、处理信息 |
| POST `/complaints/screenshot` | 同上 | 按投诉 ID 和截图序号读取图片二进制 |
| POST `/complaints/update` | 同上 | 更新处理状态、备注、操作人 |

用户接口与管理接口分别运行于 Chat API 与 Admin API，路径通过服务域名区分。接口沿用 `errCode/errMsg/data` 信封和 `operationID`；图片接口成功时返回图片，失败时返回错误信封。

创建使用 multipart：`payload` 为 JSON 字符串，`screenshots` 为重复文件字段。字段包括 `clientRequestID`（UUID）、`reportedUserID`、`groupID`、`reason`、`content`、`clientVersion`。投诉人从鉴权上下文读取，忽略客户端身份字段。原因枚举为 spam、harassment、fraud、pornography、violence、illegal、other。说明选填，最多 2000 字符；截图最多五张，每张最多 10 MiB，复用真实图像格式校验。

MongoDB `chat_complaints` 保存记录，MinIO 保存截图。用户与请求 ID 唯一索引保证重试去重；内容或截图变更冲突时拒绝复用旧键。Redis 提供每用户提交锁及十分钟十次频率限制。群投诉由服务端校验成员身份并绑定当前群主。截图通过同源管理员鉴权接口加载为临时 Blob URL，关闭详情后释放，避免 HTTP 存储地址导致混合内容拦截。

状态：received、processing、resolved、rejected。管理员操作沿用既有操作审计中间件。新错误码：20110 请求内容冲突、20111 频率限制、20112 非群成员、20113 被投诉用户不存在。

上传失败清理本次文件。数据库写入结果不确定时保留已上传文件，避免已保存记录丢失截图；此类极少数未关联文件应在维护时核查，不自动删除可能被已保存投诉引用的证据。

## 验证与部署

服务端执行了 complaints、adminauth、chat/admin API 包的 race 测试；使用独立临时 Mongo 集合与 Redis 键验证保存、幂等、冲突、筛选、处理备注、截图数量和上传失败，结束后清理测试数据。另验证了真实 MinIO 图片写入、读取、清理，以及 complaints 权限与 feedback 权限隔离。后台生产构建和两个 API 二进制构建通过。

现有 `TestSwapHTTPQuoteConfirmAndRecovery` 在修改前后均因 `USD missing must be null` 失败。记录后仅在整包回归时排除这一项，未修改其实现或断言；不能将整套测试描述为无条件全绿。

上线已检查新增路由拒绝未登录访问、两个服务正常运行、管理后台主资源含投诉页面。尚未以真实用户在手机端提交并人工登录后台验收；iOS 未做真机构建。

服务器工作及备份目录：`/srv/99chat-production/changes/complaints-20261015/`；部署前检查源代码漂移并备份被替换文件。部署结果及二进制摘要见本工作区 `artifacts/complaints-20261015/deployment.json`。回滚使用该目录 `backup-20261015-082821/manifest.json` 对应文件恢复并重启 `openimservice-chat-api-0` 与 `openimservice-admin-api-0`，不删除投诉数据。

重跑集成测试：将 `COMPLAINT_TEST_CONFIG` 指向服务器现有 Chat 配置目录后执行 `go test -race ./pkg/complaints`，不将配置内容或凭据写入仓库。
