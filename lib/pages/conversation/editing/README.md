# 会话编辑与批量已读

删除、归档继续由页面的 `ConversationEditController` 管理。批量已读由账号级 `ConversationLogic` 持有；退出编辑不取消任务，关闭账号会话则取消 HTTP 并停止后续请求。

私聊／群聊无选择时调用 `markAllConversationsRead`，由服务端枚举完整范围（包含归档和客户端未加载会话）。有选择时 `markSelectedConversationsRead` 直接提交捕获的 ID。指定分组／归档页仍通过 `markReadScope` 完整读取本地 SDK 会话并按原组织规则筛选 ID；不依赖首屏 400 条。

`batch_read/` 独立维护 HTTP API、分批流程和响应投影：先准备完整固定水位，每批 100 个会话提交服务端。部分失败仅按原水位重试一次；超时不重新抓取水位或退回逐会话 SDK 已读。单会话侧滑已读沿用原 SDK。原 `conversation_read_batch.dart` 保留给旧算法回归和界面测试假实现，不再作为生产批量路径。

编辑栏复用准备状态及已处理／总数（已处理包含失败项）。成功响应只清除本次捕获且被服务端水位覆盖的预览；新消息及增大的未读数不清零。SDK 已读回执负责本地持久化、其他设备与总未读同步；结束后重新读取 SDK 会话核对。旧批次完成不会关闭后来重新进入的编辑会话。主控制器仅保留会话生命周期和既有投影/刷新适配，独立批量职责位于子目录。

回归：`test/pages/conversation/editing/batch_read/` 覆盖 3000 条只提交 30 批、固定快照、去重、部分失败、超时、账号切换、IM token、响应校验与新消息保护；`conversation_edit_host_test.dart` 覆盖私聊/群聊范围、退出编辑继续及重复操作保护。服务端源码、协议与部署记录见 `server/batch_read/README.md`。
