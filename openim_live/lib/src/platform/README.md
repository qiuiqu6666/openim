# 系统通话画中画

`CallPictureInPictureController` 仅管理当前已接通的通话。通话UI应在
`active || entering` 时显示专用简洁画面，接通后 `configure(enabled: true)`，
结束时先 `stop()` 再释放房间。Android系统恢复触发 `onRestore`；用户关闭
系统窗口触发 `onClosed`。Session标识隔离旧呼叫的迟到回调。

## Android

`openim_call_pip` → `MainActivity` → `calling/CallPictureInPictureBridge`。
Android 8+先检查系统PiP能力。Android 12+配置自动进入，较早系统通过
`onUserLeaveHint` 进入；Activity PiP始终使用正在运行的Flutter通话画面。
退出策略区分恢复、用户关闭、锁屏/熄屏，锁屏不会伪造结束事件。
拒绝进入或缺少插件时保留应用内通话，不把成功请求误当成已进入。
远端挂断或程序结束通话时，如果原生小窗仍然存在，会恢复现有MainActivity
到前台并收起小窗，以保留SDK和聊天会话；用户点击系统关闭按钮不恢复应用。
这是当前单Activity结构的退出策略，设备行为需要实机验证。

既有 `openim_group_live_cast` 的投屏设置和AirPlay入口不属于PiP，保持原样。

## iOS

使用iOS 15+的 `AVPictureInPictureVideoCallViewController`，从现有
`FlutterWebRTCPlugin.remoteTrackForId` 订阅实际远端 `RTCVideoTrack`。
`CallVideoFrameView` 将真实硬解CVPixelBuffer或软解I420帧送入
`AVSampleBufferDisplayLayer`，不使用静态头像、截图循环或伪视频流。
没有远端视频、轨道未就绪或AVKit拒绝时安全退回应用内小窗。

后台音频通过Runner的 `UIBackgroundModes=audio` 维持，媒体会话仍归WebRTC。
本地摄像头仅在iOS 16+captureSession确认
`isMultitaskingCameraAccessSupported` 后开启multitaskingCameraAccessEnabled；
`backgroundCameraSupported=false` 时，通话UI应在后台暂停本地视频，恢复时
按原先麦克风/摄像头状态处理。这不宣称已接入离线PushKit或CallKit。

## 验证边界

Dart通道测试验证进入/恢复/关闭、拒绝、迟到事件、停止和销毁；纯JVM测试
验证锁屏不会误结束。Android APK构建检查原生编译。iOS代码必须在macOS
使用项目当前WebRTC Pod进行编译；系统PiP自动进入、恢复、关闭和后台采集
必须在Android/iPhone实机验证。Windows测试不构成iOS编译或真实通话验证。

官方接口：

- https://developer.android.com/develop/ui/views/picture-in-picture
- https://developer.apple.com/documentation/avkit/adopting-picture-in-picture-for-video-calls
- https://developer.apple.com/documentation/avfoundation/avcapturesession/ismultitaskingcameraaccesssupported

核对记录与实机验收项见 `docs/call-pip-platform-validation.md`。
