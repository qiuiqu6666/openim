# 聊天公共组件

普通文字、@消息和引用正文的 Markdown 显示归属 [Markdown 气泡](markdown/README.md)，保留原消息及复制源文本，复用现有链接与提及回调。带实体的格式化消息及应用自定义文字渲染保留各自路径。

文件气泡的文件名使用单行省略，长名称不换行增高。`ChatFileMessageView` 保留原始文件名用于下载和打开；仅 Text 展示截断，文件大小、加载/重试与点击打开继续走现有流程。既有附件布局回归包含亮暗、收发、单聊/群聊以及窄屏放大字体。

2026-10-05 调整已核对 99chat `third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKitMessageItem/tim_uikit_file_card.dart` 的单行文件名规则。本轮复用现有 Text、Expanded 和气泡约束，附件与气泡回归 10 项通过，静态分析无问题，Android debug APK 构建成功；未进行真机外观验收或安装部署。

聊天输入栏的加号展开面板对齐 99chat 的生产移动端更多面板，复用 `ChatToolBox` 的现有功能回调；独立界面模块在 `toolbox/`，包含布局、原始图标、主题与展开槽位。四列八项分页、群聊差异及安全区所有权见 [更多面板维护说明](toolbox/README.md)。输入、表情和语音继续互斥切换，草稿仍由外部控制器持有。

`ChatBubble` 的对方气泡底色独立于聊天背景：浅色为白色并加 0.5px、8% 黑色细边线，深色为 #1B1D22。对应 99chat 的 `DefTheme` 和 `MessageBubbleTextColor.othersBubbleBorder`。颜色与边线集中在 `ChatBubbleTokens`，默认底色读取当前 Theme，已有自定义底色仍优先。图片、贴纸与独立红包/转账卡片走原有展示分支；本调整不改变消息状态、时间或回执逻辑。

聊天默认背景与输入栏对齐 99chat 的生产 `DefTheme` 和 TUIKit 移动端 `TIMUIKitTextFieldLayoutNarrow`，不使用演示页的 `ChatInputBar`。颜色和几何集中在 `ChatComposerTokens`，主题解析在 `chat_composer_palette.dart`：浅色背景 #F4F5F7、白色底栏、#F1F3F5 输入填充；深色背景与底栏 #101114、输入填充 #1B1D22。输入框无边线、8px 圆角；底栏左右 16px、上下 5px，26px 原版 SVG 图标，图标与输入框之间 10px。字体 16px、行高 1.3，输入仍随多行与系统文字缩放增高。

`ChatInputBox` 保留外部输入/焦点控制器、草稿所有权、发送回调、语音、表情和附件逻辑；`ChatPage` 只更换默认底色，`WaterMarkBgView` 的用户自定义背景仍优先显示。回归覆盖 `test/widgets/chat/chat_composer_99chat_test.dart`、原输入与系统栏测试。

输入填充由 `ChatTextField` 的可选 InputDecoration 自身绘制，采用参考的 filled OutlineInputBorder（无边线、圆角8）；不要用外层灰色 Container 加 InputBorder.none 模拟，否则 Material3 的文字间距会少4px。输入文字使用非继承的常规字重和系统字体，避免带入正文的字距。按钮槽位和点击反馈复用原SVG及 InkWell，光标/选区主题只作用于输入行。IME 发送保留焦点并委托现有发送回调，纯空白不提交。独立参考渲染回归位于 `test/widgets/chat/chat_composer_reference_render_test.dart`，在统一环境内比较32种状态的实际尺寸及像素。

点击语音图标时输入栏保留 36px 空灰框，下方显示 248px 加底部安全区的录音面板；点击空框切回输入，原草稿和光标保留。语音区域按新的简洁 iPhone 风格设计：80px 平蓝麦克风、固定主控件位置、时长、真实音量历史，以及标注取消/发送/转文字的操作区。视觉参数集中在 `ChatVoiceTokens`，`voice/` 的 palette、布局、波形和视图只负责显示与命中位置。`HoldToRecordButton(expandedPanel: true)` 复用本地 `VoiceRecorderWidget` 的录音、权限、时长和文件处理；默认 compact 调用保持兼容。引用和定向消息预览独立于 `chat_composer_context_preview.dart`。

录音按下立即开始，最后松手位置决定取消、发送或转文字；PointerCancel、切换面板、禁用和离开页面取消录音。有效手指之外的取消事件不干扰录音，原 60 秒上限保留，触顶时冻结当前取消/转文字意图。原生启动完成前的松手会丢弃迟到文件；准备超时后只等待后台清理，不允许重叠启动。原生停止后先收起浮层，再交给原 OpenIM 发送或转文字预览。相关回归位于 `chat_voice_panel_test.dart`、`chat_voice_gesture_test.dart` 和本地插件的 `voice_recorder_controller_test.dart`。

只有麦克风按钮区域接受开始录音；空白处不会开启麦克风。录音期间每 100ms 采集原生归一化振幅，保留最近 24 个样本，没有正弦或随机波形。准备中显示现有加载指示器，错误通过原 Toast 和面板内说明呈现，重试清除错误。路由被覆盖和应用退后台也取消未发送录音。原生 stop 清理失败时等待释放该实例，释放完成后才允许下次重建，已交付业务层的音频不参与 discard；绕过当前依赖未等待原生结果的 cancel 通道。

`ChatListView` 保持旧调用兼容；消息阅读视口由 `chat_list_viewport.dart` 独立维护，不依赖应用页面、SDK 或未读计数状态。

- `messageIDs`：与 `itemBuilder` 一致的最新到最旧 ID 快照。传新快照，不能原地修改；空 ID 仍占据行位置，但不参与可读回调。
- `onViewportChanged(readIDs, distanceFromLatest)`：每帧最多测量一次当前挂载行。普通行整体进入视口、超长行末端进入视口时返回 ID；页面覆盖或应用不在前台时停止确认阅读。距离为 `pixels - minScrollExtent`，调用者先更新距离，再根据 ID 更新自己的计数。
- 滚动到最新使用 `controller.position.minScrollExtent`，不能假设最低位置恒为零。省略 controller 时由组件创建并释放内部 controller；外部 controller 不由组件释放。

懒加载的变高消息会精化最小滚动范围。普通 controller listener 的瞬时距离为零并不能确认到达真实最新消息；业务计数只能在本组件完成布局后的 `onViewportChanged` 中结算，或在用户明确要求返回最新端时结算。

历史浏览采用稳定的双 sliver 中心，新增消息在中心另一侧增长，保持变高消息与突发到达时原阅读位置；历史分页追加在历史一侧。删除、重排或可见行异步变高时，以仍然存在的可见消息恢复位置；纯新增和历史分页不做上一帧位置恢复，避免抵消同帧手势。

明确程序跳到最新端或原来停在最新端的数据更新，会把最新行设为新的中心，避免为到达大量变高消息的末端而遍历整个新增段。自然拖动和惯性滚动不按估算边界重设中心。短列表在同一布局阶段保持原有顶部对齐，不使用不支持 center 的 shrinkWrap。

`chat_listview.dart` 暂时保留原通用加载组件与兼容调用分支，超过 500 行主要源于这些既有入口；新的阅读测量、稳定中心与渲染代理已归入独立文件。不要把业务未读规则或 SDK 回执加入公共组件。

回归位于 `test/chat_listview_new_messages_test.dart` 与 `test/chat_listview_loading_test.dart`，覆盖不同高度、1000 条突发、同帧手势、删除相邻锚点、分页、短列表、尺寸变化、控制器所有权及路由/应用生命周期。

`WaterMark` 将新消息及回到底部提示放在消息视口右侧，右边距为零，位于输入框上方。`NewMessageIndicator` 负责蓝底白字、左侧圆角和右侧直边的样式，保留至少 48dp 的点击范围；颜色和尺寸集中在 `ChatScrollHintTokens`。计数和阅读规则仍由调用方提供。相关组件回归位于 `test/chat_new_message_indicator_test.dart`，覆盖贴边位置、点击、主题、放大文字及本地化。

提示的外层手势区域扩大点击范围，内层蓝色表面拥有独立且按形状裁剪的 Material，因此点击波纹仅绘制在蓝色表面内；外部阴影独立绘制。透明点击边距不显示灰色波纹，内外手势通过 Flutter 手势竞争只触发一次回调。按压像素回归同时确认内部有反馈、阴影和外围像素不变。

`ChatMessageContentAnchor` 标记消息内容的实际边界，不持有选择状态。普通气泡和叠加回执的媒体标记整个气泡；外置回执的媒体及独立卡片只标记内容。锚点在自己的布局阶段保存边界，应用多选布局在同帧读取，避免跨层读取 RenderBox.size 的调试限制及首帧位置跳动。该标记始终保留在消息树中，进入/退出多选不会重建媒体消息状态。
