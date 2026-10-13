# 会话阅读确认桥接

`ConversationReadRequest.capture` 在实际 SDK 已读请求发送前复制会话 ID、最新消息时间、消息 ID、序号和未读数，完成值只表示该次 SDK 请求是否成功。`IMCallback.conversationReadRequestSubject` 使用同步投递，让会话列表在发送前记录当前账号与清理代际。

聊天可传入实际看过的 SDK 最新消息 `visibleLatestMessage` 和时间线已知的未读数量 `knownUnreadCount`。这只补充本次阅读目标，不修改 SDK 会话或消息数据。会话预览落后于消息回调时，保留原预览的 ID、序号、时间和计数；成功目标可替换这个确定的旧预览，零序号同时间的其他消息仍保持未读。

`ConversationLogic` 订阅请求结果，在 SDK 成功且账号、页面和列表清理代际仍有效时更新匹配目标的列表行。聊天页面退出不取消已发出的 SDK 确认；会话列表关闭、账号切换和清空列表会停止旧确认修改列表。请求还捕获用户、IM/chat token 与服务器归属，防止同账号重新登录后执行旧补偿。

SDK 全会话已读失败时，`ConversationReadRecovery` 只补偿发送前捕获、实际可见且有正序号的普通消息 ID；不加入后来的消息、私密/阅后即焚消息或未知序号消息。每批最多 100 个 ID，失败后间隔 750ms 再试一次；每次检查账号和列表代际。它复用已有 SDK 逐 ID 已读接口，不重发没有截止边界的全会话已读。补偿完成或失败后定向读取真实 SDK 剩余未读数，不把部分成功当作全会话已读。未捕获的旧消息或持续网络失败仍可能保留真实未读，重新进入后由正常阅读流程处理。

`ConversationReadProjection` 保存至多 256 个会话、每个会话 8 个确认目标，以保护晚到的相同目标回调和列表快照。仅在时间、消息 ID、序号都匹配且未读数没有超过请求时的数值时清零；不同消息、更新的序号或时间、增加的未读数保留。旧确认目标回调不能替换列表中更晚或无法判定先后的不同消息。该模块不创建消息、不模拟 SDK 接收状态、不修改语音播放与私密消息燃烧状态。

未读校准从 SDK 重新读取会话时，可对读取期间没有实时变更的行传入 `project(..., authoritativeUnread: true)`。只有 SDK 返回未读数为零且最新消息时间、ID、序号与当前行完全相同，才允许清除超过旧确认计数的未读；不同目标仍保留。普通回调、普通快照和读取期间已有实时变更的行保持默认 `false`，避免晚到的旧零值覆盖新消息。账号和列表代际校验、读取期间变更跟踪由调用方负责；该参数本身不证明事件来自另一设备。

入口：`conversation_read_request.dart`、`conversation_read_projection.dart`。集成回归位于 `test/pages/conversation/reads/conversation_read_projection_test.dart`，原会话列表手动标为已读回归仍在 `test/pages/conversation/editing/conversation_mark_read_test.dart`。

2026-10-13：定向查询经 `ConversationLatestSync` 的读取期间变更屏障后也具备零值校准权限。普通回调的同目标零值被保护逻辑拒绝时，每个受保护目标/计数只发起一次定向校准，避免查询回调自激循环；不依赖总未读数发生变化。成功确认后仍有残留计数也会定向校准。历史与实时排序把同时间的未知序号放在已知序号之后，并保留未知序号之间的到达顺序，避免已读目标退回旧消息。

产品边界参考 `reference-99chat/lib/src/services/chat_entry_read_service.dart` 的账号隔离和捕获阅读截止边界；当前实现仍使用 OpenIM，不移植腾讯 SDK 的时间/序号清理接口。补偿测试位于 `test/core/conversation_reads/`、`test/pages/chat/receipts/chat_read_recovery_boundary_test.dart`，完整返回场景位于 `test/integration/chat/chat_conversation_read_test.dart`。
