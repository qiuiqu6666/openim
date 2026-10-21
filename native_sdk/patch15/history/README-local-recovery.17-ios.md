# Core SDK recovery.17：最新窗口、按需历史与有限缓存

本次 Android 版本为 `v3.8.3-patch.15+recovery.17`，应用版本为 `3.0.1+2030`。

## 来源与运行行为

- Core 精确提交：`03592bcae0ad0cf45343b5ae8eabe13e7b69930f`，包含 `ccf08df` 的最新窗口/有限缓存方案，以及首次登录通知基线重复写入修复。
- 两端构建入口统一读取 `manifest.json` 指定的 `core-source/`。372 个输入文件由 `core-source-manifest.json` 锁定。除固定 gomobile 依赖的 `go.mod/go.sum` 和内嵌版本 `version/version` 外，源码与上述提交逐字节一致。
- 旧 `ios-core-source/` 保留 recovery.15 历史快照，当前构建不读取它；不得直接编辑旧快照来修复当前 SDK。
- 普通消息重连只恢复最新 100 个位置，实时消息不等待旧缺口。旧历史在上滑分页时取回，不再后台全量下载。连续检查点与离散交付区间分开持久化。
- 普通消息缓存预算：每会话 1,000 条，每账号 20,000 条及约 64 MiB；任一超限清理可替换正文。待发送/失败消息及必要删除、撤回、已读状态单独保留。预算不是 SQLite 文件物理大小或媒体目录上限；缓存维护失败时允许暂时超限并后续重试。
- 未读按服务端读水位校准。预取与实时推送重叠时计数一次；撤回先于原消息到达时持久化状态；淘汰后重拉保留已读/撤回状态。
- 首次同步在通知基线落库后拉取/写入失败，重试及进程重启不会再因通知序号重复插入卡在 10%；较旧响应不回退通知水位。通知事件仍按序恢复。

## Android 构建

两端锁定 Go 1.24.0、gomobile/gobind `v0.0.0-20250711185624-d5bb5ecc55c0`；Android 使用 NDK 28.2.13676358。脚本校验源码后复制到独立构建目录，禁用隐式依赖改写，生成绑定源码/二进制哈希的凭据。

```powershell
./native_sdk/patch15/build-android.ps1 -Go C:/tools/go/bin/go.exe -Python python -AndroidSdk C:/Android/Sdk -AndroidNdk C:/Android/Sdk/ndk/28.2.13676358
python native_sdk/patch15/prepare_source.py --check-artifact android
flutter build apk --release --target-platform android-arm64 --build-name 3.0.1 --build-number 2030
```

Android 插件从清单读取 `io.openim:core-sdk:3.8.3-patch15-recovery.17`，每次构建校验 AAR 版本及哈希。AAR 包含 armeabi-v7a、arm64-v8a、x86、x86_64；本次交付的安装包针对 arm64。生成二进制被 Git 忽略，新检出需运行构建脚本。

从测试/debug 切换 release 时，使用上面的完整构建命令，不加 `--no-pub`。Flutter 3.41.6 需要重新生成 release 插件注册表，排除 `integration_test` 等开发依赖；直接复用测试注册表会导致 Java 编译失败。

完整补丁 `0001-background-message-recovery.patch` 以 `patch_base_commit=d6e0b549db904d0327d76ef7c9c283203879a095` 为基线，`commit` 表示实际 Core 来源。可用 `apply.ps1` 在干净官方基线上重建快照；补丁重建结果已逐文件核对。Windows 源码固定 LF，避免换行改写破坏哈希校验。

## 测试与验收范围

- Core common/network/interaction/conversation_msg/db 五包竞态测试通过，包括真实 SQLite 事务、重启、缓存淘汰、未读/撤回覆盖与首次同步重试。
- Flutter 聊天恢复及历史测试 274 项通过、12 项原有跳过。
- Android SDK 桥接及原生运行时/通知策略测试 24 项通过。旧插件模板测试已替换为实际方法派发错误和 Flutter 引擎生命周期回调契约测试。
- 15 项源码/产物锁测试通过；干净官方基线补丁重建与当前快照一致。
- 最终构建与 APK/AAR 对应关系见 `verification/recovery.17-android.json`。安装包采用隔离应用副本构建，排除工作区其他未提交功能改动。
- 本次未覆盖真机长时间大群、温升/帧率和真实服务端故障注入；自动化通过不代表这些现场验收已经完成。

2026-10-14 macOS 补充：iOS recovery.17 Framework 已构建并安装到本地插件，包含真机 arm64 与模拟器 arm64/x86_64；构建前 Core/SQLite 测试与 15 项源码校验通过。Xcode Release 未签名应用 `3.0.1+2030` 编译通过，最终 Runner 二进制中已核对 recovery.17，且不包含 recovery.14。iOS 证据见 `verification/recovery.17-ios.json`；`native_binary_integrated=true` 表示两端原生产物均已构建。

直接在 Xcode 打开 `ios/Runner.xcworkspace` 编译即可使用最新本地 Framework。Pods 的 `Verify shared OpenIM Core` 在每次编译前校验源码与 Framework 凭据，拒绝旧版本或哈希漂移。当前验证未包含签名、安装或真机业务验收；不得把更早版本的设备记录当成本版验收。

前版清单见 `history/recovery.15.json`。回滚需保持源码、版本、锁和平台产物成组一致；旧全量补偿版本可能重新下载大量历史，不能将最高缓存 Seq 当作连续完整检查点。保留用户数据库与恢复状态，不清库。
