# 频道

## 真实创建与目录（2026-10-22）

生产入口已接入 OpenIM：频道仍是 `GroupType.work`，通过群资料 `ex.conversationKind == "channel"` 区分。缺失该字段、未知值或无效 JSON 均按普通群聊处理，不改变 SDK 群类型。已有 `ex` 数据应合并保留，不得覆盖其他业务字段。

创建流程上传头像，通过 `createGroup` 提交名称、简介、选中联系人和 `status: 3`（全员禁言，群主与管理员沿用原群权限）。若返回状态不为禁言，会补充调用 `changeGroupMute` 后才进入真实聊天。每个创建流程保持稳定 groupID，超时重试先查询该 ID，已创建群只继续设置权限，避免重复建群。提交期间禁止重复操作，账号/令牌变化中止后续请求。临时头像文件上传后清理。

通讯录频道目录复用 GroupListLogic / GroupListPage 的真实分页、搜索、同步通知、重试与下拉刷新，仅显示频道标记的群；普通群聊目录排除频道。频道会话使用现有群聊消息、成员和设置能力。当前没有新增服务端专用频道类型、独立评论系统或公开频道发现接口；管理员仍能通过现有群设置修改禁言。尚未用真实账号执行创建验收。

下方为之前的 UI 预览说明；ChannelListPage、ChannelDetailPage 等保留用于预览测试，生产入口不再使用其中的本地数据和模拟操作。

入口：通讯录「频道」打开与「我的群聊」一致的目录，复用 SearchBox、GroupIndexedList 字母索引、空状态和列表尺寸；无预置示例频道。目录支持搜索、订阅人数、频道数量和创建入口。会话/通讯录加号菜单「创建频道」仍直接打开介绍和创建弹层。频道数据仅在当前路由保留，未接后端，不发送邀请或消息给其他人；选人使用已有真实联系人目录。用于索引显示的 GroupInfo 仅为展示适配，不调用群聊 SDK。

## 99chat 源码对照（2026-10-22）

本轮以 `E:/openim/reference-99chat` 的实际文件为基准，替换先前根据截图推测的页面。参考仓库记录的 HEAD 为 `d7c3c65`，使用其本地工作目录文件，未把截图与源码当作同一版本。

| 页面 | 99chat 来源 | 当前对应实现 |
| --- | --- | --- |
| 频道介绍 | `lib/src/pages/channel_intro_page.dart` | `create/channel_intro_page.dart`，原插画、双色标题、四个功能项、渐变按钮 |
| 创建流程 | `lib/src/create_group.dart`，`showCreateChannelSheet`、`_buildChannelForm` | `create/channel_create_flow.dart`、`channel_contact_picker.dart`、`channel_create_page.dart`；90% 高度、28 圆角弹层，选择联系人后填写资料，头像与名称必填 |
| 频道类型 | `lib/src/pages/channel_type_page.dart` | `settings/channel_type_page.dart`；公开/私密、邀请链接、顶部保存；移除截图版额外保存限制与撤销菜单 |
| 资料与设置 | `lib/src/group_profile.dart`，`_buildMobileChannelProfile`、`_openChannelSettings` | `detail/channel_profile_page.dart`、`settings/channel_settings_page.dart`；88 头像、分组卡片、54 高列表项、三项操作 |
| 更多菜单 | `third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitGroupProfile/widgets/tim_uikit_group_button_area.dart` | `detail/widgets/channel_more_menu.dart`；清空和退出/解散，图标底色、分隔线、弹出位置 |
| 管理员与订阅者 | `tim_uikit_group_manage.dart`、`group_member/tui_group_member_list.dart` | `members/channel_members_page.dart`；创建人/管理员分组，订阅者搜索和滑动移除 |

频道类型不再作为创建中的额外步骤；在频道设置中修改。选人直接复用现有创建群聊的 GroupContactPicker 和联系人加载逻辑，读取当前账号的真实联系人，保留选中用户 ID；仅创建本地频道预览，不发送邀请。联系人选择保存在创建弹层内，返回表单前一步时保持选中。相册仅读取本地图片，不上传。介绍和创建弹层挂在根导航器上，覆盖首页底部导航，关闭后恢复原页面。

复用现有 ChannelScaffold、ChannelSection、ChannelAvatar、AppTokens 和 Flutter 表单/菜单；ChannelScaffold 使用普通 AppBar 以匹配原仓库。新增创建流程容器用于弹层内路由，联系人选择页面和更多菜单各自独立维护，没有引入腾讯 IM 依赖或改变 OpenIM 消息链路。

`ChannelTokens` 和 `ChannelIntroTokens` 记录参考配色。正常亮色遵循源仓库；暗色接入现有主题，高对比度模式提高操作色和辅助文字对比度。原仓库部分固定浅色页面未照搬到暗色模式。默认参考蓝色和辅助灰并非所有组合均满足 WCAG 文本对比度，测试的对比度断言针对系统高对比度模式，不宣称默认配色通过全部对比度检查。

本轮对齐创建、资料、设置、类型和成员管理页面；消息列表/发布/评论仍为先前的本地功能预览，不是原腾讯 IM 聊天页面的逐像素移植。真实邀请链接、二维码、分享和转让创建人未接入，不伪造链接或执行真实联系人操作。资料数据、在线状态、后端加载状态无法与原仓库真实账号逐项比对。尚未进行原仓库与当前应用的同设备逐像素比对或 iOS 真机验收。

## 验证与资源

`test/pages/channels/channel_pages_test.dart` 覆盖创建校验、发布搜索、订阅评论、保存/取消、成员移除恢复、选择返回保持、搜索空态、小屏/大字、亮暗主题及高对比度。设置 `EXPORT_CHANNEL_PREVIEW=1` 可导出 `docs/previews/channels/` 的页面截图。通讯录创建入口另有对应回归测试。

插画 `assets/images/channel_intro_99chat.png` 和介绍页布局改编自 99chat（https://github.com/qiuiqu6666/99chat，Apache-2.0）；许可见 `THIRD_PARTY_LICENSE.txt`。所有本地状态归 ChannelListPage 所有，离开销毁。后端阶段需要仓储、权限校验、分页、错误/离线状态和账号生命周期管理。
