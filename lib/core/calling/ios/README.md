# iOS 系统通话

`AppController` 持有 `IOSCallKitRuntime`，`IMController` 将它提供给现有 `OpenIMLive`。普通 APNs 消息仍归 `core/push/apns`。

| 文件 | 职责 |
| --- | --- |
| `ios_callkit_platform.dart` | 独立 `ios_voip_callkit` 通道、原生事件和 VoIP 令牌元数据 |
| `ios_callkit_runtime.dart` | 当前账号归属、系统动作、已验证 SDK 邀请、音频激活和退出屏障 |
| `ios_call_invitation.dart` | 真实单聊邀请期限、收件人及原始邀请字段校验 |

`openim_live` 的 `SingleCallOwner` 和 `SingleCallMedia` 持有唯一通话会话和 RTC 房间。页面显示共享状态，系统接听无须页面挂载；权限、凭证、RTC 入房成功后才完成系统接听，随后等待 CallKit 音频激活并发布音轨。结束先释放旧媒体，再恢复全局音频设置。

`ios_voip_backend.dart` 负责独立 PushKit 令牌绑定、冷启动状态校验和取消/其他设备接听后的收尾；`../data/` 负责使用 Chat token 调用 `/calling/*` 和将现有 200–204 信令同步到服务端。普通 APNs 仍使用 IM token，两个令牌通道独立。

音视频离线推送遵守当前账户的「系统消息通知」总开关（`notifyWhenClosed`）。关闭时调用现有 `/calling/voip/unregister` 注销当前设备，开启时使用保留的 PushKit token 恢复注册。登录初始化、令牌更新和设置变化都检查该偏好；注册与注销串行执行，网络失败沿用 5 秒重试，退出时取消订阅和重试。设置按账户保存，操作仅作用于当前设备，不结束正在进行的通话。服务端确认注销前以及已经发出的推送仍存在送达窗口；不在原生 PushKit 回调中直接吞掉来电。

对照参考 99chat 的 `push_token_api.dart`、`livekit_call_api.dart` 与 `SelfHostedVoipCallKit.swift` 的独立令牌、服务端状态及昵称更新行为，复用当前 OpenIM 邀请、CallKit provider、SingleCallOwner 和 RTC 房间。未引入新的通话页面或主题组件。`ios_callkit_runtime.dart` 保留原有系统动作协调职责；新增网络流程集中在独立 backend 文件，避免把新业务继续堆入运行时。完整接口、旧客户端兼容范围和真机验证要求见 [接入说明](../../../../docs/ios-voip-callkit.md)。

测试位于 `test/core/calling/ios/`、`test/pages/chat/calling/system/`。

前台 SDK 来电通过 `IncomingSystemCallPolicy` 在原生主线程查询应用状态；未被 PushKit 上报的来电只使用现有应用内界面、铃声和 RTC 音频，不创建 CallKit 接听横幅。选择结果按本次来电固定，重复邀请和铃声共用同一结果。后台、锁屏或已存在的 PushKit 系统来电继续使用 CallKit，避免恢复前台时丢失系统接听和音频所有权。旧版 PushKit 回调仍必须向系统上报；已在后台发出的延迟推送不属于可直接忽略的前台 SDK 邀请。
`notify_quick_answer`（语音和视频通话用弹窗快捷接听）也参与离线推送控制：两个开关必须同时开启才注册 VoIP 推送；任一关闭均注销当前设备。快捷接听偏好通过独立的通话偏好事件同步设备绑定，不重复触发普通消息偏好事件。
