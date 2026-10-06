# 聊天模块维护入口

普通消息气泡默认显示 Markdown，文字源、格式解析和主题样式集中在公共包 [Markdown 气泡模块](../../../openim_common/lib/src/widgets/chat/markdown/README.md)。消息行继续通过已有匹配回调打开链接和成员资料，复制保留 Markdown 源文本；发送、草稿、历史及转发继续使用原 SDK 消息。

聊天按功能组织，页面入口仍为 `chat_view.dart`、`chat_logic.dart`、`chat_binding.dart`，原有路由和 GetX 标签保持兼容。

`ChatLogic` 负责创建本次会话的功能控制器、接收页面级 SDK 事件、协调功能和关闭资源。输入、历史、语音、资金等状态由各功能控制器实际持有，主入口的同名 getter / 方法仅作兼容代理。新功能进入对应目录，不再追加到主控制器。

| 目录 | 实现入口 | 职责与资源归属 |
| --- | --- | --- |
| `history/` | `chat_timeline_controller.dart`、`chat_history_loader.dart`、`chat_history_prefetcher.dart` | 消息窗口、SDK 首批预读与缓存、分页、同步刷新、时间分隔、删除记录和缓存计时器 |
| `scrolling/` | `chat_new_message_tracker.dart` | 实时新消息 ID 去重、尚未看到的数量、离底提示状态；位置和可见行测量复用公共 `ChatListView` |
| `receipts/` | `chat_read_receipts.dart`、`conversation_read_coordinator.dart` | 真实视口会话阅读、私密消息逐条回执、消息身份与未读快照请求合并、SDK 成功确认桥接、回执刷新计时器 |
| `composer/` | `chat_composer_controller.dart` | 输入与焦点资源、串行草稿、引用、@成员、定向成员、格式化编辑；`mention_id.dart` 为共用的提及 ID 解析 |
| `messages/` | `chat_delivery_controller.dart`、`chat_message_actions.dart` | 发送状态、失败提示、撤回删除策略；`selection/` 为当前聊天多选、长按滑选与操作栏，`forwarding/` 为单条/批量/合并转发及名片，`presentation/` 为消息显示策略，`widgets/` 为消息行渲染 |
| `media/` | `chat_media_controller.dart`、`chat_picture_gallery.dart` | 相册、相机、文件、位置、音频文件选择和临时附件准备；音频转文字预览交给语音模块 |
| `voice/` | `chat_voice_controller.dart` | 录音、播放、转文字、预览、本地扩展字段串行写入和任务取消；服务与转写状态在本目录维护 |
| `stickers/` | `chat_sticker_controller.dart`、`personal_sticker_store.dart` | 表情上传、收藏重试、个人表情存储/管理、图片与视频表情发送及展示 |
| `favorites/` | `chat_favorites_controller.dart`、`favorite_picker_sheet.dart` | 聊天收藏与选择器、收藏发送与恢复适配；收藏数据与发送日志仍由共享收藏服务持有 |
| `fund/` | `chat_fund_controller.dart`、`fund_message_card.dart` | 聊天资金卡片的可见性刷新、显示状态、打开页面；订单业务仍属于 `lib/pages/fund/` 及资金服务 |
| `group/` | `chat_group_controller.dart`、`chat_group_sources.dart` | 群资料、成员、权限、禁言、群事件订阅；`announcements/` 管理聊天页公告展示 |
| `navigation/` | `chat_message_navigation.dart` | 消息中的资料、链接与提及 ID 导航 |
| `calling/` | `chat_call_controller.dart` | 现有通话入口、忙碌判断和弹层回调保护 |
| `appearance/` | `chat_appearance_controller.dart` | 字体比例和本地背景解析；共享背景持久化仍使用现有服务 |
| `chat_setup/`、`group_setup/` | 原有 binding / logic / view | 会话与群设置页面，保持现有独立子模块 |

公告发布仍由 `group_setup/group_announcement_page.dart` 调用现有 SDK `setGroupInfo`；`group/announcements/group_announcement_error_message.dart` 将已知 SDK 网络超时、网络失败和权限错误转换为短文案，未知错误使用公告发布失败提示，完整诊断只进入日志。失败保留编辑草稿，提交期间保持单次请求和退出保护；成功后才更新群资料并返回。聊天公告栏的前缀与关闭区按可用宽度约束，正文继续使用原跑马灯和展开流程。全局提示尺寸保护归 `openim_common/lib/src/widgets/feedback/`，不在公告模块复制 Toast。

## 数据与依赖边界

- 消息、群状态和回执仍来自 OpenIM SDK；本次不替换消息链路或 GetX。
- 功能控制器只接收所需的列表、只读 getter、事件源或回调，不依赖整个 `ChatLogic`，不通过 `part` 或扩展共享私有状态。
- 消息行 Widget 使用 `ChatLogic` 的公开页面接口。主逻辑不反向依赖该 Widget。
- `lib/services/chat_history_cache.dart` 由聊天、会话、SDK 回调及退出清理共享，保留共享归属。公共消息协议、语音转写状态和公共组件仍在 `openim_common`。
- 收藏业务页、收藏发送契约与共享服务的后续拆分仍按 [模块规范](../../../docs/module-organization.md) 单独处理，聊天选择器当前沿用已存在的公开列表复用关系。

图片对象地址兼容集中在公共包 `utils/media/openim_media_url.dart`。服务端历史消息中的 loopback `/object/…` 地址在显示、图库、保存入口使用当前 `Config.imApiUrl` 解析，支持反向代理路径前缀；SDK 消息及收藏授权地址保留原值。缩略图转换保留带认证或其他业务参数的原链接，避免删除签名。存储清理同时查找原地址和兼容地址的缓存键。对应回归测试位于 `test/utils/media/`、`test/pages/chat/media/chat_picture_gallery_test.dart` 和 `test/storage_media_repository_test.dart`。

三公业务 API 的 `10008/sangong/api/v1` 与 OpenIM 对象服务的 `10002` 独立配置。前端兼容旧链接之外，上传服务应返回可被终端访问的公共对象 URL；当前 OpenIM 官方实现优先用上传请求的 `X-Request-Api`，否则从 Host/TLS 生成 `/object/` 前缀，部署修复需核对实际服务端版本及代理配置（[官方实现](https://github.com/openimsdk/open-im-server/blob/main/internal/api/third.go#L55)）。

## 生命周期

导航开始时提前读取 SDK 本地首批历史。进入时先捕获会话账号和令牌，初始化安全消息快照，再初始化输入和页面订阅并复用预读请求。群资料在首批历史之后加载，不阻挡聊天内容显示；资料尚未就绪时群成员入口等待权限信息。

关闭时，各控制器关闭自己的队列、计时器、播放资源、输入资源和订阅。页面只在回调仍属于自己时清理 SDK 消息/回执/通话回调，避免旧页面清掉新页面的订阅。最终草稿和历史快照可以保存；账号或令牌变化后，旧页面不能向新账号保存草稿、发送消息或发起媒体预览。

通话浮层由全局 `OpenIMLiveClient` 持有，离开当前聊天页不会误挂断。单聊连接、媒体资源清理、后台行为和系统 PiP 见 [通话模块](../../../openim_live/README.md)；[首轮验证记录](../../../docs/calling-first-round-validation.md) 区分已通过的本地检查和待真机验收的能力。

历史模块保留私密消息过滤、缓存世代、删除记录、SDK 游标与迟到结果保护。清空/撤回/删除同时让历史、语音、引用和复制状态失效。

查看历史时，实时消息直接进入消息窗口，列表保持当前阅读位置；新消息提示只统计当前页面实时收到且尚未看到的对方消息。真实视口确认阅读后逐条扣减，数量为零且离底时显示“回到底部”，到达最新消息位置后隐藏。计数与 SDK 已读回执互相独立，历史分页和同步刷新不增加计数。

查看历史时点击输入框，输入框正常弹出键盘，`scrolling/ChatLatestScrollController` 同时平滑返回最新消息。只有手指拖动列表会取消返回并收起键盘，程序滚动及键盘展开不改变焦点；减少动画设置下直接定位最新端。

消息多选保留原消息组件，在 `messages/selection/` 维护范围和手势。圆点由 `MessageSelectionLayout` 在当前布局帧读取公共消息内容锚点，按气泡实际高度居中，排除时间条、昵称和外置回执；消息异步变高时同帧更新。长按未选消息后滑动选中连续范围，长按已选消息则取消范围；往回滑时，范围外恢复本次手势前的选择状态。普通拖动仍滚动列表，长按滑选触及视口边缘时按实际滚动方向和最小/最大范围自动滚动，兼容聊天居中视口的负滚动位置。

拖选只读取当前挂载行的几何信息，范围状态按消息 ID 保存；历史分页不丢失起点，系统通知不参与选择。松手、取消、批量操作开始、起点失效、页面被覆盖、应用进入后台和组件销毁都会停止本次拖选及滚动计时器。专项回归位于 `test/pages/chat/messages/selection/`。

## 测试与后续维护

聊天更多面板的「个人名片」直接进入联系人模块的单好友选择页，选择后继续使用现有名片发送确认和 SDK 发送。页面布局、搜索分组和可见在线状态监听的维护说明见 [个人名片好友选择器](../contacts/select_contacts/contact_card/README.md)。

名片消息底栏复用原有时间和发送/已读状态，第二行显示与资料页一致的公开账号；原始 SDK 目标和好友邀请凭证保持独立。显示快照、历史名片补齐及会话隔离见 [个人名片消息](../../../openim_common/lib/src/widgets/chat/contact_card/README.md)。

功能测试位于 `test/pages/chat/<功能>/`，聊天入口的跨模块测试位于 `test/integration/chat/`。公共组件和其他既有共享服务测试继续在应用测试环境运行。

目录拆分的检查结果见 [拆分验证记录](../../../docs/chat-module-refactor-validation.md)；后续异步状态与性能修复见 [根因修复验证记录](../../../docs/root-cause-fixes-validation.md)，测试统计以各轮记录为准。

主控制器约 850 行，其中包括页面协调、依赖注入和已有公开接口代理；保留它用于 GetX、路由和调用方兼容。新消息计数已归入独立 `scrolling/`，主入口仅连接 SDK、视口回调与生命周期；后续新增职责必须继续放入功能控制器。现有群设置页面等超过 500 行的文件已具有独立目录，后续在变更对应功能时继续拆分其页面部件，避免机械搬动无关范围。
