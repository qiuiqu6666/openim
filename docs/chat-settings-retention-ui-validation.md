# 聊天设置与消息保留界面验证

日期：2026-10-05。

## 设计与维护范围

单聊设置参考实际 99chat 源码 `E:/openim/reference-99chat/lib/src/pages/c2c_chat_settings_page.dart` 的成员、搜索、开关、背景和清空分组。参考项目未找到对应消息保留页，因此该页复用当前应用的统一设置组件。两页使用 `SettingsScaffold`、`SettingsGroup`、`SettingsCell`、公共 `AppSwitch` 及现有选择弹层、确认框，继续使用 `AppTokens` 的亮暗颜色、14px 卡片圆角和间距。

单聊页按用户最新截图及补充要求依次显示成员、消息保留设置、查找聊天内容、置顶聊天 / 消息免打扰、背景、清空记录、投诉；普通设置行没有左侧图标，清空记录使用普通文字颜色，两条开关之间的分隔线左右内缩。成员及添加成员整块可点击，添加按钮为灰色圆形描边，标签使用次级文字颜色。成员标题最小高度 48、头像 48、操作项正常宽度 76，加号尺寸 30，均依据实际参考源码；大字体仍允许文字换行。

消息保留页采用整行选择，显示当前时长，在选择弹层标记当前设置；窄屏或大字号自动将标题与时长分行。按用户补充要求，该入口位于成员卡下方、查找内容上方，点击传递当前会话并打开原有页面及 SDK 实现。

页面数据来自原有 OpenIM SDK 与 GetX 控制器。消息保留使用 `getMultipleConversation` / `setConversation`，首次加载和保存后读取真实设置；保存失败不更新显示值，并允许重试。保持独立字段提交及关闭时省略时长的行为。控制器仍负责原有 SDK 订阅和取消；用户、凭证及关闭保护避免迟到回调更新失效页面。好友资料刷新不会丢失待完成的开关保存，较新的会话事件也不会被保存回调覆盖。新增专用组件集中于单聊设置模块，未重写公共设置、群管理或 SDK。

当前 OpenIM SDK 与已接入 Chat 服务没有直接提交单聊投诉的能力。投诉入口显示对方账号，用户确认后打开现有人工客服；不会自动发送消息、提交聊天内容或显示投诉成功，不使用参考项目的未知 `/me/complaints/c2c` 接口。

## 已执行验证

| 范围 | 结果 | 记录 |
| --- | --- | --- |
| 消息保留入口及相关页面验证 | 20 项通过，含当前会话的 SDK 读取、保存 / 重试、正常预览及亮暗大字体 | `.dart_tool/chat-settings-retention-entry-tests.log` |
| 当前控制器生命周期与投诉确认测试 | 12 项通过 | `.dart_tool/chat-settings-reference-logic-tests.log` |
| 此前单聊设置与消息保留综合验证 | 28 项通过，含 2 项真实 Widget 预览；保留历史记录 | `.dart_tool/chat-settings-final-tests.log` |
| 原有消息保留 SDK 契约用例 | 1 项通过，保留 `setConversation` 提交字段断言 | `.dart_tool/chat-settings-sdk-retention-test.log` |
| 当前生产源文件及模块测试静态分析 | 无问题 | `.dart_tool/chat-settings-retention-entry-analyze.log` |
| 扩展目录及旧 SDK 测试文件分析 | 无错误或警告；7 条既有提示位于未改动的上下文页面或其他 SDK 用例 | `.dart_tool/chat-settings-analyze.log` |
| 相关已跟踪文件空白检查 | 通过 | `git diff --check` |
| 当前 Android ARM64 调试构建 | 成功，`build/app/outputs/flutter-apk/app-debug.apk` | `.dart_tool/chat-settings-retention-entry-build.log` |

测试覆盖加载失败、重试合并、保存失败后保留原值、非预设时长、取消选择、关闭时的字段、群聊隐藏阅后即焚、退出页面、同账号凭证变化、迟到初始加载、资料刷新与设置事件并发、重复清空确认、切换账号时拒绝旧清空，以及 SDK 成功后才清空界面。

UI 验证包括 320×640 / 两倍文字大小下的亮暗主题、开关组裁剪、滚动到清空和投诉行并实际点击、安全区底部、各入口的实际阅读顺序，以及正常预览页面的返回按钮实际可点击。投诉流程覆盖重复点击只打开一个确认框、取消后可以重开、取消不打开客服，以及账号 / 凭证变化后不能确认进入旧投诉的客服流程。

## 实际页面预览

由真实生产 Widget 渲染，预览资料和 SDK 模拟回复只存在于测试。正常预览为 375×812，两倍像素输出；小屏预览为 320×640，两倍字体。

- [聊天设置正常预览](../artifacts/chat-settings-2026-10-05/chat-setup-normal-light.png)
- [消息保留正常预览](../artifacts/chat-settings-2026-10-05/message-retention-normal-light.png)
- [聊天设置深色大字体](../artifacts/chat-settings-2026-10-05/chat-setup-dark.png)
- [消息保留深色大字体](../artifacts/chat-settings-2026-10-05/message-retention-dark.png)

已人工检查正常两页及亮暗大字体截图，未见布局溢出。聊天设置的长列表可滚动访问后续操作。

## 验证边界

首次扩展运行 `test/sdk_feature_completion_test.dart` 时，两个既有群成员角色 / 免打扰用例仍查找已不存在的 `PopupMenuButton<int>`，未通过；本轮未修改群管理页面及这两个用例，日志位于 `.dart_tool/chat-settings-tests.log`。本轮最终单聊设置与消息保留验证均通过，不能据此宣称整个旧 SDK 测试文件全部通过。

尚未进行真机、真实服务端保存及双设备同步联调。业务行为维持原有 SDK 路径，截图和方法通道测试不代替实机验证。

## 圆形添加成员按钮补充验证

此前按用户反馈将添加成员的 48×48 背景改为圆形，当时 8 项页面用例通过且仅更新背景形状。最新截图调整已进一步改为灰色描边圆形，并按本文件上表重新完成当前页面验证与 Android 构建。

## 全局开关与免打扰命名补充验证

置顶聊天和消息免打扰两行使用 `SettingsCell.trailing: AppSwitch`，复用
公共包与好友权限、添加好友隐私、群管理相同的组件。Android / iOS 均为
同一 Cupertino 外观，关闭轨道灰色，开启颜色取 `Styles.c_0089FF` 的亮暗
主题值。参考 99chat 单聊设置使用 Cupertino 的实际实现，同时按本次
用户要求以当前项目的全局组件为准。没有新增开关、修改公共组件或
其他页面；原状态值、SDK 保存、保存/清空期间禁用及分隔线保持原样。

- 27 项设置和好友权限相关测试通过，含 Android/iOS × 亮暗的实际开关
  点击、分别等待置顶/免打扰保存、两控件禁用、重复点击及保存后值；
  消息保留 SDK 读写、原页面入口、小屏大字号回归继续通过。
- 改动页面及两个测试文件静态检查无问题；测试 host 的平台参数仅用于
  测试，并随亮暗主题同步 `Styles.isDark`，结束后恢复。
- 已检查真实生产 Widget 导出的 Android 亮暗关闭/开启四张预览，形状、
  轨道和滑块均与全局组件一致，没有描边关闭轨道或布局溢出。
- 会话左滑中文按钮改为「消息免打扰」，已开启时改为「取消免打扰」；
  保留英文 `Mute` / `Unmute`、原切换回调及既有单行自适应宽度。
  9 项会话布局/实际滑动回归通过，1 项未设置输出目录的可选预览跳过。
  语言文件静态检查无错误/警告，保留两个既有文件/常量命名 info 提示。
- 包含两项修改的 Android ARM64 debug APK 构建成功，14.2 秒；产物为
  `build/app/outputs/flutter-apk/app-debug.apk`，构建日志为
  `.dart_tool/chat-settings-global-switch-and-label-build.log`。

日志：`.dart_tool/chat-settings-global-switch-tests.log`、
`.dart_tool/chat-settings-global-switch-analyze.log`、
`.dart_tool/conversation-mute-label-tests.log`、
`.dart_tool/conversation-mute-label-analyze.log`。

当前开关预览：

- [Android 亮色关闭](../artifacts/chat-settings-2026-10-05/chat-setup-switches-android-light-off.png)
- [Android 亮色开启](../artifacts/chat-settings-2026-10-05/chat-setup-switches-android-light-on.png)
- [Android 暗色关闭](../artifacts/chat-settings-2026-10-05/chat-setup-switches-android-dark-off.png)
- [Android 暗色开启](../artifacts/chat-settings-2026-10-05/chat-setup-switches-android-dark-on.png)

原生 iOS 构建及真机联网保存仍未执行。
