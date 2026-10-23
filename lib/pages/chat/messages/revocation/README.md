# 消息撤回

`ChatMessageRevocation` 由当前聊天创建，复用消息长按菜单和 OpenIM `revokeMessage`。对照 99chat `lib/src/chat.dart` 的 `isGroupAdminRecallEnabled` 入口；权限按 OpenIM 的群角色校验，不依赖三公业务特权或 `gameType`。

- 自己的成功消息继续保留两分钟限制。
- 点击时与确认后跨过两分钟时限均明确提示；确认后消息或权限变化也提示原因，不再直接退出。主动取消不视为失败；旧账号/会话已退出的迟到结果只记录日志，不向新页面弹出旧操作提示。

`chat_revocation_trace.dart` 将 `chat_revoke` 结构化事件以 Info（4）写入正式版原生 SDK 日志。每次点击生成独立 `operationID`，记录消息/会话/账号标识、序号、时间及耗时，并将同一编号传入 SDK 撤回调用，供关联原生 HTTP 日志。阶段包括 `click`、`confirmation`、`permission_check`、`sdk_call`、`request_result` 和 `stopped`；失败保留错误类型及 SDK 错误码，不记录正文、令牌或原始异常文本。`request_result` 的 `sdk_success/sdk_failed` 是 SDK 返回结果，失败可能发生在 HTTP 发出前，不能当成服务器已收到请求的证据。日志失败不影响撤回操作。
- 点击撤回先显示“确定撤回这条消息？”底部确认弹窗，取消、点遮罩或返回不提交。聊天通过 `confirm` 回调接入与删除共用的 `MessageActionConfirmationSheet`；确认期间阻止重复弹窗，确认后重新检查账号、会话、消息状态、时限及群权限。
- 群主可撤回普通成员、管理员消息；管理员只可撤回普通成员消息。
- 群主角色和群 ownerUserID 双重确认后，允许将已退群/被移除用户的历史消息提交 SDK 撤回，不再要求目标仍有成员记录。管理员对未知目标角色仍不放行；非空但账号/群不匹配的成员记录仍拒绝。
- 管理他人消息不套用客户端两分钟限制，最终时限和权限由当前 SDK/服务端裁决。
- 资金卡片、系统通知、已删除/过期/未发送成功消息不开放撤回；权限信息不完整时不推断授权。

菜单使用当前群控制器的角色快照。群控制器读取 SDK 完整群主/管理员名单，避免原来前 20 人的分页限制误判角色。角色、成员和群资料事件会更新菜单；点击管理撤回时复用 `ChatMemberActionSources` 查询最新群资料、双方成员及入群状态，复核后才提交。权限查询中发生成员变化则要求重新长按。退出、切换账号/令牌或会话后丢弃迟到结果，重复点击只提交一次。

只有 SDK 撤回成功后才清理原消息内容、引用和语音状态，并在原位置替换为撤回提示。收到 SDK `RevokedInfo` 时使用撤回人的昵称显示提示；自己撤回显示“你撤回了一条消息”。历史中的 SDK 撤回通知使用相同展示，当前账号缓存和迟到历史页也覆盖为不含原内容的提示。真正删除仍移除列表项，撤回不调用删除接口。失败保留原消息并给出简短提示。

删除和撤回共用 `messages/widgets/message_action_confirmation_sheet.dart` 的原生底部弹窗，颜色、取消按钮及安全区域沿用 Cupertino 的亮暗主题行为。长按菜单继续复用公共消息组件。测试位于 `test/pages/chat/messages/revocation/`，群角色实时更新测试位于 `test/pages/chat/group/chat_group_controller_test.dart`，菜单回调测试沿用 `chat_message_tile_test.dart`。真实部署的 SDK/服务端权限、时限及多设备回调仍需联机验收。

首屏撤回防闪：普通聊天的 `readChatLocalDisplay` 和本地备用读取统一使用带有效窗口证明的 `getLocalMessageWindow`，不再显示旧 `allowIncomplete` 快照。旧快照直接读取正文，可能遗漏持久化撤回覆盖，随后正式窗口替换时会闪现媒体。窗口无效或旧 SDK 不支持时等待正式历史；私密会话仍沿用原本的普通消息筛选。回归覆盖图片/视频首次进入、缓存重入，以及缺失/不完整/错误会话窗口。
