# iOS 群列表恢复修复重建

本包版本：`v3.8.3-patch.15+recovery.53-group-pagination.1`。

已将群目录分页恢复同步至 Android/iOS 共用的 `core-source`。保留 recovery.52 的登录取消修复。分页中断后继续未完成页；全部分页、权威群 ID 和版本一致后才发布群目录；版本提交失败时保留快照；调度保护有时间上限，退出登录仍立即取消。

## Mac 上重建

需要 Xcode（含 Command Line Tools）、Go **1.24.0**、Python 3、CocoaPods，以及项目要求的 Flutter **3.41.6**。先完成 Xcode 首次启动和许可证确认。依赖下载需要联网。

在完整代码包的 `openim-flutter-demo` 目录执行，下面两个路径换成 Mac 上实际的 SDK 路径：

```bash
export GO="/path/to/go1.24.0/bin/go"
export OPENIM_FLUTTER_SDK="/path/to/flutter-3.41.6"

python3 native_sdk/patch15/prepare_source.py
bash native_sdk/patch15/build-ios.sh
python3 native_sdk/patch15/prepare_source.py --check-artifact ios

bash tool/flutterw pub get
(cd ios && pod install)
bash tool/flutterw build ios --release --no-codesign
```

`build-ios.sh` 会验证源码锁、运行核心测试、构建真机和模拟器 Framework，并安装到 `local_plugin/flutter_openim_sdk/ios/Frameworks/OpenIMCore.xcframework`。它同时写入产物校验记录；CocoaPods/Xcode 会校验该记录，防止误用旧 Framework。

未签名 App 位于 `build/ios/iphoneos/Runner.app`。需要安装或发布时，用 Xcode 打开 `ios/Runner.xcworkspace`，选择原有 Team/签名配置后构建或归档。签名证书和本机配置沿用自己的 Mac 环境。

## 验收

- 使用此前群聊未显示的账号登录，等待群目录同步完成，确认群会话及群列表恢复。
- 同步中持续接收消息、切换前后台，检查日志中的 `joined group snapshot page retained`；取消后的下一轮应继续剩余分页。
- 确认同步期间不会因不完整群列表误清理已有群，群资料、头像和成员资格最终更新。
- 同步中退出登录再切换账号，确认上一账号的临时分页不进入新账号。
- 核对启动日志版本为 `recovery.53-group-pagination.1`。

Windows 已完成的回归和源码校验见 `verification/recovery.53-group-pagination.1.json`。本包没有冒充已完成的 iOS Framework、签名 App 或真机验证。`ios-core-source` 是保留的旧历史快照；本次构建仅使用 manifest 选定的 `core-source`。
