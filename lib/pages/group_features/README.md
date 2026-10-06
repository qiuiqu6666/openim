# 群直播、三公与六合彩前端模块

参考仓库：`E:/openim/reference-99chat`，提交 `d7c3c65`（Apache-2.0）。

本次迁移保留当前 OpenIM 聊天、消息、群成员、登录和支付组件，移植 99chat 的业务页面、布局和资源。三个业务模块独立维护，共用群功能摘要、个人权限和账号范围的请求层。没有部署新后端，也没有把参考仓库的 JWT、租户或演示开奖数据写进生产环境。

## 页面与接入位置

| 模块 | 页面与交互 | 入口 |
| --- | --- | --- |
| 直播 | 56 高直播横条、16:9 群内观看、共用播放器的全屏、静音、重试、授权主播、预约、推流信息、停止／撤销、打赏 | 聊天顶部与工具箱“群直播” |
| 三公 | 游戏状态横条、可拖动运营浮窗、截止／结算、报表、规则、群绑定、成员、代理团队／查询／个人页面 | 聊天浮窗与工具箱；首次配置按 `canConfigure` 放行 |
| 六合彩 | 右侧开奖记录把手、开奖记录抽屉和完整页面、开奖历史／智能预测／已开统计／本群宣言 | 当前群 `drawHistoryEntry` |
| 六合彩代理 | 左侧代理浮窗、查询、当前收益、团队与下级、个人收益、历史区间和导出 | 群开关结合当前用户代理、历史权限 |
| 群列表与会话 | 99chat 的直播状态角标 | 共享 SDK 摘要与真实 current 显示状态，可见范围校准 |

直播教程弹窗直接使用 99chat 的 `assets/live3.webp` 原图，与
`showGroupLiveObsGuideSheet` 对齐：保留图文背景、拖动条、滚动内容和
48 高的「我知道了」按钮。移动端最多占屏幕高度 85%，桌面居中最多宽 420；
浅色／深色主题均保留原版教程图片。组件复用直播模块的背景和按钮，打开教程不请求业务接口。

群聊直播横幅按当前产品要求采用全宽矩形，移除参考组件的左右 4、上下 2 外边距及 20 圆角，
保持内容内部留白和「进入直播间」按钮样式。横幅总高度为 56，不增加导航下的空白。

`widgets/group_chat_feature_surface.dart` 负责聊天的有界布局，业务浮窗不占用消息列表高度。`widgets/group_feature_actions.dart` 对接当前工具箱；群聊设置页按用户要求隐藏“群功能”整行入口。`openim_common` 只增加通用 `extraItems` 插槽，不引用业务模块。

## 共享数据与权限

- `models/group_features.dart`：只解析 `ex.groupFeatures`，支持直播及三公、六合彩共存。非法 JSON、未知 schema 和缺失开关默认关闭。
- `models/group_game_type.dart`：单独读取群资料 `ex` JSON 对象顶层的数字 `gameType`（0 普通群、1 三公、2六合彩），与 `groupFeatures.revision` 无关。缺失、非法 JSON、非对象、字符串及未知值按普通群；只用于类型展示，不生成业务权限或改写扩展字段。三公运营浮窗只在类型为 1 且原有账号特权及显示偏好通过时显示，SDK 群资料更新后即时校准。
- `models/group_feature_capabilities.dart`：当前用户的权限与私有租户绑定；默认全关闭。群主、管理员身份不能代替游戏运营、代理权限。
- `data/group_feature_store.dart`：纯可注入仓库；现有群资料直接写入，缺失资料按最多 100 个群合批查询；行组件、页面 build 不发请求。
- `data/group_feature_runtime.dart`：复用 `IMController` 现有通知流，不重复注册 SDK listener。缓存以账号、Chat token 和节点隔离；被踢、退群与切换账号立即失效。
- `data/group_feature_api.dart`：发送当前 Chat `token` 和独立 `operationID`，支持 JSON、SSE 和导出文件。响应回来仍核对账号、token、节点。写请求超时会显示“结果尚未确认”，不能自动当作成功。

公共群版本 `revision`、个人权限 `capabilityVersion`、游戏快照版本各自比较。旧群事件不能覆盖结束状态；旧权限请求不能恢复撤销的权限。业务写入只接受服务端返回的完整群摘要，不在客户端自增版本或直接把入口改为启用。

SDK 群资料变化与业务摘要响应统一分发到已打开的群功能页面；解绑、关闭入口时清理旧绑定与权限快照。主动退出、会话失效和修改登录密码后的重新登录流程同时清除群功能缓存。

## 需要后端提供的契约

业务请求默认使用当前 `Config.appAuthUrl`。2026-10-05 按用户提供的现有后端群直播合同接入直播与个人能力；三公和六合彩能力本轮由服务端返回关闭。其他游戏业务路由仍是待后端提供的适配边界。404／501 会显示服务未开通，并提供重试；没有生产模拟数据兜底。真实云端推流、播放和扣款尚需登录设备联调，详见 `../../../docs/group-live-client-integration.md`。

| 契约 | 用途 | 状态 |
| --- | --- | --- |
| `GET /chat/groups/{groupID}/feature-capabilities` | 当前群的直播、三公、六合彩个人权限和确认绑定 | 已按现有直播合同对接；游戏能力为关闭 |
| `GroupInfo.ex.groupFeatures` 与 SDK 群资料事件 | 公共入口与直播摘要 | 直播公共状态使用群资料变化；主播个人权限使用定向 `groupFeatureCapabilitiesChanged` |
| `/group-live/api/v1/...` | 直播 current、授权、预约、停止、推流、播放、打赏 | 已按现有后端 DTO、同步状态和错误码接入 |
| `/sangong/api/v1/...` | 三公配置、运营、代理与 SSE | 适配参考代理路由，`X-Tenant-Id` 必须来自服务端确认绑定 |
| `/api/v1/lotteries/mark-six-demo/...` | 当前开奖实例的配置、开奖记录、预测和统计 | 保留参考服务的路由命名，查询 `machineCode` 来自该群确认配置，客户端不填演示实例兜底 |
| `/me/agent/...`、`/me/rebate/...` | 当前用户代理查询、申请、历史和导出 | 适配参考接口，后端按当前 Chat 身份授权 |

完整路由、DTO 校验与模块说明见 `live/README.md`、`sangong/README.md`、`mark_six/README.md`。前后端协议见 `../../../docs/group-feature-extension-design.md`。

`games.markSix.gameID`、`machineCode` 可以作为公共实例定位字段；不是凭据，也不能据此授权代理操作。三公 `tenantID` 只信任个人权限响应或当前群的业务绑定接口，不将群 ID 自动当作租户。

播放沿用项目现有 `video_player`。后端应提供设备能够播放的 HLS／MP4 地址及有效期。签名 URL 和推流密钥不写入 OpenIM 群扩展、不存入公共缓存。

打赏保留真实币种、金额和订单号，复用现有支付密码输入；不把平台币自动映射成参考仓库的 BI99。操作结果未确认时沿用原订单号核对，避免重复扣款。

## 减少请求的约束

1. 会话与群列表行直接使用共享状态；列表所有者仅校准实际可见群，去重并限并发，隐藏和后台停止，不在角标 build 中查询。
2. 首次进入群时个人权限最多一条合并请求，五分钟以内复用；未部署服务负缓存 30 秒，允许手动重试。
3. 直播凭据按需读取，群内与全屏共用一个播放实例和到期续签任务；后台、覆盖与结束停止续签，不复制 99chat 多层固定轮询。
4. 三公在有权限且可见时使用一个 SSE 与合并快照请求，后台暂停，断线退避重连。
5. 六合彩首次使用读取配置与开奖数据，预测、统计、代理页按打开的标签懒加载；通知、重连和显式刷新合并校准。
6. 角色、个人权限版本或绑定变化立即撤销旧上下文；后端操作仍必须实时鉴权。

## 验证与后续维护

测试位于 `test/pages/group_features/`。共享测试覆盖合批、缓存、版本、退群、过期响应、权限与 SSE 中文解码；模块测试覆盖真实数据适配、错误与交互。UI 预览仅在测试里提供固定数据，不进入生产代码。

页面更新先核对本地 99chat 源码，再改对应模块。保留当前项目深浅主题、安全区、Android／iOS、键盘与小屏适配。上线前需要真实业务后端联调；本地测试通过不代表直播平台、结算或扣款已经在服务器启用。

### 直播接入验证（2026-10-05）

- 按现有后端群直播合同完成接口、权限快照、提交结果、镜像同步及播放续签适配，详见 [接入说明](../../../docs/group-live-client-integration.md)。
- 下列回归命令共 227 项通过，6 项截图导出用例默认跳过；群功能源码与测试静态检查 `No issues found`。
- Android 调试安装包构建成功。直播创建、推流与等待页面的浅色／深色六张预览重新导出。
- 真实 OBS 推流、手机拉流、云端回调和资金扣款尚需配置好的服务与登录设备联调。

### 首轮迁移验证（2026-10-04）

- 群功能源码与测试的静态检查：`No issues found`。
- 群功能、现有群聊天资料、群列表、工具箱分页和本地退出会话回归：150 项通过；6 项截图导出用例默认跳过，另行启用后全部通过。
- Android：`flutter build apk --debug --no-pub` 构建成功；确认安装包包含 5 张直播图与 5 张六合彩图。
- Android／iOS 页面布局均检查了浅色、深色、小屏与权限变化。iOS 在本 Windows 环境中验证布局，未进行原生 iOS 构建。
- 截图与查看说明见 [页面预览](../../../docs/previews/group-features/README.md)。测试数据仅用于这些截图，不进入应用。

验证命令：

```text
dart analyze lib/pages/group_features test/pages/group_features
flutter test --no-pub test/pages/group_features test/pages/chat/group/chat_group_controller_test.dart test/group_list_logic_test.dart test/chat_toolbox_paging_test.dart test/core/session/local_session_exit_test.dart
flutter build apk --debug --no-pub
```

尚未完成的参考差异：六合彩「眯牌」手势缺少服务配置与可见权限，暂未迁移；直播继续使用现有播放器，其首帧判断与参考播放器不同，RTC 类型直播需要服务端提供可播放的 HTTP 地址。实际开播、开奖、结算与导出还需部署并联调上面的业务契约。
