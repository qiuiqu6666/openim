# 聊天查看后返回列表仍显示未读的修复

## 问题与结论

聊天对话中收到并看过新消息后，返回会话列表仍显示未读数和徽标。问题在前端的阅读确认和会话列表状态更新链路；本次沿用 OpenIM SDK 的真实已读接口，不修改服务端。

已确认的原因：

1. `ChatListViewport` 已检测到真实绘制的消息，但聊天页只更新本页“新消息”提示，没有同步确认会话阅读。气泡另用 `FocusDetector`，其安装版本要求 `visibleFraction == 1`；高于屏幕的消息可能永远不满足条件，前台恢复也不保证重新触发该回调。
2. 原可见内容阅读排除了语音和通话，并且 `Message.isRead == true` 会直接返回。这些内容状态不能代替会话是否已经查看。
3. 原请求合并主要依赖正序号。序号为零或缺失的新消息在前一个请求期间到达，可能被合并掉。
4. 聊天页直接调用 SDK，列表依赖 SDK 的会话变更事件。变更缺失或延迟时，SDK 请求成功也没有及时更新列表；晚到的旧快照还可能恢复徽标。
5. 退出时的清理可能进入前一个请求的等待队列，随后页面关闭导致该请求不再发送。直接在离开后重放全会话清理，又可能清掉后来未查看的消息。
6. 消息回调可能早于会话预览回调。新消息已经显示并看过，但阅读目标仍捕获旧预览，返回后晚到的新消息会话快照不能匹配该确认。

第 6 项已用真实聊天控制器、真实会话控制器和真实列表视口复现失败：旧预览 A 的序号为 30，新消息 B 的序号为 0、时间相同；B 已显示并确认阅读，返回后才到达 B 的未读快照，旧实现仍显示未读。修复后该用例通过。

## 最终行为

- 聊天路由处于前台、最新消息实际进入可阅读区域时，调用 `markConversationMessageAsRead`；超高消息使用既有视口阅读判定。
- SDK 确认成功后，列表仅清理匹配阅读目标且未读数未超过确认范围的会话。首页会话页签使用同一列表，因此徽标同步更新。
- 消息 ID、序号、时间和已知消息数量共同保护阅读目标。会话预览晚到时，使用实际看过的消息，并保留原预览身份作为顺序依据。
- 语音的会话徽标可清除，语音是否已播放仍由播放或查看内容流程管理；查看私密语音列表不会启动燃烧。
- 读历史时，后来尚未看到的新消息保持未读。路由被覆盖、应用非活动状态、历史窗口尚未连接最新记录时不自动清会话。
- 退出前对已看过但尚未发送的最新目标立即发出最终请求，避免排队后关闭丢失；已经发送的确认按账号归属完成，不再向已关闭聊天页回写状态。
- 请求失败不清徽标；取消的请求不推进已读水位，同一目标重新可见后可以重试。

## 维护位置

| 路径 | 职责 |
| --- | --- |
| `lib/pages/chat/chat_logic.dart` | 接入真实视口、会话变更和账号归属，管理关闭前最终请求 |
| `lib/pages/chat/receipts/` | 会话阅读、内容阅读、请求合并及在途状态 |
| `lib/pages/chat/messages/widgets/chat_message_tile.dart` | 气泡保留资金内容可见性回调，自动阅读交给列表视口 |
| `lib/core/conversation_reads/` | 不可变 SDK 阅读目标、确认结果和晚到快照保护 |
| `lib/core/im_callback.dart` | 同步投递阅读请求，沿用既有 SDK 事件所有权 |
| `lib/pages/conversation/conversation_logic.dart` | 成功确认投影、会话事件合并、列表刷新与首屏种子保护 |

确认记录最多保存 256 个会话、每个会话 8 个目标，账号退出、列表清理和关闭时清除。聊天和会话主控制器只增加本功能的必要接入；具体责任放在已有回执目录和新的中性核心目录，不新增页面间循环引用。

## 参考与数据源

对照了工作区 99chat 的 `reference-99chat/lib/src/services/chat_entry_read_service.dart`：同步捕获阅读边界，已发送确认按账号归属完成，离开后不重放无边界的全清理；其 `test/chat_final_read_boundary_test.dart` 检查同时间不同消息的未读保护。

正式数据来自当前 OpenIM SDK、真实消息时间线和会话事件。当前 Flutter 插件为 `flutter_openim_sdk-3.8.3+hotfix.12`，会话已读接口仅接受会话 ID；本次未替换 SDK、消息同步、数据库或导航架构。没有新增界面、颜色或主题样式，亮暗主题显示逻辑沿用现有组件。

## 验证

测试覆盖：连续及零序号消息、同批去重、失败重试、已读消息仍清会话、语音与私密阅读分离、覆盖后恢复、关闭时在途请求、账号切换、晚到旧快照、较新消息及增加未读数的保护、首屏与列表刷新，以及真实绘制的超高消息。

关键入口：

- `test/pages/chat/receipts/`
- `test/pages/conversation/reads/conversation_read_projection_test.dart`
- `test/pages/conversation/editing/conversation_mark_read_test.dart`
- `test/pages/conversation/conversation_refresh_lifecycle_test.dart`
- `test/pages/chat/voice/chat_voice_controller_test.dart`
- `test/pages/chat/messages/chat_message_tile_test.dart`
- `test/integration/chat/chat_conversation_read_test.dart`
- `test/integration/chat/chat_entry_performance_test.dart`

组合回归 **141 项全部通过**，其中回执 33 项、会话确认投影 28 项、真实视口跨模块用例 6 项；还覆盖既有手动标已读、会话刷新、语音、消息行、聊天进入和滚动回归。运行日志：`build/chat-unread-return-tests-20261005.log`。

静态检查没有错误或警告；当前仍有 SDK 弃用、既有类型注解和聊天分支风格提示。私密消息逐条已读接口虽被插件标记为弃用，本次保留其既有私密内容阅读语义。调试 APK 构建成功，修复包复制后已再次校验哈希，最终工作区的上述组合回归再次通过。

修复包：[app-debug-chat-unread-return-20261005-0c693c2f958d.apk](../build/app/outputs/flutter-apk/app-debug-chat-unread-return-20261005-0c693c2f958d.apk)。SHA256：`0c693c2f958da4f6b65057eef83fee9495a3eb92ed6661e3a870f1356e861332`。此包包含同一工作区此前的修复；原有各版本修复包继续保留。

尚未验证 Android/iOS 真实设备连接服务器的回调时序及跨端阅读。界面集成测试使用原生方法边界的受控响应，不代表已做线上验收。遵照此前要求，只保留修复包，未安装、部署或重启服务。
