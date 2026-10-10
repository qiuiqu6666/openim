# 登录与本地退出

`SdkSessionQueue` 只管理 SDK login/logout 的执行顺序和结果代次。旧请求即使完成，也不能发布到新会话。退出及账号切换必须经过同一个 `IMController` 队列，不能直接调用 SDK logout 或用超时绕过尚未结束的 native cleanup。

排队中的登录与残留旧账号清理的准备过程共用 15 秒上限，届时返回 `SdkSessionBusy`；超时请求失效，随后 SDK 清理完成也不会执行这个登录。队列始终保留尚未结束的 native cleanup，不允许下一登录越过它。真正开始 SDK login 时才结束准备计时；SDK 已经开始的登录仍沿用原 SDK 行为。调用方应展示可重试提示。

`exitLocalSession` 同步发起排队清理并接住后台异常，只等待本地凭据清除后导航。`HomeLogic.endSession` 是主页、主动退出、踢出与锁屏失败的业务入口；设置服务可以使用同一退出流程辅助函数。清理失败后换账号登录仍先重试 native logout，失败则拒绝登录，以免 SDK 复用旧账号。

对应回归位于 `test/core/session`；启动门槛回归位于 `test/pages/splash`；会话读取和事件竞态位于 `test/pages/conversation`。

连接标题使用 SDK 实际连接、同步回调。再次调用同一有效登录代次、同一账号与 IM token 的登录入口时，保留已经确认的连接／同步／失败状态：Flutter SDK 在原生已经登录时会跳过 native login，不保证重新发送连接成功回调，不能先无条件写入 connecting。新账号、token 更换、退出后重新登录仍重置状态。`getLoginStatus == logged`、本地列表加载成功和业务 HTTP 成功都不能单独证明消息长连接正常；不得据此伪造 connectionSucceeded 或 syncEnded。回归 `connection/im_connection_status_test.dart` 覆盖原生登录复用、真实重连、账号／token 切换与重新登录；页面缓存恢复回归位于 `conversation_chrome_test.dart`。

热重启会丢失 Dart 登录标记和连接事件，但原生 SDK 进程可能仍为 logged／logging。登录队列在 Dart 未持有登录会话时复用 `_logoutSafely` 检查、清理残留原生会话，再执行正常登录，等待真实连接／同步回调；原生已退出的冷启动只检查状态，不执行 logout。同一运行期已持有的会话仍按上一段复用，后台恢复不会因此强制重登。清理继续受原有准备超时、串行队列和代次保护，失败不能绕过，且不清除本地登录凭据或消息数据库。上述连接回归也覆盖热重启残留、跨账号残留、清理等待与失败。

`IMCallback` 的会话、好友、群成员、退群及资料通知仅发布实时增量，不保存和回放最后一条事件。各页面的初始数据由当前 SDK 登录会话的快照读取提供，避免同一设备 A→B→A 切换时，新控制器收到上一账号的会话预览、好友或群状态。登录和退出边界重置连接状态，新的订阅不会复用上一账号的同步完成状态；原生本人资料更新只接受当前登录代次和对应用户。回归 `im_callback_account_isolation_test.dart` 覆盖真实会话控制器订阅、加载期间切换、旧群/好友事件及当前新事件的正常递送。此处验证客户端回放隔离；原生回调没有携带账号代次，完整登出后的跨会话包投递仍需设备 SDK 验证。

`CurrentUserProfileSource` 使用现有 Chat `/user/find/full` 接口（`Urls.getUsersFullInfo`）与 `HttpUtil`，请求携带捕获的账号和 token；后台失败本身不会清凭据或导航。`HttpUtil` 统一负责当前 token 的 1501–1507、20101 和 100010 失效事件，`IMController` 只识别错误，不再重复发布事件，并在所有异步返回后检查代次、账号、token、关闭状态和目标 Rx 所有权。旧 token 或未携带 token 的响应不会结束当前会话。主页按当前语言显示登录失效提示；请求层记录该提示的所有权，避免同一次请求重复提示。

登录页通过 `Apis.login` 的可选 `isCurrent`/`showErrorToast` 请求所有权参数管理认证异常反馈；当前失败由页面反馈，关闭或凭据已改变的旧失败丢弃。共用 API helper 仅记录错误，网络异常不清凭据或导航，登录失效由请求层的 token 保护和主页退出流程处理。登录页认证返回后再次检查所有权，避免旧成功覆盖后来写入的凭据。
