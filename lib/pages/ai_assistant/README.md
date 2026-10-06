# AI 助手模块

生产入口为「我的 → 热门生态 → AI助手」以及会话列表中的助理单聊，统一打开
`AiAssistantChatPage`（`/ai_assistant_chat`）。`ChatBinding` 创建并释放现有
`ChatLogic`，按 SDK 的实际会话 ID 维护同一条单聊，不再创建独立 AI 历史。

## OpenIM 接入契约

- 全站账号为 `assistant`，昵称 `AI助理`，单聊 `sessionType=1`。
- 稳定 ID `assistant` 在 SDK `ex` 尚未返回时也显示官方认证图标；生产对话
  标题复用 `OfficialAccountNameLabel` 和共享 18dp 认证资源，与联系人、会话
  列表使用同一身份规则，普通同名好友不显示认证。助理保持现有交互能力。
- 登录沿用 `userID` / `imToken` 和现有 SDK，API `http://8.217.191.236:10002`、
  WebSocket `ws://8.217.191.236:10001`。助理入口、名片选择、附件和出图均不调用
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

- `test/pages/ai_assistant/navigation/`：官方账号识别、所有聊天入口、账号切换保护
- `test/pages/ai_assistant/openim/`：真实 ChatLogic 的 SDK 收发、正在输入、普通图片、
  亮暗主题、大字体、键盘和安全区；可通过 `AI_ASSISTANT_PREVIEW_DIR` 导出预览
- `test/pages/ai_assistant/protocol/`：出图／群名片载荷和 20 MiB 文档限制
- `test/pages/ai_assistant/data/`：协议、上传、输入校验和流解析
- `test/pages/ai_assistant/controller/`：服务关闭、停止、迟到响应和生命周期
- `test/pages/ai_assistant/presentation/`：亮暗主题、引导、搜索、菜单、键盘、
  安全区和大字体
- `test/mine_page_99chat_test.dart`：AI 入口已开放、其它入口行为保留

设置 `AI_ASSISTANT_PREVIEW_DIR` 后，界面测试可导出亮暗主题的 PNG 预览。
系统附件权限、真实 AI 服务和 iOS 打包需在对应环境另行验证。
