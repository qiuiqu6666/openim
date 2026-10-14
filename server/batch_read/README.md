# 服务端批量已读

2026-10-14 接入当前 OpenIM 服务端。`overlay/` 保存部署过的新增源码与测试；合入服务端根目录后按 `router.patch` 注册路由。保持原来的认证中间件，不能加入白名单。

## 接口

两条 POST 路由都使用 IM token，从认证上下文获取用户，忽略请求正文中的 `userID`。

- `/msg/prepare_batch_read`：`scope` 为 `single`、`group`、`all`、`selected`。指定会话使用 `conversationIDs`（每次最多 1000）。返回 `targets: [{conversationID, hasReadSeq}]` 与 `batchSize: 100`。空的 selected 返回空集合，不能扩大为全部。
- `/msg/batch_mark_conversations_as_read`：提交准备阶段的 `targets`（每次最多 100，禁止重复 ID）。逐条返回同一 ID、水位和 `success`。未确认项可按原水位重试。

全部单聊／群聊从服务端账号会话取范围，包含归档与客户端尚未加载的会话。通知会话不在此功能范围。分组和归档页由客户端现有组织状态决定 ID；多选直接传选中 ID。

## 一致性与性能

先固定所有目标水位，再分批写入。后续新消息高于水位，不会被本批操作读取。再次校验用户对会话的权限和可见消息上限。并发读取不降低已有已读水位。

每个请求最多 8 个 worker，API 进程共用最多 16 个读 RPC 名额，请求期限 20 秒。单聊使用现有 `MarkMsgsAsRead` 每 2000 个明确序号推进一次，即使历史删除导致可见起点很高，也不展开之前的序号空洞。群聊复用 `MarkConversationAsRead`，两条路径都保留消息已读、回执、Webhook 与多端通知。服务端仍须处理各会话；本改动减少客户端逐会话网络往返，不声称单次数据库写入或固定完成时间。

客户端每批 100 个会话。3000 个未读会话正常需 1 次准备 + 30 次批量提交（自动部分失败重试另计）。HTTP 超时不重新获取水位、不退回逐会话清零，避免将新消息也清掉。账号退出取消后续提交；已完成的服务端写入不会回滚。

## 验证与部署

服务端：`go test -race ./internal/api/batchread ./internal/api`；`go build ./cmd/openim-api`。

覆盖：3000 个会话筛选、空选择、未登录、正文伪造用户、权限错误、重复与越界目标、并发限制、单聊回执分块、部分失败、取消、幂等重试和固定水位。

已部署至 `124.156.151.7` 的 `/srv/99chat-production/app/source/open-im-server`，仅更新并重启 `openimservice-openim-api-0.service`。保留旧二进制和原路由备份：`/home/ubuntu/batch-read-backup-20261014-180138`。部署时核对源文件与快照，防止覆盖同期修改。认证空选择、非法空批次和匿名拒绝检查通过；检查不更改真实用户的已读状态。

真实 Android/iOS 双设备回执与大账号耗时仍需登录设备验收。无需为本次功能更换原生 SDK；客户端通过现有 SDK 的已读通知落库和更新总未读数。

单聊历史空洞优化已重新基于线上最新源码构建并部署，保留同期群通知修改。该次更新前备份为 `/home/ubuntu/batch-read-backup-20261014-180737`，相同认证检查再次通过。

客户端相关回归 81 项通过、1 项原有跳过；新增模块无静态错误或警告，主控制器保留 5 项既有提示。Android debug 包构建成功：`E:/openim/release-artifacts/99chat-batch-read-20261014-debug.apk`。实际手机需要安装包含本次接入的新客户端才会使用批量接口。
