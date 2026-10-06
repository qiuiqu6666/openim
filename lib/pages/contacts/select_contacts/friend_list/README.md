# 好友多选页

`SelectContactsFromFriendsPage` 维护「我的好友」及添加群成员的好友多选列表。`carte` 继续交给既有个人名片选择器，`crateGroup` 继续交给既有建群选择器，不改变路由、选择动作或确认结果。

## 数据与展示

- 好友、搜索和分组继续使用 `SelectContactsFromFriendsLogic` / `FriendListLogic` 提供的真实 OpenIM 好友数据。
- 创建群聊与添加群成员隐藏 AI助理及其他官方账号，列表、搜索、全选、预选和提交共用动作对应的联系人选择策略。识别使用稳定用户 ID（包含 `assistant`、`99Message`、`99Pay`）及 `accountType == official` 用户资料，不按昵称判断，普通同名「AI助理」好友仍可选择。转发和名片选择继续保留现有助手账号行为。
- 搜索结果复制展示模型后重新计算分组首行，避免同一字母组的后续成员单独匹配时被悬浮分组盖住；不改变 SDK 原列表的分组标记。
- 第一行沿用 `ISUserInfo.showName`，保留备注、昵称和 ID 的现有优先级；长名称单行省略。
- 第二行复用通讯录的 `PresenceLabel`、`UserPresence` 和 `ContactsLogic.presence.users`，通过共享 `ContactPresencePolicy` 让官方服务账号始终显示在线；普通好友保持真实在线或最近上线时间。关闭在线状态展示、会话失效或普通好友尚无记录时保留空白副行。通知账号仍显示「仅接收通知」，保留选择限制。
- 状态字号、间距和亮暗颜色复用 `ContactCardPickerTokens`；行使用最小高度，由大字号文字自然撑开。
- 分组及索引尺寸也使用现有 `ContactCardPickerTokens` 的字号适配计算；索引根据可用高度及字母数量进一步约束字号，完整 A–Z / # 在小屏大字号下也不会越界。公共 `WrapAzListView` 通过可选参数支持，其他调用方维持原默认值。
- 保留 `ChatRadio`、搜索、全选、默认已选禁用、字母索引、底部已选列表和确认流程。
- 共享 `CheckedConfirmView` 保留普通字号的左右排布；按实际文字宽度判断小屏、大字号或长翻译是否需要上下排布，行高随文字增长并保留底部安全区，避免原先固定高度与横向空间不足造成溢出。

## 可见状态所有权

复用 `ContactCardPresenceVisibility` 的独立行所有权，检测滚动和搜索移除行。页面以 State 为 owner 调用 `ContactsLogic.setDirectoryPresenceVisible`，只登记当前可见好友，与勾选集合、全选无关。

路由覆盖、`TickerMode` 关闭、后台、关闭在线展示或会话失效时暂停页面批次；退出时只释放自身 owner，不改主通讯录的可见用户集合，也不创建新的状态服务或 SDK listener。控制器继续由已有 GetX binding 管理，页面不销毁共享控制器。

## 参考与验证

参考 99chat 的 `third_party/tencent_cloud_chat_uikit/lib/ui/widgets/contact_list.dart`、`ui/views/TIMUIKitGroupProfile/group_member/tui_add_group_member.dart` 和 `lib/src/create_group.dart` 中的姓名、状态两行列表。状态数据保持当前 OpenIM SDK / presence API 来源。

对应测试在 `test/pages/contacts/select_contacts/friend_list/`，覆盖亮暗主题、隐私、选中与搜索、可见用户批次、覆盖和后台恢复、释放、会话失效及小屏大字号。
