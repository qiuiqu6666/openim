# 最近会话预览

此目录维护收件人选择页 `SelectContactsPage` 中的最近会话摘要。继续使用现有 `SelectContactsLogic.conversationList` 的收件人范围与群成员校验，勾选、确认及路由保持原流程。

## 展示与复用

参考 99chat 的 `third_party/tencent_cloud_chat_uikit/lib/ui/widgets/recent_conversation_list.dart` 中 `RecentForwardList` / `TIMUIKitLastMsg` 的名称、13 号弱色单行摘要。根据用户要求，本地还保留与主会话列表一致的未读和草稿前缀。

名称下方显示 `[未读条数] [草稿]正文`；没有草稿时显示实际最后消息，群聊保留发送人前缀。相邻会话之间使用现有联系人主题 Token 的细分割线，与文字区域对齐，首尾不额外画线。草稿复用 `conversationDraftText` 解析纯文本或输入框信封，未读来自真实 `unreadCount`，不读取历史、不清除未读、不发送已读回执。已有群公告前缀也沿用主会话列表规则。

摘要按未读、前缀、正文分段绘制，真实草稿状态的 `[草稿]` 前缀沿用主会话列表的 `Styles.c_FF381F` 红色，未读与正文保持主题次级文字颜色。普通消息正文即使包含 `[草稿]` 也不会误染；分段数据与原有纯文本摘要共用同一套安全过滤和生命周期校验。

群聊 @ 提示复用主会话列表的 `conversationMentionTag`：由 SDK 会话的 `groupAtType` 三种明确状态显示 `[有人@我]`、`[@所有人]` 或两者。它独立于草稿前缀，使用同一红色，并且不会被后来的普通消息覆盖。正常、公告、未知和单聊状态不产生 @ 提示；清除继续由已有聊天入口和 SDK 会话变更负责。

`conversation/summary/conversation_latest_message_text.dart` 共享原有 `ConversationLogic` 的消息格式与前缀规则；主会话列表继续保持原有草稿优先行为。头像、勾选框、底部确认栏、主题及文字尺寸分别复用 `AvatarView`、`ChatRadio`、`CheckedConfirmView`、`ContactCardPickerTokens`。行采用最小高度和自然布局，亮暗主题、小屏及大字号使用同一结构。

## 数据与生命周期

`RecentConversationPreviewController` 由现有选择控制器按需创建并在关闭时释放。只从共享 `ConversationLogic.list` 查找同一会话的最新对象，保持可选择对象不变；共享列表移除会话后不回退旧摘要。读取还校验创建时账号、chatToken 和共享源的有效登录会话，避免使用失效账号数据。

撤回、删除沿用已有 `IMController` 广播与 `ChatHistoryCache` 删除标记；本模块只订阅既有广播以更新摘要，关闭时取消自身订阅，不新增 SDK listener。私密消息及嵌套引用/合并消息的私密内容复用 `ConversationPeekLoader.containsPrivateContent` 判断，只展示占位；私密会话草稿也仅展示占位。过期和撤回消息不展示原正文。

`recent_conversation_preview.dart` 负责安全摘要和展示前缀，控制器负责共享状态更新和订阅所有权。没有消息时保留空副行，未读与草稿状态仍按真实数据展示。正式数据仅来自当前 OpenIM 会话及草稿，测试数据只用于测试与预览。

测试位于 `test/pages/contacts/select_contacts/recent_conversations/`，包括消息摘要、前缀、实时更新、账号和隐私隔离、选择确认、亮暗主题及小屏大字号。

多人转发确认继续使用 `ForwardHintDialog`。昵称网格的高度按真实字体、字号缩放及昵称测量，避免原来按字号估算导致的轻微溢出；取消和确认操作使用标准 `OverflowBar`，中英文在小屏大字号下可自然换行，流程保持原样。分类入口的长文案也采用单行省略。

亮暗主题与 320px / 200% 字号的实际 Widget 预览位于工作区 `.temp/recent-conversation-preview/`，仅使用测试数据。相关会话摘要及联系人选择回归共 79 项通过（含 4 项实际预览导出）；新增摘要、页面和测试静态分析通过。尚未在真机上联调。
