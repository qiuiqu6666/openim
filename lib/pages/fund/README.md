# 资金模块

聊天「+」中的红包、转账调用 `FundSendPage`；资金卡片打开 `FundDetailRoute`，返回最新已验证订单。视觉源为本地 `reference-99chat` 的钱包模块，协议说明见 [资金合同](../../../docs/fund-client-contract.md)。

资金及钱包页面的头部返回箭头统一使用公共蓝色 `AppTokens.accent`（`#1E90FF`），与迁移后的设置页一致。钱包复用现有 `AppBackButton` 默认颜色，充值、提现、兑换、账单及关联订单页不再用文字色覆盖；独立钱包首页仅在可返回时显示该按钮。红包与转账详情仅调整返回箭头颜色，保留标题、右侧操作、返回订单及资金数据链路。已核对支付密码、扫码、选好友及区号页沿用同一蓝色，不新增组件。

2026-10-06 返回箭头验收：130 项相关页面、布局和导航回归通过，9 个修改文件的 analyze 无问题，Android debug 构建通过。已检查提现页的亮暗主题真实 Widget 截图；整个钱包/资金目录分析仍有 3 项原有提示，位于未修改的余额快照、通用弹窗和路由文件。未使用真实资金，Android/iOS 实机体验尚未验证。

## 职责与所有者

- `fund_send_page.dart`：发送表单、真实余额、账户/服务地址校验、待确认交易恢复与幂等提交；页面创建并释放输入控制器和生命周期监听。
- `payment/fund_payment_preferences.dart`：账号和服务器隔离的默认支付币种，复用 SharedPreferences 持久保存确认选择，红包/转账及各聊天入口共同读取；不保存密码、金额或订单，不替换待确认交易的币种。`fund_payment_draft.dart` 持有本次支付的只读快照与切换币种校验。
- `payment/fund_transfer_authorization.dart`：转账安全预检查、当前业务的内存凭证及原业务单号恢复；`withdrawal_security/` 复用到转账与链上提现，提供等待期、短信发送与重发。业务参数改变或服务端返回凭证失效后重新验证；已成功的原订单不再要求短信或再次提交。
- `fund_detail_page.dart`：订单加载、参与者资料、显式领取与最新订单回传；异步代次、账户和订单检查由页面统一持有，展示组件不发请求。
- `widgets/fund_detail_message_sender.dart`：不可变 SDK 发送者展示资料，供接口缺省发送人时显示昵称和头像；不进入资金订单或授权判断。
- `fund_recipient_picker.dart`：OpenIM 群成员分页、昵称搜索与单人选择；取消搜索计时器并屏蔽迟到响应。
- `widgets/fund_recipient_user_id.dart`：转账页的公开用户 ID 展示，复用既有 `ContactCardProfileResolver` 按 SDK 收款 ID 查询真实 `UserFullInfo.account`，与资料页一致。缺少公开 ID 时显示占位，禁止用 `im_...` 或解码生成的值替代；切换收款人/账号和离开页面后不显示迟到结果。长 ID 可完整换行与选择复制，不更改转账请求的收款标识。
- `widgets/`：`fund_send_form`/`fund_transfer_send_form` 发送展示、`fund_pay_sheet` 支付摘要与错误适配、`fund_pay_method_sheet` 币种选择、`fund_coin_icon` 币种图标、`fund_packet_cover` 群红包拆封、`fund_packet_detail` 所有红包的共同详情展示以及 `fund_transfer_detail` 转账详情；`fund_page_colors`/`fund_send_tokens` 提供主题颜色和局部尺寸。局部度量换算到 375×812，不修改应用全局设计尺寸。
- `../chat/fund/`：资金消息展示适配、卡片尺寸/颜色与聊天订单状态协调。公共消息协议保留在 `openim_common`，公共包不反向引用页面。

`lib/services/fund_api.dart`、`fund_models.dart`、`fund_pending_store.dart` 为既有资金数据入口，本轮沿用路径，避免在并行聊天拆分中改变调用边界；后续可整体迁入本模块的 `data/`。待确认记录按账户、服务器和业务隔离，不保存支付密码、短信验证码或 challenge。详情中的长页面状态暂保留统一的请求、领取动画与路由关闭保护；已将独立纯展示职责抽出，后续状态拆分应以这三者的生命周期边界为准，禁止复制私有状态或增加第二个请求所有者。

## 复用与差异

复用 `AvatarView`、`SearchBox`、`AppTokens`、交易密码设置页以及共享六格密码/键盘组件。新增资金展示是因为原客户端缺少对应能力；不再新增通用头像、搜索或键盘实现。原图片的许可在 `docs/licenses/99chat-APACHE-2.0.txt`。

支付状态和弹窗生命周期由 [共享支付组件](../../widgets/payment/README.md) 持有。六位密码立即提交，原键盘区域显示支付中和成功状态，失败留在原弹窗清空密码重试。`FundSendPage` 保留真实请求快照、账户校验和原单幂等；通用组件不反向依赖资金模型。

红包发出和转账完成后，统一调用 `IMViews.showToast` 显示现有居中提示。提示挂在应用覆盖层，发送页返回聊天后继续显示；沿用全局颜色、字号与时长，不创建业务专用 Toast。

真实数据来自 Chat 资金 API 与 OpenIM SDK。当前服务端直接到账的订单显示已到账，不复制旧确认收款动作。红包祝福语和转账备注已经通过当前资金接口提交并展示；自定义封面、法币换算和在线状态缺少对应接口时，不伪造这些数据或动作。测试用模拟 API，不操作线上资金。本轮只补齐现有红包、转账，不新增数字资产、闪兑或提现页面。

## 祝福语与备注合同

发送页的红包祝福语、转账备注共用 `remark` 字段。公开校验入口为 `lib/services/fund_models.dart` 中的 `FundRemark.normalize`：先 trim，再用 `String.runes` 限制最多 12 个 Unicode 码点；不按 UTF-16 长度或视觉字符数截断。空红包由服务端保存默认祝福「恭喜发财，大吉大利」，空转账保存空字符串。

`FundApi.sendPacket` 和 `sendTransfer` 接收可选 `String? remark`。新请求提交实际归一化内容；待确认后备注随原单号、金额与收款对象冻结，不能在重试时编辑。旧待确认记录缺少该字段时继续原请求体，`null` 不会补字段；显式空字符串仍提交空字符串。按当前接口文档，同单号修改备注或其他业务参数返回 `20062`；客户端提示查询并核对原订单，不以新单号自动重付。

`FundOrder.remark` 缺省为空字符串，兼容旧 GET；已有字段须为字符串。OpenIM `contentType=110` 自定义资金消息新增第六个 `remark` 字段，旧消息仍能解析。详情与卡片以 GET 返回的订单备注为权威，空红包使用默认祝福，空转账不新增备注行；备注不参与金额或收款人身份校验。

当前真实订单 GET 可能省略发送人字段。详情兼容缺省发送人，读取和领取授权由认证后的资金接口决定，仍校验订单号、业务、币种、金额、场景、收款人、状态和份额。匹配原资金消息的 SDK 发送者资料仅作昵称/头像展示回退；API 已有发送人时优先使用 API 身份，不把展示资料写进 `FundOrder` 或作为付款/领取资格。

## 红包详情统一布局

按用户最新截图要求，单聊普通红包、单聊/群专属红包与已展示的群红包详情共同使用 `FundPacketDetail` 的红色弧形顶部、头像祝福、金额及记录列表。原狮子大图详情和独有入场动画已移除，拆封用的原封面与领取动画仍由原页面持有。所有红包详情不再显示“红包信息”；转账继续提供“交易信息”。复用现有主题 token、弧形画笔、头像、金额展示和列表，不维护两个红包详情实现。

直接到账记录只读取已验证 `done` 订单中的 `recvID` 与 `amount`，显示“已到账 1/1 个”；这是一条到账展示，不创建 `FundShare`、不修改空 `shares`、不请求领取。按用户 2026-10-04 要求，单聊双方与群聊的记录时间均只显示 `yyyy-MM-dd HH:mm`，不显示“发送时间”前缀。单聊仍读取订单 `createdAt`，群聊读取真实 `claimedAt`，二者统一通过 `toLocal()` 转为手机系统本地时区；时间缺省则不显示，不写死北京时间或服务端时区。群红包继续仅显示接口返回的真实份额与实际领取金额；已关闭且无记录时显示“暂无领取明细”，不会伪造领取人。资金校验、显式拆封、一次领取、身份隔离和路由回传由页面继续统一管理。

## 验证入口

2026-10-06 提币与内部转账文档接入：收款人使用专用确认接口；转账与链上提现复用本笔安全预检查、短信和等待期提示。已验证同一业务参数贯穿检查、短信与付款，凭证不落盘、取消及会话切换不提交、失效凭证重新验证、原单恢复、缺省 +86、`internal` 资金卡详情，以及冲突/服务错误保留原单号。资金相关原回归和新增契约、钱包提币回归、亮暗真实短信弹层预览通过，本次修改静态检查及 Android debug 构建通过。测试安装包为 `build/app/outputs/flutter-apk/app-fund-withdrawal-security-debug.apk`。本轮使用模拟接口，未发送真实短信或提交真实资金交易。

2026-10-04 默认支付币种长期记录：表单与支付弹窗确认选择后立即保存，取消或保存失败不改变偏好；新页面加载真实余额时恢复有效的默认币种，后续余额刷新不覆盖本页已选币种。待确认原交易始终优先，恢复交易不改写默认偏好。95 项功能验证及 2 项日夜重新打开后的渲染验证通过，相关静态分析无问题；Android debug 构建成功，固定安装包为 `build/app/outputs/flutter-apk/app-fund-default-currency-debug.apk`，效果见 `docs/previews/fund-pay-default-currency-{light,dark}.png`。验证使用模拟接口，尚未在手机实机验证。

2026-10-04 支付弹窗币种切换：复用 `FundPayMethodSheet` 和共享支付组件的选择锁，确认切换同步金额单位/余额并清空密码，取消保留原输入。业务快照及币种精度、整数范围、群红包最小分配额校验独立位于 `payment/fund_payment_draft.dart`；支付和账号/路由生命周期仍由发送页持有。请求中、成功以及原交易结果未确认时禁用更换，新币种使用新单号，未更换币种的重试保留原单号。79 项功能验证和 2 项日夜渲染通过，静态分析及 Android debug 构建通过；安装包为 `build/app/outputs/flutter-apk/app-fund-payment-currency-debug.apk`，预览为 `docs/previews/fund-pay-currency-{light,dark}.png` 及相应选择器预览。尚未使用真实账户支付或进行 iOS 真机验证。

2026-10-04 记录时间调整：详情 66 项回归及日夜 6 项渲染通过，3 个分析目标无问题。真实毫秒时间戳样本经 UTC 解析后按运行设备本地时区展示，发送方与接收方均无“发送时间”前缀。Android debug 构建成功，当前 APK 为 `build/app/outputs/flutter-apk/app-fund-local-time-debug.apk`。预览仍位于 `docs/previews/fund-packet-unified-light.png` 和 `fund-packet-unified-dark.png`；尚未进行手机实机验证。

统一红包详情验证（2026-10-03）：详情 66 项、API 29 项与聊天协调 52 项，共 147 项相关回归通过；6 项日夜主题渲染通过，5 个本轮分析目标无问题。覆盖三种直接到账红包双方展示、null/空份额不造领取记录、发送时间和缺省时间、精确金额、真实群领取明细与最佳手气、已关闭空明细提示、红包信息移除与转账交易信息保留，并保留原身份与领取保护。当前 APK 为 `build/app/outputs/flutter-apk/app-fund-packet-detail-debug.apk`，效果见 `docs/previews/fund-packet-unified-light.png` 与 `fund-packet-unified-dark.png`。本轮未操作线上资金或安装到手机验证，以下保留此前验证记录。

已有回归位于 `test/fund_api_test.dart`、`fund_send_page_test.dart`、`fund_detail_page_test.dart`、`fund_message_test.dart`；新增成员选择测试位于 `test/pages/fund/fund_recipient_picker_test.dart`。结构整理时继续保留原测试入口，新增测试按模块目录归属。

验证包含 Light/Dark、375×812、窄屏、横屏、大字体、加载失败、错误密码、超时恢复、账户/服务器切换、只看详情不领取、一次授权与一次领取。渲染预览位于 `docs/previews/`；它用于视觉检查，不能代替 iOS 真机与服务端测试账户联调。

订单缺省发送人兼容验证（2026-10-03）：224 项相关功能回归和 6 项日夜主题渲染通过。覆盖两端打开、群转账查看、服务器身份优先、展示资料隔离、订单号/金额不一致拦截与一次显式领取；6 个本轮分析目标无问题，共享聊天逻辑保留 4 项既有提示。Android debug APK 已构建，当前测试包为 `build/app/outputs/flutter-apk/app-fund-detail-debug.apk`，效果见 `docs/previews/fund-detail-sender-light.png` 与 `fund-detail-sender-dark.png`。定位时只读核对两个真实订单响应，回归和预览使用脱敏或模拟数据，未执行线上资金操作。下面保留此前验证记录。

祝福语和转账备注接入验证（2026-10-03）：201 项相关功能回归、16 项日夜主题渲染均通过，14 个分析目标无问题；覆盖码点长度、trim、空值默认、旧订单/旧待确认兼容、备注冻结、权威展示及现有支付保护。大字体横屏卡片沿用真实聊天列表验证滚动和点击。Android debug APK 已构建，测试包为 `build/app/outputs/flutter-apk/app-fund-remark-debug.apk`，效果见 `docs/previews/fund-remark-light.png` 与 `fund-remark-dark.png`。回归和预览使用模拟数据，线上资金和 iOS 真机尚未联调。

2026-10-03 原样式迁移验证：107 项资金场景及相邻模块共 134 项回归、26 个主题/页面渲染均通过，资金模块静态分析无问题，Android debug APK 已构建。

随后支付状态优化验证：176 项相关功能回归及日夜两项渲染测试（八张状态图）通过，12 个分析目标无问题；新增共享面板、发送重试和支付结果回传均覆盖。最终测试包为 `build/app/outputs/flutter-apk/app-payment-debug.apk`，当前效果见 `docs/previews/payment-status-light.png` 与 `payment-status-dark.png`。
