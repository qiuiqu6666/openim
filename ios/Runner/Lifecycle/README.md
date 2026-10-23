# iOS 场景启动与邀请入口

当前 Flutter 3.41.6 支持 UIScene。Xcode 27 / iOS 27 SDK 要求使用场景生命周期；仅通过旧 AppDelegate 启动或只改 Info.plist 都不足以完成迁移。

## 所有权与时序

- `AppDelegate.application(didFinishLaunchingWithOptions:)` 只初始化进程级 UNUserNotificationCenter delegate、PushKit，并保留旧启动 URL 入口。不在这里读取 `window.rootViewController`。
- `AppDelegate.didInitializeImplicitFlutterEngine` 使用 `engineBridge.pluginRegistry` 注册生成插件，并用 `applicationRegistrar.messenger()` 挂载应用通道。APNs、CallKit、屏幕共享、地址、PhotoKit、通知、AirPlay、原生底栏的原有协议与数据来源保留。
- `SceneDelegate` 继承 `FlutterSceneDelegate`，正常转发生命周期给引擎和插件。Info.plist 使用 `Main` 场景故事板，关闭多场景。冷启动邀请 URL 与运行中的邀请 URL 通过同一 `FriendInviteBridge` 处理；非本应用邀请交回 Flutter 的默认场景处理。
- `FriendInvitePendingState` 保存尚未消费的 URL。Dart 的 `takeInvite` 一次消费；异步 `openInvite` 的成功确认只清理对应交付，旧确认不能覆盖新邀请（包括重复点击同一 URL）。状态保存在进程级 AppDelegate，跨场景启动次序不丢失。
- 原生底栏工厂及通话 PiP 通道在引擎阶段注册，但从 registrar 延迟获取当前控制器，不提前持有窗口或强引用 FlutterViewController。

通知/通话状态仍由原有 APNs、PushKit/CallKit 与 Dart 会话所有者维护。本次不改 SDK、路由框架、账号状态或签名配置；不通过关闭系统检查或兼容模式绕过 UIScene。

## 原生依赖修复

`ios/scripts/file_picker_namespace.rb` 只对 CocoaPods 的 `file_picker` target 增加 `FileUtils=Chat99FilePickerFileUtils` 编译定义，消除其内部 Objective-C 类与 OSAnalytics 的重名，保留原插件接口及其他宏。Debug/Profile/Release 均生效；生成 Pods 工程可重复执行，不修改 pub 缓存。

`local_plugin/volume_controller` 为 3.4.0 的 iOS 局部修补：音量观察不再在主线程激活/关闭或重设共享音频会话，避免前台恢复时的 Hang Risk，并保留真正音频所有者的生命周期。来源、补丁及验证见插件 README。

## 验证入口

- `ios/tests/Lifecycle/run.sh`：冷/热 URL、一次消费、未知 URL 和过期确认。
- `ruby ios/scripts/test/file_picker_namespace_test.rb`：宏作用域、权限宏保留及幂等。
- `ruby ios/scripts/test/apns_only_plugins_test.rb`：iOS 保留直接 APNs 路径，禁止生成器恢复 FCM 的第二套注册。
- `python3 ios/tests/Volume/run.py <已启动的模拟器UDID>`：真实生产音量类监听、取消、前台恢复的会话所有权和事件检查。
- `flutter test --no-pub test/core/calling/ios test/core/push/apns test/pages/home/navigation/home_bottom_nav_bar_test.dart`：Dart 通话、推送、导航回归。

构建检查需覆盖设备和模拟器，并检查 `file_picker.framework` 导出 `Chat99FilePickerFileUtils`，而不再定义原始 `FileUtils`。必须在 iOS 27+ 实际启动 App 并观察首帧；只编译成功不能证明生命周期正常。真机冷启动通知点击、被叫唤醒、前后台通话、PiP、文件选择器及物理音量键仍需安装签名包验收。测试模拟器无真实登录账号，不能代替双向媒体与后台接听验证。

官方迁移依据：<https://docs.flutter.dev/release/breaking-changes/uiscenedelegate>；当前实现以仓库使用的 Flutter 3.41.6 头文件和模板为准。
