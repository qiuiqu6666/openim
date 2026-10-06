# 聊天搜索定位与自动双向分页验证

日期：2026-10-05。工作区：`E:/openim/openim-flutter-demo`。

## 行为

历史搜索的原消息入口原先进入「消息上下文」独立页面，并需要点击加载前后消息。现在关键词、日期、发送人、语音及私密内容的原消息入口先确认精确 SDK 记录，再返回实际聊天页，定位并短暂高亮目标。对应聊天路由仍在当前 navigator 中时复用原页面、控制器、输入框与草稿；其他会话使用已有普通聊天、官方账号与助手分流入口。

真实聊天继续使用 SDK 目标前后的连续消息窗口与现有消息 ID viewport。上下滑到更早或更新边界时自动请求对应页；短列表也能按用户拖动方向分页，普通成功加载没有加载按钮。失败仍提供重试。

99chat 的消息搜索和 byDate/byMember 入口作为交互参考；OpenIM SDK、消息窗口、输入、回执、私密消息与账号生命周期继续使用现有所有者。

## 归属与异步保护

- `history_search/navigation/chat_history_message_navigation.dart` 校验入口及目的路由身份、完整账号/令牌、精确 SDK 消息与会话，处理已删除/过期消息及重复点击。返回原聊天后由目的聊天接管定位，预期销毁的搜索入口不会取消它。
- `navigation/chat_message_focus_controller.dart` 持有高亮计时器和取消世代。`ChatLogic` 只保留当前会话守卫、路由绑定与定位入口；具体历史加载与位置计算留在既有独立模块。
- `ChatDateWindowController` 只有在真实 SDK 窗口已建立且没有在途分页/刷新时才直接定位已加载目标。首屏缓存或在途 latest/refresh 会重新安装目标窗口，旧结果不能移除目标。
- `ChatListView` 两端共享加载保护。`newerHasMore` 由实际窗口控制；loader 的窗口世代传入 `pagingWindow`，使旧请求的结果、异常及结束回调不能修改或堵住新的窗口。普通增页和实时消息不会重置归属。
- 手指拖动、清空、关闭和账号切换继续取消迟到定位；历史窗口的实时消息继续去重缓冲，到 SDK 最新边界后接回正常聊天。阅读位置与回执沿用现有 viewport。

## 验证

Flutter SDK：3.41.6，使用当前 package config 对应的 `E:/flutter/flutter`；验证使用 `--no-pub`，没有改依赖。

| 范围 | 结果 |
| --- | --- |
| 历史搜索、历史窗口、消息导航、真实 ChatLogic 集成、公共聊天列表回归 | 486 项通过；10 个需要输出目录的预览任务跳过 |
| 新的具体路由导航契约 | 20 项通过 |
| 新的真实聊天搜索定位与双向拖动集成 | 9 项通过，覆盖亮暗主题、页面/草稿复用、20 条前后 SDK 窗口、实时缓冲、缓存启动、晚到结果及消息/账号守卫 |
| 新的高亮异步回归 | 7 项通过 |
| 新的公共自动分页与窗口归属回归 | 14 项通过 |
| 新的缓存启动、在途刷新定位回归 | 2 项通过 |
| 变更模块及测试静态检查 | 没有 error/warning；38 个既有 info，使用 `--no-fatal-infos` 完成检查 |
| Android 调试 APK | 构建成功，输出 `build/app/outputs/flutter-apk/app-debug.apk` |

原个人资料导航测试补齐 SDK 账号、令牌、本地存储和普通成员查询 fixture，原业务断言保留。搜索组件测试的正向原消息跳转改为验证真实聊天导航契约，实际 route 复用和滚动由真实 ChatLogic 集成验证。

本轮测试通过 SDK channel 注入真实接口参数并在 Flutter viewport 中执行手势；未进行物理 Android/iOS 设备手势验证，也未构建原生 iOS。独立的旧 `MessageContextPage` 保留兼容测试，搜索入口已迁到实际聊天。

日志保存在 `E:/openim/.temp/chat-search-navigation-regression.log`、`chat-search-navigation-analyze.log`、`chat-search-navigation-build.log`。
