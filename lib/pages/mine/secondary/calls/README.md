# 最近通话

入口保留 `../recent_calls_page.dart` export。页面参考实际的
`reference-99chat/lib/src/pages/recent_calls_page.dart`，复用 settings 的主题、
头像、空状态、动作表、确认弹窗和现有通话入口，支持亮色、暗色和大文字。

`data/` 管理 Chat 通话记录接口、账号仓库和 OpenIM 业务通知绑定。
HTTP 使用当前 `Config.appAuthUrl` 和登录返回的 `chatToken`，调用
`GET /chat/call-records?syncAt=...&limit=200` 与 `POST /chat/call-records`。
通话本身继续走现有 OpenIM 信令和 RTC；聊天记录与通话记录各自保存。

通话 `roomID` 对应服务端 `callID`，双方共享邀请里的编号。通话终态先持久保存，
发起方再后台上报；接收方保存本地记录，通过服务端镜像及通知补齐权威记录。
网络失败的上报保留在本账号缓存，打开页面、重连或恢复前台时重试。
不使用 IM token 调用通话记录 HTTP，也不在请求中传入所属用户。

分页根据条数及服务端 `syncAt` 推进，满页继续直到不足 limit；同毫秒超额记录
全部接收，不能截断。记录和游标一起持久化，通知不推进拉取游标。
服务端 `updatedAt` 决定同一 callID 的新旧，旧分页/通知不能覆盖较新记录。
异步请求、账号切换、写入和重拨都校验原账号及会话。

持久层复用已有 CacheController 的 Hive `callRecords` box，按 IM userID 分区；
保留旧记录和 typeId=4、字段 1–10，新增群信息、始末及更新时间使用 11–15。
没有 roomID 的旧记录继续按对方、时间、媒体类型和方向识别。

列表显示昵称/头像、音视频、呼入/拨出、终态、时长及手机本地时间，
未接筛选仅展示呼入未接。重拨调用已有 `onStartCall(userID, video)`。
服务端群通话记录可同步并显示群资料；当前 RTC 入口只支持单聊，群记录不提供单人重拨。

接口没有删除端点。编辑操作因此标为“隐藏”，确认文案说明仅影响本设备。
隐藏标记随账号持久保存，后续通知和拉取不会让已隐藏记录重新出现，
期间新来的记录也不会被一次批量隐藏误伤。

测试位于 `test/pages/mine/calls/` 与 `test/pages/chat/calling/`。
验证使用模拟接口及 SDK 回调，不执行真实呼叫。

`call_surface_test.dart` 验证实际 ControlsView 和 CallCompactSurface 的
320px、2 倍字号、亮暗主题，以及连接中重复接听禁用、结束后全部控件禁用，
实际 SignalState 在取消后忽略迟到的权限和凭证。服务端 canonical
`rejected` / `cancelled` 标签根据呼入、拨出角色显示。

`docs/previews/call-light.png` 和 `call-dark.png` 是实际 ControlsView 的
测试夹具截图，采用本机中文字体、320×640 逻辑尺寸、2 倍字号和安全区；
联系人为测试数据，未建立真实音视频通话。只有显式开启
`--dart-define=CALL_SURFACE_PREVIEW=true` 时测试才加载本机字体和写入预览，
普通回归不依赖 Windows 字体文件。
