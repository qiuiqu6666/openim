# 聊天默认背景与输入栏对齐 99chat

2026-10-04，对照本地 `reference-99chat` 的 `d7c3c65` 版本。

## 对照来源与实现

- 生产颜色：`lib/utils/theme.dart` 的 `DefTheme`；默认聊天浅色背景 #F4F5F7，深色 #101114。底栏浅色白色，深色 #101114；输入填充分别为 #F1F3F5 / #1B1D22。
- 移动端布局：`third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKitTextField/tim_uikit_text_field_layout/narrow.dart`、`ui/utils/chat_input_bar_metrics.dart`。未使用演示页的 `ChatInputBar`。
- 输入框无边线、8px 圆角，16px 字体、1.3 行高，内部左右 12px、上下 8px。底栏左右 16px、上下 5px，单行输入最低 36px；多行和系统文字缩放仍可增高。
- 图标复用 99chat 原版 `voice.svg`、`face.svg`、`add.svg`、`keyboard.svg`，26px 显示尺寸与 10px 间隔。文字输入后按生产样式显示蓝色圆角“发送”按钮。
- 扩展现有 `ChatInputBox`、`ChatTextField` 和共享颜色解析，设计值集中在 `ChatComposerTokens`；未新增输入状态管理或发送组件。SVG 依赖使用应用已有的 flutter_svg 版本。
- `ChatPage` 只修改默认背景；现有用户自定义图片/纯色背景继续由 `WaterMarkBgView` 优先显示。消息、草稿、SDK 发送、提及、表情、语音回调和滚动所有权保持现有模块归属。
- 聊天专用 padding / hintStyle 通过 `ChatTextField` 的可选参数传入，富文本编辑框继续使用原默认值。

## 验证

- 最终统一运行输入、图标打包、表情、系统栏、安全区、提及/草稿控制器、自定义背景有效性及真实聊天进入/键盘/滚动回归，加上下面两项页面渲染：75 项全部通过。
- 真实 `ChatPage` 配合测试 SDK：日夜两项渲染验证通过，覆盖默认背景、自定义背景覆盖、草稿保留；生成并检查四张空白/输入状态截图。
- 针对修改文件的静态分析通过，无问题。
- Android debug APK 构建成功，并检查 APK 中四个原版 SVG 图标均存在且非空；交付路径为 `build/app/outputs/flutter-apk/app-chat-composer-99chat-debug.apk`。

预览：[浅色](previews/chat-composer-99chat-light.png)、[深色](previews/chat-composer-99chat-dark.png)、[浅色输入](previews/chat-composer-99chat-light-typing.png)、[深色输入](previews/chat-composer-99chat-dark-typing.png)。

本次验证使用实际 Flutter 页面和组件，SDK 数据及录音平台仅在预览中模拟；未执行真实消息发送或录音。尚未做 Android/iOS 真机逐像素对照或 iOS 构建。

重新构建时，顺带修复了并行改造产生的朋友圈封面空值编译错误：在已判断路径非空的分支传入非空值，未改动对应业务流程。

聊天 SDK 测试替身同步补齐新通知模块增加的 `onNotificationSessionReady` 空实现，以继续测试原 SDK 同步事件和历史合并断言；未跳过或放宽这些断言。

## 对方消息气泡辨识度修复

同日用户反馈对方气泡不明显，确认 `ChatBubble` 浅色默认填充仍为 #F4F5F7，与已对齐的聊天背景完全相同。对照 99chat `DefTheme` 和 `MessageBubbleTextColor.othersBubbleBorder`，现改为白色、0.5px / 8% 黑色边线；深色使用 #1B1D22。底色取当前 Theme 的亮度，已有显式背景色保持优先；发送方气泡样式保持既有值。

复用原 `ChatBubble`，颜色与边线归 `ChatBubbleTokens`，未改变消息链路或新增气泡组件。真实日夜 `ChatPage` 渲染、附件、红包/转账卡片、贴纸及时间回执布局共 42 项回归通过，修改文件静态分析无问题。日夜预览图片已更新。交付安装包为 `build/app/outputs/flutter-apk/app-chat-incoming-bubble-debug.apk`；未做真机验收。

## 输入行精确对齐

2026-10-04，继续对照同一 `d7c3c65` 版本的生产移动端输入行，核查空白、输入文字及多行状态。此次核查发现，先前将灰色填充放在外层 Container、内部使用 `InputBorder.none`，虽然 padding 数值相同，仍无法得到参考输入框的布局：Material3 的 `OutlineInputBorder` 默认 `gapPadding` 会在左右各增加 4px 输入间距。当前改为输入框自身 `filled: true`，使用无边线、8px 圆角的 `OutlineInputBorder`，与参考的装饰结构一致。

- 文字样式采用 `inherit: false`、常规 w400、alphabetic 基线、16px / 1.3 行高，避免继承 Material3 正文的额外字距。移动端使用系统字体；桌面按参考设置字体与回退字体。
- 左侧语音切换和表情按钮使用 36px 高槽位、Center、InkWell 及原版 26px SVG；发送按钮恢复参考的 36px 槽位 / 30px 按钮结构。输入行左右 SafeArea 关闭，内容 Column 使用 `mainAxisSize: MainAxisSize.min`。
- 输入行局部复用 `TextSelectionTheme`：日间光标使用 accent、夜间使用白色，选区为 accent 的 22% 透明度，选取手柄随光标颜色；没有改动其他页面的全局主题。
- IME 发送沿用父组件的原发送回调并保留输入焦点；纯空白输入不提交。控制器、草稿及发送结果仍由既有模块持有，未引入第二套输入状态或 SDK 数据链路。
- 继续扩展现有 `ChatInputBox`、`ChatTextField`、颜色解析与设计 token；没有新增生产输入组件。`chat_input_box.dart` 当前约 505 行，已检查职责，主要为原有输入状态、输入行和引用兼容子视图。本轮属于同一组件职责内的布局修正，没有追加独立业务流程。

独立对照夹具位于 [composer_99chat_reference.dart](../test/fixtures/chat/composer_99chat_reference.dart)，按上述生产源码转写，未引用当前 `ChatInputBox` 的布局、颜色解析或 token。对应 [chat_composer_reference_render_test.dart](../test/widgets/chat/chat_composer_reference_render_test.dart) 比较两侧渲染尺寸及 RGBA 像素，覆盖 32 种组合：日夜主题 × 375/320px 宽度 × 34/0px 底部安全区 × 空白/空格/单行/多行文字。最终 32 组尺寸与像素对比全部一致；75 项相关回归、两项真实 ChatPage 预览及一项对比图渲染全部通过，修改文件静态分析无问题。Android debug APK 构建成功，交付路径 `build/app/outputs/flutter-apk/app-chat-composer-exact-debug.apk`。

并排对比：[参考 / 当前输入行](previews/chat-composer-reference-comparison.png)。左侧为独立的生产源码转写夹具，右侧为当前组件，双方使用相同中文字体和渲染尺寸。测试使用已有 `extended_text_field` 版本，作为显式开发依赖登记，未更换运行时版本。

对照边界：像素比较在同一 Flutter 测试渲染环境内完成，参考侧为独立源码转写夹具，并非 Android/iOS 真机上的 99chat 截图。中文页面预览使用测试中加载的 CJK 字体替代原生系统字体，仅用于稳定显示中文，不改变生产字体配置。本轮精确对齐范围为文字输入行；语音模式继续复用当前录音组件，尚未将整个语音面板迁移为 99chat 的实现。Android/iOS 真机字体、输入法及录音面板仍需单独验收。

## 禁言输入栏（2026-10-05）

按用户提供的“无法在已退出的群聊中发送消息”截图，将禁言状态也显示为居中的警告图标与文字条。对照 99chat `TIMUIKitTextField/tim_uikit_forbidden_input_bar.dart` 的禁言替换行为，视觉使用当前已有 `ChatDisableInputBox`；未新增重复组件。

- 禁言时隐藏输入框、语音、表情、加号与发送按钮，提示“你已被禁言”；已退出群聊仍显示原有提示，优先级高于禁言。
- 进入禁言状态收起键盘和扩展面板；保留父组件持有的草稿与光标，解除禁言后恢复输入栏。已隐藏面板的晚到输入/发送回调也检查禁用状态。
- 复用现有警告资源、文字样式、日夜主题底色和安全区。长提示允许换行，窄屏和大字号不会溢出；引用或定向消息隐藏时不会把安全区染成原引用背景。
- 禁言数据与管理员权限继续由现有 OpenIM 群状态模块提供，本次没有修改权限规则或 SDK 发送链路。

共 44 项验证通过：现有输入栏/安全区 19 项、录音手势 16 项、新增禁言切换与窄屏大字号 7 项、真实 ChatPage 日夜状态切换预览 2 项；修改文件和新增测试静态分析通过。预览使用模拟 SDK 群状态通知驱动实际页面，验证全员禁言与解除后草稿和光标恢复，未向真实聊天发送消息。

预览：[日间](previews/chat-muted-light.png)、[夜间](previews/chat-muted-dark.png)。Android debug 构建成功，安装包 `build/app/outputs/flutter-apk/app-chat-muted-debug.apk`。尚未执行 Android/iPhone 真机禁言推送、键盘动画验证或 iOS 构建。
