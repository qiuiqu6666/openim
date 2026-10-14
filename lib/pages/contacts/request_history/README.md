# 群通知服务端迁移（2026-10-14）

群通知已改用 `../group_requests/data/` 的服务端接口。此模块继续提供共享列表外观；`RequestHistoryStore` 的本机清理和 `RequestListCache` 的快照仍用于好友申请。群通知旧本机隐藏记录仅作为一次性迁移来源，迁移完成后以服务器状态为准，不再读群通知缓存。详情见 [服务端模块](../../../../server/group_notices/README.md)。

以下为历史实现说明。

# 申请记录的共享展示与清理

2026-10-11 按 `reference-99chat/lib/src/newContact.dart`、`all_group_application_list.dart` 及 UIKit `directory_list_row.dart` 对齐新的朋友和群通知。列表行、胶囊状态、审核/验证按钮、标题栏和本机时区日期格式放在本模块，主题色复用 `AppTokens`，头像复用 `AvatarView`。

- 好友申请分为对方添加我、我添加对方，收到的待处理申请优先。显示验证附言、时间和发起方向；旧 `[99chat_src:AddSource_Type_…]` 标签只在展示时剥离，不改 SDK 记录、来源元数据或签名。
- 好友页右上角编辑进入多选，支持全选、取消全选、确认删除和完成。`hideAll` 一次保存选中身份，未选中及后来新增的申请不受影响。原有左滑删除保留。
- 群通知显示群头像/群名、申请时间、单行邀请/申请描述及真实处理管理员。优先用已加载群资料，回退到申请记录的群字段；缺少处理人时不猜测。审核仍使用当前 SDK 和详情页。右上角更多菜单提供确认清空。
- 已同意的记录点击后先通过 SDK 获取会话，再复用 `AppNavigator.startChat`，保留列表返回栈；重复点击和页面关闭/账号切换后的异步响应不会继续导航。

`RequestHistoryStore` 仍是当前账号下的本地记录清理，不删除好友/群关系，不调用参考仓库的腾讯申请接口。群通知保持原分页、重试、事件刷新和账号/token 防护。

## 首屏加载

- `data/request_list_cache.dart` 保存当前账号/token 的 30 秒内存快照，每类最多 100 条；群页只缓存首批 20 条。读出时重新过滤本地删除/清空标记，后台仍查询 SDK，快照不能启用尚未初始化的分页游标。账号或 token 改变后不复用旧快照。
- `data/request_load_coordinator.dart` 合并进行中的读取；期间收到通知只排队一次最新刷新，过期响应不覆盖新状态，关闭页面后不再发起排队请求。分页和刷新共享队列。
- 两个页面在初始化时立即开始读列表。新的朋友首屏为空时可先显示先返回的一侧申请；群通知发布列表后，邀请人群资料与用户资料并行补齐，不阻塞列表可用状态。后台资料响应仍检查账号、token、关闭及刷新版本。
- `[FriendRequests][recipient/applicant/load]` 和 `[GroupRequests][list/profiles]` 记录读取耗时与数量，不记录账号、token、昵称、申请内容。列表首屏与补资料的时间分开观察。

测试：`test/pages/contacts/{friend_requests,group_requests,request_history}/`。覆盖批量删除、刷新不复活、切换账号、来源标签、真实群/用户头像字段、时间格式、亮暗主题、小屏和双倍字号。设置 `EXPORT_REQUEST_HISTORY_PREVIEW=1` 运行 `request_history_pages_test.dart` 可在 Windows 使用微软雅黑导出 `artifacts/request-history-*.png`。
