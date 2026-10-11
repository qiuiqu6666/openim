# 代理下级头像

对照 99chat `agent_rebate_descendants_page.dart` 的可见行资料补全，使用当前 OpenIM SDK `getUsersInfo` 查询真实头像，不依赖下级统计接口携带头像字段。

- `AgentAvatarDirectory` 归当前页面所有，按账号、群权限校验请求；同帧用户合并为最多 50 人一批并去重。缓存最多 512 人、1 分钟，页面退出即清理。
- `AgentUserAvatar` 复用公共 `AvatarView` 的图片加载、失败占位和亮暗主题样式。列表、下级详情和详情内的直属下级共用该组件。
- 只在用户行实际构建时查询资料。显式 `imUserId` / `imUserID` 优先，否则使用返回的 `userId` / `userID`；不能把显示的 `playerNo` 拼成 IM ID。
- SDK 结果按 `userID` 匹配，不依赖返回顺序；无资料或查询失败时继续使用接口已有头像，没有可用头像才使用原占位。已返回的空头像表示用户没有头像。
- 异步失败不阻塞下级统计列表；退出、权限失效、行切换后旧结果不能覆盖当前头像。

测试位于 `test/pages/group_features/mark_six/agent/identity/`。
