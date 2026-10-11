# 会话批量编辑

主消息列表与归档列表共用本目录的编辑状态、选中控件和操作栏；继续调用现有 OpenIM 已读接口、归档仓储及会话删除逻辑。

- `conversation_edit_controller.dart`：稳定选中范围、操作互斥与批次生命周期。处理中不允许重复操作或更改选中项；“完成”立即退出编辑并停止尚未开始的批次项。
- `conversation_edit_actions.dart`：页面与账号有效性检查、现有业务调用及错误提示。
- `conversation_edit_action_bar.dart`、`conversation_selection_indicator.dart`：复用当前亮暗主题与 99chat 编辑样式。

退出编辑或销毁页面会释放批次等待。已经发出的 SDK／网络请求可能完成；取消不会撤销已经成功的已读、归档或删除操作。每个批次具有独立身份，迟到结果不会关闭新编辑状态、清除新选择或解除新任务的互斥。

`ConversationLogic.markConversationRead` 对 SDK 请求设置 10 秒超时。只有成功确认后才应用原有已读投影；超时显示现有本地化重试提示，迟到确认不会再次更新该请求的投影。新消息、账号切换与清空列表继续由原有读取快照和生命周期保护处理。

回归入口：`test/pages/conversation/editing/`、`conversation_edit_host_test.dart` 与 `archive/archived_conversation_page_test.dart`，覆盖挂起请求期间退出、旧结果隔离、已读超时及两种主题下的导航恢复。
