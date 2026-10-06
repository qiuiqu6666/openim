# 聊天消息行组件

`chat_message_tile.dart` 是单条聊天消息的界面入口，包含 ChatItemView 参数适配、长按菜单、提及链接、媒体预览、资金/通话等自定义消息展示。视频缩略图的异步本地路径状态由媒体模块的共享 `ChatVideoThumbnail` 持有，会话预览也复用同一组件。

ChatPage 负责页面结构、标题、消息列表、输入和背景；消息列表保留最外层 message key、反向索引和 findChildIndexCallback。ChatMessageTile 显式接收 `message` 和现有 ChatLogic 公开界面 facade，只代理事件，不持有 SDK 订阅、不访问私有控制器，也不改变数据模块的依赖方向。

`ChatMessageList` 负责实时消息入场的 ticker 和按消息 ID 保留的进度；动画包装放在原有 message key 内。入场资格、完整绘制后才确认阅读和取消策略见 `../arrival/README.md`。历史加载、本人投递及回执刷新不会产生入场动画。

普通消息保持单行 Obx；语音行额外监听 voiceTranscriptions。资金卡片仍使用自身的状态 Obx。媒体预览保留构建时的局部 context，异步图库完成后检查页面关闭和 context.mounted；普通视频缩略图异步检查本地文件，并按显示宽度和设备像素比设置解码尺寸。

默认文字气泡通过公共 `ChatInlineMetadata` 排列正文和时间；与自定义 `ChatTextBubbleLayout` 是两条入口。保留原有 6px 横向、4px 换行间距和时间下沉位置；字形测量使用 `BoxHeightStyle.max` 按整行高度分组，避免中文回退字体与数字的下沿不同，漏算同一行末尾数字宽度。空间不足、多段文字或双向内容时才将时间放到正文下面。实际 SDK 消息入口和混合字形回归见 `test/widgets/chat/chat_default_bubble_metadata_test.dart`、`test/widgets/chat/chat_mixed_metrics_metadata_test.dart`。

验证入口：`test/chat_bubble_layout_test.dart`、`test/chat_message_menu_test.dart`、`test/chat_header_test.dart`、`test/fund_message_test.dart`、`test/chat_listview_loading_test.dart`。页面生命周期由已有 `test/chat_entry_performance_test.dart` 覆盖。
