# 会话删除边界

`ConversationDeletionGuard` 只拥有单个会话删除请求的在途边界和成功后的隐藏范围，不调用 SDK、不持有页面控制器。删除期间的 SDK 事件和列表快照扩大已观测的消息/草稿边界；失败时返回最新事件供页面恢复。

删除成功后，旧快照和事件重放不能把会话加回来。更晚的消息可恢复会话；同时间消息需更高 SDK seq；新草稿需非空且 `draftTextTime` 超过已删除范围。清除列表、退出和控制器关闭会清除此边界。会话读取请求另由 `ConversationLogic` 的请求代次控制，合并读取期间的有效事件后一次发布。

在途请求保留最新事件用于失败恢复；删除成功后只保留时间、草稿时间和 seq，不持有已删除会话的消息正文或媒体元数据。

回归位于 `test/pages/conversation/deletion`；真实 MethodChannel 的刷新/删除交错回归位于 `test/pages/conversation/conversation_refresh_lifecycle_test.dart`。
