# Mark Six 与代理模块

公开入口：`mark_six.dart` 导出 `MarkSixFeatureHost`、`MarkSixModule`。Host 的 builder 参数为 `(BuildContext, Widget entry, Widget overlay)`；entry 当前为空，overlay 放入有界聊天 body Stack。Module 的 `openDrawHistory / openAgent / openCurrentRebate / openRebateHistory` 都接收 `(BuildContext, GroupFeatureContext)`，使用当前应用导航与认证传输。

群类型按 `ex.gameType` 数字区分：0 普通群、1 三公游戏、2六合彩代理、3六合彩开奖、4 三公代理。类型为 3 时，右侧开奖把手与工具箱「开奖记录」直接显示，不要求 `enabled`、`drawHistoryEntry` 或机器码先配置。缺少机器码时允许进入页面并显示配置缺失，不发送无绑定请求；绑定存在时仍使用该群真实机器码。其他类型保留既有显式开奖开关，代理与反水权限仍由原权限链判断。群类型更新会重建 Host 上下文并关闭旧预览，回归见 `mark_six_entry_visibility_test.dart`。

## 参考与视觉

布局、交互和独有图片来源：`qiuiqu6666/99chat`，Apache-2.0。此模块保留 OpenIM 会话与 root 提供的 `GroupFeatureApi`，不引入参考项目的 Tencent SDK、JWT、全局 client 或独立 WebSocket。

| 实现 | 参考文件 | 布局 |
| --- | --- | --- |
| 开奖浮动入口 | `lottery_chat_entry.dart` | 右边热区 40 × 56，图形 28 × 48，初始 y 为聊天可用高度的 0.3，左侧圆角 14 |
| 开奖抽屉 | `lottery_drawer.dart` | 宽 88% / 最大 520，高 160，左内边距 10，圆角 16，黑色 12% 遮罩，右滑进入 280 ms，展开 380 ms |
| 结果、预测、统计、宣言 | `settings/test_page.dart`、`lottery_dashboard.dart` | 展示参考实际公开的四个 tab；最新球 60 / 预览 52，表头 34 / 行 36，flex 100/44/62/38/38/30/30/30/38/38 |
| 开奖导航 | `settings/test_page.dart` | 60 高渐变导航，leading 64，品牌/群名两行 18/12；品牌取当前群配置，不捏造参考仓库固定运营品牌 |
| 代理浮动入口 | `agent_rebate_floating_entry.dart` | 显/查/反/历/隐 58 圆，间距 10，拖动后吸附边缘，位置按账号与群保存；初始左侧避免与三公右侧控件覆盖 |
| 当前反水、历史、下级、详情 | `agent_rebate_*_page.dart`、`agent_rebate_summary_card.dart` | 页面内边距 16，卡片圆角 16，指标两列、标签 12 / 数值 15，详情高亮数值 18；日期采用参考的预设选项 |

球红/蓝/绿分别 `EF2F4E / 007AFF / 00B25E`。暗色基底使用现有 AppTokens，加载、头像复用 LoadingView / AvatarView。文字放大时表格自动增高并缩放单元格，狭窄窗口允许内容滚动。

## 接口适配

下列是 **参考仓库的真实路径**，不是已确认在当前 Chat 后端部署的接口。当前后端若未实现，页面显示实际失败与重试，不制造数据或成功状态。所有请求走 root 配置的业务 base URL 和当前 Chat token；不复制参考的固定 IP。

| 方法与路径 | 参数/返回用途 |
| --- | --- |
| GET `/api/v1/lotteries/mark-six-demo/config` | `machineCode`，公开规则与 windowOptions/宣言；`mark-six-demo` 是参考路径命名，不是 mock fallback |
| GET `/api/v1/lotteries/mark-six-demo/draws` | `machineCode,limit=100`；开奖 envelope 保留 `groupUid/serverTime/data` 与当前轮 |
| GET `/api/v1/lotteries/mark-six-demo/predictions` | `machineCode,window,page,limit=20`，校验 page/window/hasMore，最多保留 100 期 |
| GET `/chat/platform` | 仅打开宣言 tab 后按需读取下载链接，真实复制到剪贴板 |
| GET `/me/agent/rebate/current` | 当前个人、团队反水汇总 |
| POST `/me/agent/rebate/apply` | 级差申请；返回 status 必须可确认，缺失时只展示未知状态 |
| GET `/me/agent/rebate/apply/status` | 页面初始化恢复上次级差申请；后续按钮触发仅前台每 2 秒查询，最多 30 次；仅 SUCCESS 判成功 |
| POST `/me/rebate/apply`、GET `/me/rebate/apply/status` | controller 支持个人申请契约；当前参考页面主按钮为级差申请 |
| GET `/me/agent/rebate/history`、`/me/agent/rebate/personal-history` | `startDate,endDate`，按日历史与合计，个人/团队切换 |
| GET `/me/agent/descendants` | `scope=all/direct,page,pageSize=100`；按需分页，去重，本机筛选与排序，保留缺父节点/循环节点 |
| GET `/me/agent/descendants/{userId}` | 当前下级详情，返回用户必须匹配 |
| GET `/me/agent/descendants/history` | `userId,startDate,endDate`；targetUserId、记录用户与日期有返回时必须匹配 |
| POST `/me/agent/rebate/history/export` | `startDate,endDate,fileType=CSV,includeDetail=true`，创建导出任务 |
| GET `/me/agent/rebate/history/export/{taskNo}`、`/{taskNo}/download` | 前者按需查询完成后才下载 binary；后者不将 token 写入 URL，采用现有文件保存/打开插件 |

代理请求固定 `X-Group-Id` 当前群，不用群列表中其他群的绑定。机器码只能来自群公开 ex/capabilities 的已确认绑定，无机器码时不发送请求。

## 数据与生命周期

预览与完整页共享 controller/repository；同时相同查询只发一次，成功查询缓存 30 秒 / 最多 64 项；手动刷新、当前群业务事件、前台恢复按需补快照。无 build 请求、无 module socket、无后台开奖 HTTP 轮询；本机倒计时不请求接口。统计直接计算已有最近 100 条开奖数据，预测在可见时才读取。

账号 guard 在请求前后执行；权限 guard 用 `capabilitiesCurrent` 单独保护私人查询、申请、导出，不限制公开开奖。群开关、绑定、revision、权限版本变更重建快照，并移除该 host 正在展示的旧 route 后释放旧 controller。分页、筛选/日期切换有 generation 防止晚响应覆盖。日区间按中国时间 07:00 → 次日 07:00 计算，最多含 93 个业务日。

当前级差汇总进入时合并查询汇总与上次申请状态，恢复结束前禁止申请；同页重复初始化合并正在执行的请求，不额外读取无可见按钮的个人申请状态。GET 状态缺失、未知或失败保持申请锁定，只允许重新查询；POST 返回 NONE 也视为结果未知。关闭后重新进入恢复到 PENDING/PROCESSING 时不会再次 POST，已确认 SUCCESS 保持申请禁用；只有服务端新状态回到 NONE/FAILED 且汇总的 `agentPendingRebate` 为有限正数才允许新申请。服务端仍须核验待结算金额、权限和申请幂等，客户端状态不能替代结算合同。

宣言来自配置，不复制参考营销文案；缺少配置显示空态。后台权限仍需由真实业务接口核验，前端隐藏按钮不能替代服务端鉴权。代理身份编辑/邀请绑定等管理员能力属于三公模块；本模块不以无效 JWT 或成功提示占位。

独立打开的开奖页也监听完整 `groupFeaturesChanged` 快照：仅自己的 Mark Six 开关、开奖入口、机器/租户绑定改变时清空旧数据、禁止旧请求并移除旧 route；其他游戏/直播变更与私人权限撤销不影响公开开奖。日期选择复用应用现有 `showSettingsActionSheet`，移动端与参考一致的 Cupertino 样式；参考桌面居中 ActionSheet 暂沿用应用已有移动 sheet。

联调缺口：参考「眯牌」刮开奖的可见权限/服务配置尚未确认，本轮不捏造权限开关；暂未迁移该手势。个人申请接口已保留 controller 适配，但 reference 当前实际 build 只有级差按钮，前端也只展示该按钮。开奖、预测、代理和导出服务仍需当前后端提供上述真实契约后才能完成端到端联调。

## 验证

测试目录 `test/pages/group_features/mark_six`：独立传输 fixture、查询合并/缓存过期/账号切换/权限撤销/分页晚响应/真实结算状态/UTC+8 日边界，实际页面亮暗与小窗口、入口权限、错误重试、预览展开测试。导出真实 UI 预览通过 `EXPORT_MARK_SIX_PREVIEW=1` 启用，输出至 `docs/previews`，默认跳过。fixture 仅存在测试目录。
