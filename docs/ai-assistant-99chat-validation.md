# AI 助手界面还原验证（2026-10-05）

本文件记录先前的视觉预览阶段。当前生产入口已改为 OpenIM 独立单聊，
接入及最新验证见 [AI 助理 SDK 对话](ai-assistant-openim-validation.md)。

参考本地 99chat `d7c3c655b20dd06458d1882b114e68c1c24133e3` 的实际
`lib/src/pages/ai_assistant/ai_assistant_page.dart`，未凭截图猜测交互。
四页引导、AI 头像、空状态和欢迎图共 7 个素材的 SHA256 与参考一致。

入口已接到「我的 → 热门生态 → AI助手」。实现了原版头部、对话内搜索、
背景、空状态、首次引导、工具胶囊、好友/群聊名片动作菜单、系统图片/文件
选择、附件草稿、输入区、消息样式及清空/复制菜单。支持亮暗主题。

用户明确“暂无服务，先完成界面还原”。生产 AI 请求默认关闭，发送保留
输入和附件并提示服务尚未接入，不生成示例回复。消息/结果卡片的展示使用
测试夹具验证，真实 AI 聊天、图片生成、总结与文件分析待后端接入。

## 完成的验证

- AI 模块覆盖网关协议、上传限制、SSE 分片与取消、服务关闭模式、账号与
  token 边界、停止前后、异常时保留缓冲内容、主题、搜索、引导、菜单、
  Markdown 图片更新、横屏安全区、键盘、2 倍文字及减少动画。
- Mine 入口和响应式宽度的 2 项针对性回归通过，包括 AI 按钮走可用入口。
- 范围静态检查覆盖 AI 生产/测试模块及 MineLogic，无问题。
- 页面预览位于 `.dart_tool/ai-assistant-preview/`；包括两种主题的空状态、
  引导、工具选中、附件菜单和消息样式，共 10 张 PNG。
- AI 模块生产 Dart 文件均不超过 500 行，按功能拆分。职责见
  `lib/pages/ai_assistant/README.md`。

最终 AI 模块：**40 项全部通过**（包含两种主题的截图导出），Mine 入口
针对性回归 2 项通过。最终范围静态检查无问题。Android debug APK 构建
成功，输出 `build/app/outputs/flutter-apk/app-debug.apk`，构建日志为
`.dart_tool/ai-assistant-android-build.log`。本次未改变现有 Android 最低版本配置。

## 扩展回归中未通过的检查

额外运行 `mine_page_99chat_test.dart`、`settings_99chat_flow_test.dart`、
`settings_package1_99chat_test.dart`：38 通过、7 失败。未通过项位于当前
「我的/设置」页面和测试宿主，不涉及 AI 模块中的界面断言；本次没有修改
这些页面的生产逻辑，也没有将扩展回归描述为全部通过。

| 用例 | 直接失败原因 |
| --- | --- |
| 99chat account-security information architecture is preserved | 测试未初始化 SDK userID，读取生物支付偏好触发 LateInitializationError |
| settings account-security row pushes a real secondary page | 同上，账号安全页未完成构建 |
| account security reflects an already-bound phone number | 同上，账号安全页未完成构建 |
| font size page uses the 99chat full chat preview shell | 测试未初始化 SDK userID，背景预览读取账号缓存失败 |
| mine profile locks source-level 99chat geometry and colors | 测试仍期待标题与指示器间距 0，当前公共 MainTabTitle 使用 2px token |
| about page uses 99chat branding and supports embedded mode | 平台配置请求留下 Dio 计时器，测试结束前未清理/完成 |
| change payment password path keeps 99chat three-field shell | 测试期待的“忘记支付密码？通过短信验证码重置”文案未找到 |

完整扩展日志：`.dart_tool/ai-mine-regression-tests.log`。
入口单独回归日志：`.dart_tool/ai-mine-entry-tests.log`。
AI 模块日志：`.dart_tool/ai-assistant-preview/ai-module-tests.log`。
静态检查日志：`.dart_tool/ai-assistant-flutter-analyze.txt`。

## 验证边界

未接入真实 AI 网关；没有验证生产服务器回复、上传、历史、生成图片或总结。
系统附件权限需要真机验证，iOS 构建需要 macOS 环境。
