# 系统聊天通知的 iOS 通信头像

本目录只补充 iOS 通信头像和在途请求失效保护。Dart 的 `lib/core/notifications/` 负责通知权限、真实 SDK 消息、过滤、头像缓存、点击导航及回复发送；`flutter_local_notifications` 18.0.1 继续负责权限、分类和通知动作回调。现有 Firebase 和 Notification Service Extension 保持其原有职责。

## 调用契约

MethodChannel 为 `openim_chat_notifications`，由主 Flutter engine 的 `AppDelegate` 创建并持有。

| 方法 | 参数 | 行为 |
| --- | --- | --- |
| `setSession` | `sessionKey: String` | 激活账号与 token 摘要对应的非秘密 scope；更换 scope 立即废弃旧请求 |
| `clearSession` | `sessionKey: String?` | 提供 expected scope 时仅清理相同会话，避免旧退出清理新登录；不传则清理当前 scope |
| `invalidateNotification` | `sessionKey: String, id: int` | 点击、回复或取消前调用；废弃同 ID 在途头像请求，包括已经超过 Flutter deadline、仍等待 OS add completion 的请求 |
| `showCommunicationNotification` | 下表字段 | 等待本地图片处理、interaction donation 及系统 add，最多 2 秒 |

`showCommunicationNotification` 返回 `true` 表示已处理，**也包括已过期且被丢弃的请求**。返回 `false` 表示当前会话头像文件无效或通信内容处理失败，调用方可使用普通 FLN 通知及系统应用图标。缺少必填字段会返回 `INVALID_NOTIFICATION`。其他三个方法正常返回 `true`；`setSession` 空值返回 `INVALID_SESSION`。

| 字段 | 类型/默认值 | 来源 |
| --- | --- | --- |
| `id` | 非负 int，最大 Int32.max | 与普通 FLN 使用同一通知 ID |
| `sessionKey` | 非空 String | 账号 + token 摘要，禁止传原始 token |
| `conversationID` | 非空 String | SDK 会话标识；与 scope 组合为 thread/conversation identifier |
| `title`, `body`, `payload`, `categoryIdentifier` | String，必填，允许空字符串 | 已格式化的正文和 FLN 点击/回复内容；无回复能力时 category 为空 |
| `senderID`, `senderName` | String，ID 非空 | 真实消息发送人身份与名称 |
| `isGroup` | bool，默认 false | SDK 会话类型 |
| `groupMemberCount` | int?，群通信头像需 >= 2 | SDK 真实群成员数；包含 sender 与当前用户，仅后台头像更新时查询，禁止阻塞普通首发 |
| `senderAvatarPath` | String? | 单聊发送人头像的完整本地缓存路径 |
| `conversationAvatarPath` | String? | 群头像的完整本地缓存路径 |
| `alert` | bool，默认 true | 头像更新应传 false |
| `soundName` | String?，限 `chat_message_{preview000,crisp,soft,chime,preview,preview1,preview04}.wav` | 与设置试听和普通 FLN 通知一致的 Runner bundle PCM 音效；未知名称回落系统默认音 |
| `presentBanner`, `presentSound`, `playSound` | bool，默认 true | 与 alert 取 AND；alert=false 始终禁用声音及前台横幅 |
| `presentList` | bool，默认 true | 前台是否进入通知中心 |

额外 `recipientID` / `recipientName` 字段目前忽略。Apple 的 incoming communication 流程自动包含当前用户，不能把当前用户再次捐赠为 intent participant。

群使用真实 `groupMemberCount - 1` 作为 donation metadata 的完整接收人数，排除发送人；通过 `speakableGroupName` 设置群头像。人数缺失或小于 2 时返回 false，继续普通平台图标通知。若 sender/group 的头像路径相同，该图片只用作群头像，避免把群图标捐赠为个人头像。

先通过普通 FLN 立即显示通知，取得头像后使用同 ID 调用本接口并设置 `alert=false`。静默更新使用 nil sound、passive interruption level、关闭前台 banner/sound，保留通知中心呈现。调用方在点击/回复/取消之前立即调用 `invalidateNotification`，并在开始头像下载及返回后检查其通知版本，防止已处理通知重新出现。退出账号先 `clearSession`，再由 Dart 调用 FLN 的 cancel；本接口不承担已完成通知的统一取消。

## 生命周期与性能

- 本地头像在 utility queue 读取并解码，禁止原生下载 URL。仅接受绝对本地路径，编码文件上限 2 MiB，ImageIO 缩略到最长 128 px。
- 每个调用有 2 秒 deadline，只回复 FlutterResult 一次。过期 donation completion 删除其 interaction，不能显示通知；已经开始 OS add 的调用不触发重复 fallback。
- request generation、scope 与同 ID ticket 共同保护会话切换和迟到结果；失效后的 add completion 根据实际 notification content 的 `openimChatDeliveryTicket` 再检查归属，避免删除同 ID 的后继 native update 或普通 FLN fallback。
- 更换或清理 scope 时只删除本模块该 scope 的 Siri interaction group；迟到 donation completion 另按自己的 interaction ID 删除，避免影响新账号。
- `updating(from:)` 后恢复原 title/body/category/thread/userInfo/sound/interruption level，保持现有回复分类和 payload。
- `userInfo` 字段与 FLN 18.0.1 的 `buildUserDict` / `isAFlutterLocalNotification` / response extraction 对齐：`NotificationId`、`payload`、`presentAlert`、`presentBadge`、`presentSound`、`presentBanner`、`presentList`。插件升级必须重新核对该内部契约。
- 回复动作在 Dart 配置 Darwin foreground / Android showsUserInterface=true，系统文本框提交后唤醒现有 app/SDK；没有创建后台 Flutter engine 或独立 SDK 登录。

## 原生配置与验收边界

Runner 的 Info.plist 包含 `NSUserActivityTypes = [INSendMessageIntent]`，Runner.entitlements 启用 Communication Notifications，PBX Sources 已注册 bridge 文件。AppDelegate 将 UNUserNotificationCenter delegate 保持为 FlutterAppDelegate，通知动作由已注册的 FLN delegate 接收。

macOS 上还需确认 Xcode Runner 的 Communication Notifications capability 与 Apple 开发者账号、签名 provisioning profile 一致，并编译和真机验收。当前 Windows 环境没有 Xcode、Apple SDK 或 swiftc，无法证实 Swift typecheck、签名及 iOS 系统头像的实际呈现。现有工程最低 iOS 15，满足 communication notifications API 的系统版本要求。

Android Manifest 明确包含 POST_NOTIFICATIONS 与非导出的 FLN ActionBroadcastReceiver；插件版本 18.0.1，现有 compileSdk 35 满足其要求。运行时通知许可仍由 Dart 申请。当前在线设备为 Android 9/API 28 模拟器，Android 13+ 运行时许可及不同厂商系统横幅样式需要对应设备验证。

本功能处理 app 已收到的 SDK 消息。app 被完全终止时远程推送的通信头像需要服务端推送载荷及 Notification Service Extension 联动，不能由当前主 engine 的本地通知桥接保证。

2026-10-06：七种现有提示音已转换为 PCM WAV，存于本目录 `Sounds` 并在 Runner 的 PBX Resources 注册。Flutter 包中部分历史 `.wav` 文件实际上是 MP3；原生 bundle 使用转换后的 PCM，避免 iOS 回落默认音。前台振动通过现有 vibration 插件单独执行，UNNotificationContent 无独立控制静音通知振动的公开参数。声音类别和音频路由由现有应用/RTC 管理，通知模块不会重置通话 session。

## 官方接口依据

- [Apple：Implementing communication notifications](https://developer.apple.com/documentation/usernotifications/implementing-communication-notifications)
- [Apple：INSendMessageIntent](https://developer.apple.com/documentation/intents/insendmessageintent)
- [Apple：UNNotificationContent.updating(from:)](https://developer.apple.com/documentation/usernotifications/unnotificationcontent/updating(from:))
- [flutter_local_notifications 18.0.1](https://pub.dev/packages/flutter_local_notifications/versions/18.0.1)
