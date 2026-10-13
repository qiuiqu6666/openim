# iOS Release 日志核查与局部优化

2026 年 10 月 12 日。实际日志确认了两项优先处理的开销：相同的零角标反复上传、正式包保留大量原生 SDK DEBUG/INFO 日志。本轮已修改对应源码，并修复首页未读初始查询覆盖新回调的竞态。已读、群同步及异常按下文证据分别处理，不把它们一概当作发热根因。

仍遵守用户限制：只读取源码和已有日志，没有构建、测试、analyzer、安装、启动应用或新增性能采集。本轮修改未进入用户手机上的包；帧率、CPU、内存、耗电、温升及完全卡死的改善均**待验证**。此前全局发现和其他已做改动见 [全局审计](E:/openim/openim-flutter-demo/docs/performance-global-static-audit-2026-10-11.md)。

## 样本与计数口径

- 用户确认平台/模式：iOS Release；设备型号、iOS 版本、应用版本和构建 commit 未提供，不能确认此前工作区优化已包含在该安装包中。
- 原文件：[sdk-log-2295249541.zip](E:/下载/sdk-log-2295249541.zip)，SHA-256 `C18C5BE5FAD70D170BD7F1BAA2B8DD3A22AB6CD3CAD722655A69CFD44E9D5388`。
- 内含 `open-im-sdk-core_temp.2026-10-11`，解压大小 **11,554,174 字节**，共 **10,000 行**。只在内存读取，不修改压缩包，不复制消息正文、令牌或用户标识到报告。
- 日志首末时间为 `2026-10-11 18:38:18.334` 至 `21:07:59.856`，中间有长间隔；时间采用日志原值。不能把全部文件称为“连续四分钟”。其中 18:38–18:41 四个分钟桶合计 7,407 行、约 7.79 MB，峰值 18:40 为 **2,770 行/分钟**。
- SDK 自报 `[flutter/IOS] [v3.8.3-patch.12]`；本地 Flutter 依赖 `3.8.3+hotfix.12`，iOS Pod 为 `3.8.3-hotfix.12`。上游同版本源码用来解释行为，不能证明所装二进制与上游 tag 完全相同。
- 方法请求按 `func call req` 计数，成功响应另算；HTTP 请求按 `ApiRequest` 计数。先去掉日志等级的 ANSI 颜色码，避免漏算 WARN/ERROR。

| 指标 | 此日志实际结果 | 解释 |
| --- | ---: | --- |
| DEBUG / INFO / WARN / ERROR | 6,836 / 3,114 / 46 / 4 | DEBUG+INFO 占 99.5% 行数 |
| SetAppBadge | 305 次请求 + 305 次成功响应 | 不是 610 次请求；305 次参数均为 0 |
| `/third/set_app_badge` | 305 次 HTTP 请求 | 占全部 419 次 SDK HTTP 请求的 72.79% |
| 角标请求相邻间隔 ≤100ms | 91 次 | 最短间隔 0ms；说明存在短时间重复派发 |
| MarkConversationMessageAsRead | 89 次请求 | 88 次针对一个会话，另一个会话 1 次；不能把同会话的每次新消息确认都算重复 |
| `unread count is 0` | 23 次 WARN | 实际 `/msg/mark_conversation_as_read` 为 66 次 |
| 群成员增量同步 / 已加入群增量同步 | 各 6 次 HTTP 请求 | 需与登录、前后台及重连一起判断 |
| AttachedInfo 解析 | 17 次 WARN | 17 次均为空字符串，均为 unexpected end of JSON input |
| WebSocket 异常断开 | 2 次 read 错误，另有对应 close 日志 | 按事件算 2 次，避免重复计数 |
| 撤回找不到本地消息 | 2 次底层警告，另有 2 次上层处理失败 | 同样不重复计数 |

## 问题、证据和处理

### L01 相同角标反复上传

**P1，实际日志和源码均确认，已修改。** 触发条件：群消息、已读回声或其他会话变化反复产生相同的总未读回调，尤其总未读一直为 0 时。

入口：[IMCallback.totalUnreadMsgCountChanged](E:/openim/openim-flutter-demo/lib/core/im_callback.dart:284) 每次调用 [AppController.showBadge](E:/openim/openim-flutter-demo/lib/core/controller/app_controller.dart:381)。旧实现不比较数值，直接调用 SDK，同时反复查询系统是否支持角标。日志确认每次 SDK 调用均产生 `/third/set_app_badge` 网络请求，不能只把它看成一次本地图标更新。

当前新增 [AppBadgeCoordinator](E:/openim/openim-flutter-demo/lib/core/notifications/app_badge_coordinator.dart:5)，复用原 SDK 和 AppBadgePlus：

- 同一登录会话、相同数值只在写入成功后去重，首次 0 仍写入；在途只保留最新待写数值。
- 服务端和系统各自串行，系统角标不等待网络；平台支持能力查询成功后缓存。
- 在实际 SDK 登录前建立归属，以接住早于 Dart login 返回的原生回调；退出/替换账号/销毁时废弃待发任务。迟到结果不能确认新账号的成功缓存。
- 回前台补写可能被 APNs 改动的系统角标；成功上传过且未变化的数值不再次上传。失败的远端写入可在后续回调或回前台时重试，冷却 5 秒，不自行无限重试。
- 在途发生 A→B→A 时，B 完成后仍恢复 A；不会因为旧缓存恰好是 A 而漏写。无法取消的原生调用仍占用槽位直到完成。

生命周期接线位于 [IMController.login](E:/openim/openim-flutter-demo/lib/core/controller/im_controller.dart:314)、[SDK 退出准备](E:/openim/openim-flutter-demo/lib/core/controller/im_controller.dart:388)、[AppController 前台恢复](E:/openim/openim-flutter-demo/lib/core/controller/app_controller.dart:111)。未改总未读事件流的业务语义。

### L02 正式包原生日志过密

**P1，实际日志和源码均确认，已修改。** 触发条件：Release 包使用默认配置或保存过 4/5/6 等详细日志等级，在持续收消息期间同时生成调用、消息转换、数据库阶段、请求响应等日志。

[Config.logLevel](E:/openim/openim-flutter-demo/openim_common/lib/src/config.dart:123) 旧默认值为 5，读取保存值直接 `int.parse`；[initOpenIM](E:/openim/openim-flutter-demo/lib/core/controller/im_controller.dart:133) 原先没有传 `isLogStandardOutput`，当前依赖默认值是 true。应用自己的 [Logger.print](E:/openim/openim-flutter-demo/openim_common/lib/src/utils/logger.dart:50) 已在 Release 返回，不能只修改应用层 print 就认为关闭了这批 SDK 日志。

按用户补充要求“关闭 DEBUG，保留必要日志”，当前 Debug 构建默认仍为 5；Profile/Release 默认 4，并把保存的 5/6 限制到 4，保留合法的更低等级。非法配置回落到默认值，避免日志配置解析异常阻断初始化。正式/Profile 包显式关闭标准输出，默认保留 INFO、WARN、ERROR 文件诊断，关闭 DEBUG/SQL 调试输出。上游依赖映射为 3=Warn、4=Info、5=Debug、6=DebugWithSQL，见 [OpenIM tools 日志实现](https://raw.githubusercontent.com/openimsdk/tools/v0.0.50-alpha.80/log/zap.go)。

当前 SDK 通过等级控制日志；保留 INFO 也会保留其中的正常请求、成功响应和消息处理记录，不能把它描述成“只保留错误”或“逐条筛选必要日志”。角标去重继续减少重复业务调用，未修改原生 SDK 的日志实现。

改动影响下一次新包的 SDK 初始化，不会改变已安装旧包。降低日志量也不等于消除所有日志参数构造开销，更不能直接换算为 CPU 或温升下降百分比。

### L03 首页初始未读查询可能回写旧值

**P2，静态确认竞态，日志不能量化发生次数；已修改。** 触发条件：首页 `getTotalUnreadMsgCount()` 尚未返回时，SDK 已发布更新的未读计数。

[HomeLogic 初始查询](E:/openim/openim-flutter-demo/lib/pages/home/home_logic.dart:108) 旧逻辑仅检查页面是否关闭，随后覆盖未读数并上传角标。现在记录回调版本，异步返回时同时检查登录归属和期间是否有新回调；较旧查询不覆盖较新事件，并处理查询异常。这样也避免旧值把角标协调器从新计数拉回旧计数。

### L04 未读为零时仍调用会话已读

**P2，空操作实际存在，具体 Flutter 触发点待验证；本轮未盲改。** 23 次空操作中，22 次距离同会话上一请求约 253–600ms；另 1 次是样本中另一会话的首个请求。SDK 已读方法共 89 次，没有相邻间隔小于 100ms 的请求。

应核查 [可见已读](E:/openim/openim-flutter-demo/lib/pages/chat/receipts/chat_read_receipts.dart:229)、[未读快照变更](E:/openim/openim-flutter-demo/lib/pages/chat/receipts/chat_read_receipts.dart:292)、[离页清理](E:/openim/openim-flutter-demo/lib/pages/chat/receipts/chat_read_receipts.dart:346)。当前 [ConversationReadCoordinator](E:/openim/openim-flutter-demo/lib/pages/chat/receipts/conversation_read_coordinator.dart:10) 已按序号、消息 ID、未读版本合并；群可见已读已有 250ms 合并，不能报告成“完全没有去重”。日志没有 Flutter 调用栈或绘制目标，无法把这 23 次准确归因到其中某个入口。

上游该版本在读取会话并发现未读为 0 后提前返回，所以这 23 次不是 23 次额外已读 HTTP 请求；仍会进入锁与本地会话查询。非零路径在锁的作用域内还会等待服务端确认，属于值得关注的 SDK 等待点，但本样本没有证明死锁。[SDK read_drawing.go](https://raw.githubusercontent.com/openimsdk/openim-sdk-core/v3.8.3-patch.12/internal/conversation_msg/read_drawing.go)

下一步应在允许采集时关联“调用入口、实际绘制的最新消息、未读版本、完成时间”；仅合并同一已确认目标的重复请求。不能直接加 `unreadCount == 0` 总开关，因为消息回调可能早于会话资料，且语音/私密消息的内容阅读与会话未读不是同一状态。

### L05 群同步与消息数据库处理

**P2，持续收消息开销存在，异常同步风暴尚无证据。** 群成员增量同步分别发生于 18:51:29、18:51:57、19:08:55、21:06:21、21:07:14、21:07:39；其中前两次登录出现在 18:51:28、19:08:55，其余多次接近前台恢复。最密集的 18:38–18:41 段没有记录这类增量 HTTP 请求，不能把当时所有消息处理日志都当作群成员网络同步。

当前 [群资料查询](E:/openim/openim-flutter-demo/lib/pages/chat/group/chat_group_controller.dart:272) 合并在途任务，[会话更新](E:/openim/openim-flutter-demo/lib/pages/conversation/conversation_logic.dart:91) 已按 80ms 合批并在同步状态转换时刷新。此次不停止正常 IM 消息同步，也不扩大战术缓存时长；相册/位置后台同步的门控是另一个模块。

SDK 共记录 171 批新消息处理，206 条 newMessages（148 批×1、18 批×2、4 批×3、1 批×10）。后续需要把原生阶段与 Flutter 回调、UI 重建和慢帧关联，再决定是否还有需要调整的同步/缓存路径。

### L06 异常复核

- **P2：两次 WebSocket 异常断开。** 21:06:21.207 为连接被对端重置，21:07:14.232 为 close 1006 / unexpected EOF，都紧邻前台恢复；可列为连接恢复检查项，不能仅凭时间接近断言 iOS 挂起是原因。未见数据足以证明无限重连导致发热。
- **P2：两次撤回目标不在本地。** 涉及 SDK `conversation_msg/revoke.go` 和 `notification.go`；保留错误诊断，待结合具体消息顺序与本地历史覆盖范围复核。没有通过改 Flutter JSON 或清数据库来掩盖它。
- **P3：17 次 AttachedInfo 空字符串警告。** SDK `conversation_msg/conversion.go` 在转换本地消息时仍尝试解析空字符串，产生 WARN 后继续构造消息。后续可在所维护的原生 SDK 源码中对空值采用默认结构，并继续记录非空畸形 JSON；本轮未修改共享 pub-cache 或替换 SDK 二进制。[上游转换实现](https://raw.githubusercontent.com/openimsdk/openim-sdk-core/v3.8.3-patch.12/internal/conversation_msg/conversion.go)

## 优化前后对照及验证边界

| 项目 | 修改前实际样本/源码 | 修改后源码行为 | 修改后真机结果 |
| --- | --- | --- | --- |
| 零角标 | 305 次 HTTP，全为 0 | 同一登录内持续不变的 0 成功上传一次后去重；新登录、失败重试另计 | 待验证，不能把含多次登录的样本宣称已从 305 降至 1 |
| 标准输出与日志 | 10,000 行，11,554,174 字节；DEBUG 6,836 行 | Profile/Release 默认 Info，关闭 DEBUG/SQL 和标准输出 | 待验证 |
| 日志等级过滤口径 | 原日志 INFO+WARN+ERROR 共 3,164 行、约 4.34 MB | 仅对旧样本按新默认等级筛选时保留这些行 | 这是旧数据筛选，**不是**新包日志量或性能实测 |
| 角标写入顺序 | 原实现可以并行提交相同/不同数值，重复查询平台能力 | 每个目的端最多一个在途、一个最新待写值；平台能力复用 | 待验证，含失败/切账号/前台恢复 |
| 首页查询竞态 | 只判断页面关闭，旧查询可覆盖新回调 | 登录归属及回调版本校验 | 待验证，日志无命中次数 |
| 已读空操作 | 23/89 次，实际已读 HTTP 为 66 次 | 保留现有合并和可见门控，本轮未新增过滤 | 无改后数据 |

已有原生日志可提供以下**耗时基线**，但其中 SDK 调用包括网络/排队等待，数据库阶段也不是 Flutter 主 Isolate CPU 时间，不能当成 UI 帧时长或直接相加推导卡顿：

| 日志阶段 | 样本数 | p50 | p95 | 最大 |
| --- | ---: | ---: | ---: | ---: |
| SetAppBadge 完整调用 | 305 | 43.42ms | 75.46ms | 142.27ms |
| MarkConversationMessageAsRead 完整调用 | 89 | 60.98ms | 94.75ms | 112.18ms |
| doMsgNew 完整阶段 | 171 | 18.43ms | 64.48ms | 88.04ms |
| 消息批量插入阶段 | 171 | 8.76ms | 10.31ms | 13.07ms |
| 会话批量更新阶段 | 171 | 2.44ms | 3.45ms | 10.33ms |
| 多会话数据库读取阶段 | 171 | 0.48ms | 0.80ms | 2.25ms |

本轮完成源码调用链、依赖签名、登录/退出/前后台接线及差异检查；未执行代码来验证上述并发边界。将来允许真机验证时，应固定相同设备和消息速率，对比 SDK 请求数、日志字节/分钟、UI/raster 慢帧比例、CPU、内存与能耗；先验证角标首次 0、A→B→A、失败重试、退出重登、后台 APNs 后恢复，再评估总体效果。完全卡死仍需发生时的线程/挂起记录或 Timeline，当前日志不能排除其他模块的问题。
