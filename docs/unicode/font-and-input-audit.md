# 字体与输入显示审计

本文记录 2026-10-08 对当前工作区字体、输入显示和行高的源码检查及修复方案。
测试、静态检查、构建和原生工具执行结果由主任务另行补充；本文不预先声明运行通过。

## 实际检查范围与结论

检查了应用 `lib/`、公共包 `openim_common/lib/`、`openim_live/lib/`、
本地插件 `local_plugin/`、各包 `pubspec.yaml`、已生成的 APK 字体清单，以及相关测试。
搜索入口包括 `fontFamily`、`fontFamilyFallback`、`FontLoader`、`ThemeData`、
`TextTheme`、`DefaultTextStyle`、`TextStyle`、`StrutStyle`、`forceStrutHeight`、
`TextHeightBehavior`、`TextField`、`EditableText`、`RichText` 和 `TextSpan`。
对搜索结果按生产正文、图标字体、测试预览字体、协议标识和固定系统文案分别核对。

发现以下事实：

- 应用及公共包没有注册 `NotoSansSCVariable` 或其他正文自定义字体资源；
  当前源码资源中没有对应 TTF/OTF/TTC 文件。已生成的
  `build/app/intermediates/flutter/debug/flutter_assets/FontManifest.json`
  只有 MaterialIcons、FontAwesome、CupertinoIcons、EvaIcons 等图标字体。
  测试中加载的 Windows/CJK 预览字体不属于产品的字体配置。
- [应用主题](../../lib/app.dart) 的 Material 主题、Cupertino 文字样式都未硬设正文
  `fontFamily`。Android/iOS 聊天输入样式原本也没有硬设字体家族。
  **没有证据表明 Noto 字体阻止了此次系统 Emoji fallback**，不能把用户提出的
  假设字体当成已证明的根因。
- 输入和钱包各自维护了桌面 CJK 字体选择，Web 分支还引用没有在本项目注册的
  `NotoSansSC`。这造成字体策略分散及对未提供字体的依赖，但不代表所有原生
  Emoji 问题都由该分支造成。
- 用户资料签名同时采用固定高度和 `forceStrutHeight: true`，会禁止字体 run
  根据 fallback 度量扩展行高。联系卡公开账号行也强制使用 strut 高度。
  后者字段虽然名为 `userID`，实际调用传入的是显示用公开账号，不能误当作 SDK
  路由标识；本次解除其强制行高，但不改变账号协议和后端校验规则。
- 联系卡昵称显示调用 `String.trim()`，会把以空白为基字符的 combining cluster
  从中间剥开。该处改用共享的 `graphemeTrim`；不改 SDK 中保存的昵称值。

本次显示系统的另一项已确认问题是公共显示工具在 UTF-16 单元之间插入 U+200B。
这会打断 surrogate pair、VS、ZWJ 和 combining sequence。该问题属于字符串显示
处理，详见主任务对应审计与修改；不是通过换字体解决。

## 中文外观与字体 fallback 方案

新增 [PlatformTextFonts](../../openim_common/lib/src/res/typography/platform_text_fonts.dart)，
集中维护输入和钱包原有的平台字体选择，不创建另一套文本控件。

| 平台 | 正文字体偏好 | 显式 fallback | 后续解析 |
| --- | --- | --- | --- |
| Android/iOS/Fuchsia | 不硬设 `fontFamily` | 不硬设列表 | Flutter 与系统字体解析 |
| Windows | Microsoft YaHei UI | Microsoft YaHei、Segoe UI | 系统 fallback |
| macOS | PingFang SC | PingFang TC、Hiragino Sans GB | 系统 fallback |
| Linux | Noto Sans CJK SC | Noto Sans CJK TC、WenQuanYi Micro Hei | 系统 fallback |
| Web | 使用实际平台的同一策略 | 使用实际平台的同一策略 | 浏览器/Flutter 可用字体 |

Android/iOS 保留系统中文、英文与 Emoji 字体选择；没有把整个应用改成另一个字体。
输入样式继续使用 16 字号、400 字重、1.3 行高及原有日夜主题颜色，
桌面已有中文字体偏好也保持。应用主题的字号、字重、导航和其他页面布局没有为 Emoji
统一替换。Web 不再依赖此项目未提供的 `NotoSansSC` 字体资源。

Flutter 的解析顺序是主字体、显式 fallback 列表、系统 fallback。
缺少显式 fallback 不等于关闭系统 fallback。主字体为 `null` 时，显式列表的
第一项会成为首选字体，因此没有给原生正文强塞一个仅用于 Emoji 的首选列表。
不逐个识别 Emoji，不根据当前样本选择字体，也不增加、删除 FE0E/FE0F/ZWJ。
Markdown 和 AI 代码块保留原来的 `monospace` 意图，缺字仍通过平台 fallback 解析。
其他显式字体位置来自现有主题，未发现生产正文强制采用图标字体。

官方依据：
[Flutter TextStyle 字体解析](https://api.flutter.dev/flutter/painting/TextStyle-class.html)、
[fontFamilyFallback](https://api.flutter.dev/flutter/painting/TextStyle/fontFamilyFallback.html)。

## 输入框与 UTF-16 编辑边界

[ChatTextField](../../openim_common/lib/src/widgets/chat/chat_text_field.dart)
复用 `extended_text_field`。当前解析版本 16.0.2 的 `ExtendedEditableText` 和
`ExtendedRenderEditable` 是该包维护的 Flutter 编辑实现副本，并不是 Flutter
`EditableText` / `RenderEditable` 的子类。检查及诊断工具必须识别它们的实际类型，
不能仅查找 Flutter 的类型后宣称输入已验证。

系统输入法的 composing 由现有编辑控件处理；字体策略不会重写 controller 内容。
显式面板编辑通过
[chat_text_editing.dart](../../openim_common/lib/src/widgets/chat/editing/chat_text_editing.dart)
使用共享 grapheme 边界，避免在复杂 Emoji 中插入或只删一部分。
Flutter 的 selection/composing 和 SDK 实体 offsets 继续使用 UTF-16 单位，
不把 grapheme 数量误写进这些协议偏移。

[聊天输入控制器](../../lib/pages/chat/composer/chat_composer_controller.dart)
保留未提交输入及草稿的原始文本。IME composing 期间不主动触发替换；
`@` 元数据清理延后到提交输入，避免取消临时 composing 后丢失被引用用户；
异步成员选择回来后重新检查输入 revision、会话及 composing 状态。
这些是输入流程保护，并不转换、标准化或图片化系统 Emoji。

## 用户签名与联系卡行高修复

[资料签名](../../lib/pages/contacts/user_profile_panel/widgets/user_profile_identity.dart)
由固定高度改为 `ConstrainedBox(minHeight: ...)`，继续保留原有两行签名的最小占位，
字号 14、行高 1.3、最多两行和日夜颜色不变。保留最低 strut，解除强制高度，
允许 fallback 字体的 run 度量扩展。短签名、异步加载前后的占位设计继续保留。

[联系卡](../../openim_common/lib/src/widgets/contact_card.dart) 公开账号行保留原有
`11.sp` 字号和 1.25 行高，解除 `forceStrutHeight`。账号行使用同样式的空 Text
保留最低占位，并排除其语义；实际账号 Text 仍按自然字体度量布局。空账号与普通
ASCII 账号的字体度量可能不同，该占位避免异步账号加载后卡片缩高，同时允许高
fallback 字形超出最低占位。两者都使用 Flutter 原有样式继承、主题及文字缩放，
没有另写字体测量或按 Emoji 分支处理。卡片没有固定正文高度，内部 Column 和
外层 ClipRRect 按内容自然高度布局，回执继续在卡片底栏。
这只增强公开账号的客户端显示容纳能力，不声称后端支持注册 Unicode 账号。

复扫后，剩余 `forceStrutHeight` 只出现在
[TitleBar](../../openim_common/lib/src/widgets/title_bar.dart) 的固定 presence/typing
文案行及其对应测量。当前调用来自应用生成的在线、离线、输入状态，
不是用户可编辑昵称或消息内容，故保留原有状态行几何。若以后允许自定义 Unicode
状态文案，需要重新检查该约束。

解除强制 strut 不等于证明任意字体的墨迹边界绝不裁剪；具体 glyph 和复杂组合
仍需原生截图检查。本次没有根据假设全局增加字号或行距。
官方依据：[Flutter StrutStyle](https://api.flutter.dev/flutter/painting/StrutStyle-class.html)。

## 本子审计新增与修改文件

| 文件 | 内容 |
| --- | --- |
| `openim_common/lib/src/res/typography/platform_text_fonts.dart`（新增） | 共享平台正文家族与 fallback 偏好；移动端保留系统解析 |
| `openim_common/lib/src/res/typography/README.md`（新增） | 字体策略、模块边界、未来 Unicode 和验收限制 |
| `openim_common/lib/openim_common.dart` | 导出字体策略，供应用复用公共入口 |
| `openim_common/lib/src/widgets/chat/chat_composer_palette.dart` | 删除分散字体分支，复用共享策略；保留输入度量与颜色 |
| `lib/pages/wallet/widgets/wallet_99chat_tokens.dart` | 钱包字体接口复用共享策略；移除未注册 Web 字体依赖 |
| `lib/pages/contacts/user_profile_panel/widgets/user_profile_identity.dart` | 签名改最低占位高度，允许自然字体行高 |
| `openim_common/lib/src/widgets/contact_card.dart` | 公开账号解除强制 strut，保持字号；保留空账号最低占位并允许自然增长 |
| `openim_common/lib/src/widgets/chat/contact_card/contact_card_identity_view.dart` | 昵称按完整 cluster 去外层空白，保存的 SDK 字符串不变 |
| `test/theme/typography/platform_text_fonts_test.dart`（新增） | 各平台、日夜主题的输入/钱包家族一致性与原有字体度量 |
| `test/pages/contacts/user_profile_panel/identity/user_profile_unicode_test.dart`（新增） | Android/iOS 主题配置、日夜、双倍文字、共享结构样本的渲染数据和布局 |
| `test/pages/chat/messages/contact_card/contact_card_message_test.dart` | 增加空白 combining 昵称、Unicode 公开账号自然布局及日夜/双倍文字下账号加载高度稳定回归 |
| `tool/unicode/unicode_native_probe.dart`（新增） | 不启动 SDK 的原生文本渲染对照入口 |
| `tool/unicode/unicode_samples.dart`（新增） | 工具引用共享测试 fixture 的入口；不是生产 Emoji 支持列表 |
| `tool/unicode/README.md`（新增） | 独立应用 ID、运行步骤、日志和截图解释 |
| `docs/unicode/font-and-input-audit.md`（新增） | 本次源码审计和验收边界 |

输入编辑、grapheme 工具、其他字符串显示、传输及生命周期修复文件由主任务汇总，
不以本表代替完整变更清单。

## 原生 probe 的证明范围

[诊断工具](../../tool/unicode/unicode_native_probe.dart) 使用共享的 Unicode 结构 fixture，
对照实际 ChatTextField、系统 Text、公共 TextView、MatchTextView、Markdown，
可切换样本和日夜主题。它不初始化 SDK、不登录、不真实发消息；按说明在独立
application ID 运行，以避免覆盖已登录产品应用。

工具遍历实际 `RenderObjectElement`，读取 `ExtendedRenderEditable`（当前输入实现）、
Flutter `RenderEditable`（如使用）以及 `RenderParagraph` 文本，按 UTF-16 单元
比较原始 controller 值、渲染内容和 JSON 往返值。Markdown 的 display-only
`A/raw/Z` wrapper 避免空白 combining 基字符触发 Markdown 边缘空白语义；
原始输入和 fixture 未被修改。

`UNICODE_NATIVE_PROBE` 日志中的一致性结果只能证明本次输入的原始序列进入了
渲染树，不能单独证明操作系统具有相应 glyph、ZWJ 已组合成单个图案、真实键盘
或复制粘贴正常。`UNICODE_NATIVE_PROBE_ERROR` 用于记录实际布局/渲染错误。
原生截图需人工核对缺字框、独立 selector、组合图形拆开、超出行高的裁剪等情况。
系统 Text 对照本身也缺字时，需区分系统字体覆盖和应用数据损坏。

## 平台差异、未来更新与未验证项

- Android/iOS 使用各自系统的字体和 Emoji 美术；不会要求两平台外观一致。
  当前及未来系统支持的序列不会因业务 Emoji 白名单而被拒绝，也不需要每新增一个
  Emoji 就修改业务映射。
- 系统没有提供的 glyph 不能靠保留字符串或字体 fallback 凭空生成。
  新增 Emoji 字形取决于系统字体；新增 Unicode segmentation/shaping 规则还依赖
  `characters`、Flutter 和 engine 的 Unicode 数据版本，可能需要正常运行时升级。
- 桌面及 Web 的字体可用性也取决于实际环境；字体策略不是内置完整 Unicode 字库。
- Android **尚未真机验证**；iOS **尚未真机验证**。模拟器结果、截图、OS/Flutter
  版本及实际输入/复制粘贴操作由主任务执行记录补充，不能由源码检查推测通过。
- 本子审计不证明部署中的服务端、数据库字符集或跨设备真实消息传输已经通过。
  原生 probe 的 JSON 和渲染检查不能替代这些链路验证。
- 最终执行结果见 [主审计](audit-and-verification.md) 与
  [原生证据](native-evidence/README.md)：相关回归 1602 通过、16 条件导出跳过，
  Android 主应用构建成功。模拟器 42 组原文检查通过，新码点仍受系统缺字限制。
  全仓 analyze 未通过，9 个 error 位于既有插件示例，另有 31 warning、461 info。
