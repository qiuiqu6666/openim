# 三公 Flutter 模块

参考 99chat 提交 `d7c3c65`，Apache-2.0；迁入源码保留来源注释，许可证见 `LICENSE-99chat`。页面继续复用 OpenIM、GetX、SettingsScaffold/SettingsCell、AppDialog、主题与生命周期能力。新版 Go 的接口适配不改变 SDK 消息和会话核心。

详细协议见 [Go v2 接口与 Flutter 接入](../../../../docs/sangong-go-v2-api.md)。当前部署已使用 Go 页面接口；安装包仍需单独构建发布。

## 入口与责任

`sangong_module.dart` 是外部入口。`SangongFeatureHost` 每个账号/群持有一份 `SangongRuntime`，builder 接收 `(scopeContext, statusBanner, overlay)`。状态条放消息列表上方，overlay 放有明确尺寸的 Stack；子页面传入同一 runtime，复用绑定和实时状态。独立路由创建的 runtime 随路由销毁。

`openManage` 打开运营或当前群初始化；`openAgent` 提供 dashboard、team、personal。代理浮窗沿用查/团/个/隐，运营浮窗沿用截/结/图/账/分/势/设/隐。运营入口要求 Chat 确认的特权用户；个人代理入口允许普通用户，但必须具备服务端确认的当前群代理权限（正返水比例、明确归属、有效账户和真实群成员）。群类型和公共摘要不能单独授予代理权限。

| 目录 | 维护责任 |
| --- | --- |
| `api/` | 按群 v2 请求、固定请求作用域、幂等回执、错误和调试日志 |
| `api/admin/` | 配置、用户、账务、局操作、预览与报表等独立适配器 |
| `models/` | 响应解析；规则、身份、版本和金额校验 |
| `services/binding/` | 当前群配置发现、已确认绑定、竞争请求失效 |
| `services/realtime/`、`services/sangong_realtime.dart` | 初始 HTTP 校准、可信 OpenIM 公共状态、重连/前台恢复 |
| `services/authorization/` | 跨 await 的账号、群、租户与权限版本保护 |
| `identity/` | 公开账号、真实 IM 头像与登录隔离的展示资料缓存 |
| `services/account_identity/` | 复用联系人搜索，把公开账号精确解析成 OpenIM userID |
| `agents/` | 独立代理群绑定、成员归属及比例编辑；复用已有设置和确认组件 |
| `agents/user_group/` | 用户详情输入群 ID 保存代理群归属；独立持有加载/保存状态与作用域保护 |
| `profile/` | 联系人资料页三公服务卡、积分操作和流水入口；见其 README |
| `pages/` | 管理、当前群配置、用户统计和代理业务页面 |
| `widgets/` | 状态条、浮窗、截止预览、开奖/重结流程、账务页签 |
| `utils/` | 纯解析、金额输入、消息边界与反馈文案 |

## 当前接口契约

默认使用当前 Chat 地址与 `/sangong`，业务前缀为 `/api/v2/groups/{groupID}` 或 `/api/v2/agent-groups/{agentGroupID}`。使用原 Chat Token 的 Bearer 头，每次请求带 operationID。v2 不发送 X-Tenant-Id，也不读取账号默认配置决定当前群。

`SANGONG_API_BASE_URL`、`SANGONG_API_PATH_PREFIX` 只配置访问地址。完整 `/api/v2` 地址会统一归一化；旧 `/api/v1` 地址明确报错，避免悄悄调用错误后端。构建配置中的固定租户不能授予任何业务权限。

当前群初始化和更新均为 `PUT .../config`，查询 `GET .../config`。明确 configured=false 才显示首次配置；403、依赖失败和停用不是未配置。保存后验证返回绑定，并刷新服务端私有能力。无需使用 `/admin/my-config`。

写操作使用 `POST .../commands/{action}` 与 `{requestId,input}`，只有匹配的回执才确认成功。结果未知保留原请求键供显式重试，不自动换键重写。命令/查询捕获作用域，账号、Token、群、绑定或权限变化后丢弃旧结果。

## 游戏与报表

已确认业务为即时扣分、截止前撤注退款、1:1 输赢、统一庄家抽水。规则页仅保留门数、最小/最大下注和庄抽水；没有牌型赔率或闲家抽水。开机/关机和所有局操作携带当前批次/局 ID，提交前后均检查操作上下文。

长按消息截止使用 OpenIM 已落库的 seq。当前页预览与提交绑定同一 roundId；选中历史边界仅排除后续有效下注，录入开奖号成功时退款，已退款的撤注不恢复。按钮只有符合当前权限和游戏阶段时才提交。

下注清单、结算明细、积分表、走势图及管理群 Excel 统一用 `report.send` 命令。结算/账单按钮使用 latestState.lastSettledRound.id；不能把缺失 ID 默认为当前局。queued=true 仅显示加入队列，送达由 OpenIM 原生图片/文件消息呈现。

`user-report` 聚合资料、汇总、流水和合庄记录；日期按上海经营日，选择批次时不再同时发 date。流水按游标最多读 5 页共 500 条，显示已读取范围和服务端总数；不混合版本不同的分页。合庄列表首屏最多 500 条并显示截断提示。旧报表响应不能覆盖较新完成的额度/比例编辑。

代理群通过 `tenants` 核对固定所属厅后直接进入，没有选厅和切换；业务请求携带固定 tenantId 作归属核验。账号、余额、代理树和返佣均按下注群租户隔离。比例使用最多四位小数的百分比字符串，不在客户端计算级差收益。公开账号输入先解析 OpenIM ID，再定位本租户数值 userId。

## OpenIM 与请求合并

共享 GroupFeatureStore 接收 `GroupInfo.ex.groupFeatures`；revision 控制公共摘要的新旧，capabilityVersion 控制私有能力失效。公开字段只含 enabled/manageEntry/agentEntry/rebateHistoryEntry，不含角色、余额或下级。

三公不再新建 SSE 连接。`snapshot` 一次读取状态条、规则、局和开奖；随后只接受可信机器人发送的已落库 OpenIM `message.ex.sangong` 状态。必须核对群、机器人 ID、serverMsgID、正数 seq、版本及完整 schemaVersion=2 状态。旧/重复事件忽略，缺口、重连和前台恢复重新请求 snapshot。状态消息不赋予管理权限。

命令响应 data.state 直接刷新显示。子页面按需读取私有数据，不在每条公开消息后全量刷新所有报表。有效旧状态可在重连错误时保留；未获得初始完整状态时不虚构空闲局。失去权限则立即清理私有数据并停止订阅。

## UI 与验证

状态条、浮窗、资料操作、账务和代理页面对照 99chat 实际布局；新增代理绑定/比例操作复用本项目设置项和 AppDialog。亮/暗主题及 Android/iOS widget 场景由测试覆盖，小屏账务合计随列表滚动，不挤压列表高度。

回归测试位于 `test/pages/group_features/sangong/`，共享权限与摘要在 `test/pages/group_features/group_feature_store_test.dart`。验证应包含特权撤销/恢复、切群、迟到请求、同幂等键重试、消息来源与版本、下注退款、报表种类与目标、小屏和主题。真实设备、原生 SDK、报表送达和生产切换需另做联调，widget 测试不能替代。

调试日志仅在 Debug 创建观察器，凭据隐藏；Release/Profile 不启用三公日志。业务接口直接复用已有账号凭据，不建立新 Token 存储。

## 文件规模

`sangong_module.dart` 仍集中协调 host 生命周期和操作入口；`widgets/sangong_bet_preview_sheet.dart` 仍维护同一截止表单状态。它们超过 500 行时需检查职责，新独立功能不得继续堆入。接口已按配置、用户、账务、局和报表拆到 api/admin；代理管理已独立放入 agents。不要通过共享全部私有状态的 part/extension 做表面拆分。

用户代理群：`agents/user_group/` 在用户详情复用 `AppDialog.prompt` 输入群 ID，`agents/data/` 保存个人归属。按旧 99chat 的 `AgentRebateApi.bindAgentChatGroup` 保存行为迁移，保留 OpenIM 原始群 ID。无需预先群级绑定或目标群管理员身份，入口根据登录用户＋群 ID 定位所属厅。接口与迁移说明见 `docs/sangong-go-v2-api.md` 的 6.1 节。

固定厅代理入口：`agents/halls/` 维护厅模型、归属加载页及所属厅标签，复用现有代理总览、团队、个人页及权限保护。`SangongAgentHallPage` 校验唯一厅后直接打开页面，拥有独立运行上下文并在离开时释放；不保留选厅偏好或切换入口。`SangongPageRoute` 为子详情传递固定上下文。此入口承接旧 99chat 的单一群归属体验；服务端保证群级唯一，个人访问仍需明确授权。测试在 `test/pages/group_features/sangong/agents/halls/`，协议见文档 6.2 节。
