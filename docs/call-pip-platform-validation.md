# 通话系统画中画平台核对

核对时间：2026-10-05。仅连接本地测试替身，未发起真实呼叫、修改远端数据。

## 当前实现

统一桥：`openim_live/lib/src/platform/call_picture_in_picture.dart`，通道
`openim_call_pip`，入口为 `configure`、`enter`、`stop`。
回调 `state` 携带会话标识和 `entering / active / restored / closed / failed`。
每次新通话使用新会话标识，停止、销毁和旧呼叫的迟到事件不会复活界面。
平台返回 `supported`、`ready`、`backgroundCameraSupported`；请求成功不等于已进入。
拒绝、缺失插件或超时都退回应用内通话。

Android 使用已存在的 MainActivity 和实际 Flutter 通话画面，Android 8+
检查 FEATURE_PICTURE_IN_PICTURE。Android 12+ 配置 autoEnterEnabled，较早版本
从 onUserLeaveHint 进入。Manifest 保留现有 Activity 和配置变更项，仅开启
supportsPictureInPicture 和 resizeableActivity。原有投屏设置入口未改。
同时检查本应用 OPSTR_PICTURE_IN_PICTURE 的 AppOps 设置，用户明确禁用时
能力为 false；该检查不申请新权限，不将设备支持误当成用户已允许。

系统恢复通知 Dart 恢复完整通话；用户关闭窗口通知结束通话。熄屏和锁屏
不会被退出策略当成用户关闭。只请求进入但没有 active 回调时的 onStop
不会结束通话，避免系统禁用 PiP 时误挂断。
原生进入请求也有同会话三秒观察器；没有真实系统小窗时只通知 failed，
不会通知 closed，之后可重试。若系统小窗已存在而 mode 回调延迟，则依据
实际系统状态补 active。停止和 mode 变更会取消观察器。关闭自动进入参数
不受用户 AppOps 拒绝限制，避免已结束通话留下旧的自动进入标记。

Android 公开 Activity API 没有 stopPictureInPicture。当前单 Activity 结构在
程序结束通话且原生仍 active/inPiP 时，先关闭自动进入，再通过
REORDER_TO_FRONT | SINGLE_TOP 恢复现有 MainActivity 一次，以收起小窗并保留
Flutter 引擎和聊天会话。因此远端挂断时应用会恢复到前台。用户点击系统 X
不会触发这一恢复。若系统拒绝恢复，仍关闭自动进入，不终止主 Activity。
这一设备行为尚待实机确认。

iOS 15+ 使用 AVPictureInPictureVideoCallViewController 和正式 ContentSource。
通过项目当前 flutter_webrtc 1.1.0 的公开 remoteTrackForId 获取真实远端
RTCVideoTrack，增加第二个 RTCVideoRenderer。真实 RTCCVPixelBuffer 直接送入
AVSampleBufferDisplayLayer；软件 I420 帧转换为 NV12 后送入同一层。
帧队列最多保留一个在途样本，轨道更换和停止通过 generation 拒绝迟到帧。
显示层为独立子层，90/270 度时交换显示层 bounds 的宽高、居中后旋转，
UIView 自身的约束和 bounds 不旋转；KVO 与 delegate 都检查当前 controller
身份，旧控制器的状态不会被标记为新会话状态。上述 iOS 修复已完成源码
核对，尚未经过 macOS 编译或设备验证。
没有远端视频、轨道未准备、没有真实首帧或 AVKit 不允许进入时安全降级，
不以循环截图、静态头像或合成视频模拟通话 PiP。

已核对参考仓库 `reference-99chat/ios/Runner/LiveKitCallPip.swift`：同样使用真实
WebRTC renderer → AVSampleBufferDisplayLayer → 视频通话内容控制器。本仓库桥
增加会话隔离、恢复/关闭回调与能力判断；原有 LiveCasting AirPlay 入口保留。
Runner 添加 audio 后台模式，媒体音频会话仍由现有 WebRTC 管理。

## iPhone 后台摄像头边界

在 iOS 16+，仅 captureSession.isMultitaskingCameraAccessSupported 为 true 时
设置 multitaskingCameraAccessEnabled，并回报实际启用结果。
当前没有新增 com.apple.developer.avfoundation.multitasking-camera-access entitlement，
也没有新增 voip/PushKit 注册。因此普通 iPhone 上该能力可能为 false，通话层
必须在后台暂停本地摄像头，返回前台按原设置恢复；真实远端视频 PiP 与该
本地采集能力分开判断。不得将在线邀请和 audio 后台模式描述成完整离线来电。

Apple 当前文档列出的 supported 条件包括支持 Stage Manager 的 iPad、获得
相应 entitlement，或链接 iOS 18+ SDK 且声明 voip 后台模式。本实现始终以
运行时 supported 属性为准，不凭设备名称或系统版本猜测，也不为未知的
离线推送服务添加 voip 声明。

## 已执行验证

- Dart 通道回归 7 项通过：进入去重、真实 native active 回调、恢复/关闭去重、
  停止后旧事件、迟到 capability、视频能力丢失与迟到 active、原生拒绝/缺失插件、
  进入超时、桌面降级和销毁。
  日志：`E:/openim/.temp/call-pip-dart-test.log`。
- 两个 Dart 文件静态分析无问题：`E:/openim/.temp/call-pip-dart-analyze.log`。
- 原生退出策略独立 JVM 14 项通过：恢复、关闭、锁屏/熄屏，以及程序停止与
  用户 X、真实窗口与进入超时的区别。源码：
  `android/app/src/test/java/io/openim/calling/CallPipExitPolicyTest.java`。
  日志：`E:/openim/.temp/call-pip-native-policy-test.log`。
- CallPictureInPictureBridge 和策略已使用 Android 35 SDK + Flutter embedding
  直接 javac 编译通过。日志：`E:/openim/.temp/call-pip-native-compile.log`。
- 最终 Android 完整 debug APK 构建通过，包含进入超时回收、AppOps 解绑及
  后台摄像头处理。日志：`E:/openim/.temp/call-pip-apk-build.log`；独立安装包：
  `build/app/outputs/flutter-apk/app-calling-pip-debug.apk`。

Windows 环境不能运行 Xcode/iOS SDK。本轮 iOS 原生文件仅完成源码与当前
插件公开接口核对，尚未通过 macOS 编译或 iPhone 实机验证。

## 设备验收

使用测试账号完成 Android 8–11、12+、当前 iPhone 的视频通话：回到桌面、
切换应用、点击小窗恢复、点击 X、远端挂断、熄屏/锁屏、系统禁用 PiP、
重复开关和更换远端轨道。确认实际远端视频持续显示、关闭只结束当前通话、
程序结束收起窗口、旧会话不误伤新通话，原有投屏功能仍可使用。
iPhone 另核验后台音频、cameraSupported=false 时本地视频暂停与恢复，以及
有相应 capability 的设备实际后台采集。iOS 音频通话保留应用内小窗。
另验首次视频帧、0/90/180/270 度帧旋转、系统小窗缩放和快速切换远端轨道，
确认真实视频不被旧帧覆盖，旋转后画幅保持正确。

## 官方依据

- [Android PiP 与生命周期](https://developer.android.com/develop/ui/views/picture-in-picture)
- [Activity API](https://developer.android.com/reference/android/app/Activity)
- [Intent REORDER_TO_FRONT](https://developer.android.com/reference/android/content/Intent#FLAG_ACTIVITY_REORDER_TO_FRONT)
- [AppOps PiP 许可](https://developer.android.com/reference/android/app/AppOpsManager#OPSTR_PICTURE_IN_PICTURE)
- [Apple 视频通话 PiP](https://developer.apple.com/documentation/avkit/adopting-picture-in-picture-for-video-calls)
- [AVPictureInPictureVideoCallViewController](https://developer.apple.com/documentation/avkit/avpictureinpicturevideocallviewcontroller)
- [真实视频通话 ContentSource](https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller/contentsource-swift.class/activevideocallcontentviewcontroller)
- [后台摄像头 supported 判断](https://developer.apple.com/documentation/avfoundation/avcapturesession/ismultitaskingcameraaccesssupported)
