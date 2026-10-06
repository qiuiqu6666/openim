# 微信式收藏与快捷发送：前后端完整设计

> 编写日期：2026-10-03（Asia/Taipei）。适用项目：`E:/openim/openim-flutter-demo`。
> 2026-10-04 更新：当前部署以[收藏 P0 最终契约](favorites-client-contract.md)和[前端对接说明](favorites-p0-integration.md)为准。本文中的 P1 类型、标签及分享协议保留为后续设计。
> 本文保留 2026-10-03 的开发设计与接口提案，以及当时的源码现状；“新增/建议”描述的是提案范围。当前服务端已提供 P0 契约，前端实现与验证见上述对接说明，未开放的 P1 能力仍属后续设计。
> 2026-10-05 更新：用户确认聊天收藏选择器左侧点击查看或播放，右侧明确的发送按钮发送。下文早期整卡发送交互已被此要求替代；当前实现见 [收藏媒体预览](favorites-media-preview-2026-10-05.md)。
> 核心目标：聊天消息可收藏，收藏跨设备长期保存；聊天内打开收藏后，点击发送按钮即可发送到当前会话；从“我的 → 收藏”也可选择其他会话发送。

## 1. 推荐结论与职责分工

推荐采用 **Flutter 收藏业务层 + 当前 Chat 业务后端收藏模块 + 私有对象存储 + 现有 OpenIM 发送链路**。

| 层 | 负责什么 | 本次改造方式 |
| --- | --- | --- |
| Flutter | 收藏入口、列表、搜索、详情、编辑、标签、快捷发送、离线缓存 | 扩展已有收藏页面，新增 API/Repository/Store 与消息适配器 |
| Chat 业务服务 | 身份验证、收藏归属、内容快照、附件归档、配额、同步、下载授权 | 在真实业务后端新增 favorites 模块，或独立服务通过现有网关接入 |
| 对象存储 | 私有收藏原件、缩略图、封面 | 建立独立存储空间与归档生命周期 |
| OpenIM SDK/服务 | 创建新消息、上传聊天附件、发送、会话更新、推送、发送失败重试 | 首期复用当前流程，保留现有核心架构 |

收藏是“用户自己的资料库”；发送是“用收藏内容生成一条新的聊天消息”。两者生命周期分开。删除收藏不删除已发消息，删除原聊天也不删除已经归档完成的收藏。

首期媒体发送采用：**私有收藏原件下载到本地 → SDK 创建原生新消息 → 正常上传并发送**。这样对方能够按现有聊天附件方式访问，也避免把仅收藏所有者能访问的 URL 放入聊天。

## 2. 当前代码现状与差距

### 2.1 当前 OpenIM 客户端

| 已核查位置 | 当前行为 | 开发含义 |
| --- | --- | --- |
| `lib/pages/mine/mine_logic.dart:33`、`:83` | 实例化 `FavoritesDraftStore`，打开 `FavoritesPage` | 已有“我的 → 收藏”入口，可以保留 |
| `lib/pages/mine/secondary/favorites_draft_store.dart:5`、`:24` | 类型只有 note/image/video；内存状态，没有网络或持久化 | 需要正式数据层与账号隔离，不能当作线上收藏 |
| `lib/pages/mine/secondary/favorites_page.dart:42`、`:56` | 选媒体后保存缩略图 bytes；选择视频也只保存缩略图 | 必须改为上传图片/视频原件，视频另存封面 |
| `lib/pages/mine/secondary/favorites_page.dart:159`、`:411`、`:523` | 操作主要是编辑/删除；刷新没有服务器拉取 | 保留页面外观，接入真实分页/搜索/详情与发送 |
| `lib/pages/chat/chat_logic.dart:902` | `_sendMessage` 已处理本地列表、SDK 发送、推送和状态 | 收藏发送应该接入该流程 |
| `lib/pages/chat/chat_logic.dart:907`、`:921`、`:1008` | 默认 `resetInput=true`，可能清空输入框、@ 信息与草稿 | 收藏快捷发送必须 `resetInput:false` |
| `lib/pages/chat/chat_logic.dart:935`、`:949` | catchError 转换成失败状态，未将错误继续抛出 | `await` 返回不代表成功；需明确发送结果接口 |
| `lib/pages/chat/chat_logic.dart:1344` | 个人表情视频已有下载、创建视频消息、发送流程 | 可参考媒体处理，不把普通图片统一当表情发送 |
| `lib/pages/chat/chat_view.dart:47`、`openim_common/lib/src/widgets/chat/chat_item_container.dart:232` | 上层 `messageMenus` 定义长按操作，容器复用 PopButton 展示 | 在已有菜单增加收藏，回调进入 ChatLogic，不另建菜单组件 |
| `openim_common/lib/src/widgets/chat/chat_toolbox.dart` | 聊天更多面板 | 新增“收藏”工具项，配合上层回调打开选择器 |
| `pubspec.yaml:113` | `flutter_openim_sdk: ^3.8.3+hotfix.12` | 按当前实际 SDK 编写适配器，不照搬腾讯 SDK |
| `pubspec.yaml:45`、`:47`、`:50` | 已有 Hive、SharedPreferences、path_provider | 首期元数据缓存优先复用已有能力，媒体保存文件路径 |

当前仅核查源码，没有运行验证现有收藏页或现网接口。已有 `test/favorites_draft_store_test.dart` 验证的是内存草稿增删，不代表云收藏、原视频发送或多端同步已实现。

### 2.2 本地服务端范围

工作区 `server/` 目前只有 `server/tencent-asr/server.mjs` 与对应 `package.json`，是语音识别代理，**没有当前部署的 OpenIM Go 服务端或 Chat 业务后端完整源码**。

因此本文不能给出“现网 Go 后端第几个文件直接修改”的承诺。服务端部分给出可实现的模块边界、表结构、接口与流程；实际实施应先定位部署使用的 Chat 后端仓库、数据库与对象存储配置。

客户端已有 `Config.appAuthUrl` 与 `Config.imApiUrl` 的业务/IM 地址分工。收藏业务走 `appAuthUrl`，沿用业务接口的 `token: DataSp.chatToken`；IM 登录与 SDK 上传发送继续使用 IM token。服务端必须验证业务 token，不接受客户端自报用户 ID 作为身份。

### 2.3 99Chat 参考实现

已核查 `E:/openim/reference-99chat` 的实际客户端源码：

| 参考位置 | 可借鉴内容 |
| --- | --- |
| `lib/src/profile.dart:1620`、`:1639` | 我的收藏入口 |
| `lib/src/chat.dart:2504`、`:2534` | 更多面板打开收藏选择器 |
| `lib/src/chat.dart:3577`、`:3588` | 长按消息收藏 |
| `lib/src/pages/favorites/favorite_picker_sheet.dart:394` | 文本点卡片预览；图片/视频点卡片发送；发送按钮直接发送 |
| `lib/utils/favorite_message_chat_sender.dart:57`、`:75`、`:108` | 媒体下载后通过腾讯 SDK 创建、发送新消息 |
| `lib/src/models/favorite_message_models.dart:4` | 当前参考仅 TEXT/IMAGE/VIDEO |

采用参考的入口与交互，再按用户需求扩展类型。参考没有完整的语音、文件、定位、合并聊天、标签能力，也没有完整的“管理页选择其他会话发送”；其 API 是否已上线未验证。

避免复制参考中的限制：`listAll()` 默认最多加载 500 条后本地搜索，不适合大收藏量；媒体替换先删旧收藏再上传，失败会丢内容；未知类型自动转成文本容易误显示。新方案使用服务器分页搜索、成功归档后更新、未知类型兼容态。

## 3. 产品功能与范围

### 3.1 必须完成的功能

1. 单条消息长按 → 收藏；多选消息 → 合并收藏。
2. 我的 → 收藏：分页、类型筛选、关键词搜索、详情、删除、批量删除。
3. 主动创建文字笔记、上传图片/视频/文件；原件可靠保存。
4. 聊天“＋ → 收藏”：显示当前发送目标，单次点击发送到当前会话。
5. 收藏详情“发送” → 选择联系人/群/会话 → 发出。
6. 保存成功的收藏跨设备可恢复；弱网有明确进度、失败、重试。
7. 已归档收藏独立于原消息；已发送消息独立于收藏记录。

### 3.2 分期覆盖的类型

| 类型 | 收藏保存内容 | 发出去的表现 | 阶段 |
| --- | --- | --- | --- |
| 文字 | 原文、必要的富文本结构 | 新的文字消息 | P0 |
| 图片/GIF | 原件、尺寸、格式、缩略图 | 新的图片消息；GIF 保真需单独验收 | P0 |
| 视频 | 原视频、封面、时长、编码 | 新的视频消息 | P0 |
| 语音 | 原音频、时长、编码；可选本人转写 | 新的语音消息；私人转写不自动外发 | P0 |
| 文件 | 原文件、文件名、大小、格式 | 新的文件消息 | P0 |
| 纯文字笔记 | 标题、正文 | 文字消息，可选带标题 | P0 |
| 网页链接 | URL、标题、摘要、可选封面快照 | P0 发 URL 文字；P1 可发链接卡片 | P0/P1 |
| 定位 | 经纬度、地址、标题 | 新的定位消息 | P1 |
| 联系人名片 | 可分享名片字段 | 新的名片消息 | P1 |
| 多图/图文笔记 | 有序 blocks + 附件 | 逐条发送或独立分享卡片 | P1 |
| 合并聊天记录 | 有序消息快照 + 归档附件 | OpenIM 合并消息或分享快照卡片 | P1 |
| 标签 | 本人标签、标签关联 | 仅用于私人管理，不随发送附带 | P1 |

P0 已覆盖“收藏后点击发到对话”的完整闭环。P1 是完整资料管理能力，仍需纳入最终验收；不要因为 P0 已能演示就宣布全部功能完成。

### 3.3 明确的内容规则

- 仅可收藏已成功发送/收到且类型支持的消息；发送中、失败、撤回占位、系统通知不给普通收藏入口。
- @ 消息收藏时保存可读文本；发往新会话默认转普通文本，不带旧群成员 ID 或 @ 全体。
- 引用消息默认保存展示快照；重新发送正文，不重新绑定旧会话 quote ID。
- 红包、转账、订单动作、通话控制等自定义消息 P0 不支持收藏重发。扩展时只能静态摘要或经专门授权的白名单卡片，禁止重新触发交易/通话行为。
- 阅后即焚/受保护内容默认禁收藏；按现网能力落实前后端共同校验。
- **建议产品规则**：以服务端成功取得可信“授权内容快照”作为收藏资格的判定点。之后的普通撤回不取消该快照的归档，包含已进入pending_archive但尚未ready的请求；取得快照之前消息已撤回则拒绝。只有归档完成才提示保存成功。监管删除/安全下架另行使收藏失效。此处是本项目的明确设计选择，没有声称与微信每个版本完全一致。
- 附件归档完成前只显示“正在保存”；全部必需内容可持久读取后才显示“已收藏”。

## 4. 前端页面与点击发送交互

### 4.1 三个入口

| 入口 | 交互 | 结果 |
| --- | --- | --- |
| 消息长按/多选 | 收藏、合并收藏 | 创建私人收藏，展示保存状态 |
| 我的 → 收藏 | 查看/搜索/管理 → 详情 → 发送 | 选择发送目标后发送 |
| 会话 → ＋ → 收藏 | 收藏选择器，顶部“发送到：目标名称” | 单条点击即可发到固定目标 |

### 4.2 聊天快捷选择器

建议新增 `FavoritePickerSheet`，与管理页面共用卡片、列表和数据层；它有独立的 `selectForChat` 模式。

```text
当前会话 → ＋ → 收藏
┌──────────────────────────────────┐
│ 收藏                 发送到：张三 │
│ 搜索收藏内容                      │
│ 全部 文字 图片 视频 语音 文件      │
│ 文字摘要……          [预览] [发送] │
│ 图片缩略图          [预览] [发送] │
│ 会议录音 00:35      [试听] [发送] │
│ 合同.pdf 2.1 MB     [预览] [发送] │
└──────────────────────────────────┘
```

在这个模式里：

1. 卡片发送区域和“发送”按钮均点击即发送；预览/试听是独立按钮，不能与发送区域重叠。
2. 打开时固定 `ChatTarget`，包括 conversationID 与 userID/groupID 二选一；不能在异步结束后读取当时的“当前路由”作为目标。
3. 单条发送不再加确认弹窗；明确的模式标题、目标与按钮承担防误发提示。
4. 当前发送项立即显示准备/下载/发送进度，锁定本次操作；失败保留列表与重试入口。
5. 成功关闭面板并回到聊天，消息按正常流程出现在底部；“发送成功”代表 IM 服务接受，不能标成对方已读。
6. 同一个目标同一条收藏的一次动作只创建一个发送尝试；成功后用户再次主动点击属于合法再次发送。
7. 多选发送使用底部“发送 N 项”按钮；提供逐条/合并选项与顺序，显示逐条结果。
8. 不清空输入文字、草稿、@ 信息、引用草稿或改变其他会话的状态。返回后恢复搜索、筛选和滚动位置。

如果移动端布局更适合整卡点击，整卡可以承担发送，但必须清楚标记“点击发送”；预览仍有独立触点。屏幕阅读器语义示例：“发送收藏，合同.pdf，到张三”。

### 4.3 我的收藏管理模式

管理模式点击卡片进入详情，长按提供发送、编辑、标签、删除；多选底部提供发送、标签、删除。不要让管理模式的普通点按隐式发送。

详情页可显示私人来源、收藏时间、本人备注与标签；发送时默认只发内容。目标选择复用 `lib/routes/app_navigator.dart:250` 的 `startSelectContacts(action: SelAction.forward, ex: 摘要)`；选择结果见 `lib/pages/contacts/select_contacts/select_contacts_logic.dart:194`，通过已有转换工具转成统一 `ChatTarget`。多目标逐一记录结果，不为此替换路由框架。

### 4.4 状态、主题与可访问性

列表至少区分：初次加载、缓存内容刷新、分页加载、空收藏、无搜索结果、网络错误、归档处理中、附件失败、未知类型。

复用现有 Settings 组件、TitleBar、SearchBox、AppIcon、AppTokens/主题，不另造按钮/颜色体系。亮暗主题均验收；触点建议至少 48×48 逻辑像素，区分发送与预览；大字体不能遮住文件名/发送目标。缩略图懒加载，大文件不放入整个列表的内存 bytes。

搜索建议 300ms 防抖，取消旧请求或使用请求序号丢弃旧结果；关键词/筛选变化重置分页。多端返回与后台恢复优先增量同步，避免每次重拉全部。

## 5. 前端代码改动清单

### 5.1 改现有文件

以下路径相对 `openim-flutter-demo` 根目录；新增路径是建议，不表示已经存在。

| 文件 | 具体改动 |
| --- | --- |
| `lib/pages/mine/mine_logic.dart` | 保留收藏入口，改为注入正式 Repository/Store；不要只由 MineLogic 创建并销毁跨页面收藏状态 |
| `lib/pages/mine/secondary/favorites_page.dart` | 保留外观与搜索/筛选/批量操作；将草稿集合替换为服务端分页状态；接入详情、发送、刷新与错误态 |
| `lib/pages/mine/secondary/favorite_note_edit_page.dart` | 编辑成功后调用持久接口；取消保留本地草稿；更新冲突时提示刷新/保留编辑内容 |
| `lib/pages/mine/secondary/favorites_draft_store.dart` | 缩小为未提交编辑草稿或退役；不再作为正式收藏数据源；有原件的草稿通过明确迁移动作上传 |
| `lib/pages/chat/chat_logic.dart` | 新增收藏动作/打开选择器/发送入口；返回明确 SendResult；快捷发送 resetInput:false；清理:909/:1658的完整Message日志，只保留脱敏类型/消息ID/错误码 |
| `lib/pages/chat/chat_view.dart` | 连接消息收藏回调、多选动作、工具箱入口，按消息类型与权限显示 |
| `openim_common/lib/src/widgets/chat/chat_item_view.dart` | 仅在现有 menu 透传不足时扩展可选回调；普通组件不直接依赖业务 API，不要求必改 |
| `openim_common/lib/src/widgets/chat/chat_toolbox.dart` | 按现有可选回调/ToolboxItemInfo模式增加 onTapFavorites；chat_view.dart:416接线，检查分页数量/顺序 |
| `lib/pages/chat/message_selection_page.dart` | 复用已有多选页，必要时增加 title/maxSelection 参数，收藏合并不沿用固定“合并转发”标题 |
| `lib/services/` 的登录态/服务注入入口 | 账号切换、注销时切换 namespace，停止旧同步与发送准备任务 |
| `openim_common/lib/src/res/strings.dart` 与语言资源 | 增加收藏、归档、发送失败、配额、未知类型等文案 |

### 5.2 建议新增文件

```text
lib/services/favorite_models.dart                 # 规范化类型、版本、状态
lib/services/favorite_api.dart                    # 业务 HTTP 封装与错误码
lib/services/favorite_repository.dart             # 云端 + 本地缓存 + 待提交操作
lib/services/favorite_store.dart                  # 列表、详情、同步、账号状态
lib/services/favorite_message_adapter.dart        # OpenIM消息 → 收藏描述
lib/services/favorite_message_builder.dart        # 收藏快照 → OpenIM新消息
lib/services/favorite_send_coordinator.dart       # 固定目标、准备、发送、对账
lib/services/chat_message_sender.dart             # 建议：SDK发送与结果的薄共享封装
lib/pages/mine/secondary/favorite_detail_page.dart
lib/pages/chat/favorite_picker_sheet.dart
lib/widgets/favorite_item_tile.dart               # 管理/快捷模式复用卡片
```

采用当前项目的 GetX/Notifier 与依赖注入惯例，不替换状态管理框架。新组件只处理现有组件没有的收藏内容结构，标题栏、按钮、搜索、弹窗继续复用。

### 5.3 数据与缓存

- namespace 至少为 `{业务服务地址, 已验证用户ID}`；内存状态也要隔离。
- Hive 或项目已有本地存储保存元数据、版本、changeCursor 与 outbox；媒体保存到账号隔离目录，列表只放路径/assetID。
- 缓存不是真数据源，显示“缓存内容/待同步”；不能把未上传项标为云端保存成功。
- 异步任务捕获 session generation；完成时发现已经换号，不写入新账号状态。
- 401/业务 token 失效走现有重新认证流程；操作只对同一身份恢复，不能换号后自动续传。
- 草稿媒体可能只有缩略图，没有办法恢复原视频。旧草稿只能按实际内容导入，不能伪造视频原件；若已销毁内存，则没有可自动恢复的数据。

## 6. 快捷发送如何接入 OpenIM

### 6.1 当前 SDK 已核查能力

实际解析包为 `E:/openim/.pub-cache/hosted/pub.dev/flutter_openim_sdk-3.8.3+hotfix.12`，下列方法在其 `lib/src/manager/im_message_manager.dart` 存在。

| 能力 | 当前方法/必需参数 | 本项目用途 |
| --- | --- | --- |
| 文本 | `createTextMessage(text)` | 创建新的文字消息 |
| @ 文本 | `createTextAtMessage(text, atUserIDList)` | 收藏重发默认不用旧 @ 列表 |
| URL 图片 | `createImageMessageByURL(sourcePicture, bigPicture, snapshotPicture)` | P2 在独立聊天资产准备完成后优化 |
| URL 语音/视频/文件 | `createSoundMessageByURL(soundElem)` / `createVideoMessageByURL(videoElem)` / `createFileMessageByURL(fileElem)` | 必须提供真实元数据与接收者可读的聊天资产 |
| 转发 | `createForwardMessage(message)` | 必须使用已清理的快照；首期优先按类型重新创建 |
| 合并消息 | **`createMergerMessage(messageList, title, summaryList)`** | 准确拼法是 Merger，不能写成不存在的 createMergeMessage |
| 常规发送 | `sendMessage(message, offlinePushInfo, userID/groupID)` | 首期复用当前 `_sendMessage` |
| 已有 URL 的发送 | `sendMessageNotOss(message, offlinePushInfo, userID/groupID)` | 仅后续优化，当前 `_sendMessage` 尚未接入此分支 |

媒体首期使用当前 SDK 的 FullPath 路径模式，已核查的必填参数如下；builder 中集中适配：

| 方法 | 必填参数 |
| --- | --- |
| `createImageMessageFromFullPath` | imagePath |
| `createSoundMessageFromFullPath` | soundPath、duration（秒） |
| `createVideoMessageFromFullPath` | videoPath、videoType、duration、snapshotPath |
| `createFileMessageFromFullPath` | filePath、fileName |
| `createLocationMessage` | latitude、longitude、description |
| `createCardMessage` | userID、nickname；faceURL/ex可选且只附带明确可分享字段 |

官方也要求先创建 Message，再调用发送；单聊与群聊目标二选一。见 [OpenIM Flutter 发送流程](https://docs.openim.io/sdk/flutter/getting-started/send-first-message)。当前项目方法签名仍以锁定 SDK 与源码为准，不因为新文档而自动升级。

### 6.2 完整发送流程

```text
点击发送
  → 固定目标、账号、收藏contentRevision、sendAttemptID
  → POST /chat/favorites/{id}/prepare-send（不发消息）
  → 得到不可变内容快照 + 短期原件下载授权
  → 下载并校验原件，创建全新的OpenIM Message
  → 记录sendAttemptID ↔ clientMsgID
  → 现有发送链路（resetInput:false）
  → 成功 / 明确失败 / 结果未知
  → 更新UI、持久发送状态、释放临时资源
```

每次新的用户发送动作生成新的 `clientMsgID`。不要直接发送原来的 `Message.fromJson`、保留旧 status/seq/发送者 ID，或将整个旧消息对象作为可执行发送参数。

收藏适配器只输出经过校验的内容字段；builder 通过 SDK 创建新消息，发送者由当前登录 SDK 决定。接收方得到普通文字/图片/语音/视频/文件消息，不需要调用私人收藏接口。

### 6.3 发送结果接口需要补齐

建议最小扩展为 `ChatSendResult`，至少区分：

```text
success(clientMsgID, returnedMessage)
failed(clientMsgID, errorCode, retryable)
unknown(clientMsgID, reason)       # 超时、应用被挂起等，不能确定IM是否接收
```

保留 `_sendSucceeded`、`_senFailed`、状态流、本地列表刷新与已有失败提示，让发送返回明确结果，避免收藏面板另起一套发送状态系统。普通发送调用方可继续忽略返回值；实施时核查所有直接调用方。

还需处理“从我的收藏发出时没有ChatLogic”的情况：`chat_binding.dart:10` 的 ChatLogic 是带tag的页面控制器，不能在收藏页通过 Get.find 假定它存在，更不能临时造一个聊天控制器发送。建议把 SDK调用/typed结果抽成很薄的共享 `ChatMessageSender`：聊天页面继续通过 `_sendMessage` 完成UI入列/草稿/失败提示并调用共享sender；管理页由 coordinator 调用同一sender，由已有SDK会话同步更新目标会话。共享sender不读取页面的userID/groupID/groupInfo或输入状态，也不新增第二套IM监听。

任何失败分类必须依据本次 `ChatTarget`，不能依据碰巧打开的ChatLogic.isSingleChat；不相关会话的失败提示/消息不写入当前聊天列表。发送中页面被销毁后，持久任务与SDK状态继续收敛，UI回调先检查目标和生命周期。

`_sendMessage` 默认重置输入，收藏分支明确传 `resetInput:false`。跨会话发送时只向正确会话添加消息，不往当前不相关聊天的 `messageList` 塞入。现有引用/富文本状态也不能被收藏 builder 读取并附带。

### 6.4 防重复与失败重试

| 情况 | 应采取的动作 |
| --- | --- |
| 连点 | UI 锁 + coordinator 按 sendAttemptID 去重 |
| prepare-send 超时 | 同一 clientRequestID 重试准备接口 |
| 下载失败 | 恢复/重新下载同一归档版本，还没有发消息 |
| SDK 明确失败 | 对原 clientMsgID 使用已有失败消息重试能力，按 SDK 实际语义验收 |
| SDK 超时/断线且结果未知 | 用监听事件/当前 SDK 可用的消息查询按 clientMsgID 对账，成功回执才确认为success；本地查不到不能证明IM未接收 |
| 应用重启 | 从持久发送任务恢复；已构建消息不能自动再生成新ID盲发 |
| 用户有意再发一次 | 新建 sendAttemptID 与 clientMsgID，允许再次发送 |

准备接口幂等只解决服务端准备重复，不等于 OpenIM 端到端 exactly-once。若当前 SDK 无法查询/复用未知消息，展示“发送状态待确认”并引导用户核对；不能承诺绝不会重复。

只有已验证的SDK明确拒绝、且其语义能确定IM未接收时，才进入可安全重试的failed。一般网络异常、本地sending/failed、查不到本地消息都保持unknown；用户点“重试”先恢复对账，不能自动换新ID。若用户核对后明确决定再次发送，记录为新的主动发送动作，并提示之前一次仍可能到达。

### 6.5 多附件与合并内容

默认逐条发：按 blocks 顺序串行构建并等待发送结果，记录每条状态；出现失败/未知时暂停后续，保留成功项，只重试明确失败项。每项有独立 clientMsgID，不一次 `Future.wait` 混发顺序。

合并聊天可使用已核查的 `createMergerMessage`，但每个内嵌 Message 必须重建、清除原私有引用，且媒体使用能覆盖聊天保留期的独立聊天资产。当前仅确认创建方法存在，尚未验证SDK会递归上传合并消息内的本地附件。P1启用媒体合并前必须完成独立聊天资产准备与接收端验收；未具备该能力时仅开放逐条发送或第9.11节分享卡片，不能把本地路径填进merger后宣称成功。

图文笔记/复杂多附件若用自定义卡片，后端生成独立、不可变 `shareSnapshotID`，访问权限绑定此次聊天受众与确定的成员历史策略。开发接收端渲染、详情、附件授权和旧客户端降级后才能开启；P0 不提前发送接收端无法识别的卡片。

## 7. 服务端模块与存储设计

### 7.1 放在什么服务

首选在已部署 Chat 业务服务增加 favorites 模块，与用户、反馈、个人表情等业务认证一致；若真实后端无法扩展，则建独立收藏服务，通过网关提供同样的 `/chat/favorites` 契约并复用身份验证。

不把收藏逻辑塞入语音识别代理；不让客户端拿管理员 token 调 OpenIM 管理接口。服务端管理员凭证仅保留在可信后端，见 [OpenIM 平台接口认证说明](https://docs.openim.io/platform-api/prepare-to-use-api)。

建议后端模块职责：API/认证、FavoriteService、FavoriteRepository、MessageSourceResolver、ArchiveWorker、StorageAdapter、ChangesService、QuotaService、GCWorker。具体包名/目录由实际后端惯例决定，以上为建议模块。

### 7.2 核心表/集合

数据库类型尚未核实。下表是逻辑模型；SQL 后端使用对应唯一键/事务，MongoDB 后端使用等效索引与事务或条件更新，不强行引入另一套数据库。

| 模型 | 关键字段 | 约束与索引 |
| --- | --- | --- |
| `favorite_items` | id、owner_user_id、kind、title、content_json、source_json、provenance、status、version、content_revision、created_at、updated_at、deleted_at、total_bytes | 主键id；所有查询带owner；索引(owner,deleted_at,created_at,id)、(owner,kind,created_at,id) |
| `favorite_assets` | id、owner、bucket、object_key、mime、size_bytes、sha256、width、height、duration_ms、codec、state、created_at | 对象位置不以URL代替；按owner/state索引；hash按真实原件计算 |
| `favorite_revisions` | owner、favorite_id、content_revision、schema_version、immutable_content、created_at、state | 唯一(favorite_id,content_revision)；不可原地覆盖，当前item只指向当前revision |
| `favorite_revision_assets` | favorite_id、content_revision、asset_id、role、block_id、ordinal | 唯一(favorite_id,content_revision,block_id,role,ordinal)；可反查历史/当前revision引用 |
| `favorite_prepares` | prepare_id、owner、favorite_id、content_revision、send_attempt_id、projected_content、asset_manifest、expires_at、state | 持久准备快照与租约；幂等绑定固定版本；普通删除不提前取消有效lease |
| `favorite_uploads` | upload_id、owner、object_key、reserved_bytes、detected_meta、expires_at、state | 账号绑定上传会话；状态/对象键可恢复，完成幂等 |
| `favorite_archive_jobs` | job_id、owner、favorite_id、authorized_source_snapshot、source_revision、object_manifest、state、retry_count | 来源授权点与快照持久保存；幂等对象键，重试/补偿/失败释放配额 |
| `favorite_requests` | owner、operation、client_request_id、request_hash、result_ref、result_version、state、expires_at | 唯一(owner,operation,client_request_id)；同键异内容返回冲突 |
| `favorite_changes` | owner、change_seq、favorite_id、version、operation、occurred_at | 唯一(owner,change_seq)；包括删除tombstone，提交时原子生成 |
| `favorite_quota` | owner、used_count、used_bytes、reserved_bytes、version | owner唯一；事务/原子预留防并发超额 |
| `favorite_tags` / `favorite_item_tags` | owner、tag_id、name；favorite_id/tag_id | P1新增；标签查询与改名严格限定owner |

`favorite_shares` 与 `favorite_share_assets` 为P1复杂分享新增，保存脱敏不可变分享内容、目标、已验证消息绑定、独立资产与保留策略，详见第9.11节。其资产引用独立于私人收藏revision。

`content_json` 使用版本化 blocks 保存笔记与合集，无需首期拆成大量类型表。`source_json` 是私人来源信息；`provenance` 至少区分 `serverVerified` / `userCreated` / `clientProvided`。

`version` 在任何内容/标签/元数据修改时递增，供同步与乐观锁；`contentRevision` 标识不可变内容版本，发送准备固定该版本。标签改名不改变已经准备好的发送内容。

### 7.3 统一内容模型

收藏详情示例，时间统一为 UTC 毫秒；id 为不透明值：

```json
{
  "id": "fav_01",
  "kind": "image",
  "title": "旅行照片",
  "schemaVersion": 1,
  "version": 3,
  "contentRevision": "rev_02",
  "status": "ready",
  "provenance": "serverVerified",
  "content": {
    "blocks": [
      {"id": "b_01", "type": "image", "assetID": "ast_01", "altText": "海边"}
    ]
  },
  "assets": [
    {
      "id": "ast_01",
      "role": "original",
      "mimeType": "image/jpeg",
      "sizeBytes": 2097152,
      "sha256": "9f1d7c8e6b5a403291827364554433221100ffeeddccbbaa9988776655443322",
      "width": 1920,
      "height": 1080,
      "durationMs": null
    }
  ],
  "source": {
    "conversationID": "c_origin",
    "clientMsgID": "m_origin",
    "displayName": "原发送者",
    "sentAt": 1790980000000
  },
  "tags": [{"id": "tag_01", "name": "旅行"}],
  "createdAt": 1790980100000,
  "updatedAt": 1790980200000
}
```

列表返回轻量摘要（id/kind/title/摘要/封面资产ID/状态/版本/时间/标签），正文、完整 blocks 和下载授权按详情/发送需求获取。示例 hash 仅用于展示字段形状，生产值由服务端计算。

支持 blocks：text/image/video/audio/file/link/location/contact/message。每类字段做 schema 校验；禁止任意 OpenIM 原始 JSON 直接作为重发模板。未知 kind/schemaVersion 返回可读占位与禁发态，不能静默转成 text。

| block.type | 规范化字段与校验 |
| --- | --- |
| text | text；可选受限richText spans，长度与链接scheme校验，不接受可执行HTML |
| image/video/audio/file | assetID；视频封面由asset关系引用；文件fileName；尺寸/时长/编码由已检测资产提供 |
| link | url、title、summary、可选coverAssetID；封面已归档，自动抓取另做安全校验 |
| location | latitude[-90,90]、longitude[-180,180]、address、title；拒绝NaN/无限值 |
| contact | userID、nickname、明确可分享头像；ex仅白名单展示字段，不含隐私设置 |
| message | 静态作者展示、sentAt、childBlocks；不得含可重放动作、私有会话定位或任意递归JSON |

durationMs转SDK秒值集中在builder：按真实解码时长转换为正整数秒（建议向上取整，最小1秒），视频时长取实际秒语义；无法解码/时长为零拒绝创建。单位转换、短语音与视频封面需覆盖测试。

## 8. 附件归档、权限与删除策略

### 8.1 收藏收到的消息

```text
客户端提供源定位（conversationID/clientMsgID等）
 → 服务端校验当前身份拥有该消息的访问权
 → MessageSourceResolver读取可信消息与媒体定位
 → 在权威读取中校验支持类型、撤回/保护状态，取得带来源revision的授权内容快照
 → 预留容量，建立pending_archive项
 → ArchiveWorker复制/下载原件至本人私有收藏空间
 → 校验hash、可解码、尺寸/时长，生成封面
 → 原子提交内容/资产关系/配额/changes，置为ready
```

收到的文件可能属于原发送者。**不能套用个人表情收藏“对象名必须以当前用户ID开头”的规则**来拒绝所有收到的附件，也不能凭“URL可以访问”就认可权限。依据可信的消息交付/访问记录，归档后资产归当前收藏用户。

`clientMsgID` 单独不够做授权。实际部署可用什么消息读取/访问证明接口需先确认；服务端管理接口具有读取能力也不自动意味着该用户有权收藏，resolver 仍需验证受众、受保护状态与消息版本。

归档job持久化已经取得的授权快照，普通撤回的资格边界按第3.3节处理，不靠前端时间判断先后。如果来源读取是过期缓存、无法证明撤回状态，则不能标serverVerified；需补齐权威读取/事件版本能力。平台安全下架仍会停止未完成job并使现有收藏不可读取。

对象存储和数据库不能放入一个普通事务：归档使用幂等对象键与持久任务，先完成原件写入/核验，再事务提交revision、资产引用、配额和changes；失败对象留给补偿任务/对账清理。删除收藏或换状态时，worker提交使用条件版本检查，不能把已删除项重新置ready。

若源记录已被清理或无法验证，允许用户将本地可用内容作为“本人创建/导入”上传，来源标 `clientProvided`；不冒充可信原发送者、原会话或服务器验证记录。此降级不绕过禁止收藏的保护内容策略，无法判断时不提供“消息收藏”成功假象。

### 8.2 收藏自己上传的内容

上传初始化由服务端签发账号绑定的 upload session；对象 key 由服务端生成。上传完成后服务端核验 session 所属、对象存在、字节数/hash/MIME/解码结果。前端传入的扩展名、MIME、大小仅为提示。

只有核验完成的 `uploadID`/`assetID` 才能创建或替换收藏。替换媒体先上传新原件，成功后事务修改内容与版本，最后延迟回收旧无引用资产；不先删除旧收藏。

### 8.3 私有读取与长期保存

- 元数据保存 bucket/objectKey/assetID；短期签名 URL 仅是每次授权读取的结果，不能作为收藏唯一内容。
- 收藏原件与聊天缓存/临时上传的存储生命周期分开；底层使用同一个桶时也必须有不同前缀、策略与引用关系。
- 每次详情预览/原件下载都检查当前用户对收藏/资产的归属；猜到 assetID 不能获得授权。
- URL 刷新在过期/授权失败时进行，不把临时 URL 当离线长期可用地址。
- 归档处理中遇到原件缺失显示失败，保留任务可重试；不能只留下一个失效链接却显示成功。
- `ready` 后独立保存快照。普通源聊天删除/清空/退群不影响已归档内容；创建/重新取源受当前策略控制。

### 8.4 发送后的资产与回收

P0 媒体由 SDK 重新上传成为普通聊天资产。删除收藏仅解除收藏引用，已发消息仍读取独立聊天资产。GC 不能因删除收藏去删普通 OpenIM 消息对象。

P1复杂分享，以及P2普通媒体服务端资产转交/复用，都须建立独立聊天资产引用或不可变分享快照；聊天受众可读、生命周期覆盖聊天保留策略、收藏删除不撤销它，三个条件缺一不可。

建议删除记录软删并生成 tombstone；收藏无引用资产延迟 7 天回收，未完成临时上传可 24 小时回收；这些是建议配置，需结合真实保留策略决定。GC 与发送准备 lease 原子协调：仍有有效准备租约/归档任务/内容版本引用的资产不回收；过期后的 prepare-send 返回明确失效，让客户端重新准备。

不能只用一个不准确的 ref_count 决定删除。引用创建、prepare租约、资产复用与GC共用同一事务/条件锁协议：仅ready资产可加引用，GC原子检查无引用/无有效lease并标deleting后，禁止所有新引用与lease；对象键不可复用。执行删除前再核验删除任务状态，删除失败重试。仅“检查一次再删”无法消除竞态。

## 9. 后端 API 契约提案

### 9.1 通用约定

- Base URL：`Config.appAuthUrl`；以下 `/chat/favorites` 均为**建议新增接口**。
- Header：`token: <chatToken>`、`operationID: <每次HTTP请求新的跟踪ID>`、JSON Content-Type。
- 归属用户来自服务端验证的 token，忽略/拒绝 body 中 `ownerUserID`。
- 成功外壳沿用业务接口：`{"errCode":0,"errMsg":"","data":{...}}`。HTTP 状态与业务码由网关统一；客户端同时检查二者。
- 写操作 `clientRequestID` 为 UUID，同一用户/operation/ID/请求体重试返回原结果；同键异内容冲突。
- 准备/上传幂等记录建议至少保留 7 天，写操作按 outbox 重试窗口配置。过期重试需通过业务去重/任务状态核对，不能无限宣称幂等。
- 幂等创建命中已删除项时返回“原操作已完成且对象已删除”，不得隐式复活。新收藏动作使用新请求ID。
- 时间 UTC 毫秒，durationMs 使用毫秒，SDK要求秒时由 adapter 明确转换并测试。

### 9.2 总览

| 方法与路径 | 功能 |
| --- | --- |
| `GET /chat/favorites` | 分页列表、关键词/类型/标签筛选 |
| `GET /chat/favorites/{id}` | 私人收藏详情 |
| `POST /chat/favorites` | 从消息/文字/已上传资产创建 |
| `PATCH /chat/favorites/{id}` | 带版本更新正文/标题/标签 |
| `DELETE /chat/favorites/{id}` | 删除，含版本保护/幂等 |
| `POST /chat/favorites/batch-delete` | 批量删除并返回每项结果 |
| `POST /chat/favorites/uploads` | 创建上传会话 |
| `POST /chat/favorites/uploads/{uploadID}/complete` | 核验并返回可引用资产 |
| `POST /chat/favorites/{id}/asset-access` | 授权预览/下载指定资产 |
| `POST /chat/favorites/{id}/prepare-send` | 固定内容版本、返回原件下载授权，不发送 |
| `POST /chat/favorites/{id}/retry-archive` | 重试失败归档任务，复用已授权快照，重检下架状态/原件/配额；未获授权时重新验证来源 |
| `GET /chat/favorites/changes` | 按变更游标增量同步 |
| `GET /chat/favorites/quota` | 当前配额与使用量 |
| `GET /chat/favorite-tags`、`POST /chat/favorite-tags` | P1本人标签列表/创建；创建带clientRequestID/name |
| `PATCH /chat/favorite-tags/{tagID}`、`DELETE /chat/favorite-tags/{tagID}` | P1带expectedVersion改名/删除；删除只解除标签关联，不删除收藏 |
| `POST /chat/favorite-shares` | P1复杂内容创建目标绑定的不可变分享快照与独立资产 |
| `POST /chat/favorite-shares/{shareID}/register-message` | P1发送前持久登记候选clientMsgID/目标/正文摘要，未核实前不开放读取 |
| `POST /chat/favorite-shares/{shareID}/bind-message` | P1将分享绑定实际已发送消息，服务端验证消息/发送者/目标 |
| `GET /chat/favorite-shares/{shareID}` | P1接收者按已验证消息受众权限读取分享 |
| `POST /chat/favorite-shares/{shareID}/asset-access` | P1按分享权限获取独立附件授权 |

静态 `/changes`、`/quota`、`/uploads`、`/batch-delete` 在路由中优先匹配，不被 `/{id}` 吞掉。首期没有 `/favorites/send` 接口，真正发消息由客户端 OpenIM SDK 执行。

### 9.3 列表与搜索

`GET /chat/favorites?cursor=<opaque>&limit=30&q=<keyword>&kind=image&tagID=<tag>`

`limit` 建议 1–100。按 createdAt、id 倒序 seek 分页；游标携带且校验 owner/筛选/排序，不能用于另一用户/另一查询；nextCursor=null 表示没有下一页。搜索在服务端按本人标题、文字、文件名、本人来源展示名和标签查询，P0 不默认 OCR 全部图片。

```json
{
  "errCode": 0,
  "data": {
    "items": [{"id": "fav_01", "kind": "image", "title": "旅行照片", "status": "ready", "version": 3}],
    "nextCursor": "opaque_cursor",
    "changeCursor": "opaque_change_cursor"
  }
}
```

并发新增可能留待刷新，删除会减少后页，客户端按 id 去重与增量同步补齐；不宣称普通 seek 分页自带数据库全局一致快照。`changeCursor` 与列表分页 cursor 是不同类型，不得互换。

### 9.4 创建：从消息收藏

```json
{
  "clientRequestID": "ea267930-d049-4a0e-8b5c-a69a132c8cec",
  "origin": "message",
  "source": {
    "conversationID": "c_origin",
    "clientMsgID": "m_origin",
    "serverMsgID": "s_origin",
    "sequence": 101
  }
}
```

`serverMsgID`/sequence 是否需要、是否可从现网取得由 MessageSourceResolver 确定；示例不是新增 OpenIM 官方消息查询契约。服务端解析可信正文/资产，客户端可带 displayHint 加快占位，但不得将其视为可信快照。

文字可立即返回 ready；媒体异步归档返回 item.status=pending_archive + jobID。通过 changes/详情轮询拿最终状态。建议按(owner,可信sourceIdentity,内容revision)做活跃收藏去重；不同用户收藏同消息是独立记录。自建笔记同文不强制去重；删除后新动作允许再次收藏。

### 9.5 创建：笔记或自建媒体

```json
{
  "clientRequestID": "f0fa5bc9-1e38-4d6b-a389-90ff4b4ba695",
  "origin": "userCreated",
  "kind": "note",
  "title": "工作安排",
  "content": {"blocks": [{"id": "b1", "type": "text", "text": "明天十点开会"}]},
  "uploadIDs": [],
  "tagIDs": []
}
```

媒体 blocks 引用上传完成返回的资产ID，服务端核验该资产属于当前用户且与 uploadIDs 对应。内容和资产引用必须一致，禁止引用其他用户资产或任意外部 URL。

### 9.6 上传和完成

```json
{
  "clientRequestID": "4b7c4fbd-dcd6-4705-9c88-c86e17c77e01",
  "fileName": "meeting.m4a",
  "declaredMimeType": "audio/mp4",
  "declaredSizeBytes": 5242880,
  "purpose": "favorite_original"
}
```

初始化响应含 uploadID、uploadURL/必要头或分片参数、expiresAt、maxSizeBytes。complete 接口核验实际对象后返回 assetID、检测出的 mime/size/hash/尺寸/时长。上传完成不等于收藏创建完成，孤立 asset 在临时规则下清理。

重试沿用 uploadID；过期重新申请时需关联前次请求，避免两个上传都计入最终配额。P0 可先支持受限单文件上传，文件/视频较大时实现分片/断点续传。

### 9.7 编辑、删除、批量删除

PATCH 示例：

```json
{
  "clientRequestID": "b562d6e6-687a-4c47-920f-c49c42f3ea4d",
  "expectedVersion": 3,
  "title": "新的标题",
  "tagIDs": ["tag_01"]
}
```

版本一致才事务更新并递增 version，正文改变时生成新 contentRevision；媒体/旧 revision 按引用延迟回收。冲突返回当前版本摘要，客户端保留本地编辑内容，不用静默覆盖处理。

DELETE 建议使用 query/header 传 clientRequestID 与 expectedVersion，避免依赖某些网关会忽略的 DELETE body。已删除/不存在对本人返回幂等成功；跨用户统一返回不可访问，避免泄露是否存在。

批量接口 body：clientRequestID + items[{id,expectedVersion}]，建议最多 100 项。先验证所有请求项归属与参数，跨账号非法项整体拒绝；合法项返回逐项 deleted/alreadyDeleted/versionConflict，不把部分删除说成全部成功。

### 9.8 发送准备

```json
{
  "clientRequestID": "d3df46ec-ed8a-4d15-abfa-dc0d9956d67f",
  "sendAttemptID": "a75b33c0-16d4-4de7-80e0-d4e4236734d3",
  "expectedContentRevision": "rev_02"
}
```

响应示例：

```json
{
  "errCode": 0,
  "data": {
    "prepareID": "prep_01",
    "contentRevision": "rev_02",
    "expiresAt": 1790980800000,
    "sendContent": {"kind": "image", "blocks": [{"id": "b1", "type": "image", "assetID": "ast_01"}]},
    "downloads": [{"assetID": "ast_01", "url": "https://storage.example.com/temporary-download", "sizeBytes": 2097152, "sha256": "9f1d7c8e6b5a403291827364554433221100ffeeddccbbaa9988776655443322"}]
  }
}
```

sendContent 是经过白名单投影的内容，剔除 owner、favoriteID、私有来源、标签、备注、旧clientMsgID/seq/status；downloads 只是本人临时下载凭证。客户端私有日志也不记录签名 URL/token/完整收藏正文。

准备成功建立短期版本/资产 lease；收藏随后编辑不改变本次准备内容，删除也按已建立lease的有效期处理。幂等保证的是prepareID、内容revision与资产集合；有效lease内重放可重新签发下载凭证，但不延长lease、不换内容。lease过期返回PREPARE_EXPIRED；客户端使用新clientRequestID、原sendAttemptID与原revision申请新准备，只有该revision仍获授权可用时成功，不能自动换到新内容；若消息已构建则仍使用原clientMsgID。

签名URL失效无法收回已经下载到客户端的明文原件。安全下架保证限于后续在线授权/分享读取与客户端获知后的检查，不能承诺物理远程擦除；原件下载完成后发送前仍检查账号、任务取消/已知下架状态。普通删除后既有lease到期就不再授权续期。

P0原生消息prepare不接收发送目标，目标仅由客户端coordinator固定，IM实际权限仍由SDK/IM服务校验。P1复杂分享/媒体合并所需的独立资产与目标授权必须随该功能一起上线，详见第9.11节；P2再优化普通媒体不重复上传，不能信任任意客户端self-declared audience。

### 9.9 增量同步

`GET /chat/favorites/changes?cursor=<opaque>&limit=100` 返回 events、nextCursor、hasMore；事件包括 upsert、delete 和 version。删除事件不返回私人正文。

初次加载在第一页查询前取得同步水位，固定为整个回填基线，后续分页返回的水位不能覆盖它。分页建立缓存后拉取基线之后的变更；按id/version合并，忽略旧版本与迟到的已删除快照。服务端水位与事件必须来自提交顺序可靠的序列，避免事务尚未提交就让游标越过事件。

upsert事件至少携带完整列表DTO及版本；详情按需重新读取。客户端将事件、删除tombstone与新的changeCursor在同一本地事务持久化，成功应用后才推进游标。changes是账号级变更，先更新规范化缓存，再重新筛选当前页面，不能把所有upsert直接塞入当前搜索结果。全量回填不能只用某个类型/关键词的列表，若仅有局部缓存应显式标记覆盖范围。

若沿用Hive而没有跨key事务，使用持久批次journal实现等效提交：先记录events与新cursor，再幂等应用实体，全部成功后提交cursor/清理journal；启动时先恢复未完成批次，恢复前不展示半批状态。不得先保存cursor再异步写实体。

建议 tombstone/changes 至少保存 30 天；游标太旧返回 CURSOR_EXPIRED，客户端重建收藏元数据缓存，再恢复自己未提交的 outbox，不能把旧缓存重新上传当成服务端新数据。

### 9.10 业务错误码

以下用语义名称定义；数值段在真实业务后端统一分配，避免与现有个人表情/资金等错误码冲突。

| 名称 | 含义/前端处理 |
| --- | --- |
| AUTH_INVALID / AUTH_EXPIRED | 重新认证，停止旧身份任务 |
| FAVORITE_NOT_FOUND_OR_FORBIDDEN | 不存在/他人收藏，移除不可用占位 |
| FAVORITE_ALREADY_EXISTS | 返回本人已有项，提示已经收藏 |
| SOURCE_NOT_ACCESSIBLE / SOURCE_REVOKED | 无法验证/已撤回，不创建伪成功项 |
| UNSUPPORTED_CONTENT / PROTECTED_CONTENT | 禁止收藏或发送，明确提示 |
| ASSET_MISSING / ARCHIVE_FAILED | 原件缺失或归档失败，提供任务重试 |
| MEDIA_TOO_LARGE / MEDIA_INVALID | 大小/时长/格式/解码不符合配置 |
| QUOTA_EXCEEDED | 展示配额与管理入口，不无效自动重试 |
| VERSION_CONFLICT | 保留编辑/选项，刷新确认版本 |
| IDEMPOTENCY_CONFLICT | 同请求ID不同内容，修正调用逻辑 |
| PREPARE_EXPIRED | 重新准备，不直接发送失效资产 |
| CURSOR_EXPIRED | 重建缓存与同步水位 |
| RATE_LIMITED / TEMPORARY_UNAVAILABLE | 指数退避与可见重试，避免请求风暴 |

### 9.11 P1复杂内容分享的最小闭环

分享卡片属于新协议，需与接收端同时开发：

1. `POST /chat/favorite-shares` 请求含clientRequestID、sendAttemptID、固定contentRevision/prepareID、target(userID或groupID)及显示原作者信息的显式选项。后端验证本人收藏和发送目标权限，复制独立分享资产，返回shareID与脱敏卡片摘要，状态pending_send。
2. 客户端SDK创建新的白名单自定义消息，只带协议版本、shareID、标题/安全摘要；不带私人favoriteID、来源conversationID或下载凭证。取得新clientMsgID后，先调用register-message持久登记shareID/候选消息ID/固定目标/卡片正文摘要，收到登记成功再交SDK发送。登记不是发送证明，不能开放接收读取。
3. SDK收到成功后调用bind-message；后端也通过可信IM事件/候选消息ID后台对账核实真实发送者、目标、消息正文中的shareID，绑定server定位/序列。应用崩溃/成功回调丢失仍可由发送前登记恢复绑定，不能只依赖客户端再次打开。绑定任务幂等、可恢复；未核实的接收端展示“正在准备”，不放开内容。实际部署无法提供此可信对账能力时，不开启这类卡片。
4. GET分享和asset-access以接收者自己的业务token调用，通过实际消息的可信交付/历史受众策略授权；不向所有当前群成员或猜中shareID的人默认开放。群成员变化/历史访问规则与第14节确认的策略一致。
5. 分享内容与资产保留按聊天策略，删除私人收藏不影响已绑定分享。未登记且不允许SDK发送的prepare可按TTL回收；已经登记的分享只有可信对账明确未发送/已安全终止时才能清理，unknown或仅“长期未绑定”不能触发删资产。未决任务继续占用配额并进入对账/人工处理，不能牺牲已发送卡片来释放容量。安全下架可撤销读取授权。
6. 原生merger如需直接URL附件，另准备符合当前OpenIM媒体访问模式的独立聊天资产并验证嵌套发送；不能把需要本人header的分享asset-access接口URL直接填入原生媒体。未验证时使用上述卡片或逐条发送。

如果真实后端没有可验证IM消息与受众的能力，分享卡片不得开放；该阶段保留逐条发送，复杂分享仍属于待完成项。普通媒体重上传闭环不依赖这套新分享协议。

## 10. 配额、性能与安全边界

### 10.1 建议的初始配置

下面是本项目建议值，不是已上线配置或微信限制。与真实 IM 消息大小、SDK 上传限制和移动网络能力取交集；超出 IM 可发大小的收藏应明确不可快捷发送或提供下载。

| 配置项 | 建议起点 |
| --- | --- |
| 每用户收藏数 | 5,000 条 |
| 每用户归档总量 | 5 GiB |
| 图片/GIF | 单原件 20 MiB |
| 视频/普通文件 | 单原件 100 MiB |
| 语音 | 单原件 20 MiB，时长上限按现网支持确定 |
| 文字正文 | UTF-8 64 KiB；聊天发送上限另校验，可分段提示 |
| 合集blocks | 100 个，嵌套深度 2，附件总量 200 MiB |
| 单次选择发送 | 20 个，按顺序发送 |
| 列表默认页/最大页 | 30 / 100 |
| 下载授权/准备lease | 建议 10 分钟；大文件合理延长，不无限授权 |
| 无引用收藏资产延迟回收 | 7 天 |

归档预留配额使用实际检测字节结算，失败释放预留，重试不重复扣费；同一用户复用同一资产不重复计算物理容量。跨用户内容去重如实现，不能通过hash探测接口泄露他人收藏存在性。

### 10.2 必须落实的安全检查

- 所有详情/编辑/删除/资产/prepare/标签接口验证归属；禁止 IDOR。
- 源消息收藏必须经过授权解析；源URL只接受允许的存储对象定位，不允许任意URL服务器抓取。
- 归档器拒绝内网/metadata地址、危险重定向；有下载字节/时间上限，避免 SSRF 与资源耗尽。
- 文件名只用于展示，落盘使用生成名称；禁止路径穿越。文件默认下载，不在 WebView 执行上传的 HTML/脚本。
- 链接仅允许明确 scheme（如 https/http），用户打开前遵循现有跳转策略；自动抓取预览需同样的 SSRF 防护。
- 归档格式依据文件头/解码核验；视频/图片解码使用隔离任务与资源限额；必要时复用后端已有文件安全扫描。
- 收藏内容私密，日志/监控不记录正文、原件URL、token、本人备注；运营指标使用计数/错误码。
- 私有正文的搜索索引同样按 owner 隔离；不能全库搜完再由客户端过滤。

### 10.3 性能目标与可观测性

目标是点击立即得到可见反馈（建议100ms内）；缓存列表快速展示；媒体显示下载/上传进度。服务时延指标在真实部署测量后定 SLA，不把本文建议当测试结果。

监控收藏创建成功率、归档队列延迟/失败率、同步游标失效率、prepare耗时、下载校验失败、发送 success/failed/unknown、配额预留泄漏、GC重试。operationID 关联 HTTP 调用，sendAttemptID/clientMsgID 关联发送；隐私字段脱敏。

## 11. 多端同步、离线与生命周期

收藏业务数据跨设备同步；发送状态以 IM 系统为准。业务变更可以通过现有可靠业务通知通道提示“有更新”，客户端再拉 changes；首期没有通知能力时在进入收藏、下拉刷新、前台恢复时拉取。

离线创建文本笔记可保存 pendingUpload/outbox；媒体保留原件路径与上传进度。重新联网使用相同 clientRequestID，归档失败不能自动生成多个收藏。删除可以先标 pendingDelete，服务器失败恢复并提示；版本冲突不覆盖他端操作。

页面 covered/resume/background/dispose 需取消 UI 订阅，但 Repository 中已持久化任务可继续受账号生命周期管理；用户关闭面板不自动撤回已经提交 IM 的消息。未提交准备阶段可取消下载；发送已提交则继续跟踪结果。回到聊天时按 clientMsgID 合并 SDK 返回/监听消息，避免双条显示。

## 12. 实施顺序、上线与回滚

| 阶段 | 前端交付 | 服务端交付 | 出口条件 |
| --- | --- | --- | --- |
| 0：确认契约 | 核对SDK签名、ChatTarget/发送结果与缓存方式 | 定位真实后端；确认token、消息读取授权、DB/存储/IM限制 | 无阻断未知项；接口错误/大小/源权限契约锁定 |
| 1：云收藏基本链 | 正式API/Store，现有列表替换，笔记与原件上传 | 元数据/上传/归档/查询/删除/配额/changes | 重启与换设备可恢复，归档状态真实 |
| 2：P0快捷发送 | 长按收藏、工具入口、picker、原生消息builder、SendResult、防重复 | prepare-send/下载授权/lease | 文本图片视频语音文件能在单聊群聊收到并打开 |
| 3：P1完整管理 | 标签、多选、链接卡片、定位/名片、图文笔记/合集，分享接收渲染 | 标签、独立分享资产、实际IM消息绑定/受众授权与接收接口 | 复杂内容与部分失败可恢复，接收端兼容 |
| 4：优化 | URL资产模式、缓存策略/断点续传、性能 | 聊天资产转交/安全复用、索引与监控完善 | 性能实测达标，不改变隐私/删除语义 |

上线顺序：向后兼容的数据库迁移 → 后端与归档worker → 内部验证 → 带 capability/feature flag 的客户端 → 分批开放 → 验收后开启P1。

服务端公布 supportsFavorites、supportsPrepareSend、supportedKinds、quota 与单附件限制等能力；具体接入现有配置接口还是新增 capabilities 由真实后端决定。客户端未拿到准备发送能力时禁用该入口，不静默回落成假内存收藏。

回滚用功能开关关闭新建/快捷发送，仍保留已保存内容的只读访问与导出；停止GC危险策略并保留资产。无需回滚 OpenIM SDK 核心或破坏已有聊天历史。迁移为新增表/字段，灰度期间不做不可逆删除。

## 13. 验收场景与开发验证

以下为**要实现后执行的验收要求**；本文编写没有执行这些功能测试。

| 场景 | 操作与期望 |
| --- | --- |
| 文本闭环 | 长按收藏 → 当前会话快捷发 → 对方收到同样正文，clientMsgID为新ID |
| 输入草稿 | 输入一段未发送文字/@后发送收藏 → 原输入与草稿保留 |
| 真视频 | 收藏视频 → 重启/换设备 → 可播放原视频并重新发送，不能只有封面 |
| 语音/文件 | 语音时长/编码正确；文件名/字节一致；接收端能播放/下载 |
| 图片/GIF | 原件完整、缩略图正确；GIF不因缓存/SDK转换丢帧，无法保真时明确限制 |
| 目标固定 | 打开A会话收藏面板后切换路由/等待下载 → 仍只发A，或明确取消 |
| 单聊群聊 | userID/groupID二选一；禁言/退群/非好友按现有SDK错误显示失败 |
| 原消息删除 | ready收藏后删除原消息/清空会话 → 收藏仍可看与发 |
| 撤回时序 | 已获取可信授权快照且pending时普通撤回，继续归档；取快照前已撤回则拒绝；安全下架停止归档并禁读 |
| 收藏删除 | 已发送收藏媒体后删除收藏并执行GC → 旧聊天媒体仍可访问 |
| 失效授权 | 下载URL过期 → 刷新授权；聊天消息不携带临时收藏URL |
| 多端编辑 | A/B编辑同version → 一方成功，另一方冲突且不丢本地修改 |
| 多端删除 | A删除，B增量同步 → tombstone移除旧项，迟到响应不复活 |
| 离线/断点 | 上传中断/重启 → 同一任务恢复，不重复收藏，不虚报已保存 |
| 连点/未知 | 连点只一次；SDK超时标待确认并先对账，不盲目建新ID重发 |
| 重复主动发送 | 成功后再次明确点击 → 可发第二条，不能被永久去重 |
| 部分发送失败 | 第1成功第2失败 → 保留结果，只重试失败，不重发第1 |
| 分享绑定崩溃 | 登记clientMsgID后IM已接受、客户端崩溃 → 后台核实并绑定；未知状态不因TTL删除已发卡片资产 |
| 同步批次崩溃 | 应用events中途退出 → journal/事务恢复，cursor不越过未应用事件，无漏项/复活 |
| 越权 | 他人favoriteID/assetID/标签/伪造源定位 → 无法获取私有内容 |
| 配额并发 | 并发归档不突破预留容量；失败释放配额 |
| 私有数据外发 | 接收消息无favoriteID、原会话ID、本人备注/标签/临时授权凭证 |
| 未知类型/旧客户端 | 新schema显示兼容占位禁发；卡片启用前有接收端降级 |
| 大数据 | 超过500条依旧服务器分页搜索，换筛选不串结果 |
| 平台/主题 | Android/iOS、亮暗主题、大字体、键盘、SafeArea与手势返回正常 |

建议新增 `favorite_api_test.dart`、`favorite_repository_test.dart`、`favorite_message_builder_test.dart`、`favorite_send_coordinator_test.dart`、`favorite_picker_sheet_test.dart`；保留/调整已有草稿测试。后端增加接口/授权、归档、并发配额、GC与幂等集成测试。

当前已存在的相关回归测试包括 `test/favorites_draft_store_test.dart`、`test/chat_message_menu_test.dart`、`test/chat_toolbox_paging_test.dart`、`test/chat_input_box_test.dart`。实现后在项目根目录执行对应范围，例如：

```powershell
flutter analyze
flutter test test/favorite_message_builder_test.dart test/favorite_send_coordinator_test.dart test/favorite_picker_sheet_test.dart
flutter test test/chat_message_menu_test.dart test/chat_toolbox_paging_test.dart test/chat_input_box_test.dart
```

第一组收藏测试路径是建议新增，创建之前不能作为已通过的验证命令。项目 `.flutter-version` 为 3.32.8，实施时使用项目配置环境；后端命令在定位真实仓库后按其构建/CI脚本补充，不假定本地ASR代理是收藏服务。

## 14. 实施前必须确认的事项

这些问题不影响本文方案，但会影响服务端编码与上线：

1. **真实后端仓库与版本**：定位 appAuthUrl 对应服务，确认路由/认证中间件/数据库；本工作区不能证明其目录结构。
2. **消息来源授权能力**：确认现网能否由后端按定位读取消息，并取得真实交付/受众/保护/撤回状态；如不能，采用明确的自建导入降级，不能伪造已验证来源。
3. **对象存储策略**：确认 provider、私有读取、复制、分片、生命周期、删除权限；验证独立收藏资产可长期保留。
4. **现网SDK/服务限制**：核对单消息体、媒体大小、格式、群发权限、未知发送结果查询/重试语义。
5. **撤回/安全下架规则**：确认普通撤回后已有收藏是否保留，以及安全删除如何传播至收藏；本方案默认规则见第3节。
6. **复杂分享接收端**：P1/P2自定义卡片必须确认移动端/旧客户端/其他平台渲染和分享资产授权，明确群成员变化后的访问策略。
7. **容量与费用**：按真实用户量和媒体量调整配额/备份/回收时间；建议起点不等于批准的存储预算。

## 15. 证据与文档状态

- 当前主项目 HEAD：`df95207df8a100ef5e604659365334143caa33be`。工作区有未提交修改，本文优先依据写作时的工作区源码，引用行号可能随后续开发变化。
- 源码调查覆盖现有收藏页、聊天发送、菜单/工具箱、业务token/存储模式、解析SDK签名，以及99Chat收藏参考。没有借用其他99Chat工作树的图谱推断本项目。
- GitNexus已登记仓库中没有当前 `E:/openim/openim-flutter-demo` 或参考路径；没有本项目可用的图谱/PDG。因此调用关系与现状结论来自定向源码核查，未声称做过图谱影响验证。
- 本文件为普通Markdown技术设计，不是自动执行计划或经图谱验证的实现上下文包。开发前应对被改符号与当前最新工作区再做影响核查。
- 本次交付只新增设计文档；没有把这里的接口、表、功能、默认配额或测试结果标成已实现。

后续开发应以本文件第12节分期与第13节场景验收：先交付真实云收藏与当前会话一键发送，再补齐复杂管理/分享能力。
