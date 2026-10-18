# 会话整理刷新与诊断

`ConversationLogic.refreshOrganizer` 默认是用户主动刷新，失败沿用现有错误提示。
启动、SDK 重连、回前台、分组删除推送和归档页初始化传入
`userInitiated: false`，失败仅保留错误状态及原有数据，不弹 Toast。
分组排序失败后的恢复刷新也静默，避免同一次操作提示两次。

`OrganizerRefreshQueue` 串行执行请求，合并执行期间收到的刷新触发。
排队的手动请求优先保留反馈权限，后来的自动触发不能覆盖它。
返回的 Future 等待排队刷新结束；会话失效后不执行剩余刷新。
队列本身不定时重试，仍由原有生命周期、推送及用户操作触发。

`ChatOrganizerApi` 的请求统一经过 `OrganizerRequestDiagnostics`。
失败日志事件为 `organizer_request_failed`，包含固定接口模板、触发来源、
operationID、elapsedMs、异常类型，以及可获取的 HTTP 状态或业务错误码。
不记录域名、token、请求体、查询参数、分组名、会话 ID 或异常原始详情。
动态路径使用 `:id`。分页请求分别计时和记录请求编号。

诊断在正式版同样执行：写入开发者日志；SDK 已初始化时同时写入原有
OpenIM 原生日志。SDK 未就绪或日志写入失败时不影响原请求及用户反馈。
这覆盖会话整理 API，不代表已为全部 HTTP 客户端或 SDK 方法补齐诊断。

验证入口：
- `test/pages/conversation/organizer/organizer_refresh_queue_test.dart`
- `test/pages/conversation/folders/conversation_folder_api_test.dart`
- `test/pages/conversation/archive/`
- `test/widgets/feedback/`
