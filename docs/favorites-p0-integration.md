# 收藏 P0 前端对接与验收

更新日期：2026-10-04。部署接口以用户提供的[收藏 P0 最终契约](favorites-client-contract.md)为准。早期[完整设计](favorites-full-design.md)保留为功能规划，不代表当前开放能力。

同日真实接口深入检查发现并修复 block ID、响应兼容、上传恢复和删除冲突等前端问题；服务端公网签名地址及删除幂等问题仍需部署补丁。最新状态和真实验收范围见[收藏接口检查记录](favorites-interface-audit-2026-10-04.md)，下方原验收表保留当时的检查范围。

2026-10-05 续查“收藏页添加图片／文件提示原件不可用”，新增失效媒体恢复与归档任务确认兼容修复。服务端仍运行旧版本，手机上传尚未恢复，最新证据、验证和部署边界见[续查记录](favorites-original-unavailable-2026-10-05.md)。

## 入口与能力

| 入口 | 行为 |
| --- | --- |
| 聊天消息长按 → 收藏 | 提交原会话、消息 ID 和正数 sequence，服务端核对访问权限 |
| 我的 → 收藏 | 云端分页、搜索、类型筛选、详情、删除、批量删除 |
| 收藏 → 添加 | 文字笔记、HTTP/HTTPS 链接、图片、视频、音频、文件原件 |
| 收藏详情 → 编辑/重试保存 | 纯文字编辑保留失败输入；仅 archive_failed 可重试归档 |
| 聊天加号 → 收藏 | 固定当前对话，点击 ready 项直接发送；预览只查看 |
| 管理/详情 → 发送 | 复用联系人/群选择器；多项发送只选择目标一次 |

先调用 `GET /chat/favorites/quota`。只有 `supportsFavorites` 和 `supportsPrepareSend` **都严格为布尔值 true**，才显示正式内容并开放操作。能力未知、失败或未开放时显示加载/错误/重试，不使用本地假收藏；账号或 Chat token 变化会失效旧能力。

P0 仅开放 `text/image/video/audio/file/note/link`。标签、定位、名片、消息合集、分享卡片入口关闭，请求不带 `tagIDs`。未知类型/schema 禁发，旧复杂发送任务也不能绕过当前白名单。

界面沿用 AppTokens、GlassAppBar、导航、确认弹窗、联系人和媒体选择器，支持亮暗主题。交互对照本地 99Chat 收藏管理与选择器，数据来自真实收藏 API 与 OpenIM SDK。

## 地址、认证与数值错误码

- 默认 Chat API 为 `http://8.217.191.236:10008`，沿用 `Config.appAuthUrl` 与已有服务器配置覆盖。
- 每次请求生成新 operationID，token 使用登录返回的 chatToken；有正文时用 JSON Content-Type。
- 不发送自报 owner/user ID；检查 HTTP 状态与 errCode，详情读取 data.item。
- 20051 使用已有 data.item；20061 保留本地编辑，提供“查看最新版本”对照服务器正文。“保留我的编辑继续”只更新下一次保存使用的版本和标题，再次点击“完成”才提交；最新版本含媒体时禁止纯文字覆盖。
- 20067 结束已删除对象对应的旧幂等动作，不隐式复活；新的主动创建使用新 UUID。
- 1001、1501–1507、20050–20067 按最终数值码映射，错误提示不依赖旧大写名称。

签名上传/下载使用独立媒体客户端，不携带业务 token，不在提示或日志展示私有 URL/token。

## 创建与上传原件

从消息创建只发 conversationID/clientMsgID/sequence；服务端取得正文、原作者及附件归属。撤回、阅后即焚、金融/通话控制、自定义动作消息不开放收藏。

文字 ready 后显示已收藏；媒体 pending_archive 显示保存中并禁发，轮询归档结果。archive_failed 提供重试。取消息时已撤回由服务端拒绝；进入 pending_archive 后的普通撤回遵从服务端快照归档策略。

自行导入媒体：初始化上传 → PUT 原件到 uploadURL → complete 取得检测资产 → 创建收藏。图片/音频最多 20 MiB，视频/文件 100 MiB，同时遵守返回的 maxSizeBytes 和过期时间。视频 block 带 complete 返回的 coverAssetID。完成上传不等于已创建收藏，重试复用完成资产及原请求正文。

文字正文限制 UTF-8 64 KiB，编辑器按字节计数，保留长笔记、中文输入组合和完整表情；超限时不能提交。链接只接受 HTTP/HTTPS。不以缩略图代替原件，也不把临时 URL 当正文。

## 分页、增量与通知

列表首屏不带 cursor，保存本次查询返回的 syncAt，后续分页原样携带 baseline。分页游标与增量水位分别维护，关键词不超过 64 字符。

增量请求使用 updatedAfter 时间水位、limit=100。满页使用本页 syncAt 继续；同毫秒事件可超过 limit。不满页保存服务器当前 syncAt，表示已追平。每页先持久提交记录和水位，再取下一页；本地写入失败不越过该页。

按 id/version 合并 upsert，保留 delete 版本墓碑，旧响应不能复活已删除项。20064 重建云端记录缓存，保留待处理请求和已完成上传，再补齐未提交操作。

favoriteChanged 通知仅触发增量查询，不信任通知记录正文。连接恢复、SDK 同步结束、回到前台及前台每分钟补齐复用同一流程；合并请求，退出取消绑定，后台停止周期请求。

列表/搜索仍来自服务端；请求代次与账号/token 守护防止迟到响应覆盖当前查询。

## 写入恢复与批量删除

账号和 Chat 服务共同划分展示缓存、收藏 outbox 与 SDK 发送日志。轻量缓存不含原件、凭证或全文；独立 outbox 保存恢复所需的业务正文和原 UUID，不保存 token 或签名授权。

请求 ID、outbox 和完成媒体记录持久成功后才发对应请求；存储失败停止操作。服务端已确认成功后，原子保存同 UUID 的完成依据；展示缓存清理失败不误报写入失败，也不会复用旧 UUID 发起新的创建。未完成上传不因缺少完成记录而丢弃原 UUID，已完成上传在创建确认清理前保留。

同步恢复以原正文、原请求 ID 重放未确认的收藏写入。版本冲突保留正文并提示重新编辑；用户审阅并成功保存新编辑后，才清理该项明确冲突的旧编辑。网络结果未知的请求继续保留。SDK 消息由独立任务恢复，收藏同步不会重放聊天发送。

批量删除调用真实 batch-delete，最多 100 项并逐项携带 expectedVersion。只移除 deleted/alreadyDeleted 项，保留 versionConflict 项；整单权限错误不宣称全部删除成功。

## 快捷发送与未知结果

2026-10-05 按最新交互调整：聊天收藏选择器左侧点击查看或播放，右侧“发送”按钮发送到顶部显示的固定对话。预览只读，不发送消息；不可发送状态禁用右侧按钮，发送中与结果未知继续防重复。媒体及修复包记录见 [收藏媒体预览](favorites-media-preview-2026-10-05.md)。

1. 确认双能力、账号、固定目标和不可变 contentRevision。
2. prepare-send 只准备，不发消息。20063 时先持久新的 clientRequestID，沿用原 sendAttemptID/contentRevision 有界重试。
3. 下载有效期内的原件，校验大小和 SHA-256，取得视频封面，将音视频毫秒时长转 SDK 秒。
4. SDK 创建新 Message，持久 clientMsgID 后提交，逐块保存成功状态。

快捷发送保留输入文字、草稿、引用和 @。接收端收到普通原生消息，不带私人 favoriteID/source/tags 或下载签名；删除收藏不删除已发消息和独立聊天资产。

超时保持结果未知，不生成新 ID 盲重发。“核实结果”只查询原 ID，仅同账号、同目标、成功状态且有服务端序号的记录可确认；查询不到仍为未知。失败气泡重试经原收藏任务处理。

管理页在提交前固定每个“收藏 × 目标”的 attemptID，续发跳过成功部分。取消剩余发送不撤回已发内容，保留未知结果防重复记录。每次 SDK 提交前检查账号、会话和能力。

## 维护位置

| 位置 | 职责 |
| --- | --- |
| lib/pages/favorites/models | 双能力、配额元数据、批量删除结果 |
| lib/pages/favorites/data | 时间同步、版本墓碑、通知/生命周期绑定、持久 outbox |
| lib/pages/favorites/sending | prepare 租约刷新、P0 发送验证 |
| lib/pages/favorites/widgets | 管理、详情、编辑和选择器共用能力门 |
| lib/pages/chat/favorites | 聊天适配与快捷选择器 |
| lib/services/favorite_*.dart | 既有 API/DTO/仓储/构建/发送编排的兼容入口 |
| lib/pages/mine/secondary/favorite*.dart | 既有管理、详情、文字编辑页 |
| test/pages/favorites、test/pages/chat/favorites | 新协议、能力、恢复和 UI 测试 |

本轮新增职责进入独立模块。既有服务和页面暂保留路径，避免同时改变日志键与生命周期；进一步迁移先独立公共列表、共享发送契约及仓储职责，详见模块 README。

## 验证与设备验收

2026-10-04 最终验证结果：

| 检查 | 结果 |
| --- | --- |
| 收藏及相关聊天回归 | 25 个测试文件、167 项全部通过；覆盖协议、能力、同步、原件、恢复、快捷发送、草稿、冲突审阅和 UTF-8 限制 |
| 收藏模块、数据服务、界面与对应测试定向静态检查 | 60 个文件，无问题 |
| 加入聊天主控制器的扩展静态检查 | 61 个文件，无 error/warning；chat_logic.dart 保留 3 条已有 info：输入提示的两处花括号、旧 SDK 群 @ 重置接口弃用 |
| Android 调试包 | 最终修改后重新编译通过，产物 build/app/outputs/flutter-apk/app-debug.apk |
| 修改行空白检查 | 通过 |
| Android/iOS 真机双账号收发、接收端原件访问 | 尚未验证 |

日志位于项目 `.dart_tool/favorites-p0-regression.log`、`favorites-p0-scoped-analyze.log`、`favorites-p0-final-analyze.log` 和 `favorites-p0-final-android-build.log`。这些模拟 HTTP/SDK 与编译检查验证客户端行为，不代表真实接收端已验收。

可在项目根目录复现回归（PowerShell）：

```powershell
flutter test --no-pub `
  test/favorite_api_test.dart test/favorite_models_test.dart `
  test/favorite_repository_test.dart test/favorite_message_adapter_test.dart `
  test/favorite_message_builder_test.dart test/favorite_send_coordinator_test.dart `
  test/favorite_batch_sender_test.dart test/chat_message_sender_test.dart `
  test/favorites_draft_store_test.dart test/chat_toolbox_paging_test.dart `
  test/chat_input_box_test.dart test/chat_message_menu_test.dart `
  test/pages/favorites test/pages/chat/favorites --reporter expanded
flutter build apk --debug --no-pub
```

部署地址已做未携带登录凭证的只读 quota 探测，返回 HTTP 200、业务码 1001；未取得真实用户能力/配额，未进行真实收藏写入或聊天发送。

上线前用两个测试账号在 Android/iOS 验收：

1. 双能力 true/false/请求失败，账号与 token 切换后的入口状态。
2. 单聊/群聊保存并发送各类原件，接收端验证文件名、封面、时长及 hash。
3. 分页 baseline、另一设备增删改、通知丢失补齐、30 天旧水位重建。
4. 弱网、上传后强退、准备过期、发送超时、版本冲突、部分批量删除。
5. 草稿/@/引用保留、连续点击只提交一次、未知结果只查询、删除收藏后聊天资产仍可读。
