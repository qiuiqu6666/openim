# 同进程原生消息通知：阶段一验收版本

## 所有权

- `NativeIMRuntime` 位于本地 OpenIM 插件的 `runtime/`。唯一的进程级生命周期管理者，保留真实 Go Core AAR。
- `IMService` 是同进程普通 Service，不使用 `:im`、AIDL、数据库迁移、WakeLock、定时拉活或厂商推送。只在应用可见时尝试启动，返回 START_NOT_STICKY；系统停止服务不会启动自救任务，也不会把 Service 销毁等同于用户退出 SDK。
- Application 注册原生消息消费者；Flutter Engine 只订阅 UI 事件。Engine 解绑后，网络监听和 Go Core 均保留。
- `GoCoreLifecycle` 是现有 JNI 的薄生命周期适配，不模拟协议。业务 Manager 的 126 个处理入口（125 个不同方法名）保留。
- 登录、退出和反初始化由宿主控制。重复相同初始化复用现有实例；改变服务端或数据库目录必须显式关闭。重复相同登录复用，跨账号及并发登录拒绝。

## 通知

`NativeMessageNotifications` 直接接收真实 SDK onRecvNewMessage；串行查询 SDK 自身资料和会话设置。离线同步事件不批量触发新提醒，assistantStream 分块不触发通知，消息完整性由 Core 和 Flutter 现有恢复逻辑负责。

`NativeNotificationPolicy` 处理账号、会话、全局免打扰、私密消息、当前会话、预览和官方账号快捷回复限制。`NativeMessagePreview` 解析现有消息元素、资金和通话摘要，不信任 offlinePush 文本或自定义 HTML。

通知 ID、渠道名、原有声音资源、会话替换、点击和快捷回复保持现有契约。通知使用系统标准标题/正文模板：第一行用户昵称或群名称，第二行消息内容，不再使用会额外显示发送人标题的 MessagingStyle，也不拼接群发送人前缀。快捷回复仍启动 Flutter 并使用原有发送流程，不增加另一个消息发送器。

通知设置及本地化标签写入应用私有 SharedPreferences `native_im_notifications_v1`，按账号保存；原生展示时读取。登录凭据和原始 token 不持久化到该存储。通知动作带原有 sessionKey 指纹，继续通过 Dart 的账号和会话校验。

Flutter 仅通过 `openim_native_im` 同步设置/页面状态和接收点击。启用时 Dart receive 不再触发 Android 通知或前台提示音；iOS 路径保留。AppController 显式退出会清理通知；纯 Engine 解绑不等同于退出。

资源限制：待通知会话最多 64、消息去重最多 512、通知版本最多 128、头像单工作线程/队列 16/LRU 16，压缩头像最多 4 MiB，有连接与读取超时和读取总时限。GameShield 单线程队列 32，网络唤醒合并。SDK 元数据查询只有一个在途任务；不新增第二套 WebSocket 重连或同步水位。

## 开关与构建

新通知默认关闭，验收构建使用：

```
flutter build apk --release --target-platform android-arm64 --dart-define=NATIVE_IM_NOTIFICATIONS=true
```

开关只控制通知所有权与 IMService 启动。SDK 进程宿主和 Android GameShield 生命周期解耦不受该开关控制。关闭开关不是整项改造回滚；整项回滚需要安装事先保存的旧版本。不要清除应用数据，也不要在两个 APK/进程间复制正在使用的数据库。

## 验证边界

自动测试覆盖生命周期复用、隔离旧 Engine、显式退出、账号拒绝、配置切换保护、隐私策略、稳定 ID 和 Dart 设置桥。生命周期单元测试使用仅在 test 目录内的假 Core，不能作为真实网络接收的证明。生产始终调用真实 AAR。

必须通过真实设备和另一发送账号验收，才能默认启用：

1. 同账号初始化两次、重建 Engine，日志仅一次 Core 初始化且没有第二个连接。
2. 关闭/销毁 Flutter Engine，确认主进程 PID 不变，再发真实消息：原生通知出现，点击重建界面并恢复消息。
3. 后台 30 分钟、锁屏 1 小时；记录发送/接收/通知时间与断线原因，缺失区间前台恢复后补齐。
4. 静音、关闭预览、私密消息、快捷回复、官方账号、红包/转账、群聊、头像、中文/英文和通知权限拒绝。
5. 切账号、踢下线、Token 失效、断网恢复、进程被回收，确认旧回调不通知新账号、消息不重复。
6. GameShield 开启后 Engine 销毁，确认真实代理仍工作；当前未发现可直接验收的兼容供应商 AAR，不能宣称此项通过。
7. 对比相同设备/网络/消息量的旧版与验收 Release 包的电量、流量、线程数、内存及接收延迟。Debug 包不能作为电量结论。

普通 Service 会被 Android 后台执行限制停止。进程存活不代表网络可用；主进程死亡时同进程 SDK 同时消失；强行停止后不能接收。此阶段没有自动启动并恢复凭据的后台登录，也不承诺深度休眠实时接收。

## 回滚

仅通知问题：重新构建不带 NATIVE_IM_NOTIFICATIONS=true 的包并重启应用。宿主/登录回归：用变更前的实现生成同签名、版本号不低于已安装版本的回滚包，沿用既有数据库，禁止卸载或清除数据。旧 APK 已备份，但 Android 可能拒绝直接降版本安装，不能把旧 APK 直接覆盖视为已验证的回滚方案。存在其他任务修改，不能用 git reset 整仓回滚；本次开始时的范围备份在工作区外 artifacts/native-im-runtime-20261013/baseline。

2026-10-13 验收包构建记录：Flutter Release 编译成功，但生成的插件注册文件错误包含开发依赖 flutter_native_splash，导致 Java 编译失败。移除该生成文件中的开发插件注册后，保留已成功生成且启用通知开关的 Release Dart 产物，以 Gradle 完成原生编译及签名打包。未修改启动页资源、依赖版本或 Flutter 工具源码。版本号 2029 已通过 APK 元数据及真机安装核验；此构建流程问题仍需独立复现排查。
