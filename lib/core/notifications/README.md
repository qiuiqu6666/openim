# 系统消息通知

## 2026-10-14 无声音／横幅排查

- 共用入口原先要求 `currentSdkStatus == syncEnded`，前台声音也使用相同的反向静音条件。已登录会话增量同步变成 syncStart/syncFailed 时，即便实时消息继续到达，也会同时丢弃横幅和提示音。已连接 Android 的通知权限为 granted，近期日志反复出现 syncFailed，与这条阻断路径一致；未把该设备证据推广为 iOS 真机验证。
- 改为记录当前账号和凭据的通知就绪状态。后续实机日志发现冷启动也可能一直 syncFailed，因此除同步成功外，当前登录会话完成认证资料与通知偏好加载也可放行，不再等待历史同步。同步（含 reInstall）和连接恢复不抹掉就绪状态；通知入口仍验证 SDK 登录、账号匹配、资料偏好就绪与路由。退出、踢下线、凭据失效和账号更换仍阻断。离线补发仍不重放旧提醒。
- 原生通知初始化失败时释放失败的 Future，下一次会话就绪或实时消息可重试，避免一次插件异常永久关闭提醒。
- Android `PushController` 每次读取新实例的默认 `PushType.none`，当前 FCM 登录不注册 token；这意味着被系统暂停/结束后的远程通知不能由本次本地通知修复保证。没有擅自启用 Firebase 或更改推送服务配置。iOS 有 APNs 注册与绑定代码，真实签名、token 绑定和服务端投递仍需独立验收。
- 通知还受账号本地偏好、旧偏好迁移、会话免打扰、全局接收选项和系统设置约束；完整用户资料拉取失败会阻止偏好就绪，此处保留隐私保护，没有默认绕过。正在打开的同一会话按产品规则不弹横幅；通话期间静音。声音资源和平台通知参数由现有测试覆盖。

验证记录：首轮 `E:/openim/artifacts/notification-audit-tests.log` 276 项通过；后续 `notification-followup-tests.log` 277 项通过，补充登录集成断言后 `notification-followup-session-tests.log` 20 项通过。Android debug APK 构建成功并覆盖安装到已连接安卓机，尚未完成真实新消息声音验收；iOS 未编译/安装。本机通知音量非零、铃声模式 NORMAL，通知开关均开启。

本模块负责已由 OpenIM SDK 接收的消息，使用 Android 系统标准标题/正文横幅和 iOS 系统通知。通知第一行显示用户昵称或群名称，第二行显示消息内容，不附加发送人标题、群副标题或正文发送人前缀。界面不创建 Flutter 浮层。

| 文件 | 职责 |
| --- | --- |
| `app_badge_coordinator.dart` | 按登录会话合并相同角标；服务端/系统分别串行，缓存平台能力，前台恢复系统角标，退出废弃待发任务 |
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

应用被完全终止后的 iOS 消息提醒由 [APNs 推送模块](../push/apns/README.md) 接入 Apple 远程推送；点击后复用本模块的会话就绪队列、收件人校验与 SDK 目的会话验证。接口、点击 payload 和签名要求见 [APNs 接入说明](../../../docs/ios-apns-push.md)。远程通知头像与回复仍需推送服务及 iOS Notification Service Extension 联动。

测试位于 `test/core/notifications/`，覆盖展示策略、严格目标校验、重复回调、账号切换、乱序查询、隐私变化、初始化并发、回复在途的新消息与原生平台参数。聊天入口的集成回归仍在 `test/integration/chat/chat_entry_performance_test.dart`。

## 高频接收

总未读角标由 SDK 回调和首页初次查询共用同一协调器；初次查询不得覆盖期间到达的新回调。相同数值（包含 0）仅在写入成功后去重，平台能力查询成功后缓存；请求在途只保留最新数值，服务端网络等待不阻塞系统角标。失败不写成功缓存，后续事件可重试，最短间隔 5 秒且不自行无限重试。实际 SDK 登录开始前建立归属，原生退出/替换账号前清理，旧请求返回不得确认新账号。回前台只补写可能被 APNs 改动的系统角标，不重复上传不变的数值。

全局关闭提醒时在读取 SDK 会话前返回。同一会话共享进行中的元数据查询；跨会话最多 4 个查询并行，等待队列最多 128 个。队列超限时放弃最旧的待处理提醒，消息接收与 SDK 存储不受影响。相同会话按最后到达的消息展示，离线补发消息始终安静恢复。

不缓存已完成的会话免打扰结果，以便下一次提醒读取最新设置。账号失效时清除待处理提醒并阻止迟到结果展示；无法取消的 SDK 查询继续占用槽位直到结束，避免重登时再制造并发峰值。

生产通知元数据查询使用 1 秒短缓存，上限 128 条；SDK 会话回调即时覆盖免打扰/资料信息，更新也可完成等待中的查询，旧查询结果不得覆盖回调。账号失效/关闭清理缓存。通知点击等需校验的动作仍直接查询最新数据。
