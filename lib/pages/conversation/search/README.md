# 会话页原地搜索

`InlineGlobalSearchSurface` 在会话当前路由内切换列表与全局搜索。`InlineGlobalSearchField` 始终挂载同一个输入框，列表中只保留等高占位；搜索内容通过 `GlobalSearchPage.searchBar` 使用占位，避免在过渡中出现第二个输入框。输入框沿顶部位置连续移动，宽度随取消按钮逐渐显现而收缩，取消时沿同一路径展开并恢复原位，输入框本身保持不透明。`InlineGlobalSearchTokens` 集中维护 300ms 的平滑缓入缓出过渡，减少动画设置下立即切换。尺寸、颜色和大字规则继续复用 `ChatHistorySearchBar`。

搜索实例由本子模块创建并启动，不注册到 GetX 的全局搜索路由。现有 `GlobalSearchPage` 接受实例及取消回调，复用好友、群组、会话和聊天记录查询、失败重试和结果导航。取消或系统返回消耗当前路由的 `LocalHistoryEntry`，退回会话状态；同时通过 `PopScope` 将嵌套首页的返回交给当前搜索状态。过渡结束后，输入框重新绑定空闲控制器，再销毁搜索实例，取消订阅与防抖并阻止迟到请求更新。列表始终挂载，退出后保留滚动位置、文件夹和会话投影。首页通过 `onSearchModeChanged` 在搜索期间隐藏底部导航，群聊入口同样适用。

动画回归逐帧检查进入、退出和中途取消时的位置与宽度连续变化，确认整个往返过程中只有一个 `TextField`、其 State 身份保持不变、输入框不参与淡入淡出，并在退出后恢复原始尺寸与位置。

本次平滑过渡版本已更新到连接的 Android 真机，录屏检查了输入框上移收缩、取消后下移展开及键盘收放，原页面恢复正常。顶部录屏位于工作区 `artifacts/conversation-search-morph-header-verified-20261015.mp4`；会话及全局搜索回归、额外的中途反向回归和共享聊天历史搜索导航回归均通过。

对照 99chat 的 `search_entry_narrow.dart`、`search.dart` 和搜索输入组件。本次原地切换遵循用户明确要求，替换参考仓库的 `Navigator.push` 行为；底层仍使用当前 OpenIM 查询能力。

搜索模式是当前页面的展示状态，进入时不以 `ConversationLogic.isSessionActive` 拦截点击；会话恢复或连接切换期间仍允许收起头部并聚焦输入。实际查询沿用搜索数据源的会话验证。输入条的图标、文字和右侧空白均可以点击进入。

回归位于 `test/pages/conversation/search/`，覆盖原路由、输入框连续上移、焦点、滚动位置恢复、返回、迟到请求隔离、重入、销毁、大字横屏和减少动画。`conversation_edit_host_test.dart` 通过真实首页及嵌套导航覆盖消息/群聊与亮/暗主题，传入 `CONVERSATION_INLINE_SEARCH_PREVIEW` 可导出进入前、搜索中及恢复后的预览。iOS 真机键盘和边缘手势仍需设备验收。

2026-10-15 Android 验证：已将当前调试包以保留数据的方式更新到连接的真机，分别点按消息页中部、群聊页右侧空白进入搜索，确认顶部操作栏消失、输入框上移到状态栏下方、焦点和软键盘正常，取消后返回原会话页。相关点击、搜索切换及首页回归共 23 项通过，静态检查和 Android 调试构建通过。真机截图保存在工作区 `artifacts/conversation-search-phone-*.png`。

