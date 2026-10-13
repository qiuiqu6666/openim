# 单聊通话状态同步

本模块连接 Chat `/calling/*`、OpenIM 200–204 和 iOS PushKit/CallKit。群通话协议不在本模块扩展范围内。

## 维护边界

- `data/call_backend_api.dart`：通过 `Config.callingUrl` 使用当前 `Config.appAuthUrl`，跟随服务配置和活动节点路由；捕获 Chat token、账号和安装设备 ID，检查 HTTP 与业务错误。地址切换后旧请求不再发布到当前会话；不使用 IM token。
- `data/call_state_snapshot.dart`：验证单聊快照的房间、参与账号、版本和设备字段；accepted 不再使用邀请截止时间。
- `data/call_state_runtime.dart`：Android/iOS 共同的状态所有者，处理业务通知、版本去重、邀请校验、操作提交、恢复查询和振铃期间的状态轮询。
- `data/call_signal_persistence.dart`：保留原信令发送前的持久化入口。
- `data/call_state_heartbeat.dart`：仅执行已接听参与设备的显式保活；停止不关闭共享 API、不自动挂断。
- `ios/`：原生来电展示、设备 token 注册、冷启动恢复、CallKit 音频及系统操作适配。状态轮询统一交给通用 runtime。

`IMController` 只绑定已验证的 SDK BusinessNotification、SDK 恢复事件和现有媒体控制器；`AppController` 转发前台恢复与系统通话状态。`openim_live` 保留 RTC、铃声、通话记录和普通信令的身份校验。本次在这些已有超长协调文件中只接入必要入口，状态协议与请求逻辑均在本模块维护。

## 必须保持的约束

1. 业务通知只是查询提示，通过带 Chat token 和 deviceID 的 status 确认；普通聊天自定义消息不能驱动服务端状态入口。
2. 账号、Chat token、通话 ID 和会话代次隔离。版本按房间比较，终态不复活，accepted 不回退到 ringing。
3. accept 由服务端确认本机设备后，才发 201、取 RTC 凭证及入房。权限错误、404、其他设备抢接不能变成接听成功。
4. 每个房间只合并一个在途 status；振铃时完成查询后等 2 秒再查。参与设备接听后首跳立即执行，之后完成心跳后等 10 秒；失败等 3 秒短暂重试。
5. 服务端终态/其他设备接听只能走 `endCallLocally(..., localOnly: true)`。不能用通用用户挂断回调清理，否则可能反向结束获胜设备。
6. iOS 原生 `markAccepted` 只取消邀请计时，不报告媒体连通。RTC 连接仍有独立超时，真正媒体连接后才调用 `markConnected`。
7. `otherAccepted` 是本地结果，不能排入服务器通话记录上报；缓存合并保留该结果，避免后续共享记录把本机显示改成已通话或未接。

## 验证状态

见 [2026-10-12 修改与联调说明](../../../docs/call-multi-device-sync-2026-10-12.md)。本轮按用户限制未构建、未运行测试或 analyzer，也未连接真机/调用线上接口。静态检查不代表编译或双端联调通过。
