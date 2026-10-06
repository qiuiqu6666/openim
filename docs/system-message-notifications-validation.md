# 系统消息横幅实现与验收

日期：2026-10-04。

## 已实现

- SDK 收到其他会话的新消息时，使用 Android 系统 MessagingStyle / iOS 系统通知横幅。
- 单聊显示会话或发送人头像，群聊显示群头像，缺失或下载失败使用平台图标。头像异步更新且不重复响铃；缓存源文件变化后重新生成小尺寸 PNG。
- Android RemoteInput 与 iOS 文本通知动作提供快捷回复；提交时唤醒既有应用与 SDK，通过既有消息发送链路发送。系统控制展开手势。
- 点击通过现有聊天导航进入对应会话，冷启动等待 SDK 同步与主页准备，重复回调不会重复发送回复。
- 遵守应用内通知开关、前后台预览、SDK 全局/会话免打扰、声音及振动设置；当前正在查看的会话不重复提示。
- 退出、账号切换、旧消息查询迟到、新消息覆盖、旧通知取消、头像晚到及隐私设置改变均有保护。消息设置改变立即取消在途原生头像处理，语音/视频快捷接听保持独立。

模块与维护契约：[通知模块](../lib/core/notifications/README.md)、[iOS 原生桥接](../ios/Runner/Notifications/README.md)。参考已核对本地 99chat 的 Android `AppSystemNotificationPlugin` / `NotificationAvatarUpdates` 与 iOS `NotificationAvatarDecorator`：复用立即展示、异步头像与系统通信通知的行为，接入本项目的 OpenIM SDK、现有导航与发送能力。

## 验证结果

新增通知测试共 121 项通过：动作/目标 33、展示策略 26、运行时 22、原生通道适配 22、头像缓存 8、设置 10。

最终联合运行通知测试、设置状态、聊天入口及消息发送测试，168 项全部通过。记录位于 `.dart_tool/message-notification-final-regressions.txt`。原生通道测试模拟系统接口，未登录测试账号、访问真实头像网络或发送真实聊天消息。

通知生产模块及对应测试静态分析无问题，记录位于 `.dart_tool/message-notification-modules-analyze.txt`。连同接入文件检查无错误或警告，保留 `ChatApp` 构造参数与既有 `showBadge` 参数两条原有风格提示，记录位于 `.dart_tool/message-notification-final-analyze.txt`。

Android debug APK 构建成功：`build/app/outputs/flutter-apk/app-debug.apk`，记录位于 `.dart_tool/message-notification-debug-build.txt`。Manifest、iOS plist/entitlements/PBX 文件及 Swift 注册静态核对通过。

早期扩大运行包含 `settings_99chat_flow_test.dart` 时有 3 项既有失败：两个账号安全页面与字体预览页面的测试未初始化 SDK `userID`。当前错误与 `.dart_tool/chat-modules-final-full-tests.txt` 旧基线同栈；不是通知功能新增问题，本次未修改无关页面。

## 尚需设备验收

Windows 没有 Xcode/Apple SDK，iOS 编译、Communication Notifications 签名 capability、头像与文本回复实际呈现需要 Mac 与真机确认。Android 13+ 通知权限及不同厂商的横幅展开手势需要对应设备确认；当前未安装此 APK 替换现有设备应用。

系统通知权限和频道设置决定横幅是否展示。实现处理的是应用已接收到的 SDK 消息；完全终止应用后的远程消息接收与通信头像还需既有推送服务及 iOS Notification Service Extension 联动，本次不宣称完成该场景。
