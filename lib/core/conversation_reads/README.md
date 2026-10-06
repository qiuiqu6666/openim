# 会话阅读确认桥接

`ConversationReadRequest.capture` 在实际 SDK 已读请求发送前复制会话 ID、最新消息时间、消息 ID、序号和未读数，完成值只表示该次 SDK 请求是否成功。`IMCallback.conversationReadRequestSubject` 使用同步投递，让会话列表在发送前记录当前账号与清理代际。

聊天可传入实际看过的 SDK 最新消息 `visibleLatestMessage` 和时间线已知的未读数量 `knownUnreadCount`。这只补充本次阅读目标，不修改 SDK 会话或消息数据。会话预览落后于消息回调时，保留原预览的 ID、序号、时间和计数；成功目标可替换这个确定的旧预览，零序号同时间的其他消息仍保持未读。

`ConversationLogic` 订阅请求结果，在 SDK 成功且账号、页面和列表清理代际仍有效时更新匹配目标的列表行。聊天页面退出不取消已发出的 SDK 确认；会话列表关闭、账号切换和清空列表会停止旧确认修改列表。失败不会清除徽标，也不会额外发送 SDK 请求。

`ConversationReadProjection` 保存至多 256 个会话、每个会话 8 个确认目标，以保护晚到的相同目标回调和列表快照。仅在时间、消息 ID、序号都匹配且未读数没有超过请求时的数值时清零；不同消息、更新的序号或时间、增加的未读数保留。旧确认目标回调不能替换列表中更晚或无法判定先后的不同消息。该模块不创建消息、不模拟 SDK 接收状态、不修改语音播放与私密消息燃烧状态。

入口：`conversation_read_request.dart`、`conversation_read_projection.dart`。集成回归位于 `test/pages/conversation/reads/conversation_read_projection_test.dart`，原会话列表手动标为已读回归仍在 `test/pages/conversation/editing/conversation_mark_read_test.dart`。
