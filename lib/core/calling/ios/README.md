# iOS 系统通话

`AppController` 持有 `IOSCallKitRuntime`，`IMController` 将它提供给现有 `OpenIMLive`。普通 APNs 消息仍归 `core/push/apns`。

| 文件 | 职责 |
| --- | --- |
| `ios_callkit_platform.dart` | 独立 `ios_voip_callkit` 通道、原生事件和 VoIP 令牌元数据 |
| `ios_callkit_runtime.dart` | 当前账号归属、系统动作、已验证 SDK 邀请、音频激活和退出屏障 |
| `ios_call_invitation.dart` | 真实单聊邀请期限、收件人及原始邀请字段校验 |

`openim_live` 的 `SingleCallOwner` 和 `SingleCallMedia` 持有唯一通话会话和 RTC 房间。页面显示共享状态，系统接听无须页面挂载；权限、凭证、RTC 入房成功后才完成系统接听，随后等待 CallKit 音频激活并发布音轨。结束先释放旧媒体，再恢复全局音频设置。

`ios_voip_backend.dart` 负责独立 PushKit 令牌绑定、冷启动状态校验和取消/其他设备接听后的收尾；`../data/` 负责使用 Chat token 调用 `/calling/*` 和将现有 200–204 信令同步到服务端。普通 APNs 仍使用 IM token，两个令牌通道独立。

对照参考 99chat 的 `push_token_api.dart`、`livekit_call_api.dart` 与 `SelfHostedVoipCallKit.swift` 的独立令牌、服务端状态及昵称更新行为，复用当前 OpenIM 邀请、CallKit provider、SingleCallOwner 和 RTC 房间。未引入新的通话页面或主题组件。`ios_callkit_runtime.dart` 保留原有系统动作协调职责；新增网络流程集中在独立 backend 文件，避免把新业务继续堆入运行时。完整接口、旧客户端兼容范围和真机验证要求见 [接入说明](../../../../docs/ios-voip-callkit.md)。

测试位于 `test/core/calling/ios/`、`test/pages/chat/calling/system/`。
