# UI 交互设备验证

`ux_device_smoke_test.dart` 启动真实应用，使用已有登录、SDK 和缓存。
验证底部切换、亮暗主题、反馈键盘和返回保护。只填写并放弃测试文字，不提交反馈、发消息或交易。
主题在 finally 中恢复；账号为空时明确失败，不伪造登录或跳过后报告通过。

`ux_driver.dart` 把截图、profile 帧耗时和完整性标记保存到环境变量
`UX_AUDIT_OUTPUT` 指定的本地目录。使用引擎 FrameTiming 回调采样 build/raster，
不依赖设备内的 VM timeline 连接；必须使用 `--no-dds --keep-app-running` 启动，
避免 flutter drive 默认清理时卸载测试包。登录页最多等待五分钟，供用户自行登录。
`UX_DEVICE_SERIAL` 必须明确指定 Android 设备。驱动监听固定的实时输入准备标记，
再通过 adb 实际输入 `UX draft keep`，避免 profile 模式的模拟输入与系统 IME 冲突。
截图回调只保存图片，Android 会在测试结束后批量交付截图。
测试使用 fullyLive 帧策略，让路由和图标按实际引擎帧连续渲染。
驱动临时开启硬件键盘连接时的系统软键盘显示，结束后恢复原设置。
模拟器测量不替代真机帧率、输入延迟或耗电基准。
