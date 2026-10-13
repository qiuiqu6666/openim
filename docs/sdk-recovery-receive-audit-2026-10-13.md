# SDK 离线恢复弱网补拉与消息接收审计

当前链路能在重连后核对消息序号并补拉，历史查询也会修补缺口；但存在消息回调被后继聊天页覆盖、迟到的旧消息追加到最新位置、弱网探测过早断连，以及原生补拉错误未传递为失败状态等风险。应先修复客户端接收归属与弱网恢复策略，再处理受控原生 SDK 的错误传递、队列和缺口生成。

审计日期为 2026 年 10 月 13 日。本文基于当前工作区源码、锁定版本的公开原生源码和已有 iOS Release 日志。没有修改运行代码，没有构建、analyzer、运行测试或新增真机采集；下面的场景推演不是实测复现，修复后耗时、掉帧和耗电对比均待验证。

本文保留修复前的审计快照。随后已按用户授权实施修复，当前状态、源码行为对比与原生接入限制见 [修复记录](sdk-recovery-fixes-2026-10-13.md)；下面的旧行为不代表当前客户端源码。

## 版本和证据范围

- 当前项目为 `E:/openim/openim-flutter-demo`。Flutter 依赖锁定 `flutter_openim_sdk 3.8.3+hotfix.12`；Android 插件依赖 `io.openim:core-sdk:3.8.3-patch12@aar`；iOS Pod 锁定 `OpenIMSDKCore 3.8.3-hotfix.12`。
- 对照原生源码为 [OpenIM SDK Core v3.8.3-patch.12](https://github.com/openimsdk/openim-sdk-core/tree/v3.8.3-patch.12)，标签解析到 commit `101cf038eb114bc58bd9298dedeff33e3b1a73f2`。保存的 [源码清单](E:/openim/artifacts/sdk-recovery-audit-20261013/source-manifest.json) 包含下载文件哈希。声明版本和日志自报版本不能证明手机二进制与此 commit 完全一致，因此原生问题按该版本源码风险报告。
- 用户提供的 [sdk-log-2295249541.zip](E:/下载/sdk-log-2295249541.zip) 内含 `open-im-sdk-core_temp.2026-10-11`，10,000 行、11,554,174 字节。读取时只输出事件、耗时和计数；[恢复事件摘要](E:/openim/artifacts/sdk-recovery-audit-20261013/ios-existing-log-summary.json) 和 [等待耗时摘要](E:/openim/artifacts/sdk-recovery-audit-20261013/ios-existing-cost-summary.json) 不包含消息正文、用户标识或令牌。
- 日志日期为 10 月 11 日，应用构建 commit 未知，不能声称它运行了当前工作区的恢复修改。GitNexus 当前没有索引本 OpenIM 仓库，本次结论直接沿当前源码核对，没有借用其他仓库索引。

## 实际恢复链路

1. 原生 WebSocket 重连成功后，`MsgSyncer.doConnected` 查询服务端最大 SEQ，与本地同步位置比较。这个版本 `connectPullNums = 1`，普通会话先获取最新少量记录；唤醒补拉用 `defaultPullNums = 10`。通知消息有不同的拉取预算，不能把 1 或 10 当作全部消息的统一上限。
2. 用户打开聊天、翻页或刷新时，`getAdvancedHistoryMessageList → fetchMessagesWithGapCheck` 检查页内、页间和末端缺口，再按缺失 SEQ 请求历史。因此“同步完成”与“全部离线历史都已下载到本地”含义不同。[同步实现](https://raw.githubusercontent.com/openimsdk/openim-sdk-core/v3.8.3-patch.12/internal/interaction/msg_sync.go)、[历史缺口检查](https://raw.githubusercontent.com/openimsdk/openim-sdk-core/v3.8.3-patch.12/internal/conversation_msg/message_check.go)
3. 客户端 `IMConnectionRecovery` 在前台/网络恢复时唤醒，在需要复查时等待 15 秒，其他前台状态每分钟检查。它先调用 `setAppBackgroundStatus(false)`；失败或 4 秒超时才调用会关闭 socket 的 `networkStatusChanged`。前者成功表示前台状态请求返回并尝试派发唤醒命令，不能证明后续补拉已经成功。
4. 原生入库后经 Flutter 插件解析回调。`IMCallback` 向共享消息流、业务观察者和聊天页分发；会话行变化先合并 80 毫秒，缺失会话回调的局部补查延迟 120 毫秒。聊天页在 `syncEnded` 或 App 恢复前台时刷新历史。

## 需优先处理的问题

P1 表示可能影响接收正确性或使补拉长时间停滞，应优先处理；P2 表示恢复延迟、重复任务或特定场景的额外负担。源码能证明下述执行路径，具体命中频率和真机表现仍待验证。

### R01 叠加聊天页返回后原消息回调没有恢复

**P1，客户端。** [ChatLogic 注册接收回调](E:/openim/openim-flutter-demo/lib/pages/chat/chat_logic.dart:897) 将实时、离线消息和 C2C 回执写入 `IMController` 的三个单例回调槽。[关闭页面](E:/openim/openim-flutter-demo/lib/pages/chat/chat_logic.dart:1201) 只在归属相同时清空，没有恢复前一个仍存在的页面。注册位置只在初始化执行。

[AppNavigator](E:/openim/openim-flutter-demo/lib/routes/app_navigator.dart:107) 支持 `offUntilHome: false` 和重复聊天路由。联系人共同群、聊天历史导航等存在该入口。推演：聊天 A 打开聊天 B，B 覆盖回调，关闭 B 后槽变成 null，A 仍在栈内；此后 A 的新消息和已读回执无法经这三个槽更新，SDK 数据库和会话列表仍可能正常更新。

**方案：** 复用当前共享消息流，为每个聊天路由持有并释放自己的过滤订阅，实时/离线来源需保留；回执也使用拥有订阅归属的共享流。也可建立有路由归属的回调恢复机制，但不能在旧页面关闭时无条件抢占后继页面。验证 A→B→A、同会话叠加、离线回调和回执。

### R02 迟到的补拉旧消息被追加到最新位置

**P1，客户端。** [实时和离线共用回调](E:/openim/openim-flutter-demo/lib/pages/chat/chat_logic.dart:898) 最终调用 [appendIncoming](E:/openim/openim-flutter-demo/lib/pages/chat/history/chat_timeline_controller.dart:199)。后者直接构造 `[..., message]`，没有检查新记录是否比当前末尾更旧。去重只排除窗口/缓冲内已经存在的 ID。

触发条件是最新历史已经安装，但窗口外较旧的离线或补拉回调随后到达。例如窗口为 SEQ 101–140，迟到 SEQ 100 会变成末尾的“最新”记录。SDK 在一批内排序也不能保证所有异步批次与历史查询之间的全局顺序。此时最新滚动目标、时间标记和读取“最后一条”的已读逻辑会受影响。

**方案：** 正常递增消息保留快速追加；较旧消息按与历史合并一致的排序规则插入，历史模式继续进入原缓冲；或在补拉突发结束时合并一次。保留 SDK 消息对象、ID 去重和滚动锚点。验证先安装最新页、再到达窗口外旧消息、相同时间的不同 SEQ 和重复回调。

### R03 四秒超时可能把仍可用的弱网连接断开

**P1，客户端策略。** [wakeIMConnection](E:/openim/openim-flutter-demo/lib/core/session/connection/im_native_connection_wake.dart:9) 的前台请求默认 4 秒超时，随后直接调用 `networkStatusChanged`。对照原生 [NetworkStatusChanged](E:/openim/artifacts/sdk-recovery-audit-20261013/source/open_im_sdk__init_login.go:130) 会关闭当前连接。原生 [响应等待](E:/openim/artifacts/sdk-recovery-audit-20261013/source/internal__interaction__long_conn_mgr.go:526) 本身允许 10 秒，前面还可能有排队等待。

因此一次 5–9 秒才返回的请求，或被其他 SDK 请求排队的前台通知，会在原生等待截止前被客户端主动断连。超时后的原生操作并没有取消，重连及下一次唤醒又会增加排队。旧账号/后台的资格检查已经存在，这个风险发生在同一有效前台会话内。

**方案：** 把“确认断开”“原生错误返回”和“请求暂时超时”分开；超时先做非破坏性复查和退避，不能只因 4 秒没有回调就关闭 socket。等待预算需要包含 SDK 排队，真正断开仍交给原生重连与明确失败兜底。验证 5 秒/9 秒延迟、队列繁忙、真实断网及后台切换。

### R04 分批补拉失败仍可能报告同步完成

**P1，原生 SDK 风险。** [compareSeqsAndBatchSync](E:/openim/artifacts/sdk-recovery-audit-20261013/source/internal__interaction__msg_sync.go:222) 丢弃 `syncAndTriggerMsgs` / `syncAndTriggerReinstallMsgs` 返回的错误。[doConnected](E:/openim/artifacts/sdk-recovery-audit-20261013/source/internal__interaction__msg_sync.go:371) 只在“查询最大 SEQ”失败时报告失败；后续批次失败仍可能发送 `MsgSyncEnd` 或 `AppDataSyncFinish`。首次安装的 `Installed` 标记也由 defer 写入，不能反映所有批次成功。

触发条件：最大 SEQ 查询成功，后续某一补拉批次超时/失败。App 会接收 `syncEnded`，结束同步提示并启用相关准备状态，但某些会话的最新记录可能还未修复。下一轮补拉可重试未推进的会话，这不等于已证实永久丢消息。

**方案：** 在受控 SDK 源码中返回批次结果，失败应保留待恢复状态并产生失败或部分完成信号；只有规定的初始化任务成功后才提交首次安装完成标记。客户端应分别看连接状态、补拉状态和当前会话历史加载状态。[上游同步源码](https://raw.githubusercontent.com/openimsdk/openim-sdk-core/v3.8.3-patch.12/internal/interaction/msg_sync.go)

### R05 消息派发或入库失败时同步位置仍可能前移

**P1，原生 SDK 风险。** [syncAndTriggerMsgs](E:/openim/artifacts/sdk-recovery-audit-20261013/source/internal__interaction__msg_sync.go:457) 忽略向会话队列派发的错误，随后更新 `syncedMaxSeqs`；连续实时消息也在派发前更新内存位置。[队列发送](E:/openim/artifacts/sdk-recovery-audit-20261013/source/pkg__common__trigger_channel.go:33) 等待超时可返回错误。后续 [doMsgNew](E:/openim/artifacts/sdk-recovery-audit-20261013/source/internal__conversation_msg__conversation_msg.go:443) 对部分消息/会话数据库错误仅记录，继续执行后续步骤，没有把持久化失败回传同步器。

队列拥塞、数据库写失败或解析异常时，内存同步位置与可用本地记录可能分离。同一进程下一次按最大 SEQ 对比可能跳过已前移的区间；历史缺口查询和重新加载本地序号是其他修复途径。正常只拉最新 1/10 条后推进位置是此 SDK 的按需历史策略，不能把它本身判定为数据丢失。

**方案：** 至少不忽略派发失败，持久化失败保留会话的重试/修复资格；必要时使用会话处理确认，再提交该批进度。按上游按需历史语义区分已接收的最新边界与历史覆盖范围，不从 Flutter 人为改写 SDK SEQ。

### R06 历史缺口先全量生成再截取五十个序号

**P1，原生 SDK 性能风险。** [getLostSeqListWithLimitLength](E:/openim/artifacts/sdk-recovery-audit-20261013/source/internal__conversation_msg__message_check.go:175) 遍历 `minSeq..maxSeq`，把所有缺失序号加入 slice，完成后才截取 `PullMsgNumForReadDiffusion`，当前常量为 **50**。

长时间离线、高活跃群或本地覆盖稀疏时，实际请求只有 50 个序号，CPU/内存分配却按完整缺口增长。100 万个缺失 `int64` 的元素存储就需 8,000,000 字节，不含扩容和其他对象；返回子 slice 仍引用原底层数组，网络等待期间不会因截取而立即释放它。这是容量计算，不是真机内存测量。

**方案：** 根据前向/反向拉取语义，从所需端开始遍历，收集到 50 个缺失序号就停止；保留已有消息、边界与方向语义。验证大跨度、稀疏覆盖、两种方向、删除消息及服务端最小可拉 SEQ。[上游缺口实现](https://raw.githubusercontent.com/openimsdk/openim-sdk-core/v3.8.3-patch.12/internal/conversation_msg/message_check.go)

### R07 一个原生写请求可阻塞后续补拉和前台通知

**P1，原生 SDK 队列风险。** [发送队列](E:/openim/artifacts/sdk-recovery-audit-20261013/source/internal__interaction__long_conn_mgr.go:148) 容量为 10；`writePump` 同步执行 [dispatchMessage](E:/openim/artifacts/sdk-recovery-audit-20261013/source/internal__interaction__long_conn_mgr.go:396)，等待该请求完成后才处理下一条。[writeBinaryMsgAndRetry](E:/openim/artifacts/sdk-recovery-audit-20261013/source/internal__interaction__long_conn_mgr.go:533) 对部分请求最多重试 300 次，每次失败睡眠 1 秒；写入耗时还另计。`GetNewestSeq` 在未连接时有快速失败分支，其他请求不能据此认为也会快速失败。

持续断网或写失败时，一个请求可累计约 5 分钟的重试睡眠，后面的补拉、前台状态和其他长连接请求被排队。`SendReqWaitResp` 的 `c.send <- msg` 在检查 context 之前执行；队列满时也会阻塞。Flutter 的 4/8/30 秒超时只结束自己的等待，不能解除原生队列占用。这能解释“连接恢复迟迟不动”的路径，但已有日志未命中该长时间阻塞，不能认定它就是已反馈完全卡死的原因。

**方案：** 原生入队、重试和等待统一响应 context/deadline；断网时及时失败幂等查询，让恢复调度退避后重试。保留消息发送顺序，不能为减轻阻塞盲目并行所有请求。[上游长连接实现](https://raw.githubusercontent.com/openimsdk/openim-sdk-core/v3.8.3-patch.12/internal/interaction/long_conn_mgr.go)

## 其他影响恢复的路径

### R08 健康状态每分钟探测包含整账号元数据同步

**P2，客户端与原生。** [IMConnectionRecovery](E:/openim/openim-flutter-demo/lib/core/session/connection/im_connection_recovery.dart:75) 在健康前台状态也调用唤醒。原生 [doWakeupDataSync](E:/openim/artifacts/sdk-recovery-audit-20261013/source/internal__interaction__msg_sync.go:394) 除补拉消息，还派发 `syncData`。后者同步核对会话已读/最大 SEQ，并异步核对群成员、好友、黑名单、会话和用户资料。

[syncData](E:/openim/artifacts/sdk-recovery-audit-20261013/source/internal__conversation_msg__notification.go:411) 在同步会话已读 SEQ 的网络/数据库阶段持有 `conversationSyncMutex`，[doMsgNew](E:/openim/artifacts/sdk-recovery-audit-20261013/source/internal__conversation_msg__conversation_msg.go:412) 的入库和回调阶段也要获取同一个锁。现有日志有 8 次超过 20 毫秒的等待，范围 47.70–64.37 毫秒；日志不能把每一次等待都归因于当前一分钟定时器。

**方案：** 将健康连接活性确认与整账号数据修复分离；必要补拉按网络状态、失败记录和实际缺口安排。受控 SDK 缩小共享锁覆盖范围，网络请求不要长时间持有阻挡消息入库的锁。不能停掉群消息接收或以丢弃离线消息换取速度。

### R09 超时和缓存过期没有限制真实原生在途任务

**P2，客户端。** [ChatHistoryPrefetcher](E:/openim/openim-flutter-demo/lib/pages/chat/history/chat_history_prefetcher.dart:48) 的 12 个上限和 2 秒过期限制的是缓存条目。过期/淘汰没有取消原生查询，也没有继续占用真实在途额度；旧请求没结束时再次准备同一会话可以发起新查询。

[ConversationLatestSync](E:/openim/openim-flutter-demo/lib/pages/conversation/updates/conversation_latest_sync.dart:207) 五秒等待超时后释放 `_running`，失败重试或新消息会继续启动下一次读取，旧原生 Future 仍可在途。它已有最多两次失败重试，风险在持续新信号或反复导航时仍可叠加，而非无条件无限重试。

**方案：** 为这两类读取保留真实未完成 Future 和并发额度，同键请求复用，超时进入界面错误态但不释放原生名额。当前 [ChatHistoryReadGate](E:/openim/openim-flutter-demo/lib/pages/chat/history/chat_history_read_gate.dart:39) 已实现这一原则，可按模块边界复用设计。验证迟到响应、连续进出页面、超时后再次请求和切换账号。

### R10 会话恢复快照缺少等待截止和请求合并

**P2，客户端。** [加载快照](E:/openim/openim-flutter-demo/lib/pages/conversation/conversation_logic.dart:578) 每次调用都增加代次并启动新读取，旧查询只被禁止写回，没有等待合并或真实并发限制。[逐页读取](E:/openim/openim-flutter-demo/lib/pages/conversation/conversation_logic.dart:892) 无超时；等待已开始的旧会话清理操作也无截止。

触发条件是 SDK 本地调用迟迟不返回，或前台恢复、未读校准与同步结束同时请求快照。`_readingList` 可长时间保留，未读校准等待快照结束，失败自动重试入口又要求 `!_readingList`，页面可能一直保留旧行/加载状态。

此外，offset 分页针对可变排序列表，没有稳定快照或分页进展校验。第一页读取后删除/取消置顶前面的会话，会让未发生回调的后继会话移到已跨过的 offset；合并变化记录不能补回所有未变化的遗漏行。例如 `[A,B,C,D]` 先读 A/B，再删除 A，offset 2 从 `[B,C,D]` 读 D，C 无变化回调就遗漏。这里遗漏的是展示快照，不是 SDK 消息数据库。

**方案：** 合并同一登录的恢复读取，等待有界且保留真实在途所有权；分页确认游标/ID 进展，排序变化或删除发生时做有限的重新校准，避免无限重扫。验证大账号、无返回、并发恢复、读中删除和取消置顶。

### R11 弱网历史失败后同一连接恢复未必再刷新页面

**P2，客户端。** [聊天状态监听](E:/openim/openim-flutter-demo/lib/pages/chat/chat_logic.dart:1326) 只在 `syncEnded` 刷新历史，另一个入口是 App `onResumed`。历史错误/超时会结束加载并保留重试错误态。原生 `doWakeupDataSync` 不产生与 `doConnected` 同样的开始/结束回调；返回前台状态请求也不是补拉完成事件。

如果 Wi-Fi/蜂窝类型没变、socket 没重连，只是历史请求短暂失败，后续客户端唤醒即使修复了 SDK 数据，聊天页也不一定自动重试失败窗口。它有手动重试，因此不能描述为不可恢复；用户可能要再次点重试或重新进页面。

**方案：** 对失败的当前历史窗口提供有界、合并的恢复重试，覆盖明确的连接恢复和补拉修复信号。只重试失败任务，保留历史窗口、阅读位置及账号归属；不要每次健康探测都全量刷新聊天。

### R12 连接失败事件不会立即切换客户端复查节奏

**P2，客户端兜底。** [恢复信号过滤](E:/openim/openim-flutter-demo/lib/core/controller/im_controller.dart:404) 仅包含连接成功、同步结束和同步失败。`connecting` / `connectionFailed` 改变 `isDisconnected` 的结果，但不会重新安排已经等待的一分钟定时器。

网络类型没有变化且缺少生命周期事件时，客户端这一层可能等到旧的分钟检查才开始按 15 秒重试。原生本身仍运行重连循环，不能因此推断所有消息必然延迟一分钟。

**方案：** 将真实断开转移纳入有去重的恢复调度，尽早进入失败节奏；保留原生重连所有权、并发唤醒保护和后台停止规则。

## 现有保护与不应误判的现象

- 历史读取默认 30 秒等待；当前路由最多两个真实未结束读取，超时不会自动释放名额。非零 `AdvancedMessage.errCode` 被拒绝，失败页面不提交游标或半页结果。
- 历史刷新与当前页读取合并，最新范围断开时保持阅读窗口；实时消息去重，安全首屏缓存最多 12 个会话各 40 条，自动消息窗口约 600 条加待发送记录，历史模式最近缓冲 100 条。它们是展示缓存，SDK 仍拥有持久化历史。
- 登录代次、账号和令牌检查阻止旧结果覆盖新账号；恢复观察者、网络订阅和计时任务有关闭处理，后台暂停客户端定时唤醒。
- 会话增量更新已有合并、权威回调冲突保护与有限失败重试；这些保护不能替代上述真实在途限制或稳定分页。
- 离线回调入口没有重播旧通知。上游回调分类还受 SDK 前后台状态与消息接收选项影响，没有逐条离线回调不等于没有入库；应核对消息 ID、SEQ 与历史查询结果。
- 17 次 AttachedInfo 警告在既有日志核查中均为空字符串，原生继续构造消息。它不能作为漏消息证据，也不应通过清空数据库来处理。

## 已有日志结果与验证边界

| 指标 | 既有 iOS Release 样本结果 | 可支持的结论 |
| --- | --- | --- |
| WebSocket 读取异常 | 2 次 | 21:06:21.207、21:07:14.232 的原生断开事件 |
| 断开到原生重连事件 | 94、99 毫秒 | 这两次没有显示长时间重连阻塞；不代表 UI 完成或全部历史已齐 |
| 同步开始和结束 | 各 4 次，区间 196、204、254、247 毫秒 | 原生同步阶段有结束事件；不能据此证明所有元数据异步任务和历史补拉完成 |
| 前后台状态方法调用 | 10 次；成功耗时 34.02–122.29 毫秒 | 样本中未命中 R03 的超过四秒场景；也未验证当前客户端策略 |
| 消息处理等待共享锁 | 8 次，47.70–64.37 毫秒 | 确认接收处理与其他共享锁任务存在等待；不是 Flutter UI 帧时长 |
| 最大 SEQ 查询错误、分批补拉错误、历史补拉发送失败 | 对应关键字均 0 次 | 仅表示此日志未观察到这些错误，不证明其他时段或设备没有发生 |
| 通道发送超时和同步器 panic | 对应关键字均 0 次 | R05、R07 的极端条件未由此样本复现 |

SDK 序号核对、消息解析和数据库处理在原生 Go 路径执行；Flutter 回调 JSON 解析、观察者分发和列表更新在主 Isolate。主 Isolate 掉帧、温升或完全卡死需要相应 Timeline、CPU、Memory 或线程采样，当前日志不能量化这些结果。

本轮没有实施性能优化，因此没有修改后实测数据。后续对比必须固定账号、设备、包模式和离线消息量：检查实际消息 ID/SEQ 是否齐全、重复回调次数、从恢复到当前会话可交互的耗时、真实在途 SDK 请求峰值、入库/共享锁等待，以及 UI/raster 慢帧、CPU 和内存峰值。

优先验证 A→B→A 接收、旧消息晚到、5–9 秒弱网响应、分批补拉失败、百万序号跨度、原生请求持续不返回、同网络类型恢复和会话分页中删除。客户端先处理 R01–R03；原生 SDK 的 R04–R07 应在可维护源码及可追踪二进制中修复，不能直接改共享 pub-cache 或声称修改 Dart 就修复了原生行为。
