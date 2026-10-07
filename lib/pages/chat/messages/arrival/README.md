# 实时消息入场

本模块只负责正在查看的聊天里实时收到的新消息入场。消息数据、SDK 订阅、历史分页和阅读回执继续由已有聊天模块持有。

## 入口与职责

- `ChatLogic._appendLiveMessage` 完成会话过滤、去重和历史窗口缓冲判断后，调用 `messageArrivals.register`。只在当前路由、前台、历史已加载、位于最新位置、列表没有滚动或多选时登记；本人投递、typing 和系统通知直接展示。
- `ChatMessageArrivalController` 持有待领取、入场中及取消的消息 ID，不持有 SDK 订阅或 ticker。最多同时登记 4 条，超过上限的消息正常插入并直接显示。`retain` 清理插入后又被删除的消息。
- `ChatMessageList` 持有 `ChatMessageArrivalAnimations` 和 ticker，将动画放在原有最外层消息 key 内，保留 SDK ID、反向索引和 `findChildIndexCallback`。
- `ChatMessageArrivalAnimations` 按消息 ID 持有动画进度。公共 viewport 在新消息插入时可以更换 sliver center，因此动画不能由消息行自身重新创建；重叠到达、回执刷新和行重建均复用已有进度。

## 动画与阅读

240ms 内，完整气泡从聊天 viewport 下边界之外向上平移，保持实际尺寸和透明度。位移距离由真实 viewport 与目标行的位置计算，不使用固定 24px 偏移，也不在行内裁剪。行占位使用 `easeInOutCubic` 逐渐增加，为原有长列表的底部锚定提供连续高度变化；旧消息因此平滑上移。短会话沿用原来的顶端排版，但入场起点仍在 viewport 下边界之外。

入场期间，`ChatLogic.onChatViewportChanged` 排除仍在平移的消息 ID，避免把占位高度误认为气泡完整可见或提前启动阅后即焚。`ChatReadReceipts.canReadConversation` 同时阻止全会话阅读，防止后续本人消息或超过动画容量的消息绕过屏障。私密消息的逐 ID 阅读仍按实际完整可见消息进行。动画完成后，先绘制完整高度，再释放此屏障；下一帧交给原有公共 viewport 重新测量和确认阅读，不自行补发回执。

用户开始拖动或多选会取消入场；系统减少动画、ticker 关闭、路由遮挡会令已开始的动画立即完整显示。已开始的行仍等完整高度绘制后才释放阅读屏障。离开页面时释放控制器和 ticker，迟到的帧回调不会访问已销毁的动画。

已经入场的行在完成后保留同类型包装，避免结束瞬间重建媒体气泡子树；完成时即释放 ticker，只保留仍在当前 SDK 列表里的行 ID。

多个入场气泡按 SDK 列表的上下顺序约束绘制位置，后到的行保持在上方入场行的完整高度之后。邻接数据只持有仍在入场且已挂载的渲染行，最多 4 条；只影响平移位置，不修改消息数据、滚动位置或布局约束。

## 验证入口

- `test/pages/chat/messages/arrival/chat_message_arrival_controller_test.dart`：入场资格、去重、容量、删除清理、取消屏障和销毁。
- `test/integration/chat/chat_message_arrival_motion_test.dart`：实际 ChatPage 和 SDK 收消息回调，逐帧检查完整气泡从视口外移入的位置、尺寸恒定、旧气泡位置及已读时机；覆盖空／短／长会话、亮暗主题、不同高度、批量与重叠到达、回执刷新、历史阅读及减少动画。
- `test/pages/chat/receipts/chat_read_receipts_test.dart`：会话门控覆盖退出、普通显式阅读和排队请求，私密逐 ID 阅读保持独立。

未更改媒体下载、内置表情缓存、原有消息发送或手动回到底部的动画策略。
