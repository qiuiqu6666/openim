# 聊天群状态

`ChatGroupController` 拥有聊天页的群资料、自己的成员资料、角色、管理员列表、成员名称映射、公告、成员数量和禁言到期计时器。它只订阅当前群的六类 SDK 群事件，不依赖 `ChatLogic`。

页面在会话参数就绪后调用 `initialize()`，首批历史呈现后调用 `loadAfterHistory()`，退出时调用 `close()`。生产入口注入现有 `IMController`、群与账号 getter、消息列表、清空输入和更新群名称/头像的回调。`withSources` 允许测试注入有限的事件流与查询，不初始化全局 SDK。

首次初始化通过 `readCachedGroupInfo` 从账号共享群缓存取得防御性资料快照，同步种入公告正文、公告版本、群名称、头像和成员数量，避免进入群聊后这些区域再次出现。缓存读取仍检查当前账号和退群状态；没有缓存时沿用原查询路径。首批历史完成后继续后台 SDK 校准群成员关系、群资料、自己的成员资料与管理员列表，缓存不授予群角色或操作权限。

并发历史完成通知共用正在运行的查询。查询后的写入检查关闭状态、群、账号和退群世代；群资料和自己的成员事件还会使对应的旧查询结果失效。成员资料更新每次只刷新一次消息列表。禁言计时器和六个订阅由模块统一释放。

`announcements/GroupAnnouncementBanner` 由聊天页传入已初始化的 `SharedPreferences`，首帧同步决定当前账号、群和公告版本是否已关闭，不先显示后隐藏，也不在相同资料刷新时临时收起公告。关闭记录按 `version:text` 比较，新版公告仍可出现；「我知道了」的已读记录独立保存。未初始化偏好时保留异步加载，未读弹窗也继续在布局后检查；异步结果校验挂载状态、账号与群键、公告版本及加载代际，旧结果不能改变新的公告。

相关测试位于 `test/pages/chat/group/`，覆盖初次查询、异步关闭/退群、查询与实时事件的先后顺序、成员资料刷新以及禁言和角色。

`member_actions/` 管理聊天消息头像的长按菜单。`chat_member_action_policy.dart` 按当前用户与目标成员的群角色决定 @、专属红包、禁言/解除禁言、移除权限；`chat_member_action_sheet.dart` 复用公共菜单与确认弹窗，`chat_member_action_sources.dart` 接入真实 OpenIM 成员查询、禁言与踢人接口，`chat_member_action_result.dart` 校验原生返回结果，兼容 OpenIM 原生成功回调的 JSON 空字符串。`ChatMemberActionsController` 只协调流程，不新增 SDK 订阅；由 `ChatLogic` 创建并关闭，通过既有成员事件同步成功后的状态。

菜单打开前与执行前定点查询群资料、当前用户和目标成员；菜单/确认期间的群事件使旧操作失效，权限同时受 SDK 资料与最新事件资料约束。禁言沿用 99chat 头像操作的长期禁言时长（315360000 秒），解禁传 0；只有接口成功才更新界面。SDK 即时读取的旧禁言值不会盖住成功回写，写入期间有新事件时不广播旧成员资料。退出成员记录由 `ChatGroupController` 保留，直到明确再次入群，防止缓存让已退出用户重新出现管理入口。

头像操作测试位于 `test/pages/chat/group/member_actions/`，包含角色矩阵、SDK 返回值、菜单亮暗/小屏/横屏/大字、取消、异步关闭、重复长按及权限与禁言更新竞争。对照入口为 `reference-99chat/lib/src/chat.dart` 的 `_onLongPressOthersAvatar` 和成员禁言/移除流程；本项目继续使用 OpenIM 工作群的真实权限规则。

专属红包与 @ 使用相同的发言权限条件。点击后重新核验目标仍在群内，结束加载提示，再调用 `ChatFundController.sendExclusiveRedPacket()` 打开既有 `FundSendPage`，预选专属类型和该成员的 ID、昵称、头像。头像菜单只负责导航；金额输入和支付确认由原有资金页面处理。不同成员或红包类型的待确认支付不能覆盖这个入口预选的接收人。
