# Shorebird 热更新维护入口

本目录负责 Shorebird 初始化、环境检查、基础包构建、补丁构建和设备预览。业务后端不负责补丁分发；现有版本接口与整包升级流程继续保留。

完成热更新接入需要：登录真实 Shorebird 账号、通过官方初始化绑定真实应用、发布 Shorebird 基础包，再在设备上验证补丁。仅新增脚本或通过普通 Flutter 构建不能证明热更新已经可用。

## 环境与账号

先按 [官方安装说明](https://docs.shorebird.dev/) 安装 CLI。Android 仍需要现有 JDK 和 Android SDK；iOS 的构建、补丁和预览在有 Xcode、CocoaPods 与签名配置的 Mac 上执行。

Windows 可以把 Shorebird 的 bin 目录加入 PATH，或设置本终端的安装目录：

~~~powershell
$env:OPENIM_SHOREBIRD_DIR = 'E:\flutter\shorebird'
$env:PATH = "$env:OPENIM_SHOREBIRD_DIR\bin;$env:PATH"
shorebird login
.\tool\shorebird\shorebird.ps1 doctor
~~~

脚本优先使用进程级 OPENIM_SHOREBIRD_DIR；Windows 当前终端未刷新时也会读取用户级的同名变量，最后从 PATH 查找。Windows 使用官方 bin/shorebird.ps1，避免官方批处理入口的参数数量限制；SDK 下载与 app_id 注册由官方 CLI 处理，脚本不代替登录或伪造应用配置。

Windows 实际调用 CLI 时，入口会临时追加进程级 Git 配置 core.longpaths=true，避免下载历史 Flutter SDK 时出现 Filename too long。已有 Git 环境配置仍保留，调用结束或失败后恢复原值；不修改系统或用户 Git 配置。直接运行官方 CLI 时需自行处理相同环境条件。

项目 SDK 固定在根目录 .flutter-version，当前为 3.41.6，与现有业务代码和本机工作 SDK 对齐。基础包构建显式传这个版本；补丁由 Shorebird 自动使用对应基础包的 Flutter revision，不传 --flutter-version。CLI 自身所需的 SDK 与应用构建 SDK 可以不同。见 [Flutter 版本说明](https://docs.shorebird.dev/flutter-version/)。

## 首次初始化

在项目根目录执行：

~~~powershell
.\tool\shorebird\shorebird.ps1 init
~~~

这个命令调用官方 shorebird init，会在已登录账号下注册真实应用，生成根目录 shorebird.yaml，并把它加入 pubspec.yaml 的 flutter.assets。检查生成的应用名称、app_id 和资产条目后再保存版本控制。已存在配置时脚本停止，避免重复注册应用；迁移账号或应用时先核对控制台，再按官方流程处理。

本项目采用内置后台自动更新：保持 shorebird.yaml 中 auto_update: true（默认也是开启）。无需额外的 Dart 更新器，不在聊天或通话过程中重启应用。补丁通常在启动后下载，下次冷启动生效。见 [初始化](https://docs.shorebird.dev/code-push/initialize/) 与 [更新策略](https://docs.shorebird.dev/code-push/update-strategies/)。

没有真实账号、有效配置或基础包时，不能宣称接入完成。实际构建与预览会检查根配置中的 app_id 格式、自动更新开关和资产条目，账号归属、可用基础版本与 YAML 完整语义由 CLI 校验。

## Windows Android 基础包

脚本区分参数预览、构建验证和正式发布三类操作：

- -DryRun 只输出调用目录与参数，完全不调用 CLI，可在初始化前检查参数。
- release / patch 默认使用官方 --dry-run，真正构建并验证，但不上传。
- 添加 -Publish 才会向 Shorebird 上传基础版本或补丁。直接使用官方 CLI 时，应自行添加 --dry-run；脚本的默认策略不会作用于直接 CLI 命令。

先检查参数，再构建：

~~~powershell
.\tool\shorebird\shorebird.ps1 release -DryRun
.\tool\shorebird\shorebird.ps1 release
~~~

需要正式注册基础版本时执行：

~~~powershell
# Google Play 使用 AAB；脚本默认就是 aab。
.\tool\shorebird\shorebird.ps1 release -Artifact aab -Publish

# 官网或其他渠道使用 APK。
.\tool\shorebird\shorebird.ps1 release -Artifact apk -Publish
~~~

同一平台的同一版本选择一次基础包发布流程；不要把上述两个发布示例连续运行来创建重复 release。按 CLI 输出的产物路径分发，也可按 [官方 release 文档](https://docs.shorebird.dev/code-push/release/) 从已发布的 AAB 获取 APK。

默认构建验证完成后，先用 -Publish 注册云端基础版本，再分发该次正式发布生成的产物；不要直接把未注册基础版本的验证产物投放到用户渠道。

脚本固定 Android ABI 为 android-arm64,android-x64，对齐 android/app/build.gradle 的 arm64-v8a、x86_64。release 使用 Shorebird 的 --target-platform 参数，patch 则在 -- 后转发同一参数给 Flutter。Gradle 清除 Flutter 3.41 注入到 buildTypes 的默认过滤列表，再由 defaultConfig 根据目标架构过滤；否则插件的 32 位库会混入仅编译 64 位 Flutter 运行库的包。分 ABI 构建仍交由 Flutter 的 splits 配置处理。调整 ABI 时必须同时修改 Gradle 和本脚本，并发布新基础包。

现有构建需要的 Dart 定义可以通过数组传入；基础包和它的补丁必须使用一致的构建参数：

~~~powershell
.\tool\shorebird\shorebird.ps1 release -FlutterArgs @('--dart-define=KEY=VALUE') -DryRun
~~~

正式基础包先按现有渠道发布。用户必须安装这个新基础包，才能接收对应补丁；先前使用普通 flutter build 生成的旧安装包不会因服务端上传补丁而获得热更新能力。每个仍需维护的基础版本分别发布补丁。版本号、签名、原生依赖与分发渠道沿用本项目现有流程。

当前准备上线版本为 3.0.1+22。用户已于 2026-10-11 确认，历史 3.8.3+235 仅用于内部测试，没有向正式用户或商店发布。内部测试设备若已安装构建号 235，不能按正常覆盖升级方式安装构建号 22；不要自动卸载或清除测试设备数据。正式分发前仍需核对渠道版本记录，并同步现有版本接口的最新版、下载地址及最低版本策略。

## Mac iOS

在同一项目、同一配置和锁定依赖下直接使用官方 CLI。以下验证命令不上传：

iOS 整包与 Shorebird 的 iOS 基础包、补丁构建共用 `ios/Runner.xcodeproj`：主应用 Bundle ID 为 `vip.99chat.ios`，通知扩展为 `vip.99chat.ios.NotificationService`，Debug / Release / Profile 一致。`shorebird.yaml` 的 `app_id` 继续使用已注册的云端应用 ID。包名变更须先在 Mac 上使用对应签名构建新基础包，后续补丁使用该基础版本。

~~~bash
shorebird login
shorebird doctor
shorebird release ios --flutter-version "$(cat .flutter-version)" --dry-run
~~~

准备分发基础版本时，执行不带 --dry-run 的同一 release 命令，再把生成的 IPA 按现有签名流程提交 App Store / TestFlight。iOS 用户同样需要先安装该基础包。Windows 入口会阻止实际 iOS 构建与预览，只允许 -DryRun 查看参数。

## 补丁与 staging 验收

ReleaseVersion 必须填写控制台中已经发布的准确基础版本，包含 build number。下面的 3.0.1+22 是本次准备上线的版本，只有对应平台的基础包已经登记成功并实际分发后才能用于补丁。脚本不允许 latest 或自动推断，避免补错基础版本。历史内部测试版本 3.8.3+235 的登记记录不能代替新版本登记。

~~~powershell
# 参数预览、真实构建验证、上传到 staging，按需逐步执行。
.\tool\shorebird\shorebird.ps1 patch -ReleaseVersion '3.0.1+22' -DryRun
.\tool\shorebird\shorebird.ps1 patch -ReleaseVersion '3.0.1+22'
.\tool\shorebird\shorebird.ps1 patch -ReleaseVersion '3.0.1+22' -Publish

# 默认 staging；可用 -DeviceId 指定测试设备。
.\tool\shorebird\shorebird.ps1 preview -ReleaseVersion '3.0.1+22'
~~~

Mac iOS 的等价流程：

~~~bash
shorebird patch ios --release-version 3.0.1+22 --track staging --dry-run
shorebird patch ios --release-version 3.0.1+22 --track staging
shorebird preview --platform ios --release-version 3.0.1+22 --track staging
~~~

preview 会下载、安装并启动该基础版本，通过指定 track 验证补丁。**Android preview 会重装应用并清除其本地数据，包括登录状态和本地聊天数据，必须使用测试设备与测试账号。** 它不能代替对已安装生产包原位升级、保留数据的验收；该部分用正常渠道安装的基础包另测。生产设备内置更新默认接收 stable，上传 staging 不会推给全部用户。先启动并等待下载，完全结束进程后重新打开，确认补丁已生效；切到后台再返回不等于冷启动。Android 预览生产签名包需要额外的 keystore 参数时，用 [官方 preview 命令](https://docs.shorebird.dev/code-push/preview/) 配置。

至少验证启动、登录、消息收发、会话恢复、通话、退出登录、无网络启动和补丁失败时继续使用当前版本。界面变更同时检查亮暗主题与 Android / iOS。补丁构建遇到原生或资产差异时先查原因，不绕过 CLI 检查；原生 SDK、权限、图片和字体等变更走新基础包。

## 发布 stable 与回滚

验收后在 [Shorebird 控制台](https://console.shorebird.dev/) 将已验证补丁的 track 改为 stable，或在项目根目录使用以下官方命令。先用 list 确认版本和补丁编号；set-track 与 rollback 会修改线上分发状态：

~~~bash
shorebird patches list --release-version 3.0.1+22
shorebird patches set-track --release 3.0.1+22 --patch 1 --track stable
shorebird patches rollback --release-version 3.0.1+22 --patch-number 1
~~~

把示例编号 1 替换为本次真实补丁编号。发布后观察现有崩溃监控与核心业务；发现问题时回滚对应补丁，设备在后续联网检查与重新启动后恢复先前可用补丁或基础版本。回滚不是强制立即重启在线会话。见 [staging 流程](https://docs.shorebird.dev/code-push/guides/staging-patches/)、[tracks](https://docs.shorebird.dev/code-push/tracks/) 和 [回滚](https://docs.shorebird.dev/code-push/rollback/)。

现有版本接口、下载地址、商店跳转和最低版本策略继续负责整包升级；热补丁不会替代新原生功能、签名变更、资源变更或首次迁移基础包的发布。

## 维护与核对

公开入口为本目录 shorebird.ps1；不修改版本号、原生工程或业务代码，不自动登录和发布。真实数据源是已登录账号下的 Shorebird 服务。参数按 Shorebird CLI 1.6.124 源码核对，升级 CLI 后复核 release、patch 与 preview 的帮助。

本地检查可使用 PowerShell 语法解析和 -DryRun 参数预览；真实云端初始化、Android / iOS 构建、设备补丁生效和回滚必须另外记录实际结果。参数预览成功不能替代这些验证。

## 3.0.1+22 上线准备（2026-10-11）

- 用户确认 Android 通过官网或链接分发 APK，iOS 同时准备；历史构建号 235 仅用于内部测试。
- Android 已使用 Flutter 3.41.6、Shorebird CLI 1.6.124 完成真实 release --dry-run。用户随后明确确认正式登记，已执行 release -Artifact apk -Publish，云端 release ID 为 889704，回查状态为 android: active。尚未发布补丁、安装设备或上传官网/商店。
- 正式发布产物归档在 E:\openim\release-artifacts\shorebird\android\3.0.1+22，含 APK、AAB、release-manifest.json、SHA256SUMS.txt、云端查询记录和 APK 签名/元数据。已复核最终产物的签名、版本、图标、引擎、配置与归档 SHA-256。官网应使用此目录的 app-release.apk；带 -validation 后缀的目录仅保留先前构建验证记录。
- APK 名称 99chat、版本 3.0.1+22、包名 chat.chat99.chatpro，签名 v2 验证通过。APK/AAB 均检查了自动更新配置、两个架构的完整 Shorebird 引擎，以及五种密度新图标与源图逐像素一致。
- 修复了打包时混入缺少 Flutter 运行库的 armeabi-v7a 插件库问题，最终只包含 arm64-v8a、x86_64；APK 从约 315 MiB 降至 254 MiB。32 位设备不属于本次支持范围。
- 发布配置和验证码桥接相关 6 项现有测试通过。未执行真机安装、补丁下载与冷启动、推送、通话和钱包实机验收，构建通过不能替代这些验收。
- iOS 主应用 Bundle ID 已按用户指定改为 vip.99chat.ios，通知扩展同步为 vip.99chat.ios.NotificationService，三个构建配置一致。清除了旧 Bundle ID 的固定 provisioning profile。发布证书和新 profile 仍待配置；Shorebird iOS 基础包与补丁构建使用同一工程标识。
- iOS 图标已从 launcher_icon/app-icon.png 重新生成，图标目录 19 项引用的尺寸和无 alpha 通道检查通过。当前原图为 254×254，1024×1024 商店图标为放大生成，正式提交前需验收清晰度。
- iOS Firebase 配置仍绑定旧应用：ios/Runner/GoogleService-Info.plist 的 BUNDLE_ID 为 io.openim.flutter.base，openim_common/lib/src/controller/firebase_options.dart 的 iosBundleId 为 io.openim.flutter.full.NotificationService。必须用注册 vip.99chat.ios 后取得的真实配置同步两处，不能只改字符串冒充注册完成。
- 当前执行环境为 Windows，iOS 尚未构建。需在 Mac 上完成签名配置、Shorebird 基础版本登记和 IPA/设备验收。

## 历史接入验证（2026-10-05）

- 已通过已有账号完成真实登录和初始化。应用为 OpenIM Flutter，app_id 为 cd009261-2d7d-4e4d-9fdc-dc9d3d16b6ec，auto_update 为 true，配置已加入应用资产。
- Shorebird CLI 1.6.124，应用构建使用 Flutter 3.41.6；版本文件已与现有代码使用的 SDK 对齐，保留接入前的依赖包版本。
- Android 3.8.3+235 的真实 release --dry-run 通过，AAB 与 APK 均已生成；APK 内已核对 Shorebird 配置以及 arm64-v8a、x86_64 引擎和应用库。
- 随后已用 -Publish 正式登记 Android 3.8.3+235，云端 release ID 为 875158，查询状态为 android: active；patches 列表为空。该版本可作为测试基础包，正式上架前仍需核对现网版本号。
- 正式发布产物已复制到 E:\openim\release-artifacts\shorebird\android\3.8.3+235，包含 app-release.apk、app-release.aab、release-manifest.json 和 SHA256SUMS.txt；复制后的 SHA-256 与该次构建产物一致，避免清理 build 目录时丢失。
- platform_config_service_test.dart 与 aliyun_captcha_bridge_test.dart 共 6 项测试通过；发布入口参数、错误处理、环境恢复及 tool/flutterw 版本检查通过。
- 最终 shorebird doctor 所有检查通过。按用户选择，未安装到已连接的设备，未提交应用商店，未分发任何补丁。iOS 构建、真机补丁下载与冷启动生效、数据保留和回滚仍需实际设备验收；Windows 本机无法完成 iOS 构建。
