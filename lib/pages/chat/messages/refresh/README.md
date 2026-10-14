# 消息状态行刷新

`ChatMessageReadUpdates` 仅保留已挂载气泡的消息 ID 与监听回调。
已读回执和发送状态通过 `ChatLogic` 转发有变化的 ID，`ChatMessageTile` 使用 ListenableBuilder
刷新对应行，其他消息及整个列表的索引、时间标记和历史快照不因此重新构建。

同一消息可以有多个显示位置；最后一个监听移除即释放该 ID，账号或路由关闭
时清空。历史再次加载从 SDK 消息与回执确认缓存恢复状态，不在此重复缓存消息。
测试位于 `test/pages/chat/messages/refresh/`，回执合并与迟到结果另见 `receipts/`。

类名及页面接口保留原 `ReadUpdates` 名称以兼容已有调用方；通知器不保存消息数据，发送阶段也可复用。发送时间被 SDK 修正、消息插入或窗口裁剪等结构变化仍由时间线刷新处理。
