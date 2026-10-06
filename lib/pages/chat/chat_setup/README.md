# 单聊设置与消息保留

`chat_setup_view.dart` 沿用 `ChatSetupBinding` 和现有导航入口，负责组合设置界面。成员卡片在 `widgets/`，尺寸在 `chat_setup_tokens.dart`；消息保留的专用行组件在 `message_retention/widgets/`。既有 `message_retention_page.dart` 保留入口，避免同时维护两套页面。

界面复用设置模块的 `SettingsScaffold`、`SettingsGroup`、`SettingsCell`、确认框和选择弹层，颜色与圆角使用 `AppTokens`。参考实际 99chat 的 `lib/src/pages/c2c_chat_settings_page.dart` 分组次序及成员操作，消息保留页沿用当前产品设置组件，未发现参考项目中对应的消息保留页面。

当前单聊页面按用户最新参考图及补充要求依次显示成员、消息保留设置、查找内容、置顶 / 消息免打扰、背景、清空、投诉。普通行不显示左侧图标，清空使用普通文字颜色；添加成员是灰色圆形描边，成员标签使用次级文字颜色。消息保留入口采用相同圆角行，传递当前会话并打开原有页面及 SDK 实现。

置顶与免打扰两行直接复用公共包 `AppSwitch`，与好友权限、添加好友隐私及群管理的全局开关一致；Android / iOS 都采用相同圆形滑块、灰色关闭轨道与品牌蓝开启轨道。保存或清空期间仍禁用两个开关，继续使用原 `ChatSetupLogic` 和 SDK 状态，不新增开关组件或状态服务。

`ChatSetupLogic` 继续拥有原来的会话、好友资料订阅，关闭时取消。首次读取保留传入的会话快照；迟到结果不能覆盖更新后的资料或设置。好友资料刷新不会丢失待完成的开关保存，但较新的会话设置事件仍优先保留。置顶、免打扰和清空过程中锁定重复操作，清空仍需确认且只有 SDK 成功后才更新聊天界面。

`MessageRetentionPage` 使用 OpenIM SDK 的 `getMultipleConversation` / `setConversation`，展示读取到的当前值，保存后重新读取。关闭时只提交相应布尔字段，不提交无关时长。加载和保存失败保留原值并提供重试，已保存的非预设时长也能展示和选择。异步回调同时核对页面生命周期、当前用户以及 IM / Chat 凭证，不新增全局订阅或服务接口。

当前服务没有单聊投诉提交接口。`reportConversation` 显示对方账号及人工客服确认，确认后复用 `showCustomerServiceSheet`，取消不进行后续操作；不自动发送聊天资料、不伪造投诉成功，也不调用参考项目中未接入的接口。重复入口、账号变化和页面关闭由当前控制器保护。

对应测试位于 `test/pages/chat/chat_setup/`，包含真实 SDK 方法通道的延迟、错误与账号变更场景，以及 320px、两倍字体的亮暗布局检查。`CHAT_SETUP_PREVIEW_DIR` 可导出真实页面 Widget 的测试截图；预览资料仅存在于测试中。
