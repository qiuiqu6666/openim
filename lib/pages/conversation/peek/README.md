# 会话长按预览

对照本地 `reference-99chat` 的 `d7c3c65`：
`lib/src/widgets/conversation_peek/conversation_peek_overlay.dart`、
`conversation_peek_actions.dart`、`conversation_peek_message_item.dart`，以及
`lib/src/conversation.dart` 中主会话与归档页的长按入口。

`conversation_peek_entry.dart` 将主列表、群聊、分组与归档页面的现有动作
转换成预览菜单。`conversation_peek.dart` 协调展示与关闭，菜单选中后等待
220ms 退场及路由实际移除，再打开聊天、分组选择或删除确认。
每次动作重新查找当前会话，检查页面挂载、账号会话及编辑状态。

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

`conversation_peek_content.dart` 负责逆序滚动、日期与加载/空/重试状态。
短首屏自动补齐更早历史；整个窗口被过滤时保留显式更早消息入口，
分页失败可重试同一游标。没有可见性回调的只读消息不注册焦点追踪。
`conversation_peek_message.dart` 复用现有 `ChatItemView`、头像、文本、
图片、语音、文件、名片和资金卡片。共享消息组件仅扩展紧凑间距/头像
尺寸与图片尺寸参数；语音的只读模式不下载音频或提取波形，视频使用
聊天模块共享的 `ChatVideoThumbnail`，不创建播放器。私密消息（包括
引用/合并中的私密内容）提示进入会话查看，不启动阅后即焚显示或读取。
资金卡片沿用真实历史快照，未查询订单状态时不显示为已确认资金状态。

`conversation_peek_menu.dart` / `conversation_peek_actions.dart` 只展示可用
动作并报告选择。主列表：归档、添加至分组、置顶、静音、删除；当前分组
可移出分组。归档页：取消归档、置顶、静音、删除。全部继续使用现有
OpenIM SDK 与 Chat 归档/分组接口。没有添加 SDK 不支持的“标记未读”；
参考主列表/归档页也没有传入该回调。

测试位于 `test/pages/conversation/peek/`，页面集成回归在原会话/归档测试。
测试中的历史和账号 fixture 不进入正式代码。真机账号联调需在设备上
核对快速连续长按、历史滚动、返回、网络失败、切换账号与实际菜单操作。

验证：本次203项相关回归用例通过（会话/分组/归档、预览、共享聊天消息
与图片生命周期），另两项真实组件截图测试导出 Android/iOS 亮暗主题。
相关生产与测试文件静态检查无问题，Android debug 资源构建通过。
预览截图在 `docs/previews/peek[-ios]-{light,dark}.png`；未执行真机联调。
