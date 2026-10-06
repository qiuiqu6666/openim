# 会话列表空态

`ConversationEmptyState` 负责主导航消息、群聊及会话分组的空态展示。
它复用 `AppTokens` 的字号、间距和主题颜色，使用可滚动布局以适配横屏与大字体，保留外层下拉刷新。

`assets/99chat_empty.png` 来自用户提供的 `ChatGPT Image 2026年9月21日 01_50_15.webp`，经 ImageGen 移除白色背景，保留 99CHAT 吉祥物及插图元素。图片为 1445×1089 的透明 PNG；原始输入文件不被修改。

主列表仅在会话读取成功、SDK 连接正常且同步完成、当前范围为空且没有需要展示的归档入口时显示空态。加载状态与读取失败由 `ConversationLogic.canShowEmptyFeed` 控制。分组为空时使用分组专属文字。

验证入口：`test/pages/conversation/empty/conversation_empty_state_test.dart`，以及会话刷新生命周期和会话分组页面的回归测试。可通过 `CONVERSATION_EMPTY_PREVIEW` 指定亮暗主题预览 PNG 输出路径。
