# 通知设置功能与验证

日期：2026-10-06。

对照本地 99chat 的 `notification_settings_page.dart`、`notification_settings_service.dart` 和 `livekit_call_ringtone.dart`。保持当前设置页面结构、AppTokens 日夜主题和公共 SettingsScaffold/SettingsGroup/SettingsCell/SettingsSwitchCell/ActionSheet。真实入口为「我的 → 通知」，由 MineLogic 传入账号设置 store。

## 已接入的行为

| 选项 | 实际行为 |
| --- | --- |
| 系统消息通知 | 控制后台已收到的 OpenIM SDK 消息是否展示系统通知，保留前台独立开关 |
| 弹窗快捷接听 | 开启显示复用 BottomSheetView 的接听/拒接/打开通话弹层；关闭使用全屏接听；操作同一个 SingleCallSession |
| 消息横幅快捷回复 | Android RemoteInput / iOS 文本动作，经既有 SDK 与 ChatMessageSender 发送；关闭立即清理旧通知，重复回调不会重复发送 |
| 前后台通知内容 | 分别选择发送人及内容、仅发送人、隐藏详情；异步头像和原生展示前再次检查隐私 |
| 打开时通知 | 控制前台其他会话横幅，当前聊天不再弹横幅 |
| 消息提示音、振动 | 前台独立提醒；即使横幅关闭或正在当前聊天，仍按这两个开关执行；免打扰/历史同步/活动通话继续抑制 |
| 默认提示音 | 七种现有声音可选择与试听，选中声音用于实际前台声音与后台系统通知；已在通话时仍能保存选择，推迟试听 |
| 来电铃声 | 关闭立即停止来电声音，接听入口保留；出站等待接通的回铃仍正常 |

所有当前页面偏好按账号持久化，reload 后恢复。Store 捕获 owner，旧页面在账号切换、销毁后不再写入。当前 OpenIM 后端没有通知设置 endpoint，因此闭屏开关与预览在本地控制实际 SDK 通知，不调用继承的 Stub。只有明确支持真实远程接口的 SettingsService adapter 才先保存、成功后更新；失败保留旧值，页面给可重试提示。

设置页检查系统通知权限，支持申请、永久拒绝跳转系统设置、恢复后重新读取、错误重试和重复点击保护。声音模块采用单播放器及 500ms 节流，声音/振动故障互不阻断；异步加载、换账号、通话开始、后台与退出立即失效，停止时不 deactivate 共享 RTC 音频 session。来电偏好订阅随 IMController 生命周期释放，公共 call 包不反向依赖应用。

## 验证结果

- 通知策略、原生通道序列化、消息/账号生命周期、设置持久化、页面交互、前台声音取消、快捷接听、全部通话/PiP/视频小窗、通话记录与聊天进入流程联合 **431 项通过**。日志：`E:/openim/.temp/notification-settings-scoped-final-tests.txt`。
- 旧提示音迁移校验另单独通过 1 项，日志：`notification-settings-legacy-picker-test.txt`。
- 本次相关生产与测试文件静态分析无 error/warning。包含大型接入文件时保留 22 项既有/测试风格 info，日志：`notification-settings-final-analyze.txt`；没有为清理无关风格改动大控制器。
- 更宽运行旧 `settings_package1_99chat_test.dart` 时有三个无关现存失败：账号安全测试未初始化 SDK userID、关于页遗留 timer、支付密码测试的旧文案断言；本次未改这些产品页面。相关提示音校验单独运行通过。
- Android debug APK 构建成功：`build/app/outputs/flutter-apk/app-notification-settings-debug.apk`，384667225 字节，SHA256 `F383541FF64E95788A20F0D6A112DD8CD45C2B5F7EA707C63791E7226B516598`。七种原生 PCM WAV 均已核对 APK 中的资源字节与源文件一致。
- 日夜主题真实 Flutter widget 渲染 12 张，路径 `docs/previews/notifications/`：正常、权限未开、依赖项禁用、内容选择、保存失败、声音选择。390×844 逻辑尺寸，测试字体；账号/权限/失败为测试夹具，没有触发真实请求或真实消息。内容弹层另加载 Cupertino 字体后重新导出，正常中文字形已目视核对。
- UI 测试覆盖 320 窄屏、横屏与大字体，无布局溢出。预览作 home，生产导航通过共享 Scaffold 显示返回按钮。

## 未完成的设备/服务端边界

当前能力处理应用已经收到的 SDK 消息。应用被完全终止后的远程推送尚未接入收件人通知偏好、隐私预览、声音与快捷回复；需要服务端推送载荷/设置接口及 iOS Notification Service Extension 配合。没有猜测新增 endpoint 或把闭屏关闭映射为 SDK 全局免打扰，以免连前台消息也被关闭。

Android 13+ 权限、系统横幅的展开回复与各厂商后台限制，实际声音/静音/振动及来电需要真机验证。本次没有替换设备应用，没有向任何联系人发消息或发起真实通话。Windows 无 Xcode，iOS Swift 编译、签名 capability、bundle 自定义音效和通知动作仍需 Mac/iPhone 验收。

原生音效转换依据：[Apple 自定义通知声音](https://developer.apple.com/documentation/usernotifications/unnotificationsound)、[Android 通知频道](https://developer.android.com/develop/ui/compose/notifications/channels)。七种声音沿用现有资源，转换为小于30秒的 PCM WAV；Android 新声音使用独立频道，不尝试修改已创建频道的声音属性。
