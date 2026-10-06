# 群直播

入口为 `GroupLiveFeatureHost`（聊天正文前普通 Column）和
`GroupLiveModule.openManage/openWatch`。页面及图片来自本地 reference-99chat 的真实
`group_live_top_banner.dart`、`group_live_inline_watch_banner.dart`、`group_live_authorize_page.dart`、
`group_live_online_live_scaffold.dart`、`group_live_push_info_page.dart`、`group_live_room_page.dart`
和 `group_live_tip_sheet.dart`；手机使用 56px 顶栏、16:9 边看边聊、20px 表单卡片和 52px 主按钮。
六张 `assets/img/group_live_*.webp` 使用现有 assets/img 目录声明，不新增依赖。

管理入口由 `LiveEntryPage` 在同一路由内分流：先校准当前场次和缓存权限，
已有预约、已授权或直播中场次直接进入推流配置；无场次才显示创建表单。
校准失败显示重试，不视为无直播。创建表单复用入口的「无活动场次」结果，
首轮不重复查询 current；关闭入口会取消尚未完成的场次读取，返回 Future 在实际退出后完成。
仅有观看权限时进入观看页面；读取推流密钥仍必须满足服务端 `canPush`。
权限校准期间若群摘要已确认换场，再校准当前场次，避免沿用过期的「无活动场次」结果。
从此入口创建预约直播后也直接进入待开播配置，离开配置后返回原来的群聊。

推流配置页底部只有管理主按钮：预约／已授权显示「撤销直播」，直播中显示「结束直播」。
只有 `canManage` 才能操作，顶栏保留手动刷新。结束成功按后端确认的场次回写并返回。
确认框打开期间状态变化必须重新确认；后台收到成功结果在恢复前台后发布一次。
返回只关闭当前推流路由，覆盖其上的直播教程关闭后再返回，避免误关其他弹窗。
入口按钮保留橙红粉渐变和主播粉色环；创建内容上移 24px，图左右 24px、卡片左右 16px，
名称最多 10 字、描述 30 字并在字段右侧计数。观看底栏使用 44px 主播头像、15px 标题和描边全屏按钮。

## 服务适配

2026-10-05 已按用户提供的现有后端「群直播」文档对接以下业务协议。
共享 GroupFeatureApi 使用当前 Chat 服务地址、当前 Chat token 和独立 operationID，
不会使用 Tencent JWT、IM token 或阿里云密钥。404/501、权限拒绝、网络错误和数据不完整
均显示真实错误，不生成虚构的预约、推流地址或支付成功。可以通过共享 API 的 pathPrefix
调整代理部署前缀。

| 方法 | 路由（前缀 `/group-live/api/v1`） | 请求 / 返回 |
| --- | --- | --- |
| GET | `/groups/:groupID/live/current` | `{active:false}` 或 `{active:true,session:LiveSession}` |
| POST | `/groups/:groupID/live/authorize` | `anchorUserId,roomName,description,scheduledStartAt`；立即开播为 `null`；返回场次、完整摘要和同步状态 |
| PATCH | `/groups/:groupID/live/schedule` | `roomName,scheduledStartAt`；返回场次 |
| POST | `/groups/:groupID/live/stop` | 返回已结束场次 |
| POST | `/groups/:groupID/live/revoke` | 返回已关闭场次 |
| GET | `/live/:sessionID` | 场次详情 |
| GET | `/live/:sessionID/play-info` | `liveSessionId,protocol,playUrl,fallbackFlvUrl?,fallbackHlsUrl?,expiresAt?` |
| GET | `/live/:sessionID/push-info` | `rtmpServer,streamKey,expiresAt?,obsHint?`；仅 canPush |
| POST | `/live/:sessionID/tip` | `currency,amount`（整数最小单位）,`payPin,clientOrderId,memo`；返回 `tipId,liveSessionId` |

场次字段为 `liveSessionId,groupId,status,roomName,description,anchorUserId,version,scheduledStartAt,expireAt,endReason`。
状态为 SCHEDULED/AUTHORIZED/LIVE/ENDED/BANNED；公开群摘要 ready 映射 AUTHORIZED。
ID 均按 URI 组件编码；预约时间发送 UTC ISO-8601。管理只能使用 capabilities.canConfigure/canManage，
私人请求发送前检查 capabilitiesCurrent；推流密钥接受响应前仍检查私人权限。创建、改预约、结束及打赏收到合法成功 DTO 后按已提交处理，权限事件不能把成功变成未知；账号／群守卫仍在响应前校验。公开观看只检查账号/群成员 sessionCurrent。
管理页面成功回调 onStateChanged 供宿主按群重新获取群资料。
保存成功、推流地址复制成功与打赏入口异常统一复用程序现有的 `IMViews.showToast` 居中提示，
沿用全局样式和自动消失时间；保存后的页面跳转不会移除提示。异步提示保留账号、场次和前台守卫。
只有服务端返回的有效 `groupFeatures`（schemaVersion=1、revision 整数）才回写摘要，不自行增加版本。
`imSyncStatus=pending` 仍显示保存成功；业务摘要比已知 SDK 镜像新或镜像缺失时，共享仓库保留该已提交摘要，旧或非 JSON SDK 镜像不能擦除它。
`LivePermissionState` 为已打开的直播页刷新当前权限快照，创建前 `canPush=false` 不会阻断保存后的推流入口。

## 请求与播放器

聊天首帧复用账号共享仓库的 `liveFeature` 公开展示投影，已有直播入口无需等待 current 再出现；已接受的 `active:false` 也会复用，避免旧 SDK 摘要再次显示已结束的入口。没有投影时沿用公开群摘要。打开群聊同时查询 current 校准真实状态，即使 SDK 镜像暂未带直播摘要也能显示直播。
回到前台在未观看时再次校准，原先无直播也会检查；首屏不获取播放或推流凭据，进入观看才读取场次和播放地址。
直播业务返回的有效摘要同步到账号共享仓库；current 仅返回真实场次或 active=false 时，独立的公开显示状态也会更新角标，不伪造群摘要或 revision。
公开投影只用于展示，不授予管理、推流或打赏权限。权限更新或普通父级重建不会重建未变化的同场次 DTO，已接受的场次版本和状态继续保留；实际公开状态变化仍更新入口，结束或换场释放旧观看状态。
会话、归档和“我的群组”共用 `GroupLiveListScope`：实际可见头像报告群 ID，`GroupLiveListSync` 去重并最多 2 并发查询单群 current。打开列表、切回标签和恢复前台立即校准；无完整摘要的直播变更通知合并 250ms 后定向补查，完整摘要直接更新。
参考 99chat `group_live_index_sync_service.dart`，列表显示期间每 45 秒仅为可见群兜底检查；隐藏标签、路由覆盖、后台、最后一个可见来源离开及账号失效会取消请求和计时。单个群滚出再进入复用成功缓存，失败负缓存 30 秒，界面重建不重复查询。
没有摘要的 current 显示状态能抵抗 SDK 单纯缺摘要；新有效群摘要、明确损坏的数据、退群及退出账号仍清除旧显示状态。业务群版本、个人权限和播放凭据继续各自维护。
查询按群、账号和 API 实例隔离，关闭或切换时取消；较新群摘要取消旧读取，避免结束或换场后被迟到结果恢复。
聊天入口调用 current 时传入已显示场次作为 `minimumSession`。同场次响应的低版本在回写群摘要、发布公开投影或通知任何共享观察者之前被拒绝，不能先让入口回退再恢复。合法的 `active:false` 和新场次响应仍正常生效，并继续受账号、群与摘要版本守卫约束。
聊天入口的后台 current 校准失败时保留已接受的直播入口，不在聊天正文显示错误行或重试按钮；后续通知与前台恢复继续校准。进入观看及管理后的实际操作错误仍由对应页面处理。
在途读取期间的直播变更事件合并为完成后一次补查，普通界面重建不重复请求。
同一观看状态合并在途请求，同场 SDK 摘要更新合并 250ms 后校准，恢复应用时校准；结束和换场立即释放旧场次，不额外查询旧场次。
内嵌等待提示共用固定图标槽，加载时保留刷新按钮的实际布局尺寸，首次读取和手动刷新都不移动提示。摘要没有场次 DTO 版本；同场次状态或版本输入实际变化时校准，被拒绝的同状态旧版本及普通父级重建不触发额外加载。
等待和播放状态均提供全屏、静音及移动端系统投屏入口。`GroupLiveWatchSurface` 的全屏路由复用同一个 `LiveWatchState`，可见性与转场占位合并管理，进入/退出不取消等待中的请求，也不重建正在播放的解码器。结束、换场和离开只关闭自己的全屏路由，不弹出覆盖其上的页面。
全屏填满当前窗口并使用 `AppSystemBars`/`SafeArea`，保持应用既有方向策略；退出回到原聊天位置。静音偏好在首次播放前生效，进出全屏、凭据更新和重连继续沿用；快速点击合并原生音量写入，声音设置失败提供重试。`LiveWaitingView` 复用既有等待几何和 `LiveWatchingBottomBar`，投屏模块及原生接入见 [casting/README.md](casting/README.md)。
播放器没有 4/12/45/60 秒常驻轮询。预约提供手动刷新。推流密钥在权限成立且非预约状态时按需取，
过期一次性禁用复制/二维码，用户刷新才重新取。
播放凭据按 `expiresAt` 提前续签，续签任务归共享播放器所有；后台、覆盖、结束、换场和离开取消任务与在途读取。没有有效期时不启用定时续签；失败采用退避，不密集重复请求。

单账号单场次的观看面共享一个 native video_player controller；另一场次会替换旧播放器，
全屏使用同一 controller 并隐藏原视频绘制，普通页面覆盖暂停，返回/恢复重连直播边缘。
控制器先释放旧播放器再创建新播放器，支持静音、12 秒启动超时、有限 HTTP FLV/HLS 备用地址和重试。
重试刷新签名并原位更新 controller，已结束场次立即释放播放器，同版本或更旧 LIVE 不能恢复已结束场次。
不注册聊天监听器、不发消息、不改变聊天已读数。

`video_player` 不支持 WebRTC/TRTC/LEB：只接受真实 HTTP 备用地址。iOS 等平台不支持某一格式时自动尝试
服务端提供的下一格式。现有依赖没有渲染首帧回调，加载动画在 initialized 后播放 position 首次前进时结束；
这与参考 media_kit 的精确首帧信号有差异。仅前端不能产生直播源，OBS 推流仍需要实际直播服务。

## 打赏与支付

复用 OpenIMProfileService 的真实支付密码设置、PasswordPaymentSheet 和 FundPendingStore。
服务在 live capabilities 明确返回 `tipCurrencies`，元素为 `{code,label,decimals}`。现有后端只接受 USDT/TRX（6 位）、BI99（2 位，显示名 99BI）；提交还校验币种在当前能力列表中。
未返回币种时显示“打赏币种尚未配置”。通用金额模型保留其他旧码解析，不代表直播接口允许这些币种；不自动互换币种码。
金额使用 BigInt / 现有 FundAmount 转换整数单位，不使用浮点舍入，限制 JSON 安全整数范围。

首次发起前按服务地址、账号、群、场次保存 clientOrderID 和原参数，绝不保存支付密码。
页面关闭、进程重启或网络超时后重试同一订单；另一个窗口不能覆盖待确认记录。
未知结果锁定金额/备注；只有首次明确拒绝可以清除待确认，已存在未知结果的后续失败不清除。
服务端须对 clientOrderId 保证幂等、真实鉴权和扣款原子性，前端不能替代。

## 现有服务边界

公共直播状态由进入群聊时的 current 查询校准，并继续响应 OpenIM 群资料变化，不要求服务端发送群业务广播；主播收到定向权限通知后重查个人能力。群公开版本与个人权限版本分别比较，查询携带的旧公共版本不覆盖已接受的新摘要。权限拒绝会失效共享能力快照；云配置缺失、已有活动场次、状态失效及资金错误均显示对应提示。

手机只调用用户接口。`10009 /live/config` 的管理员配置、腾讯云密钥与推流回调由后端管理；手机不携带管理员令牌，也不将签名播放地址或推流密钥存进群 `ex`。推流页提供 OBS 推流地址及说明，真实 `LIVE` 以云端回调为准。

## 验证

`test/pages/group_features/live/` 覆盖 adapter 真实请求、权限和账号迟回包、未开通服务、金额精度、
待确认支付保存、单播放器、暂停/迟初始化、结束防复活、请求合并、等待提示位置稳定、场次重建不重复读取、全屏路由及返回、静音竞态、系统投屏桥接和日夜布局。
`GROUP_LIVE_PREVIEW` 指定图片前缀时导出 create/push/waiting 六张真实页面 PNG，
使用 Windows 微软雅黑仅改善人工检查时的中文字体，不改变生产字体。
