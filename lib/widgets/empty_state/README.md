# 共用空状态插画

`IllustratedEmptyState` 从设置组件中的 `SettingsEmptyState` 提取，设置和通话记录保留旧名称兼容入口，联系人列表直接使用此公共组件。复用 `openim_common/assets/images/empty_99chat.webp`、主题次级文字颜色以及 99chat `AppEmptyState` 的布局，不增加资源或数据请求。

组件仅负责插画、提示和可选重试按钮。滚动、加载和错误状态由页面管理；联系人模块的 `empty/contact_list_placeholder.dart` 返回带 `SliverFillRemaining` 的滚动视图，兼容群列表下拉刷新、小屏幕和大字号。
