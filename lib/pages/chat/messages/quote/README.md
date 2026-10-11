# 引用消息定位

`ChatQuoteNavigation` 负责点击引用卡片后的原消息校验和重复点击保护。公共 `ChatItemView` 通过 `onTapQuotedMessage` 上抛引用，普通引用和带 @ 的回复使用同一入口，不区分发送方。

应用层复用 `ChatMediaMessageLocator.findStoredMessage`，按当前会话和原消息 ID 查询真实 SDK 记录，避免把已删除消息的引用快照重新插入历史。定位与高亮复用 `ChatLogic.focusSearchMessage`，历史窗口、滚动及返回最新消息仍归原有控制器管理。账号或路由失效后丢弃返回；找不到、已失效或定位失败时提示用户。

测试：`test/pages/chat/messages/quote/chat_quote_navigation_test.dart`、`test/widgets/chat/quote/chat_quote_preview_test.dart`，以及已有历史窗口和消息高亮测试。
