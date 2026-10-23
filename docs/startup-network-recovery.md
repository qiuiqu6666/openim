# 启动网络准备与 IM 独立恢复

## 审计与边界

3.0.1+2035 调用链：`main → Config.init → InitBinding → IMController 首帧 → StartupNetworkPreparation → YoumengRuntime.prepare → initOpenIM → SplashLogic.login → 首页`。

旧流程在 SDK 前等待线路准备。历史游戏盾必须先完成，直连采用约 2.25 秒的旧快照；iOS 原生最长 40 秒，再加业务验证 15 秒。失败无限退避，用户只有相同的加载提示。

新流程保持同一 SDK、鉴权和 GetX 所有者，替换启动准备：

1. A/B 三服务检测与游戏盾原生准备并行，直接使用首个验证结果，不等待历史线路。
2. 同一路线的业务 API `/healthz` 与 IM API `/healthz` 必须均满足 HTTP 200、对应 service、status=ok、无业务错误码。消息网关独立验证协议错误响应，不能只凭 HTTP 200。
3. 两项 API 成功即以 `degraded` 放行；三项均成功才为 `ready`。这两个名称描述探测结果，均不表示 SDK 已连接或消息同步已完成。真实连接/同步仍由现有 SDK 回调、IMConnectionRecovery、ApiConnectionHealth 和会话标题管理。
4. SDK 登录初始化本地会话后启动长连接，并不要求预检先完成 WebSocket。保留现有 token、登录失败处理、消息恢复和单实例约束，未改 Go Core 或线上服务。

## 所有权与状态

`startup/startup_network_preparation.dart` 是启动状态与路由唯一写入者。状态包括 initializing、probing、switching、ready、degraded、retrying、unavailable。结果带 endpoint、generation、checkedAt 和各服务状态。每轮还有 attempt；网络/前后台/手动选择使 generation 失效，旧回调只能留诊断记录，不能提交路由。

选择采用同步 RuntimeNetworkRoute 提交，避免异步偏好写入晚到。路由一旦交给 SDK 即锁定。首次初始化和登录期间，自动切线与手动运行时切线均被交接锁阻止；进入登录页或首页后才交给原有运行时恢复。IMController 合并并发 init 请求，并在登录未完成时拒绝切线。

运行时更换 SDK endpoint 仍复用原来的串行注销、teardown、init 和登录流程，这是现有 SDK 更换地址的约束；本次没有改写其架构，也不宣称运行时更换 endpoint 完全不需要重新初始化。保证的是启动竞争不会产生额外初始化或同时运行多个 Core。

SDK 初始化明确失败后提供单次重试，只重试该步骤，不重新选路，也不重复安装失败实例的消息监听。原生调用仍在进行时不会启动第二次初始化。

## 重试、游戏盾与界面

### 原生登录取消（recovery.52-login-cancel.2）

- Dart 登录等待 20 秒后保留同一个原生任务；状态监测发出带原登录 operation ID 的取消请求，不重复初始化或登录。
- Core 取消先通知登录上下文，等待登录工作线程完成数据库清理，再确认取消。10 秒取消等待超时不释放登录占用，也不允许新任务越过旧任务。
- 登录提交与取消共用互斥保护：已经提交的有效会话不会被取消；取消先发生时禁止启动连接和消息监听器。登录初始化失败恢复为未登录状态，不删除应用保存的凭据。
- Android 和 iOS 桥接在确认清理后结束旧调用，晚到回调不能清理新会话。Android AAR 和 ARM64 Debug APK 已重建；iOS 框架仍需在 macOS 使用共享锁定源码重建。
- Flutter 相关回归 138 项通过、2 项跳过；Core 构建测试通过。取消确认以实际清理结束为准，底层不可中断调用未退出时继续保持占用，不能把计时器到期当作取消成功。

- 直连单轮 2 秒预算；失败后先 0.5/1 秒快速重试，再 2/4/8/16/30 秒上限退避，使用 0.8–1.0 随机系数。直连重试不等待游戏盾。
- 系统离线/在线、Wi-Fi/移动网络变化、前台恢复使旧结果失效并立即新测。后台取消探测与待初始化游戏盾，前台重新检查。
- 游戏盾共享一个原生准备 Future。原生 iOS/Android 18 秒看门狗，Dart 20 秒超时与独立取消；取消在下一次 start 前按 FIFO 发送，晚到结果不能完成新任务。
- 原生准备成功后可以保留备用，后台业务探测不安装路由。游戏盾失败会重新检测直连。已进入应用后不再显示启动反馈。
- iOS 取消调度 HTTP 任务、监听与旧代回调。Android 清理不排在阻塞初始化后；旧实例不能完成新实例回调。避免取消尚未声明前台状态的 service 导致 Android 杀进程。
- 前 3 秒不显示额外提示；之后显示“正在连接…”。连续失败进入暂不可用状态后显示“暂时无法连接，网络恢复后将自动重试”，不提供手动线路选择或重试入口；网络恢复后自动重新检测。SDK 初始化单独失败时保留单一重试操作。
- 使用现有 AppTokens、Material 主题、SafeArea、可换行按钮、滚动布局和 liveRegion；无新增弹窗。亮暗主题与 2 倍文字测试通过。

## 日志

每次创建启动协调器生成 startupTraceId。记录平台/版本、网络类型、generation/attempt、各探测起止/耗时/服务状态、盾准备、选路原因、退避及状态转换、开始登录、进入登录页或首页。

正式包在 SDK 初始化前也保存日志：应用 cachePath 下 `startup_diagnostics/startup.jsonl` 和 `startup.previous.jsonl`，每份约 256 KiB，串行异步写入；写入失败不影响启动。仅记录预定义事件、线路编号、错误类型，不记录 URL、用户标识、token、密码、密钥或响应正文。

## 验证（2026-10-24）

- 回归命令：`flutter test --no-pub test/core/server_nodes test/core/youmeng test/core/session test/pages/splash`。
- 217 项通过、2 项跳过（原有跳过项、默认关闭的真实网络基准）。覆盖并发赢家、游戏盾挂起/失败/成功、API 与网关隔离、初始超时后恢复、网络变化、前后台、过期/错误响应、连续失败与恢复按钮、SDK 初始化和登录交接。
- 新原生准备测试覆盖共享 Future、20 秒超时、取消立即结束 Dart 等待、取消确认前不启动新任务、晚到回调和失败清理。
- 原来验证“必须优先等待历史游戏盾”的两个测试文件已由并行启动与 native_shield_preparation 测试替代。
- Android arm64 debug 构建通过；在 emulator-5554 安装，验证失败恢复面板与线路 2 操作。发现并修复 foreground-service 取消竞态后，进程持续运行。模拟器访问外部线路超时，不能据此声称正常联网登录/收发通过。
- 两个修改的 Swift 文件语法解析无错误。Windows 环境未执行 Xcode 类型检查、iOS 打包或 iPhone 真机验收。

## 性能比较

使用同一台 Windows 主机、两条公开线路，交替执行旧 TimedNodeProbe 与新 StartupRouteProbe，各 20 次，无登录、无修改配置。命令：

`flutter test --no-pub --dart-define=STARTUP_LIVE_PROBE=true test/core/server_nodes/startup/startup_latency_test.dart`

| 指标 | 原快检选择 | 新并行 API 放行 |
| --- | ---: | ---: |
| P50 | 1001 ms | 93 ms |
| P95（nearest-rank） | 1252 ms | 102 ms |

新流程没有旧版 1 秒决策等待，也不等待游戏盾初始化或消息网关预检。此基准是线路探测耗时，不包含 Flutter 冷启动、原生并行初始化开销、SDK 登录、消息同步；不是手机端 P95 或端到端启动 SLA。真实游戏盾、Wi-Fi/蜂窝切换、消息无丢失与 iPhone 3.0.1+2035 升级路径仍需真机回归。
