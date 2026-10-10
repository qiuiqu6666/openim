# 共享消息发送

`message_send_session.dart` 在发送相关异步操作开始前捕获当前 OpenIM SDK 账号、IM/Chat 令牌和服务地址；等待目标群资料或联系人选择后检查所有权，防止旧页面动作以新账号发送。它不保存或打印凭据，也不持有监听或计时器。

普通消息的 SDK 传输仍由 `../chat_message_sender.dart` 提供，聊天、转发、收藏、联系人推荐、分享和通知快捷回复共用该入口。APNs 提示与目标会话协议由公共包的 `APNsOfflinePushInfo` 工厂生成；未知群类型只发通用通知，消息仍按原 SDK 目标发送。通话在线信令由通话包单独管理。

真实 SDK 传输与账号切换测试位于 `test/services/messaging/apns/`；纯推送协议测试位于 `test/core/push/apns/apns_offline_push_info_test.dart`。平台与服务端合同见 [iOS APNs](../../../docs/ios-apns-push.md)。
