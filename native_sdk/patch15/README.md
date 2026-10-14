# Core SDK recovery.13：Android / iOS 共享源码

当前版本：`v3.8.3-patch.15+recovery.13`。在远端 `767a024` 的完整 Core 源码上补入恢复修复，保留累计已读、显式已读重放及撤回修复。

`ios-core-source/` 现在是 **Android 与 iOS 唯一共同构建输入**，目录名为兼容原路径而保留。两端脚本先校验 `ios-core-source-manifest.json` 中全部 357 个构建输入，再复制到独立目录；不重复应用补丁、不读取其他 SDK 工作目录，也不复制测试数据库或日志。`0001-background-message-recovery.patch` 保留从官方基线重建同一源码的能力。

## 本轮修复

| 问题 | 处理方式 |
| --- | --- |
| 最大 Seq 已追上，但中间消息没有落库 | 在现有用户版本存储中分别记录目标 Seq 和连续完成检查点；每页最多 100 条，保存未完成义务，重启后继续。旧数据库的 `MAX(seq)` 不作为完整证明，首次升级重新核对可见范围。 |
| 初始化资料同步失败后一直等待新推送 | 周期恢复重试初始化，必要资料成功前保留首次登录保护；失败不误标完成。 |
| 首屏本地为空，历史查询误判结束 | 已知远端水位时主动补取尾部；未知时查询最新消息。请求失败、离线及未确认的空响应不伪装成历史结束。 |
| 消息已落库，重试后仍没有通知或摘要 | 原生 SQLite 将消息与会话状态放入同一事务；写入前保存待交付记录，回调成功后清除。重开数据库后恢复消息及总未读通知，重复补拉保持幂等。 |
| 旧可见上限屏蔽新消息，空响应吞掉缺口 | 冲突的缓存上限通过服务端已有历史协议重新确认；只有明确方向边界可以缩小范围，不能凭空结果推进检查点。 |
| 持续实时推送使其他会话永远补不完 | 单一调度器限制连续实时批次，补拉按页让出且保留进度机会，会话轮转，首次资料同步和退出取消保护保留。 |

检查点及交付记录复用现有存储，不改服务端协议、Seq 权威来源或用户已读水位。跨平台共用以上 Core 实现。回调之后、交付确认之前若进程退出，允许再次通知；应用仍须按消息身份合并，不能宣称恰好一次交付。升级旧数据库可能重新读取较多历史，每页有界且轮转执行；无法证实的空洞会保留恢复义务。

## 版本与构建校验

- 上游：`openimsdk/openim-sdk-core`，官方提交 `d6e0b549db904d0327d76ef7c9c283203879a095`。
- Go：`1.24.0`；gomobile / gobind：`v0.0.0-20250711185624-d5bb5ecc55c0`。
- `go.mod` / `go.sum` 延用已入库的锁定文件；构建关闭外部 Go workspace、禁止隐式依赖改写，并在结束时再次检查锁文件。
- 当前源码、补丁、平台版本必须与 `manifest.json` 一致；`.gitattributes` 固定源码 LF，避免 Windows 与 Mac 的换行转换改变哈希。
- 每次构建记录 `verification.json`，关联源码哈希、版本、工具链及二进制哈希。Android `preBuild` 和 iOS Pods 安装及编译前均验证来源，旧包、缺少凭据或包被替换时停止构建。
- 二进制与构建目录不入 Git。`native_binary_integrated=false` 表示本轮两端产物尚未全部完成集成；当前 Android 已构建，iOS recovery.13 待 Mac 构建。

校验源码及校验器测试：

```sh
python3 native_sdk/patch15/prepare_source.py
python3 -m unittest discover -s native_sdk/patch15/tests -v
```

Windows 将 `python3` 换成 `python`。Gradle / CocoaPods 可通过 `CORE_PYTHON` 指定可执行文件路径。

## Android 构建

需要 Go 1.24.0、Python 3、JDK、Android SDK 和 NDK。本次使用 NDK `28.2.13676358`。

```powershell
./native_sdk/patch15/build-android.ps1 -Go C:/tools/go/bin/go.exe -Python python -AndroidSdk C:/Android/Sdk -AndroidNdk C:/Android/Sdk/ndk/28.2.13676358
python native_sdk/patch15/prepare_source.py --check-artifact android
flutter build apk --debug --target-platform android-arm64 --no-pub
```

脚本先运行四个 Core 包回归，再生成四 ABI AAR，写入本地 Maven `io.openim:core-sdk:3.8.3-patch15-recovery.13`。新检出项目先完成 Flutter 依赖准备；应用构建示例的 `--no-pub` 仅适用于依赖已就绪时。

## iOS 构建与用户验收

需要 macOS、完整 Xcode（命令行工具选中该 Xcode）、Go 1.24.0 与 Python 3。在仓库根目录执行：

```sh
native_sdk/patch15/build-ios.sh
python3 native_sdk/patch15/prepare_source.py --check-artifact ios
./tool/flutterw build ios --release --no-codesign
```

Go 不在 PATH 时设置 `GO=/absolute/path/to/go`。脚本运行四包回归、原生 SQLite 恢复测试及事务测试，生成真机 arm64 与模拟器 arm64/x86_64，最低 iOS 13。通过校验后安装到 `local_plugin/flutter_openim_sdk/ios/Frameworks/OpenIMCore.xcframework`，同时保存 `recovery-verification.json`；旧 Framework 留在本次独立构建目录。**不能只复制 Framework 而遗漏验证记录。** `fetch-ios.ps1` 仅获取未修复官方包作对照，不能用于本版本。

先执行上述 Flutter 构建以更新 Pods，之后直接从 Xcode 构建也会执行编译前校验。iOS recovery.13 尚未在本次 Windows 环境构建或真机验证，由用户在 Mac 验收。

验收至少覆盖：A 离线，B 发 10 / 100 / 1000 条后停止发送，A 恢复后无需新消息或手动查历史即可补齐；初始化失败后自动重试；空首屏恢复；落库后退出再启动；持续其他会话推送时静默会话仍补齐。检查消息完整性、顺序、未读及重复通知，Android / iOS 使用相同场景。

## 本轮已执行验证（2026-10-14）

- Core common / network / interaction / conversation_msg 四包 `-race`：114 项顶层测试通过；另事务回滚测试通过，相关 `go vet` 通过。两端构建共用的 CGO=0 四包测试通过。
- 公平调度 5 项故障场景重复 20 次通过。SQLite 关闭重开覆盖同账号其他设备消息、对方消息及总未读通知恢复；这是持久化重启模拟，不是真机强杀验收。
- 完整补丁在干净官方基线上应用，357 个构建输入逐字节与共享源码一致；32 个移植文件及全部 311 个 Go 文件与已审核修复快照一致。
- Android 四 ABI AAR 和 arm64 debug APK 构建通过，APK 内原生库与 AAR 经标准符号剥离后的内容一致；本轮未安装设备。
- Flutter 空首屏恢复及合并后配置/网络就绪相关 10 项定向测试通过。平台源码/版本/产物漂移防护由 Python 回归覆盖。
- 扩展运行 `pkg/db` 全包时，`TestGetLatestValidateServerMessage` 与 `Test_GetVersionSync` 失败；在未修复基线同样失败，单独列为既有失败，未计入通过。
- iOS Framework / 应用、双平台真机、真实网络切换、千人/万人群和服务端故障注入未完成。不能把 Core 测试或 Android 编译成功视为这些验收已通过，也未证明原始故障手机只有一个根因。

本地证据：`E:/openim/artifacts/sdk-parity-fix-20261014/`；版本与执行状态见 `manifest.json`。旧版记录保留在 [history/README-before-recovery.13.md](history/README-before-recovery.13.md) 与 [history/recovery.12-readseq2.json](history/recovery.12-readseq2.json)，其中旧尾部策略及集成状态不适用于 recovery.13。

回滚时回退整组源码、版本清单和对应平台产物，保留用户消息数据库及恢复记录，不清库、不回退已读状态。上游许可证保留于 `ios-core-source/LICENSE`。
