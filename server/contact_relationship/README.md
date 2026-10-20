# 好友与黑名单规则修正

## 状态与范围

2026-10-20：客户端已修改并通过 132 项相关测试。两份服务端补丁已在用户指定的服务器发布，Chat、好友 RPC、消息 RPC 均已重启并验证运行二进制一致，健康检查返回 200，检查期间无自动重启。

开发补丁基于 `artifacts/security-audit-20261019/source` 快照；实际发布使用服务器当前源码的隔离副本，并在发布前校验源码及旧二进制未变化。`source-manifest.json` 是原始开发基线摘要，实际发布和回滚以服务器备份为准。没有用开发快照覆盖生产源码。

服务器备份、测试日志、构建产物及发布脚本位于 `/srv/99chat-production/friend-blacklist-20261020.447ZCL`。生产源码位于 `/srv/99chat-production/app/source`。本地发布记录见工作区 `artifacts/friend-relationship-20261020/server-publish.log` 和 `server-postcheck.log`。未记录登录密码。

## 行为

- 普通单聊必须同时存在 A→B 和 B→A 两条好友关系。任意一方删除后，双方发送均返回现有非好友错误，客户端显示验证入口。
- 普通单聊不再通过 `friendVerify: false` 放行陌生人；既有管理员和系统通知豁免保持原样。
- 好友申请和同意申请都检查双方黑名单；任一方向拉黑或黑名单查询失败，均不能继续创建申请或建立关系。拒绝申请不受限制。
- 删除仍是单向删除，拉黑不删除好友，解除拉黑不恢复已删除的好友。现有隐藏会话和保留聊天记录行为不变。
- 朋友圈服务端现有 `resolveFeedAuthors`、`resolvePair`、`CanReadMoment` 已要求双向好友且任一方向未拉黑，覆盖动态、详情和媒体授权，本补丁不重复修改。
- 客户端在 SDK 黑名单事件后立即清空朋友圈私有内容、失效旧请求；重新加载时，也按排除黑名单后的好友集合过滤动态作者。详情读取不能回退显示未授权原始响应。点赞、评论和通知沿用已有过滤。
- 客户端所有 `FriendAddRequest.send` 入口、同意申请和聊天验证入口增加本人黑名单检查。对方黑名单仍必须由服务端权威校验。
- Chat 授权、提交及成功/处理中申请的重试均重新检查双向黑名单。IM 返回的 `1302` 错误优先于历史申请存在性，不能转换成成功。
- 申请存在性按本次 `opID` 核对，旧申请、空操作 ID、其他申请对象均不能证明本次成功。
- 客户端收到 `1302` 明确显示“你已被对方拉黑，无法添加好友。”；仅 `applyState: success` 能显示发送成功，空确认和 pending/unknown/failed 均保留申请页。

## 服务端应用与验证

在确认是当前生产版本的隔离源码副本中执行：

```sh
git apply --check /path/to/mutual_friend_blacklist.patch
git apply /path/to/mutual_friend_blacklist.patch
go test ./pkg/relationshippolicy ./internal/rpc/relation ./internal/rpc/msg
go build ./cmd/openim-rpc/openim-rpc-msg ./cmd/openim-rpc/openim-rpc-friend
```

上述 `mutual_friend_blacklist.patch` 应用于 OpenIM Core；`friend_blacklist_error_flow.patch` 应用于 Chat 源码，需运行好友/黑名单相关测试并构建 `./cmd/rpc/chat-rpc`。

本次部署对象为 `openimservice-openim-rpc-msg-0`、`openimservice-openim-rpc-friend-0`、`99chat-sec-chat-rpc`。后续发布仍须沿用实际服务流程并备份旧二进制；补丁上下文不匹配时应合并当前源码，不能强制覆盖。

## 已验证与待验证

- 132 项客户端定向测试通过，覆盖好友申请来源、黑名单、账号切换、朋友圈撤权、缓存、详情、直达验证及申请流程，以及授权/提交端点的 HTTP 错误映射、准确文案、不误报成功和解除拉黑后的重试。
- 定向 Dart 静态检查无错误；公共 API 文件有一个既有冗余 import 提示。
- Android debug APK 构建成功；消息 RPC、好友 RPC 的 Linux amd64 二进制交叉构建成功。
- Go 策略测试覆盖双向好友关系矩阵、双向黑名单矩阵、查询失败；好友 RPC 测试验证拉黑时申请和同意均不会继续写入关系；消息 RPC 现有测试通过。
- 补丁对基线执行 `git apply --check` 成功。
- 两份补丁对服务器当前源码检查成功，服务器定向测试及三个服务构建通过，已发布。
- 自动化测试使用隔离数据与测试 HTTP 服务；没有使用真实用户账号发申请。尚未安装新客户端及完成双账号真机验收，旧客户端不保证显示新增精确文案。需安装本次 APK 后验证完整手机交互，包括朋友圈相册、详情和图片链接。
