# 媒体附件

`ChatMediaController` 持有附件选择锁和待发送附件，负责相册、相机、文件、位置与音频文件选择、留置媒体及 SDK 消息构造。真实发送由注入的发送能力执行，语音转文字由语音模块执行。

`ChatPictureGallery` 根据消息快照异步检查本地文件并构造公共浏览器数据。原生选择、压缩、SDK 创建和音频时长检查完成后都核对会话生命周期；关闭释放待发送列表，延迟操作不再提交旧会话内容。

媒体预览在异步文件检查前冻结 SDK 消息内容与顺序，`messageAt(index)` 与每个实际 `MediaSource` 一一对应。跳过无媒体文件的消息不会造成索引错位；无消息 ID、越界或映射缺失返回 `null`，不会回退到最初点击的消息。浏览器数据保持固定，转发/删除先按该索引的 ID 核对当前消息，再使用当前有效 DTO，避免旧的转发和过期元数据。

`ChatMediaMessageLocator` 是聊天内预览的定位适配器。公共浏览器关闭预览后调用 `onViewInChat(index)`；应用继续使用原 `ChatLogic.jumpToDateMessage` 完成历史窗口及滚动，不另开聊天或实现 SDK 分页。已加载消息直接定位；离开当前窗口的消息先以当前 `conversationID` 和单个 `clientMsgID` 调用 SDK `findMessageList`，确认仍存在后使用 SDK 返回的消息定位，防止删除的旧快照被历史窗口重新带入。无效/已删除、到期和失败显示现有应用 Toast；账号、令牌、聊天路由失效或定位时被新页面覆盖则静默丢弃。

映射及定位回归：`chat_picture_gallery_test.dart`、`chat_media_message_locator_test.dart`。覆盖跳页、过滤与深拷贝、当前消息元数据、失效/过期、未加载时精确 SDK 契约、重复定位和晚回包保护。此接线仅用于当前聊天媒体入口，历史搜索和存储媒体入口仍保持原有行为。

测试：`test/pages/chat/media/`。公共图片组件测试仍在应用的公共组件测试中。

`widgets/chat_video_thumbnail.dart` 是原聊天消息行中的缩略图组件，现由聊天
与会话长按预览共同复用。异步检查本地文件，缺失时使用远端 snapshot，
保留路径更新、晚回包保护与限制解码尺寸；显示缩略图不创建视频播放器。
