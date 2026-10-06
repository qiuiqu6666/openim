# 全局搜索会话草稿与导航调整

日期：2026-10-05。

## 用户可见变化

- 综合搜索与会话分类中的会话，有草稿时显示 `[草稿] 正文`，草稿标识沿用会话列表的强调色。
- 无草稿、空白草稿或结构化草稿正文为空时继续显示单聊/群组；联系人和聊天记录结果仍显示各自的信息。
- 明文和包含 `text`/`mentions` 的结构化草稿均只展示正文，保留 @ 成员名称，不展示内部 JSON 或用户 ID 映射。搜索摘要将换行替换为空格并单行省略。
- 搜索页打开期间的会话草稿变更会跟随现有本地会话投影更新；从聊天返回后可看到保存成功的新草稿。
- 顶部统一为蓝色返回箭头、居中标题，复用其他页面的导航组件和主题。

## 实现与维护

展示组件：`lib/pages/global_search/widgets/global_search_conversation_subtitle.dart`。共享草稿解析：`lib/pages/conversation/drafts/conversation_draft_text.dart`，从既有会话列表的解析逻辑提取，没有改变草稿保存格式或写入顺序。

`GlobalSearchSource.conversationUpdates` 复用 `ConversationLogic.list.stream`；本页订阅只更新当前关键词的会话投影，不另注册 OpenIM SDK 回调，不因草稿事件重新搜索其他分类。新搜索沿用原查询代次；本地会话事件另有版本保护，初始读取的迟到结果不能覆盖最新草稿。退出页取消订阅并忽略迟到结果。

导航复用 `GlassAppBar`、`NavigationGlassTokens.iconSize`、`AppTokens.accent` 与现有标题字体 token，保持亮暗主题及返回行为。核对了本地 99chat `lib/src/search.dart` 的 17 号半粗标题及 `lib/src/pages/favorites/favorite_list_page.dart` 的蓝色返回箭头、居中标题；居中与蓝箭头按用户本次要求及现有好友验证页风格统一。

正式数据仍来自已有 OpenIM SDK 及其会话列表投影，没有新增接口，没有向真实对话发送消息。本次仍保留此前“不部署”的决定。

## 验证

- 搜索相关 14 项（含新增 11 项），连同现有会话预览、会话刷新与输入草稿回归，合计 39 项通过。
- 覆盖明文和结构化草稿、@ 名称、空白与清空草稿、综合/会话分类、更新后不重查其他分类、迟到快照、查询清空、关闭取消订阅。
- 亮暗导航的蓝色返回图标、标题实际居中坐标，以及 320 宽、1.6 倍字体的长草稿布局验证通过。亮暗实际组件 PNG 已检查。
- 全局搜索、新解析文件及测试静态分析无问题。既有 `ConversationLogic` 保留 4 项历史 info（1 项旧 SDK API 弃用、3 项类型注解），无错误或警告。
- Android debug APK 构建成功，副本 SHA-256 已核对。

测试使用测试搜索源和本地更新流替身，没有新增真实好友搜索或对话发送。未在真机验证实际 SDK 草稿事件的时序，未安装到设备，没有部署或重启服务。修复包包含当前共享工作区状态。

## 预览与修复包

- [亮色预览](../build/global-search-preview/global-search-draft-light.png)
- [暗色预览](../build/global-search-preview/global-search-draft-dark.png)
- [Android 调试修复包](../build/app/outputs/flutter-apk/app-debug-search-draft-navigation-20261005-7b42e5aa081b.apk)

SHA-256：`7b42e5aa081b9071f7c6e59e59b7d1d4048b3b69311f8caf73dea888ab090481`
