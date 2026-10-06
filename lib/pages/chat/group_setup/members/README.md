# 群设置成员预览

`GroupMemberPreviewController` 管理群设置页首屏的成员预览，不管理全量群成员和群人数。

## 接入与数据源

- `GroupSetupLogic` 创建并持有控制器，提供 `memberList`、`membersLoading`、`membersFailed` 和 `getGroupMembers()` 给现有页面。
- 仍使用 `GroupMemberIdentitySource.list()`，请求当前 IM 服务的 `/group/get_group_member_list`，第一页 20 人；页面展示排序后的前六人。
- SDK `userID` 与可选公开 `account` 继续遵循 `../../group/identity/README.md`；不添加 SDK 或资料接口作为账号字段的兜底来源。
- 页面在 `LayoutBuilder` 内使用局部 `Obx` 订阅成员及请求状态，避免数据返回后头像区域没有重建。

## 请求和权限边界

`refresh(groupID, scope, isCurrent)` 的 scope 是父控制器捕获的账号、SDK 账号、IM token、服务器、群 ID 和权限 generation。相同 scope 的进行中请求共用一个 Future；更换 scope 时立即清理原成员。

首次读取群资料和本人角色只是初始化，不重复清空和发起成员请求。实际权限或群规则变化仍通过 `invalidate()` 废弃旧结果并清空预览，保持原有权限保护。

`lookMemberInfo` 变化不依赖成员版本号，重新请求 `/group/get_group_member_list` 第一页。本人资料的新更新事件也会清空预览并重新读取群资料、本人角色及 HTTP 成员页，覆盖系统管理员资格变化；已有 `selfInfoUpdatedSubject` 缓存重播由首次加载负责，不额外重复发请求。只处理当前 IM 登录用户的新事件，关闭或离群后取消/拒绝刷新。公开账号始终以当前群接口返回为准，不由系统管理员或群角色字段在客户端补出。

同 scope 的普通刷新保留上次成功结果，失败也保留；首次失败显示内联重试。空结果或连接/发送/接收超时、连接错误自动延迟一秒重试一次；服务端错误不自动重试。手动重试仍受进行中请求合并保护。未加入群、会话改变或页面关闭时不接受迟到响应。

`invalidate()`/`dispose()` 取消等待重试的计时器；底层已经发出的 HTTP 可以完成，但过期结果不再写入页面。本模块没有持久化或跨页面成员缓存，不尝试加载一万人的全量列表。

## UI 与验证

成员列表为空时区分加载、失败和空结果；加载用现有 `CircleAvatar` 与 `Styles` 显示六个占位，失败和空结果用可点击提示重试。保留原有头像样式、加减按钮、主题色和 78.h 区域高度。

测试在 `test/pages/chat/group_setup/members/`；与 `test/pages/chat/group_setup/` 及 `test/pages/chat/group/identity/` 一起运行，验证回包顺序、请求合并、重试、权限和会话失效、日夜主题和窄屏布局。实际设备/网络验证范围见 `docs/group-member-preview-stability-validation.md`。
