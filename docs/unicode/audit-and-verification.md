# Unicode / Emoji 修复与验收记录

日期：2026-10-08。范围为当前 Flutter IM 工作区，包含应用 `lib/`、
`openim_common/lib/`、`openim_live/lib/`、本地插件、锁定 SDK 和相关测试。
只读对照 `E:/openim/reference-99chat`。本轮保留既有钱包、权限、撤回、
联系人选择和配置目录等未提交改动；没有把整个工作区的差异都归为 Unicode 修复。

客户端的 Unicode 原文保留、可见字数、显示分段和显式编辑已完成修复。
最终相关回归 **1602 项通过、16 项跳过、0 项失败**，主应用 Android debug
构建成功。完整 `flutter analyze` **未通过**；部署数据库和物理设备仍未验收。

## 1. 根因

**输入框与编辑流程：** 面板删除按 UTF-16 长度退一个位置，复杂字符会被拆开；
面板插入及 @ 插入没有共同的完整字符边界处理。替换后相邻 regional indicators
还可能重新组成旗帜，原候选光标会进入新 cluster。发送/派生文本中的普通 trim
会改变空白基字符上的 combining sequence。IME composing 期间触发 @ 选择和
元数据清理，以及异步选择返回时未确认输入版本，也会干扰正在组合的文字。
标准软键盘由现有编辑控件处理，不能仅凭这些源码修复断言真实输入法已经验收。

**字体：** 当前应用没有注册 `NotoSansSCVariable` 正文字体，移动端主题及输入框
也没有硬设该家族；没有证据支持“Noto 阻止此次原生 Emoji fallback”的猜测。
可确认问题是输入/钱包的桌面字体策略分散、Web 引用未注册 Noto 字体，以及资料
签名和联系卡账号强制行高可能压住 fallback 字形。旧系统缺少新字形是另一项限制。

**Unicode 处理：** TextView 的 `replaceAll('', '\u200B')` 和匹配/Markdown 的
`split('').join('\u200B')` 在 UTF-16 单元间插入字符，会打断 surrogate pair、VS、
ZWJ、modifier、RI、tag 和 combining sequence。另有普通消息的 HTML 过滤、
伪 Emoji 占位表、substring 省略/搜索摘要、码点计数的可见字数校验，以及接收
资金备注错误套用发送限额。未调用的 `fixed63Length` 也已清除，但不能据此认定
它是运行中的输入异常根因。

## 2. 修改文件

完整逐文件清单分为三份，覆盖生产文件、测试、README 与诊断工具：

- [显示、搜索、字数与资料文本](display-and-limits-audit.md)
- [字体、行高与原生探针](font-and-input-audit.md)
- [创建、传输、通知、转写与存储边界](transport-audit.md)

本报告第 3 项补充共享工具、输入、面板及主任务测试文件；三份分项报告不是
“只列几个代表文件”的摘要。检查但无需改变的协议处理也在分项报告明确列出。

## 3. 每个文件修改内容

下表补齐主任务负责的文件。路径相对 `E:/openim/openim-flutter-demo`。
分项负责的其他每个文件与其具体修改见第 2 项的逐文件表。

| 文件 | 本轮内容 |
| --- | --- |
| `openim_common/lib/src/utils/text/unicode_text.dart` | 共享 grapheme 前后截取、裁边空白、单行摘要、UTF-16 边界及安全范围；匹配支持缓存边界。 |
| `openim_common/lib/src/utils/text/README.md` | 文本语义与协议偏移的使用边界。 |
| `openim_common/lib/src/widgets/chat/editing/chat_text_editing.dart` | 显式插入/删除完整 cluster；替换前后均对齐光标，不改系统 IME 原文。 |
| `openim_common/lib/src/widgets/chat/editing/README.md` | 面板、@、标准键盘与 composing 的职责。 |
| `openim_common/lib/openim_common.dart` | 导出共享文本、编辑和字体入口。 |
| `pubspec.yaml`、`openim_common/pubspec.yaml` | 直接声明 `characters ^1.4.1`。 |
| `pubspec.lock` | 当前解析仍为 1.4.1，调整直接依赖归属；未替换 SDK/原生协议。 |
| `openim_common/lib/src/widgets/chat/chat_input_box.dart` | 复用共享面板编辑；发送原文，仅用空白判断决定是否允许发送。 |
| `lib/pages/chat/composer/chat_composer_controller.dart` | 原文发送/草稿；安全 @ 插入；composing 提交后处理元数据，异步 picker 校验 revision、会话和 composing。 |
| `openim_common/lib/src/widgets/chat/chat_emoji_panel.dart` | 去除手写支持列表与平台过滤；收藏/最近项不经目录白名单校验；目录只用于浏览。 |
| `lib/pages/customer_service/customer_service_controller.dart` | 客服文本发送保留原文。 |
| `openim_common/lib/src/widgets/chat/location_picker/chat_location_picker.dart` | 用户位置描述原样返回。 |
| `lib/pages/conversation/folders/folder_name_dialog.dart` | 保留原有文件夹名称裁边政策，改为完整 cluster 安全处理。 |
| `lib/pages/chat/group/member_actions/chat_member_actions_controller.dart` | 成员菜单、@ 与专属红包显示名不拆空白基底组合字符；ID 协议不变。 |
| `test/support/unicode/unicode_samples.dart` | 21 类结构 fixture，仅测试/独立探针使用，生产代码不依赖。 |
| `test/utils/text/unicode_text_test.dart` | 截取、trim、摘要、高亮边界、插删原文和 RI 重新合并后的光标。 |
| `test/widgets/chat/editing/chat_unicode_input_test.dart` | 实际 Extended 输入组件、受控输入法、硬键盘删除、发送、未知目录收藏、Android/iOS 日夜配置。 |
| `test/pages/chat/composer/chat_composer_unicode_test.dart` | 原文草稿 JSON 恢复、普通/引用发送、@ 插入、IME 取消和异步选择失效。 |
| `test/folder_name_dialog_test.dart` | 复杂 cluster 字数及空白结合符保留。 |
| `test/pages/chat/group/member_actions/chat_member_actions_controller_test.dart` | 组合字符成员名完整保留。 |
| `test/widgets/chat/location_picker/chat_location_picker_page_test.dart` | 用户描述与首尾原文保留。 |

为运行当前既有相关测试，另修正了以下测试夹具，生产行为未因此放宽：

| 文件 | 修正 |
| --- | --- |
| `test/sdk_feature_completion_test.dart` | 按当前管理员/禁言行的按钮定位操作，保留权限断言。 |
| `test/nickname_edit_entry_test.dart` | 补当前 Mine 设置草稿依赖和昵称页面流程，用固定帧等待持续装饰动画。 |
| `test/pages/chat/messages/contact_card/contact_card_message_test.dart` | 补资料导航守卫的受控 SDK 查询和等待，保留 SDK ID、邀请码与切换账号断言；另有字体分项 Unicode 布局测试。 |
| `test/pages/global_search/global_search_draft_test.dart` | 按当前字幕组件定位结果，兼容 OfficialAccountNameLabel 标题，保留草稿及 Unicode 断言。 |
| `test/profile_nickname_save_test.dart` | 对齐当前业务错误映射，并断言不展示原始服务器堆栈；失败保留输入和重试断言仍在。 |
| `test/pages/chat/history_search/chat_history_assets_test.dart` | 用 Flutter 编码器生成有效 PNG 夹具，避免旧图片字节解码异常；不改产品图片逻辑。 |
| `artifacts/create_group_two_rows_preview.dart` | 预览 override 对齐现有 `Future<void>` 创建接口；该产物目录已在既有忽略规则内。 |

审计新增 `docs/unicode/` 三份分项、本文、验证记录和原生证据；
`tool/unicode/` 的探针、fixture 入口与 README 逐项说明见字体报告。

## 4. Unicode 兼容方案

用户输入的 String 不经过 Emoji normalize、VS 增删、ZWJ 过滤、肤色/性别改写、
shortcode 或图片转换。Unicode Emoji 按普通文本处理；自定义 Sticker/GIF/WebP/
TGS 等继续使用原有资源和消息协议。表情目录用于选择浏览，不决定什么文字能够
输入、保存或显示；最近项和收藏可保留不在目录中的原文。

原始消息/草稿与用于显示的摘要、搜索折叠或 Markdown 语法解释分离。
原有非聊天名称的裁边政策采用 grapheme 安全处理；不把显示摘要回写为消息正文。

“未来不用新增业务 Emoji 分支”已经实现；“冻结客户端/系统后永远包含未来字形和
分词规则”无法保证。基础库、Flutter/engine 或系统更新仍可能需要。

## 5. 字体 fallback 方案

共享 `PlatformTextFonts` 保留桌面原有中文字体偏好，Android/iOS 不硬设家族或
Emoji 字库，让 Flutter 与系统解析 fallback。移除 Web 的未注册字体假设。
聊天及钱包字号、字重、行高参数和日夜颜色保持原值，没有全局粗暴换字体。
签名以最低占位代替固定高度；账号行解除强制 strut，并保留空账号最低占位，
允许实际 fallback 行高自然增长。原生探针对照系统 Text，区分项目破坏和系统缺字。

依据：[Flutter fontFamilyFallback](https://api.flutter.dev/flutter/painting/TextStyle/fontFamilyFallback.html)、
[StrutStyle](https://api.flutter.dev/flutter/painting/StrutStyle-class.html)。

## 6. Grapheme Cluster 处理方案

可见字数和用户文本截取使用 `package:characters` extended grapheme clusters。
昵称、签名、备注、公告、朋友圈、反馈、直播等的提交校验与可见计数保持同一语义。
共享工具不重组或规范化字符，只选择完整 cluster。搜索/格式化边界一次生成并
缓存，匹配位置通过二分查找对齐，避免每次命中重复扫描全文。

Flutter selection/composing、SDK 实体 offset/length 和 parser offsets 仍按 UTF-16
协议单位处理。字节限额、ID、金额、手机号及协议 scalar 限制不机械替换。
现有支付备注 12 scalar、收藏搜索 64 scalar、设备同步 200 scalar 仍按既有合同，
不会截取半个 cluster；是否应调整服务端合同另需部署端证据。

当前 [characters 1.4.1](https://pub.dev/packages/characters) 基于 Unicode 16.0。
新 Unicode 分词规则不能凭旧版本库自动获得；这是基础版本更新问题。

## 7. 输入框处理方案

复用项目 `ChatTextField` / `extended_text_field 16.0.2`。实际实现为该包的
`ExtendedEditableText` / `ExtendedRenderEditable`，不是 Flutter 同名类型的子类；
测试和探针检查真实类型。系统 composing 不经业务层过滤或修改。

显式面板编辑只处理完整 cluster；光标对齐新文本，涵盖插删后 RI 合成旗帜等情况。
@ 选择不在 composing 中触发，组合提交后才整理提及元数据；选择返回时再次
检查输入版本/会话/组合状态。原始 controller 文本进入草稿和发送链路。

受控虚拟 IME、硬键盘删除和 composing 测试通过；真实软键盘和系统剪贴板
**尚未真机验证**，不将 widget 测试中的 iOS 主题当作 iOS 设备运行。

## 8. 消息显示处理方案

TextView、MatchTextView、Markdown 不再插入隐藏断行字符，普通文字不再作为
HTML 过滤；搜索命中和实体样式扩大到完整 cluster，不更改 SDK 元数据。
省略组件不从 surrogate/ZWJ 中间切片、不重复尾部。引用摘要折叠完整空白 cluster。

| 场景 | 检查/覆盖结果 |
| --- | --- |
| 普通、@、引用/回复、格式化、Markdown 气泡 | 原文进入渲染树；共享显示边界及结构测试通过。 |
| 会话列表、长按预览、草稿、历史缓存 | 复用消息显示和对象/JSON 原文；预览/草稿/缓存相关回归通过。 |
| 转发、合并转发 | SDK 创建函数原始对象/正文传递；method codec、JSON/UTF-8 受控往返通过。 |
| 搜索与高亮 | 本地历史查询原文、摘要边界、AI 折叠索引映射、全局草稿字幕测试通过。 |
| 消息编辑、撤回重新编辑、复制粘贴 | 源码复用原始正文/标准平台 String，未发现 Emoji 转换；编辑与受控 Clipboard 往返有测试，真实剪贴板未验。 |
| 群名、群昵称、好友备注、签名、公告、注册昵称 | 提交/计数/裁边按完整 cluster；现有编辑测试和新增结构测试通过。 |
| 系统/本地通知、快捷回复、App 内推送 | 摘要只处理允许的控制字符/完整空白 cluster；回复原文排队发送测试通过。 |
| @ 用户及输入联想 | 提及安全插入，picker 与 IME 冲突保护测试通过；目录不限制系统文字。 |
| 语音转写、客服、业务附件/厅名 | 返回、localEx/JSON 缓存、预览编辑、发送/API/模型原文测试通过。 |
| 中文、RTL、多语言及混排 | 结构测试保留原文；Android 代表截图对照系统显示，详见证据。 |

这些客户端/受控 native handler 测试不等于真实 SDK 核心或在线收发已通过。

## 9. 数据库存储检查结果

本地锁定 `flutter_openim_sdk 3.8.3+hotfix.12` 的 Dart managers/模型、Android Java
String + JSONObject.wrap、iOS String + JSONSerialization + UTF-8 已检查；
未发现已检查文本路径过滤 VS/ZWJ/tag 或错误单字节编码。没有修改 SDK 协议。

公开上游 v3.8.3 SDK 使用 SQLite，服务端消息模型为 BSON/Mongo 文档。
工作区没有当前部署的服务端源码、schema、数据库连接或字符集配置，不能拿
上游代码证明线上环境。原生 SDK 二进制数据库、WebSocket/TCP、Redis、消息回调、
资料存储和搜索索引的真实 roundtrip **未验证**。

如果部署使用 MySQL，消息、昵称、备注、群名、群公告、草稿、引用和搜索索引
相关数据库、表、字段及连接均需核验 `utf8mb4`，不能只检查 message.content。
当前没有这些实际证据，未猜测性修改服务端或数据库。详细 SDK 文件与上游链接
见 [传输审计](transport-audit.md)。

## 10. Android 检查结果

主应用 `flutter build apk --debug --no-pub` 成功，生成
`build/app/outputs/flutter-apk/app-debug.apk`；未安装覆盖已登录主应用。

独立包在 Android 9 / API 28 模拟器执行 **21 样本 × 日夜主题 = 42 组**。
每组 8 项渲染原文/回调/JSON 检查与 seedUnchanged 均通过。截图由探针自身生成，
人工核对箭头、家庭、肤色职业、Tag 旗帜及中文混排等代表项；新补充平面值在
系统 Text 和项目组件均缺字，但原始序列仍完整。未声称人工检查全部 42 张字形。

[原生截图、日志及证明范围](native-evidence/README.md)。物理 Android
**尚未真机验证**；真实 Gboard/其他输入法、剪贴板和在线跨设备收发未验。

## 11. iOS 检查结果

已检查 SDK Swift 桥、主题/fallback、selection/composing 语义，且 iOS 平台配置
的输入/资料日夜与文字缩放 widget 测试通过。当前 Windows 环境没有 iOS 执行器，
未执行 iOS 构建、模拟器或物理设备测试。iOS **尚未真机验证**。

## 12. 自动化测试结果

最终相关整批：**1602 通过，16 跳过，0 失败**。跳过项是既有条件控制的图片/页面
预览导出测试，需输出目录/导出开关；Unicode 原文回归没有被跳过。
最后新增的 RI 合并光标与旧搜索/图片夹具定向批次：70 通过；随后完整批次再次通过。
这不是全仓所有测试，执行范围与摘要见 [验证记录](verification-results.json)。

结构覆盖单码点、VS15/VS16、ZWJ、肤色、家庭、情侣、性别、职业、RI/旗帜、
keycap、tag、combining、空白基底 combining、补充平面 CJK、Indic、RTL、
CJK/Latin/多语言混排和目录未知的新码点。业务逻辑不导入 fixture。
验证包括输入/编辑/IME、草稿创建保存恢复、消息/资料 JSON/UTF-8、搜索、高亮、
通知队列、转写 localEx、复制、日夜主题与布局；不连接真实用户或远端数据库。

## 13. flutter analyze 结果

完整 `flutter analyze --no-pub` 已执行，**退出码 1，未通过**。
最终结果为 **501 项：9 error、31 warning、461 info**。
9 个错误全部位于原先未改动的本地插件示例：

- `local_plugin/uri_to_file/example/lib/main.dart`：缺 fluttertoast/uni_links、
  getInitialLink、linkStream、Fluttertoast。
- `local_plugin/uri_to_file/example/test/widget_test.dart`：缺示例包导入/MyApp。
- `local_plugin/voice_note_kit/example/test/widget_test.dart`：缺示例包导入/MyApp。

最终没有应用 `lib/`、公共包 `openim_common/lib/`、新增 Unicode 测试/工具的
error 诊断。项目仍有旧式可变 widget、弃用 API、导入、类型、发布依赖与测试
lint 等警告/提示；不能说全仓分析已干净。本轮未通过改排除规则来隐藏错误。
`git diff --check` 通过，所改 Dart 文件格式化完成。

## 14. 尚未解决的问题/风险

1. 系统字库/Flutter shaping 不包含的字符仍可能缺字；Android 9 探针已实际发现
   新码点缺字。它不代表原文损坏，也不能保证任意未来规则在旧 runtime 中正确分词。
2. Android/iOS 真实输入法、复制粘贴、选择光标、提及交互、跨设备在线发送和物理
   字形/行高 **尚未真机验证**。iOS 构建也未验证。
3. 原生 SDK 核心 SQLite 和部署端数据库/连接/回调/索引未做实际往返；MySQL
   utf8mb4 未得到当前部署证据。更改可见字数语义后，远端资料/业务限额还需联机核对。
4. 完整静态分析仍有上述插件示例错误及旧 lint。支付、收藏、设备同步保留既有
   scalar/byte 合同；业务若要求可见字数合同需同时确认服务端。
5. 本轮改善原文和边界处理，没有承诺所有平台的 Emoji 美术样式一致。

客户端修复可在当前系统能力范围内保留复杂 Unicode；任何新增 Emoji 不需要
维护业务白名单。上线前的最终设备与部署验收必须按以上未验证项独立完成。
