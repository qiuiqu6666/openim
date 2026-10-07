# 联系人列表空状态

“我的群聊”的创建/加入分页、“新的朋友”、“群通知”和选择联系人中的群列表共用 `contactListPlaceholder`。确认请求成功且列表为空后显示插画；首屏等待期间显示加载，失败显示中文/英文重试提示。数据仍来自各自原有 OpenIM SDK 请求和 Rx 列表，保留群分页、刷新、好友申请事件订阅和联系人选择行为。

插画通过 `widgets/empty_state/IllustratedEmptyState` 与通话记录复用；参考 99chat `group_list.dart`、`newContact.dart` 和 `widgets/app_empty_state.dart`。样式支持亮暗主题，空状态自身可滚动，群列表由现有 SmartRefresher 接管滚动。
