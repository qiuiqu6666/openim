# 聊天存储维护入口

- 现有入口 `../pages/chat_storage_page.dart` 保留 SDK 查询、分页和会话汇总，按数据 revision、筛选、搜索及日期缓存会话分组，兼容导出 `ConversationStoragePage`。
- `conversation_storage_page.dart` 负责当前会话的展示、拖选、删除确认和异步预览。每个时间段使用 `SliverGrid`，仅布局当前可见及滚动缓存范围。排序、时间分组、ID 查询和总容量由 `storage_media_catalog.dart` 在数据或排序条件变化时生成。
- `widgets/storage_media_tile.dart` 注册/释放当前挂载的格子用于拖选命中，监听选择 revision；缩略图由独立 `storage_media_thumbnail.dart` 复用，不随选中变化重建。
- 文件识别和安全删除仍复用 `../pages/storage_media_repository.dart`；消息记录保留，预览本地可用性异步检查且最多同时处理 12 项。
- 回归测试：`test/pages/mine/settings/storage/conversation_storage_page_test.dart`，覆盖大列表可见区域布局、缓存与 revision、连续拖选及边缘自动滚动。

现有入口和会话页面略超过 500 行，已分别检查职责：前者是 SDK 搜索与会话汇总，后者是会话交互协调；缩略图、格子和目录投影已独立。后续新增存储功能进入此目录，不继续堆入兼容入口。
