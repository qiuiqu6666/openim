# 登录与本地退出

头部健康状态由业务 Chat API、IM API 的只读可用性探测和 SDK 独立连接状态共同决定。消息／群聊和通讯录复用 `connection/widgets/connection_health_title.dart`；同步开始、进度、结束或失败不覆盖连接结果。API 未确认时显示连接中，API 不可用显示服务连接异常，SDK 连接失败显示连接失败，两者正常时恢复页面标题。`ApiConnectionHealth` 每个登录代次只有一个前台检查循环，正常 30 秒、连续失败按 3/6/12/30 秒退避复查，回前台或网络恢复立即检查并重置退避；后台暂停，旧账号、旧节点和旧前台周期的结果不能发布。探测复用节点检查中的公开只读 Chat/IM API，不携带凭据、不建立额外消息 socket，也不发送测试消息；SDK 连接成功代表消息通道连接状态，不是逐条消息送达证明。

`connection/IMConnectionRecovery` 由当前登录代次持有。切回前台、网络恢复时立即通知原生 SDK，前台恢复 3 秒后复查；connecting／connectionFailed／syncFailed 或上次唤醒失败时每轮唤醒结束后等待 3 秒重试。其余前台状态每分钟只检查失败状态，不调用原生全量元数据同步。后台停止检查，登录替换、退出和关闭取消观察者、网络订阅及当前等待；旧计时任务不能覆盖新一轮前台复查。完整唤醒等待最多 18 秒，超时只结束调用方等待。

SDK 的连接成功、连接中、连接失败或同步失败会请求一次 3 秒后的增量复查，覆盖网络类型不变时的原生重连。连续相同状态先去重，已有待执行复查不被重复回调延期。同步结束不再触发新唤醒，避免原生补丁发布结束事件后产生循环。唤醒成功向聊天历史发送恢复提示：可见的健康最新窗口补读，失败窗口恢复有限重试，历史窗口保留阅读位置，后台或被覆盖页面延后处理。这个提示不证明“全部消息补齐”，不改写 SDK 状态。

`connection/im_native_connection_wake.dart` 先调用 `setAppBackgroundStatus(false)`，等待前台确认最多 12 秒。超时不关闭 socket；只有原生明确报错、状态为连接中/连接失败且本轮仍有效时才调用 `networkStatusChanged`。该方法在锁定 SDK 中会关闭 socket，因此同步失败本身也不能授权断连。`IMNativeConnectionWake` 用 `SdkQueryGate` 保留实际未结束请求的一个名额，重复唤醒复用同方法请求；等待上限与真实在途时间分离。每次后续操作都检查账号、登录代次和唤醒资格。

这两个未在 Dart 包装层公开的方法必须携带与 `IMManager._buildParam` 一致的 `ManagerName: imManager` 和非空 `operationID`。Android 插件按该字段反射定位 manager；缺失会在 `getDeclaredField` 抛空指针异常并留下未完成的调用。iOS 同样按该字段分发，缺失时也不回调。2026-10-12 已有 Android 日志证据；对应测试入口为 `im_native_connection_wake_test.dart`。本轮仅维护断连和请求占用的断言，没有执行测试或安装设备包。

现有原生二进制仍可能忽略分批拉取错误并发布同步结束；一次 `syncEnded` 不能证明每个群都已补齐。错误传播、处理回执、序号提交及截止修复已保存为 [受控原生补丁](../../../native_sdk/README.md)，尚未产出和接入新二进制。正常增量重试不绕过退群、历史下限或服务端权限，也不把最新摘要拉取变成全部历史下载。[修复状态与待验证项](../../../docs/sdk-recovery-fixes-2026-10-13.md)。

`SdkSessionQueue` 只管理 SDK login/logout 的执行顺序和结果代次。旧请求即使完成，也不能发布到新会话。退出及账号切换必须经过同一个 `IMController` 队列，不能直接调用 SDK logout 或用超时绕过尚未结束的 native cleanup。

排队中的登录与残留旧账号清理的准备过程共用 15 秒上限，届时返回 `SdkSessionBusy`；超时请求失效，随后 SDK 清理完成也不会执行这个登录。队列始终保留尚未结束的 native cleanup，不允许下一登录越过它。真正开始 SDK login 时才结束准备计时；SDK 已经开始的登录仍沿用原 SDK 行为。调用方应展示可重试提示。

`exitLocalSession` 同步发起排队清理并接住后台异常，只等待本地凭据清除后导航。`HomeLogic.endSession` 是主页、主动退出、踢出与锁屏失败的业务入口；设置服务可以使用同一退出流程辅助函数。清理失败后换账号登录仍先重试 native logout，失败则拒绝登录，以免 SDK 复用旧账号。

iOS SDK 清理使用 `endRemotePushSession(waitForRemote: false)`：等待本机 APNs 注销、CallKit pause、音频释放与媒体结束，但不等待远端推送注册／解绑。远端操作仍使用捕获的旧账号 transport，在原串行队列中继续并处理失败，不能删除队列或提前允许新推送注册覆盖旧解绑。本机和 SDK 操作没有增加超时放行；若它们未结束，新登录仍受会话队列保护。这项优化只消除远端推送等待对 SDK 登录的阻塞，不解决原生 SDK 或媒体清理自身卡住的问题。

对应回归位于 `test/core/session`；启动门槛回归位于 `test/pages/splash`；会话读取和事件竞态位于 `test/pages/conversation`。

连接标题使用 SDK 实际连接、同步回调。再次调用同一有效登录代次、同一账号与 IM token 的登录入口时，保留已经确认的连接／同步／失败状态：Flutter SDK 在原生已经登录时会跳过 native login，不保证重新发送连接成功回调，不能先无条件写入 connecting。新账号、token 更换、退出后重新登录仍重置状态。`getLoginStatus == logged`、本地列表加载成功和业务 HTTP 成功都不能单独证明消息长连接正常；不得据此伪造 connectionSucceeded 或 syncEnded。回归 `connection/im_connection_status_test.dart` 覆盖原生登录复用、真实重连、账号／token 切换与重新登录；页面缓存恢复回归位于 `conversation_chrome_test.dart`。

热重启会丢失 Dart 登录标记和连接事件，但原生 SDK 进程可能仍为 logged／logging。登录队列在 Dart 未持有登录会话时复用 `_logoutSafely` 检查、清理残留原生会话，再执行正常登录，等待真实连接／同步回调；原生已退出的冷启动只检查状态，不执行 logout。同一运行期已持有的会话仍按上一段复用，后台恢复不会因此强制重登。清理继续受原有准备超时、串行队列和代次保护，失败不能绕过，且不清除本地登录凭据或消息数据库。上述连接回归也覆盖热重启残留、跨账号残留、清理等待与失败。

`IMCallback` 的会话、好友、群成员、退群及资料通知仅发布实时增量，不保存和回放最后一条事件。各页面的初始数据由当前 SDK 登录会话的快照读取提供，避免同一设备 A→B→A 切换时，新控制器收到上一账号的会话预览、好友或群状态。登录和退出边界重置连接状态，新的订阅不会复用上一账号的同步完成状态；原生本人资料更新只接受当前登录代次和对应用户。回归 `im_callback_account_isolation_test.dart` 覆盖真实会话控制器订阅、加载期间切换、旧群/好友事件及当前新事件的正常递送。此处验证客户端回放隔离；原生回调没有携带账号代次，完整登出后的跨会话包投递仍需设备 SDK 验证。

`CurrentUserProfileSource` 使用现有 Chat `/user/find/full` 接口（`Urls.getUsersFullInfo`）与 `HttpUtil`，请求携带捕获的账号和 token；后台失败本身不会清凭据或导航。`HttpUtil` 统一负责当前 token 的 1501–1507、20101 和 100010 失效事件，`IMController` 只识别错误，不再重复发布事件，并在所有异步返回后检查代次、账号、token、关闭状态和目标 Rx 所有权。旧 token 或未携带 token 的响应不会结束当前会话。主页按当前语言显示登录失效提示；请求层记录该提示的所有权，避免同一次请求重复提示。

登录页通过 `Apis.login` 的可选 `isCurrent`/`showErrorToast` 请求所有权参数管理认证异常反馈；当前失败由页面反馈，关闭或凭据已改变的旧失败丢弃。共用 API helper 仅记录错误，网络异常不清凭据或导航，登录失效由请求层的 token 保护和主页退出流程处理。登录页认证返回后再次检查所有权，避免旧成功覆盖后来写入的凭据。

消息和群聊标题通过 `IMController.connectionChecking` 观察当前恢复等待，并用独立的 `connectionVerified` 保存本轮原生前台确认结果。只有当前恢复获得成功确认、SDK 明确为连接成功、API 检查正常且延迟有效时，才显示正常延迟胶囊。等待结束不等于确认成功：超时、失败、后台、网络断开或新一轮恢复均不能沿用旧确认，迟到回调也不能确认后续恢复；未确认时保留“连接中...”，明确连接或服务失败仍显示失败状态。确认连接不代表消息已全部同步完成。
