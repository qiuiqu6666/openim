# 统一媒体与语音输出

`MediaCoordinator.instance` 是聊天语音、收藏语音、视频、录音和前台提示音的统一入口。图片浏览不申请媒体租约，也不改音频会话。

播放模式存储在 SharedPreferences 的 `voice_output_mode`，启动时恢复，默认扬声器。长按语音菜单由 `lib/pages/chat/voice/widgets/voice_output_menu.dart` 提供。切换仅更新原生音频输出，不重新加载或跳转语音。

播放中的语音气泡外显示独立倍速胶囊（发出的语音在左侧，收到的在右侧），暂停时显示“继续播放”并从保留的进度继续；原速播放时显示“倍速播放”（切换至 2 倍），倍速时显示“原速播放”（切回 1 倍）。`VoicePlaybackController` 直接更新当前 just_audio 播放速度，保持进度，不重新加载或调用播放；同一聊天控制器的后续语音沿用倍速。新控制器默认原速，倍速不写入持久化输出模式设置。组件及控制器回归覆盖点击不暂停、快速切换顺序、进度不变和下一条沿用倍速。

## 所有权与竞争

- 每次播放先申请 `MediaLease`。新请求同步使旧租约失效，然后串行等待旧媒体停止和会话释放；停止失败时禁止启动新媒体。
- 录音申请立即预留所有权，在录音原生初始化前阻止其他播放；原生录音停止、取消或销毁后才释放。
- 视频只在请求播放时申请租约。未播放的预览不初始化播放器；迟到的初始化、失败回退不能抢回已经失去的租约。
- 提示音优先级最低，不抢占语音、视频或录音。互斥停止、系统中断均不自动恢复。
- `lease.run` 仅串行执行短原生命令，不能等待覆盖整段播放的 Future。释放旧租约不能影响新所有者。

适配入口：`voice_playback_controller.dart`、`native_media_video.dart`、`hold_to_record_button.dart`、收藏 `favorite_audio_preview.dart` 和 `foreground_message_alert.dart`。录音器通过 `voice_note_kit` 的 `acquireAudio` 回调接入，插件不依赖业务协调器。

## 原生路由

Android 的 `MediaAudioBridge.java` 管理 Audio Focus、通信模式和输出设备；支持新设备 API 和旧版 speakerphone 路径。iOS 的 `MediaAudioBridge.swift` 管理 AVAudioSession。录音原生配置仍交给现有录音插件。外部耳机优先于手机听筒/扬声器偏好，断开耳机或系统中断停止播放，不自动外放或恢复。平台失败反馈给调用方，不能假定路由成功。

参考：[Android AudioManager](https://developer.android.com/reference/android/media/AudioManager)、[Apple 输出覆盖](https://developer.apple.com/documentation/avfaudio/avaudiosession/overrideoutputaudioport(_:))、[Apple 路由变化](https://developer.apple.com/documentation/avfaudio/responding-to-audio-route-changes)。

## 验证边界

自动化覆盖模式持久化、实时切换不重载、保留暂停进度、快速抢占、录音预留、失败停止、视频延迟初始化和图片浏览。测试入口在 `test/media/`、`test/widgets/chat/voice/`、`test/widgets/media_browser/`、`test/widgets/chat/chat_voice_gesture_test.dart` 及收藏和提示音测试。

`integration_test/media/voice_audio_route_device_test.dart` 使用实际 just_audio 和原生桥检查输出状态、播放进度、图片浏览及录音互斥。2026-10-22 在明确指定的 Android 模拟器 `emulator-5554` 执行；模拟器不能证明真实声学输出或无可闻卡顿。录音集成步骤检查媒体租约，实际录音插件调用顺序由组件测试验证。

仍需 Android、iOS 真机验收：听筒/扬声器连续切换的实际音频和进度、重启恢复偏好、实际录音、视频互斥、有线/蓝牙耳机连接与拔出、电话中断、后台前台切换。Android 应覆盖 API 31 前后；当前环境没有 iOS 编译和真机工具，不能宣称 iOS 已编译或通过真机验收。
