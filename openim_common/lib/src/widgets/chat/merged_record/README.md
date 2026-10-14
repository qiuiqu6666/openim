# 聊天记录卡片

`ChatMergedRecordCard` 实现用户确认的发送/接收、Light/Dark 卡片设计：两行标题、三条摘要、分隔线与“聊天记录”入口。
对照 99chat 的 `tim_uikit_merger_message_elem.dart`，复用当前 SDK 合并记录字段及公共主题 token。

`ChatStructuredMessage` 保留记录导航、过期检查与八层嵌套限制；`ChatItemView` 通过现有 standaloneCard 和 childWithStatusBuilder 接口传入发送状态。
卡片自身没有 SDK 调用或状态订阅。发送时间在卡片内部，接收时间在下方；重试、已读和菜单仍由消息容器管理。
独立文件避免继续把卡片布局堆入通用结构化消息组件。普通文本、位置和其他卡片保持原有呈现。

测试：`test/widgets/chat/merged_record/chat_merged_record_card_test.dart`。
设置 `CHAT_MARKDOWN_PREVIEW_DIR` 可输出实际 Flutter 渲染，测试覆盖长标题、320px/200% 字号、亮暗主题、接收/发送和记录导航返回。
