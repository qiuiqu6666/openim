# 群聊入场：公告与直播入口位置稳定

日期：2026-10-05。

## 问题与修复

群公告原先从空值开始，首批历史后才读取 SDK 群资料；公告组件随后又异步读取关闭状态。群聊顶部的公告因此先隐藏再出现，将下方直播入口和消息区推下去。直播入口原先只读取群摘要，忽略账号共享仓库中已由 `/current` 确认的公开状态，重进时可能先隐藏再恢复，或短暂显示已经结束的场次。

现在 `ChatGroupController.initialize()` 从现有账号共享 `GroupFeatureStore` 同步取已确认的群资料，先设置公告版本，再设置正文。首批历史后的真实 SDK 查询继续校准成员资格、资料及角色。缓存不填充自己的成员资料、角色或管理员列表；缓存读取仍检查账号、群、退群和关闭状态，并返回资料的防御复制。

`ChatPage` 将应用启动时已初始化的 `SpUtil().prefs` 交给现有 `GroupAnnouncementBanner`。组件在布局前同步决定这条公告是否被当前账号关闭，不再先绘制零高度。未读提示继续在首帧后按原流程打开，异步结果检查加载世代、账号/群键和公告版本。关闭公告继续只作用于当前用户、当前群、当前版本；新的公告正常显示。

`GroupFeatureContext.liveFeature` 使用已接受的公开直播投影，包含 `/current` 返回的 `active:false`，缺少投影时才使用群摘要。现有 `GroupLiveFeatureHost` 首帧使用这个状态，再后台校准真实 `/current`。无变化的权限更新或父级重建不替换同一场次 DTO，保留场次版本。读取携带 `minimumSession`，同场次低版本响应在回写摘要、发布共享显示通知之前拒绝；真正的结束、换场及新状态继续生效。公开投影不保存播放地址或推流密钥，不改变私人能力校验。

## 99chat 对照与复用

已对照本地 `reference-99chat` 的实际实现：

- `lib/src/chat.dart` 的 `_seedGroupLiveFromIndex`、群公告本地同步、关闭状态检查与相同内容去重。
- `lib/src/services/group_live/group_live_chat_state.dart` 的同步 `seedFromIndex` 和后台刷新保留已接受状态。
- `lib/src/widgets/chat_top_fix_view.dart` 的公告、直播、游戏入口顶部排列。
- `lib/src/chat_page/chat_top_fix_state_controller.dart` 的顶部状态去重。
- `lib/src/services/group_notice_marquee_dismiss_service.dart` 的用户、会话关闭状态隔离。

继续复用 OpenIM 群事件和查询、`GroupFeatureRuntime/Store`、`GroupAnnouncementBanner`、`GroupChatFeatureSurface`、`GroupLiveFeatureHost` 和 `GroupLiveBanner`。没有新增页面、组件、路由、依赖、轮询或 SDK 监听器；仅扩展现有状态与组件参数。展示样式、按钮和主题 token 保持现有实现，数据仍来自 OpenIM SDK、当前 Chat 直播服务及既有本地设置。

## 验证

新增回归用例分别覆盖：缓存公告首帧、仍执行真实 SDK 校准、角色边界、退群/账号变化/关闭后的迟回包、公告关闭和新版本、亮暗主题、小屏及大字体、重复进入的公告/直播/消息区精确位置、直播结束实际移除入口、有效/无效公开投影、权限刷新保持 DTO、同场次低版本响应零共享发布。

实际执行结果：

- `flutter test --no-pub --reporter expanded` 执行全部 `test/pages/group_features`，以及 `chat_group_controller_test.dart`、`group_chat_entry_geometry_test.dart`、公告目录、聊天入场性能、回到最新消息动画和聊天头部测试：480 项通过，7 个需要显式导出预览开关的用例按原规则跳过，无失败。
- 新增公告与直播组合位置测试独立执行也通过：3 项。使用真实群状态控制器、账号仓库及生产公告/直播组件，逐帧比较公告、直播和消息区边界；不使用固定占位栏模拟入口。
- 对本次 8 个生产文件及 6 个测试文件执行 `dart analyze`：没有错误或警告；保留 1 条既有 `chat_logic.dart:1091` 的 `resetConversationGroupAtType` 弃用提示。
- `flutter build apk --debug --target-platform android-arm64 --no-pub` 成功，Gradle 16.7 秒。`build/app/outputs/flutter-apk/app-debug.apk` 已于 2026-10-05 14:02 更新。

完整日志保存在 `.dart_tool/group-chat-entry-stability-tests.log`、`.dart_tool/group-chat-entry-stability-geometry-tests.log`、`.dart_tool/group-chat-entry-stability-analyze.log` 和 `.dart_tool/group-chat-entry-stability-build.log`。

## 边界

没有已确认缓存的首次访问仍需等待真实数据，不能预先虚构公告或直播。真正新增/关闭公告、开始/结束直播所需的布局变化仍然发生。直播主播头像继续在固定头像槽内由 SDK 解析，不承诺首次位图加载完全无变化。

本次修复保留既有账号、群、请求取消、摘要版本与场次版本守卫；没有扩展为独立列表/聊天请求的全局响应代际排序。未携带完整群摘要、来自不同调用者的并发 `/current` 响应仍使用既有共享投影机制。

尚未在真实 Android/iOS 设备录屏检查入场动画，未验证原生直播源、实际推流或播放。当前改动不涉及原生播放器或通话流程。
