# 群直播与游戏入口：OpenIM 群扩展字段设计

更新日期：2026-10-05。

本文用于前后端对接。字段、版本规则和新增业务接口是待实现约定，不代表线上后端已经接入。客户端迁移说明见 [群功能前端模块](../lib/pages/group_features/README.md)，实际服务仍需按契约联调。参考 99chat 的入口与权限行为，使用当前 OpenIM 的群资料和通知机制承载群级功能摘要。

按当前客户端实际字段、路径与入口条件整理的实施说明见 [后端对接说明](group-features-backend-handoff.md)。其中区分已经被客户端调用的接口与仅建议新增的后台配置接口。

## 1. 设计目标与范围

- 群列表角标、聊天顶栏、浮窗和功能菜单共用同一份群功能摘要。
- 使用已经加载的 `GroupInfo.ex` 判断直播状态、游戏类型及入口开关，减少分别查询各个入口的请求。
- 三公与六合彩按独立模块配置，支持同群共存；不预设只能启用一种游戏。
- 群级配置与当前用户的业务权限分开。代理、运营、配置等权限由业务后端确认。
- 直播播放、游戏实时状态、开奖记录、代理报表和结算继续由对应业务模块处理。

`ex` 是展示用的群级摘要。业务数据库是配置和业务状态的权威来源，不能仅凭客户端提交的 `ex` 授权、开播或结算。

## 2. 当前能力与 99chat 对照

当前 Flutter SDK 版本为 `flutter_openim_sdk 3.8.3+hotfix.12`，已确认具有 `GroupInfo.ex`、`setGroupInfo` 和 `onGroupInfoChanged`。项目已经集中监听群资料变化，并向群聊模块分发事件。

99chat 本地参考提交为 `d7c3c65`，已确认的行为如下：

| 功能 | 99chat 当前判断 | 本方案的迁移方式 |
| --- | --- | --- |
| 三公运营入口 | 用户特权，加首次配置或匹配绑定群 | 群级运营开关结合当前用户的配置、运营权限 |
| 三公代理入口 | 后端返回 `showAgentEntry`，且租户标识非空 | 群级代理开关结合当前用户在该群的三公代理权限 |
| 六合彩代理入口 | 机器人群已绑定、启用，且当前用户是代理 | 群级模块、入口开关结合有效绑定与当前用户权限 |
| 开奖记录入口 | 群自定义 `gameid` 非空，且业务群 `gameEnabled` 为真 | 群级 `drawHistoryEntry` 加有效开奖业务绑定 |
| 代理收益历史 | 代理入口权限下的独立流程 | 单独的 `rebateHistoryEntry`，不能与开奖记录混用 |

99chat 的腾讯 IM `customInfo` 与 OpenIM 的 `ex` 不是同一种存储接口。此次需要定义自己的 JSON 协议，不能把参考字段当作当前 OpenIM 已有的业务契约。

## 3. 群扩展 JSON

在 `ex` 的 JSON 根对象内增加独立命名空间 `groupFeatures`，保留原有其他业务字段。以下 JSON 是 `ex` 字符串解码后的内容，实际提交时需要序列化成字符串。

```json
{
  "groupFeatures": {
    "schemaVersion": 1,
    "revision": 12,
    "live": {
      "status": "live",
      "sessionID": "live_001",
      "roomName": "群直播间",
      "description": "欢迎观看",
      "anchorUserID": "user_001",
      "scheduledStartAt": null
    },
    "games": {
      "sangong": {
        "enabled": true,
        "manageEntry": true,
        "agentEntry": true,
        "rebateHistoryEntry": true
      },
      "markSix": {
        "enabled": true,
        "agentEntry": true,
        "drawHistoryEntry": true,
        "rebateHistoryEntry": true,
        "machineCode": "machine_001",
        "gameID": "game_001"
      }
    }
  }
}
```

### 公共字段

| 字段 | 类型 | 约定 |
| --- | --- | --- |
| `groupFeatures.schemaVersion` | integer | 结构版本，首版为 `1` |
| `groupFeatures.revision` | integer | 后端维护的群功能摘要版本，同一群内单调递增 |
| `live.status` | string | 直播公共业务状态，枚举见下一节 |
| `live.sessionID` | string | 当前或最近结束的直播场次 ID；未建立场次时为空字符串 |
| `live.roomName` / `description` / `anchorUserID` | string | 横条标题、描述与主播 OpenIM 用户 ID |
| `live.scheduledStartAt` | integer / string / null | 摘要兼容 Unix 毫秒或 ISO 时间字符串；没有预约时为 `null`。直播业务 DTO 与写请求使用 UTC ISO 字符串 |
| `games.sangong.enabled` | boolean | 该群是否启用三公模块 |
| `games.sangong.manageEntry` | boolean | 该群是否开放三公运营入口 |
| `games.sangong.agentEntry` | boolean | 该群是否开放三公代理入口 |
| `games.sangong.rebateHistoryEntry` | boolean | 可选；是否开放三公成员逐日数据、上下分流水等代理账务历史，仍须 `canViewRebateHistory` |
| `games.markSix.enabled` | boolean | 该群是否启用六合彩模块 |
| `games.markSix.agentEntry` | boolean | 该群是否开放六合彩代理入口 |
| `games.markSix.drawHistoryEntry` | boolean | 该群是否开放开奖记录入口 |
| `games.markSix.rebateHistoryEntry` | boolean | 该群是否开放代理收益／反水历史入口 |
| `games.markSix.gameID` / `machineCode` | string | 当前群绑定的开奖实例定位字段；非代理权限、非凭据，供公开开奖记录按需请求 |

业务模块由 `games` 内的模块键确定。管理后台另外维护 `ex` 根对象的数字 `gameType`（0 普通群、1 三公游戏、2六合彩代理、3六合彩开奖、4 三公代理）；三公运营浮窗要求类型为 1，类型为 3 时直接显示公开开奖入口，不要求模块或子入口开关、机器码预先存在。缺少机器码时页面显示配置缺失，不伪造绑定或开奖数据。其他类型沿用显式模块与子入口开关，私人业务权限独立判断。缺失或非法类型按普通群。`enabled=true` 表示后端已确认该模块绑定有效并已启用；解绑时同步改为 `false`，类型为 3 的公开开奖入口仍保留，其他子入口按原规则关闭。

客户端把缺失的开关按 `false` 处理。未知模块不显示；不支持的结构版本或非法 JSON 不引起页面崩溃，也不据此放开业务权限。服务端更新时保留未知字段和其他命名空间。

## 4. 直播状态与显示规则

| `live.status` | 文案 | 群内行为 |
| --- | --- | --- |
| `none` | 无直播 | 隐藏当前直播角标和观看入口 |
| `scheduled` | 待开播 | 显示预约信息；点击进入预约／等待页 |
| `ready` | 有直播 | 已授权或创建场次，尚未确认实际开播；点击进入等待页 |
| `live` | 直播中 | 显示直播角标和观看入口；点击获取有效播放凭据 |
| `ended` | 已结束 | 隐藏当前观看入口；已有观看会话切换为结束状态 |

`scheduled`、`ready`、`live` 必须带非空 `sessionID`。数据不完整时不启动播放器，先合并补查该场次。`ended` 保留结束场次 ID 和最新群摘要版本，避免旧事件重新激活旧场次。

典型流程为 `none → scheduled → ready → live → ended`，立即开播可以跳过 `scheduled`；取消预约也可直接进入 `ended`。实际开播、断流和结束状态由服务端结合直播平台回调及业务规则确认，不能由某个观看端自行决定。

不再增加与 `status` 重复的 `hasLive`。播放器的加载、缓冲、重连、静音和全屏状态属于本机状态，不写入全群字段。

## 5. 入口与个人权限

群开关决定该群开放的功能；当前用户权限决定可以进入的业务页面。有效群绑定由服务端维护，客户端不能通过修改群字段建立业务租户或代理关系。

| 入口 | 最终显示条件 |
| --- | --- |
| 三公运营 | `sangong.enabled && manageEntry`，且当前用户拥有该群三公运营权限 |
| 三公代理 | `sangong.enabled && agentEntry`，且当前用户拥有该群三公代理权限 |
| 六合彩代理 | `markSix.enabled && agentEntry`，且绑定有效、当前用户拥有该群六合彩代理权限 |
| 开奖记录 | `gameType=3` 直接显示；其他群沿用 `markSix.enabled && drawHistoryEntry`，且已确认当前用户仍为群成员 |
| 代理收益历史 | `markSix.enabled && rebateHistoryEntry`，且当前用户拥有该群对应的收益历史权限 |

三公运营权限、三公代理权限、六合彩代理权限各自独立，不以“是群主／管理员”或某一个代理标志替代全部业务授权。

开奖记录按当前群成员公开展示，不依赖额外的个人代理权限查询；点击后业务接口仍校验实时成员资格。代理收益历史继续采用个人授权。

首次配置入口单独由 `canConfigure` 判断。获准配置的用户即使面对 `enabled=false` 或尚未绑定的群，也应能进入配置流程并创建首次绑定，避免关闭状态导致无法首次启用。不能仅因模块关闭而跳过配置权限查询。首次绑定由对应业务配置流程创建，再同步启用摘要；实际代理、运营操作要求已有效绑定。

以下内容不放进全群共享的 `ex`：当前用户的代理身份、个人角色、个人余额、收益明细、账户令牌、推流密钥、带签名的播放地址。客户端向业务接口传入群 ID，后端依据登录态确定操作者和有效业务绑定。

## 6. 个人权限查询与缓存（拟定接口）

建议合并查询该用户在当前群的入口权限，避免分别调用三公身份、六合彩身份和各入口判断接口。

`GET /chat/groups/{groupID}/feature-capabilities`

请求头沿用当前 Chat 接口的 `token`（`chatToken`）和 `operationID`。操作者从登录态取得；路径中的群 ID 按 URL 组件编码。

建议响应：

```json
{
  "errCode": 0,
  "errMsg": "",
  "errDlt": "",
  "data": {
    "groupID": "group_001",
    "capabilityVersion": 5,
    "cacheTTLSeconds": 300,
    "live": {
      "canConfigure": false,
      "canManage": false,
      "canPush": false,
      "canTip": true,
      "tipCurrencies": [{"code": "USDT", "label": "USDT", "decimals": 6}]
    },
    "sangong": {
      "canConfigure": false,
      "canManage": false,
      "canOpenAgent": true,
      "canManageMembers": false,
      "canViewRebateHistory": true,
      "tenantID": "tenant_001"
    },
    "markSix": {
      "canConfigure": false,
      "canOpenAgent": true,
      "canViewRebateHistory": true,
      "machineCode": "machine_001",
      "gameID": "game_001"
    }
  }
}
```

`capabilityVersion` 属于用户在该群的权限上下文，不能与 `groupFeatures.revision` 比较。`cacheTTLSeconds=300` 是首版建议值，当前客户端实际限制为 0～300 秒；缓存只改善入口展示，不能代替业务接口的实时授权。`data.groupID` 必须与请求群完全相同。

前端能力对象同时支持 `live.canConfigure`、`canManage`、`canPush`、`canTip`；直播管理保留当前 SDK 群管理员入口，实际操作仍由后端确认。三公／六合彩个人对象可返回 `tenantID`、`gameID`、`machineCode` 与 `canViewRebateHistory`，以便少一次绑定查询。租户和代理权限必须来自该登录用户的响应，不能直接从公共 `ex` 推导。

三公帮工管理使用独立的 `sangong.canManageMembers`，或当前用户业务绑定响应中的明确同名权限；不能由 `canConfigure` 推断。三公逐日收益、上下分流水等私人历史同时要求群级 `rebateHistoryEntry` 与个人 `canViewRebateHistory`。未返回这些字段时，相关入口默认隐藏。

- 缓存键包含服务端环境、账号、登录会话和群 ID。同一键的进行中请求合并。
- 进入页面先使用有效缓存，不因 Widget 重建重复查询。
- 权限变化、退群、解绑、账号退出或被踢时失效；定向权限通知只更新对应用户的上下文。
- 没有已确认权限时不先展示代理操作入口。查询失败不默认授权。
- 直播模块遇到 HTTP 403 或 `1002/20012` 时会使共享权限缓存失效；通用请求层不替其他模块自动执行此行为。后端撤权同时定向发送 `groupFeatureCapabilitiesChanged`，携带群 ID 和新的 capabilityVersion，客户端据此失效并合并重查。业务接口始终实时鉴权，不能不断重试被拒绝的写操作。

## 7. 后端写入与并发规则

群功能配置、直播场次状态先在业务后端落库，再通过服务端任务同步到 OpenIM `ex`。入口操作应经过业务接口，统一校验配置权限、有效绑定和状态；前端不自行把 `status` 改成 `live` 或 `ended`。

建议后台群功能配置接口为 `PATCH /chat/groups/{groupID}/features`；该通用接口当前客户端尚未调用。三公首次绑定实际调用 `PUT /sangong/api/v1/admin/my-config`，直播使用独立 authorize/schedule/stop/revoke 路由。通用配置接口只允许修改已开放的配置字段，不允许客户端写入直播实际状态或个人权限。例如：

```json
{
  "clientRequestID": "request_001",
  "expectedRevision": 12,
  "games": {
    "sangong": {
      "agentEntry": false
    }
  }
}
```

后端执行规则：

1. 依据登录态检查该用户在该群的配置权限，校验模块；修改已绑定业务的开关时校验有效绑定。首次配置流程允许获准用户创建绑定，不能要求进入该流程前已经存在绑定。
2. 在业务数据库内比较 `expectedRevision`，按群合并修改；有实际变化时递增摘要版本。
3. 使用操作者、群 ID、`clientRequestID` 作为幂等上下文；同一重试不重复执行，载荷冲突时拒绝。
4. 在同一事务中保存新摘要与待同步任务；提交后返回新的完整 `groupFeatures`，客户端可以立即应用。
5. 由按群串行的同步任务读取最新摘要，合并完整 `ex` 后调用 OpenIM。失败可重试，任务不得以保存的旧字符串覆盖新摘要。

配置成功和 OpenIM 同步成功是两个阶段。响应建议携带 `groupFeatures` 及 `imSyncStatus`（`synced` 或 `pending`）；业务落库成功但镜像待重试时，不应让用户重复创建同一操作。其他成员可能短暂显示旧入口，点击业务功能时由后端重新校验。

`ex` 是整段字符串替换，SDK 不提供 JSON 字段自动合并，也不能把普通 `revision` 字段当作 SDK 自带的 CAS。读取旧值再写回本身不能防止并发覆盖。[OpenIM 扩展字段说明](https://docs.openim.io/zh/sdk/android/group/set-group-extension)

所有写入 `ex` 的业务模块必须遵守同一按群合并规则，保留其他命名空间和未知字段。若现有部署仍允许客户端或其他模块绕过此流程直接写 `ex`，需要先统一写入路径或增加服务端校验；仅串行本模块不能消除这些并发写入。

遇到旧格式、非 JSON 的 `ex`，先明确迁移与兼容规则，不静默清空旧数据。关闭功能应返回带新版本的显式关闭状态，不通过删除版本信息完成。

## 8. 客户端同步流程

1. 从已经加载的群资料解析 `groupFeatures`，写入账号范围内的共享仓库，立即生成入口和角标。
2. 使用项目现有的 `onGroupInfoChanged` 广播更新对应群，不在页面重新注册 SDK 单例 listener。
3. 完整摘要按同一群的 `revision` 拒绝重复或旧版本；较新的完整摘要可以直接替换，不因版本跳跃逐个补查。只有增量事件缺少前置版本、摘要不完整或明确失效时才合并补查。
4. 群 ID、账号、登录会话、请求代次都必须匹配。退群、切号、退出后到达的旧响应不能写入新上下文。
5. SDK 重连／同步完成后，对当前需要展示的群批量校准；有可靠版本或新鲜度依据时跳过重复读取。推送未到达不能视为永远没有变化。
6. 点击观看、游戏管理或代理页面时，由业务接口确认最新状态和权限；返回成功数据直接更新相应业务仓库。

同一群的请求合并；页面只订阅仓库，不各自启动查询和轮询。批量同步也要分页或按可见群限制范围，避免会话列表逐项查询群状态。

## 9. 版本与生命周期边界

| 标识 | 作用域 | 用途 |
| --- | --- | --- |
| `schemaVersion` | JSON 结构 | 确定解析方式 |
| `groupFeatures.revision` | 同一群的完整功能摘要 | 入口、直播摘要更新顺序，包括结束或关闭状态 |
| `live.sessionID` | 一次直播场次 | 防止旧场次查询、播放结果影响新场次 |
| `capabilityVersion` | 当前用户在该群的权限上下文 | 权限缓存更新与失效 |
| 游戏 `roundID`、状态版本、事件 ID | 对应游戏服务明确规定的场次／租户／房间 | 实时状态排序、事件去重和断线恢复 |

这些版本不能混合比较。完整群摘要由统一仓库按群版本处理；独立场次、游戏和权限响应使用各自标识。直播场次切换后丢弃旧场次的业务异步结果，不能仅比较两个场次内部可能重新从 1 开始的版本。

本方案不要求把游戏每局状态写入 `ex`。倒计时根据服务端截止时间在本地计算，开奖与结算由后端确认。SSE 等实时协议由游戏模块共享一条连接，只有需要该业务状态的前台订阅者才启用；后台、退出会话时按所有权释放。停止固定轮询前，先确认服务端具有完整状态事件、序号及恢复能力。

直播小窗、全屏和直播间由一个播放控制器统一接管，真正观看时获取播放凭据。观看已按 `expiresAt` 提前续签，共享一条调度；失败退避，到期停止旧地址，后台或关闭观看取消请求并释放资源，恢复前台合并校准。推流凭据过期后手动刷新。同场未结束摘要允许业务详情校准真实开播状态；结束和换场立即停止旧场播放，不额外查询旧场次。

## 10. 请求数量目标

以下统计的是新增入口判断和业务查询目标，不是现有实现的测量结果；已有聊天同步、SDK 群资料读取、实时连接建立和媒体流量另行统计。

| 场景 | 新增业务请求目标 |
| --- | --- |
| 已有有效群资料，只判断公开入口和直播角标 | 0 次单独入口查询 |
| 首次需要个人权限且没有有效缓存 | 1 次合并权限查询 |
| 群资料和个人权限均有效，再次进入群聊 | 0 次入口查询 |
| 收到完整且更新的群资料摘要 | 公共摘要直接应用；直播活动资格、场次或主播变化，以及游戏绑定、启用或私人入口变化，合并刷新已有权限；同场显示状态变化不补权限查询 |
| 群资料缺失或重连后需要校准 | 合并 SDK 群资料读取，不为每个入口分别请求 |
| 点击直播观看 | 按需获取播放凭据，并确认当前场次 |
| 打开开奖记录、代理报表或管理页 | 按需分页加载实际业务数据 |
| 执行管理或结算操作 | 保留权威业务请求，成功后直接应用返回状态 |

群字段减少的是“判断入口”的接口。个人权限查询、播放授权、实际数据查询和写操作仍然需要后端。ETag／304 可以减少传输内容，但请求本身依然发生。[HTTP 条件请求说明](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/If-None-Match)

## 11. 分工与落地顺序

后端负责群级配置、绑定、个人权限、真实直播状态、摘要版本、幂等写入，以及 OpenIM 镜像同步和失败重试。具体错误码沿用项目规范统一分配，不在本文假定新增接口已拥有固定错误码。

客户端负责兼容解析、共享仓库、现有 SDK 通知接线、入口组合判断、缓存与失效、按需导航、账号和异步隔离。新增模块按 [项目模块规范](module-organization.md) 独立组织，不把直播、游戏、权限和配置全部堆入聊天主控制器。

当前客户端共享仓库、入口与直播／三公／六合彩页面已迁移。后端落地先完成真实绑定、合并权限接口、完整摘要和 OpenIM 同步，再接直播实际业务及平台回调、游戏状态与代理接口，最后联调资金与导出。具体顺序和已有前端边界见 [后端对接说明](group-features-backend-handoff.md)。

## 12. 联调验收

- 缺失、空值、非法 JSON、未知模块和不支持的结构版本能正常打开群聊。
- 直播五种状态文案正确；新场次开始后，旧查询和旧结束事件不能覆盖新状态。
- 三公与六合彩可以独立启用、关闭和共存，子入口互不串用。
- 普通成员、运营人员、三公代理、六合彩代理及获准配置者分别符合入口条件。
- 开奖记录与代理收益历史入口、权限和数据源分开。
- 新摘要通过 SDK 通知更新列表、顶栏和菜单，不清除未读或改变聊天草稿。
- 两个模块并发修改 `ex` 时，其他命名空间和未知字段不丢失；旧同步任务不覆盖新摘要。
- 配置重试幂等；业务提交后 OpenIM 暂时失败可恢复，客户端不重复创建操作。
- 缓存命中、多个组件同时进入、返回页面等场景符合请求目标。
- 断线、恢复前台、权限撤销、退群、账号退出及被踢后能够正确补同步或清理。
- 亮暗主题、Android／iOS 的入口和生命周期行为一致。

## 13. 核对来源

### 当前项目

- [SDK 统一业务及群通知入口](../lib/core/controller/im_controller.dart)：群通知由已有全局监听分发。
- [群聊资料与生命周期](../lib/pages/chat/group/chat_group_controller.dart)：群信息事件、初始请求合并和晚响应保护。
- [群资料查询适配](../lib/pages/chat/group/chat_group_sources.dart)：复用真实 OpenIM SDK 查询。
- [已有业务事件与账号隔离示例](../lib/services/moments_repository.dart)：可借鉴缓存、去重和请求代次模式；其版本定义不能直接套用到本协议。

### 99chat 参考源码

以下为本地 `reference-99chat` 提交 `d7c3c65` 已核对的源码路径：

- `lib/src/widgets/lottery_chat_entry.dart`：`gameid`、业务群开关和开奖记录入口。
- `lib/src/services/group_game/sangong_my_config_service.dart`：三公特权、首次配置与绑定群判断。
- `lib/src/chat.dart`：三公运营、三公代理与六合彩代理入口接线。
- `lib/src/services/agent_identity_service.dart`：六合彩代理的群绑定、启用和个人身份判断。
- `lib/src/api/agent_rebate_api.dart`：三公代理 `entry-context` 查询。

参考仓库：[qiuiqu6666/99chat](https://github.com/qiuiqu6666/99chat)。

### 官方协议

- [OpenIM 群扩展字段与资料变更通知](https://docs.openim.io/zh/sdk/android/group/set-group-extension)。
- [OpenIM 服务端群资料更新接口](https://docs.openim.io/zh/platform-api/group/managing-groups/set-group-info-ex)：管理员凭据只放可信后端，成功以业务错误码为准。
- [OpenIM 业务通知](https://docs.openim.io/zh/platform-api/message/sending-messages/send-business-notification)：定向权限变化等事件可复用现有业务通知通道；部署版本支持情况需联调确认。
