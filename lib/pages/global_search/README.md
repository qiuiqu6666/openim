# 全局搜索

`GlobalSearchLogic` 管理输入防抖、查询代次、分类结果及局部失败重试；`GlobalSearchSource` 继续调用现有 OpenIM 好友、群组、消息搜索与主页会话列表。`GlobalSearchPage` 负责分类和结果布局，独立业务展示组件位于 `widgets/`。

会话结果优先显示 `[草稿] 正文`，无草稿或仅空白时沿用单聊/群组类型。`GlobalSearchConversationSubtitle` 复用 `conversation/drafts/conversation_draft_text.dart`，兼容 SDK 明文和聊天输入模块的 JSON `text`/`mentions` 草稿；只显示正文，不显示提及元数据，不修改存储。换行在搜索摘要中转换为空格，长正文单行省略。会话列表控制器也使用该解析 helper，保持原有解析行为。

搜索页订阅既有 `ConversationLogic.list.stream` 的本地会话投影。草稿更新、清除和会话变更只重新筛选当前关键词下的会话结果，不重新调用联系人、群组或聊天记录搜索，不另注册 SDK 回调。初始会话结果和更新事件通过查询代次与会话更新版本区分，迟到结果不能覆盖新草稿；关闭时取消本页订阅。

头部复用 `GlassAppBar`、`NavigationGlassTokens` 与 `AppTokens`，标题居中，17 号半粗字体，蓝色返回箭头并保留返回语义。支持亮暗主题，点击会话继续走既有 `ConversationLogic.toChat`；本次没有改变发送或草稿保存流程。

导航对照 99chat `lib/src/search.dart` 的 `AppBar` 和 `lib/src/widgets/app_back_button.dart`：保留本项目已有“搜索”标题，工具栏沿用 `NavigationGlassTokens.toolbarHeight`，返回和清除按钮使用 48px 触控区域。输入条复用公共 `SearchBox`，保留原控制器、搜索提交及输入防抖；空输入时隐藏清除按钮。

分类栏使用自然高度的横向滚动区域，避免固定高度裁剪大字和触控区域。顶部表面与结果列表之间增加主题分隔线；结果列表明确自身滚动及上下内边距，分区标题使用自然高度与标题语义。切换分类仍沿用原有关键词/分类键，不更改滚动恢复和数据请求策略。群组、群会话、聊天记录及文件结果共同使用显式圆形 `AvatarView`。

相邻搜索结果之间增加细分割线，左侧按当前头像尺寸和文字间距对齐文字起点；综合结果不同分区之间增加整宽分割线。复用顶部既有的 1px 高、0.5px 线宽和 `AppTokens.border` 主题颜色，不改变结果点击、草稿展示或搜索请求。行间线对照 99chat 搜索复用的 `DirectoryListRow`。

2026-10-05 分割线验证：页面静态检查通过，`test/pages/global_search` 与 `test/global_search_test.dart` 共 26 项回归通过；实际亮暗 Android/iOS 预览导出至 `build/global-search-divider-preview/`，已检查亮暗结果图。当时调试包构建被工作区通话模块未完成的文件引用阻挡；缺失文件后续补齐后，包含分割线的 `app-debug-chat-smooth-bottom-20261005-5370a16dd51f.apk` 已成功构建，存放于 `build/app/outputs/flutter-apk/`。

`global_search_layout_test.dart` 用真实页面和控制器、测试数据源覆盖首次搜索/切换分类的分区标题与首行、大字窄屏、各类群头像、加载高度稳定、清除和局部失败重试。传入 `--dart-define=GLOBAL_SEARCH_PREVIEW=docs/previews` 时导出实际结果页的亮暗 Android/iOS 预览（正常测试跳过导出）。

新增回归归 `test/pages/global_search/`，历史通用查询回归仍保留在 `test/global_search_test.dart`。
