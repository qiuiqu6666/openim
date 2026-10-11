# Markdown 消息气泡

`ChatItemView` 的普通文字、@消息和引用正文使用普通聊天字号与字重，不自动识别 Markdown。下载说明、带下划线的昵称、分隔线等不会再被误显示为标题或粗体；正文、换行和原有链接/@点击保持不变。合并转发详情复用同一规则。

明确使用 `MessageType.advancedText` 的高级文字继续保留格式：有实体时由 `ChatFormattedText` 显示，无实体时允许 Markdown。`ChatText` 的独立调用仍通过 `enableMarkdown` 选择启用；应用传入的 `textContentBuilder` 优先，AI 专用回复和自定义消息渲染不受普通文字规则影响。

`chat_message_text_source.dart` 读取 SDK 原始正文并保留换行，@成员沿用现有昵称及全体成员转换；不修改 SDK 消息。会话摘要和引用摘要仍使用单行的 `IMUtils.parseMsg`。Markdown 的复制回调提供源文本，收藏、发送和转发继续使用原协议，不要求新增后端参数。

普通文字直接跳过 Markdown 检测和报表元数据解析。高级文字中的报表仍保留保护：带 `ex.sangongReport` 的三公报表、可识别的开奖/代理报表使用普通聊天文字，避免清单中的 `==================` 被解析成标题。不增加接口请求、不改写原文；分隔线、换行、复制内容及亮暗主题沿用普通消息。

`ChatMarkdownText` 复用既有 `flutter_markdown` 与 GitHub Markdown 扩展，支持标题、粗斜体、删除线、列表、任务列表、引用、代码、表格和链接。代码块软换行，宽表格横向滚动，时间及回执独立放在正文下方；调用者必须提供有限宽度，不可包在 `IntrinsicWidth` 内。字体和前景来自现有气泡样式，装饰来自同一颜色的透明度和共享间距，支持亮暗及系统文字缩放。

`chat_markdown_patterns.dart` 在正文中接入现有链接、邮箱、电话及提及回调，代码区保留字面量；安全链接仅允许 HTTP、HTTPS、mailto、tel。图片复用共享网络图片组件，只加载 HTTP/HTTPS 地址，加载或失败时保留占位。HTML 不作为网页执行。

回归测试及可选高级文字气泡预览在 `test/widgets/chat/markdown/`，另保留普通气泡、菜单、多选和私密消息回归。普通聊天行为对照 `reference-99chat/lib/src/chat.dart` 的 `isSupportMarkdownForTextMessage: false`，按用户“这种不要富文本”的要求关闭普通文字的自动格式识别；复用已有 `ChatText` / `MatchTextView`，无新增组件、协议或状态。

2026-10-11 验证：普通文字/Markdown、气泡布局及 AI 聊天页共 67 项测试通过，4 项可选图片导出测试未启用；相关静态分析通过。覆盖亮暗主题下载说明的普通字重、两条 URL 点击、长按复制、@成员、引用、合并转发、窄屏和大字号；未进行真机验收或重新打包。

2026-10-06 验证：Markdown 31 项、聊天气泡/菜单/多选 57 项及相关 SDK 消息 5 项通过，4 张亮暗/窄屏/双倍字号/RTL 预览已检查，静态分析和 Android debug 构建通过。多选菜单的测试替身补齐了现有通知会话 getter。完整 `sdk_feature_completion_test.dart` 中另有 2 项群管理测试仍查找已不存在的 `PopupMenuButton<int>`，未在本次消息渲染变更中处理；尚未进行真机与 iOS 构建验收。
