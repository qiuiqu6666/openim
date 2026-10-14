# Core SDK recovery.15：最新消息优先，历史独立补齐

当前版本：`v3.8.3-patch.15+recovery.15`。Android 与 iOS 的唯一共同构建输入为 `ios-core-source/`，目录名保持兼容；361 个源码、测试及依赖文件受清单哈希校验。基线为官方 patch.15 的 `d6e0b549db904d0327d76ef7c9c283203879a095`。

## 修复行为

- 普通新推送跨越旧历史缺口时先通过已有消息/会话事务和持久交付记录落库通知，后续同一消息回放按身份去重。累计已读、撤回、初始化保护及远端 `833c19e` 的缺失终点已读回执兼容修复全部保留。
- `delivered` 仅记录最新消息已交付，`completed` 才表示连续覆盖；交付最新消息不取消 `[completed+1,target]` 的历史义务。旧数据库不凭 `MAX(seq)` 宣告完整。
- 超过 100 条的恢复区间先补最多 20 条最新可见消息，再按每页 100 条轮转补旧范围。尾部结果不能吞掉内部空洞；失败保留待补目标，启动、重连及前台周期继续调度。
- 恢复页面先按服务端已读/最大水位校准未读；后续旧消息、重复补拉不重复增加未读，也不回退最新摘要。通知序号继续按序处理，首次资料和权限初始化保护保留。
- 回调与交付记录确认之间崩溃时仍可能再次通知，应用按消息身份合并；本版本不宣称恰好一次回调。

## 构建与同源校验

两端锁定 Go 1.24.0、gomobile/gobind `v0.0.0-20250711185624-d5bb5ecc55c0`，保留 `go.mod/go.sum`。脚本禁用外部 Go workspace 和隐式依赖改写，先校验并复制同一快照，再执行测试和构建。生成的 `verification.json` 绑定来源与二进制哈希；Android 每次 preBuild、iOS Pods 安装及编译前都会拒绝旧产物。

二进制被 Git 忽略。完整补丁 `0001-background-message-recovery.patch` 可在官方干净基线上重建相同 361 文件。源码换行固定 LF，许可证保留。`native_binary_integrated=false` 表示 recovery.15 的 iOS 产物尚待生成；前一版 recovery.14 的 Mac 构建记录保存在历史清单，不能当作 recovery.15 的构建验收。

Windows Android（需要 Python 3、JDK、SDK、NDK）：

```powershell
./native_sdk/patch15/build-android.ps1 -Go C:/tools/go/bin/go.exe -Python python -AndroidSdk C:/Android/Sdk -AndroidNdk C:/Android/Sdk/ndk/28.2.13676358
python native_sdk/patch15/prepare_source.py --check-artifact android
flutter build apk --debug --target-platform android-arm64
```

Mac iOS（需要完整 Xcode、Go 1.24.0 和 Python 3）：

```sh
native_sdk/patch15/build-ios.sh
python3 native_sdk/patch15/prepare_source.py --check-artifact ios
./tool/flutterw build ios --release --no-codesign
```

Go 不在 PATH 时设置 `GO=/absolute/path/to/go`。Framework 包含真机 arm64 和模拟器 arm64/x86_64，安装时同时保存 `recovery-verification.json`，最低 iOS 13。`fetch-ios.ps1` 仅取未修复官方对照包，不能用于此版本。Gradle/Pods 可通过 `CORE_PYTHON` 指定 Python。

## 2026-10-14 验证

- 合并远端累计已读兼容后，Core common/network/interaction/conversation_msg 四包 race 和 CGO=0 测试通过，相关 vet 通过。新增回归覆盖同会话 15 万条积压时新推送先交付、最新尾部先于旧页提交、SQLite 重启及旧页回放的未读与摘要幂等。
- 15 项来源/产物校验测试通过；361 文件与干净官方基线上应用补丁的结果逐字节一致。四 ABI AAR、arm64 APK 构建通过，APK 原生库与 AAR 标准剥离结果一致。
- 最终 recovery.15 包已保留数据安装到小米 2506BPN68G（应用 3.0.1+2029），验证实时显示，以及发送十条后停止发送、接收端恢复自行补齐。十条 SQLite 记录各一条；未读恰好增加十条，重新启动不再增加；聊天页显示最新消息。机器可读结果见 [verification/recovery.15-xiaomi.json](verification/recovery.15-xiaomi.json)。
- 本次手机离线场景为应用停止/重新启动，未冒充真实移动网络切换验收。iOS recovery.15 Framework/iPhone 真机、长时间离线、大群与服务端故障注入仍待验收。扩展数据库全包存在两项已记录的基线失败，本轮保留说明，未计为通过。

回滚必须回退整组版本、锁清单及平台产物，保留用户消息数据库、恢复记录和已读状态，不清库。上一版记录见 [history/recovery.14.json](history/recovery.14.json) 与 [history/README-before-recovery.15.md](history/README-before-recovery.15.md)。
