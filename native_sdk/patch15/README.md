# Core SDK 移动端同步

## recovery.38-foreground-probe.2：前台主动确认假在线连接

每次收到前台恢复通知，Core 通过独立的 WebSocket Ping/Pong 检查当前连接，3 秒未收到匹配响应则关闭被探测的旧 socket、释放旧请求并唤醒重连。即使本地仍记录为前台，也会进行检查；正在进行的探测合并，切后台、退出会话或替换连接后旧探测失效。普通消息不会因此自动重发。

在 emulator-5554 的 x86_64 原生包上，只丢弃旧 Core socket 的双向数据，允许新连接建立。旧 recovery.37 三次耗时 [29.899, 29.908, 28.596] 秒，最终版 [3.121, 3.109, 3.115] 秒；中位数从 29.899 秒降至 3.115 秒。指标从回前台命令到 Core 连接恢复，不代表消息全部补齐。健康连接探测耗时 [54, 53, 53, 54, 53, 53] 毫秒，三轮均未重连。

重复前台通知、半开连接、迟到 Pong、退出、切后台及连接替换通过竞态回归；53 项 Flutter 测试、15 项源码锁测试和累计补丁还原通过。Android 四 ABI AAR、arm64/x86_64 APK 已构建并核对。ARM 转译层崩溃样本不纳入最终对照；未连接实体手机，iOS 仍须在 macOS 重建。详见 [验证记录](verification/recovery.38-foreground-probe.json)。

## recovery.37-foreground-wait.1：回前台时释放旧连接请求

旧连接关闭后，已经写出的请求仍可能等待完整的 10 秒响应超时，阻塞串行发送队列中的前台状态确认和消息补偿请求。本版将响应等待绑定到实际写入时的连接生命周期：连接明确关闭即返回网络错误并释放队列，快速重连不会掩盖旧连接关闭，也不会取消新连接请求。已进入响应队列的服务端确认继续保留；未确认消息不会因此自动重发。

两项旧实现失败场景已复现，四项回归覆盖断连释放、替换连接隔离、已确认消息和串行队列恢复。移动端同源代码通过 30 次 race 重复测试；37 项 Flutter 恢复测试通过。版本与构建、验收范围见 [验证记录](verification/recovery.37-foreground-wait.json)。

此修复不缩短健康连接的普通请求超时，不实现新的假在线探测或推送机制。真机端到端恢复时延尚未测量；iOS Framework 仍须在 macOS 重建。

## recovery.36-group-extremes.1：首次同步交叉场景回归

本轮复现并修复 7 处边界问题：普通群通知产生超过队列容量的更新而自阻塞；已排队的实时消息被后台重试挡住；群通知失败仍推进进度；通知执行期间未继承回执超时；重复同步结束重置群身份查询；连接事件覆盖同步阶段而提前读取未完成缓存；离群重新加入后沿用旧高权限身份。

通知处理期间持续收取队列，但持久化和后续更新保持串行；失败通知保留原进度供重试。页面保留同步阶段并合并重复完成事件，离群时使旧高权限信息失效。

两份源码的 5 个 Go 包通过 CGO/race，针对性并发回归重复 30 次通过。90 项 Flutter 状态/权限测试（新增 12 项）、2 项亮暗页面测试、范围静态分析、15 项源码锁测试及累计补丁还原均通过。详情与限制见 [验证记录](verification/recovery.36-group-extremes.json)。

当前为源码修复，AAR/APK 和 iOS Framework/App 尚未重建，未完成真机弱网与长时间运行验收。原有窄屏箭头数量断言失败保留记录。

## recovery.35-group-sync.1：首次同步群资料加载与会话队列循环等待

群资料查询持有群同步锁并发布更新通知时，后台元数据任务可能等待同一把锁。原会话消费者取消后台任务后直接等待退出，停止消费队列；1000 容量队列填满后，持锁查询与消费者形成循环等待。取消任务现在继续接收并暂存通知，任务退出后再串行处理，不并发执行消息写入、不丢弃已入队更新。

群资料页未确认身份时，等待同步超过 20 秒显示现有失败/重试组件；进度事件不延长期限，重试重新计时。同步恢复会重新查询，已确认资料继续展示；关闭、切换会话和真实退群保护保留。

旧监听器在容量 2 与 1000 两个复现用例均失败；修复后四个 Go 包和移动端锁定源码通过 CGO/race 回归，队列用例重复 30 次通过。34 项 Flutter 状态/控制器回归、2 项亮暗页面测试、范围 analyze、15 项源码锁测试及累计补丁还原通过。既有窄屏测试要求 5 个箭头、实际 4 个，在 HEAD 测试上也失败，未改动该断言。

Android AAR/APK 与 iOS Framework/App 尚未重建，手机上的旧 SDK 不包含本修复；未进行真机首次同步验收。详情见 [验证记录](verification/recovery.35-group-sync.json)。

## recovery.34-local-call.1：历史通话气泡与 Android 构建

消息窗口加入已持久化的本地通话记录（seq=0），不把本地记录计入服务器序号覆盖。旧数据库重新打开后自动读取，无需重发或清理数据；删除和私密消息保护继续生效。

Android 四 ABI SDK 已重建，凭据及哈希校验通过，arm64 调试 APK 编译通过，内置 SDK 经符号裁剪后与 AAR 一致。锁定源码通过 SQLite 升级读取回归、15 项源码锁测试与累计补丁还原核对。已在 emulator-5554（SM N9810）安装启动；历史通话界面未手动验收。iOS Framework 仍须在 macOS 重建。验证记录：`verification/recovery.34-local-call.json`。

## recovery.33-cold-receipt.1：后台恢复缺表与聊天窗口停留

日志中同一群的已读通知因本地消息表尚未建立而 107 次阻塞通知页提交。`GetMessagesBySeqs` 现在复用既有消息表初始化，与按消息 ID 查询一致：空缓存返回空结果，真实建表和查询失败仍向上传递。真实 SQLite 回归覆盖冷缓存、重复查询、后续入库、关闭数据库，并通过通知页入口确认检查点推进。旧实现已复现日志中的相同错误。

Flutter 的已加载聊天页恢复时，仅在用户正在阅读历史消息时保留旧窗口；位于最新消息处时安装新的有界最新窗口，并继续处理实时消息。首次已绘制的缓存窗口仍沿用原有保护。33 项 Dart 回归及修改范围 analyze 通过；开启 CGO 的 db、conversation_msg、interaction 测试通过。源码锁和累计补丁校验通过，详情见 `verification/recovery.33-cold-receipt.json`。

Android、iOS 使用相同更新后的源码锁；本次未重建 AAR、Framework 或 App，尚未进行长时间后台真机验证。


## recovery.32-read-receipt.1：空预览已读通知不再阻塞同步

修复对方已读通知在 `latestMsg=""` 时解析 JSON 失败、反复重试同一页的问题。空预览仍会更新本地消息已读状态、发送回执事件并推进通知序号；不会生成虚假预览。非空损坏 JSON、消息查询和写入错误继续阻止确认，以便重试。保留已有的零行已读更新幂等修复。

回归覆盖空预览、缓存缺失、重复通知、正常预览、损坏 JSON、查询及写入失败，并通过真实通知页入口检查序号 56→57。旧代码已复现相同失败，修复后相关五个 Go 包通过。Android/iOS 共用更新后的源码锁；尚未重建 AAR、Framework 或进行真机验证，旧二进制不代表本修复。SQLite 数据库回归仍需启用 CGO 的 C 编译环境。

当前会话同步优先级、前后台消息去重及 iOS 一致性核对见 [priority-sync.md](priority-sync.md)。版本以 `manifest.json` 为准，以下为历次修改记录。

## recovery.31-friend-profile.1：好友头像、昵称同步与旧快照修复

好友通知处理错误现在返回通知页处理器，失败时不推进通知检查点，恢复后可重试原通知。用户资料更新通知在好友增量同步后，重新核对指定好友的服务器资料，不再仅依赖好友列表版本变化。所有资料更新仍通过既有好友同步器入库、失效用户缓存并发布通知；不使用群昵称作为全局昵称，不复活已删除好友。

既有辅助同步任务在登录、重连等恢复时分批核对已有好友（每批最多 100 位，完整成功后一分钟内不重复核对）。因此旧版本已经错误确认的通知、空增量返回也能恢复，失败保留原资料并在下次辅助同步重试；不增加轮询、不阻塞消息先就绪。好友全量替换同时清理公共用户缓存，防止表数据更新后继续读到旧头像昵称。

Flutter 资料页补齐好友事件中的头像字段，拒绝较早查询覆盖新的头像、昵称和备注。Android、iOS 构建均从 `manifest.json` 指定的同一 `core-source` 读取，并运行好友同步回归。旧 iOS Framework 与本源码锁不匹配时必须重建，不能以旧 Framework 代表本修复。测试与设备验证见 `verification/recovery.31-friend-profile.json`。

## 2026-10-15 Core 与 iOS 远端源码同步核对

核对独立 Core 开发仓库 `9d0b64f` 与共享构建源码，补入遗漏的 `TestInvisiblePrefixLifecycleDoesNotSkipNewMessages` 回归测试，覆盖清空后收新消息、退群重入旧边界、断线及持久化检查点恢复。该测试三个子场景通过；15 项源码锁测试通过。业务实现未改变，共享源码保留较新的 recovery.30 上传修复、固定依赖及版本覆盖；运行时 `identifier.sqlite` 数据库不作为源码同步。

Android 与 iOS 构建脚本继续读取 `manifest.json` 指定的 `core-source`（433 个锁定文件）；`ios-core-source` 为历史目录，不是当前构建输入。补丁和源码哈希已随新增测试更新。已有二进制回执不匹配新源码锁，需分别重建 Android AAR 和 iOS Framework；本次仅同步源码，未重建二进制或执行真机验收。

## recovery.30-image-upload.1：图片上传卡住与重试锁

共享文件上传增加 9 分钟总期限，覆盖哈希检查、元数据 API、签名 PUT 和响应体读取。Dart 的 `Future.timeout` 只停止等待，不取消 Go 请求；旧实现的无时限 HTTP 请求可持续持有同内容上传锁。本版主动取消原生请求，锁等待也响应取消，失败后再次上传同一文件可以正常进入。已提交聊天消息的未知回执仍不自动重发。

新增 `internal/third/file/upload_lock.go` 和本地 HTTP 故障回归，覆盖响应头/响应体卡住、超时后同图重传、取消等待不破坏当前持锁者、60 个并发任务互斥。两端构建脚本均运行这些隔离测试，不运行仓库中依赖历史外部服务的 `TestUpload` 示例。保留 recovery.29 的全部同步修改；前版清单在 `history/recovery.29-friend-sync.1.json`。

Flutter 同步修复相册 HEIF/缺失格式元数据、长图预览等待、节点切换后悬挂状态，并增加 Info 级 `chat_media` 阶段日志。验证记录见 [verification/recovery.30-image-upload.json](verification/recovery.30-image-upload.json)。iOS 使用同一锁定的 `core-source`，Framework 和手机实测仍需 macOS。

## recovery.29-friend-sync.1：登录后通讯录自动刷新

消息就绪继续先于辅助资料同步。好友全量同步批量入库后，对比同步前后的本地好友快照，通过现有好友新增、资料更新和删除通知发布实际变化，避免通讯录在较早的消息同步完成事件中读到空表后一直不刷新。相同快照不重复通知；同步失败或取消不发布成功快照。Flutter 继续使用原有好友事件订阅、批量索引及账号关闭保护，无需轮询或重复全量查询。

相关 SDK 回归、12 项通讯录测试与 15 项源码锁测试通过。Android 3.0.1+2042 已安装到模拟器，备份账号数据库后仅清空好友缓存及对应同步版本，重新启动并使用已保存账号登录，确认完整补拉并显示 21 位联系人。界面和日志证据见 [verification/recovery.29-friend-sync.json](verification/recovery.29-friend-sync.json)。iOS 沿用同一锁定的 `core-source`，尚未构建 Framework 或进行设备验证。

## recovery.28-fast-recovery.1：冷启动、重连与回前台恢复

主动让出或取消的同步任务保留持久化恢复目标，不再反馈成网络同步失败。Flutter 执行失败定时器前重新检查当前状态，已自行恢复的任务不再触发新一轮完整同步；真实网络错误仍进入重试。

会话可见范围沿用同一认证历史协议，按每批最多 100 个会话合并方向边界查询，缺失或无效边界只阻止对应会话。近期小缺口每次最多合并 8 个会话，总响应预算仍为 100 条；通知独立按序处理。消息持久化回执成功后才更新恢复覆盖，单会话失败保留待办；继续复用前台历史协调通道并重新验证 SQLite 已存记录，避免重复下载和重复交付。

必要会话设置、可见范围和读水位仍先确认。消息可用后，再由同一个串行调度器更新好友、群成员等辅助资料；辅助资料失败保留重试，不再把已保存消息标成同步失败。同一恢复轮次不重复同步全局已读。冷启动一次读取恢复检查点；已有持久化检查点的会话跳过逐表 `MAX(seq)`，旧数据库继续按保守兼容路径建立恢复目标，稀疏覆盖不会被当成连续完整历史。

Android AAR 四种架构及 3.0.1+2041 调试 APK 已构建。两端均从 `core-source` 构建，428 个输入文件逐文件一致；按用户要求，本轮 iOS 只交付同源代码，不构建或测试 Framework。macOS 后续须先运行 `build-ios.sh`，旧 Framework 的构建回执会被拒绝。

回归覆盖批量恢复无丢失/重复、边界缺失隔离、取消与真实错误、资料失败重试、读水位、真实 SQLite 和六包竞态检测。Flutter 扩展回归有两个会话预览用例失败，替换成本次修改前的恢复代码后仍同样失败，未计为通过。完整范围、产物哈希及日志见 [verification/recovery.28-fast-recovery.json](verification/recovery.28-fast-recovery.json)。Android 未执行本版真实账号端到端验收。

## recovery.27-sync-heat.2：重复同步与日志开销

撤回引用查询排除已删除记录，处理器也跳过保留类型、正文为空的删除占位。显式已读回执允许本地缓存缺失和重复执行，继续核对全部序号；真正的 SQL 错误仍阻止确认通知页。空摘要使用带方向的服务端历史边界证明不可见前缀、后缀，只确认已证明的范围，保留更早的历史缺口与原有自动恢复窗口。

没有恢复进展时按 1、2、4、8、16、30 秒退避并合并重试，实时消息和退出仍立即处理；退避期间排队超过 32 条的消息也继续交付。正常稀疏缓存已覆盖最新窗口时不再触发空同步，真实新缺口仍触发恢复。INFO 请求、返回、命令及会话日志不再输出整页消息正文；诊断 Log 调用不再产生额外的请求与成功 INFO 日志。

回归包含两份发热日志中的删除引用、重复回执、四组序号边界、无下一条消息的重试、实时消息抢占及 70 条排队消息。真实 SQLite、六个包的 race 检查和源码锁验证结果见 [verification/recovery.27-sync-heat.json](verification/recovery.27-sync-heat.json)。Android 与 iOS 共用当前锁定源码；iOS 仍需 macOS 重建 Framework，真机温度和耗电效果尚未测量。

## recovery.26-chat-window.2：会话级首屏窗口

在原历史接口中增加版本化窗口证明，固定服务端水位、原子读取 SQLite 已提交消息与可见边界，并按 seq 排序。当前会话可发布不再依赖全局同步；较旧撤回/删除通过既有持久化通知与重读窗口保护。首屏准备有界，实时展示采用有界批量队列，页面请求按账号/会话/代次隔离。无需新增数据库完整标志，崩溃前后不会留下错误覆盖证明。

Flutter 保留灰色骨架过渡和阅读锚点，导航复用准备请求，即使其他会话持续收消息也不重复拉取。服务端缺失消息不再被伪造为删除占位；该补丁已按授权上线。详细契约见 [WINDOW_CONTRACT.md](../../lib/pages/chat/history/WINDOW_CONTRACT.md)，结果见 [verification/recovery.26-chat-window.json](verification/recovery.26-chat-window.json)。最终 Android 验证包为 3.0.1+2035，包含本节与 recovery.27 修复；iOS 仍需 macOS 构建和设备验证。

## recovery.25-group-profile-scale.4：大账号群资料同步

单群资料更新只读取、比较该群，避免每个群重复加载完整群目录。仅群名称、头像等资料变化时，不再读取未变化的群成员目录；全量成员同步、实际成员增删改、排序版本及群资料版本确认继续保留。SQLite 在库内筛出资料不一致的可见群会话，每批最多 128 条，事务提交后发送完整 SDK 回调；不加载无关会话的消息摘要。后续排队的同资料通知不重复写入、发布；真实后续变更（含头像清空）继续更新。事务失败整批回滚，重试继续补齐，名称、头像清空、未读、草稿和置顶均有回归覆盖。

压力测试使用真实 SQLite，覆盖 1000/5000 群与 4000/20000 会话，每条消息摘要约 2 KiB，核对全部变更结果。`internal/group/profile_stress_test.go` 测逐群更新，`profile_network_stress_test.go` 测真实批量 HTTP（人工固定 10ms 等待），`internal/conversation_msg/group_profile_stress_test.go` 测会话核对。CGO 开启后可用 `go test ./internal/group ./internal/conversation_msg -run '^$' -bench 'Benchmark(Group|Conversation)Profile' -benchtime=1x -count=1` 重跑；性能测量不启用 race，正确性另用 race 回归。

界面压力用 [integration_test/performance/group_profile_stress_test.dart](../../integration_test/performance/group_profile_stress_test.dart) 的真实会话行、群功能资料投影及聊天页标题控制器，在独立 Android 测试应用运行 profile 模式；只使用合成数据和本机头像服务。`STRESS_PAGE_MODE=bulk/paged` 可分进程对比大回调与 128 条回调。测试源抑制应用登录初始化，不访问业务服务器；不要用生产包名覆盖已安装客户端。模拟器结果不代表手机真机帧率。最终测量及平台验证见 [verification/recovery.25-group-profile-scale.json](verification/recovery.25-group-profile-scale.json)。

## recovery.24-group-profile.1：离线群名称与头像恢复

群成员全量补拉也处理附带的群资料，资料保存成功后才确认版本。并发单群同步失败回传到同步重试流程；空批次及部分空响应正确推进，不重复提交已请求的批次。已加入群的全量恢复先完整取回服务器分页，再按差异更新本地数据，保留群资料事件、头像缓存及会话资料更新。

元数据同步完成后核对现有可见群会话的名称和头像，只写这两列，对已有旧会话自动修复，保留未读、草稿、消息、置顶等状态。初始化和普通重连都执行核对；失败继续返回错误，未变化的数据不重复写入。聊天页同步结束补读当前群资料，保留成员及历史加载状态，合并重复请求并拒绝晚到的旧资料和其他账号的结果。

回归覆盖全量群资料通知、单群失败重试、头像清空、旧会话自愈、重复同步、聊天页历史等待期间资料刷新，以及账号切换。Android 四 ABI Core 已构建；应用打包及最终验证以 [verification/recovery.24-group-profile.json](verification/recovery.24-group-profile.json) 为准。iOS 共用同一份锁定源码，本轮仍需 macOS 重建 Framework，旧版 Framework 不代表本版。未执行双账号真实离线修改验收。

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

Android 与 iOS 共用清单指定的 `core-source/`。输入文件和补丁由 `core-source-manifest.json` 锁定；当前文件数及版本以清单和本版验证记录为准。

```powershell
./native_sdk/patch15/build-android.ps1 -Go <Go-1.24.0路径> -Python python -AndroidSdk <SDK路径> -AndroidNdk <NDK-28.2.13676358路径>
python native_sdk/patch15/prepare_source.py --check-artifact android
flutter build apk --release --target-platform android-arm64 --build-name 3.0.1 --build-number 2031
```

插件从清单读取当前 Android 坐标并验证源码与产物哈希。旧版本二进制不会被当作本版使用。iOS 需要在 macOS 运行 `build-ios.sh` 重新构建 Framework。

## 验证范围

Core common、network、interaction、conversation_msg、db 五包通过竞态测试，包含实际 SQLite、207 个会话先显示摘要、首轮失败隔离、删除末尾、断线重试及历史摘要保护。375 文件的移动端锁定源码也通过五包竞态测试；15 项源码与产物锁测试通过。原生及 JS/WASM 编译、相关包静态检查通过。

Android 构建证据见 `verification/recovery.18-android.json`。测试与构建结果限于本版记录，真机运行验收单独记录。

## macOS iOS recovery.23-notification-tombstone.1 verification (2026-10-14)

The current locked Core source was rebuilt for iOS device arm64 and simulator arm64/x86_64, installed in the local plugin, and verified against its artifact receipt. Core/SQLite build-script tests and 15 source-lock tests passed. Xcode Release no-codesign application 3.0.1+2027 compiled successfully; the Runner binary contains v3.8.3-patch.15+recovery.23-notification-tombstone.1 and does not contain recovery.17. Evidence: `verification/recovery.23-notification-tombstone-ios.json`.

Open `ios/Runner.xcworkspace` for subsequent Xcode builds. The existing pre-compile artifact guard verifies this Framework and its locked source. Original local Xcode/project registration edits were preserved. Signing, installation, and device runtime were not verified in this build.
# 聊天首屏窗口校验（2026-10-15）

`localSnapshot=true` 的本地读取增加 `snapshotReady`。只有最近序号范围完整（删除占位也计入已保存序号）时才允许 Flutter 用该结果绘制首屏；完整的一页旧记录或仅保存最新摘要都不能证明中间无缺口。同一 `sendTime` 的消息按 `seq` 排序，未分配序号的发送中消息保持在该时间的已确认消息之后，使用稳定排序保持相等项的原始顺序。

Flutter 同时检查实时消息与快照之间的连续性，在全局同步进行中等待完整查询；新消息使导航预读失效。服务端当前历史接口的序号、可见范围、删除占位和终止标记回归已通过，本次无需部署服务端代码。验证入口为 `test/integration/chat/chat_entry_performance_test.dart`、`test/pages/chat/history/`、Core `history_snapshot_test.go` 和 `history_snapshot_sqlite_test.go`。Android 验证包与产物校验见 `verification/chat-entry-window-20261015.json`；iOS Framework 与设备性能仍需 macOS/Xcode 验证。

## macOS iOS recovery.30-image-upload.1 verification (2026-10-15)

The current 433-file locked Core source, including the added visible-empty lifecycle test, was rebuilt for iOS device arm64 and simulator arm64/x86_64 and installed in the local plugin with an artifact receipt. Core/SQLite build-script tests, upload deadline/hash tests and 15 source-lock tests passed. Xcode Release no-codesign application 3.0.1+2028 compiled successfully; its Runner binary contains v3.8.3-patch.15+recovery.30-image-upload.1 and does not contain recovery.17 or recovery.23-notification-tombstone.1. Evidence: `verification/recovery.30-image-upload-ios.json`.

Open `ios/Runner.xcworkspace` for subsequent Xcode builds. The pre-compile artifact guard verifies the current Framework against the locked source. Original local edits were preserved. Signing, installation, and device runtime were not verified in this build.

## CocoaPods CDN download repair (2026-10-15)

A CDN HTTP/2 framing failure left the GoogleUtilities 8.1.5 spec cache empty. The official spec was downloaded over HTTP/1.1, validated for package/version, and cached with its server ETag. The application remains locked to GoogleUtilities 8.1.0; Podfile.lock and dependency versions were unchanged. Both deployment installation and repository refresh passed with reduced CDN concurrency:

```sh
COCOAPODS_CDN_MAX_CONCURRENCY=4 pod install --repo-update --deployment --project-directory=ios
```

Run the command from the project root. The cache repair is local to this Mac; the cached spec and native binaries are not stored in Git. Direct Xcode Release no-codesign compilation passed after the repair. Evidence: `verification/cocoapods-download-repair-ios.json`. This verifies dependency installation and compilation, not signing or device runtime.
