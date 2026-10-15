# 列表页原地搜索

`InlineGlobalSearchSurface` 是消息、群聊和通讯录共用的搜索展示与生命周期宿主。各页面通过 `feedBuilder` 把等高占位放在原搜索框的位置，顶部标题栏和列表仍属于原页面，始终保留挂载。宿主浮层中的 `InlineGlobalSearchField` 复用 `ChatHistorySearchBar`，往返过程中保持同一个输入框 State，不淡出、不替换输入控件。

`InlineGlobalSearchTokens` 统一 300ms 缓入缓出动画：进入时输入框上移并随取消按钮出现而收缩，退出时沿同一路径下移展开。`toolbarHeight` 使用原页的实际顶部栏高度；通讯录把大字适配后的标题栏高度传入，避免恢复错位。`entryKey` 由宿主页面提供；会话沿用 `conversation-search-entry`，通讯录沿用 `contacts-search-button`。

输入、焦点、查询、取消和资源销毁共用同一条生命周期链。页面可以用 `onWillOpen` 结束编辑状态；`onSearchModeChanged` 通知首页按当前标签隐藏、恢复底部导航。`LocalHistoryEntry` 与 `PopScope` 保留原路由及系统返回行为。退出过渡后先把输入框重新绑定空闲控制器，再销毁活动搜索控制器并取消订阅、防抖与迟到查询更新。减少动画设置下立即切换。

正式查询继续使用现有 `GlobalSearchLogic`、OpenIM SDK、会话本地投影与历史搜索 API；没有新增数据源或 SDK 回调。独立全局搜索页的原路由仍然可用。

对照 99chat `lib/src/contact.dart` 和 `lib/src/widgets/contact_style_search_bar.dart` 的入口、尺寸及取消控件；当前页移动输入框遵循用户明确要求，替换参考实现的页面跳转。

维护与回归：

- `test/pages/conversation/search/` 覆盖共享过渡的 State 身份、位置/宽度连续变化、中途反向、清理和减少动画。
- `test/pages/contacts/search/contacts_inline_search_test.dart` 覆盖真实通讯录页面的亮暗主题、滚动恢复、大字标题栏、焦点和系统返回。
- `test/pages/conversation/conversation_edit_host_test.dart` 使用真实首页嵌套导航，覆盖消息、群聊和通讯录搜索时底部导航的隐藏、返回和原标签恢复。
- 共享搜索及历史导航回归覆盖原查询、清空、失败重试与结果跳转。

2026-10-15 通讯录接入验证：页面与首页相关 28 项、共享搜索与历史导航相关 85 项测试通过，修改范围静态检查及 Android 调试构建通过。已以保留应用数据的方式更新连接的 Android 真机，并录屏确认通讯录输入框上移收缩、取消后下移展开、软键盘与原列表恢复；顶部录屏为工作区 `artifacts/contacts-inline-search-header-motion-20261015.mp4`。亮暗主题、大字和减少动画由组件测试覆盖，iOS 真机尚未验证。
