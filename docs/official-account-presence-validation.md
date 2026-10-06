# 官方账号在线展示验证

日期：2026-10-05。

## 行为

官方账号始终提供「在线」展示状态：固定 ID `assistant`、`99Message`、
`99Pay`，以及真实 SDK 资料 `ex` 的 `accountType` 为 `official` 的账号。
昵称、备注、无效 JSON 不会改变普通用户的状态。

`ContactPresencePolicy` 复用既有官方身份判断、`UserPresence`、
`PresenceLabel` 及在线显示偏好。通讯录、好友/名片/建群选择、历史发送者、
群成员列表、普通单聊标题和长按预览统一使用此展示策略；已有官方通知
页在线标题及 AI 助理专属页的产品/正在回复提示继续保留。

历史发送者从原 `getUsersInfo` 查询带回 `ex`。没有增加查询、HTTP 接口
或 SDK listener。原账号缓存、真实 SDK 在线快照、可见用户订阅和普通
用户隐私状态保持原样；SDK 离线更新不改变官方在线文案。
全局关闭在线状态展示及页面原有账号有效性检查继续生效。

本次复用现有联系人两行布局及亮暗主题，没有调整尺寸或新增图片资源。
参考沿用本地 99chat 的 `contact_list_with_presence.dart`、
`contact_list.dart` 和 `tim_uikit_conversation_member_picker_page.dart`
对应的既有页面结构；官方状态规则来自本次用户要求。

## 已执行

- 14 个相关测试文件，共 **137 项通过**：共享展示策略、亮暗通讯录、
  好友选择/生命周期、个人名片选择、目录订阅所有权、历史发送者及 SDK
  资料源、真实会话长按预览、presence 缓存/隐私、官方页和 AI 助理页。
- 新回归验证：空缓存/SDK 离线更新持续在线、普通同名用户仍离线、普通
  最近上线隐私不变、全局偏好隐藏、历史发送者换号保护、通知账号选择
  限制保留、预览不改未读且不写 SDK、原缓存未被修改。
- 10 个修改过的生产文件静态检查无错误/警告。原群成员列表有两条既有
  info 级样式提示（if 花括号、super parameter）；6 个修改过的测试文件
  静态检查无问题。
- Android ARM64 debug APK 构建成功，15.1 秒。

测试日志：`.dart_tool/official-account-presence-tests.log`。
静态检查日志：`.dart_tool/official-account-presence-analyze.log`、
`.dart_tool/official-account-presence-test-analyze.log`。
构建日志：`.dart_tool/official-account-presence-build.log`。
产物：`build/app/outputs/flutter-apk/app-debug.apk`。

本次未执行真机联网联调和原生 iOS 构建。状态规则在客户端展示层生效。
