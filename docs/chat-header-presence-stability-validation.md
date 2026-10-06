# 聊天头部在线时间稳定性验证

日期：2026-10-05。范围：普通聊天头部进入时的在线时间闪变及状态行跳动。

## 原因与修复

原资料/聊天页注册或释放 presence 所有者会强制刷新，导致已订阅用户也被
重新订阅。SDK 事件又会立即覆盖状态：离线时先生成当前时间，随后接口把
实际最近在线时间写回来。同一用户短时间内因此出现不同的在线文案。
副标题在未加载时不存在，加载后加入，还会让居中的昵称上下移动。

- `ContactsLogic.setProfilePresence` 去重所有者与用户，使用增量订阅。
  已确认的共享用户不重复查询；首次失败、缺少快照的用户仍可重试查询。
  前台恢复、SDK 重连和同步完成保留原强制刷新路径。
- SDK 状态事件只作为变化通知，120 ms 内的通知合并查询既有
  `/chat/users/presence`。接口一次确认在线状态、lastSeenAt 和隐私。
  等待期间保留已确认快照，避免生成中间在线状态或猜测「刚刚在线」。
  新事件立即使旧查询失效，旧查询在批次开始前或后返回都不会覆盖状态。
- 只处理被当前页面订阅的合法状态，后台、关闭、旧账号及旧凭证不产生
  新的状态批次。HTTP 回包继续校验请求版本，新增相同用户更换 chatToken
  时的过期回包校验。SDK 状态数值核对了
  [OpenIM 官方协议常量](https://github.com/openimsdk/protocol/blob/main/constant/constant.go)：
  online 为 1，offline 为 0；其他值不会被当成离线。
- `TitleBar.chat` 为单聊保留固定的副标题行。未知或关闭显示时为空文本，
  不显示虚构状态、不残留旧语义。昵称、头像和状态行在文字切换时位置稳定。
  `ChatPage` 和标题栏使用同一字体缩放高度；群成员行按原自然行高计算。

## 参考与复用

对照了本地 `reference-99chat` 的实际实现：

- `lib/src/widgets/chat_header_title.dart:159` 的状态投影去重，`:196`、
  `:521` 的状态行布局，以及 `:264` 的同用户加载去重。
- `lib/src/widgets/presence_subtitle.dart:59`、`:68` 的加载和空状态等高占位。
- `lib/src/provider/presence_provider.dart:425` 的相同状态不重复通知。

继续复用现有 `TitleBar`、`AvatarView`、`ContactsLogic`、`PresenceStore`、
`ContactPresencePolicy`、主题 `Styles` 与 `AppTokens`，没有新增重复组件。
数据仍来自现有 SDK 变化通知和已有 Chat presence 接口，缓存仍按用户保存。
官方账号在线展示、全局显示偏好、隐私、正在输入、通话及设置入口保持有效。
这是现有订阅生命周期和标题布局的局部修错，没有新增路由或控制器职责。

GitNexus 的仓库列表没有当前 Flutter 仓库，因此调用链由当前源码核对，
没有使用其他仓库的索引推断本项目行为。

## 验证结果

| 检查 | 结果 |
| --- | --- |
| 状态、标题、共享联系人页面、选择模式回归 | 109 项通过 |
| 联系人分页、关闭、事件合并性能回归 | 4 项通过 |
| 本次 4 个实现文件与 3 个测试文件静态检查 | 无 error/warning；TitleBar 保留 3 条原有 info |
| 修改文件差异格式检查 | 通过 |
| Android ARM64 debug 构建 | 成功，15.3 秒 |

113 项相关测试覆盖：重复进入/多所有者、初次失败重试、SDK/HTTP 返回顺序、
两次过期请求、前后台切换、账号和同账号 token 变化、取消订阅、关闭、隐私、
官方账号策略、真实后续在线变化。标题检查覆盖亮暗主题、320/375 宽、1×/2×
字号的空状态→在线→输入中→最近在线→空状态，校验位置、文字边界和语义。

日志位于 `.dart_tool/chat-header-presence-stability-tests.log`、
`chat-header-presence-stability-contacts-performance.log`、
`chat-header-presence-stability-analyze.log`、
`chat-header-presence-stability-build.log`。调试包为
`build/app/outputs/flutter-apk/app-debug.apk`。

扩展检查中的既有 `global_performance_regression_test.dart` 通知查询用例
仍失败，单独运行也可重现（期望 1 次查询，实际 0 次）。该夹具直接构造
`_NotificationApp` 而未调用当前通知模块的 `onInit`；当前 `showNotification`
委托给初始化后才存在的运行模块，因此旧夹具不匹配。此用例没有使用本次
presence 或标题路径，未为此修改通知业务。完整文件其余 12 项通过，其中
涉及本次联系人控制器的 4 项在最终代码下单独再跑通过。

尚未在用户实机上验证连续进出、真实服务状态延迟或 iOS 原生构建。
