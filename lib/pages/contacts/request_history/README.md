# 申请记录的共享展示与清理

2026-10-11 按 `reference-99chat/lib/src/newContact.dart`、`all_group_application_list.dart` 及 UIKit `directory_list_row.dart` 对齐新的朋友和群通知。列表行、胶囊状态、审核/验证按钮、标题栏和本机时区日期格式放在本模块，主题色复用 `AppTokens`，头像复用 `AvatarView`。

- 好友申请分为对方添加我、我添加对方，收到的待处理申请优先。显示验证附言、时间和发起方向；旧 `[99chat_src:AddSource_Type_…]` 标签只在展示时剥离，不改 SDK 记录、来源元数据或签名。
- 好友页右上角编辑进入多选，支持全选、取消全选、确认删除和完成。`hideAll` 一次保存选中身份，未选中及后来新增的申请不受影响。原有左滑删除保留。
- 群通知显示群头像/群名、申请时间、单行邀请/申请描述及真实处理管理员。优先用已加载群资料，回退到申请记录的群字段；缺少处理人时不猜测。审核仍使用当前 SDK 和详情页。右上角更多菜单提供确认清空。
- 已同意的记录点击后先通过 SDK 获取会话，再复用 `AppNavigator.startChat`，保留列表返回栈；重复点击和页面关闭/账号切换后的异步响应不会继续导航。

`RequestHistoryStore` 仍是当前账号下的本地记录清理，不删除好友/群关系，不调用参考仓库的腾讯申请接口。群通知保持原分页、重试、事件刷新和账号/token 防护。

测试：`test/pages/contacts/{friend_requests,group_requests,request_history}/`。覆盖批量删除、刷新不复活、切换账号、来源标签、真实群/用户头像字段、时间格式、亮暗主题、小屏和双倍字号。设置 `EXPORT_REQUEST_HISTORY_PREVIEW=1` 运行 `request_history_pages_test.dart` 可在 Windows 使用微软雅黑导出 `artifacts/request-history-*.png`。
