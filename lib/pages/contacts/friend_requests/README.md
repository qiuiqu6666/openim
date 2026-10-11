# 好友申请来源

## 左滑删除与清空

列表支持左滑露出删除按钮，顶部清空需确认。复用现有 Slidable、TitleBar、CustomDialog、主题和中英文文案；对照 99chat 的群通知滑动操作与 `friend_application_helper.dart` 的记录清理语义，数据仍来自当前 OpenIM SDK。

当前 SDK 没有申请记录删除方法，所以清理状态由联系人共享模块 `../request_history/` 按账号和通知类型保存到本机。删除按双方 ID 和申请时间识别记录，审批变化不恢复记录；清空以最新可见申请的服务端时间为界，覆盖尚未展示的旧记录，不使用手机时间。重新登录和刷新保留清理结果；其他设备及清除应用数据后不共享这些状态。不会删除好友、撤销申请或更改审批结果。

列表和首页红点都过滤已清理记录。异步写入成功后才移除列表项，保存失败保留原记录；刷新提交再次过滤，旧账号页面不能清理新账号记录。测试位于 `test/pages/contacts/request_history/` 和 `test/pages/contacts/friend_requests/friend_request_cleanup_test.dart`。

列表沿用 OpenIM SDK 的收件、发件申请数据和现有处理入口。`widgets/friend_request_item.dart` 保留昵称、验证消息及待验证、已同意、已拒绝状态，额外显示添加来源；行高随内容和字号扩展，复用 `AvatarView`、`Button`、`Styles` 与原列表间距。

`source/friend_application_source.dart` 只读取 `FriendApplicationInfo.ex` 中的 `addSource`（兼容明确的 `source`），按已有来源枚举显示聊天号、手机号、邮箱、二维码、链接、名片、群聊或群管理等文案。旧版明确来源保留历史含义；缺失、未知或非法值显示“来源未知”。验证消息、用户 ID、签名和操作 ID 都不能用于推断来源，也不在界面显示原始扩展字段。

当前 Chat 凭证申请在 `sendFriendApply` 中仅写入签名信息。服务端补丁位于 `server/friend_request_source/friend_apply_source.patch`：附加真实凭证记录的 `row.Source`，不改变签名或权限校验。补丁发布后新申请可以显示来源；旧的无来源申请不会自动补齐。

参考 99chat 的 `friend_request_audit_page.dart` 来源文案，使用本项目已有 OpenIM 数据和组件。解析与列表项测试位于 `test/pages/contacts/friend_requests/`，覆盖来源元数据、旧签名记录、收发方向、处理动作、亮暗主题和英文大字号布局。
# 99chat 列表对齐（2026-10-11）

当前列表已按参考仓库 `lib/src/newContact.dart` 调整为“新的朋友”：分收件/发件区块、待验证优先、验证附言和时间方向、状态胶囊、编辑多选删除。旧来源协议标签仅在展示时去除，数据继续使用 OpenIM SDK。共享组件、清理语义和验证说明见 `../request_history/README.md`；下文为此前实现记录。
