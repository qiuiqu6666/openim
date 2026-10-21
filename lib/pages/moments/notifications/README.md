# 朋友圈互动通知

页面入口保留在 `moments_notifications_page.dart`，行组件与内容补全归本目录。
复用 `MomentUser`、`MomentMedia`、好友目录和 `MomentsMediaImage`，不新增资料或媒体网络客户端。

- 名称与头像使用当前账号的好友资料，备注优先，其次昵称；资料确实缺失时保留通知提供的数据和 ID 兜底。
- 解析通知的 `momentPreviewMedia`，展示图片、视频封面或纯文字摘要。媒体继续使用现有授权下载和账号切换失效机制。
- 页面持有内容补全订阅，销毁或替换仓储时释放。后台角标刷新不额外取详情，打开列表期间的实时刷新会补全内容。
- 稀疏通知先显示，再按动态 ID 合并详情请求，最多四个并发；缺少评论时按评论 ID 匹配，最多取三页、每页 100 条，避免遍历全部历史。超出范围、已删除或网络失败时保留互动类型提示，可下拉重新加载。
- 补全结果只写入当前会话、权限和请求代次；保留补全过程中发生的已读变更，并重新执行现有好友可见性过滤。
- 进入列表或下拉刷新成功后，按该次响应的 `seenWatermark` / `readThroughSeq` 自动确认已有互动已读。新到的互动保留未读；加载失败、缺少截止位置、页面已退出或会话变化时不自动确认。确认失败保留角标并可通过“全部已读”重试。

`moments_repository.dart` 继续拥有通知分页、未读数与 SDK 事件状态。本次只增加接入与生命周期协调，独立补全职责置于 `data/`，不拆动既有跨页面状态。

参考：本地 99chat 的 `lib/src/models/moments/moment_models.dart` 与 `lib/src/pages/moments/moments_notifications_page.dart`。
测试：`test/pages/moments/notifications/`，以及既有通知、仓储和 API 合约测试。
