# Chat 通话记录对接验证

## 对接范围

- Mine → 最近通话沿用现有入口和 99chat 列表布局、全部/未接、编辑、单聊重拨。
- POST/GET 使用 Chat 服务 `Config.appAuthUrl`、`token: chatToken` 和 `operationID`，
  请求中不包含所属用户。API 自动兼容配置地址末尾已有 `/chat`。
- invitation.roomID 为双方共享 callID；caller 终态上报一次，callee 保存本地记录并接收镜像。
- 已接通、超时、拒绝、取消分别映射 completed/missed/rejected/cancelled；
  接通后断线仍保存已接通时长。通过可选 terminalState 兼容区分超时与拒绝。
- 新增报告字段始末时间为毫秒，群参与人使用 participantUserIDs。
- 按账号持久保存 pending 报告、服务端记录、syncAt 及隐藏标记，继续使用已有 Hive box。
- 满页和超额同毫秒页继续增量请求，短页结束；记录和 syncAt 在同一次持久写入中提交。
- OpenIM `callRecordChanged` 业务通知校验 sendUserID/recvUserID，按 callID/updatedAt 更新。
- 页面打开、重连、恢复前台补拉并重试未同步报告。失败保留本地记录并提供重试。
- 群记录显示群名称或群 ID；现有 RTC 只支持单聊，因此不把群记录当成单人重拨。
- 服务端未提供删除接口，页面明确提供“仅从本设备隐藏”。

## 自动验证

针对测试覆盖 HTTP 请求和响应、游标分页、失败后的续拉、同 callID 权威覆盖、
报告持久重试、实时通知、账号/凭据切换、旧 Hive 数据兼容、结束信令和 SDK 聊天消息。
页面测试覆盖实时未接转接通、隐藏后更新、错误重试、前后台/重开、320px/两倍文字及亮暗主题。

2026-10-05 验证结果：

- 通话页、数据同步及现有通话回归：102 项通过。
- 账号会话生命周期与首页入口回归：23 项通过。
- 本次通话模块与接线的静态检查无错误、无警告；涉及旧文件仍有 21 项 info 提示，
  主要为既有代码风格、SDK group 弃用及依赖声明提示。
- Android ARM64 debug APK 构建成功，产物 `build/app/outputs/flutter-apk/app-debug.apk`。
- 相关改动 `git diff --check` 通过。

命令日志保存在 `.dart_tool/call-records-regression.log`、
`.dart_tool/call-records-session-regression.log`、`.dart_tool/call-records-analyze.log`
和 `.dart_tool/call-records-android-build.log`。

回归还修正了平台识别在无挂载页面时的空上下文访问，以及既有会话测试中
AppController 模拟对象缺少通知清理方法的问题；原账号与清理断言保留。

## 真机联调

当前自动验证使用模拟 HTTP 和 SDK 回调，不调用真实用户或发起真实电话。
上线前用两个测试账号确认：caller 音视频各打一通；分别执行接听结束、拒绝、取消、超时；
检查双方 callID 相同、方向相反、时长正确。第二台设备保持在线确认通知覆盖，
离线后再登录确认增量补齐；断网结束后重连确认待上报记录补写。

服务端群通话测试可使用既有群呼叫客户端产生记录，再在此页面验证群资料和列表同步。
本次不新增群 RTC 引擎。
