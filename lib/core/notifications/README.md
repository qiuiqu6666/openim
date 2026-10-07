# 系统消息通知

本模块负责已由 OpenIM SDK 接收的消息，使用 Android 系统 MessagingStyle 横幅和 iOS 系统通知。界面不创建 Flutter 浮层。

| 文件 | 职责 |
| --- | --- |
| `message_notification_runtime.dart` | 消息到达顺序、账号生命周期、通知版本、头像更新和动作排队的协调 |
| `message_notification_policy.dart` | 当前聊天、免打扰、隐私预览、消息类型及设置的纯展示判断 |
| `message_notification_preferences.dart` | 按账号读取通知开关、预览、声音、振动和快捷回复偏好 |
| `message_notification_sound.dart` | 设置试听与 Android/iOS 通知共用的七种声音标识和资源名称 |
| `foreground_message_alert.dart` | 前台消息声音与振动，单播放器、节流、可中断加载及安全的原生音频适配 |
| `notification_sound_activity.dart` | 来电、出站呼叫及账号退出时立即停止设置页试听的事件边界 |
| `message_notification_target.dart` | 严格校验点击/回复 payload；包含账号、登录摘要、会话及消息标识 |
| `message_notification_actions.dart` | SDK 未就绪时有界排队，校验目的会话，防止重复回复及跨账号操作 |
| `message_notification_avatar_cache.dart` | 异步获取小尺寸 PNG，失败保留平台图标，不等待下载后才显示横幅 |
| `system_message_notifier.dart` | flutter_local_notifications 平台适配、原生回复分类、权限及通信头像桥接 |

## 接入与行为

`AppController` 持有 runtime，`IMCallback.recvNewMessage` 转发 SDK 实时消息。当前正在打开的会话、自己发送的消息、正在同步的离线历史、typing/系统事件及免打扰会话不重复弹窗。群使用群头像，单聊使用会话头像或发送人头像，缺失或无效头像使用平台图标。匿名预览不会带头像或发送者身份。

同一会话的后续消息覆盖该会话通知；较早的异步查询、图片下载和取消操作不能盖掉或删除后来的通知。首发立即显示平台图标，头像随后使用同一 ID 静默更新。点击/回复立即使在途头像失效，防止已处理的通知重新出现。隐私设置在异步边界重新检查。通知设置修改后按账号同步发出变更事件，立即废弃原生在途头像并移除旧通知，覆盖 iOS 原生 donation 内无法调用 Dart 判断的时间窗口；语音/视频专用设置不会触发此清理。

点击通过现有 `AppNavigator.startChat` 导航，SDK 与主页未准备好时排队，避免冷启动导航被启动页覆盖。快捷回复使用 Android `RemoteInput` 和 iOS 文本动作；系统展开手势由设备控制，提交后唤醒现有应用并经现有 `ChatMessageSender` 发送。回复失败不自动重发，避免发送结果不确定时重复消息。该功能没有创建第二个后台 SDK 登录。

路由与前台恢复调用 `onSessionReady()`；真实 SDK 同步完成调用 `onSessionReady(authenticated: true)`。退出账号先 `invalidateSession()`；普通路由回调不能重新开启已经退出的同一登录身份。原生清理与新会话准备共享串行屏障，新消息不会被初始化清理误删。

通知设置存储前缀为 `99chat_settings_<accountID>_`，设置 store 绑定构造时的账号；退出、账号切换和销毁后不会把旧页面的迟到操作写给新账号。`notify_quick_reply` 与语音/视频快捷接听的 `notify_quick_answer` 独立。

前台横幅与消息声音/振动独立：横幅关闭或已在当前聊天时仍遵守「消息提示音」和「振动」开关，其他会话的系统横幅本身保持静音，避免双重提示。免打扰、历史同步、自己发送、typing/系统事件和活动通话继续过滤。foreground driver 每个异步边界重新检查账号、设置、前后台和通话归属；前台已经派发的提醒即使随后切后台，也不会再响一次原生声音。后台通知继续遵守闭屏开关、隐私和 SDK 的 allowBeep/allowVibration。

提示音选择同时接到试听、前台实际声音和后台原生通知。Android 使用 `chat_messages_v2_<soundID>_v*` 或 `chat_messages_v2_silent_v*` 频道，适应系统频道创建后声音属性不能直接修改的规则；七种声音转换为原生 PCM WAV 并放入 Android raw 与 iOS Runner bundle。iOS 普通 FLN 和通信头像路径都传同一白名单文件名。系统权限、静音模式和频道设置决定设备实际展示/响铃。

声音试听复用 foreground driver 的音频适配，不修改共享 RTC 音频 category，不在结束时停用共享 session；呼叫开始、后台、账号退出或页面销毁立即废弃加载并停止试听。来电选项由 [聊天来电偏好模块](../../pages/chat/calling/preferences/call_notification_preferences.dart) 与现有 OpenIMLive 管理；声音开关仅控制来电铃声，出站回铃保留。

## 原生配置与验证边界

Android 使用 FLN 18.0.1，Manifest 包含通知权限和动作接收器。iOS 头像采用通信通知，配置包含 Communication Notifications entitlement、INSendMessageIntent activity 与原生桥接文件；完整契约见 [iOS 说明](../../../ios/Runner/Notifications/README.md)。Mac 上仍需编译、确认 Apple 签名 capability，并在真机验收头像、横幅与文本回复；Windows 无法验证这些环节。

本模块不提供应用被完全终止后的远程消息接收。该场景继续由现有推送链路负责；远程通知头像与回复需要推送服务及 iOS Notification Service Extension 另行联动。

测试位于 `test/core/notifications/`，覆盖展示策略、严格目标校验、重复回调、账号切换、乱序查询、隐私变化、初始化并发、回复在途的新消息与原生平台参数。聊天入口的集成回归仍在 `test/integration/chat/chat_entry_performance_test.dart`。

## 高频接收

全局关闭提醒时在读取 SDK 会话前返回。同一会话共享进行中的元数据查询；跨会话最多 4 个查询并行，等待队列最多 128 个。队列超限时放弃最旧的待处理提醒，消息接收与 SDK 存储不受影响。相同会话按最后到达的消息展示，离线补发消息始终安静恢复。

不缓存已完成的会话免打扰结果，以便下一次提醒读取最新设置。账号失效时清除待处理提醒并阻止迟到结果展示；无法取消的 SDK 查询继续占用槽位直到结束，避免重登时再制造并发峰值。
