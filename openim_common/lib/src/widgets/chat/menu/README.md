# 消息长按菜单

`ChatMessageMenu` 仅负责消息菜单的展示。`ChatItemContainer` 传入当前消息允许的 `PopMenuInfo` 列表，应用的 `ChatMessageTile` 提供语义 ID；操作权限、私密消息限制和 SDK 回调仍由原业务逻辑维护。

对照本地 99chat 的 `tim_uikit_mobile_telegram_message_menu.dart`、`tim_uikit_chat_message_tooltip.dart` 和 `message_action_reference_icon.dart`。使用实心深色面板、五列图标格、最多两行、超过十项横向滚动、消息侧对齐、小三角、220ms 淡入/缩放和约 32% 遮罩。当前参考应用没有启用快速表情条，因此本菜单保留当前已有操作。图标与文字样式来自同一参考实现（Apache-2.0），许可记录见应用的 `docs/third-party-assets.md`。

固定样式集中在 `chat_message_menu_tokens.dart`，矢量图标归 `chat_message_menu_icon.dart`，网格归 `chat_message_menu_panel.dart`，定位归 `chat_message_menu_layout.dart`。放大文字时增加格子高度，屏幕空间不足时菜单内部滚动；定位避开安全区与当前键盘。

与原通用菜单共用 `CustomPopupMenuController` 和 `PopMenuInfo`。`id` 为可选字段，旧调用可继续使用文字/图标/回调。新增独立展示组件是因为消息需要横向图标格和消息锚点定位；导航及其他通用 `PopButton` 保留各自展示方式。

菜单挂在根导航的临时弹出路由。点击操作先关闭菜单再执行原回调；点击空白、系统返回、进入后台、消息卸载或被其他路由覆盖时关闭。菜单不请求输入焦点，保留键盘状态。组件拥有内部创建的控制器，调用方提供的控制器不由组件释放；控制器已释放时关闭操作安全退出。

测试归应用 `test/pages/chat/messages/chat_message_menu_test.dart`，覆盖亮暗主题、真实消息锚点、图标及动作布局、回调顺序、不点透、返回和路由生命周期、键盘与大字体、横向滚动。

2026-10-04：新菜单 20 项、既有长按与消息布局 6 项、语音转文字菜单 4 项均通过；新菜单、接线及测试检查无问题，Android debug 构建通过。旧通用弹窗仍保留原有的 12 条分析提示。本轮还补齐了收藏搜索 `String.characters` 扩展的缺失导入以恢复构建，其两项既有字符/输入法测试通过。
