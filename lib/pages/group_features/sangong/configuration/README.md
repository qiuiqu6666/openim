# 群配置列表选择

`SangongMyConfigPage` 继续管理加载、校验、保存与当前群权限；`SangongConfigSelectionCell` 复用设置输入行，提供群聊 / 通讯录选择入口及选中名称，保留手动编辑能力。通过 `ContactSingleSelection` 直接复用 `SelectContactsFromGroupPage` 和 `SelectContactsFromFriendsPage`（现有单选通讯录 `ContactCardFriendPicker`），没有独立列表页面。保存仍走现有三公接口。

结账群、上下分通知群从已加入的群列表选择；机器人从通讯录选择。当前群配置的下注群遵循后端绑定约束，固定为当前群。选中的机器人 userID 作为已知 SDK ID 传入身份解析器，不将形似公开账号的 userID 再次解析；手动修改为其他公开账号时，恢复原有精确查询校验。

群聊沿用现有 SDK 已加入群列表；通讯录沿用 `FriendListLogic` 的真实好友快照、目录索引和好友变更监听。单选返回不会触发名片确认框，不覆盖 Get 中其他页面的选择控制器；账号、群或权限变化会关闭选择页并丢弃迟到结果。

测试：`test/pages/group_features/sangong/pages/sangong_config_directory_test.dart`，覆盖复用现有页面、选择与保存、取消保留输入、手动修改、搜索、重试、空状态、权限变化、控制器隔离和明暗主题。
