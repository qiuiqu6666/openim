# 会话首屏本地预取

`ConversationHistoryPrefetch` 持有可见会话注册和调度生命周期，`ConversationHistoryPrefetchItem` 复用项目的 VisibilityDetector，排除仅在列表缓存范围内构建的行。

- 停止滚动 150ms 后，每轮最多 8 个实际可见会话，两个并发读取，每个会话 40 条。
- 调用现有 ChatHistoryPrefetcher.warmLocal，只读本地 SDK；网络补齐仍由点击导航和聊天页负责。
- 页面覆盖、隐藏标签、后台、会话失效和销毁停止后续调度。无法取消的原生读取仍占据查询槽，避免超时后无限增加并发。
- SDK 的 MessageWindowCache 共享有界窗口，最多 8 个、30 秒过期，账号、令牌、版本化窗口及原有删除/撤回失效链继续生效。内存压力清空缓存并停止待调度会话。
- 不拼接会话预览与旧消息，不改动 SDK 持久化和连续性契约。进入页同步消费已有证明，未命中时异步读本地；200ms 后仍未就绪才显示文字提示。

聊天页无内存记录时会独立读取 SDK SQLite 的展示快照（`allowIncomplete: true`），因此应用重启后不必等最新窗口补齐才显示已有记录。快照仍须带原生 `localSnapshot` 标识且无错误，排除私密消息、删除记录和过期会话读取；不作为分页游标、完整窗口或同步完成依据。最新窗口及历史查询在后台继续，已完成的新结果不会被晚到的展示快照覆盖。没有本地记录时仍显示加载状态。

开启阅后即焚的会话被原生快照整页排除，因此展示读取改用既有 `OpenIMChatHistorySearchSource` 的本地查询（40 条、第一页），再逐条过滤私密消息，仅预显示可搜索的普通历史消息。完整消息类型和最新状态继续由后台历史读取接管。请求期间会话隐私状态变化、账号变化、清空或页面关闭均丢弃迟到结果。

测试：`test/pages/conversation/prefetch/conversation_history_prefetch_test.dart`、`test/pages/chat/history/chat_history_prefetcher_test.dart`、`test/pages/chat/history/message_window_cache_test.dart`。真实页面、窗口连续性和回执验证位于 `test/integration/chat/`。
