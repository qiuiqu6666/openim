# 个人名片好友选择器

此目录维护聊天「个人名片」入口的单好友选择页。界面参考本地 99chat 的实际手机页面，数据和发送流程继续使用当前 OpenIM 模块。

## 入口与发送流程

`ChatForwardingController.onTapCard()` 收起聊天更多面板，再调用 `AppNavigator.startSelectContacts(action: SelAction.carte)`，携带当前会话的接收人名称、头像和群聊标记。

`SelectContactsPage` 的 `carte` 分支直接构建 `ContactCardFriendPicker`；不经过「我的好友 / 我的群聊 / 最近会话」分类页。`SelectContactsFromFriendsPage` 的同一分支也复用此选择器。其他选择动作继续使用原有页面。

选择器点击好友时先关闭键盘，再调用 `SelectContactsLogic.onTap(friend)`。发送确认仍由 `confirmSelectedItem()` 和公共 `ContactCardSendDialog` 处理；确认后返回真实 `UserInfo`，取消确认保留选择页。`_confirmingCard` 防止重复打开确认，现有关闭检查继续生效。页面返回和搜索右侧「取消」退出选择流程，不创建消息。

返回聊天页后沿用 `sendCarte()`：`createFriendCardExtension(userID)` 调用现有 `Apis.createFriendInvite(FriendAddSource.card, targetUserID: userID)`，把 `inviteCode` 写入扩展，再使用 OpenIM `messageManager.createCardMessage` 和原有发送链路。接收名片后添加好友的 invite / grant 校验继续由现有 `FriendAddRequest`、API 和后端负责。选择器不另建发送服务或授权规则。

## 文件职责与复用

| 文件 | 职责 |
| --- | --- |
| `contact_card_friend_picker.dart` | 页面、搜索输入、分组列表、路由和应用生命周期、presence 所有权 |
| `contact_card_friend_directory.dart` | 从真实好友创建搜索和分组投影，不修改源列表 |
| `contact_card_friend_row.dart` | 好友行、头像、在线点、状态副标题、星标和点击回调 |
| `contact_card_presence_visibility.dart` | 可见行变化与行移除通知，筛选移除行时释放可见状态 |
| `contact_card_picker_tokens.dart` | 参考尺寸、文字样式、亮暗主题和大字体高度计算 |

页面复用公共 `SearchBox`、`AvatarView`、`GlassAppBar`、`directoryIndexBarOptions`，以及已有 `AzListView`。状态副标题复用联系人模块的 `PresenceLabel` 和 `UserPresence`，通过 `textStyle` 参数使用本页的 13 号 / 1.25 行高。发送确认复用现有 `ContactCardSendDialog`。

## 真实数据与搜索投影

`SelectContactsFromFriendsLogic.friendList` 提供真实 SDK 好友。进入 `carte` 时可先从当前会话有效的 `ContactsLogic.friends` 复制已有目录，随后仍由 `FriendListLogic` 的 SDK 分页查询和好友变化事件维护；SDK 查询保留 `filterBlack: true`。

星标来自 `ContactsLogic.stars.records`；在线和最近上线时间来自 `ContactsLogic.presence.users`，继续使用现有 SDK 在线订阅、presence API、本地账号缓存及展示隐私。行通过共享 `ContactPresencePolicy` 为官方服务账号提供始终在线的展示状态，普通好友保持原隐私规则。页面遵从 `FriendDisplayPreferences.showOnlineStatus`；在线点使用解析后的 `UserPresence.displayOnline`。

`buildContactCardFriendDirectory()` 跳过空 ID、按 ID 去重，并为匹配的好友创建 `ISUserInfo` 副本。`tagIndex`、`isShowSuspension` 等展示字段只修改副本，搜索、星标分组和字母索引不改变 SDK 源列表，也不改变主通讯录分组。

搜索 trim 后忽略大小写。99chat 此页匹配显示名或用户 ID；本地保留现有备注、昵称和拼音兼容，匹配 `showName`、`nickname`、`userID`、`namePinyin`、`pinyin` 和 `shortPinyin`。`showName` 保持当前 OpenIM 的备注 → 昵称 → 用户 ID 优先级。缺少索引时复用 `IMUtils.setAzPinyinAndTag`。星标按记录更新时间倒序，时间相同时保留源顺序；普通好友按 A–Z 分组，`#` 最后，同组保留已有源顺序。

无查询且无好友显示「暂无联系人」；有查询无结果显示「未找到相关联系人」。页面没有多选圆点、全选、底部确认栏、主通讯录功能入口或联系人数量页脚。

## Presence 所有权与生命周期

选择器只维护当前可见行的用户 ID 集合，以 State 实例作为独立 owner，调用 `ContactsLogic.setDirectoryPresenceVisible(owner, ids)`。此接口以 120 ms 合并批量变化，不修改主通讯录的可见 ID 集合。

- 非空集合：订阅当前选择器可见好友。
- 空集合：保留 owner 并暂停选择器订阅。路由被覆盖、`TickerMode` 停用、应用不在前台、账号会话失效或关闭在线展示时使用此状态。
- `null`：释放该 owner。选择器 dispose 时调用，恢复其他目录 owner 或主通讯录订阅。

订阅优先级为：前台时最新详情页 owner 的单个用户 → 最新目录 owner 的集合 → 主通讯录可见集合；应用后台暂停订阅。详情页关闭后恢复目录 owner；释放一个目录 owner 只移除它自身，不能删除主通讯录中相同好友的可见状态。

行包装器在被搜索筛除或卸载时主动报告不可见，避免旧行继续刷新。页面 dispose 释放 owner、偏好监听、应用生命周期监听、搜索控制器和焦点节点。`ContactsLogic.onClose()` 取消批量计时器、清除目录 owner 并释放 SDK 订阅；关闭或会话失效后的目录更新不会建立新订阅。

## 参考尺寸与主题

所有尺寸集中在 `ContactCardPickerTokens`，默认按逻辑像素记录手机规格。

| 项目 | 规格 |
| --- | --- |
| 页标题 | 「选择朋友」，居中，17 / w600；返回图标使用 accent `#1E90FF` |
| 搜索 | 外边距 `(16, 8, 16, 12)`；最小高 44；字号 15、行高 1.2；圆角 10；搜索图标 18 |
| 取消 | 字号 16；与搜索框间距 10；点击退出页面 |
| 好友行 | 最小高 64；圆头像 44；水平边距 16、垂直边距 8；头像到文字 12 |
| 姓名 / 状态 | 16 / w500 和 13 / w400；行高 1.25；两行间距 4；单行省略 |
| 分隔线 | 厚 0.6，左侧起点 72；亮色 `#0F000000`、暗色 `#14FFFFFF` |
| 分组 / 索引 | 分组最小高 32、左 16、字 12；星标组显示 `★`；索引字 11、弱色透明度 0.8、每格 16 |
| 星标 | `Icons.star`，18，`#F4B400`，左间距 8 |
| 在线点 | 12，右 / 下偏移 −1.5，白边 2，绿色 `#4CAF50` |
| 未知状态 | 保留 13 号副标题行高；骨架 64 × 10、圆角 4、弱色透明度 0.22 |
| 空态 | 居中 14 号弱色文字 |

好友行、分组和搜索框高度结合 `MediaQuery.textScalerOf` 增长。页面使用 `SafeArea(top: false)` 保留底部安全区；搜索不自动获取焦点，取消和点选会关闭键盘。

| 颜色 | 亮色 | 暗色 |
| --- | --- | --- |
| 页面 / 分组背景 | `#FFFFFF` | `#101114` |
| 联系人行背景 | `#FFFFFF` | `#1B1D22` |
| 搜索填充 | `#F1F3F5` | `#1B1D22` |
| 主文字 | `#1C1C1E` | `#F4F4F4` |
| 副标题 / 提示文字 | `#7B8491` | `#9A9CA3` |

颜色通过 `AppTokens` 和主题获取。在线文字继续使用弱色；在线点提供头像上的状态提示。

## 来源与验证位置

参考仓库 revision：`d7c3c655b20dd06458d1882b114e68c1c24133e3`（Apache-2.0）。实际页面与组件为：

- `lib/src/pages/contact_card_user_picker_page.dart`
- `lib/src/widgets/contact_style_search_bar.dart`
- `lib/src/widgets/contact_list_with_presence.dart`
- `lib/src/ui/components/app_search_bar.dart`
- `third_party/tencent_cloud_chat_uikit/lib/ui/utils/directory_list_style.dart`
- `third_party/tencent_cloud_chat_uikit/lib/ui/widgets/az_list_view.dart`、`avatar.dart`
- `lib/utils/theme.dart` 与 `lib/src/ui/app_tokens.dart`

参考只用于界面结构和交互参数。真实用户、好友关系、账号规则、名片协议与发送授权属于当前 OpenIM 和后端实现。本模块不增加图片资源。

页面回归位于 `test/pages/contacts/select_contacts/contact_card/`；订阅所有权回归位于 `test/pages/contacts/directory/contact_picker_presence_owner_test.dart`。维护时检查真实 `carte` 入口、搜索 / 清空 / 取消、分组和源列表隔离、确认返回、亮暗主题、大字体、键盘、路由覆盖 / 恢复、后台 / 前台、在线偏好切换和关闭释放。验证结果由任务实际执行记录提供。

`AzListView` 底层以列表位置复用行。搜索或星标排序可能让同一好友先后位于不同位置，因此可见报告按行实例持有，页面再合并好友 ID；旧行卸载仅移除自己的报告。每个行实例使用独立的 `VisibilityDetector` key，卸载时调用 `forget` 清理检测缓存，避免旧行覆盖新行可见状态或缓存跳过新行回调。好友行使用最小高度约束，实际字体度量可以自然撑大；字母索引项高度跟随文字缩放。
