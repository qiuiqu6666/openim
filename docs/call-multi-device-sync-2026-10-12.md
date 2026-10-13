# 音视频通话多端同步：客户端修改记录

日期：2026-10-12。依据用户提供的同日服务端契约实施。

修改目录是本地 `E:\openim\openim-flutter-demo`。已确认此目录原来已有 `/calling/invite`、`action`、`status` 接入。未访问、修改或确认服务器 `/www/wwwroot/openim-flutter-push-20261011` 的打包分支；本文不代表已部署。保留工作区已有性能优化及其他并行修改。

## 静态证据与修改

| 源码位置 | 原行为及触发条件 | 修改后行为 |
| --- | --- | --- |
| `lib/core/calling/data/call_backend_api.dart` | status 不带 deviceID，通过查询隐式保活 | 明确携带持久设备 ID；新增 heartbeat/current；使用契约 HTTPS 入口、Chat token 和 UUID operationID；错误同时保留 HTTP 与业务码 |
| `lib/core/calling/data/call_signal_persistence.dart` | 接听收到 404 仍可继续，invite 后便启动保活 | 委托统一状态所有者；404 不授予接听权；获胜设备确认后才能继续原信令 |
| `lib/core/calling/data/call_state_runtime.dart` | 原来没有跨平台的 callStateChanged 消费、版本去重和 current 恢复 | 只订阅 SDK 业务通知，再查 status 校验；按账号/Chat token/房间/代次隔离，按 revision 去重；登录、重连、回前台查询本地活跃房间及 current |
| `lib/core/calling/data/call_state_heartbeat.dart` | 定时 status，finish 会额外 cancel/reject/hangup | accepted 且本机为实际参与端才显式 heartbeat；一次只一个请求；停止仅清理本地任务 |
| `openim_live/lib/src/live_controller.dart` | 接听前先取 RTC 凭证；结束流程先占用本地终态，再请求服务端 | accept 提交与设备归属确认在前；终结操作合并，失败查询校准/提示；权威服务端终态通过独立本地关闭路径处理 |
| `openim_live/lib/src/live_client.dart`、`session/single_call_session.dart` | 通用结束回调可能间接触发结束信令 | 新增 localOnly 标记，只对服务端清理跳过信令/错误回调；普通远端信令的已有回调保留 |
| `lib/core/calling/ios/ios_voip_backend.dart` | 独立 2 秒状态轮询，与跨平台 10 秒 status 重叠；冷恢复一次网络错误就关闭 | 共享 status 和振铃轮询；瞬时失败不直接当成远端挂断；非获胜设备无权结束通话 |
| `lib/core/calling/ios/ios_callkit_runtime.dart` | 服务端关闭、系统 ended 回调与用户挂断容易串联 | 系统 ended 仅关闭本地；用户结束/本机系统操作失败仍经过服务端权限校验；媒体释放后恢复音频会话 |
| `ios/Runner/Calling/CallKitCallCoordinator.swift`、`IOSVoIPCallBridge.swift` | 原邀请计时可能在 accepted 后继续结束 CallKit | 新增 markAccepted，只取消邀请计时；媒体连接独立超时；不把 accepted 当作 connected |
| `openim_common/lib/src/controller/cache_controller.dart`、`utils/utils.dart` | 其他设备接听结果可能被后来的共享记录覆盖，聊天气泡缺少对应映射 | 本地 otherAccepted 结果不入上报队列，合并保留，并显示“已在其他设备接听” |

以上多端抢接、误挂断和越过接听授权边界属于高优先级正确性问题。重复定时查询同时带来额外网络与耗电开销；本次没有更改群通话协议、消息主链或数据库架构。

## 前后开销对照（源码推导，非实测）

| 条件 | 修改前 | 修改后 |
| --- | --- | --- |
| iOS 已接听且两套旧任务都在运行 | 2 秒 status 加 10 秒 status，理论稳态约 36 次/分钟 | 仅参与设备的 10 秒 heartbeat，约 6 次/分钟；停止振铃轮询 |
| Android 已接听 | 10 秒 status 隐式续租 | 10 秒 heartbeat 显式续租；按设备归属启动 |
| 振铃阶段 | 两个平台的补偿机制不一致 | 共享 2 秒只读 status；不保活，不延长邀请期限 |
| 重复状态通知 | 缺少统一版本处理 | 已知版本直接丢弃；同房间在途 status 合并；最多跟进一次更新提示 |
| 本地界面清理 | 可能额外发结束请求 | 服务端关闭不反馈结束信令/请求 |

上述频率忽略请求耗时；新调度是在请求完成后计时。立即首跳、通知补偿、前台恢复和失败重试另计，不能将表中数字作为真机功耗降幅。CPU、内存、帧耗时、耗电和温升均 **待实测**；未生成任何性能实测数值。

## 静态核对与验证边界

- 已沿业务通知入口、200–204 发信令顺序、单次接听入口、状态校准、本地清理、CallKit ended 回调、媒体释放和本地记录合并检查调用链。
- 已执行差异空白检查 `git diff --check`；无差异格式错误。未运行构建、测试、analyzer、模拟器、真机或线上请求。
- 既有 `test/core/calling/data/call_state_heartbeat_test.dart` 仍描述“status 续租、finish 自动挂断”的旧契约；该入口已移除，其调用签名/断言需要按新协议迁移。既有 API/iOS 后台假实现也需要注入当前凭证及通用状态管理器，不能把旧测试结果视作新版验证。本轮遵守不构建测试的限制，未执行或新增测试。
- 老版本调用方若没有服务端通话记录，当前客户端将拒绝恢复/接听；这是按新契约撤销原 404 放行行为后的兼容性变化。
- 旧版业务通知可能缺失 revision，按 0 兼容；accepted 可前进到终态，但不能回退振铃。每个会话最多保留 256 个非活跃快照；超过保留窗口的历史状态仍须由服务端 status 兜底。

## 真机联调清单（全部待验证）

1. 同账号 iOS + Android 同时来电，一端成功，另一端停止铃声/振动/界面，记录其他设备已接听。
2. 同时点击接听，仅获胜端发 201、获取 RTC 凭证及入房；冲突端不发结束请求。
3. 非获胜端点击拒接、关闭页面、CallKit 结束，不影响获胜设备。
4. 取消、拒接、挂断同步至双方其他设备；取消先于 invite 返回也不复活。
5. 无人接听按原邀请期限结束；最后一秒接听后不被旧邀请计时挂断，媒体连接仍有独立超时。
6. 一端断网、另一端正常心跳；服务端 45 秒独立租约到期后结束整场，单次网络失败不误判挂断。
7. LiveKit 短断重连在服务端 15 秒宽限期内恢复；旧连接 leave 不结束新连接。
8. RTC 房间结束，业务通知或 heartbeat 终态关闭正确房间，客户端不调用 webhook。
9. 重复/延迟/乱序通知；旧房间终态与新来电交错；接受状态之后的旧 ringing 不回退。
10. 重启、IM 重连、回前台、账号和 Chat token 切换；旧任务不使用新凭证操作旧房间；current=null 不恢复历史邀请。
11. iOS 前台/后台/锁屏、冷 PushKit 和 CallKit 接听/取消，与 Android 交叉拨打；确认媒体音频释放顺序、无误挂断。
12. accept/hangup 返回 401、403、404、409、HTTP 200 非零 errCode、超时及响应丢失；以 status 校准但不把权限错误变成成功。
