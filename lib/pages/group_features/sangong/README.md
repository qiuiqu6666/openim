# 三公模块迁移说明

参考：本地 `reference-99chat` 提交 `d7c3c65`，Apache-2.0。迁入源码已标注来源，完整许可证保存在 `LICENSE-99chat`。此模块没有新增资源或依赖，不需要修改 pubspec。

## 入口与布局

资料页三公服务卡、游戏管理、流水及宽屏右栏已接入联系人资料页；消息长按统计、不计入和定庄已接入实际消息行。具体布局、身份与权限边界见 [资料页子模块](profile/README.md)。服务展示读取当前完整用户资料的 `isPrivileged`，私人数据及操作仍沿用群级能力与已确认租户。

对外入口为 `sangong_module.dart`。`SangongFeatureHost(featureContext: ..., builder: ...)` 每个账号／群只拥有一份运行状态；builder 接收 `(scopeContext, statusBanner, overlay)`。状态条放聊天正文的 Column 顶端，overlay 放同一正文的 bounded Stack，例如 `Positioned.fill(child: overlay)`。默认返回 bounded Stack，不能放进无高度约束的 ListView。菜单调用可传 `runtime: SangongScope.read(scopeContext)`，共用绑定缓存和状态。

`SangongModule.openManage` 提供运营／首次配置；`openAgent` 的 section 为 `dashboard`、`team` 或 `personal`。代理浮窗“查”打开查询下级，“团”打开团队统计，“个”打开当前用户个人数据。独立打开时创建路由所有的运行实例，退出后释放；主聊天浮窗打开的页面共用主聊天实例。

运营浮窗的截、结和四类报表分别执行原操作，“设”直接打开游戏规则。运营未就绪时先刷新群能力，再定点查询当前下注群的租户；恢复权限后继续本次操作。只有当前群查询返回 HTTP 404 且错误码精确为 `TENANT_NOT_FOUND`，才进入未配置状态并向特权账号显示“配”；当前群群主／管理员可用 POST 初始化，其他成员查看只读配置入口。已配置但无法运营时显示具体原因与重试。`canConfigure` 是配置操作权限，不能证明该群已经配置，也不能将 false 解释为租户不存在。

debug 模式下未派发运营请求的检查也输出 `[三公API]` 诊断，包括公开 `enabled/manageEntry`、私有 `canManage`、逻辑租户及已读取的当前群配置绑定。`gameType=1` 与 `canManage=true` 单独都不能替代其余运营条件；业务请求优先发送已确认的逻辑租户头，构建配置租户只作后备，不能替代当前群确认。

群聊右侧运营浮窗（截／结／图／账／分／势／设／隐）还要求群资料 `ex` 为 JSON 对象且顶层数字 `gameType=1`。`gameType=0`、`2`、缺失或非法扩展资料均隐藏该运营浮窗；账号特权和已保存的浮窗隐藏偏好继续生效。类型单独由共享仓库传入 `GroupFeatureContext.gameType`，不依赖 `ex.groupFeatures` 是否存在或版本是否变化。收到后台群资料更新后即时显示／隐藏，不覆盖其他扩展字段，也不授予运营、绑定或投注权限。

| 99chat 页面／组件 | 已迁入布局与真实操作 |
| --- | --- |
| group_game_floating_entry | 58px 圆形按钮、边缘收起／展开、拖动吸附与位置保存；展开依次截止、结算、结图、账单、积分、走势、设置、隐；特权账号精确确认未配置时显示“配”，提交初始化另要求当前群管理身份 |
| group_game_status_banner | 蓝色状态条、2–10门、6门原有间距、庄门高亮、下注窗口预录入与截止后落注分别显示 |
| sangong_agent_floating_entry | 查／团／个／隐，58px圆钮，与运营浮窗独立展开及定位 |
| sangong_manage_home_page | 游戏规则、冲正重结、配置、全部用户；按真实能力显示当前群配置入口，默认配置模式保留成员管理 |
| sangong_my_config_page | 当前群模式固定下注群，用 POST 初始化／PUT 更新返回租户，厅名与报表群可为空、机器人必填；默认配置模式保留原 GET／PUT my-config 和表单校验；机器人支持公开账号名解析 |
| sangong_game_rules_settings_page | 门数、最小／最大下注、赔率等完整原表单；开机／关机及冲正重结确认 |
| sangong_members_page | 角色排序、公开账号名添加帮工及输入确认、移除帮工确认、错误重试 |
| sangong_all_users_page / user_detail | 分页用户列表、公开账号精确查找与已加载昵称／ID筛选，积分／流水／合庄记录及可负额度设置；流水支持小屏滚动并注明最近500条范围；消息指令由实际 IM 消息桥接联调 |
| sangong_agent_dashboard_page | 团队统计、会话／批次汇总、成员数据及详情入口 |
| sangong_agent_team_page | 团队／直属筛选、搜索、成员详情、积分划转确认、划转记录 |
| sangong_agent_personal_page / member_detail | 当前登录 OpenIM 用户的个人数据、日期／批次、返水申请、收益及明细；不借用他人身份 |
| sangong_agent_transfers_page | 划入／划出筛选、场次过滤、按服务端记录排序、复制真实编号 |
| sangong_bet_preview_sheet / round_settle_dialog | 下注预览及截止确认；各门开奖录入、原生数字键盘、结算及冲正重结 |

复用项目现有 SettingsScaffold、SettingsGroup、SettingsCell、SettingsInputCell、SettingsPrimaryButton、AppTokens 和 EasyLoading。保留参考页面布局；改掉腾讯 `@TGS#` 示例与归一化，OpenIM 用户和群 ID 作为不透明字符串，只 trim。

参考的 `sangong_daily_report_page` 本身是没有接口的未接入占位，未迁入可点击入口。实际历史／收益页面使用上述真实报表与个人数据接口，不造假记录。

## 接口适配

三公业务调用经共享 GroupFeatureApi，每次请求捕获当前 `chatToken`，发送 `Authorization: Bearer <chatToken>`、`Content-Type: application/json` 与独立的 `operationID`，账号变更前后均检查。运营、规则、代理数据及 SSE 的默认基础地址为 `http://129.226.192.93:10008/sangong/api/v1`，普通业务请求的 `X-Tenant-Id` 优先取已确认逻辑租户，未确认时配置后备值为 `@z8hFfDvVQP0x`；实际业务派发仍要求有效绑定。SSE 使用相同地址、认证和租户规则，另发 `Accept: text/event-stream`。当前群租户查询、创建和更新使用当前 **Chat 服务地址＋Chat Bearer，不带 `X-Tenant-Id`**，不受三公业务基础地址或后备租户配置影响。

### 当前群租户与默认配置

当前游戏群通过 `SangongGroupTenantApi` 和 `services/binding/sangong_group_tenant_store.dart` 维护独立绑定状态。以下路径直接拼在当前 `context.api.baseUrl`（通常为 `Config.appAuthUrl`）及共享路径前缀之后：

| 操作 | 当前 Chat 服务合同 |
| --- | --- |
| 查询当前群 | GET `/sangong/api/v1/admin/tenants/{URLencoded groupID}`；默认查询当前群 ID，代理用途可明确传入已确认的聚合 `tenantID` |
| 初始化当前群 | POST `/sangong/api/v1/admin/tenants`；`imGroupGameId` 必须等于当前群 ID，`imBotUserId` 必填，厅名与结账／账单／水报表群可为空 |
| 更新当前群 | PUT `/sangong/api/v1/admin/tenants/{URLencoded tenantId}`；使用查询返回的租户 ID，当前下注群必须匹配，不能通过 body 更换 `imGroupGameId` |

查询只要求当前账号特权，不要求 `canConfigure/canManage`，因此全部业务能力为 false 时仍能确认该群是否已配置。200 响应支持直接配置、envelope 或 `payload.tenant`，`active` 必须明确为布尔值；true 表示已配置且启用，false 表示“当前群的三公已停用”。显式租户 ID 必须匹配请求，当前游戏群的显式下注群 ID 必须匹配当前群；缺少 ID 可由成功的定点查询补入。配置模型中的 `configured=true` 表示已有明确租户资料，不能授予权限；缺少角色／权限字段保持空／false。

只有 **HTTP 404＋精确 `TENANT_NOT_FOUND`** 表示未配置。HTTP 403＋精确 `TENANT_ACCESS_DENIED` 显示“当前群已配置三公，请联系配置者授权”；停用、401、其他特权／权限 403、普通 404、503、网络失败或格式错误均保留停用／拒绝／错误状态，不能显示首次配置空表单。非特权账号与普通群不会额外做当前群租户查询；代理专用群继续用能力或 entry-context 确认的聚合 `tenantID`，不按代理群 ID 判断游戏租户缺失。

初始化还要求当前群群主／管理员身份。POST 201 必须明确 `ok:true`、`active:true` 和完整配置才能确认保存；PUT 200 用完整配置与明确 `active` 判断结果，不强依赖 `configured/canEditConfig`。原始响应保留，错误／不完整写响应显示结果未确认，不自动重发。已有配置的更新由当前群 `canConfigure` 与服务端权限控制，SDK 群管理员身份不能自行授予已有租户的更新权限。保存后刷新群能力及绑定，操作能力继续以真实能力响应为准。

`GET /api/v1/admin/my-config` 读取当前账号的**默认租户配置**，`PUT /api/v1/admin/my-config` 保存时会改变该账号的默认配置；两者不能判断当前聊天群的绑定。原默认配置页及其严格 `configured` 解析继续保留，当前群模式改用上述定点租户接口。由于 `/my-config/members` 管理默认租户成员，当前群模式暂不显示该成员入口，也不在当前群初始化后自动跳入；默认配置模式保留原成员页面与接口。

### Debug 请求与返回日志

Debug 构建自动输出 `[三公API]` 控制台日志，无需额外开关。日志在真实传输层记录请求方法、完整地址与查询参数、请求头与请求体，以及实际 HTTP 状态码、耗时、完整返回 envelope 和失败原因；同一 `operationID` 关联请求与响应。正常 SSE 记录连接响应、每个完整事件的数据和关闭／异常；被拒绝的 SSE 额外读取错误正文，最多等待两秒，避免错误服务阻塞重连。长内容分块输出，保留末尾。

格式与脱敏集中在 `api/diagnostics/sangong_api_debug_log.dart`，三公普通请求、当前群租户 GET／POST／PUT 和实时连接显式接入共享传输层的可选观察接口。三公页面刷新群权限时，也在该次刷新范围记录 Chat 的 `GET /chat/groups/{groupID}/feature-capabilities` 真实请求与返回；请求结束后不影响其他共享调用。运营未就绪时会输出 `[权限检查]`，记录群 ID、权限版本、解析后的能力、原始三公字段、群功能开关与当前群绑定；否定能力不阻止特权账号做定点存在性查询，也不会因此授予运营权限。

Release／Profile 不创建三公日志观察器，不输出这些内容；其他共享 Chat／业务请求不会自动加三公日志。Authorization、Chat／IM token、密码及 Cookie 等凭据只在日志副本中隐藏，实际请求与响应保持原样；日志不写入 OpenIM SDK 日志。回归测试位于 `test/pages/group_features/sangong/api/diagnostics/`。

### 统一服务地址和路径前缀

三公业务服务的统一入口为 `api/sangong_api_config.dart`，运营、默认配置、规则、代理、划转、报表、HTTP 快照与 SSE 使用它。构建时可覆盖 `SANGONG_API_BASE_URL`、`SANGONG_TENANT_ID` 与 `SANGONG_API_PATH_PREFIX`，无需逐个修改业务接口路径；当前群租户 GET／POST／PUT 则按用户合同固定走当前 Chat 地址与 `/sangong/api/v1` 路径，不采用这些业务地址／租户覆盖。默认业务服务合同对应以下配置：

```text
--dart-define=SANGONG_API_BASE_URL=http://129.226.192.93:10008/sangong/api/v1
--dart-define=SANGONG_TENANT_ID=@z8hFfDvVQP0x
--dart-define=SANGONG_API_PATH_PREFIX=/sangong
```

接口文件保留 `/api/v1/...` 合同路径。基础地址以 `/api/v1` 结尾时，忽略独立的 `SANGONG_API_PATH_PREFIX`，并只去掉接口路径开头的一个 `/api/v1`，防止重复。默认配置下，`GET /api/v1/admin/my-config` 最终访问 `http://129.226.192.93:10008/sangong/api/v1/admin/my-config`；报表总览最终访问 `http://129.226.192.93:10008/sangong/api/v1/me/reports/overview`。

基础地址为根地址时，仍使用独立前缀。例如 `SANGONG_API_BASE_URL=http://129.226.192.93:10008` 加 `/sangong` 前缀会生成同一个完整 URL。若服务直接提供根目录下的 `/api/v1/...`，可配置空前缀；显式配置空基础地址时沿用当前 Chat 服务。服务地址只接受不含凭据、查询参数或片段的 HTTP/HTTPS 地址，首尾空白与尾部 `/` 会归一化。

这些是构建配置，改动后需要重新运行或构建应用。host/module 的显式 `pathPrefix` 参数覆盖根地址模式下的默认前缀；完整 `/api/v1` 基础地址始终按上述规则处理。账号特权、群能力和公开账号查询这 3 个共享依赖继续访问当前 Chat 服务，使用原有 `token` 头，不随三公地址或 Bearer 配置变更。

完整方法、路径、参数与调用状态见 [三公接口清单](../../../../docs/sangong-api-inventory-2026-10-06.json)。清单区分当前客户端接口、共享依赖和参考仓库尚未迁入的接口，路径未包含可配置前缀。

2026-10-06 源码核对共 60 个不同的「方法＋路径模板」组合，包含 59 个普通 HTTP 和 1 个 SSE；49 个有当前应用调用或活跃方法的兼容分支，11 个仅保留在适配器中。新增 3 个当前群租户 GET／POST／PUT 已有页面调用。`SangongReportsApi.fetchOverview()` 原样读取解包后的响应，尚未挂接页面，未定义未经提供的响应字段。另列 3 个 Chat 共享依赖，以及参考仓库已有、当前未迁入的 7 个下级返水／代理群绑定／上下级管理接口。此计数表示客户端合同，不表示真实后端已部署或抓取到了全部请求。

**以下为当前适配器的接口合同；地址、鉴权与当前群租户合同来自用户提供的部署配置。** 只有当前群查询的精确 404／403 合同映射为未配置／未授权状态，其他失败呈现真实错误与重试，不模拟成功或自动补权限。

| 范围 | 方法与参考路径 |
| --- | --- |
| 当前群租户 | GET `/sangong/api/v1/admin/tenants/{groupID}`；POST `/sangong/api/v1/admin/tenants`；PUT `/sangong/api/v1/admin/tenants/{tenantId}`（Chat 地址＋Bearer，无租户头；路径 ID 必须 URL 编码） |
| 账号默认配置 | GET / PUT `/api/v1/admin/my-config`（业务地址；无需预先确认群绑定，使用配置后备租户头，保存会改变账号默认租户） |
| 默认租户帮工 | GET / POST `/api/v1/admin/my-config/members`；DELETE `/api/v1/admin/my-config/members/{encodedUserID}`（业务地址；无需预先确认群绑定，默认发配置后备租户头；当前群模式暂不开放） |
| 保留的管理能力 | POST `/api/v1/admin/auth/setup`；GET `/api/v1/admin/tenants`（租户列表无需预先确认群绑定）；当前没有页面调用 |
| 规则与会话 | GET / PUT `/api/v1/settings`；GET `/api/v1/admin/session`；POST `/api/v1/admin/session/start`、`/stop` |
| 实时 | GET `/api/v1/admin/events/snapshot`、SSE `/api/v1/admin/events/stream` |
| 用户与流水 | GET `/api/v1/admin/reports/users`、`/user-detail`、`/user-hierarchy`、`/user-flow`、`/api/v1/admin/sessions` |
| 积分／分组／额度 | POST `/api/v1/admin/users/credit`、`/debit`；PUT `/api/v1/admin/users/group`、`/api/v1/admin/users/{userId}/max-negative` |
| 定庄 | POST `/api/v1/admin/banker/setup`、`/send`、`/quick-setup` |
| 合庄 | POST `/api/v1/admin/rounds/{roundID}/co-bank`、`/co-bank/close`；无轮次时用 `/api/v1/admin/rounds/current/co-bank`、`/co-bank/close`；POST `/api/v1/admin/rounds/current/co-bank/remove`、`/api/v1/admin/co-bank/send` |
| 截止与预览 | POST `/api/v1/admin/rounds/{roundID}/betting/preview`、`/submit`；无轮次时用 `/api/v1/admin/betting/preview`、`/submit` |
| 开奖与结算 | GET `/api/v1/admin/rounds/current/draws`；POST `/api/v1/admin/draws`、`/api/v1/admin/rounds/{roundID}/settle`、`/void-settlement`、`/resettle`、`/api/v1/admin/rounds/last-settled/resettle` |
| 发报表 | POST `/api/v1/admin/reports/bet-image`、`/settle-image`、`/settle-bill`、`/trend-image`、`/users/points-image`、`/preview-images/send` |
| 代理绑定 | GET `/api/v1/agent/entry-context?imGroupId=...`（无需预先确认群绑定，默认发配置后备租户头；响应确认聚合逻辑绑定） |
| 代理数据 | GET `/api/v1/me/team/dashboard`、`/team/members`、`/team/member-dashboard`、`/member-daily`、`/transfers` |
| 划转／返水 | POST `/api/v1/me/transfer-to-child`、`/api/v1/me/rebate/claim` |
| 报表总览 | GET `/api/v1/me/reports/overview`；`SangongReportsApi.fetchOverview()` 仅返回解包后的原始数据，当前没有页面调用 |

`SANGONG_TENANT_ID` 配置业务服务的后备传输租户，默认 `@z8hFfDvVQP0x`。普通业务 HTTP／SSE 的 `requestTenantId` 优先取已确认逻辑 `tenantId`，再取配置后备值；有效后备值不能授予角色、替代授权绑定或直接启用入口。旧默认配置、默认成员、租户列表与代理发现的 `extraSkipTenant` 表示无需预先确认逻辑绑定；这些业务发现请求有配置后备值时仍发该值，若后备配置为空则省略租户头。当前群租户 GET／POST／PUT 始终不发 `X-Tenant-Id`，与上述兼容模式分开。

旧默认配置读取仍需返回明确可解析的 `configured`，null／未知字符串等是格式错误；默认配置保存仍校验其原有响应字段。当前群首次配置只认精确租户缺失，初始化后按明确 `ok/active` 和匹配的租户配置确认，再刷新真实私有能力；更新不依赖默认配置字段，不从角色补 `owner/canManage`。更新群摘要的响应须携带完整 groupFeatures 和服务端 revision；只将该完整摘要回交 root，不自行增版本或硬开群字段。

公开账号名沿用现有联系人搜索的10位小写字母／数字规则，可带 `@`。帮工与机器人输入经正式联系人搜索精确匹配 `account` 后取真实 `userID`，再调用三公接口；已保存的内部ID保持兼容。全部用户的公开账号查询先解析身份，再以当前已确认租户调用 `user-detail?imUserId=...`，不受已加载列表页数限制。昵称／内部ID筛选仍只检查已加载列表。身份查询与写入之间若账号、群权限或租户变化，会丢弃旧结果。

已提供的后端合同中，`user-flow` 仅支持 `imUserId/userId/sessionId`，按账变编号倒序返回最近最多500条，无日期参数或续页能力。自然日汇总使用支持 `date` 的 `user-hierarchy`；明细在已返回范围内筛选日期，并显示原始读取条数和覆盖限制，不能把空明细视为当天没有交易。完整较早历史需要后端先按日期过滤再分页，前端没有发送未经确认的新参数。

此前对默认 Chat 地址下两个三公路径的只读核验发生在本次 Bearer／固定租户合同接入之前，不能用该结果判断新合同是否可用。本次文档核对基于当前客户端源码，未重新验证线上响应；本地没有三公服务端源码，结算、消息桥接和实际到账仍需在真实服务上联调。

## 权限、生命周期与请求

- 当前账号必须由聊天端口的 `POST /user/find/full` 确认 `isPrivileged == true`，缺失或请求失败按关闭。群聊运营／代理工具箱及代理浮窗继续受该账号字段控制，运营浮窗另外要求群类型 `gameType=1`，且已确认当前群租户与运营能力，或精确缺失后允许当前群管理员初始化；手动保存的浮窗隐藏设置仍生效。普通群和非特权账号不额外查当前群租户。登录后、返回前台、进入群聊／群功能面板和进入特权页面前刷新；关闭后隐藏入口并退出已打开的三公页面、弹窗和面板。点击入口后先刷新业务权限，读取失败／无权显示原因与重试，不自行授予业务或管理员权限。实现见 [账号特权展示权限](../../../services/account_privilege/README.md)。
- canConfigure 独立于 enabled，只表达配置操作权；存在性来自当前群定点查询。特权群主／管理员只有精确确认租户缺失后才可初始化，不能以 SDK 身份覆盖已有租户的否定授权。运营／代理能力同时需要模块 enabled、对应 entry、当前用户私有能力与有效租户；运营还要当前游戏群租户处于 configured 状态。旧角色／配置不能覆盖新的否定权限。
- 帮工管理另看私有 `capabilities.sangong.raw.canManageMembers=true` 或当前已确认配置的 `canManageMembers`；不能从 canConfigure 推断更广权限。当前群模式暂不接默认租户 `/my-config/members`，默认配置模式保留该入口。代理当前汇总与私人历史分开：每天收益／划转历史同时要求 `rebateHistoryEntry` 与 `canViewRebateHistory`，两者缺一不展示入口、不请求历史。
- 账号／服务端环境／群隔离。权限版本或能力变化清配置与代理上下文、清旧租户；关闭业务 entry 或模块停止业务操作与实时订阅，账号特权入口仍可进入加载／错误页。该公开页允许刷新业务权限版本，含私人数据的页面及子路由仍保留旧权限版本隔离，运行时变化立即检查路由。后台、最后订阅者离开、路由销毁、账号失效时取消请求、定时器与 SSE。
- 私有路由请求前后都检查 `capabilitiesCurrent()` 及最新具体操作能力。旧权限快照即使仍在 Navigator 中也不能继续读取私人数据或提交操作；否定授权可以清空旧 tenant，不受旧 epoch 已失效的阻挡。
- `api/sangong_scoped_requests.dart` 在调用业务 API 时固定请求上下文与逻辑租户，HTTP派发和响应返回都再次校验，包括无需预先确认绑定的旧默认配置／成员接口。后备传输租户头不会绕过这些检查。当前群定点 adapter 独立检查会话、账号、Chat API／环境及账号特权代次；当前群 store 再按账号／群和本地请求代次丢弃旧结果，不依赖否定能力来判断不存在。跨弹窗和身份查询的事务使用 `services/authorization/sangong_operation_scope.dart` 固定群、账号、环境、逻辑租户和能力版本；切换逻辑租户即使仍拥有相同权限，旧操作也失效，旧私人缓存不继续展示。
- 当前群租户和账号默认配置分别内存缓存5分钟、进行中请求合并；保存先增加各自的本地请求代次，先发后到的旧查询不能覆盖新配置，群／账号／环境变化清理缓存。浮窗位置与展开状态按环境＋账号＋群保存，不作为权限依据。
- 同一个 runtime 的实时状态引用计数复用一条连接。首订阅、恢复前台、断线重连校准快照；45秒无传输重连，退避1／2／5／10／30秒；快照并发合并、旧HTTP不能覆盖更晚SSE。没有参考每15秒无条件轮询。
- 参考前端 SSE 使用 event/data，没有已确认的 Last-Event-ID 恢复合同；本地未提供参考服务端源码，不能据前端 DTO 证明线上版本生成方式。本适配要求完整快照带正整数 `version` 及真实 `settings.doorCount`（2–10），缺失／0／无效门数显示格式错误并合并校准，不默认成六门空游戏。当前按租户快照单调版本拒绝重复／旧状态；服务端须确认版本在重启与场次切换时的作用域，不能与 groupFeatures.revision 混用。移除轮询前需联调心跳及完整状态事件覆盖。
- 上分／划转／结算／发图片只有服务端确认才提示成功；超时显示结果未确认，不自动重发写请求。积分写入须给真实 balance；开机须确认 running、关机须确认 idle/stopped/ended；截止须给 submit 的实际数量（允许明确0条）和已关闭的 round；划转须给 referenceId 与 fromBalance，并在输入、确认、提交和刷新期间锁定。可负额度必须返回匹配用户及请求值，旧版空确认最多再读一次同租户的用户资料核实；未核实不显示保存成功。返水返回有效amount只提示申请已提交、需刷新确认到账；缺失或非法金额为未知结果。HTTP200空DTO按未知结果处理。source 的添加／移除帮工为 void ack，未无依据要求新增 ok；后端仍需确保2xx确实已提交，业务失败须明确返回错误码／ok=false。请求结果的最终授权仍由服务端校验。
- 代理未返水使用 `pendingRebate`，已返水与未返水分开；`rebatePer10000/100` 转百分比，显式 `rebatePct` 优先。代理报表校验成员身份、实际读取结构及已提供的数值；可选汇总指标未提供时显示“—”，不把缺失数据补为0。
- OpenIM 消息截止只使用服务器明确给出的业务 messageId 或 SDK seq；不能把 clientMsgID 强制转成参考服务的数字数据库 ID。后台消息接入与截止字段须按 OpenIM 真实协议联调。

测试放在 `test/pages/group_features/sangong/`，覆盖隔离、缓存、撤权、首次配置、配置失败、代理错误、浮窗与状态条及 SSE 生命周期。测试中的数据与传输替身仅用于验证，不进入生产页面。

可选真实组件截图通过 `SANGONG_PREVIEW` 指定绝对 PNG 输出路径，默认跳过；覆盖 Android／iOS、亮／暗、320×640／390×844，排列浮窗、管理、配置、规则、代理五行。使用实际迁入 Widget，不能把截图测试数据当上线数据。

## 大文件边界与维护计划

本轮保留少数超过800行的参考文件，目的是维护同一表单／DTO合同迁移的可核对性，不按行数机械切割；每个文件职责如下。

| 文件 | 当前单一职责 | 后续拆分边界 |
| --- | --- | --- |
| models/sangong_admin_models.dart | 三公运营 API 的不可变 DTO 与 JSON 解析，不包含网络和页面状态 | 按 session/round、bet preview/cutoff、draw/settlement、user/account flow 分文件，保留旧 export 兼容，补协议样例校验 |
| models/agent_rebate_models.dart | 参考代理／返水 DTO；保留原共享字段以避免迁移时删改未知服务数据 | 按三公团队、entry-context、其他游戏 DTO 拆分；移除无引用 DTO 必须先核对 import，不改变资金字段含义 |
| pages/sangong_game_rules_settings_page.dart | 一张完整规则表单及开／关机操作，所有 controller 随页面销毁 | 抽取字段分区纯 UI（基础限额、赔率、会话），状态／保存仍统一由页面负责，避免多分区重复请求 |
| widgets/sangong_bet_preview_sheet.dart | 一个截止预览 sheet 的用户统计、记录与提交忙态 | 抽取预览记录／统计 card，提交与关闭仍由单一 sheet 状态管理 |
| api/sangong_admin_api.dart | 运营 HTTP 路径与响应适配，不持有账号凭据或全局业务状态 | 拆配置／成员、报表、round 操作 adapter，全部继续共用当前 scoped transport、tenant 与取消令牌 |

上述拆分属于后续维护，不新增业务接口、并行刷新或独立 token 存储；当前上线路径仍必须先完成后端合同联调。
