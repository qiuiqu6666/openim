# 聊天通话入口

## 备注展示

呼出、连接中、已接通、全屏来电以及小窗/PiP 中的对方名称，统一通过
`openim_common` 的 `ContactNameBuilder` 读取现有联系人备注；改名后立即更新，
清空后回退公开昵称。它只组合已有布局，不持有信令、RTC 或额外 SDK 订阅。
iOS 系统通话名称也使用同一只读接口解析，公开用户资料不再决定备注显示。
覆盖测试为 `test/pages/chat/calling/call_contact_remark_test.dart`。

`ChatCallController` 集中聊天页的通话选择、直接语音/视频呼叫和忙碌状态读取。它通过明确的 getter 获取用户 ID、名称、单聊状态、关闭状态和现有 RTC 忙碌状态，并使用现有 `IMController.call` 发起通话。

模块沿用公共通话选择弹层、提示文本、OpenIMLive 和 SDK 信令流程，不拥有 RTC 连接。选择弹层返回时检查页面是否仍有效；页面负责提供涵盖关闭、退出账号和会话失效的 `isClosed`。

`preferences/` 读取 `99chat_settings_<accountID>_notify_quick_answer` 与 `call_ringtone_enabled`，设置保存后通过 `CallNotificationPreferences.notifyChanged(accountID)` 发布变化。`IMController` 持有唯一 `CallNotificationPreferenceBinding`，销毁时关闭；其他账号变化不会影响当前通话。公共包只接收 `IncomingCallPreferences`，不导入应用设置或存储。

应用内语音/视频邀请直接显示全屏来电页，与 99chat 一致。移除了底部快捷接听弹层和“打开通话”中间入口；既有 `notify_quick_answer` 设置值保留兼容，但不再决定来电展示方式。全屏、最小化、接听与拒接共用原 `SingleCallSession` 和期限。关闭来电铃声不停止出站回铃；设置更新、权限/接听开始、终态及退出账号使旧来电音频失效。后台在线邀请返回前台时读取原账号的铃声偏好并显示全屏入口，现有离线推送边界不变。

99chat 来电展示参考 `lib/src/services/livekit_call_signaling.dart`、`livekit_call_navigator.dart` 与 `lib/src/pages/livekit_call_page.dart`（本地参考提交 `d7c3c655b20dd06458d1882b114e68c1c24133e3`）。铃声参考 `notification_settings_service.dart`、`incoming_call_coordinator.dart` 和 `livekit_call_ringtone.dart`：来电静音只控制 incoming，禁用提示仍保留应用内接听入口。其 `notifyVibration` 仅用于消息/系统消息；本模块同样不新增来电振动。

全屏邀请 UI 位于 `openim_live/lib/src/widgets/incoming_call/`，复用 `CallFullScreenSurface`、`AvatarView`、`LiveButton` 和现有图片加载器；独立维护布局与延迟背景解码，不持有信令或媒体。正常屏幕对齐 99chat 的 110px 头像、1/4 屏头像位置、2/3 屏提示、底部 50px 按钮区域与原图。小屏/大字体保留安全区并支持滚动。

测试归属 `test/pages/chat/calling/incoming/`、`preferences/`、`termination/` 与 `ringtone/call_waiting_sound_controller_test.dart`，覆盖全屏邀请、账号隔离、实际来电静音/异步装载取消、出站回铃保留、后台恢复、接听/拒接幂等与期限保持，通过本地模拟边界执行。真实双端音视频与系统来电界面仍需设备验收。
