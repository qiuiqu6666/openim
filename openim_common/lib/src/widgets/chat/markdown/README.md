# Markdown 消息气泡

`ChatItemView` 的文字、@消息、引用正文及无实体的高级文字默认启用 Markdown；`ChatText` 的独立调用通过 `enableMarkdown` 选择启用。纯文本继续使用原有匹配和自然气泡宽度，带格式实体的高级文字继续由 `ChatFormattedText` 显示，应用传入的 `textContentBuilder` 优先。

`chat_message_text_source.dart` 读取 SDK 原始正文并保留换行，@成员沿用现有昵称及全体成员转换；不修改 SDK 消息。会话摘要和引用摘要仍使用单行的 `IMUtils.parseMsg`。Markdown 的复制回调提供源文本，收藏、发送和转发继续使用原协议，不要求新增后端参数。

`ChatMarkdownText` 复用既有 `flutter_markdown` 与 GitHub Markdown 扩展，支持标题、粗斜体、删除线、列表、任务列表、引用、代码、表格和链接。代码块软换行，宽表格横向滚动，时间及回执独立放在正文下方；调用者必须提供有限宽度，不可包在 `IntrinsicWidth` 内。字体和前景来自现有气泡样式，装饰来自同一颜色的透明度和共享间距，支持亮暗及系统文字缩放。

`chat_markdown_patterns.dart` 在正文中接入现有链接、邮箱、电话及提及回调，代码区保留字面量；安全链接仅允许 HTTP、HTTPS、mailto、tel。图片复用共享网络图片组件，只加载 HTTP/HTTPS 地址，加载或失败时保留占位。HTML 不作为网页执行。

回归测试及可选真实气泡预览在 `test/widgets/chat/markdown/`，另保留普通气泡、菜单、多选和私密消息回归。99chat 当前普通聊天配置关闭 Markdown，本功能按用户新增要求实现，复用本项目 AI 消息已经使用的解析依赖。

2026-10-06 验证：Markdown 31 项、聊天气泡/菜单/多选 57 项及相关 SDK 消息 5 项通过，4 张亮暗/窄屏/双倍字号/RTL 预览已检查，静态分析和 Android debug 构建通过。多选菜单的测试替身补齐了现有通知会话 getter。完整 `sdk_feature_completion_test.dart` 中另有 2 项群管理测试仍查找已不存在的 `PopupMenuButton<int>`，未在本次消息渲染变更中处理；尚未进行真机与 iOS 构建验收。
