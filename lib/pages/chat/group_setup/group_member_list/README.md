# 群成员列表与选择

成员列表、移除成员、已选姓名和已选成员弹层优先显示当前好友备注，
其余使用 SDK 群内昵称。头像与文字共用同一显示名；名称来自现有联系人目录，
不修改 `GroupMembersInfo`，操作和选择始终以用户 ID 为准。

`group_member_remark_search.dart` 补充备注搜索：联系人目录只提供候选 ID，
SDK 按最多 100 人一批核对群成员身份，排除群外用户及已移除成员；结果与原有
SDK 搜索去重合并。分页偏移和更多标志仍取 SDK 原始页，搜索词、权限或账号变化
使旧响应失效。已有的可见性、身份字段保护、角色限制及移除确认沿用原逻辑。

测试：`test/pages/chat/group_setup/group_member_list/group_member_remark_test.dart`
以及同目录的身份与权限回归测试。
