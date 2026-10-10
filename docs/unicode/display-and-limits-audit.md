# 显示与用户文本限制审计

审计日期：2026-10-08。范围为当前 Flutter 客户端 `lib`、`openim_common/lib`、`openim_live/lib` 中用户可见文本的切分、摘要、匹配、高亮、字数校验和显示归一化。聊天输入编辑、主题字体以及 SDK/数据库链路由对应审计报告说明。

## 实际根因与受影响场景

1. `TextView` 使用 `replaceAll('', '\u200B')`；匹配文本和 Markdown 自定义匹配使用 `split('').join('\u200B')`。这些操作按 UTF-16 位置插入零宽空格，可能拆开补充平面代理对、Variation Selector、ZWJ、肤色、旗帜、Tag 和 Combining 序列，也使可复制文本与原文不同。
2. `MatchTextView` 在普通消息显示前用 HTML 正则过滤 `<...>`、`&...;`，还无条件插入一个名为 `emojiFaces` 的占位匹配表。普通聊天文本并非 HTML；过滤会使聊天内容和可见/复制内容不一致。该占位表并没有提供 Unicode Emoji 能力。
3. 中间省略组件直接按 `String.substring` 提取尾部，并把包含尾部的完整原文又作为前段显示。长文件名/用户文本可能从组合序列中间截断，并重复显示尾部。
4. 搜索摘要以 `index - 4` 回退，AI 搜索直接用小写字符串索引截取原文。搜索命中或上下文边界可能落在一个完整可见字符内部。格式化消息只防止代理对截断，没有保护 ZWJ、VS、Combining 等多码点字符。
5. 注册昵称把 UTF-16 长度当昵称字数；朋友圈正文/评论、反馈、直播名称/描述/备注把码点数当可见字数。输入框已有的 Flutter 可见字符计数可能与提交校验不一致。一个复杂 Emoji 可能被算成多个字，从而过早拒绝提交或显示错误计数。
6. `String.trim` 和 `RegExp(r'\s+')` 会处理组合序列内部的空白基底。例如 `空格 + combining mark`、`NBSP + combining mark` 本身是完整字符，不能只移除或替换其基底。
7. 资金消息接收模型重复执行发送接口的 12 码点上限，超过上限时把整段备注置空。收到的合法 Unicode 文本可能因此完全不显示，即便只有少量可见 Emoji。
8. `fixed63Length` 扩展会在 63 个 UTF-16 单元时插入空格。本次搜索未发现调用，因此它是未使用的危险编辑逻辑，不能据此认定它是当前输入异常的运行时原因；已移除。

本次修复通过共享 `unicode_text.dart` 与 `package:characters` 处理完整 grapheme cluster。渲染、匹配、复制不插入隐藏断行字符，不枚举 Unicode Emoji，不改写 VS15/VS16、ZWJ、modifier、regional indicator 或 tag。字符串偏移仍使用 Flutter/SDK 的 UTF-16 协议单位，仅显示分段对齐完整 cluster。边界表一次生成，匹配时二分查找，避免每个命中重复扫描全文。

## 修改文件逐项说明

所有路径相对 `E:/openim/openim-flutter-demo`。本表只列本审计范围实际修改，AI 创建/传输契约的最终修复由传输审计负责。

| 文件 | 修改内容 |
| --- | --- |
| `openim_common/lib/src/extension/custom_ext.dart` | `TextView` 原样显示原文；`fixAutoLines` 不再插零宽字符；分组格式化按完整 cluster；删除无调用的 63 UTF-16 单元空格注入逻辑。 |
| `openim_common/lib/src/widgets/text_view.dart` | 普通文本不再经过 HTML 过滤或伪 Emoji 占位表；匹配的显示范围对齐完整 cluster；原文不插零宽字符；非法/空自定义匹配安全降级；链接前缀使用 `startsWith`，避免短邮箱越界。 |
| `openim_common/lib/src/widgets/text_ellipsis_middle_view.dart` | 中间省略前后段按完整 cluster 划分，保留完整尾部且避免重复；前段单行；不注入零宽字符。 |
| `openim_common/lib/src/widgets/chat/chat_formatted_text.dart` | 保留原始 SDK 实体偏移，显示范围扩展到完整 cluster；共享边界缓存；无效协议范围仍忽略。 |
| `openim_common/lib/src/widgets/chat/markdown/chat_markdown_text.dart` | Markdown 自定义匹配显示原文，不按 UTF-16 单元插零宽字符。 |
| `openim_common/lib/src/widgets/chat/markdown/chat_markdown_patterns.dart` | 仅在完整 cluster 边界创建自定义匹配节点；零宽正则回到普通解析；按 parser 原文缓存边界。 |
| `openim_common/lib/src/widgets/chat/quote/chat_quote_content.dart` | 引用摘要只折叠完整空白 cluster；摘要及发送者名使用 cluster 安全边界空白处理。 |
| `openim_common/lib/src/utils/utils.dart` | `IMUtils.calContent` 搜索摘要从完整 cluster 边界开始，向前保留最多 4 个完整可见字符。 |
| `openim_common/lib/src/models/fund_message_data.dart` | 接收的可选备注只做类型检查及安全边界空白处理，不再因发送码点上限整段隐藏。 |
| `openim_common/lib/src/widgets/title_bar.dart` | 会话/群名标题的边界空白处理保留组合字符基底。 |
| `lib/pages/ai_assistant/search/ai_assistant_search.dart` | 复制保留原文；搜索折叠只用于匹配；建立折叠位置与原始 cluster 边界映射，高亮完整字符。 |
| `lib/pages/chat/group/announcements/group_announcement_banner.dart` | 公告可用状态和摘要空白压缩按完整 cluster，保留空白基底组合字符。 |
| `lib/pages/chat/group_setup/group_announcement_page.dart` | 公告提交及是否修改的比较使用 cluster 安全边界空白处理。 |
| `lib/pages/chat/group_setup/edit_name/edit_name_logic.dart` | 群名/群昵称原始值及保存比较采用 cluster 安全边界空白处理。 |
| `lib/pages/chat/group_setup/group_setup_logic.dart` | 本人群昵称显示及默认昵称比较保留完整 cluster。 |
| `lib/pages/chat/group_setup/group_member_list/group_member_list_logic.dart` | 群成员查询关键词保留空白基底组合字符。 |
| `lib/pages/chat/group_setup/group_manage/group_member_permissions_page.dart` | 管理员/禁言成员查询及姓名显示采用 cluster 安全边界空白处理。 |
| `lib/pages/chat/history_search/chat_history_results_page.dart` | 历史搜索各查询入口、初始词及空查询检查使用同一 cluster 安全处理。 |
| `lib/pages/chat/history_search/chat_history_search_source.dart` | 冻结查询的关键词保持完整 cluster；会话和发送者 ID 继续采用身份协议语义。 |
| `lib/pages/chat/history_search/files/chat_history_file_tile.dart` | 历史文件气泡中的显示文件名不拆空白基底组合字符。 |
| `lib/pages/chat/history_search/selection/chat_history_sender_page.dart` | 按发送者筛选的查询词保留完整 cluster。 |
| `lib/pages/chat/history_search/selection/chat_history_sender_source.dart` | 发送者显示名与成员昵称查询采用 cluster 安全边界空白处理；ID 不变。 |
| `lib/pages/chat/history_search/widgets/chat_history_result_tile.dart` | 历史文字及语音结果的发送者昵称显示保留完整 cluster。 |
| `lib/pages/chat/history_search/widgets/chat_history_search_bar.dart` | 查询变化、提交及清空按钮状态采用一致的 cluster 安全关键词处理。 |
| `lib/pages/contacts/create_group/create_group_default_name.dart` | 自动群名使用昵称时保留完整组合序列。 |
| `lib/pages/contacts/create_group/create_group_logic.dart` | 用户填写群名称的边界空白处理不拆组合字符。 |
| `lib/pages/contacts/user_profile_panel/set_remark/set_remark_logic.dart` | 好友备注保存及原始值比较不拆空白基底组合字符。 |
| `lib/pages/contacts/user_profile_panel/user_profile_panel_view.dart` | 传入个人资料身份组件的昵称与签名保留完整 cluster。 |
| `lib/pages/contacts/select_contacts/search_contacts/search_contacts_logic.dart` | 空查询状态采用 cluster 安全检查。 |
| `lib/pages/contacts/select_contacts/search_contacts/search_contacts_view.dart` | 复用公共 `MatchTextView` 高亮昵称，替换无法保证完整 cluster 边界的第三方高亮组件；搜索词按字面正则匹配。 |
| `lib/pages/global_search/global_search_logic.dart` | 共享 `CommonSearchLogic.searchKey` 的边界空白处理保留完整 cluster，覆盖继承它的全局/联系人搜索。 |
| `lib/pages/global_search/widgets/global_search_conversation_subtitle.dart` | 草稿正文保留原文，只用 cluster 安全空白检查决定是否显示草稿。 |
| `lib/pages/group_features/live/data/live_api.dart` | 直播名称、描述、备注的可见字符限制采用 `characters.length`；安全边界空白处理；协议 ID 保持原规则。 |
| `lib/pages/group_features/live/models/live_models.dart` | 接收 DTO 的名称/描述按可见字符校验，保留完整文本组合序列。 |
| `lib/pages/group_features/live/pages/live_manage_page.dart` | 名称/描述右侧计数按可见字符，与输入限制及提交校验一致。 |
| `lib/pages/group_features/live/pages/live_tip_sheet.dart` | 打赏备注计数及冻结提交文本按完整 cluster 处理。 |
| `lib/pages/mine/settings/pages/edit_signature_page.dart` | 签名保存及修改状态比较采用 cluster 安全边界空白处理。 |
| `lib/pages/mine/settings/pages/feedback_page.dart` | 反馈提交校验按可见字符，与现有计数一致；提交正文与重复提交指纹保留完整 cluster。 |
| `lib/pages/mine/settings/pages/profile_info_page.dart` | 个人资料签名显示的边界空白处理保留完整 cluster。 |
| `lib/pages/mine/settings/pages/qr_profile_page.dart` | 二维码资料中的显示昵称保留组合字符。 |
| `lib/pages/mine/settings/settings_draft_store.dart` | 服务端签名进入个人资料缓存时保存原文，不删除原始边界空白；原有本地编辑优先规则不变。 |
| `lib/pages/mine/widgets/mine_profile_view.dart` | 我的页面昵称与签名显示采用 cluster 安全边界空白处理，账号 ID 规则不变。 |
| `lib/pages/moments/moments_compose_page.dart` | 发布按钮的正文长度校验按完整可见字符。 |
| `lib/pages/moments/moments_draft_store.dart` | 草稿是否有内容以及发布前正文校验按完整 cluster；不改持久化原始草稿内容。 |
| `lib/pages/moments/presentation/moments_composer_layout.dart` | 正文长度错误提示按可见字符校验。 |
| `lib/pages/moments/interactions/moments_comment_editor.dart` | 评论提交、计数、禁用及错误提示统一按可见字符；冻结提交文本安全保留组合序列。 |
| `lib/pages/register/rules/register_nickname_rules.dart` | 昵称最少 2 字按可见字符校验。 |
| `lib/pages/register/set_password/set_password_logic.dart` | 注册按钮及提交昵称与新昵称规则保持一致，不把一个代理对当成两个字。 |
| `lib/services/moments_api.dart` | 正文/评论可见字符上限校验与界面一致，HTTP 请求文本采用完整 cluster 安全边界空白处理。 |
| `lib/services/fund_models.dart` | 资金备注继续遵循 12 Unicode 码点发送合同，只将不安全 `trim` 换为完整 cluster 边界空白处理。 |
| `lib/pages/fund/README.md` | 明确资金备注发送码点合同与接收完整显示的不同职责。 |
| `test/widgets/text/unicode_text_rendering_test.dart` | 新增结构类型 fixture 的普通/匹配文本、格式化边界、引用、Markdown、短邮箱点击、摘要上下文及中间省略回归。 |
| `test/pages/ai_assistant/search/ai_assistant_unicode_search_test.dart` | 新增完整 query 与部分 cluster 命中回归，核对原文和全部 span 边界。 |
| `test/pages/register/register_unicode_nickname_rules_test.dart` | 新增单 cluster 昵称不足 2 字、追加一个汉字符合 2 字的结构类型回归。 |
| `test/fund_message_test.dart` | 接收备注回归改为保留复杂字符；非 String 类型仍不能扩大自定义消息识别。 |
| `test/fund_api_test.dart` | 增加空白基底与 combining mark 的发送备注保留验证；既有 12 码点合同断言继续保留。 |
| `test/moments_api_contract_test.dart` | 增加 2000 个 family cluster 的请求/DTO完整性、2001 字拒绝以及空白基底组合字符保存验证。 |
| `test/pages/group_features/live/live_api_test.dart` | 增加复杂 cluster 名称/描述的接收 DTO 上限与原文验证。 |
| `test/pages/chat/history_search/unicode_history_text_test.dart` | 新增结构类型的历史查询关键词、发送者昵称与身份 ID 保留回归。 |
| `test/pages/global_search/global_search_draft_test.dart` | 增加草稿字幕保留空白基底组合字符的回归。 |
| `test/pages/mine/settings/settings_draft_unicode_test.dart` | 新增结构类型昵称/签名进入资料草稿时原文及边界空白保留回归。 |

## 合理协议例外及已检查但不机械替换的代码

| 代码/场景 | 保留理由 |
| --- | --- |
| `FundRemark.maxCodePoints` / 发送 `remark` | 现有 `fund_models.dart` 和资金 README 明确规定 12 个 Unicode 码点。保留发送合同，不改为 12 个可见字符，不按码点从中间截断。 |
| 收藏搜索 `FavoriteApi.list` 与 `FavoriteSearchFormatter` | README 与 formatter 明确规定 API 的 64 Unicode 标量限制。formatter 已逐完整 cluster 累计码点；不会保留半个 cluster。 |
| 收藏笔记 UTF-8 字节上限 | 明确的 64 KiB 网络/存储合同；字节数不是可见字符数，不能改成 grapheme 字数。 |
| `device_sync_models.dart` | 接收/传输模型设备说明和文件名的现有码点字段保护；没有按码点切片或重组内容，本轮没有证据更改服务端合同。 |
| SDK `MessageEntity.offset/length`、Flutter `TextSelection`、解析器索引 | 它们必须保持 UTF-16 offset 协议语义。本轮只规范显示分段，不更改上传的 SDK 实体位置。 |
| 账号、公开用户 ID、群 ID、UUID、哈希、URL 路径、MIME 后缀、文件协议头、数字金额/验证码/支付密码 | 它们具有独立协议语法，不是自由昵称或聊天正文；原有 ASCII、数字、字节、路径偏移及长度保护不机械替换。 |
| 三公帮工公开账号和用户 ID 的空白过滤 | 属身份协议限制，不用于昵称、备注、正文或 Unicode Emoji。 |
| 电话脱敏、固定币种代号首字母、固定 A–Z 索引、ASCII 派生拼音索引 | 不表示用户可见字符计数，也没有截断自由聊天内容；保留现有语义。 |
| `install.codeUnits` 更新灰度散列 | 内部稳定标识散列，不是可见字数或文本编辑。 |
| 自定义表情/Sticker | 保持原资源和协议归属。本轮不把 Unicode Emoji 转成图片、shortcode 或 `[表情]`，不为 Unicode 新建白名单。 |

也检查了聊天历史搜索、转发/合并转发、消息缓存、昵称与备注共用编辑组件和系统通知字符串操作。其中已有的 `characters.first`、Flutter `maxLength`/标准长度 formatter、列表 `.take`、按已知协议前缀剥离字符串等保持正确语义；没有把所有 `.length`、`substring` 或正则机械替换。字体及输入光标真实运行行为以对应报告和平台验证结果为准。

## 参考实现

只读对照了 `E:/openim/reference-99chat/lib/utils/chat_emoji_sticker_list.dart` 与其 `third_party/tencent_cloud_chat_uikit/.../tim_uikit_text_field.dart`。前者将自定义 PNG Emoji 包作为 Sticker 管理，继续保留这一业务边界。参考输入仍存在按 UTF-16 长度删除的实现，因此没有将这种编辑逻辑移植为 Unicode 兼容方案。

## 回归结构覆盖

复用 `test/support/unicode/unicode_samples.dart`。测试涵盖补充平面单码点、VS15、VS16、ZWJ、肤色、家庭、情侣、性别、职业、旗帜、单 regional indicator、keycap、tag、combining、空白基底 combining、补充平面 CJK、Indic、CJK/Latin 混排、RTL 和多语言混排，以及原始未来码点值。fixture 只属于测试，业务代码不导入它，也不依赖某个 Emoji 图案识别。

测试重点是原文一致性、完整 cluster 分段、提交校验语义和协议单位保留。widget 文本数据断言不能证明 Android/iOS 系统字形或软键盘真机表现。没有改变部署服务端、数据库、SDK 协议或资金合同；尚未依据这些客户端测试证明部署服务端对新的可见字符长度语义已经联机通过。

## 运行结果

最终执行范围及证据见 [主审计](audit-and-verification.md) 和
[验证记录](verification-results.json)。

| 项目 | 最终结果 |
| --- | --- |
| 自动化回归 | 1602 通过、16 个条件预览导出跳过、0 失败。 |
| Flutter 静态分析 | 未通过：9 error、31 warning、461 info；错误在既有插件示例。 |
| Android | 主应用构建成功；模拟器 42 组原文检查通过，代表截图已查，系统不支持的新码点仍缺字；尚未真机验证。 |
| iOS | 源码/平台配置 widget 测试已查；未构建或设备运行，尚未真机验证。 |
| 服务端/数据库 | 锁定客户端桥与公开上游已查；实际部署、字符集与原生核心数据库往返未验证。 |
