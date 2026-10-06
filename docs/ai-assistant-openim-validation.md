# AI 助理独立 SDK 对话（2026-10-05）

## 实现

「我的 → 热门生态 → AI助手」和会话列表的 `assistant` 单聊统一打开
`AiAssistantChatPage`。账号 `ex` 的 `accountType=official` 也由统一导航识别。
既有 OpenIM 登录的 `userID` / `imToken`、单聊会话、历史、上传和消息 SDK
继续作为生产数据链路，没有新增 Chat HTTP 接口。

视觉复用当前「我的」AI 页面和本地 99chat
`lib/src/pages/ai_assistant/ai_assistant_page.dart`：机器人头像、渐变背景、空状态、
工具栏、输入框和搜索头部。助理页去掉电话／视频按钮及重复好友提示。

新增 `ai_assistant_chat_page.dart`、`AiOpenIMComposer` 和
`AiOpenIMMessageTile` 负责 SDK 会话的组合、助理输入操作和消息显示适配。
原有 AI 预览页依赖独立网关模型，无法直接持有 SDK 的 Message、已读、失败
重试和分页状态，因此新增这些薄适配层。底层继续复用 `ChatLogic`、
`ChatBinding`、聊天消息组件、收藏和表情组件，没有另造消息存储或 SDK 订阅。
共用 `ChatMessageList` 从原聊天页面提取，保留原分页、视口、滚动和多选行为。

图片生成只有选中指令才发 110 / `description=image`；普通出图措辞仍发文本。
好友名片直接发 108，不依赖好友邀请 HTTP 或 `chatToken`；群名片发
110 / `description=groupCard`。PDF、DOCX、TXT 文件保留后缀，最大 20 MiB。
图片表情的 115 `data` 是原始图片 URL。收到的 101 / 102 和错误正文都是 SDK
普通消息；113 正在输入通过常规／online-only 回调显示，不进入历史。

生产页使用现有主题和安全区，支持 Light / Dark、Android / iOS 布局。
附件草稿保留在页面，进入多选再退出不会丢失；已有失败消息行拥有重试，
下次发送不会重复发送同一附件。未创建消息行的附件和失败输入仍保留。
异步动作验证 SDK 账号、`imToken`、收件人及页面关闭状态。

## SDK 流式输出兼容

`assistantStream` 的 online-only 自定义消息直接进入当前单聊的接收回调，
跳过业务信令解析与通知。普通／离线回调收到同类消息时也使用该路径。
SDK 的 `Message` 模型没有 `isOnlineOnly` 字段，客户端以在线回调及
110 / `customElem.description=assistantStream` 识别，不依赖新增 HTTP。

`streaming/assistant_stream_state.dart` 按 `streamID` 隔离增量文字，缓存乱序
`index`，从 0 起连续拼接，忽略重复分片。`end=true` 保留临时内容；
普通 101 的 `ex.streamID` 到达后删除对应临时行，正文由完整 SDK 消息显示。
历史同步中的完整消息也会完成对应流；已完成 ID 拒绝迟到分片。
没有接收分片的设备直接显示普通完整消息。

临时回复使用同一滚动视口和 incoming 气泡／Markdown，但不加入
`messageList`、历史缓存、未读计数、已读请求、搜索结果或多选。
只有流出现／删除时重建列表索引，文字增量只刷新对应气泡。
阅读旧消息时保持已绘制行的位置；查看日期历史窗口时隐藏在线预览，
仅缓冲最终普通消息。并发流与已完成回复之间通过显示锚点保持位置，
最终聊天记录仍遵循 SDK 的消息顺序。

仅接收当前 IM 账号与 `assistant` 的单聊分片，检查发送者／收件人，
关闭页面后清除状态并拒绝旧回调。标题显示「正在回复…」，完整消息
到达后恢复常规状态。身份问题的正文仍由服务端生成，客户端不修改回复。

流式专项新增 21 项测试通过：11 项协议／SDK 回调测试与 10 项真实聊天
控制器页面测试。包括 native online-only 回调、乱序与重复、空末片、并发
回复、历史 final、断线同步、关闭与切号保护，以及长回复在最新位置可见、
上翻时 1px 范围内保持 SDK 行位置、两倍字号／亮暗主题与日期窗口缓冲。
原独立 SDK 页 15 项测试也全部通过。

扩展回归 245 项通过、1 项既有通知测试失败：
`global_performance_regression_test.dart` 的通知用例没有初始化当前通知
runtime，仍期待旧 `promptSoundOrNotification` 路径的会话查询。
本次没有修改该生产通知路径；仅补齐测试 `_FakeApp` 缺少的会话就绪方法，
保留所有原计数和断言。日志 `.dart_tool/ai-stream-regression.log`。
流式及聊天修改的静态检查无 error / warning，保留 1 条既有 SDK 弃用 info；
日志 `.dart_tool/ai-stream-analyze.log`。
流式版本 Android ARM64 debug 构建通过，产物仍为
`build/app/outputs/flutter-apk/app-debug.apk`，日志
`.dart_tool/ai-stream-android-build.log`。服务器流式回复尚未真机联调。

## 验证

- 官方账号解析及导航：11 项通过，涵盖 SDK 会话、草稿／搜索参数、预读、
  「我的」返回栈、资料失败回退、异步账号切换保护。
- 出图／群名片载荷和文档限制：3 项通过。
- 独立 SDK 页面：15 项通过，涵盖实时文字、113 输入状态、普通图片、
  出图指令、空 Chat token 名片、引用 114、失败输入恢复、附件重试归属和
  多选草稿保留；亮暗主题、320px 小屏、横屏、两倍文字、键盘与安全区均通过。
- 扩展聊天／旧 AI 回归：146 项通过、2 项跳过；1 项既有「我的」标题几何测试
  失败，预期指示线距标题 0px，当前实现为 2px。该标题组件未在本次改动。
  日志 `.dart_tool/ai-openim-regression.log`。
- 修改范围静态检查无 error / warning；既有长文件的 41 条 info 保留，主要为
  类型标注、旧 API 弃用和构造参数风格。日志 `.dart_tool/ai-openim-analyze.log`。
- Android ARM64 debug 构建通过，产物
  `build/app/outputs/flutter-apk/app-debug.apk`。日志
  `.dart_tool/ai-openim-android-build.log`。

## 预览

- [亮色对话](previews/ai-assistant-openim-light.png)
- [暗色对话](previews/ai-assistant-openim-dark.png)
- [亮色空状态](previews/ai-assistant-openim-empty-light.png)
- [暗色空状态](previews/ai-assistant-openim-empty-dark.png)

预览样例只来自测试，不会写入生产 SDK。每个主题使用单独测试进程导出，
避免测试字体重载导致离屏截图的文字图层缓存失效。

## 验证边界

SDK 收发使用真实聊天控制器及模拟原生 SDK 返回；未使用生产账号登录服务器。
实际助理模型回复、生成图片、权限校验及跨设备拉取尚未进行真机联调。
iOS 编译需要 macOS；Windows 环境只验证了 iOS 布局约束。
