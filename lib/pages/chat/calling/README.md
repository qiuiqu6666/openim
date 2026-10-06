# 聊天通话入口

`ChatCallController` 集中聊天页的通话选择、直接语音/视频呼叫和忙碌状态读取。它通过明确的 getter 获取用户 ID、名称、单聊状态、关闭状态和现有 RTC 忙碌状态，并使用现有 `IMController.call` 发起通话。

模块沿用公共通话选择弹层、提示文本、OpenIMLive 和 SDK 信令流程，不拥有 RTC 连接。选择弹层返回时检查页面是否仍有效；页面负责提供涵盖关闭、退出账号和会话失效的 `isClosed`。

`preferences/` 读取 `99chat_settings_<accountID>_notify_quick_answer` 与 `call_ringtone_enabled`，设置保存后通过 `CallNotificationPreferences.notifyChanged(accountID)` 发布变化。`IMController` 持有唯一 `CallNotificationPreferenceBinding`，销毁时关闭；其他账号变化不会影响当前通话。公共包只接收 `IncomingCallPreferences`，不导入应用设置或存储。

快捷弹层、全屏、接听与拒接共用公共包的原 `SingleCallSession` 和期限。关闭快捷接听仍显示全屏接听入口，关闭来电铃声不停止出站回铃；设置更新、权限/接听开始、终态及退出账号使旧来电音频失效。后台在线邀请返回前台时读取原账号的来电偏好并展示入口，现有离线推送边界不变。

99chat 参考为 `notification_settings_service.dart`、`incoming_call_coordinator.dart` 和 `livekit_call_ringtone.dart`：来电静音只控制 incoming，禁用提示仍保留应用内接听入口。其 `notifyVibration` 仅用于消息/系统消息；本模块同样不新增来电振动。其快捷接听 key 已持久化但未接入来电显示，本次将该开关接入已有通话浮层。

测试归属 `test/pages/chat/calling/preferences/` 与 `ringtone/call_waiting_sound_controller_test.dart`，覆盖账号隔离、重复订阅释放、实际来电静音/异步装载取消、出站回铃保留、后台恢复、弹层接听/拒接与期限保持，全部通过本地模拟边界执行。
