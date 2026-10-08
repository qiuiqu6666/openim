# 三公 Go v2 接口与 Flutter 接入

本文对应 `/www/wwwroot/openimservice/sangong` 和当前 Flutter 实现。Go 模块编译进 OpenIM Chat API/RPC；三公账务继续使用独立的 MySQL 表，OpenIM 的消息库与 Chat MongoDB 不承担余额记账。可以共用数据库服务器，不能把三公余额存进 OpenIM 自定义字段。

2026-10-07 22:23（UTC+8）已在当前部署切换到 Go：Chat API/RPC 同步启用，原 Java 三公服务已停止并禁用开机启动。新版不再沿用 Java 的账号默认配置、v1 游戏接口或三公 SSE。旧版接口文档仅供迁移对照。客户端源码已同步，Android/iOS 安装包构建不属于本次服务端发布结果。

## 1 请求约定

下注群资源前缀记为 `G=/sangong/api/v2/groups/{groupID}`，代理群资源前缀记为 `A=/sangong/api/v2/agent-groups/{agentGroupID}`。ID 来自当前 OpenIM 群，作为不透明字符串使用，并对路径段执行 `Uri.encodeComponent`。一次请求只操作路径中明确绑定的租户。

所有三公请求均使用以下请求头：

```http
Authorization: Bearer <原始 Chat 登录 Token>
operationID: <每次 HTTP 请求的 UUID>
Content-Type: application/json
```

Token 复用现有登录状态，不是 OpenIM SDK 的 IM Token，也不另建三公登录。无需 `X-Tenant-Id`。客户端构建默认使用当前 Chat 地址和 `/sangong` 前缀；自定义地址只能改变服务位置，不能赋予租户权限。

页面接口要求账号为特权用户；普通群成员继续发群内文字指令。每次请求仍核对真实 OpenIM 成员身份。运营写入还需群管理员/群主身份与本租户 `owner/admin` 授权。配置保存、权限变更及绑定代理群需要本租户 owner；绑定代理群还需该代理群管理员身份。

查询、配置接口响应：

```json
{"ok":true,"data":{"version":12}}
```

命令统一为 `POST G/commands/{action}`：

```json
{"requestId":"3acf8655-0580-4222-a4cb-c3dc18b2e5cf","input":{"roundId":18}}
```

成功响应：

```json
{"ok":true,"requestId":"3acf8655-0580-4222-a4cb-c3dc18b2e5cf","data":{}}
```

`requestId` 是业务幂等键，和 `operationID` 分开。一次操作超时或结果未知时，重试必须保留相同 requestId 和完全相同的 input；修改操作内容后生成新键。客户端必须核对回执 requestId，不能只凭 HTTP 200 或空对象显示成功。`round.*`、`bet.*` 都需要所确认的 roundId；`session.stop` 需要 sessionId，避免把旧页面操作应用到新局或新批次。

积分、下注、余额、额度均为整数；不要使用浮点数记账。开奖使用 `amountHundredths` 整数 1–100 表示 0.01–1.00。返水设置 `rate` 是百分比字符串，例如 `"0.1234"`，保留最多 4 位小数。`groupId` 若出现在积分筛选中是数值分组编号，区别于 URL 的 OpenIM groupID。

## 2 进入群聊及当前群配置

1. 复用现有账号特权检查和 OpenIM 群资料缓存。普通账号不拉三公私有页面数据。
2. 通过 Chat 的 `GET /chat/groups/{groupID}/feature-capabilities` 确认当前账号能力。此接口沿用 Chat 请求头 `token: <Chat Token>`、`operationID` 和 `{errCode,errMsg,data}` 包装，不能套用三公 Bearer 响应解析。
3. 特权群管理员进入三公群时执行 `GET G/config`，定点判断当前群是否配置。不要请求 `/admin/my-config`，不要把账号默认租户代入当前群。
4. 明确 `configured:false` 时显示“配”；网络失败、无权限和停用租户不能当成未配置。
5. 配置与能力确认后执行一次 `GET G/snapshot`，同时获得规则、当前局、批次、开奖和状态条。以后接收 OpenIM 消息状态；页面按需读取用户或代理私有数据。

### 查询和保存

| 方法 | 路径 | 请求体 |
| --- | --- | --- |
| GET | `G/config` | 无 |
| PUT | `G/config` | 下方配置对象；初始化与更新共用此接口 |

未配置响应的 data：

```json
{"ok":true,"configured":false,"groupID":"game-B","canInitialize":true}
```

初始化示例：

```http
PUT /sangong/api/v2/groups/game-B/config
Authorization: Bearer <Chat Token>
operationID: <UUID>
Content-Type: application/json

{
  "name":"B群三公",
  "imBotUserId":"bot-B",
  "imGroupAdminStatsId":"stats-B",
  "imGroupLedgerId":"ledger-B",
  "imGroupWaterId":""
}
```

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| name | string | 厅名，最长 128；新租户为空时以群 ID 命名 |
| imBotUserId | string | 已注册的独立机器人 OpenIM 用户 ID，最长 64 |
| imGroupAdminStatsId | string | 管理账单和关机返水表接收群，可空；空时不能发该类账单 |
| imGroupLedgerId | string | 可指定的积分表接收群，可空 |
| imGroupWaterId | string | 保留的返水群配置；不能据此推断代理群绑定 |
| active | bool | 更新启停；新建始终 active=true；运行期间部分变更会被拒绝 |
| imGroupGameId | string | 可省略；如提供必须等于 URL 当前群，不能改绑另一个下注群 |

更新是按已提供字段修改，省略字段保持原值。保存不需要业务命令信封，也没有 requestId 字段；成功后使用返回配置更新当前群缓存，并刷新能力。

已配置 data 包含 `configured, groupID, tenantId, name, imGroupGameId, imGroupAdminStatsId, imGroupLedgerId, imGroupWaterId, imBotUserId, active, myRole, canInitialize, canClaim, canEditConfig, canManageMembers, debitAllowOverdraft, sessionStatus`。`active:false` 仍然是 configured。无人认领的历史租户可能 `canClaim:true`，允许符合条件的管理员保存并原子认领；竞争保存不会产生两个并发认领者。

### 租户运营授权

| 方法 | 路径 | 输入与返回 |
| --- | --- | --- |
| GET | `G/access` | data.members，每项 `imUserId,role,isDefault` |
| POST | `G/access` | `{"imUserId":"helper","role":"admin"}`；owner 可授权 owner/admin |
| DELETE | `G/access/{imUserId}` | 无请求体；移除本租户授权 |

最后一个 owner 不能被移除或降级。授予三公 admin 不等于授予 OpenIM 管理员身份；实际运营仍核对两层权限。特权资格同样独立。

## 3 游戏状态和操作顺序

推荐顺序：读取 snapshot → `session.start` → 可选 `rules.update` → `round.banker` → `round.open` → 群下注/撤注 → 预览 → `round.close` → 等待 `collectionReady` → `round.draws` → `round.settle`。`round.banker` 传 `openBetting:true` 可合并定庄和开放下注。合庄可在允许阶段添加、移除和关闭。

`GET G/snapshot` 的 data 包含：

| 字段 | 用途 |
| --- | --- |
| schemaVersion | 固定 2 |
| version / at | 当前提交版本、服务端时间；0 是新群有效初始版本 |
| groupId / tenantId / botUserId | 当前群、租户及可信状态消息机器人 |
| status / session | 总状态；批次 id、batchNo、periodNo、currentRoundId、startedAt、stoppedAt |
| settings | doorCount、minBet、maxBet、rakePercent |
| round / lastSettledRound | 当前局、最近有效结算局；无则 null |
| round.coBank | poolTotal、成员列表及主庄/合庄比例 |
| draw | 各门开奖、缺失门位与 complete |
| placed | 已生效下注 doorTotals、grandTotal、betCount；即时扣分后的展示依据 |
| pending | 消息收集状态；不能将其理解为未扣分资金 |
| collectionReady | 截止历史消息及撤回核对是否完成 |
| me | 本人私有余额资料，未登记时 null；不放进公开消息 |
| canManage / canBet / canSettle / canRecordDraws | 当前状态下服务端操作提示；提交时再次鉴权 |

局状态有 `await_banker, await_banker_door, betting, co_bank_closed, settled, voided`。下注开放还取决于 betWindowOpenAt、betWindowCloseAt 和 drawLockedAt，不能只看 status 字符串。

所有下列命令均为 `POST G/commands/{action}`。表中是 input，不是整个请求体。

| action | input | 行为 |
| --- | --- | --- |
| session.start | `{}` | 新建经营批次和第一局 |
| session.stop | `{"sessionId":2}` | 未结算局退款作废，自动领取返水并生成最终管理账单；余额保留 |
| rules.update | `{"doorCount":6,"minBet":10,"maxBet":10000,"rakePercent":5}` | 2–10 门；限额非负，maxBet=0 表示不设最大值；庄抽水 0–100 整数；定庄前修改 |
| round.banker | `{"roundId":18,"imUserId":"banker","nickname":"庄家","door":1,"bankerLimit":5000,"openBetting":true}` | 定庄；也可使用本租户 userId；定庄时冻结本局规则 |
| round.open | `{"roundId":18}` | 开放下注并排队发送庄家通知 |
| round.co_bank | `{"roundId":18,"userId":9,"amount":1000}` | 管理员设置合庄额度 |
| round.co_bank_remove | `{"roundId":18,"userId":9}` | 移除合庄成员 |
| round.co_bank_close | `{"roundId":18}` | 关闭合庄 |
| round.co_bank_notice | `{"roundId":18}` | 排队发送合庄通知 |
| round.close | `{"roundId":18}` | 截止到服务端核对的当前消息边界 |
| round.close | `{"roundId":18,"untilMsgSeq":120,"excludeMsgSeqs":[118]}` | 截止到所选消息；排除明确消息；排除边界后的有效下注，录入开奖号成功时退款 |
| round.draws | `{"roundId":18,"draws":[{"door":1,"amountHundredths":36}]}` | 录入门位开奖号；结算前必须齐全 |
| round.settle | `{"roundId":18}` | 按 1:1、统一庄抽水结算，返佣入待领记录，排队发送四类结算报表 |
| round.reverse | `{"roundId":18}` | 冲正该局实际结算入账和返佣，清空开奖号，废弃旧自动报表 |
| round.resettle | `{"roundId":18,"draws":[所有门位]}` | 同一事务冲正并按替换开奖号重结；失败保留原结算 |
| round.next | `{"roundId":18}` | 从已结束局进入下一局 |
| round.restart | `{"roundId":18}` | 退回当前未结算局下注，作废后新建下一局 |
| bet.place | `{"roundId":18,"bets":[{"door":2,"amount":100}]}` | 本人下注，成功立即扣分 |
| bet.proxy | `{"roundId":18,"userId":9,"bets":[{"door":2,"amount":100}]}` | 管理员替指定本租户用户下注 |
| bet.cancel | `{"roundId":18}` | 截止前取消本人本局有效下注并退款 |
| user.join | `{"nickname":"玩家"}` | 登记本人；群内有效指令也可触发登记 |

已成功撤注退款的记录不会因历史截止点前移而恢复扣分。群消息 seq 必须是 OpenIM 服务端已落库的消息序号；不能传本地消息时间、列表索引或 clientMsgID。历史核对尚未完成时应等待状态更新，不自行显示“全部落注完成”。

`round.*` 与 `session.*` 的成功 data 带同次提交 `state`；直接应用该状态，避免再请求 session、settings、draws、snapshot 四次。不同操作还返回 round/session/refundedAmount 等结果，不把缺失金额默认为成功。

## 4 用户积分和账务

| 方法/命令 | 参数 | 说明 |
| --- | --- | --- |
| GET `G/users` | beforeId、limit、groupId 可选 | 游标用户目录，返回 users、total、nextBeforeId、version |
| GET `G/user` | imUserId 必填 | 返回 exists、user、parent；未登记与服务错误分开 |
| POST `G/commands/user.ensure` | `{"imUserId":"u","nickname":"玩家"}` | 登记当前群实际成员 |
| POST `G/commands/user.group` | `{"imUserId":"u","group":"甲组"}` | 设置本租户积分分组 |
| POST `G/commands/wallet.adjust` | `{"imUserId":"u","delta":100,"note":"上分"}` | 正数上分、负数下分；也可用 userId，但不能同时提供两个身份字段 |
| POST `G/commands/wallet.limit` | `{"userId":9,"maxNegative":500}` | 设置非负的可负额度；不能只改客户端展示 |
| GET `G/balance` | 无 | 本人当前余额资料 |
| GET `G/ledger` | userId/imUserId 二选一；sessionId、beforeId、limit 可选 | 管理员查租户用户；其他账号仅允许自身授权范围 |
| GET `G/user-report` | imUserId 必填；date 或 sessionId 二选一；beforeId、limit | 一次获取用户资料、统计、流水与合庄记录 |
| GET `G/sessions` | beforeId、limit | 经营批次选择 |
| GET `G/rounds` | sessionId、beforeId、limit | 局记录 |
| GET `G/settings` | 无 | 单独规则查询；游戏页优先复用 snapshot.settings |

游标 limit 最大 100；nextBeforeId=0 表示该列表无后页。不要把用户 ID、OpenIM ID、公开账号名混用。Flutter 的公开账号输入先复用联系人搜索，精确匹配账号取得 OpenIM userID，再查询本租户 user；写入之间若账号或群已变更，应放弃旧结果。

`user-report` 的 date 是上海时区经营日，即该日开始的批次，包含跨午夜延续的批次；不是按每笔流水自然日随意过滤。未传 date/sessionId 时按服务端当前批次范围查询。

data 包含 `version,user,parent,summary,aggregation,date,session,entries,totalEntries,nextBeforeId,coBankFlow,coBankHasMore`。entries 每项有 `ledgerId,userId,imUserId,nickname,sessionId,periodNo,type,amount,balanceAfter,refType,refId,note,operator,createdAt`。合庄列表是额度、占比与庄家结算表现，不是又一次积分扣款；仅首个游标页返回，超过 500 条时 coBankHasMore=true。

当前 Flutter 最多读 5 页流水，共 500 条，并明确显示已读取范围和服务端总条数。后页必须与首页 version 一致；版本变化时重新读取，不能拼接两份账务状态。切换批次、日期、账号、群和权限后丢弃旧请求；资料修改成功后，较早开始的报表响应不能把额度或比例改回旧值。

## 5 下注预览与五类 Java 报表

`GET G/bet-preview?roundId=18` 可附带 `untilMsgSeq,excludeMsgSeqs,beforeId,limit`。excludeMsgSeqs 使用逗号分隔正整数，最多 100 个，不重复。返回 version、nextBeforeId 和 preview，preview 包含 roundId、pendingMessageCount、report；report 含用户/各门总额和明细。分页只读取明细，不能把不同 version 的分页合并。

统一发送接口：

```http
POST /sangong/api/v2/groups/game-B/commands/report.send
Authorization: Bearer <Chat Token>
operationID: <UUID>
Content-Type: application/json

{"requestId":"<持久保留的操作 UUID>","input":{"kind":"settlement","roundId":18}}
```

| kind | 额外 input | 输出及默认接收群 |
| --- | --- | --- |
| bets | roundId 必填；可带 untilMsgSeq/excludeMsgSeqs | Java 下注清单图片 → 下注群 |
| settlement | roundId 必填 | Java 结算明细图片 → 下注群 |
| points | 可带数值 groupId；可带 targetGroupId | Java 积分图片 → 下注群；指定目标只允许当前下注群或已配置积分群 |
| trend | 无 | 当前批次最近 12 个有效结算局走势图 → 下注群 |
| bill | roundId 必填 | Java 管理群账单 `.xlsx` → imGroupAdminStatsId |

响应示例：

```json
{"ok":true,"requestId":"原请求ID","data":{"queued":true,"sent":false,"reportId":"稳定报表ID","deliveryIds":["待发送ID"],"pageCount":1,"targetGroupId":"game-B","type":"settlement","roundId":18,"message":"图片报表已加入发送队列"}}
```

`queued:true` 表示任务已可靠入库，不代表已送达群。重复相同 requestId 不产生第二份任务。前端提示“已加入发送队列”，并通过 OpenIM 群消息确认送达；没有独立的客户端发送图片接口。

Java 对照要求：

- 下注清单保留总注、庄门、各门明细和按下注总额/昵称排序；自动截止核对完成后先发文字汇总，再发图片。
- 结算明细保留庄家汇总、合庄比例、流水、抽水、各门金额、玩家结算前后积分；财务数字在结算事务冻结，重发旧局不取当前余额替代。
- 积分表仅列非零积分，按绝对值、实际积分、昵称排序，保留合计。
- 走势图保留最近 12 局，正序展示，不足补空行。
- 管理群账单保留汇总、个人流水、庄流水、上下分，代理覆盖至少 5 名不同用户时独立工作表，否则归“其他”；保持列名、分组合计、金额类型、合并单元格及包费显示。
- 图片沿用 Java 字体、橙绿配色、字号、列宽、头像和分辨率规则。AWT 与 Go 抗锯齿不同，验收需分清内容/版式一致与逐像素相同。

结算自动发送顺序为结算图、积分图、走势图，账单发管理群。关机自动领取返水后，发送用户返水表、代理返水表和最终管理账单。重开、重新截止、冲正、重结会作废旧自动报表，撤回已发送旧消息；结果未确认的发送先核对原回执，避免重复发送或撤错消息。

## 6 多级代理

代理群独立于下注群；一个代理群只能绑定一个下注群租户。owner 在下注群设置中操作：

| 方法/命令 | 参数 | 用途 |
| --- | --- | --- |
| GET `G/agent-groups` | 无 | 已绑定代理群 |
| POST `G/commands/agent.group_bind` | `{"agentGroupId":"agents-B"}` | 绑定独立代理群；不会把下注群变成代理群 |
| POST `G/commands/agent.attach` | `{"userId":9,"parentUserId":8}` | 设置未建立上级的成员关系；禁止环和跨租户 |
| POST `G/commands/admin.rebate_rate` | `{"userId":8,"rate":"0.5"}` | 管理员设置成员返水比例 |
| GET `A/context` | 无 | 当前群绑定、当前代理身份；未绑定不能从账号默认厅兜底 |
| GET `A/balance` | 无 | 本人余额 |
| GET `A/team` | direct、imUserId、sessionId/batchNo、beforeId、limit | 团队/直属列表；只读授权下级 |
| GET `A/team-summary` | direct、sessionId/batchNo、beforeId、limit | 团队汇总 |
| GET `A/member` | imUserId 必填；sessionId/batchNo | 成员汇总 |
| GET `A/member-daily` | imUserId 必填；batchNo 或 from/to | 日期/批次明细 |
| GET `A/transfers` | direction=all/in/out；sessionId、beforeId、limit | 积分划转记录 |
| GET `A/ledger` | sessionId、beforeId、limit | 本人流水 |
| POST `A/commands/agent.rate` | `{"userId":9,"rate":"0.2"}` | 当前代理设置直属下级比例 |
| POST `A/commands/agent.transfer` | `{"imUserId":"child","amount":100}` | 向授权下级划转；也可用 userId，两者不能同时填 |
| POST `A/commands/rebate.claim` | `{}` | 领取本人可领取返水 |

sessionId 和 batchNo 不能同时传；batchNo 和 from/to 不能混用。rate 采用百分比字符串，必须遵循上级 ≥ 本人 ≥ 下级，服务端校验，不在 Flutter 用浮点数计算收益。不同下注群的相同 OpenIM 账号具有独立的三公 userId、余额、代理树和返佣。

### 6.1 用户归属代理群（2026-10-08 新增）

这组接口保存“当前下注群内的某个用户归属哪个代理群”。与 `agent.group_bind` 的群级绑定、`agent.attach` 的代理上下级，以及隐藏的积分分组互相独立；不改变余额、返水比例、代理树或代理群访问权限。每个用户在每个下注群最多归属一个代理群，不从群成员列表或代理树自动推断。

**查询**：`GET G/user-agent-group?imUserId=<OpenIM用户ID>`。必须传 `imUserId`，不得传公开账号或三公数字 userId。成功响应：

```json
{"ok":true,"data":{"userId":9,"imUserId":"im_target","agentGroupId":"agents-B","gameGroupId":"game-A","version":12}}
```

没有归属时 `agentGroupId` 为 `null`；该用户尚未建立当前下注群的三公账户时返回 `USER_NOT_FOUND`，不要把它当作已有用户的空归属。

**保存或更换**：`POST G/commands/user.agent_group`：

```json
{"requestId":"<UUID>","input":{"imUserId":"im_target","agentGroupId":"agents-B"}}
```

成功响应：

```json
{"ok":true,"requestId":"<同一UUID>","data":{"userId":9,"imUserId":"im_target","agentGroupId":"agents-B","gameGroupId":"game-A","version":13}}
```

**清除**：调用同一保存接口，显式传 `"agentGroupId":""`。不要省略字段或传 `null`。回执中的 `agentGroupId` 为 `null`。

查询与保存均要求当前下注群的特权账号、真实 OpenIM 群管理员/群主身份及本租户 `owner/admin` 授权。保存还校验目标用户是当前下注群真实成员、三公账户有效。独立代理群入口 `A` 不提供这些管理操作。所有写入继续使用统一幂等和审计记录，相同请求重试不重复写入事件。

可选群读取 `GET G/agent-groups`（`data.agentGroupIds`），再用现有 OpenIM 群聊列表/群资料显示群名与群头像，按 groupID 匹配。选择器可以复用已有群聊列表，但只允许选已绑定当前下注群的代理群；未绑定需先由有权限的 owner 使用 `agent.group_bind`，不在保存用户归属时自动绑定。群名和群头像不由此接口重复存储。

错误：`AGENT_GROUP_NOT_BOUND` 表示先绑定当前下注群；`AGENT_GROUP_TENANT_MISMATCH` 表示绑定其他下注群；`INVALID_GROUP` 表示群标识无效；`INVALID_INPUT` 表示参数缺失/格式错误；`FORBIDDEN` 表示权限或成员资格不符；`IDEMPOTENCY_CONFLICT` 表示复用了不同内容的幂等键。

用户详情接入：使用当前页面绑定的下注群 ID 查询；公开账号仅用于显示，请求使用用户资料里的内部 IM 标识。保存确认回执后重新查询。关闭页面、切换登录/群或权限变化时丢弃迟到结果。更换选择生成新 requestId；超时重试保留原 requestId 和 input。

服务端新增迁移 `035_go_user_agent_groups.sql`，单独保存租户、用户、代理群、操作人及更新时间。先应用迁移，再更新 Chat RPC；不迁移已有积分分组或代理树数据为用户归属。

## 7 OpenIM 自定义字段与减少请求

群摘要位于 `GroupInfo.ex.groupFeatures`。保留 ex 中其他字段和其他游戏配置，由 Chat 的统一群资料同步任务写回：

```json
{
  "gameType":1,
  "groupFeatures":{
    "schemaVersion":1,
    "revision":25,
    "capabilityVersion":11,
    "games":{"sangong":{"enabled":true,"manageEntry":true,"agentEntry":false,"rebateHistoryEntry":true}}
  }
}
```

gameType=1 对应运营浮窗，gameType=4 对应独立代理浮窗；它们表示群类型，不授予权限。群资料同步保留既有 gameType，不把群类型变更混入每条游戏事件。

`revision` 用于忽略迟到群摘要；`capabilityVersion` 变化时使缓存的私有能力失效，即使四个入口布尔值没变化，也重新校验权限。配置、授权、代理绑定及比例变化通过 SQL 待同步记录 → Chat MongoDB 规范记录/待同步任务 → OpenIM 群 ex 持久化同步。失败重试，保留直播和其他游戏字段。公开 ex 不放 owner、角色、余额、返水比例或下级名单。

游戏状态随可信机器人发送的已落库消息出现在 `Message.ex.sangong`：

```json
{
  "marker":"sangong-go:<eventId>",
  "sangong":{
    "type":"sangong.event",
    "schemaVersion":2,
    "eventId":"事件ID",
    "groupId":"game-B",
    "version":13,
    "event":"round.settled",
    "state":{"schemaVersion":2,"groupId":"game-B","botUserId":"bot-B","version":13}
  }
}
```

上方 state 为字段示意，实际消息携带完整公共 snapshot，包括 settings、round、placed 等；不含 me 和私有管理能力。事件中不得用当前数据库新状态冒充旧 version。

Flutter 接受事件前核对群、sendID=可信 snapshot.botUserId、非空 serverMsgID、正数 seq、schemaVersion、eventId 及 state.version 一致。初次 HTTP 完成前可暂存消息，身份确认后再应用。重复/旧版本忽略；断线重连、前台恢复、版本缺口重新拉一份 snapshot 校准。普通成员伪造同名昵称、文本或 ex 都不能更新管理状态。

报表消息另用 `Message.ex.sangongReport={schemaVersion:2,reportId,deliveryId,kind}`，以 OpenIM 原生图片/文件消息呈现；它不代替游戏状态事件。头像、文件 URL、Token 也不放进 groupFeatures。

减少请求的具体做法：

1. 同一账号/群共用 GroupFeatureStore、SangongRuntime；聊天浮窗和其子页面复用当前实例，不各建轮询。
2. 群资料只决定入口候选，私有能力按版本缓存；未变更时不重复读取。
3. 首屏 snapshot 聚合规则、局、开奖和状态，后续优先用命令回执 data.state 与 OpenIM 状态消息。
4. 用户详情首屏使用 user-report 聚合接口；不并行请求资料、汇总和流水三份接口。
5. 代理页面只拉可见页签；日期、批次、分页使用固定上下文，权限失效立即清理私有缓存。
6. 报表生成全部由后端排队；前端不下载图片再上传，也不轮询每一份报表。

## 8 错误和发布验收

错误按 HTTP 状态及 body 的 code/message 处理，不能把缺字段当成功。常见错误：

| 类别 | 处理 |
| --- | --- |
| UNAUTHORIZED / 登录失效 | 走原 Chat 登录失效流程 |
| GAME_PRIVILEGE_REQUIRED / FORBIDDEN / TENANT_ACCESS_DENIED | 隐藏私有操作、清理该上下文私有数据，不能自动换租户重试 |
| GROUP_NOT_CONFIGURED / AGENT_GROUP_NOT_BOUND | 对应当前群配置/绑定，不使用账号默认群 |
| ROUND_CHANGED / SESSION_CHANGED | 提示刷新，让用户重新确认当前局/批次 |
| RULES_LOCKED / DRAWS_INCOMPLETE / 状态冲突 | 保留输入，按服务端提示修正；不自动重放到另一局 |
| 消息边界核对未完成 | 等待 collectionReady 或后续状态，不提前结算 |
| 网络超时 / 502 / 回执不完整 | 结果未知；保留原 requestId，核实或显式重试 |
| REPORT_GROUP_MISSING | 配置管理账单接收群后再提交 |

本次服务端切换已完成：独立数据库集成测试、Java 报表样本核对、475 项 Flutter 回归、真实 OpenIM 群下注/撤回/截止/结算/报表链路，以及数据库备份恢复演练。维护窗口中先停止 Java 和旧入口，确认任务排空，再应用 MySQL 026–032 迁移并显式转移执行权，随后启动 Go Chat API/RPC。两个实际群的配置、状态、用户、批次、能力接口已用现有登录会话验证；无效 Token 返回 401，旧游戏接口返回 410。不能让两个执行器同时处理同一租户。Android/iOS 安装包仍需各自的构建与设备验收。

实现入口：`api/service.go`、`api/query.go`、`engine/service.go`、`storage/mysql/game_queries.go`；Flutter 对应 `lib/pages/group_features/sangong/api/` 与 `services/realtime/`。该契约的金额和路由以这些实现及集成测试共同校验。

### 详细报表中心（管理权限）

新增只读 `management-summary`、`management-users`、`management-teams`、`management-round`。群主和获授权帮工可读，普通成员拒绝访问；租户仍由当前群确定。

前三者支持 `sessionId`，省略取最近经营批次。用户/团队列表支持 `beforeId`、`limit`、`search`（昵称包含匹配或完整 IM 用户 ID，最长128字节）。牌局详情要求 `roundId`，只能查询本群牌局，已结算明细来自冻结快照。

`ledger` 增加可选 `type` 精确筛选，返回昵称、IM 用户 ID、操作人，保留金额、账变后余额、来源与备注。分页末页 `nextBeforeId=0`。总览是全批次统计，当前积分及当前运行状态明确属于实时数据。作废或已冲正结算不计入有效结算汇总。

### 返水账变凭据

`user-report.entries` 与 `ledger.entries` 的用户/代理返水账变增加可选 `rebate`：`turnover`（流水）、`rate`（百分比字符串）、`amount`（实际入账金额）、`claimType`（MANUAL/AUTO）、`accountType`（PLAYER_REBATE/AGENT_DIFF）、`turnoverBasis`（unclaimed/team_total）。用户记录的是本次未返流水；代理记录团队累计有效流水与本人配置比例，金额仍按分支比例差额计算。以上值与入账在同一事务保存，不随当前配置变化。旧记录缺失此字段时不得推算历史比例，也不得再次入账。用户详情上下分列表展示这些既有账变及返水冲正，人工上下分与返水合计分别统计。
