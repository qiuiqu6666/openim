# iOS 系统通话

`AppController` 持有 `IOSCallKitRuntime`，`IMController` 将它提供给现有 `OpenIMLive`。普通 APNs 消息仍归 `core/push/apns`。

| 文件 | 职责 |
| --- | --- |
| `ios_callkit_platform.dart` | 独立 `ios_voip_callkit` 通道、原生事件和 VoIP 令牌元数据 |
| `ios_callkit_runtime.dart` | 当前账号归属、系统动作、已验证 SDK 邀请、音频激活和退出屏障 |
| `ios_call_invitation.dart` | 真实单聊邀请期限、收件人及原始邀请字段校验 |

`openim_live` 的 `SingleCallOwner` 和 `SingleCallMedia` 持有唯一通话会话和 RTC 房间。页面显示共享状态，系统接听无须页面挂载；权限、凭证、RTC 入房成功后才完成系统接听，随后等待 CallKit 音频激活并发布音轨。结束先释放旧媒体，再恢复全局音频设置。

后端尚无独立 VoIP 令牌接口、VoIP 发送或实时邀请状态查询。客户端只保存 PushKit token 到内存，不上传到普通 APNs 位置，也不访问参考仓库的 `/me/voip-push-token`、`/calls/livekit/status/*`。推送 payload 不能自行恢复可接听通话；需要当前账号真实、未结束的 SDK 邀请。完整服务端缺口与原生/真机检查见 [接入说明](../../../../docs/ios-voip-callkit.md)。

测试位于 `test/core/calling/ios/`、`test/pages/chat/calling/system/`。
