# 聊天消息气泡入场检查与修改

日期：2026-10-06

## 原来的表现与原因

聊天收到消息的主要路径：

1. `ChatLogic._ownedMessageCallback` 接收 SDK 消息并确认属于当前会话。
2. `_appendLiveMessage` 处理 typing、助手流式片段、重复消息和历史窗口缓冲。
3. 普通实时消息直接加入 `messageList`。当前位于最新位置时，由既有 `scrollBottom(force: false)` 保持最新位置。
4. `ChatMessageList` 按 SDK 消息 ID 生成反向列表，`ChatMessageTile` 构建现有气泡。
5. 公共 `ChatListViewport` 按真实绘制位置确认可见消息，聊天阅读模块发送已读回执。

原来没有气泡入场动画；列表变更后直接绘制完整高度，在底部阅读时立即跟随最新布局，因此看起来突然出现。

## 本次效果

可以实现从下方平滑向上滑出的效果，已接入前端。第一版使用了行内裁剪、行高展开和固定 24px 上滑，视觉上会像在原位置撑开。根据反馈，最终版本改为完整气泡先位于聊天可视区域下边界之外，再向上平移到目标位置，裁剪仅发生在原有 viewport 边缘。

本次检查了实际本地 99chat 参考的动画时序与列表配合，最终呈现适配当前 OpenIM 的公共 viewport 和已读流程；没有声称复刻微信或 Telegram 的内部实现。

| 项目 | 行为 |
| --- | --- |
| 时长 | 240ms，完成确认在最终完整高度绘制后进行 |
| 起点 | 完整气泡在聊天 viewport 的下边界之外 |
| 上滑距离 | 依据真实 viewport 和行位置计算，覆盖空会话、短会话与长会话 |
| 呈现 | 气泡保持实际尺寸、保持不透明，从下方整体平移进入 |
| 位移 | `easeOutCubic` |
| 占位高度 | `easeInOutCubic`，从零到实际消息高度，为旧消息提供平滑位移 |
| 长会话 | 最新位置保持底部锚定，新气泡展开时旧消息平滑上移 |
| 短会话 | 保留原来的顶端排版，入场仍从 viewport 下边界外开始 |
| 连续来消息 | 每条保持独立进度；新的到达不会重播前一条；完整气泡按上下顺序滑入，避免互相覆盖 |
| 上翻历史 | 保留阅读位置，新消息不播放入场、不强制拉回底部 |
| 减少动画 | 直接完整显示 |

只对当前前台聊天中、位于最新位置且列表没有滚动或多选的实时收到消息启用。打开页面、历史分页、历史日期窗口、本人投递、typing、系统通知和已读状态刷新直接显示。最多同时播放 16 条；超过上限仍正常插入消息，直接显示。

## 已读与生命周期保护

入场期间，公共 viewport 测到的占位高度并不代表正在平移的气泡已完整可见。前端会暂时排除这些消息的自动阅读确认；同时阻止全会话已读，避免后续无动画的本人消息、系统消息或批量第 17 条提前消费仍在入场的消息。门控覆盖可见区确认、排队请求、显式普通阅读及退出清未读；私密内容的逐 ID 确认保持独立。

动画完成并绘制完整高度后，再由原有可见区域检测确认已读，避免提前清未读或启动阅后即焚。

拖动和多选会终止入场；减少动画、关闭 ticker 或遮挡路由会令动画收尾到完整高度。页面销毁会释放所有 ticker；删除消息会清理对应登记，迟到的帧回调检查动画是否仍归当前列表持有。

原有媒体预览、表情图片缓存、消息数据、发送流程、历史定位以及手动回到底部的慢到快滚动沿用现有实现。

## 修改位置

- `lib/pages/chat/messages/arrival/`：资格控制、动画持有、参数和模块说明。
- `lib/pages/chat/messages/widgets/chat_message_list.dart`：由列表持有动画，包装原有消息行，保留消息 key 和索引。
- `lib/pages/chat/chat_logic.dart`：实时收消息登记、已读屏障、拖动／多选取消与销毁。
- `lib/pages/chat/receipts/chat_read_receipts.dart`：可选会话阅读门控，默认兼容已有调用。

本地参考：`reference-99chat/third_party/tencent_cloud_chat_uikit/lib/ui/widgets/chat_message_enter_animation.dart`。

## 验证与交付

最终回归 **131 项全部通过**，包含真实 ChatPage 收消息逐帧检查、入场资格、空／短／长会话、亮暗主题、批量与重叠到达时的上下顺序、子树状态保留、拖动取消、减少动画、会话已读门控、历史阅读位置、历史定位和回到底部。测试入口如下：

```powershell
flutter test --no-pub --reporter expanded `
  test/integration/chat/chat_message_arrival_motion_test.dart `
  test/pages/chat/messages/arrival `
  test/integration/chat/chat_entry_performance_test.dart `
  test/integration/chat/chat_back_to_bottom_motion_test.dart `
  test/integration/chat/chat_conversation_read_test.dart `
  test/pages/chat/scrolling `
  test/pages/chat/receipts `
  test/pages/chat/history/date_jump/chat_viewport_seek_test.dart
```

静态检查没有新增错误或警告；仍有两条原有 SDK 接口弃用提示（`resetConversationGroupAtType` 和私密逐 ID 阅读使用的 `markMessagesAsReadByMsgID`），本次不改动这些接口。Android Debug APK 已成功构建并复制为固定文件名：

- 文件：`build/app/outputs/flutter-apk/app-debug-chat-message-viewport-slide-20261006-4793d1448f29.apk`
- 大小：384,679,645 bytes
- SHA-256：`4793d1448f292674ff72cbae4cb56b1657ca533cb7a9edac953ae9a8e166387e`
- 完整回归记录：`build/chat-arrival-final-tests-20261006.log`
- 静态检查记录：`build/chat-arrival-analyze-20261006.log`
- 构建记录：`build/chat-arrival-apk-build-20261006.log`

实际页面的 0／80／160／241ms 绘制截图保存在 `build/chat-message-arrival-preview-20261006/`；截图使用测试环境字体，只用于检查移动位置和可视区域裁剪。

模拟测试可验证几何变化和生命周期，设备帧率与最终手感仍需真机体验。本次仅保留测试包，未安装或部署。
