# 引用消息

参照 99chat `third_party/tencent_cloud_chat_uikit/lib/ui/widgets/tim_uikit_reply_quote_card.dart` 的输入预览和气泡卡片，并对齐用户提供的三张截图。

- `chat_quote_content.dart`：两行发送者与摘要，复用 `IMUtils.parseMsg` 的消息解析；红包补充祝福，名片沿用昵称摘要。完整内容通过长按提示查看，不修改原消息。
- `chat_quote_thumbnail.dart`：图片/视频的 40dp 缩略图，复用 `ImageUtil` 的缓存、对象地址兼容及解码尺寸限制；本地失效回退远端，失败保留固定占位，不在 build 中同步检查文件。过期消息不加载缩略图。
- `chat_quote_card.dart` / `chat_quote_tokens.dart`：回复正文上方的圆角引用卡片、左侧竖线，按实际收发气泡底色解析明暗样式。

输入栏仍使用 `ChatComposerContextPreview`，与引用卡片共用内容展示。关闭目标为 48dp，图标为 18dp，焦点、草稿及 SDK 引用发送由原控制器持有。原有文字及定向消息参数保持兼容。

相关验证位于 `test/widgets/chat/quote/`、`test/widgets/chat/markdown/` 与输入/发送控制器的原有测试。图形预览复用 Markdown 测试的字体与 PNG 导出工具；不依赖真实用户或网络。
