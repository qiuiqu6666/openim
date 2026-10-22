# 朋友圈权限前后端联动

2026-10-21 已实现并部署服务端。Flutter 源码已更新，尚未打包安装到手机。

## 行为与协议

`GET /moments/settings` 和现有 PATCH、逐人 PUT/DELETE 响应补充 `blockedViewerIDs`、`hiddenAuthorIDs`、`privacyListsLoaded`、`updatedAt`。读取使用当前登录用户 ID，不允许查询他人名单。名单和设置通过数据库事务形成快照，用户 ID 排序后返回。

`updatedAt` 为服务端 UTC Unix 毫秒，存储在已有设置文档 `updated_at` 中。修改范围、封面及实际改变逐人权限时写入；逐人重复操作不更新时间。旧文档保持 0，不推测历史修改时间，无需批量修改用户数据。

客户端首次打开和重进相关页面从服务端读取，完整空名单可清除缓存；旧服务缺字段仍兼容单项确认。缓存按账号、业务服务器隔离，迟到读取及旧账号写入不能覆盖新状态。保存失败可单独重试本地持久化。

## 源码与复现

- `patch_backend.py <source-root>`：对匹配基线应用数据库、RPC、proto 源码修改；断言防止误套。
- 先保存原 `pkg/protocol/chat/chat.pb.go`，以 protoc 29.0、protoc-gen-go 1.36.4 重新生成。再运行 `preserve_protocol_tags.py <original-pb.go> <generated-pb.go>`，保留既有 JSON 字段输出规则。不能直接使用未经此处理的生成文件，否则会改变其他接口的 null/缺字段行为。
- `moment_privacy_test.go` 放入 `pkg/common/db/database/`；`moment_privacy_http_test.go` 放入 `internal/api/chat/`。
- `owner.patch`、`api.patch` 是发布源码相对部署前源码的审查差异，包含自动生成的描述符。源文件换行有历史差异，复现优先使用上述脚本。
- `deploy.sh` 是本次发布脚本，含精确基线哈希检查、备份、回滚与加密连接探测；后续发布必须重新核对当前基线，不应跳过哈希保护。

线上使用独立安全构建，不能把普通 chat-rpc 二进制覆盖 chat-owner。本次基于实际已部署的 `/home/ubuntu/friend-auto-accept-release-20261021/chat` 与 `api` 合入，保留 TLS、鉴权、worker 管理及最新好友权限改动。

发布源码与构建产物：`/home/ubuntu/moments-privacy-release-20261021`。
发布时间：2026-10-21 18:54:45 +08:00。
备份：`/srv/99chat-production/backups/moments-privacy-20261021-185441`，附 `rollback.sh`。
更新服务：`99chat-sec-chat-owner`、`99chat-sec-chat-api`。普通 RPC 二进制与配置未变动。

## 验证

- 后端数据库、RPC、API、协议、TLS、worker 生命周期、IM API 相关 9 个包测试通过；两个正式安全构建成功。
- 新增测试验证服务端时间、幂等操作、用户隔离、完整/空名单在 protobuf 与 HTTP 序列化后的字段。
- 客户端相关 214 项回归测试通过；覆盖两台独立客户端、账号切换、旧请求竞争、缓存恢复与保存重试、设置页时间显示和现有封面/通知功能。
- 线上服务 active，重启计数为 0；直连及转发 mTLS 探测成功；未登录访问设置接口正常拒绝；发布后检查未发现连接失败或 panic。
- 未使用真实用户账号改动线上权限，未进行双手机真机验收。数据库新增测试使用隔离的测试替身，未对生产用户数据执行测试写入。

本地验证日志：`E:/openim/artifacts/moments-privacy-sync-20261021/`。
