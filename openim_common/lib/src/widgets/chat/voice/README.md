# 共享聊天语音

`../voice_playback_controller.dart` 保留原有公开入口，负责当前会话的播放、顺序连播、已听回调与生命周期。气泡、聊天页和历史预览继续复用它；录音和转写业务仍归应用聊天语音模块。

`voice_playback_source.dart` 负责本机录音、缓存文件与远程地址的选择。参考 99chat 的 `voice_playback_source.dart` / `voice_message_path_utils.dart`，优先播放已下载文件，避免真机原生播放器重复请求远程流或依赖服务器的 Range 支持。下载复用 `DefaultCacheManager` 和波形提取的缓存；本机文件不存在、不可读或为空时尝试远程来源。下载超过 8 秒或失败后回退远程流，不让缓存失败阻断播放。

语音与波形均复用 `OpenIMMediaUrl.resolve` 修正未签名的 OpenIM 回环对象地址；签名地址原样保留，不向媒体服务器附加账号令牌，也不改写 SDK 消息。

整个播放器准备过程（停止旧播放器、取得来源、原生装载、定位）最多等待 20 秒；失败后结束加载、显示原有重试按钮并释放播放器，重试创建新实例。加载中取消、换消息、后台或销毁都会使旧请求失效，迟到下载/原生结果不能开始播放、触发已听回调或覆盖新状态。普通播放暂停和既有连播行为保持不变。

`voice_playback_log.dart` 在 debug 下输出 `[语音播放]`，区分 `player_stop`、`resolve_source`、`download_*`、`load_file`、`load_remote`、`play` 与对应失败阶段；只记录平台、请求代次、异常类型、HTTP/播放器错误码，不打印签名 URL、本机路径、令牌或原生异常正文。真机排查时可只收集这一前缀，定位网络获取和原生装载哪个阶段未完成。

回归：`test/voice_playback_test.dart` 保留连播和生命周期验证；`test/widgets/chat/voice/voice_playback_*_test.dart` 覆盖地址选择、缓存回退、超时重试、取消和迟到结果隔离。真实设备网络与解码能力仍需通过真机日志及播放验收确认。本次使用既有加载/重试 UI，亮暗主题和布局不变。

本目录其他 `chat_voice_*` 组件只负责录音面板显示与布局；录音生命周期由 `HoldToRecordButton` / `VoiceRecorderWidget` 持有，转写样式由 `voice_transcription_tokens.dart` 提供。
