# Core SDK 移动端同步

当前会话同步优先级、前后台消息去重及 iOS 一致性核对见 [priority-sync.md](priority-sync.md)。版本以 `manifest.json` 为准，以下为历次修改记录。

## recovery.23-notification-tombstone.1：删除通知占位

通知同步页的 `status >= MsgStatusHasDeleted` 且 `seq > 0` 行只作为删除占位推进检查点，不再按 `contentType=0` 分发。整页处理成功且检查点写入成功才确认同步；普通未知通知、有效通知处理失败及数据库写入失败仍返回错误，保留重试。修复模拟器中群通知 seq 2–52 的删除占位导致全局 syncFailed、每 30 秒唤醒并刷新正常聊天的循环。

Flutter 后台刷新保留忙碌和恢复状态，独立控制分页加载指示。Android 四 ABI AAR 与 arm64 APK 已构建并验证内嵌库一致；验证记录见 `verification/recovery.23-notification-tombstone.json`。iOS 使用同一共享源码，Framework 仍需 macOS 构建。

## recovery.22-local-snapshot.1：冷启动本地首屏

新增带 `localSnapshot=true` 的独立展示读取，经 Flutter 的 `getLocalHistorySnapshot` 接入。只查本地 SQLite 的有界最新记录，不访问网络、不补洞、不更新分页/已读，也不把本地空记录视为云端历史结束。过滤删除、私密、typing 和本地可见下限外的行。现有完整历史校验仍在后台执行，继续保障最新消息及连续分页。

Android 四 ABI AAR 与 arm64 调试 APK 已构建，实际验证记录见 `verification/recovery.22-local-snapshot.json`。iOS 桥接与共享源码已更新，Framework 仍需 macOS 构建；未进行手机冷启动端到端测速。前版清单保留在 `history/recovery.21.json`。

## recovery.21-sync-empty.1：空可见范围同步修复

本版在 recovery.20 上修复首次同步的空摘要重试：服务端 `seq_user.min_seq` 可以高于会话最新序号，例如个人下限 5、群最大序号 4。范围接口返回空页符合可见性约束；SDK 必须再用带方向的历史接口批量确认不可读前缀，才能保存检查点，不能仅凭空页或 `isEnd` 跳过缺失消息。每批最多 100 个会话，确认成功后后续同步不重复下载；网络错误、缺失边界及本地保存失败仍保留待办。

新增 `msg_sync_visible_empty.go` 和对应回归测试；`msg_sync_diagnostics.go` 每轮最多记录 12 个响应元数据样本，不包含消息正文。Android 诊断与验证证据见 `verification/recovery.21-sync-empty.json`。当前版本与产物坐标以 `manifest.json` 为准，以下保留 recovery.20 及此前版本的背景说明。

## recovery.20 背景

Android 与 iOS 使用同一份 `core-source/` 和源码锁，版本均为 `v3.8.3-patch.15+recovery.20`。Android 坐标为 `io.openim:core-sdk:3.8.3-patch15-recovery.20`。本轮 iOS 按用户要求只交付共享源码，不构建 Framework；现有旧 Framework 不代表本版，构建前仍必须运行 `build-ios.sh`，校验禁止混用。

普通重连和回前台先完成会话可见范围、设置及读水位同步，再按已有摘要优先策略恢复服务端最新消息和有限近期窗口。用户资料、黑名单、好友、群成员等完整资料同步移到消息保存与通知之后；失败仍发布同步失败并保留重试路径，不吞错，也不再阻断本轮最新消息。首次安装仍保留必要初始化顺序，消息未保存前不会提交恢复检查点。

Flutter 已加载聊天窗口收到无扫描游标的空刷新结果时，保留当前消息、上翻游标和最新锚点，即使 `isEnd=true` 也不把它解释为删除。明确清空、删除、账号更换和页面关闭继续使用原有世代及删除 ID 保护。

首次读取或返回最新窗口遇到空响应且已有可见消息时，不确认空窗口、不启用基于该响应的已读回执。冷启动主动进入现有有限重试流程，最多自动重试两次；成功后显示服务端最新历史，关闭页面后取消重试。

回归涵盖无下一条推送的普通断线与一亿序号长期离线、资料同步失败后重试、207 会话摘要优先、真实 SQLite/并发检测、前后台切换和空刷新。验证记录见 `verification/recovery.20-offline-latest.json`。本轮未进行两端真机端到端验收。

## recovery.19：历史扫描预算与续读

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
