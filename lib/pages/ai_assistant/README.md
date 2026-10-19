# AI 助手模块

生产入口为「我的 → 热门生态 → AI助手」以及会话列表中的助理单聊，统一打开
`AiAssistantChatPage`（`/ai_assistant_chat`）。`ChatBinding` 创建并释放现有
`ChatLogic`，按 SDK 的实际会话 ID 维护同一条单聊，不再创建独立 AI 历史。

## OpenIM 接入契约

- 全站账号为 `assistant`，昵称 `AI助理`，单聊 `sessionType=1`。
- 稳定 ID `assistant` 在 SDK `ex` 尚未返回时也显示官方认证图标；生产对话
  标题复用 `OfficialAccountNameLabel` 和共享 18dp 认证资源，与联系人、会话
  列表使用同一身份规则，普通同名好友不显示认证。助理保持现有交互能力。
- 登录沿用 `userID` / `imToken` 和现有 SDK，API 和 WebSocket 分别读取当前节点的
  `Config.imApiUrl`、`Config.imWsUrl`。助理入口、名片选择、附件和出图均不调用
  Chat HTTP 接口，不用 `chatToken` 认证助理。
- 「我的」入口通过 SDK `getOneConversation(sourceID: 'assistant', sessionType: 1)`
  打开会话，SDK 决定会话 ID（例如 `si_assistant_im_a`）。好友关系仍由服务端补齐，
  SDK 拒绝发送时保留失败消息，使用现有重试能力。
- `startChat` 优先识别 `assistant`，其它单聊解析会话或 SDK 用户资料的 `ex` JSON
  字符串，`accountType == 'official'` 打开官方账号页面。解析失败或资料不可用时
  保留普通会话入口。异步查询返回后重新验证账号及 `imToken`。
- 普通输入用文本／引用消息；个人名片用 SDK 108；群名片用 110，
  `description='groupCard'`，`data={groupID,groupName,faceURL}`。
- 仅选中「生成图片」才用 110，`description='image'`，`data={prompt}`。
  普通文字中的出图措辞仍是文本消息；空提示词交给服务端返回说明。
- 图片通过现有 SDK 上传及发送，图片表情用 115 且 `data` 为图片 URL。
  文件选择仅接受 PDF、DOCX、TXT，保留后缀，每个文件不超过 20 MiB。
  收藏复用现有收藏发送器；外部会话可读权限由服务端验证。
- `contentType=113` 的 `typingElem.msgTips='yes'` 只显示正在输入，完整回复清除
  提示；online-only SDK 回调也分发给当前会话，不写入消息列表或另发通知。
  SDK 原有 input-state 事件继续兼容。
- 收到的 101 原文／失败提示、102 图片复用普通消息渲染。AI 文本使用已有
  Markdown 展示，图片预览、长按复制、收藏、引用、多选、已读和失败重试继续由
  共用消息组件处理。服务端的记忆隔离、消息合并和 60 秒出图超时不在客户端重做。

## SDK 流式回复与诊断

- 主输入区点击发送后，先在消息列表显示临时「正在回复…」气泡，再创建或发送
  SDK 消息；文本、暂存名片、附件及生成图片指令共用这一发送流程。连续尚未收到
  回复的发送合并为一个等待气泡，每次发送拥有独立取消 token。首个新流继承气泡
  的稳定 `presentationID`，首段连续非空正文到达后原气泡切换为 Markdown；首片
  为空或乱序时继续显示等待。等待和在线正文不写入 SDK 消息历史或本地历史缓存。
- 普通完整文本或图片回复也结束本地等待，typing 不结束。已知旧流的后续分片或
  最终回复、历史同步均不会清除较新的等待。发送未成功时只取消本次 token；同批
  已有附件成功发出或较早发送仍在等回复时保留有效等待。失败 SDK 消息和可编辑
  输入沿用现有恢复能力，页面关闭释放全部等待和分片，账号失效后的异步发送不再
  修改新账号。存在等待或分片气泡时抑制页底重复的思考提示。
- 这是即时发送反馈，不缩短模型首段生成或上游推送等待，不人为延迟真实分片或
  制造逐字播放。表情、收藏确认发送及失败重试开始实际 SDK 投递到助理时，也通过
  共享 `ChatDeliveryController` 创建等待 token，与主输入区提前创建的等待合并，
  不增加重复气泡。完成钩子在投递失败或账号失效时取消对应 token；当前会话及
  真实投递目标必须同时为 `assistant`，转发到其他用户或群不创建助理等待。
- 分片使用 `contentType=110`、`customElem.description='assistantStream'`、
  `isOnlineOnly=true`；`customElem.data` 是 JSON 字符串，包含非空 `streamID`、
  从 0 连续递增的整数 `index`、新增文字 `text` 和布尔 `end`。末片 `end=true`。
  兼容 Go `omitempty` 省略零值：缺少 `index` 视为 0，缺少 `end` 视为 false；
  显式 null、错误类型、负索引以及缺少 `streamID` 或 `text` 仍拒绝解析。
  这是协议兼容处理，不代表已经确认线上后端省略字段或确定了真机等待完整回复的原因。
- SDK 的在线回调将分片转给当前助理单聊。接收前检查 `sessionType=1`、发送者
  `assistant`、当前 IM 收件人及路由所属账号和登录凭据。分片按索引拼接并去重，
  不等待末片就更新非空气泡，不进入 SDK 消息历史、未读数或通知。
- 最终回复为正常保存历史的 `contentType=101` 消息，`ex` 是携带同一 `streamID`
  的 JSON 字符串。最终消息替换临时气泡并屏蔽迟到分片；重连后同步到的最终历史
  也会执行替换。在线分片不重放，丢失前片时后片等待连续索引，完整最终消息负责
  恢复正文。日期定位或最新窗口加载中发送时，本地请求的等待与实时正文即时显示
  在历史列表下方的受限反馈区，仍不写入历史或改写 SDK 历史窗口。
  未由本地请求产生的旧流在该窗口继续隐藏，回到最新后恢复正常流式列表。
- `streaming/diagnostics/assistant_stream_log.dart` 输出 `[AI流式]` 阶段摘要：
  `submit`（发起发送）、`receive`（SDK 接收）、`route`（路由过滤）、`invalid`
  （载荷拒绝）、`accept`（状态接收）、`bubble_build`（非空气泡构建）、`final`
  （完整消息）。摘要仅记录时间、类型、字段存在性、索引、字符长度、身份匹配
  布尔值和流 ID 摘要，不输出正文、原始载荷、账号 ID 或 Token。SDK 账号尚不可读时
  收件人匹配记录为 null，不阻断消息投递。接收日志也覆盖来自助理但消息类型或
  description 不匹配的外壳，仅记录是否匹配，不输出 description 原文。
  接收、路由分别记录每条流在该阶段的首次到达，包括先收到非零索引的情况；
  后续与状态日志一样抽样记录索引 0、每 10 片及末片。气泡构建日志按字符长度
  档位去重。默认仅调试构建开启，`AI_STREAM_DIAGNOSTICS` 可显式控制。
- 单元和页面测试验证的是客户端协议及展示逻辑。真实模型 → 助理服务 → OpenIM
  → 手机的逐段回复效果仍需对照同一轮分片和最终消息日志联调，不能由测试通过
  推定真机流式已生效。

## 参考与当前范围

界面和交互依据本地 `reference-99chat` 的真实实现，版本
`d7c3c655b20dd06458d1882b114e68c1c24133e3`：

- `lib/src/pages/ai_assistant/ai_assistant_page.dart`
- 同目录的消息、文件、搜索和上传辅助模块
- `assets/ai/{11,22,33,44,99chat}.webp`、`bg.png`、`welcome.jpg`

素材未改动，7 个文件的 SHA256 均与参考仓库相同。界面布局经过当前
OpenIM 的主题、生命周期和数据入口适配；使用 Apache-2.0，完整许可位于
`docs/licenses/99chat-APACHE-2.0.txt`，素材来源见 `docs/third-party-assets.md`。

独立对话复用原有 AI 页面背景、素材、头部、空状态、工具栏和输入区，移除普通
聊天的电话／视频按钮和重复好友通知。亮暗主题、键盘避让和安全区沿用当前设计
系统。生产消息来自真实 SDK；预览样例只存在于测试文件。

## 目录职责

| 目录/文件 | 职责 |
| --- | --- |
| `ai_assistant_chat_page.dart` | 生产 SDK 会话组合、对话内搜索、焦点与页面布局 |
| `navigation/official_account_resolver.dart` | 官方账号识别，供所有聊天入口统一路由 |
| `protocol/ai_openim_payload.dart` | SDK 自定义消息载荷和文档限制 |
| `streaming/` | 本地发送等待、在线分片拼接、最终回复替换和阶段诊断 |
| `presentation/composer/ai_openim_composer.dart` | SDK 发送、工具、附件暂存、收藏与表情入口 |
| `presentation/messages/ai_openim_message_tile.dart` | SDK 消息的 AI 头像、Markdown 和指令显示 |
| `ai_assistant_page.dart` | 旧视觉预览页，不由生产入口创建 |
| `controller/` | 旧网关预览的历史、工具草稿、回复状态及取消 |
| `models/` | 消息、文件、名片和输出模型 |
| `data/` | 旧网关预览的协议与解析，生产 SDK 页面不调用 |
| `composer/` | 草稿模型、工具输入和附件限制校验 |
| `attachments/` | 系统图片/文件选择、页面文件缓存限制 |
| `history/` | 服务端历史到显示模型的转换 |
| `search/` | 文本搜索、复制和高亮规则 |
| `picking/` | 真实联系人、群组和会话的 AI 名片选择 |
| `storage/` | 按账号保存引导和欢迎图的关闭状态 |
| `navigation/` | 常规头部和对话搜索头部 |
| `presentation/background/` | 原版渐变、光晕和星点 |
| `presentation/guide/` | 四页首次引导 |
| `presentation/empty/` | 空状态和欢迎图 |
| `presentation/messages/` | 消息气泡、Markdown、文件和结果卡片 |
| `presentation/history/` | 延迟构建的历史列表 |
| `presentation/composer/` | 工具、附件草稿、输入区和动作菜单 |
| `theme/` | 原版亮色数值、现有暗色主题及尺寸常量 |
| `localization/` | 页面文案和工具输入提示 |

生产页面只使用 `ChatBinding` 所有的聊天控制器和 SDK 订阅，复用
`chat/messages/widgets/chat_message_list.dart` 的历史、读回执、视口和多选能力。
页面拥有搜索资源，输入和焦点继续由聊天控制器持有，关闭页面沿用原有草稿和
SDK 资源清理链路。附件暂存仅属于当前页面和当前 `userID` / `imToken`；
异步选择或发送返回后再次检查账号、收件人及页面关闭状态。失败消息仍可重试，
未发送附件和文本保留。

以下生命周期说明仅适用于保留的旧预览页：
旧页面拥有默认创建的 controller；注入 controller 的调用者负责释放。
Controller 不持有 BuildContext、FocusNode 或滚动对象。回复文字使用独立
ValueNotifier，每 32ms 合并发布，普通流式更新只重建当前回复行。页面滚动
每帧合并，逐字输出不重复启动动画；查看历史时不会被输出拉回底部。
搜索计数仅在搜索已开启且匹配集合改变时刷新。

停止、清空、替换回复、切换账号和页面销毁会取消流、计时器和历史请求。
账号身份包含 userID 和 Chat token，迟到的数据不会写入新账号。
下载按文件 ID 去重，页面预览缓存上限 32MiB，页面退出后释放。

## 旧界面预览兼容

`AiAssistantPage`、原有 `controller/` 和 `data/` 仅保留旧视觉预览／测试兼容，
不再由生产入口创建。旧 SSE／HTTP 契约不属于当前助理接入，也不应通过
`serviceEnabled` 打开生产功能。生产 SDK 页面没有新 Chat HTTP 接口或文件 ID。

## 验证入口

### 图文作为一次提问

- 输入文字并添加 1–3 张图片时，先完成全部上传，再发送唯一一条 SDK custom
  消息（`description: assistantTurn`）。载荷含 `version: 1`、独立 UUID `turnID`、
  `text` 和 `images: [{url, name}]`。引用文字合入本次问题。
- 通过助理公开资料 `ex.assistantTurnVersion == 1` 核对服务支持；不支持时保留
  草稿并提示，不回退到分别发送。图片与其它文件、名片混选时需先调整附件。
- 选中“生成图片”并添加参考图时，同一载荷增加 `intent: generate_image`。
  需公开资料 `assistantImageEditVersion == 1`；服务端将参考图原始像素与文字
  一起发往图片编辑接口，只请求一张结果图。无参考图时继续使用原纯文字生图流程。
  参考图失败不降级成纯文字生图；上游限流时返回繁忙提示。图片回复也使用持久去重。
- 图片准备或上传失败不发消息、不清草稿；进入消息列表后的失败由该消息重试，
  重试保留同一个 `turnID`。历史、复制和会话摘要可以显示这条图文问题。
- 服务端每个显式图文消息单独组成视觉模型输入，不再依赖队列时间窗口。
  用户与 `turnID` 共同生成持久去重键，最终回复发送前占用唯一记录。
  回执不确定时保留记录、不自动重复发送；这属于至多一次发送，不能保证进程在
  占位后、发送前崩溃时仍然送达。需要再次提问时创建新的提交。
- `openim/ai_image_turn_test.dart` 覆盖完整上传后单消息创建、部分上传失败、
  旧服务能力校验、账号切换、非法载荷、窄屏图文展示与图片可访问名称。

### 2026-10-19 可靠性与交互修正

- 本地等待和每条流分别计时；两分钟没有新增可显示内容时改为静态等待说明，
  保留已生成正文，迟到分片/最终回复仍可恢复展示。该提示不代表取消了服务器任务。
  页面关闭、等待取消、最终回复和清空都会释放对应计时器。
- 已存在或已删除的 SDK 消息重放只协调最终流状态，不消费新问题的等待。
- 输入区最多占可用正文高度的 65%，超出后可滚动，保留多行输入和引用草稿。
- 工具按钮使用完整的至少 48 高点击区域切换选择，取消图标不再独立占用无名称的小点击区域。
- 当前窗口查找明确标注“查找已加载消息”，并提供复用 `ChatHistorySearchPage`
  的“搜索全部聊天记录”入口；完整搜索的数据范围和可用性仍由共享搜索服务决定。
- `openim/ai_assistant_reliability_test.dart` 覆盖长等待、迟到回复、并发流计时、
  重复旧消息、搜索范围、按钮切换及小屏键盘下的多行引用输入。

- `test/pages/ai_assistant/navigation/`：官方账号识别、所有聊天入口、账号切换保护
- `test/pages/ai_assistant/openim/`：真实 ChatLogic 的 SDK 收发、正在输入、普通图片、
  亮暗主题、大字体、键盘和安全区；可通过 `AI_ASSISTANT_PREVIEW_DIR` 导出预览
- `test/pages/ai_assistant/openim/ai_assistant_reply_wait_page_test.dart`：主发送按钮
  即时等待、首段原气泡切换、失败恢复、普通结果以及关闭和账号隔离
- `test/pages/ai_assistant/streaming/`：分片顺序与去重、零值兼容、等待 token 隔离、
  稳定显示 ID、历史不消除新等待、清理与诊断摘要
- `test/pages/chat/messages/chat_delivery_controller_test.dart`：共享 SDK 投递、
  转发目标、成功失败状态及关闭/账号切换后的完成处理
- `test/pages/ai_assistant/protocol/`：出图／群名片载荷和 20 MiB 文档限制
- `test/pages/ai_assistant/data/`：协议、上传、输入校验和流解析
- `test/pages/ai_assistant/controller/`：服务关闭、停止、迟到响应和生命周期
- `test/pages/ai_assistant/presentation/`：亮暗主题、引导、搜索、菜单、键盘、
  安全区和大字体
- `test/mine_page_99chat_test.dart`：AI 入口已开放、其它入口行为保留

设置 `AI_ASSISTANT_PREVIEW_DIR` 后，界面测试可导出亮暗主题的 PNG 预览。
系统附件权限、真实 AI 服务和 iOS 打包需在对应环境另行验证。
