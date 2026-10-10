# 钱包入口

首页底部钱包与“我的 → 数字资产”都会立即切到钱包标签，不等待 IM 重连或支付密码接口。`WalletEntryCoordinator` 在页内检查支付密码；首页不持有密码，不以本地缓存代替后端状态。

`WalletEntryPlaceholder` 按真实 `WalletHomeView` 的总资产、今日变动、三个操作按钮和代币列表布局显示骨架，复用钱包间距、宽度和亮暗主题 token。骨架不包含假金额或可用交易操作；静态占位避免动画引起不适。按用户补充要求，请求失败（包含现有网络层的超时）时继续保留骨架，不显示错误提示或“重试”按钮；支持下拉刷新或再次点击钱包标签重新检查。

复用 `OpenIMProfileService` 和 `TradePasswordPage`：`GET /chat/fund/pay-password` 读取 `data.set`，未设置时用根导航打开现有设置页；设置页 `PUT` 成功并返回 `true` 后重新查询状态，确认生效才展示资产和操作。取消设置后留在钱包占位页，可再次点击设置；异常响应不会放行。每次进入或点击重试都会重新检查，连续点击不会并发检查。

后端默认值兼容：2026-10-11 只读核对 `/www/wwwroot/openimservice/chat/internal/api/chat/fund.go`、`internal/rpc/chat/fund_pay.go`、`pkg/protocol/chat/chat.pb.go` 及 tools v0.0.50-alpha.113 的 `apiresp` / `jsonutil`。`GetFundPayPasswordResp.Set` 使用 `json:"set,omitempty"`，经标准 JSON 编码后 false 返回成功的 `data:{}`。客户端仅将该空对象视为未设置，不将 null、字符串、数字、未知字段或业务失败当作已设置。真实 HTTP 返回到设置页的集成回归位于 `wallet_password_status_contract_test.dart`。

`WalletEntryGate` 首次通过检查才挂载真实资产页面；之后重新检查时隐藏已挂载内容，并通过 `Visibility` / `TickerMode` 暂停钱包刷新，保留同一会话的控制器、筛选和滚动位置。登录会话变化会丢弃旧内容。顶栏扫码、通知入口也要在检查通过后启用。

协调器由首页创建与释放；选择其他标签取消待完成检查。请求同时归属钱包标签、路由、登录账号、服务地址和 token，响应时仍在后台、已退出登录、已切换账号或已关闭页面的请求不能打开设置页或展示资产。覆盖或后台期间失效的响应也会结束检查，返回后可下拉重新加载。设置页服务同时检查原会话，防止在旧页面输入密码时误用新账号的 token。钱包交易操作原有的密码检查保持独立。

本地 99chat 的 `lib/src/pages/home_page.dart` 与 `lib/src/pages/wallet/wallet_pay_pin_guard.dart` 为入口和密码流程参考；参考仓库在交易前检查密码。本实现按用户 2026-10-07 确认的交互先打开钱包、显示真实布局骨架，检查通过后展示资产；没有新增设置页、资产接口或绕过交易前检查。

对应测试位于 `test/pages/wallet/entry/`。

排查持续骨架屏时，在 Debug 控制台筛选 `[WalletLoad]`，可区分入口检查失败、请求未返回、路由／会话失效以及资产加载。日志字段与隐私边界见 [钱包加载日志](../../../services/fund/diagnostics/README.md)。页面交互与错误展示规则不变。

测试覆盖入口协调、真实首页两入口、重连与网络失败重试、根导航、PIN 设置与返回、取消与重复点击、会话和生命周期、五种语言提示、真实状态接口响应契约，以及亮暗主题 / Android / iOS / 窄屏大字体骨架布局。`WALLET_ENTRY_PREVIEW_DIR` 可导出真实组件截图。测试不会写入线上支付密码。

验证（2026-10-07）：本目录 43 项测试及修改范围 analyze 通过，已检查 Android / iOS 亮暗主题实际组件截图，Android debug APK 构建成功。扩大回归结果为 77 项通过、12 项可选预览跳过、29 项失败；失败集中于未改动的资产列表、主页布局/状态、趋势测试，包含固定 CNY 仍按可切换币种断言、未知显示值仍按 `--` 断言等，与当前主页文档不一致。本次没有修改这些断言。未安装真机或执行 iOS 原生构建。
