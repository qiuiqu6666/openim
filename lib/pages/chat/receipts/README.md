# 聊天回执

`ChatReadReceipts` 持有可视消息 ID、在途消息 ID、刷新计时器和 `ConversationReadCoordinator`。`ChatLogic.onChatViewportChanged` 接入公共 `ChatListViewport` 的真实绘制结果，只有当前路由、前台且最新消息确实可见时才确认会话阅读；历史窗口未连接最新记录时不清会话未读。气泡自身的 `FocusDetector` 不再发送自动阅读请求。

会话“已查看”与语音播放、私密内容阅读分开。查看语音、通话或本地 `isRead` 已为真的消息仍可清会话徽标，但不会设置语音已播放或启动私密语音燃烧。私密文字等内容仍通过消息 ID 回执；显式播放与转文字沿用 `markRead`。

`canReadConversation` 是可选的会话阅读门控，默认允许。聊天接入实时气泡入场时，直到所有入场行完整绘制才允许全会话已读，覆盖可见判断、排队请求、显式普通阅读和退出清未读，防止另一条已显示的最新消息提前消费尚在滑入的消息；已经完整可见的私密消息仍可按 ID 确认。

请求按序号、最新消息 ID 和新观察到的未读快照合并；零序号新消息不会继承上一条消息的确认。实际发送时再次核对路由与可见目标，取消的请求不推进已读水位。SDK 回调宣布了尚未进入时间线的新消息时，也不会清零。

发送前向 `IMCallback.conversationReadRequestSubject` 同步发布 [阅读目标](../../../core/conversation_reads/README.md)，由会话列表在 SDK 成功后更新对应行。会话资料晚到时，目标使用实际看过的 SDK 消息及已知消息数量，并保留原会话预览的身份，避免误用上一条预览或误清同时间的新消息。

退出前仅对最后确实看过的最新目标立即发出最终请求，已经在 SDK 发送中的相同目标不重复。页面关闭后停止排队请求和消息状态回写；已经发出的 SDK 确认可继续交给同账号会话列表，账号或令牌变化则失效。

测试：`test/pages/chat/receipts/`、`test/integration/chat/chat_conversation_read_test.dart`。修复验收见 [返回列表未读修复](../../../../docs/chat-unread-return-fix-2026-10-05.md)。
