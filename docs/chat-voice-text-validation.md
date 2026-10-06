# 语音转文字界面优化

2026-10-05，延续用户确认的简洁 iPhone 风格，优化录音后的转文字确认及消息中的转写结果。

## 改动

- 原 AlertDialog 改为底部确认面板，右上角关闭。加载、识别失败和结果使用同一高度，识别完成后可直接编辑。
- 保留“发送原语音”和“发送文字”；加载、失败或输入为空时禁止发送文字。关闭或发送原语音立即取消识别请求，重复重试不创建并行任务。
- 日夜主题复用 `ChatVoicePalette`、AppTokens、现有 Cupertino Loading 和 Material BottomSheet/按钮，未新增重复的弹窗或 Loading 组件。
- 小屏与大字号时操作纵向排列；键盘打开后缩减说明区域，优先保留编辑、关闭和发送操作。极小可用高度采用滚动回退。
- 消息内转写使用轻分隔线、简洁 Loading、可选正文和文字操作。仅超过三行的结果显示展开/收起；失败仍显示具体原因和重试入口。私密消息不开放文本选择、不持久化转写内容。

对照了 99chat `TIMUIKitTextField/tim_uikit_send_sound_message.dart` 的 `_buildConvertStatusBanner` 和 `_buildConvertReviewControlsPanel`，保留识别、编辑、发送文字/原语音的流程。本次按用户确认的新风格重设计视觉，未声称与其原绿色状态条像素一致。

正式识别仍使用现有 `VoiceToTextService`、认证代理和取消机制；发送仍走 OpenIM。发送文字继续使用 `resetInput:false`，保留输入栏草稿；原语音文件交给消息链路，取消和文字发送清理未交付文件。

## 验证

组件与业务回归涵盖：日夜、320px、2 倍字号、键盘、长文本、空结果/全空输入、识别失败与重试、连续操作、关闭与晚结果、文件所有权、账号/token/会话退出，以及私密消息行为。

2026-10-05 分批验证共 144 项通过：转写组件/服务/控制器/私密消息菜单 76 项，底部确认面板 11 项，聊天入口/录音手势/播放回归 55 项，正式 ChatPage 预览 2 项。相关代码与测试静态分析无问题。

Android debug 构建成功，安装包 `build/app/outputs/flutter-apk/app-chat-voice-text-debug.apk`，大小 362,159,400 字节。此前录音面板的独立安装包继续保留。

预览通过正式 Flutter ChatPage 与实际确认面板渲染，聊天数据及 ASR 回复在测试中替换，不向真实聊天发送消息。字体使用测试字体，不代表手机系统字体。

| 状态 | 日间 | 夜间 |
| --- | --- | --- |
| 识别中 | [查看](previews/chat-voice-text-light-loading.png) | [查看](previews/chat-voice-text-dark-loading.png) |
| 编辑结果 | [查看](previews/chat-voice-text-light-result.png) | [查看](previews/chat-voice-text-dark-result.png) |
| 失败重试 | [查看](previews/chat-voice-text-light-error.png) | [查看](previews/chat-voice-text-dark-error.png) |
| 消息内转写 | [查看](previews/chat-voice-text-light-message.png) | [查看](previews/chat-voice-text-dark-message.png) |

尚未进行真实 ASR 服务联调、Android/iPhone 真机键盘与输入法验证，未执行 iOS 编译或安装。
