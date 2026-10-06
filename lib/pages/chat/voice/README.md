# 聊天语音模块

- `chat_voice_controller.dart` 持有本次会话的录音、播放、转写和文件交接，继续通过 OpenIM 创建/发送消息。账号、token、会话关闭检查位于业务交接边界。
- `voice_to_text_service.dart` 使用现有认证 ASR 代理、取消令牌和错误映射；不在界面中处理服务商凭据，不用假识别结果替代正式服务。
- `voice_transcription_controller.dart` 管理消息内转写、请求去重与 localEx 合并；私密消息的转写不持久化。
- `widgets/voice_text_preview_dialog.dart` 保留原调用契约，通过 `VoiceTextPreviewDialog.show` 打开底部确认面板。复用 Material BottomSheet 路由、现有 Cupertino Loading、公共语音颜色和按钮，历史类名保留兼容。
- `widgets/voice_text_preview_tokens.dart` 只管理确认面板尺寸。内容和按钮分区，识别状态切换保持高度；键盘与大字场景优先保留关闭、发送按钮和编辑区域，极小可用高度采用滚动回退。

识别只允许一个活动请求。关闭或发送原语音会取消识别；迟到结果不能回写。文字可编辑，发送前去除首尾空白，全空内容不可发送。面板只返回选择，由控制器继续完成发送；文字发送保留输入栏草稿，原语音交付后由消息链路持有文件，取消或发送文字会删除不再需要的录音。

消息内转写仍由公共 `VoiceTranscriptionView` 显示，使用同一语音颜色。短结果不显示冗余折叠操作，长结果按实际宽度和字号判断三行预览；私密消息继续禁止文字选择。

测试位于 `test/pages/chat/voice/` 及 `test/voice_transcription_view_test.dart`。界面变更与预览见 `docs/chat-voice-text-validation.md`。
