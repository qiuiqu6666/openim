# Core SDK 后台消息恢复修复

本方案从 OpenIM 官方 `v3.8.3-patch.15` 源码修复后台回前台时消息同步失败后无法恢复的问题。补丁包含实现和测试，保留官方 patch.15 的历史消息、重复消息修复。

## iOS 与 Android 共用 recovery.10

两端以 `manifest.json` 的官方提交和补丁 SHA256 为准，原生版本为 `v3.8.3-patch.15+recovery.10`。iOS 使用 macOS/Xcode 从同一份补丁源码构建，不再使用未打补丁的官方预编译包。以下旧版 recovery.1–6 的接入状态和 Windows 验证记录为历史记录。

在 macOS 安装 Go 1.24.0、Xcode 和 Python 3 后执行：

```sh
native_sdk/patch15/build-ios.sh
./tool/flutterw build ios --release --no-codesign
```

Go 不在 PATH 时可以设置 `GO=/absolute/path/to/go`。脚本创建独立源码目录，验证官方提交与补丁哈希，使用 Android 清单固定的 gomobile/gobind，执行四个 Core 包的测试，并编译 iOS arm64 和模拟器架构。完成校验后安装到本地插件的 `Frameworks/OpenIMCore.xcframework`；旧 Framework 保留在本次构建目录以便回退。每次输出的 `verification.json` 记录来源、版本和二进制哈希。

`fetch-ios.ps1` 仅用于获取未修复官方包作对照，不用于当前发布。生成物仍被 Git 忽略，新机器需要运行构建脚本。Core 源码对齐不代表 iOS 后台执行策略与 Android 相同；真机后台恢复、首次登录和消息收发需要单独验收。

## 2026-10-13 同步让出实时消息处理（recovery.3）

- `MsgSyncer` 收到实时推送时取消同步任务当前的网络等待，等待该任务退出后串行处理推送，再恢复一项合并后的同步任务。序号提交、落库回执和去重沿用原链路，不并发修改同步游标；重复唤醒不积累同步任务，退出会取消并等待当前同步任务。
- 会话 worker 的同步开始／元数据任务允许被后续消息、发送状态和会话更新中断。被中断的同步返回取消错误，不冒充完成；上层失败重试继续补齐。正常消息写入不被中断，两个任务不同时落库。同步发起的元数据子任务使用同一取消上下文并等待全部退出，避免后台任务持锁继续挡住消息。
- Flutter 可见聊天页在同步中仍能执行有界历史补读和最新消息恢复；历史窗口、日期定位、账号代次、并发读取额度和已读保护保留。
- 定向原生测试 42 项通过，相关 Go vet 和 Windows 全包 build 通过；Flutter 聊天恢复、连接、历史窗口回归 283 项通过、12 项跳过。新增故障测试覆盖同步请求不返回时实时推送先处理、同步恢复、重复唤醒合并、发送后会话更新抢占元数据等待，以及同步中最新消息补读。
- 四 ABI Android AAR 已构建为 `3.8.3-patch15-recovery.3` 并接入；构建源码与受控补丁的 27 个文件逐一核对一致（忽略换行符）。APK 构建与验证记录位于 `E:/openim/artifacts/sync-priority-20261013/`。尚未安装或进行真机收发、Go race 测试；iOS 本地补丁仍待 macOS 集成。

这项修复允许取消可取消的同步网络等待，不承诺中断正在执行的数据库事务或不响应取消的第三方操作。消息本身存在序号缺口时仍按原 SDK 规则补齐、提交和去重。

Android `3.0.1+2029` arm64 APK 已从独立源码快照构建成功，避免共享工作区插件注册文件在构建过程中变化。最终 APK 的 `libgojni.so` 与最终 AAR 经标准剥离后的文件 SHA256 相同，内嵌 SDK 为 `v3.8.3-patch.15+recovery.3`。安装包：`E:/openim/artifacts/sync-priority-20261013/99chat-sync-priority-2029-arm64.apk`；机器可读结果见同目录 `verification.json`。未安装设备，未将构建成功视为真机收发验收。

## 2026-10-13 连接与历史恢复补强（recovery.2）

本轮经用户授权修复；用户明确暂缓推送接入，因此未改生产服务端，未启用 FCM/厂商推送。

- 历史查询每次使用调用方锚点；补拉失败立即返回，不推进内部翻页位置。查重、更新、插入失败均上报，响应缺少目标会话不能当作成功页。
- 重连采用带随机抖动的封顶退避，后台失败至少等待一分钟；恢复前台可唤醒等待。保留低频后台重试，不宣称后台永不断线。
- Android 拨号绑定会话取消上下文，限制为 15 秒；退出关闭 socket，重试等待可取消，每个管理器只启动一组任务。协议错误后的读取任务可继续恢复。
- 关闭错误加锁、重连后清空旧原因。日志加入连接时间、重试次数、恢复耗时、最后 Ping/Pong/数据时间及 Close Code；1006 不冒充实际 Close 帧，超时不认定为 Android 杀后台。连接日志移除带 token 的完整 URL。
- Android 按 started Activity 集合上报可见状态；同一时刻仅一个状态上报。网络切换等待验证并合并重复回调，初始网络快照不主动断开健康连接。
- Token 过期与踢下线分开；原生分发异常向 Dart 返回错误。Flutter 缺口恢复在初始重试失败后保持单个 30 秒定时器，仅前台可读取且未完成时继续。

验证：Core 38 个顶层测试通过（本轮新增 7 个），相关 vet 与 Windows 全包 build 通过；四 ABI AAR、arm64 APK 构建通过。Flutter 定向 56 项通过；扩大回归 422 通过、12 跳过、22 失败。22 项在移除本轮相关 Dart 行为修改的隔离对照中均复现，涉及既有日期/搜索定位、已读及账号隔离，不计为通过。静态分析无 error/warning，4 个既有风格 info。

小米已保留数据安装 3.0.1+2028，JNI 返回 v3.8.3-patch.15+recovery.2；APK 原生库与 AAR 标准剥离后内容一致。真实消息收发对照、长时间锁屏、Go race 尚未完成。证据目录：E:/openim/artifacts/connection-repair-20261013/。

本轮没有数据库结构迁移；回滚可用上一稳定源码和 recovery.1 AAR 构建更高 versionCode，保留应用数据。下文 recovery.1 结果为历史记录。

## 来源与位置

- 上游：https://github.com/openimsdk/openim-sdk-core
- 标签：`v3.8.3-patch.15`
- 基线：`d6e0b549db904d0327d76ef7c9c283203879a095`
- 工作源码：`E:/openim/sdk-source/openim-sdk-core-recovery`
- 本地分支：`fix/background-message-recovery`
- 补丁：`0001-background-message-recovery.patch`，SHA256 见 `manifest.json`
- 旧 patch.12 源码和补丁仍保留，没有覆盖。

## 修复范围

| 场景 | 修复后的行为 |
| --- | --- |
| 补拉网络失败、消息/会话写入失败 | 向同步器返回失败，收到处理成功回执后才推进同步位置，不再把成功入队当成成功落库 |
| 回前台失败后再重连 | 失败保留缺口；同步状态随本轮结束释放，允许下一次恢复继续补拉 |
| 首次同步中断、部分会话已存在 | 读取未完成安装标记；所有必要同步成功后才标记完成 |
| 普通消息已落库，通知写入失败 | 分别提交两类同步位置，通知仍可重试 |
| 重复或乱序推送 | 检查完整序号连续性，按最大序号补齐缺口，不再只检查最后一条 |
| 重复响应和超时清理同时发生 | 重复响应立即返回错误；响应路由不再持锁无限等待，读取注册表也加锁 |
| 请求取消、发送队列满、弱网重试 | 请求具有统一截止时间，排队和重试可取消，已过期请求不会继续写网络 |
| 接收队列拥堵 | 处理回执具有截止时间，过期排队任务不执行；必要元数据同步使用该截止时间 |
| 同步流程在接收线程内通知会话变化 | 释放会话锁后直接通知，避免向自己的满队列等待入队 |
| 消息写入失败或部分写入后重试 | 未读进度在对应会话写入成功后提交，按真实序号去重；避免提前消费或重复增加未读数 |
| 单项处理或并行元数据任务 panic | 返回失败，保留后续接收处理能力 |
| 极大历史序号缺口 | 只生成当前批次需要的有限序号，包含整数上界测试 |

新增职责文件为 `internal/interaction/msg_sync_commit.go` 与 `internal/conversation_msg/sync_recovery.go`。原有大文件只做接收链路的局部修错，未进行无关目录或架构重构。

## 验证

2026-10-13，使用便携 Go 1.24.0 完成：

- 新增 28 个顶层故障回归测试全部通过；受影响三个包共 31 个顶层测试、7 个子用例通过。
- `go test ./pkg/common ./internal/interaction ./internal/conversation_msg -count=1 -timeout=60s` 通过（Windows，CGO=0）。
- `go vet ./pkg/common ./internal/interaction ./internal/conversation_msg` 通过。
- `go build ./...` 通过（Windows，CGO=0）。
- Android arm64、API 21、NDK 28.2.13676358、CGO=1 的 `go build ./open_im_sdk` 通过，包括原生 SQLite 编译。
- 格式检查和 `git diff --check` 通过。
- 完整补丁在官方基线干净 checkout 上应用、再次应用以及逐文件内容一致性检查通过，详见验证文件。

故障测试在修复前复现了取消后仍入队、重复响应阻塞、重复/乱序推送跳过缺口；日志保存在 `E:/openim/artifacts/sdk-core-recovery-20261013`。其余回归覆盖写入失败和恢复重试、首次同步、回执、未读数、异常接收线程及历史缺口。

官方联调测试包会在初始化时访问 `127.0.0.1:10002`，当前没有该服务，因此没有通过完整联调测试。单元测试使用故障注入数据库和模拟网络响应，不代表已完成真实 SQLite 故障注入运行测试或 Go race 检测。随后已完成 Android AAR、Flutter APK 和真机版本核验，见下文；完整消息收发验收仍待进行。

## 应用补丁

对上述官方 commit 的干净源码执行：

```powershell
./native_sdk/patch15/apply.ps1 -SourcePath E:/openim/sdk-source/openim-sdk-core-recovery
```

脚本检查基线和补丁哈希，已应用时直接返回，拒绝覆盖其他修改。旧 patch.12 的脚本不适用于 patch.15。

## 接入状态与剩余边界

2033 恢复首次登录/重装同步的居中进度弹窗，使用 SDK 实际进度；完成、失败或页面销毁时关闭。日常后台同步不弹窗，头部仍只检查 SDK/API 连接。原生库保持 recovery.6，首次初始化保护不变。连接和聊天恢复测试 48 项通过，静态检查仅保留 4 条原有 info。

recovery.6 修正新设备首次登录被真实消息流饿死的问题。小米 recovery.5 日志显示初始同步 1% 后立刻被推送取消、重启，并出现登录用户资料未就绪。首次初始化现在在消息调度器和会话工作器两层受到保护，期间继续接收并排队消息，必要资料及首批消息入库后按序处理；已完成初始化后的同步仍可让出执行权给实时消息。首次初始化标记仍只在存储确认后完成，退出账号仍取消全部任务。新增首次登录连续 20 条消息及外部会话更新用例，Core 共 46 项通过，vet 和 Windows 全量构建通过。全局同步弹窗保持移除，头部仍只表示 SDK/API 连接状态。

2032 arm64 APK 已保留数据覆盖安装到小米，安装版本及 recovery.6 原生版本已核实，现有聊天页面可显示消息。release 构建关闭详细 SDK 标准输出，尚未独立确认完整首次同步结束回调；未清除数据或退出用户账号。安装包、原生一致性校验和验证记录见 `E:/openim/artifacts/first-login-sync-20261013/`。

当前 Android 集成为 recovery.5，包含 recovery.4 的终止回调修复，并修正同步任务被自身资料通知取消的问题。会话线程给同步派生通知标记来源，延后到任务退出后串行处理，并使用登录会话生命周期；外部实时消息仍可抢占网络同步。新增测试验证自身通知不取消同步、不与同步并发执行、任务退出后通知仍有效。Flutter 不再显示全局居中同步进度弹窗，保留同步后的列表刷新和失败恢复。Core 44 项通过；本轮 Flutter 扩展检查 67 项通过、4 项失败，失败集中在现有列表快照/删除生命周期测试，修改前对照结果记录在 `artifacts/sync-status-20261013/flutter-tests-baseline.log`。真机与 iOS 尚未验收。

2026-10-13 recovery.4 修正 recovery.3 的同步结束事件生命周期：唤醒同步退出会取消单次任务上下文，之前排队的成功/失败通知因此被会话线程丢弃，导致状态停留在同步中。所有终止通知改用登录会话上下文，保留退出账号时的取消隔离。回归测试延迟消费成功和失败通知，确认任务清理后仍可处理、退出账号后失效。Core 43 项和 Flutter 连接/聊天恢复 48 项通过；Android 四 ABI AAR 已构建。设备实际收发与 iOS 验证仍待完成。

应用通过 `dependency_overrides` 使用 `local_plugin/flutter_openim_sdk`，保留 Flutter 适配层版本 `3.8.3+hotfix.12` 和 Dart API；该版本号不代表原生 Core 版本。没有修改共享 Pub 缓存。

- Android：本地 Maven 坐标 `io.openim:core-sdk:3.8.3-patch15-recovery.1`，来源为上述官方 patch.15 加本目录补丁。已编译四种 ABI；手机 APK 为 arm64。补齐旧 Android 适配层缺少的三个用户命令回调。
- iOS：改为直接包含官方 patch.15 `OpenIMCore.xcframework`，取消旧 patch.12 Pod 依赖。官方 Framework **不包含本地恢复补丁**；Windows 无法编译该补丁的 iOS Framework，尚未完成 macOS 的 `pod install`/构建。旧 `ios/Podfile.lock` 保留为上一次解析结果，需在 macOS 重新生成，不手写校验值冒充解析成功。
- 新 Android APK `3.0.1+2027` 已保留数据覆盖安装到小米 2506BPN68G。实际 JNI 返回 **`v3.8.3-patch.15+recovery.1`**，进程启动正常；启动后出现连接/同步失败，随后收到连接成功及同步完成回调。没有发送测试消息，不将这些回调视为完整后台消息验收。

## 重新准备原生库

Android 需要 Go 1.24、JDK、Android SDK 和 NDK。以下脚本创建独立构建目录、检查基线和补丁，固定 gomobile 版本，先执行 Core 回归再编译，不覆盖工作源码：

```powershell
./native_sdk/patch15/build-android.ps1 -Go /path/to/go.exe -AndroidSdk /path/to/Android/Sdk -AndroidNdk /path/to/Android/Sdk/ndk/28.2.13676358
# 可指定已存在的官方源码仓库，避免重新下载：-SourcePath E:/openim/sdk-source/openim-sdk-core-recovery
./native_sdk/patch15/fetch-ios.ps1
flutter pub get
```

生成的 AAR 位于 `artifacts/maven`；iOS Framework 位于本地插件的 `ios/Frameworks`。二进制被 Git 忽略，首次检出必须准备；Android 仓库使用独占模块解析，不会回退到官方 patch12。iOS 脚本验证官方压缩包 SHA256；macOS 也可从 manifest 指定的官方 URL 下载、验证并解压至同一路径，再运行 `pod install`。

本轮使用 gomobile `v0.0.0-20250711185624-d5bb5ecc55c0`。它在独立构建目录引入固定的 x/mobile，并按 Go 模块选择更新 x/image、x/sync、x/sys、x/text；未修改原始 Core 工作源码的 go.mod。完整二进制依赖见验证目录 `apk-native-buildinfo.txt`。

## 集成验证

- 14 个补丁文件与实际编译源码一致（忽略 Git 的 LF/CRLF 转换）。
- 构建目录 Core 三个受影响包回归通过；聊天恢复、历史分页、提示计数回归 **290 通过、12 跳过**。
- Android Java 桥接、APK 构建和签名验证通过；Gradle 依赖报告只有 patch15-recovery.1。
- APK 中 `libgojni.so` 与 AAR 经 Android 标准符号剥离后的产物逐字节一致；arm64 加载段为 16 KiB 对齐。
- 真机原生版本、安装版本与启动记录已核实。包哈希、构建日志和验证记录位于 `E:/openim/artifacts/core-patch15-integration-20261013/`。
- 后台消息完整区间、弱网、锁屏、连续切换和账号退出仍需实际收发验收；iOS 构建与验收未完成。

保持官方最新摘要策略：重连补拉每会话 1 条，唤醒补拉 10 条，完整历史继续由历史查询按缺口补齐。补丁没有引入跨消息表和会话表的统一事务，不承诺恰好一次回调；应用层仍需按消息 ID 合并。好友、用户和群通知的既有处理接口不返回内部错误，因此无法确认它们所有内部副作用都成功。持久错误或无法解析的消息会报告失败，仍需根据日志修正数据或协议，不能靠无限重试解决。
