# 用户资金明细接口接入（2026-10-06）

## 数据入口

余额变动明细使用 `GET /chat/fund/journals`，通过 `WalletJournalSource.getJournalPage(WalletJournalQuery)` 获取当前登录用户的账本事件。生产实现为 `WalletFundRepository`，调用 `WalletFundApi.fetchJournals`；复用 `FundApi` 的 Chat API 地址、Chat token、每次请求独立的 UUID operationID 和安全错误处理。

查询支持 `currency`、`bizType`、`type`、`direction`、`startTime`（包含）、`endTime`（不包含）、`limit`（1–100，默认20）和不透明 `cursor`。不发送 userID、page/pageSize、offset，也不假设存在全量 total。`withCursor` 保留相同筛选条件；筛选改变后由列表状态清空游标，从首屏重新请求。

## 数据和分页约束

- `WalletJournalEntry` 保留接口全部字段，金额和余额维持原字符串；USDT/TRX 使用6位、BI99使用2位精度，以 BigInt 验证，不经过 double。旧流水 beforeAvailable/afterAvailable 为 null 时保持未知，不替换为零。
- 验证 assetDelta = availableDelta + frozenDelta，并按照原币资产变化区分 income、expense、freeze、unfreeze、neutral。冻结不代表支出，解冻退回不代表收入；neutral允许零操作金额。
- `WalletJournalPage` 保留服务器顺序及 hasMore/nextCursor。空的中间页仍可携带有效下一页游标；末页以 hasMore=false 结束，冗余 cursor 不改变结束状态。hasMore=true 缺少 cursor 则作为异常数据处理。
- 唯一身份是明细 id，同一 orderID 可以有多条事件。DTO mapper保留 id、原币金额、Unix毫秒时间、真实 title/remark/reason 和 orderID；hash只来自 chainTxID。
- counterpartyID 是 IM UID，未查询用户资料时不伪装成可展示账号。orderStatus 是订单当前状态，不将已入账事件改写为历史待处理／失败事件。
- 仓储创建时固定账号归属，在请求前后校验归属；换号期间的旧账号响应不得用于新账号页面。
- `walletJournalErrorMessage` 将1001解释为资金明细筛选参数错误，认证、服务、异常数据提供中文重试提示，不暴露原始服务诊断。

模型、查询、分页、来源接口、映射和错误提示集中在 `lib/pages/wallet/record/journals/`。旧 `/chat/fund/deposits` 及提现列表方法仍保留已有用途；不要将它们拼成完整用户账本。

## 数据层验证

新增18项测试覆盖接口字段、null余额、同订单多条事件、完整红包冻结／领取扣款／退回过程、五种方向、超过double与int范围的大额原币精度、查询筛选与游标、空中间页、无total、真实Dio请求参数与认证头、异常响应、1001中文提示和换号旧响应。

运行新增测试与 wallet_fund_api、wallet_fund_repository、fund_api 回归，共69项通过；涉及数据文件和测试的 analyze 无问题。测试使用合成账号与mock transport，未读取真实凭证、调用真实资金写操作或进行生产接口联调。

## 页面与最终验证

生产余额变动明细直接使用 journals，不再显示“仅最近100条链上充值”的提示。保留99chat页面、月份分组、全部／支出／收入页签、客服和下拉刷新。筛选新增业务、事件及冻结／解冻／无数量变动；99币向接口发送BI99，月份和日期范围使用包含起始、排除结束的Unix毫秒时间戳。

列表以20条一页按cursor继续加载，逐条懒构建；300条记录可通过15页滚动加载。页首刷新和筛选改变会废弃旧分页响应，换号和关闭页面也拒绝旧响应。后台／被覆盖期间推迟事件刷新，恢复后合并一次请求。分页失败保留已有列表和游标供重试；所有已接受游标按查询代记录，拒绝A→B→A等循环。

流水详情保留原币精度和未知余额，区分资产／可用／冻结余额变动；显示订单当前状态、流水ID、订单号、真实备注／调整说明及链上哈希。冻结和解冻都有清晰说明，不作为资产收支。

最终联合运行record模块及钱包API、仓储、FundApi相关回归：193项通过，6项旧可选截图导出未启用。生产与对应测试的scoped analyze无问题，diff-check通过，Android debug APK构建成功。真实账户接口联调与iOS设备验证尚未进行。

用户随后提供的200×200 RGBA `红包.png` 按原文件复制到record/assets/red_packet.png并注册。所有packet_*事件及旧红包列表优先展示原图；群转账保留原识别，详情顶部继续使用币种标识。图标修改后37项相关展示／布局／页面测试通过，2项可选预览测试导出6张列表及详情亮暗截图，已人工检查。预览使用测试夹具，保存于 `E:/openim/artifacts/wallet-journals/`。包含新图标的Android debug APK再次构建通过（12.8秒）。

用户补充要求圆形显示后，红包列表复用统一头像尺寸的CircleAvatar和圆形裁剪，背景采用钱包surfaceAlt主题色；完整原图缩小并居中，亮暗主题均有圆形底色。

随后退款图标使用用户提供的 `退款中.png`，原文件复制到record/assets/refund.png。packet_refund、withdraw_refund及旧退款／退回记录优先使用退款原图，继续圆形显示；发出、领取、冻结和扣款保留红包图。图标按真实流水事件识别，不能因关联订单当前已退款就改写原来的发出／冻结／扣款记录图标，也不把充值撤销误标为退款。

充值／提现类记录使用其原币对应图标，直接复用钱包已有WalletCoinLogo：USDT绿色币标、TRX红色币标、BI99／99平台币标，大小与明细头像一致。该规则覆盖deposit、deposit_reversal、withdraw及旧链上充值／提现；退款事件继续优先使用退款图标，保持亮暗主题一致。

用户随后提供TRX、USDT原图并要求硬编码。原文件分别复制到wallet/widgets/assets/trx.png及usdt.webp（USDT附件实际为WebP），按原色圆形显示；这两个已知币种优先使用本地资源，接口图片地址不能覆盖。钱包首页、充值／闪兑、资金明细列表及详情复用同一个WalletCoinLogo，替换旧USDT手工绘制和TRX着色／SVG图标。

币标组件归属共享wallet/widgets/wallet_coin_logo.dart；首页、充值、闪兑、提现、支付弹窗和明细的调用均直接使用此共享入口，保持原有尺寸、头像／角标及99币行为。旧首页目录中的币标实现没有生产引用。

## 红包与转账标题

按业务类型packet_normal、packet_lucky、packet_exclusive，将packet_sent／packet_freeze显示为“发出普通红包／发出拼手气红包／发出专属红包”，packet_received显示为“收到普通红包／收到拼手气红包／收到专属红包”。冻结方向单独显示在列表次级文字，扣款和退回保留原事件标题与方向说明。

单聊、群转账的transfer_sent／transfer_received显示“转账-对方用户昵称”。只根据counterpartyID调用现有OpenIM批量getUsersInfo资料方法，使用真实nickname，不使用account、好友备注或IM UID替代。查询暂失败／未提供昵称时显示“转账”。资料查询不阻塞流水加载，同一查询代内跨页去重并共享真实昵称；缺失资料可在后续页重试。首屏刷新成功后重查昵称，筛选、账号或登录令牌变化以及dispose均拒绝旧结果。

DTO保留原账本事件，并增加独立counterpartyNickname展示字段。页面只在仓储实现WalletJournalCounterpartySource时补充资料；生产WalletFundRepository默认使用OpenIM实现，可注入测试来源。列表和已打开详情通过现有ListenableBuilder同步接收昵称迟回，返回列表不重复查询。

本次联合回归240项通过，另2项实际昵称页面集成通过；8项可选截图导出默认跳过。新增29项标题组合、9项资料来源、9项异步控制器及2项页面测试，覆盖六种红包文案、真实资料批量方法、缺失／失败回退、跨页复用、迟回与会话隔离。生产与对应测试analyze无问题；亮暗预览已查看，预览昵称“测试好友”仅存在测试夹具。

## 明细详情参考卡片

按用户第二张截图，将余额明细详情改为单张主题圆角卡片：转账对方头像、昵称标题和大金额居中，主信息用左标签／右侧左对齐值。关联账单位于金额与主信息之间，其后保留细分隔线。普通流水去掉冗余方向说明，冻结／解冻保留资产数量不变的解释。用户随后要求移除“更多明细、商品说明、付款方式、余额”，当前卡片已经不渲染这四项，也去掉对应底部分隔线与展开区留白。

主信息显示真实发生时间、资产方向、对方用户、流水交易号及备注。金额继续以原币字符串展示，不按今日价格换算人民币；原账本余额和增减仍保留在模型中，null不转为零。PublicUserInfo没有公开account，故此处显示真实昵称并标为“对方用户”，不伪造99号、实名或掩码。新增可选资料能力getProfiles在同次既有SDK批量调用取得nickname和faceURL，旧getNicknames注入仍兼容；头像/昵称迟回同步更新已打开的详情。

非空orderID的“查看账单详情”使用既有WalletFundApi.getOrder读取真实关联订单。订单金额与本次流水操作金额分别保留（例如订单10 USDT、退回事件8 USDT），不把退款或领取数量当成订单总额。只读账单支持失败重试、请求去重、订单ID校验、页面关闭及账号／令牌变化后的迟回隔离；提现广播成功仍只显示“已提交链上”。

硬编码币种资源检查：两张原图按原字节保留，注册到wallet/widgets/assets；TRX为192×192 PNG，USDT附件实际为192×192 WebP。明细列表与详情的亮暗截图均确认使用用户图。此前扩大运行的首页旧测试有15项与当前首页合同不一致：10项CNY文本旧点击高度要求、3项未知估值旧`--`要求、2项已移除的USD菜单；这些字段与图标无数据／布局依赖，本次未修改其合同或断言。

转账流水列表随后按用户截图改为对方圆形头像。transfer／group_transfer的transfer_sent／transfer_received复用同一批真实资料的counterpartyAvatarUrl；群转账也显示明确对方用户，不能替换成群头像、方向箭头或99币图标。缺少头像或加载失败时显示昵称首字，昵称未提供时显示问号。昵称及头像迟回同时更新列表和已打开详情，不新增资料请求，红包／退款／充值提现图标规则保持。

头部合并检查确认，另一并行对话中的用户已要求移除筛选／客服按钮、币种筛选摘要与清除条，并将总页改为“历史记录”、币种页改为例如“TRX变动”。此处保留当前已授权的头部实现，不再恢复已移除的入口。列表仍支持收支切换、月份选择、刷新与cursor分页；接口筛选参数和控制器筛选逻辑继续由数据层测试覆盖。

本轮最终验证：journals全模块与wallet_fund_api／wallet_fund_repository／FundApi联跑202项通过，4项可选预览默认跳过；单独启用两种预览define后4项全部导出。精简详情、头像、迟回同步及视觉回归39项通过，充值／闪兑页面相关27项通过；生产与对应journal测试analyze无问题、diffcheck通过。精简后的Android debug APK于11:07构建成功（13.8秒），亮暗预览已目视检查。真实资金账户与iOS设备验证仍未进行。

扩大record模块的旧模式回归曾有21项头部合同差异：10项旧筛选入口、10项旧客服入口和1项旧“余额变动明细”标题。这些断言对应用户已授权移除的旧界面，本轮未修改旧模式测试；本轮journals测试已按当前方向／月份／分页和无actions标题合同验证通过。
