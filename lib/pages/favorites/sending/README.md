# 收藏发送

本目录只维护收藏发送的业务流程，不依赖页面 Widget，不持有聊天页面或 SDK listener。

- `favorite_prepare_lease.dart`：调用真实 `prepare-send`，在 `20063` 或本地租约过期时最多自动刷新一次；固定 `sendAttemptID` 和 `contentRevision`，由调用方先持久化新的请求 UUID。短时下载地址仅用于当前调用。
- 对应新增测试：`test/pages/favorites/sending/favorite_p0_contract_test.dart`。

现有兼容入口仍位于 `lib/services/favorite_message_adapter.dart`、`favorite_message_builder.dart` 和 `favorite_send_coordinator.dart`。本次只做 P0 协议适配，不在并行开发中移动这些公共入口或改动已有持久化键。协调器包含共享发送契约、账号隔离的任务 journal 和 SDK 提交状态机；后续迁移应先将共享发送契约归入 `lib/services/messaging`，再迁移 journal 和协调器，保留旧导出以同步所有调用方。

迁移及维护时必须保留：

- P0 仅支持 text、image、video、audio、file、note、link；复杂类型整条拒绝。
- SDK 提交前检查服务器双能力，并校验账号/会话代次。
- 先保存构造后的新消息 ID，再提交 SDK；部分成功只恢复剩余消息。
- 未知状态只查询既有消息 ID，不自动重新发送。
- 批次固定 ID 与既有任务的 alias 必须在返回确认结果前持久化。
- 私人收藏定位、下载 URL 和管理字段不进入发出的聊天消息；授权 URL 不写入发送 journal。

验证时使用 fake SDK、测试下载器和临时目录，不发送真实消息。发送回执、本地 SDK 查询及服务器能力应以真实对接时的响应为准。
