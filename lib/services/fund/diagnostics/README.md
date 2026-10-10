# 钱包加载日志

Debug 模式控制台筛选 `[WalletLoad]`。仅在状态变化及请求边界输出，不在 build、动画帧或轮询中输出；Release 不输出，也不创建诊断计时器。

- `view mounted`：钱包入口占位页已挂载，附当前 phase。
- `entry start/phase/password_check_start/password_check_result/end`：入口检查及最终状态；`failed` 仍按原交互保留骨架。`skipped/ignored/cancelled` 附未挂载、重复请求、标签、账号、路由及前后台判断。
- `http start/response/error/end`：仅 GET `/chat/fund/pay-password` 与 `/chat/fund/balances`，包含服务地址、operationID、耗时、HTTP 状态、业务错误码、返回结构类型；支付密码状态只输出布尔值。
- `assets start/snapshot_applied/error/end`：资产加载与解析、条目数量、缓存和 loading 状态；`deferred/coalesced/ignored` 表明请求推迟、合并或结果丢弃。
- 未结束的入口检查／资产加载／HTTP 请求满 5 秒各输出一次 `pending`，不修改请求超时、不触发重试；等待用户设置密码也可能仍处于 entry pending，结合 `password_setup_open` 判断。结束、取消及入口释放会停止该诊断计时器。

每个跟踪的 `id` 在进程内递增。`operationID` 沿用真实请求头，方便关联后端日志。日志不输出 token、账号、密码、金额、地址、交易明细、请求／响应正文或原始异常消息；请求地址剔除 user-info、query 与 fragment。诊断写入异常不能改变业务结果。

回归：`test/services/fund/diagnostics/wallet_load_log_test.dart`；原有入口、支付密码协议、资金 API、资产控制器用例继续验证业务行为。
