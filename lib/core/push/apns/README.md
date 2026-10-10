# iOS APNs 推送

由 `AppController` 持有一个 `APNsPushRuntime`，负责 iOS 普通消息的设备注册、OpenIM 后端绑定、令牌刷新和退出解绑。Android 继续使用原有推送入口。

| 文件 | 职责 |
| --- | --- |
| `apns_platform.dart` | 原生通道、令牌元数据和注册／点击／失败事件 |
| `apns_token_api.dart` | 捕获 IM 身份的 `POST /third/set_push_token`、`POST /third/delete_push_token` 与回执校验 |
| `apns_push_runtime.dart` | 会话归属、前台／24 小时续期、离线通知开关、原生失败保护及上传／解绑串行队列 |
| `apns_notification_target.dart` | 服务端顶层收件人／消息 ID 与 `ex` 转换，查询 SDK 真实会话后创建本地目标 |

请求使用 `Config.imApiUrl` 的完整地址前缀、`token: <IM token>` 和独立 `operationID`，不带 Chat Bearer 或三公租户头。注册 JSON 为 `{platformID:1, deviceID, provider:"apns", token, environment}`；`environment` 为 `development` 或 `production`，仅上报普通 APNs token，不混入 PushKit token。

注册必须收到 HTTP 2xx、整数 `errCode:0`，且 `data.userID`、`data.platformID:1`、`data.deviceID` 对应捕获的用户和设备。解绑 JSON 为 `{platformID:1, deviceID}`，成功回执同样核对用户及平台，并要求 `data.removed` 是非负整数；空的 HTTP 204 不作为确认。

SDK 同步认证成功可以解除退出阻止；普通前台和路由回调不能恢复已经退出的旧身份。账号、IM token 或服务器变化会立即废弃旧回调，用旧凭据完成旧设备解绑。令牌只保存在内存，不写日志。

原生注册失败会使当次等待结果失效。失败后至少等待 30 秒，再在后续会话就绪／前台回调重试；没有后台重试定时器。

退出解绑只有收到有效成功回执才标记完成。失败时在内存保留捕获的旧 IM 身份和设备作用域，至少等待 30 秒，再由明确退出、前台或会话就绪回调重试；即使没有新账号或 SDK 尚未就绪，也可以清理旧绑定。首次冷启动的 SDK 登录准备尚未拥有会话时，不发起解绑请求或等待网络。

旧清理与新注册共用串行队列。同一服务器、用户和设备开始新注册后，旧作用域的失败清理任务被取代，不能再迟到删除新绑定；取代不代表旧 DELETE 已成功。其他账号的失败任务继续保留。旧凭据不持久化；进程被结束或服务端撤销旧 IM token 后，客户端无法保证残留绑定已清除，需要服务端失效策略兜底。

通知点击按收件人和消息 ID 去重，等待 SDK 同步及通知偏好就绪，复用消息通知模块的队列与聊天导航。已验证属于当前账号但缺少定位信息、或 SDK 会话无法匹配时，返回消息列表；错误账号的通知直接忽略。关闭离线通知只删除本机绑定，已显示的通知仍可点击。明确退出清理原生点击事件，冷启动 SDK 登录准备保留待处理点击。

完整接口、原生协议、点击 payload 与 macOS／iPhone 验证步骤见 [接入说明](../../../../docs/ios-apns-push.md)。PushKit 和 CallKit 由独立通话模块维护。

回归测试位于 `test/core/push/apns/`。
