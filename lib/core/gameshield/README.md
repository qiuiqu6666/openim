# GameShield Android / iOS 接入准备

当前完成的是 Flutter 接入层和 SDK 兼容检查，默认关闭。现有 OpenIM、账号、消息、APNs/PushKit 继续使用原来的所有权与生命周期；没有改写 OpenIM 核心。原始两份 60.1.10 SDK 尚不兼容，不能当作已完成真实游戏盾接入。

## 模块与行为

- `gameshield_settings.dart`：启用开关、运行时凭据和四个转发规则的选择条件。
- `gameshield_runtime.dart`：进程启动准备、防重复启动、超时与清理；客户端在登录页也保持运行，账号退出不停止转发。
- `gameshield_routes.dart`：检查 SDK 版本、就绪状态、TCP、唯一规则、回环地址和有效端口，然后整体生成登录 API、IM API、WebSocket 和客服服务地址。
- `startup/`：准备失败时显示重试页面，使用现有主题并支持亮暗主题、窄屏和滚动。
- `local_plugin/gameshield_bridge/`：Android / iOS 原生串行桥接；Android 的 `GameShieldRuntime` 由进程持有，Engine 解绑只释放通道，显式 stop 才停止代理。iOS 保持原有 Engine 生命周期。Android 网络事件合并，任务队列上限 32；真实代理验收仍需兼容的供应商 SDK。
- `tool/gameshield/check_sdk.py`：检查、可选暂存兼容 SDK，产生包含文件 SHA-256 的检查记录。

启用时的顺序：本地配置加载 → GameShield 启动 → 读取与检查入口 → 设置进程内地址 → HTTP 初始化 → ChatApp / OpenIM 初始化。不执行直连节点探测；失败时不挂载 ChatApp，也不静默回退直连。启动等待最多 20 秒，失败清理等待最多 5 秒；原生阻塞不能由 Dart 强制终止，停止任务在原生串行队列中等待执行。

本地入口不会写入服务器偏好；每次进程启动重新读取实际端口。禁止在 HTTP、IM 或通话仍在使用入口时调用 `close()`；只有调用方都关闭后才能释放。网络与前台事件只通知核心恢复，当前准备不主动重启 SDK或重分配正在使用的端口。

当前支持内置 `129.226.192.93` 的三个 HTTP/WS 地址，以及客服服务1 `http://129.226.192.93:8815`。客服 REST、附件上传和 `ws://129.226.192.93:8815/cable` 共用第四条 TCP 规则；相对附件与同源 HTTP 绝对附件地址也映射到该入口。客服会话存储继续使用原始服务地址，换端口不创建新的访客会话。自定义服务器不会自动套用生产转发规则；启用游戏盾时覆盖为自定义 `CUSTOMER_SERVICE_BASE_URL` 会拒绝启动。HTTPS/WSS 需要另外准备保留原域名/SNI 的传输层。这个模块不宣称所有流量已受保护：通话固定地址、LiveKit/WebRTC 的信令与音视频、其他对象存储/CDN、外部网页和推送仍需逐项配置与联调。iOS 后台挂起后仍依赖原来的 APNs/PushKit 链路。

## 先取得供应商兼容包

供应商必须保持公开的 `com.gameshield.sdk.mobile.Mobile/Client` 与 `GameShieldSDK` / `MobileClient` / `MobileNewClientWithToken` 接口，SDK 运行时版本为 60.1.10。

Android 需要隔离 `go.*` 类和 JNI 绑定，使用不与 OpenIM 重复的原生库名，并让每个 `.so` 的 PT_LOAD 满足 16KB 对齐。当前检查要求包含 armeabi-v7a、arm64-v8a、x86_64。

iOS 需要隔离 GoSeqRef、Universeerror、go_seq、cgo 等公共运行时符号；修改文件名不能解决。需要真机 arm64、模拟器 arm64/x86_64，修复 framework 的 `MinimumOSVersion=100.0`，交付静态 XCFramework。供应商可能需要统一构建 Go 运行时或提供经过隔离的实现，具体方式必须由供应商在真实 OpenIM 工程中验证。

检查工具只证明列出的结构条件通过，不能证明两个 Go 运行时一定可以共存，也不能替代真机与 Xcode 链接验证。当前原始包会被检查工具拒绝，不会自动复制进构建。

## 检查与暂存

在项目根目录执行，路径指向新取得的兼容包：

```text
python tool/gameshield/check_sdk.py android /path/to/GameShieldSDK.aar --stage
python tool/gameshield/check_sdk.py ios /path/to/GameShieldSDK.xcframework --stage
```

省略 `--stage` 仅检查。通过后文件进入 `local_plugin/gameshield_bridge/vendor/android/` 或 `vendor/ios/`，这些目录已忽略，不能提交凭据或供应商二进制。暂存会再次检查复制后的 SDK，并生成 `compatibility.json`；Gradle / CocoaPods 会核对文件摘要，禁止未经检查或已被替换的 SDK。已有暂存目录时拒绝覆盖，升级应先移出旧目录并重新检查。

未暂存 SDK 时，Android 桥接不加载 GameShield 类；iOS 使用 `canImport(GameShieldSDK)` 编译关闭的实现。默认构建只包含桥接代码，可以继续使用直连节点。

## 配置与启用

复制 `tool/gameshield/gameshield.example.json` 为同目录的 `gameshield.local.json`，填入完整移动端 GS2 凭据和转发规则信息。文件已忽略。密钥不进入仓库、命令参数、错误对象或桥接日志。

| 配置 | 含义 |
| --- | --- |
| GAMESHIELD_ENABLED | 默认 false；兼容包及四个规则准备好后设为 true |
| GAMESHIELD_TOKEN | 用户中心 Android / iOS 的完整 GS2 移动端凭据 |
| GAMESHIELD_AUTH_APP_ID / AUTH_GROUP | 登录与业务 API，源服务端口 10008 |
| GAMESHIELD_IM_API_APP_ID / IM_API_GROUP | OpenIM API，源服务端口 10002 |
| GAMESHIELD_IM_WS_APP_ID / IM_WS_GROUP | 消息 WebSocket，源服务端口 10001 |
| GAMESHIELD_CUSTOMER_SERVICE_APP_ID / CUSTOMER_SERVICE_GROUP | 客服服务1，源服务 `http://129.226.192.93:8815`，REST 与 `/cable` 共用 TCP 入口 |

GROUP 项完整名称也以 `GAMESHIELD_` 开头；GROUP 可空。先按 APP_ID、GROUP 和 TCP 筛选；同一个应用与分组包含多条规则时，使用 SDK 的 currentTCPPort 查询原始端口（10008、10002、10001、8815）对应的实际本地端口，再匹配唯一入口。查询缺失或入口仍不唯一则拒绝启动，不猜测列表顺序或固定本地端口。四个源服务需要四个不同的本地入口。App ID、组名使用控制台实际值，不假定 SDK 返回列表的顺序。缺少客服规则时不允许只保护其他三条连接后让客服走直连。

```text
flutter run --dart-define-from-file=tool/gameshield/gameshield.local.json
flutter build apk --release --dart-define-from-file=tool/gameshield/gameshield.local.json
```

在 Mac 上暂存兼容 iOS 框架后执行 CocoaPods 安装，并重新构建：

```text
cd ios
pod install
cd ..
flutter build ios --no-codesign --dart-define-from-file=tool/gameshield/gameshield.local.json
```

此本地定义文件用于接入联调，编译参数最终会进入客户端；生产凭据发放方式需要按实际部署确定，不能把客户端接入凭据当作服务端私钥。

## 验证与剩余工作

```text
flutter test --no-pub test/core/gameshield test/core/server_nodes test/node_endpoint_config_test.dart
python -m unittest discover -s tool/gameshield -p test_check_sdk.py
```

Dart 测试覆盖关闭时无原生操作、启动并发、四入口整体映射、不持久化临时端口、配置失败、缺失 SDK、凭据脱敏、超时、无效规则和初始化失败不进入正常应用。`test/pages/customer_service/customer_service_forwarding_test.dart` 覆盖客服 REST、附件上传、ActionCable、同源附件地址、端口变化时会话恢复以及自定义客服隔离。Python 测试覆盖 Android 类/库冲突与 16KB、iOS 公共符号、平台切片、异常元数据和文件摘要变化。

在当前 Windows 主机可验证 Dart 和 Android 默认构建。未完成：兼容 SDK 的真实启动、Android 16KB 真机、Mac CocoaPods / Xcode 编译、iOS 真机与模拟器、实际 GS2 凭据及规则认证、登录/收发消息/大文件、网络切换和前后台恢复、通话与媒体链路。
