# 通话视频预览与呼出回铃验收

日期：2026-10-06。用户确认截图来自 Android 模拟器；本次处理全屏通话右上角的视频预览，与应用内最小化浮窗恢复功能分别验证。

## 视频显示与切换

对照参考仓库 `reference-99chat/lib/src/pages/livekit_call_page.dart` 的大小视频切换：预览固定宽高，外层持有点击，视频子层忽略指针，缺失轨道使用头像占位。

当前实现复用 `SignalState`、`ParticipantWidget`、公共 `AvatarView` 和通话颜色 Token。没有新增另一个播放器或通话状态所有者。

- `ParticipantWidget` 明确撑满父容器并裁剪，继续使用真实 LiveKit `VideoTrackRenderer` 的 cover 模式，关闭视频时使用现有通话底色。
- 预览置于操作层之上，采用 opaque 命中和 `IgnorePointer`，避免移动端本地摄像头的对焦、缩放识别器消耗切换手势。
- 移除对远端轨道存在的点击限制；等待接听只有本地摄像头时也可切到主画面。另一侧缺失时仍保留可点击的头像预览，能再次切回。
- 点击切换只改变现有显示选择，不再拨号、不重新采集、不发布新轨道；最小化后恢复保留选择。

旧代码已经使用 cover，真实 SDK 的布局测试也确认其原始预览矩形为 96×144。因此不能把截图中摄像头源画面内部的小图和青色留白断言为 Flutter 未铺满。模拟器源帧自身带有的画布、边框或缩略内容无法通过容器 cover 自动去除；需要调整模拟器的摄像头输入或用真机摄像头核对。

## 呼出回铃

对照 99chat 来电和呼出等待分开使用声音的行为，继续复用 just_audio 单播放器和现有信令链路；声音资源为模块内原创生成的 PCM WAV，详见 `openim_live/assets/audio/ringtone/README.md`。

回铃在呼出邀请和 RTC 凭证成功后异步开始，不等待媒体连接结束，不阻塞连接流程。收到对方响应时立即停止；接通、取消、拒绝、超时、退出和销毁均释放声音。已接听的房间不允许迟到的媒体就绪回调重新播放。

音频装载与播放失败只记日志，不使通话失败；播放器加载期间的停止和销毁立即使旧结果失效。回铃不强制改全局音量、扬声器或蓝牙路由，不把 RTC 音频会话重新配置成音乐会话。

## 发起通话浮层兼容

实际控制器集成测试发现当前 Flutter 与 Get 4.7.2 的上下文边界失配。Get 的 `overlayContext` 是 Navigator 浮层的直属 Theater 子元素；当前 Flutter 的 `Overlay.maybeOf` 只从 OverlayEntry 内部标记取得浮层，直接传入该上下文得到 null。旧 `OpenIMLiveClient.start` 因此返回 false 并释放通话。

保留现有入口、忙碌、单聊和房间校验，改为 `Overlay.maybeOf(ctx) ?? Navigator.maybeOf(ctx)?.overlay`。回退只使用调用上下文所属的最近 Navigator，不使用另一窗口的全局浮层，不执行页面 push/pop。控制器回归继续使用真实 Navigator/Get 上下文，不能靠伪造位于 Entry 内的测试上下文掩盖问题。

## 自动验证与构建结果

- 旧实现实际复现等待时点击仍保持 96×144，未切换到 375×812；修复后 11 项视频测试全部通过，覆盖等待、双轨道、缺失/静音占位、反复切换、控件、最小化恢复、日夜、窄屏及原生尺寸变化。
- 新增 28 项回铃回归通过，包含 PCM 资产、单播放器去重、装载/销毁取消、音频故障恢复、实际邀请和凭证调用、提前接听、终态停止、退出及旧房间事件隔离。
- `flutter test --no-pub --timeout=60s test/pages/chat/calling test/pages/mine/calls`：180 项全部通过。本次新增 39 项，测试没有拨打真实电话。
- 视频/回铃新增文件和测试的定向 analyze 无问题；包含现有 controller/client/state 的范围检查没有 error 或 warning，另有 15 项既有花括号和字符串插值风格 info。未为本次修复批量重排其他通话逻辑。
- Android `flutter build apk --debug --no-pub` 成功；最终包保留为 `build/app/outputs/flutter-apk/app-call-preview-ringback-debug.apk`。

最终 APK：340851235 字节，SHA256 `817638C4CD21E7FE805F29FFFD310DDDEB99BB96E941FE9BEE64D56D80B8CDFF`。
直接核对 APK 内的 `packages/openim_live/assets/audio/ringtone/outgoing_ringback.wav`：160044 字节，SHA256 `F9619EE7FFA4B81E4E7B1468ABA0C5B3C98430CB1DCA143344958A6E975AADAE`，与源码资源一致。仅打包 WAV，没有把 README 和开发期生成脚本打入该资源目录。

## 验证边界

回归使用真实 Flutter 通话状态、SDK Participant/Track/VideoTrackRenderer/RTCVideoView，只模拟原生媒体通道及外部信令。Windows 上 SDK 平台判断使用 `dart:io Platform`，不执行 Android/iOS 摄像头手势分支；移动端同型手势测试与实际设备验收分别说明。

原生视频纹理模拟没有摄像头像素，尺寸/cover 测试不能证明真实源画面内容。音频测试可以验证静态 PCM 音调、节奏、资源打包和生命周期，不能代替设备实听。

尚需 Android 模拟器安装新包后验证摄像头输入与视频点击；Android/iPhone 真机验证实际两端通话、回铃实听、静音开关、通信音量、听筒/外放/蓝牙路由以及后台行为。Windows 环境不能编译和运行 iOS。
