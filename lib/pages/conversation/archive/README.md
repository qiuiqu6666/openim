# 归档会话

样式来源为本地 `reference-99chat` 的 `d7c3c65`：
`lib/src/conversation.dart` 中 `ArchivedConversationPage`，以及 UIKit 中的
`TIMUIKitConversationItem`。归档行采用自然高度、无分隔线；深色普通行使用
surface，导航和页面使用 background。

`ArchivedConversationPage` 持有滚动、滑动和选择状态。它复用会话模块的
`ConversationFeedRow`、编辑按钮、选择控制器和编辑底栏；页面销毁时释放这些
状态，不销毁共享 `ConversationLogic`。主列表的归档入口通过根导航器全屏打开此
页面，覆盖首页底部主导航，编辑时显示页面自己的批量操作栏。旧的
`ConversationPage(archivedOnly: true)` 调用保留为兼容入口。

滑动控制器由共享 `ConversationSlideScope` 按挂载行持有和销毁，页面只登记
当前挂载的行以关闭面板。取消归档或列表顺序变化后不重用旧行控制器，避免当前
flutter_slidable 3.1.2 的旧通知监听访问已销毁的上下文。

列表数据取自当前 `ConversationLogic.list` 的 OpenIM SDK 会话，按单聊/群聊和
`states.archived` 筛选。进入页面和下拉刷新调用原有 `refreshOrganizer`；已有
会话保留显示，空列表初次加载显示转圈，接口失败显示重试。

取消归档调用原有 Chat `PUT /chat/conversation-states/{conversationID}`，保留
folderID 和版本控制，成功后归档页与主列表通过同一状态立即更新。已读、置顶、
删除使用现有 OpenIM SDK 操作；删除会话不清掉服务端归档标记。批量已读只处理
当前归档范围，其他批量操作只处理勾选项，已读或取消归档失败保留勾选以便重试。

参考仓库的腾讯 SDK 分页存储和会话预览不迁入此模块；当前列表沿用 OpenIM 的
实时加载，长按使用与“更多”相同的置顶/取消归档菜单。
