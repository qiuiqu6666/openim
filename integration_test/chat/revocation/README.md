# 图片撤回真机回归

发送阶段调用相册的真实 `ChatMediaOutbox`、`ChatMediaUpload` 和 SDK 链路，用应用内置图片省去系统选图器操作；不能改成 `sendPicture` 直接发送，否则不会经过引发本次闪现的成功发送队列恢复路径。

入口运行完整 App、真实登录态、OpenIM SDK、上传、撤回和生产路由，不替换 MethodChannel 或消息数据。必须通过 `RECALL_TEST_CONVERSATION` 指定用户授权的精确会话显示名；同名多条、找不到会话或登录超时都会失败，不自动选取其他联系人。测试发送两张应用内置 logo 并撤回，不操作已有消息。

覆盖成功后返回，以及点击撤回确认后立即返回；分别再进入五次。后者记录真实回包和路由关闭的先后顺序，不将快速成功误报为覆盖了在途请求。逐帧检查消息列表和挂载的 `ChatMessageTile`，并断言撤回前原图确实挂载、再进入后撤回提示确实挂载。原生历史查询必须确认消息已撤回。JSON 报告仅保存计数、阶段和布尔值，不保存正文、令牌、联系人或消息标识。另在报告同目录保存撤回前及首次重新进入的设备截图，截图含实际可见聊天界面，仅用于本地验收。截图是采样证据，不是逐帧屏幕录像。

```sh
RECALL_TEST_OUTPUT=/tmp/picture-recall-result.json flutter drive \
  --no-pub --keep-app-running \
  --driver=integration_test/chat/revocation/picture_recall_driver.dart \
  --target=integration_test/chat/revocation/picture_recall_device_test.dart \
  --dart-define=RECALL_TEST_CONVERSATION='<用户授权的会话显示名>' \
  -d '<真机设备ID>'
```

必须保留 `--keep-app-running`，避免驱动退出时卸载应用。新调试包 ID 没有既有登录态时，需要用户在设备登录；不复制其他应用容器的凭据。测试后用正常 `lib/main.dart` 构建恢复同一调试包，不卸载、不清数据。真实设备运行的结论以报告 `completed: true` 且两组结果完整为准；编译或主机测试通过不能作为真机通过的证据。
