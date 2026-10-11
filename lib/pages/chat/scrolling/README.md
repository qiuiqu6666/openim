# 聊天新消息提示

`ChatNewMessageTracker` 只拥有当前聊天页面的新消息计数、去重记录和是否离开底部的状态。它不拥有滚动控制器、消息列表、SDK 订阅或消息已读回执，也不依赖 `ChatLogic`。

接入时使用当前页面的用户 ID getter，并把包含账号/token 失效判断的关闭 getter 注入 `isClosed`。页面正常关闭时调用 `close()`；清空当前聊天时调用 `reset()`。

- 反向消息列表使用 `pixels - minScrollExtent`，离最新位置超过 48 个逻辑像素才退出自动跟随，真实视口回到 24px 内恢复跟随，避免轻微滚动或尺寸抖动在 600 条窗口上误触发历史暂存。普通滚动监听与 SDK 收消息前只能确认离开；重新贴底由 `onViewportChanged` 完成布局后的真实距离确认，或用户明确点击回底后确认。未看见计数仍只在真实距离不超过 1px 或气泡实际可见时清除。历史窗口尚有较新消息时，即使局部距离为零也保持历史状态和回底入口。公共列表稳定中心之前的新消息可产生负滚动范围，不能把绝对零点当成底部。
- 只把当前会话 SDK 实时接收事件交给 `recordIncoming(message)`。初次进入页面的未读数、历史分页、缓存恢复和历史刷新都不能调用它。本人消息、typing、缺少 ID 的消息不会计数。
- 气泡实际进入视口时调用 `markVisible(clientMsgID)`。列表 build、离屏预构建或仅仅滚动了一段距离不能当作消息已看见。
- 删除或撤回消息调用 `remove(clientMsgID)`，只扣掉尚未看见的消息。
- UI 将阅读状态 `awayFromLatest` 与按钮状态 `showBackToBottom` 分开：离底超过半个消息视口才显示“回到底部”，回到 0.45 个视口以内隐藏，避免小幅移动或阈值附近抖动时频繁显隐。阈值使用消息列表实际高度，无有效布局时按 600px 兜底，集中定义在 `ChatLatestScrollTokens`。对照 99chat 的 `BackToBottomCapsulePolicy` 半屏显示与 0.45 屏隐藏规则。
- “X 条新消息”仍由实际未看见的实时消息计数优先显示；日期/搜索定位到历史窗口且还有较新消息时保留回底入口，不受半屏门槛影响。回到底部隐藏并清空计数。按钮显隐与贴底缓冲区独立，不改变 SDK 已读回执。

同一次页面生命周期内，已看见、已删除和在底部收到的消息都保留接收 ID，避免 SDK 重复回调再次增加计数。`reset()` 和 `close()` 清空这些记录。该模块仅有内存集合与 GetX Rx 状态，没有异步任务、计时器或 SDK 资源。

本轮验证：317 项聊天相关测试全部通过，其中新增 54 项（计数 10、真实 SDK 接线 16、公共列表 14、提示按钮 14）；覆盖 1000 条不同高度消息、同帧拖动与接收、估算边界精化、删除撤回、账号/令牌切换和关闭。相关静态分析无 error/warning，保留 11 条既有 info；Android debug 构建成功。这里的 317 项为聊天相关范围，不代表全项目测试统计。

模块测试位于 `test/pages/chat/scrolling/chat_new_message_tracker_test.dart`。真实 SDK、页面协调和公共列表的组合测试归 `test/integration/chat/chat_entry_performance_test.dart`，大批量变高消息与活跃手势场景注册在同目录 `chat_new_message_cases.dart`；二者共用 `test/support/chat` 的挂载和 SDK 假实现。运行 `flutter test test/pages/chat/scrolling/chat_new_message_tracker_test.dart test/integration/chat/chat_entry_performance_test.dart`。

`ChatLatestScrollController` 独立负责返回最新端和自动跟随请求合并。输入框获得焦点或点击“回到底部”/新消息提示时，以先慢后快的缓动回底，同时保留焦点和键盘。`ChatLatestScrollTokens` 集中管理动画：首段按距底部的屏数使用 300–650ms 与 `easeInCubic`，较远时适当延长；键盘改变视口或懒加载精化边界后，有限次数重新确认最新端并以短动画校正。只允许末端不超过 1px 的精确定位，不能在多次校正后大幅跳转；仍未到实际底部时保留提示，不提前发布抵达通知。自动跟随不抢占这次动画，显式非动画定位可以替代动画。只有带手势信息的消息列表滚动会取消回底并收起键盘，程序滚动和键盘布局不收起键盘。减少动画设置下直接定位；关闭和手势取消都使旧异步完成回调失效，滚动控制器仍由页面协调器释放。

回底交互对照 99chat 的 `TIMUIKitTongue/tim_uikit_chat_history_message_list_tongue_container.dart`：复用其按距离调整时长、`easeInCubic` 和大残差继续动画的行为；继续使用本项目已有滚动控制器、真实 SDK 历史窗口与视口可见性回调，不新增消息或已读状态来源。

回底模块测试位于 `test/pages/chat/scrolling/chat_latest_scroll_controller_test.dart`；输入框、真实 SDK 接线及公共列表的组合场景注册在 `test/integration/chat/chat_keyboard_scroll_cases.dart`，复用聊天入口测试环境。覆盖动画中间帧、键盘渐进展开、手势中断、新消息到达、减少动画、关闭以及显式跳转替代。

2026-10-05 回底动画验证：改动文件静态检查通过，滚动、历史窗口、聊天入口、日期定位、可视已读和新消息提示的既有 85 项回归及新增 2 项行为回归，共 87 项分批通过。`test/integration/chat/chat_back_to_bottom_motion_test.dart` 挂载真实 `ChatPage` 并点击生产按钮，验证相同时间段的位移逐渐增加、中途提示保留、最终最新气泡完整可见；控制器测试覆盖真实双 sliver 最新端持续移动时不大幅跳转、不误发抵达通知。Android debug 构建成功，保留调试包 `build/app/outputs/flutter-apk/app-debug-chat-smooth-bottom-20261005-5370a16dd51f.apk`；SHA-256 为 `5370a16dd51f220112f683e0b350b9b68b1311e62a69d5aaa74d77d81b483b8f`。没有安装到设备或部署服务，真机连续滚动观感仍需复测。
