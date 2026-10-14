# 已读行刷新

`ChatMessageReadUpdates` 仅保留已挂载气泡的消息 ID 与监听回调。
回执通过 `ChatLogic` 转发有变化的 ID，`ChatMessageTile` 使用 ListenableBuilder
刷新对应行，其他消息及整个列表的索引、时间标记和历史快照不因此重新构建。

同一消息可以有多个显示位置；最后一个监听移除即释放该 ID，账号或路由关闭
时清空。历史再次加载从 SDK 消息与回执确认缓存恢复状态，不在此重复缓存消息。
测试位于 `test/pages/chat/messages/refresh/`，回执合并与迟到结果另见 `receipts/`。
