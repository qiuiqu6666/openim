# 语音区域重设计验证

2026-10-05，按用户确认的简洁 iPhone 风格重新设计当前聊天页语音区域。继续使用当前 ChatPage、ChatInputBox、HoldToRecordButton、本地 voice_note_kit，以及现有 OpenIM 发送、语音播放和转文字确认流程。

## 界面与交互

- 固定 248px 面板加手机底部安全区，主麦克风 80px，平蓝色与项目强调色一致。输入栏和草稿沿用原组件。
- 日夜主题分别使用当前聊天底栏颜色。录音浮层采用轻遮罩、时长、真实音量波形，以及有文字标签的取消、发送、转文字区域。
- 波形只绘制最近 24 个原生振幅样本，每 100ms 更新。静音维持基线，时间显示使用录音插件的秒数；没有随机或正弦动画生成假音量。
- 准备中、处理中复用加载指示器。错误同时在当前面板内说明和原 Toast 中提示，下一次按下清除错误。
- 仅麦克风范围接受录音开始。最终松手位置决定行为；多指取消、快速松手、重复操作、切换面板、路由覆盖、退后台和退出都受录音状态保护。
- 录音交付后仍在读取时长或复制文件期间，切换输入或离开页面会使本次录音失效，即使马上返回也不能恢复旧发送。播放器释放或文件清理异常时仍解除处理中状态。
- 原 60 秒时长上限、短录音检查、识别失败重试、转文字编辑确认与发送原语音能力保留。
- 取消时原生 stop 出错会等待释放录音器；后续启动须先完成旧录音器释放。已交付业务层的文件不会被录音器清理流程删除。当前依赖的原生 cancel 通道未等待异步结果，因此使用可等待的 dispose 兜底，不修改依赖缓存。

## 维护入口

- `openim_common/lib/src/res/chat_voice_tokens.dart`：统一尺寸、时间和显示参数。
- `openim_common/lib/src/widgets/chat/voice/`：主题颜色、共享命中几何、真实波形及纯视图。
- `openim_common/lib/src/widgets/hold_to_record_button.dart`：手势、采样历史、前后台/路由生命周期与文件交付。
- `local_plugin/voice_note_kit/lib/recorder/`：沿用一个原生录音器，管理权限、启动/停止/取消与临时文件。

## 验证

面板测试覆盖日夜主题、320/375 宽度、0/34 底部安全区、放大文字、准备/录音/取消/转换/错误/处理状态，检查状态切换时固定高度、控件与文案不越界，以及草稿和选区保留。原输入栏的独立参考渲染回归继续使用 99chat 生产布局作为基线。

实际手势测试覆盖取消、最终松手、多指、时长上限、真实采样与秒数、权限错误和重试、路由覆盖、准备期间切换/卸载，并检查取消后没有进入音频解码、发送或识别链路。插件测试通过原生通道 mock 和真实临时文件检查迟到权限、迟到启动、停止失败、资源释放、重试及文件所有权。

正向手势完整经过时长加载、复制文件和业务回调，分别验证发送、转文字只交付一次；另验证 500ms 短录音的提示与清理，以及解码期间切换输入并立即返回后零交付、无遗留文件。

分批执行结果：

| 验证组 | 结果 |
| --- | --- |
| 面板布局、日夜主题、320/375 宽、1/1.5/2 倍字号 | 7 项通过 |
| 实际指针手势与音频交付 | 16 项通过 |
| 原生录音控制器、权限与释放异常 | 14 项通过 |
| 原输入栏布局与独立参考渲染 | 6 项通过，包含 32 组像素比较 |
| 输入、系统栏、播放、转文字、聊天入口相关回归 | 139 项通过 |
| 正式 ChatPage 日夜预览 | 2 项通过 |

共 184 项测试通过。本次语音组件、录音插件、相关测试的静态分析无问题。整包构建前还恢复了工作区 AI 页面中损坏的括号、标识符和提示字符串；只恢复编译，未调整其业务。

Android debug 构建成功，安装包：`build/app/outputs/flutter-apk/app-chat-voice-iphone-debug.apk`（362,125,429 字节，2026-10-05 05:01）。保留原来的 99chat 语音基线安装包，当前安装包单独命名。

预览来自正式 ChatPage 和现有录音组件，SDK、原生麦克风回复与预览字体由测试环境替换。`docs/previews/chat-voice-iphone-{light,dark}-{idle,preparing,recording,cancel,convert,error}.png` 覆盖日夜六种状态。预览使用可控的模拟振幅输入展示真实采样驱动路径，未将模拟数据放进生产代码。

| 状态 | 日间 | 夜间 |
| --- | --- | --- |
| 待录音 | [查看](previews/chat-voice-iphone-light-idle.png) | [查看](previews/chat-voice-iphone-dark-idle.png) |
| 准备中 | [查看](previews/chat-voice-iphone-light-preparing.png) | [查看](previews/chat-voice-iphone-dark-preparing.png) |
| 录音中 | [查看](previews/chat-voice-iphone-light-recording.png) | [查看](previews/chat-voice-iphone-dark-recording.png) |
| 取消 | [查看](previews/chat-voice-iphone-light-cancel.png) | [查看](previews/chat-voice-iphone-dark-cancel.png) |
| 转文字 | [查看](previews/chat-voice-iphone-light-convert.png) | [查看](previews/chat-voice-iphone-dark-convert.png) |
| 错误 | [查看](previews/chat-voice-iphone-light-error.png) | [查看](previews/chat-voice-iphone-dark-error.png) |

尚未验证 Android/iOS 真机麦克风权限弹窗、实际音质、系统字体和键盘动画，未进行 iOS 编译或真机安装。预览及原生通道 mock 不能替代真机验收。
