# 请求错误与提示

- `ApiErrorMessages` 管理业务错误码的本地化文案，已知业务原因保留具体提示；服务故障隐藏后台详情。
- `TransportErrorMessages` 将 Dio、原生 SDK、Socket 和超时异常转换为用户提示，并为已转成字符串的旧 Toast 入口提供兜底。仅识别明确异常格式，普通提示不按网络关键词猜测。
- `HttpUtil.errorMessage` 先读取 HTTP 业务错误响应，再委托上述映射器；原始异常继续向调用方传播，不改变失败状态。
- `RiskFeedback` 负责应静默的风控拒绝。拥有提示的调用方仍需保留登录失效处理、账号有效性检查及取消请求策略。

页面优先使用 `IMViews.showErrorToast(error)`，需要特定业务上下文时传 `path` 或用户可读的 `fallback`。禁止直接展示 `error.toString()`、后台 `errMsg` 或异常堆栈。

验证：`test/widgets/feedback/error_toast_test.dart`、`test/services/account_verification/`、`test/services/risk_control/silent_risk_feedback_test.dart`。
