# 会话变化合并

`ConversationLatestSync` 补齐消息事件与会话元数据事件之间的缺口：普通/离线收消息使用现有 `receivedMessages`，共享发送器成功回执、通话记录成功写入和聊天退出使用公共包 `ConversationRefreshEvents`。这些事件只请求重新读取受影响的 SDK 本地会话，不拼造摘要、不修改消息正文、不增加未读数，也不发送第二次已读请求。AI 流式片段、正在输入和在线通话信令不参与。

定向读取按 120ms 固定窗口合并，同一目标仅查询一次，每批最多 64 个目标；通过 SDK 解析会话 ID，再用 `getMultipleConversation` 取得完整快照。读取失败静默保留当前列表，后续事件再触发，不轮询。查询期间到达的 SDK 回调、列表快照、置顶/静音操作或删除优先于该旧查询；删除清除对应待刷新项，清空/关闭使旧请求失效。事件核对账号、令牌和服务地址，不跨会话重放。列表仍通过已有删除屏障、已读投影和排序发布，归档和分组页共用这一份数据。

退出聊天的刷新使用账号身份判断：GetX 在调用 `onClose` 之前已经设置 `isClosed`，不能再用“页面仍打开”作为退出刷新的前提。产品行为参考 99chat 的 `ConversationSyncCoordinator.refreshConversationItem/patchConversationAfterChatLeave`，数据仍由 OpenIM SDK 提供。

回归：`conversation_latest_sync_test.dart` 覆盖合并、乱序查询、删除、清空、账号切换与失败；`test/integration/chat/chat_conversation_read_test.dart` 覆盖无会话回调的文字与退出后的本地通话记录，并验证未读与已读行为；发送器、通话写入器和真实首页导航测试分别验证触发入口及返回后的显示。

`ConversationUpdateBuffer` 只合并 SDK 会话元数据；每个会话 ID 保留窗口内的最后一次变化。实时窗口为 16ms，同步窗口为 80ms，固定时间发布，持续有消息也不会无限等待。消息正文的 SDK 接收、存储不经过这个缓冲。

读取会话分页时，入口立即记下变化以保护查询期间的新状态；同步结束主动发布，删除、清空和关闭时清理对应缓冲。置顶、免打扰写入完成前先应用积累的 SDK 快照，避免旧缓冲撤销用户操作。未读仍由 `ConversationReadProjection` 校准。

列表单次排序仍随总会话数增长；本模块降低重复次数，不承诺任意吞吐量。会话页一次遍历生成分组计数，隐藏的主页标签保留已构建子树和滚动位置，切回时重新读取当前数据。

测试：`test/pages/conversation/updates/`、会话恢复生命周期、删除屏障、已读投影与分组页面回归。

初次本地快照为空或读取失败时，普通登录的同步完成也必须重新读取 SDK 列表，不能仅在 `reInstall=true` 时读取。连续重复的同步完成回调不重复扫描；新的同步周期仍刷新。重连成功、回到前台时只对失败且没有正在读取的列表重试，继续遵守账号、token 和请求代次隔离。失败保留已显示会话，加载期间的实时变化仍合并到最新快照。产品行为参考 99Chat `conversation_sync_service.dart` 的同步结束恢复与重复结束事件抑制，保留本项目 OpenIM/GetX 数据链路。

未读的跨设备校准另由 [会话未读模块](../unread/README.md) 处理：SDK 总未读失配、正常前台恢复或真实重连时合并校准，继续使用本页的分页读取与增量合并，不新增轮询。

`test/pages/conversation/conversation_startup_recovery_test.dart` 覆盖普通同步恢复、结束事件先于页面构建、旧首屏响应、实时增量、重复结束、重连/前台重试及账号切换。Android 大列表的 `read-only file system` 则由原生 `io/openim/storage/OpenIMApplication` 的 SQLite 临时目录配置修复；客户端重试本身不能修复错误的文件路径。
