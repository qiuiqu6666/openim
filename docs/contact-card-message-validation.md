# 个人名片账号与回执验证

日期：2026-10-05。当前 OpenIM Flutter 工作区；99chat 参考版本为 `d7c3c655b20dd06458d1882b114e68c1c24133e3`。

## 结果与数据边界

个人名片的时间与发送/已读图标共同显示在卡片底栏。复用现有 `ContactCardView`、`AvatarView`、`ChatReadReceiptIcon` 和失败重发组件，不创建第二套回执状态。发送成功为单勾、对方已读为双勾；收到的名片不显示自己的发送回执。隐藏已读状态和群消息继续遵守既有策略。

卡片显示 `UserFullInfo.account`，与当前详细资料页使用的 `displayedUserID` 相同。OpenIM 的 `CardElem.userID`、点击目标、服务端名片邀请和好友申请凭证保持原值。截图中的内部 `im_...` 标识不会被截取或解码成假账号。

新发送的名片携带目标绑定的公开账号快照，并保留原 `inviteCode`。旧名片使用当前 `user/find/full` 接口补齐；无法获得公开账号时保持该行空白，仅原始纯数字旧 ID 可直接显示。查询不会显示加载条或弹错误提示，保留行高避免补齐时抖动。

查询服务合并请求，按用户与 token 隔离，最多保留 256 项 LRU 结果；网络失败可重试。组件关闭、目标或扩展字段原地变更、旧请求迟到和会话切换均有保护。当前会话的鉴权错误仍正常处理，旧会话的鉴权错误不会退出新账号。

选择好友与推荐名片在选择器打开前捕获登录会话，各次异步等待后重新核对；关闭聊天或换账号时停止后续创建和发送，也不在新页面弹迟到的失败提示。推荐流程会接住异常，真正属于当前会话的错误继续使用既有发送失败提示。

## 参考与复用

99chat 的 `lib/utils/custom_message/contact_card_message_item.dart` 提供既有蓝色名片主体与时间底栏参考，其底栏没有本次用户要求的 OpenIM 回执。回执布局由当前组件扩展完成，未复制 Tencent 业务流程或新增图片资源。亮暗主题、小屏大字体使用相同名片结构。

协议、解析服务与身份组件分别维护在公共包 `models/contact_card/`、`services/contact_card/`、`widgets/chat/contact_card/`。现有 `Apis`、名片邀请 helper 和共享消息组件仅增加必要兼容参数，未把新身份解析职责继续堆入公共大文件。

## 验证场景

- 17 项协议与解析服务检查：快照与 SDK 目标绑定、错误字段、数字旧 ID、真实邀请接口载荷、匹配目标资料、并发合并、缓存边界、失败重试、256 项 LRU、换账号、换 token、登出和迟到响应。
- 11 项消息组件检查：亮暗主题的单勾/双勾位置、接收卡片、隐藏已读、群消息、失败重发、真实点击资料导航、旧名片补齐且高度固定、SDK 对象原地变更、关闭保护、发送延迟及小屏两倍字体。
- 9 项真实 API 与 HTTP 拦截器检查：`1501`、`1506`、`20101` 在账号或 token 改变后不触发退出，当前会话每个错误仅触发一次。
- 27 项名片发送生命周期检查：选择器之前固定会话，关闭/账号/token/SDK 用户变化后不发送，迟到邀请或 SDK 构造结果与错误不弹提示，当前真实错误提示一次，推荐备注和卡片等待发送后停止后续操作，正常单人及群接收路径保持原 SDK 目标与邀请扩展。
- 邻近回归包含名片原有行为、好友来源、消息气泡、表情元信息、逐条/合并转发、消息行与语音菜单。原语音消息行测试夹具改为明确四行，符合其既有“超过三行才可收起”的行为；生产语音逻辑未修改。

预览使用测试夹具；实际账号与回执仍来自当前资料接口和 OpenIM SDK。四张预览已经检查：

| 场景 | 亮色 | 暗色 |
| --- | --- | --- |
| 375×812，发送未读/已读及接收名片 | [亮色](previews/contact-card-message-light.png) | [暗色](previews/contact-card-message-dark.png) |
| 320×568，两倍字体、长昵称与账号 | [亮色大字体](previews/contact-card-message-light-large.png) | [暗色大字体](previews/contact-card-message-dark-large.png) |

## 最终检查

专项 64 项与相邻 56 项，共 **120 项全部通过**。本轮将测试 SDK 的未初始化登录用户字段在夹具中初始化，并为真实资料 API 测试挂载 Get 页面上下文；未绕过生产接口、SDK 建卡或真实点击资料路径。

```text
flutter test --no-pub
  test/pages/chat/messages/contact_card
  test/contact_card_test.dart
  test/friend_add_source_test.dart
  test/chat_bubble_layout_test.dart
  test/pages/chat/stickers/sticker_metadata_overlay_test.dart
  test/pages/chat/messages/forwarding/chat_forwarding_controller_test.dart
  test/pages/chat/messages/chat_message_tile_test.dart
  test/pages/chat/voice/voice_message_transcription_menu_test.dart
  test/session_invalidation_http_test.dart
  --dart-define=CONTACT_CARD_MESSAGE_PREVIEW=true
```

13 个身份模型、查询、卡片组件、消息容器、发送状态、转发控制器与相关测试文件的 scoped analyze 无问题。单独检查既有 `apis.dart` 与 `friend_add_source.dart` 时仍有 6 项原有单行 if 缺少大括号的 info，均不在本次新增逻辑处；没有新错误或警告。相关文件 `git diff --check` 通过。

最终代码执行 `flutter build apk --debug --no-pub` 成功，产物为 `build/app/outputs/flutter-apk/app-debug.apk`。

未在真实设备上发送新的名片或发起线上好友申请；iOS 原生构建未运行。

维护入口：[个人名片消息](../openim_common/lib/src/widgets/chat/contact_card/README.md)。
