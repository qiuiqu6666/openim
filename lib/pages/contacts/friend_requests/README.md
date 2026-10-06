# 好友申请来源

列表沿用 OpenIM SDK 的收件、发件申请数据和现有处理入口。`widgets/friend_request_item.dart` 保留昵称、验证消息及待验证、已同意、已拒绝状态，额外显示添加来源；行高随内容和字号扩展，复用 `AvatarView`、`Button`、`Styles` 与原列表间距。

`source/friend_application_source.dart` 只读取 `FriendApplicationInfo.ex` 中的 `addSource`（兼容明确的 `source`），按已有来源枚举显示聊天号、手机号、邮箱、二维码、链接、名片、群聊或群管理等文案。旧版明确来源保留历史含义；缺失、未知或非法值显示“来源未知”。验证消息、用户 ID、签名和操作 ID 都不能用于推断来源，也不在界面显示原始扩展字段。

当前 Chat 凭证申请在 `sendFriendApply` 中仅写入签名信息。服务端补丁位于 `server/friend_request_source/friend_apply_source.patch`：附加真实凭证记录的 `row.Source`，不改变签名或权限校验。补丁发布后新申请可以显示来源；旧的无来源申请不会自动补齐。

参考 99chat 的 `friend_request_audit_page.dart` 来源文案，使用本项目已有 OpenIM 数据和组件。解析与列表项测试位于 `test/pages/contacts/friend_requests/`，覆盖来源元数据、旧签名记录、收发方向、处理动作、亮暗主题和英文大字号布局。
