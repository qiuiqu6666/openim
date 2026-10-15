# 会话同步优先级与前后台去重

同步复用 Core 的近期消息同步、SQLite 和存储回执，没有新增 Flutter 登录全量预取队列或第二份消息数据库。当前共享源码为 `recovery.28-fast-recovery.1`；实际版本以 `manifest.json` 和产物验证记录为准。

## 调度

- 登录初始化的必要元数据完成后，从本地会话表一次读取置顶和最近消息时间。
- 正在进行首屏历史请求的会话优先，然后置顶，再按最近消息时间降序；同优先级保留稳定顺序。
- 会话摘要仍先于普通后台近期历史，保留有界批量摘要请求。每个摘要批次重新检查前台请求优先级。
- 点击聊天的已有预取会进入 `ensureLatestHistory`，立即注册前台请求，直接竞争该会话的共享通道，不需要等待所有会话同步完毕。前台请求完成或取消后释放优先状态。
- 近期历史继续限制在最近 100 个消息序号范围；小缺口最多合并 8 个会话，每次请求的消息总预算仍为 100 条。每批重新核对前台优先级，更旧历史仍按需读取。通知消息独立按序处理，可见范围继续使用认证方向边界。
- 必要会话设置和读水位先确认，消息持久化与发布后再更新辅助资料；辅助资料由同一串行调度器维护重试，不阻塞消息就绪。主动让出不再触发应用层网络恢复，真实失败继续重试。

## 避免重复下载

`internal/interaction/history_priority.go` 随登录连接实例持有协调状态。前台最新历史与后台摘要/近期历史，在同一会话的网络读取和保存期间互斥；其他会话不共用全局锁。

后台已完成时，前台重查 SQLite，只下载缺失序号。前台先完成时，登记已持久化的序号；后台重新验证 SQLite，并走现有存储回执流程复用这些行，维护摘要、未读和检查点，再拉剩余缺口。失败、空响应、未落库消息不会被登记为已完成。覆盖记录最多 128 个会话，每会话 100 个序号，只用于避免重复工作，不能替代数据库或把稀疏窗口误判为完整历史。

## 平台一致性

Android 和 iOS 的原生历史入口均调用同一个 Core 接口；无新增平台专属桥接。两个构建脚本通过 `prepare_source.py` 使用 `manifest.json` 指定的同一份 `core-source`。`ios-core-source` 旧目录不是当前构建输入。

Android AAR 已通过源码指纹校验。当前 iOS Framework 没有本版构建回执，`--check-artifact ios` 明确拒绝；必须在 macOS/Xcode 执行 `build-ios.sh`，再验证 Pod、iOS 构建和设备行为。不能以源码相同声称现有 iOS 二进制已更新。

## 回归

- `history_priority_test.go`：实际后台请求顺序、前台持锁期间后台等待、40 条已存历史只补剩余 60 条、清除缓存后重新下载、存储回执失败后重试、取消释放、账号实例隔离与容量上限。
- `history_priority_sqlite_test.go`：新设备没有消息表时的读取、真实 SQLite 成功消息和删除占位复用、缺口保留。
- `go test -race ./pkg/common ./pkg/network ./internal/interaction ./internal/conversation_msg -count=1 -timeout=120s`：通过（含 SQLite，CGO 开启）。
- 数据库消息批次与初始化通知专项测试、15 项源码锁测试：通过。
- Flutter 聊天历史、滚动、集成和提示组件回归：481 项通过，12 项现有跳过。

验证数据见 `verification/priority-sync.json`。尚未测量真实新设备登录耗时，也未完成本版 iOS 构建/真机验证。

recovery.28 的批量恢复、冷启动、SQLite、竞态与 Android 构建结果见 [verification/recovery.28-fast-recovery.json](verification/recovery.28-fast-recovery.json)。本轮按用户要求只验证 iOS 与 Android 的源码一致性，iOS 构建和运行由用户后续完成。
