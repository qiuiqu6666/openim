# 登录与本地退出

`SdkSessionQueue` 只管理 SDK login/logout 的执行顺序和结果代次。旧请求即使完成，也不能发布到新会话。退出及账号切换必须经过同一个 `IMController` 队列，不能直接调用 SDK logout 或用超时绕过尚未结束的 native cleanup。

排队中的登录与残留旧账号清理的准备过程共用 15 秒上限，届时返回 `SdkSessionBusy`；超时请求失效，随后 SDK 清理完成也不会执行这个登录。队列始终保留尚未结束的 native cleanup，不允许下一登录越过它。真正开始 SDK login 时才结束准备计时；SDK 已经开始的登录仍沿用原 SDK 行为。调用方应展示可重试提示。

`exitLocalSession` 同步发起排队清理并接住后台异常，只等待本地凭据清除后导航。`HomeLogic.endSession` 是主页、主动退出、踢出与锁屏失败的业务入口；设置服务可以使用同一退出流程辅助函数。清理失败后换账号登录仍先重试 native logout，失败则拒绝登录，以免 SDK 复用旧账号。

对应回归位于 `test/core/session`；启动门槛回归位于 `test/pages/splash`；会话读取和事件竞态位于 `test/pages/conversation`。

`CurrentUserProfileSource` 使用现有 Chat `/user/find/full` 接口（`Urls.getUsersFullInfo`）与 `HttpUtil`，请求携带捕获的账号和 token；后台失败本身不会清凭据或导航。`HttpUtil` 统一负责当前 token 的 1501–1507、20101 和 100010 失效事件，`IMController` 只识别错误，不再重复发布事件，并在所有异步返回后检查代次、账号、token、关闭状态和目标 Rx 所有权。旧 token 或未携带 token 的响应不会结束当前会话。主页按当前语言显示登录失效提示；请求层记录该提示的所有权，避免同一次请求重复提示。

登录页通过 `Apis.login` 的可选 `isCurrent`/`showErrorToast` 请求所有权参数管理认证异常反馈；当前失败由页面反馈，关闭或凭据已改变的旧失败丢弃。共用 API helper 仅记录错误，网络异常不清凭据或导航，登录失效由请求层的 token 保护和主页退出流程处理。登录页认证返回后再次检查所有权，避免旧成功覆盖后来写入的凭据。
