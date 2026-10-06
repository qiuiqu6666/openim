# 会话摘要与提示

`conversation_latest_message_text.dart` 供主会话行、归档会话行和收件人最近会话预览复用。正文继续由现有 `IMUtils.parseNtf` / `parseMsg` 格式化；草稿解析、未读数和隐私占位仍由原调用方负责。

`conversationMentionTag` 只读 OpenIM 群会话的 `groupAtType`，分别处理 `atMe`、`atAll`、`atAllAtMe`，显示 `[有人@我]`、`[@所有人]`、`[@所有人][有人@我]`。这三个值是枚举状态，不按位混用；正常、公告、未知状态和单聊不产生 @ 提示。文案复用现有 `everyone` 和新增的中英文 `someoneMentionMe` 本地化键。

@ 提示独立于 `conversationPrefixTag` 的草稿/公告标签，以主题已有的 `Styles.c_FF381F` 红色展示；草稿和 @ 可同时显示，未读仍按原顺序保留。依据真实会话状态而非最后一条消息中的 @ 字符串，因此之后到来的普通消息不会覆盖尚未处理的提醒。它不新增历史请求、不发送已读回执，也不修改 SDK 会话状态。

清除沿用 `ChatLogic._resetGroupAtType` 及已有会话变更更新；手动已读与 @ 状态各自保持原 SDK 行为。原生端时序须在真实登录会话中联调。

测试位于 `test/pages/conversation/summary/`；亮暗实际 Widget 预览仅使用测试数据。

2026-10-05 验证：当前工作区的相关静态检查与独立提示规则测试通过。基于此前已验证的项目副本，叠加与工作区一致的本次代码后，48 项摘要/收件人预览回归测试、4 项亮暗主会话及归档行行为测试、2 项实际 Widget 预览导出全部通过。当前工作区完整编译受并行通话模块改动影响，因此整页测试运行在隔离副本；未进行真实登录的原生 SDK 联调。
