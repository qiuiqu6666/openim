# 频道对话

对照 `reference-99chat/lib/src/chat.dart` 的频道配置与
`widgets/channel_notification_toggle_bar.dart`：隐藏发送者头像、昵称、群公告和群专用功能；
频道主/管理员保留现有发布输入区，订阅者显示通知开关。

消息继续使用 ChatMessageList / ChatItemView，频道判断来自群 ex 标记。
通知栏仅负责交互与订阅生命周期，通过现有 ConversationLogic.setNotDisturb 保存，
读取真实 recvMsgOpt，不在请求成功前乐观改变通知状态。
会话更新只接受当前 conversationID；卸载后取消监听，异步完成不更新已卸载组件。
亮暗主题、底部安全区域和放大字体沿用公共组件与主题。

验证：test/pages/channels/channel_conversation_test.dart、channel_publish_permission_test.dart，
以及现有 chat_bubble_99chat_test.dart。
