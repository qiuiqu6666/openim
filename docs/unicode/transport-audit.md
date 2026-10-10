# Unicode 传输与存储检查

本记录区分可读取的当前客户端源码、受控自动化测试、公开上游源码和未验证的部署环境。测试 fixture 仅按 Unicode 结构选取代表样本，生产代码不依赖样本、Emoji 白名单或字符枚举。

## 当前客户端链路

| 环节 | 检查的实现 | 结果 |
| --- | --- | --- |
| 草稿 | `ChatComposerController.saveDraft/restoreDraft`、`conversationDraftText` | JSON 保存/恢复原始文本与 @ 元数据，不做 Unicode normalize；Flutter selection offset 保持 UTF-16 协议语义。 |
| 创建和发送 | `ChatMessageSender`、`ChatDeliveryController`、SDK `MessageManager` | 使用原始 String 与 `Message.toJson`；发送完成通过 SDK 真实回执更新状态。目的地和账号校验不修改正文。 |
| 普通/引用/@/合并 | SDK `TextElem`、`QuoteElem`、`AtTextElem`、`AtUserInfo`、`MergeElem` | 序列化的文本、被引用原文、@ 昵称和合并原文均保留 String。展示摘要是独立视图，不回写消息内容。 |
| 历史与预览 | `ChatHistoryLoader`、`ChatHistoryCache`、`ConversationPeekLoader` | 排序、消息条数上限、账号隔离和隐私过滤按消息对象操作，不裁切文本；预览 JSON 深拷贝保留原始序列。 |
| 本地搜索 | SDK `searchLocalMessages`、`SearchResult` | 关键词通过 method channel 原样传递，返回正文通过 `Message.fromJson` 读取。自动化测试覆盖参数与返回模型；没有执行真实 SDK SQLite 搜索。 |
| 收藏/笔记 | `favorite_repository`、`favorite_message_builder`、`favorite_models` | 正文使用 JSON/String；空白仅用于必填验证，64 KiB UTF-8 限额属于载荷字节限制，不转换成可见字符限额。 |
| 本地与应用内通知 | `MessageNotificationPolicy`、`SystemMessageNotifier`、iOS `ChatCommunicationNotificationBridge` | 原文进入通知视图；单行摘要只替换 C0/DEL 控制字符，保留 VS15、VS16、ZWJ、combining mark、modifier、RI 和 tag。群发送者前缀按已验证的完整前缀去除。原始消息不回写。 |
| 通知快捷回复 | `MessageNotificationActions`、`AppController._sendNotificationReply` | 原始输入直接入队、创建 SDK 文本消息并发送。trim 只判断是否空白，不改正文和去重键中的文本。 |
| 语音转文字 | `VoiceToTextService`、`VoiceTranscriptionController`、`VoiceTextPreviewDialog`、`ChatVoiceController`、`VoiceTranscriptionView` | ASR 原文、localEx 转写缓存、预览编辑和文本发送保留完整序列；发送有效性判断与字符串存储分离。 |
| 业务资料与附件 | `SangongMyConfigPage`、`SangongConfigurationApi`、`SangongMyConfig`、`CustomerServiceAttachment` | 自填厅名采集、API 请求与模型 JSON 往返保留原文。客服附件文件名使用原文 helper；URL、扩展名、角色和 MIME 继续按协议解析。 |
| 复制粘贴 | Flutter `Clipboard`、项目 `IMUtils.copy` | String 通过标准平台通道传递，未找到文本重新编码或 Emoji normalize。平台剪贴板 roundtrip 为受控测试，未在真实 Android/iOS 剪贴板验证。 |
| SDK AI 流 | `AssistantStreamChunk`、`AssistantStreamState` | 原始 delta 文本按 index 顺序追加，不 normalize；最终普通 SDK 消息仍为持久化的权威来源。 |
| 旧 AI 网关 | `AiAssistantTransport`、`AiAssistantStreamClient`、`AiAssistantStreamEvent` | 流使用 chunk-aware `utf8.decoder`。修复图像 prompt、输入规划、上传文件名和错误显示文本的 trim；标识、URL、MIME 和状态仍按协议校验。 |

客户端发现主动去除首尾空白的路径包括 AI 图像 prompt、旧 AI 规划器、通知快捷回复、语音转文字的缓存与编辑发送、三公厅名保存和客服附件文件名。空白作为 combining mark 的基底时，这会改变原始 grapheme。现改为保存原文，仅做空白有效性判断。通知单行展示的裁空白也改为共享 `graphemeTrim`，保留 combining mark 的基底。AI 用户字数和安全错误文字上限使用 grapheme cluster 数量。旧网关模块仅用于预览/兼容，当前生产助理使用 OpenIM 会话。

## 本分项修改文件

以下为传输与存储分项实际修改的生产文件；未替换 SDK 依赖或数据库协议。

| 文件 | 修改 |
| --- | --- |
| `lib/core/notifications/message_notification_actions.dart` | 快捷回复原文入队与发送。 |
| `lib/core/notifications/message_notification_policy.dart` | 单行显示按 grapheme 裁边缘空白。 |
| `lib/pages/chat/voice/voice_to_text_service.dart` | 原始 ASR 文本返回。 |
| `lib/pages/chat/voice/voice_transcription_controller.dart` | 原始转写存入 localEx 与状态。 |
| `lib/pages/chat/voice/widgets/voice_text_preview_dialog.dart` | 识别和用户编辑的文字原样返回。 |
| `lib/pages/chat/voice/chat_voice_controller.dart` | 预览文字原样创建消息和发送。 |
| `openim_common/lib/src/widgets/chat/voice_transcription_view.dart` | 显示可选中的原始转写文字。 |
| `lib/pages/ai_assistant/composer/ai_assistant_capability.dart` | 原始输入规划、grapheme 字数上限。 |
| `lib/pages/ai_assistant/data/ai_assistant_contract.dart` | 文本字段与协议字段分离。 |
| `lib/pages/ai_assistant/data/ai_assistant_transport.dart` | 原始安全错误文字和 grapheme 上限。 |
| `lib/pages/ai_assistant/data/ai_assistant_upload_mime.dart` | 非空文件名保留原文。 |
| `lib/pages/ai_assistant/protocol/ai_openim_payload.dart` | 图像 prompt 保留原文。 |
| `lib/pages/group_features/sangong/pages/sangong_my_config_page.dart` | 厅名采集和空白判断分离。 |
| `lib/pages/group_features/sangong/api/admin/sangong_configuration_api.dart` | API 请求保留厅名。 |
| `lib/pages/group_features/sangong/models/sangong_my_config.dart` | 厅名 fromJson/toSaveBody 保留原文。 |
| `lib/pages/customer_service/data/customer_service_attachment.dart` | 文件名与 URL/扩展名协议解析分离。 |

## 当前锁定 SDK 与原生桥

当前 Flutter SDK 为 `flutter_openim_sdk 3.8.3+hotfix.12`，源码来自本地依赖缓存，未修改该依赖。

- Dart `lib/src/manager/im_message_manager.dart`：创建正文、引用、@、转发、合并、发送、插入本地记录和搜索；`im_conversation_manager.dart`：草稿。
- Dart `lib/src/models/message.dart`：消息各元素、`OfflinePushInfo`、`AtUserInfo`；`conversation_info.dart`：草稿和嵌套 `latestMsg`；`user_info.dart`、`group_info.dart`：昵称、备注、群名、群公告和群成员昵称。
- Android `manager/MessageManager.java`、`manager/ConversationManager.java`：正文和草稿直接传 Java String；嵌套 maps/lists 通过 `JsonUtil` 的 `JSONObject.wrap` 生成 JSON。已检查的用户文本路径未使用 ASCII、单字节编码或 Unicode 过滤。
- iOS `Module/MessageManager.swift`、`Module/ConversationManager.swift`、`Util/FlutterMethodCall+Extension.swift`、`JsonUtil.swift`：正文和草稿直接传 String；maps/lists 使用 `JSONSerialization`，JSON 数据按 `.utf8` 转回 String。已检查的用户文本路径未过滤 Unicode 序列。
- Android 原生核心锁定 `io.openim:core-sdk:3.8.3-patch12@aar`，iOS 锁定 `OpenIMSDKCore 3.8.3-hotfix.12`。以上二进制核心不能仅通过 Dart/native bridge 源码检查证明内部数据库已通过测试。

Android/iOS 桥的源码检查完成；SDK 原生数据库、系统输入法和真机传输均尚未真机验证。

## 数据库与远端边界

当前工作区没有实际 OpenIM 服务端、业务服务端源码、数据库 schema、连接字符集配置或数据库访问连接；没有读取部署数据，也没有发送测试消息到真实用户。

公开上游 v3.8.3 的 [SDK go.mod](https://github.com/openimsdk/openim-sdk-core/blob/v3.8.3/go.mod) 引入 `gorm.io/driver/sqlite` 和 `go-sqlite3`。这证明上游原生 SDK 的本地存储技术是 SQLite；SQLite 的 UTF 文本能力不能当成当前设备上的 SDK 数据库 roundtrip 已通过。

公开上游 v3.8.3 的 [服务端消息模型](https://github.com/openimsdk/open-im-server/blob/v3.8.3/pkg/common/storage/model/msg.go) 把消息正文、发送者昵称和离线通知保存为 BSON string，使用 MongoDB 消息文档。该证据不能证明部署端版本、插件或回调没有额外处理正文，也不能证明用户/好友/群资料与业务数据库采用相同存储。

如果部署端资料、昵称、备注、群名、群公告、草稿、引用、搜索索引或业务内容使用 MySQL，仍需在实际环境检查数据库、表、字段以及会话连接的字符集均为 `utf8mb4`，并检查中间服务的编码、大小限制和回调转换。未获得当前部署证据，因此这些项目保持“未验证”，没有基于猜测修改协议或数据库。

`lib/core/device_sync/models/device_sync_models.dart:24/84` 对 deviceName、platform 和文件名沿用 200 Unicode scalar 的协议校验；超限时拒绝载荷，不切开 grapheme。该限制是否必须按 scalar 计数仍需实际服务端合同确认。本次保留现有 guard，没有将其未经确认地改成 200 grapheme。支付备注 12 scalar 与收藏搜索 64 scalar 的现有协议限制也没有改成可见字数。

## 自动化证明范围

- `test/services/messaging/unicode/unicode_transport_roundtrip_test.dart`：真实 SDK Dart managers + Flutter method codec，受控 native handler 经过 JSON/UTF-8 序列化，覆盖草稿、发送回执、离线通知、搜索、历史缓存、预览拷贝、引用、@、转发、合并、资料模型和剪贴板。比较 UTF-16 code units 是为了证明原始序列相等，不将 code units 当作用户字符数。
- `test/pages/ai_assistant/data/ai_unicode_contract_test.dart`：结构样本与边缘空白原文保存、grapheme 上限、协议标识与文本的区别，以及响应逐字节拆分时 UTF-8/SSE 的完整恢复。
- `test/pages/ai_assistant/protocol/ai_openim_payload_test.dart`：现有图像 prompt 测试更新为原文保留。
- `test/core/notifications/message_notification_actions_test.dart`：21 类结构连同边缘空白和空格基字符上的结合符，经过真实通知操作队列、恢复就绪与发送回调后保持原文；重复回调不会重复发送。通知回复只在空白判断时使用 trim，不修改排队或发送的正文。
- `test/pages/chat/voice/{voice_to_text_service,voice_transcription_controller,voice_text_preview_dialog,chat_voice_controller}_test.dart` 与 `test/voice_transcription_view_test.dart`：ASR 返回、转写 localEx 保存与重新加载、预览编辑、创建文本消息和发送回调、可选中文本展示均保留 21 类结构的完整原始序列。空白仍被拒绝；原始首尾空白不会被移除。
- `test/pages/group_features/sangong/api/sangong_my_config_status_test.dart`：21 类厅名经实际业务 API、JSON、fromJson、copyWith 和 toSaveBody 后原样保存；群和机器人 ID 仍按协议去除边缘空白。
- `test/pages/group_features/sangong/pages/sangong_config_directory_test.dart`：既有日夜主题配置页保存测试同时断言输入框里的组合字符厅名原样进入请求。
- `test/pages/customer_service/customer_service_api_test.dart`：21 类客服正文和附件文件名经过真实 API 响应解析后保持原文，覆盖文件名别名和空白时的默认扩展名；附件 URL 和类型仍按协议解析。

测试不会连接远端，也不会调用原生 SDK 核心数据库；不能用于声明线上存储、系统 Emoji 字体支持、Android 真机或 iOS 真机已验证。
最终相关整批 1602 通过、16 个条件导出跳过、0 失败；执行范围及其他检查结果见
[主审计](audit-and-verification.md) 与 [验证记录](verification-results.json)。
