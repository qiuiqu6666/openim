# 全局搜索

`GlobalSearchLogic` 管理输入防抖、查询代次、分类结果及局部失败重试；`GlobalSearchSource` 继续调用现有 OpenIM 好友、群组、消息搜索与主页会话列表。`GlobalSearchPage` 负责分类和结果布局，独立业务展示组件位于 `widgets/`。

会话结果优先显示 `[草稿] 正文`，无草稿或仅空白时显示最新消息，两者都为空时不创建副标题，名称与头像垂直居中。`GlobalSearchConversationSubtitle` 复用 `conversation/drafts/conversation_draft_text.dart`，兼容 SDK 明文和聊天输入模块的 JSON `text`/`mentions` 草稿；只显示正文，不显示提及元数据，不修改存储。换行在搜索摘要中转换为空格，长正文单行省略。会话列表控制器也使用该解析 helper，保持原有解析行为。

搜索页订阅既有 `ConversationLogic.list.stream` 的本地会话投影。草稿更新、清除和会话变更只重新筛选当前关键词下的会话结果，不重新调用联系人、群组或聊天记录搜索，不另注册 SDK 回调。初始会话结果和更新事件通过查询代次与会话更新版本区分，迟到结果不能覆盖新草稿；关闭时取消本页订阅。

头部复用 `ChatHistorySearchBar`、`ChatHistorySearchTokens` 与 `AppTokens`，包括搜索、清除和取消操作，支持亮暗主题。点击会话继续走既有 `ConversationLogic.toChat`，不改变发送或草稿保存流程。

列表对照 99chat `TIMUIKitSearch/pureUI/tim_uikit_search_item.dart` 和 `DirectoryListStyle` 的名称、摘要及圆形头像层级。输入条保留原控制器、搜索提交及输入防抖；空输入时隐藏清除按钮。

联系人、群聊、会话和聊天记录按分区展示在同一列表，分区标题使用自然高度和标题语义。顶部表面与结果列表之间保留主题分隔线，列表随当前关键词更新。群组、群会话和聊天记录共同使用显式圆形 `AvatarView`。

相邻结果使用与文字起点对齐的细分隔线，不同分区通过留白和轻量标题分组。`widgets/global_search_result_tokens.dart` 复用已有历史搜索尺寸与主题样式，统一 44 点头像、64 点最小行高、16 点名称和 13 点摘要；字号放大时行高自然增长，文字保留主题字体。加载占位沿用同一组尺寸。复用 `ListTile`、`AvatarView`、官方账号及群名组件，没有新增重复的结果行组件或改变数据源。

2026-10-15 精修验证：相关 58 项测试及模块静态检查通过，包含空摘要居中、实时摘要变化、草稿、清除与重试、入口往返、减少动态效果、320 点窄屏、横屏、平板及双倍字号。通过真实页面与测试数据导出 Android/iOS 亮暗预览至工作区 `artifacts/global-search-polish-20261015/`；已检查亮暗概览。尚未进行本次改动的真机安装验收。

2026-10-05 分割线验证：页面静态检查通过，`test/pages/global_search` 与 `test/global_search_test.dart` 共 26 项回归通过；实际亮暗 Android/iOS 预览导出至 `build/global-search-divider-preview/`，已检查亮暗结果图。当时调试包构建被工作区通话模块未完成的文件引用阻挡；缺失文件后续补齐后，包含分割线的 `app-debug-chat-smooth-bottom-20261005-5370a16dd51f.apk` 已成功构建，存放于 `build/app/outputs/flutter-apk/`。

`global_search_layout_test.dart` 用真实页面和控制器、测试数据源覆盖首次搜索/切换分类的分区标题与首行、大字窄屏、各类群头像、加载高度稳定、清除和局部失败重试。传入 `--dart-define=GLOBAL_SEARCH_PREVIEW=docs/previews` 时导出实际结果页的亮暗 Android/iOS 预览（正常测试跳过导出）。

新增回归归 `test/pages/global_search/`，历史通用查询回归仍保留在 `test/global_search_test.dart`。

消息、群聊及通讯录入口共同使用 [inline](inline/README.md) 的当前页搜索模式。`GlobalSearchPage` 可接受宿主持有的 `GlobalSearchLogic`、取消回调、自动聚焦开关和输入条占位；各宿主用同一个常驻输入框完成往返动画，搜索内容不再另外创建输入框。既有独立搜索路由仍由原绑定管理控制器，未传回调时取消继续返回原路由。
# 云端历史补齐

全局聊天记录分类在本地结果后主动通过 SDK 分批补齐历史，再更新搜索结果；未查完时提供继续加载。账号、查询和页面生命周期隔离及批量上限见 [cloud/README.md](cloud/README.md)。这不是后端全量关键词搜索，也不承诺能恢复超出服务器保留期限或账号权限的消息。

## UID 查找

全局搜索继续通过 SDK 的用户 ID、群 ID 标志匹配好友和已加入的群，
并在当前会话列表匹配 userID/groupID。符合公开账号格式的用户 UID
额外复用 ContactSearchSource.friends 查询已有好友，按 userID 去重并优先
保留 SDK 好友备注；不会自动查询陌生人或未加入的群。

全局搜索结果不显示“搜索添加好友”或“搜索添加群聊”入口。
未匹配到现有联系人、群聊、会话和聊天记录时，显示既有无结果状态。
用户 UID 可能是公开账号，与 SDK 内部用户 ID 不同，两者均保留既有入口。

新增测试：test/pages/global_search/global_search_uid_test.dart。

## 群资料实时同步

搜索页复用 IMController 的群资料、入群、退群事件，更新当前结果并合并刷新。
identity/global_search_group_projection.dart 保存页面期间的资料变化与退群记录，
旧查询不能覆盖较新的群资料或恢复已退出的群；改名后重新匹配当前关键词。
进入搜索时优先读取账号内已有群资料缓存，搜索快照不再反向写入群资料缓存。
会话、历史命中展示当前群名称和头像；消息正文（包括历史改名通知）保持原文。
关闭搜索时取消监听与延迟刷新。回归见 global_search_group_sync_test.dart。
