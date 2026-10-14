# 转发确认弹窗

按用户确认的微信风格设计实现；参考 99chat 的
`third_party/tencent_cloud_chat_uikit/lib/ui/widgets/forward_confirm_bottom_sheet.dart`
中收件人和分类预览的组织方式，保留本项目的居中确认与多人选择流程。

- `forward_hint_dialog.dart`：收件人、可滚动内容、取消和发送。继续由 `widgets/dialog.dart` 导出，兼容原有调用。
- `forward_preview_data.dart`：SDK 消息到只读显示快照，覆盖文本、@、高级文本、引用、图片、视频、语音、文件、名片、位置、表情和聊天记录，以及逐条/合并转发。
- `forward_message_preview.dart`：分类展示，复用 AvatarView、ImageUtil、StickerImageData 和主题颜色。图片优先尝试已有本地文件，失败回退远程缩略图；视频仅加载封面。
- `forward_dialog_tokens.dart`：本弹窗的尺寸和发送色。

聊天转发控制器通过 AppNavigator 的 `forwardPreview` 参数把快照传到联系人选择器。
原 `ex` 摘要仍保留，收藏、应用分享等未传结构化预览的入口显示文本摘要。
本模块不持有 SDK listener，不播放音视频，不改变发送策略或消息数据；确认之后仍执行原有权限、过期、账号和发送结果校验。

多人收件人可滚动，大字号自动减少每行人数；底部操作保持可见。
Light/Dark 使用 AppTokens。位置消息没有地图图片字段，显示真实描述和坐标，不生成虚构地图。

验证：`test/widgets/forward/forward_hint_dialog_test.dart`，聊天 forwarding 控制器测试，以及 recent_conversation_selection/search 测试。
设置 `FORWARD_PREVIEW_DIR` 可输出 Flutter 实际渲染预览；预览中的缺失媒体展示占位状态。
