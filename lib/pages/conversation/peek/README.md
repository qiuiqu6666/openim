# 会话长按预览

对照本地 `reference-99chat` 的 `d7c3c65`：
`lib/src/widgets/conversation_peek/conversation_peek_overlay.dart`、
`conversation_peek_actions.dart`、`conversation_peek_message_item.dart`，以及
`lib/src/conversation.dart` 中主会话与归档页的长按入口。

`conversation_peek_entry.dart` 将主列表、群聊、分组与归档页面的现有动作
转换成预览菜单。`conversation_peek.dart` 协调展示与关闭，菜单选中后等待
220ms 退场及路由实际移除，再打开聊天、分组选择或删除确认。
每次动作重新查找当前会话，检查页面挂载、账号会话及编辑状态。
打开期间订阅已有会话、归档/分组状态和分组列表，实时刷新菜单及高度，
关闭后取消订阅。动作保存点击时的目标状态，避免退场期间的远端更新
把“置顶”反转成“取消置顶”；静音晚回包不能修改已切换的账号。

`conversation_peek_menu_icon.dart` 按用户提供的图标参考绘制圆头、圆角
矢量轮廓：归档盒/向下箭头、加号文件夹、竖直图钉、斜线铃铛、单线
垃圾桶。两端使用同一路径，删除保持红色；取消静音与移出分组使用
同一风格的铃铛/减号文件夹。原来的系统 Material 字体图标不再用于此菜单。

单聊标题的在线副标题复用联系人 `ContactPresencePolicy`：官方服务账号
始终显示在线，普通好友保留真实缓存及隐私文案。全局显示偏好和共享
联系人控制器的有效性检查继续生效，群聊副标题保持原逻辑。

`conversation_peek_overlay.dart` / `conversation_peek_layout.dart` 只管理界面：
最近聊天卡片、中央标题胶囊、右下独立菜单、35% 遮罩和淡入淡出。
尺寸按参考的屏幕比例计算；Android 沿用参考的无模糊背景，iOS 使用
12px 背景模糊。亮暗主题使用项目 Token；小窗口、大字下菜单可滚动。

`conversation_peek_loader.dart` 独立持有只读历史窗口，真实数据来自
OpenIM `getAdvancedHistoryMessageList`，首屏与向上分页每次30条。
复用现有 `ChatHistoryCache`，不创建 `ChatLogic`、不另注册 SDK 监听、
不标记已读、不清未读、不写草稿。缓存和 SDK 对象先复制，保留 SDK
原始页游标，过滤已删除/到期消息也不会丢失下一页；失败保留窗口并可重试。
销毁、账号/token变化、清历史、缓存失效后的晚回包不能写回界面或缓存。
SDK 历史中 `attachedInfo` 的字符串 `"null"` 与字段缺失都表示没有额外
元数据，不能当作解析损坏而过滤整条文字/引用消息，也不能将引用误判
为私密消息；结构化的真实私密标记和损坏数据保护仍然优先。

`conversation_peek_content.dart` 负责逆序滚动、日期与加载/空/重试状态。
短首屏自动补齐更早历史；整个窗口被过滤时保留显式更早消息入口，
分页失败可重试同一游标。没有可见性回调的只读消息不注册焦点追踪。
`conversation_peek_message.dart` 复用现有 `ChatItemView`、头像、文本、
图片、语音、文件、名片和资金卡片。共享消息组件仅扩展紧凑间距/头像
尺寸与图片尺寸参数；语音的只读模式不下载音频或提取波形，视频使用
聊天模块共享的 `ChatVideoThumbnail`，不创建播放器。私密消息（包括
引用/合并中的私密内容）提示进入会话查看，不启动阅后即焚显示或读取。
资金卡片沿用真实历史快照，未查询订单状态时不显示为已确认资金状态。

引用回复复用聊天页的 `ChatQuoteCard`，同时读取普通引用的 `quoteElem`
和带 @ 回复的 `atTextElem.quoteMessage`；原发送者、摘要/媒体缩略图与
回复正文一起展示。私密内容检查也覆盖带 @ 引用。图片继续复用
`ChatPictureView`：高宽比超过 3 的长图先取头部 3:5 裁切区域，再按
预览的 220×260 上限和实际可用宽度缩放，避免先按整图高度缩成细条。
普通照片保留原始比例；长图及引用中的长图缩略图沿用原图/大图清晰来源、
头部裁切和受限解码预算。

自定义消息与聊天页共用 `chat/messages/custom/chat_custom_message.dart`，
包含通话、资金、好友/群状态提示及 AI 工具卡片，预览按聊天字体偏好显示。
自定义正文优先读取真实 data 中的 text/content/body/markdown，兼容嵌套
JSON 字符串，保留换行、Markdown 标题/列表/表格。未知协议保留原文或
格式化 JSON，不用列表摘要替代正文；空 data 才回退 description。未知
业务卡片不会被猜测成可操作卡片，原始 HTML 也不会执行。AI 卡片的被动
展示单独提取，不创建 AI 或聊天控制器。

`conversation_peek_menu.dart` / `conversation_peek_actions.dart` 只展示可用
动作并报告选择。已有分组显示“移动至分组”，没有分组显示“添加至分组”；
全部列表、当前分组和归档页都可移出所属分组。归档页也能选择/新建分组，
移入分组会取消归档，单独移出分组保留归档状态。置顶、静音、归档按
实时状态显示反向操作，删除继续保留确认和待处理保护。全部使用现有
OpenIM SDK 与 Chat 归档/分组接口。没有添加 SDK 不支持的“标记未读”；
参考主列表/归档页也没有传入该回调。

测试位于 `test/pages/conversation/peek/`，页面集成回归在原会话/归档测试。
测试中的历史和账号 fixture 不进入正式代码。真机账号联调需在设备上
核对快速连续长按、历史滚动、返回、网络失败、切换账号与实际菜单操作。

2026-10-07 验证：预览/分组/归档/自定义正文 130 项回归通过，另两项真实
组件截图测试导出 Android/iOS 亮暗主题。扩大到会话、聊天消息、AI 和
Markdown 后 502 项通过、12 项跳过，1 项独立名片导航测试失败（
`contact_card_message_test.dart` 的 SDK-target profile navigation，单独
复测仍失败），没有将其计为通过。Android debug APK 构建通过。
预览截图在 `docs/previews/peek[-ios]-{light,dark}.png`；未执行真机联调。

同日引用/长图修复回归：`conversation_peek_reply_media_test.dart` 覆盖 SDK
历史序列化、普通/带 @ 引用、文字/图片引用、私密引用、双向长图及窄容器。
按设备日志补上 `attachedInfo: "null"` 的历史样本，修复前 13 项渲染
用例全部复现消息被过滤；修复后也覆盖缓存首屏、SDK 新页和真实私密标记。
预览、图片、引用、Markdown 和图片生命周期共 143 项通过，7 项可选截图
测试跳过；另行开启媒体截图导出，核对 Android/iOS 亮暗主题。
效果图为 `docs/previews/peek-reply-media[-ios]-{light,dark}.png`，通过
`--dart-define=EXPORT_PEEK_PREVIEW=1 --dart-define=PEEK_MEDIA_PREVIEW=true`
运行 `conversation_peek_preview_test.dart` 生成。
