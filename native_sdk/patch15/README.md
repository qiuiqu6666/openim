# Core SDK recovery.19：历史扫描预算与续读

本版在 recovery.18 的会话摘要恢复基础上修复历史读取。扫描上限保持 3 层；预算耗尽返回已有有效消息与独立 `scanCursor`，`scanLimited=true`、`isEnd=false`，不恢复已删除消息，不改变服务端权限或已读序号。续读按会话和方向校验位置，删除锚点被清理后仍可从已扫描位置继续。网络与存储等真实错误继续失败，不能伪装成历史结束。

SQLite 清理中的原始 SQL 使用方言引用表名，覆盖真实 `sg_@lg_…` 群 ID。Flutter 接收并传递扫描游标，暂停后通过“继续加载历史消息”读取下一批；同步通知不自动重启暂停扫描。请求、扫描位置、重试次数与重置来源记录到原生日志，发布版也可收集。

共享移动源码为 `v3.8.3-patch.15+recovery.19`，基于清单中的 recovery.18 提交加本地历史修复，376 个文件由源码锁校验。Android 坐标为 `io.openim:core-sdk:3.8.3-patch15-recovery.19`；iOS 必须在 macOS 重新构建同源 Framework。旧 Framework 的校验会明确失败，不能混用旧 SDK。前版清单保存在 `history/recovery.18.json`。

构建命令沿用下方脚本，版本从清单读取。验证记录见 `verification/recovery.19-history-scan.json`；真机验收不包含在源码和构建测试中。

## recovery.18 的恢复行为与既有验证记录

Android SDK 版本为 `v3.8.3-patch.15+recovery.18`，Core 来源提交为 `88d76afecdd31c22ee07acf2f51d8f6d5b6e2815`。前版记录保存在 `history/recovery.17.json`。

## 恢复行为

1. 同步必要的好友、群组、会话资料和读水位。
2. 首轮每批最多处理 100 个会话，每个会话只拉最后一个消息序号；批次交错安排单聊和群聊。保存成功后立即通知会话列表刷新。
3. 所有会话完成首轮尝试后，再后台补各会话最近 100 个消息序号内的缺失消息。已经恢复的最后消息不会重复下载；较早历史继续按需翻页。
4. 最大序号为删除占位时，另取最后一条有效消息，包括位于最近窗口之前的有效摘要。可见范围和权限边界继续生效。
5. 单个会话请求、响应或保存失败，会保留恢复目标并与其他会话隔离；前台定时检查和重连可重试。最新摘要的保存不会将更早缺口标记完成。
6. 后台补历史保留当前最新摘要，避免覆盖首轮摘要或期间收到的新消息。首轮保存后通知失败，重复尝试仍会发布已保存的会话。

通知事件继续按序处理。缓存预算沿用每会话 1,000 条、每账号 20,000 条及约 64 MiB，已读、撤回和必要本地状态继续保留。

## 构建

Android 与 iOS 共用清单指定的 `core-source/`。375 个输入文件由 `core-source-manifest.json` 锁定；除固定的移动端依赖和内嵌版本外，源码与上述 Core 提交一致。

```powershell
./native_sdk/patch15/build-android.ps1 -Go <Go-1.24.0路径> -Python python -AndroidSdk <SDK路径> -AndroidNdk <NDK-28.2.13676358路径>
python native_sdk/patch15/prepare_source.py --check-artifact android
flutter build apk --release --target-platform android-arm64 --build-name 3.0.1 --build-number 2031
```

插件从清单读取 `io.openim:core-sdk:3.8.3-patch15-recovery.18` 并验证源码与产物哈希。旧 recovery.17 二进制不会被当作本版使用。iOS 需要在 macOS 运行 `build-ios.sh` 重新构建 Framework。

## 验证范围

Core common、network、interaction、conversation_msg、db 五包通过竞态测试，包含实际 SQLite、207 个会话先显示摘要、首轮失败隔离、删除末尾、断线重试及历史摘要保护。375 文件的移动端锁定源码也通过五包竞态测试；15 项源码与产物锁测试通过。原生及 JS/WASM 编译、相关包静态检查通过。

Android 构建证据见 `verification/recovery.18-android.json`。测试与构建结果限于本版记录，真机运行验收单独记录。
