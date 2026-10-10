# OpenIM 原生 SQLite 临时目录

`OpenIMApplication` 通过主 manifest 注册，在 `attachBaseContext` 中、Flutter 插件及 SDK 初始化前，将 `SQLITE_TMPDIR` 设置为应用私有 `getCacheDir()`。直接使用缓存根目录，避免额外子目录被清理后环境变量指向不存在的位置；SQLite 排序临时文件由 SQLite 自行释放。

OpenIM 内嵌的 SQLite 不复用 Android framework SQLite 的临时目录配置。会话数量大、分页排序需要落盘时，未配置的 Unix VFS 会依次尝试 `/var/tmp`、`/usr/tmp`、`/tmp` 和当前工作目录。Android 应用工作目录通常为只读 `/`，因此读取会话列表会报 `10005 / disk I/O error: read-only file system`。这不是空列表，也不能通过清空消息数据库解决。

2026-10-11 在当前 Android 模拟器确认：数据库完整性检查通过，3351 条可见会话；SDK `GetConversationListSplit(0,400)` 失败，文件访问跟踪显示临时目录不存在，最终访问 `.` 返回 `EROFS`。这里只配置进程启动环境，不改变 SDK 数据目录、数据库内容、账号或会话排序规则。

验收需要重新编译并启动 Android 应用进程，单独 Flutter hot restart 无法执行新的 Application 初始化。使用含大量会话的原数据库验证冷启动、下拉刷新、热重启以及所有分页；同时运行会话及登录恢复测试。环境设置失败会输出 `OpenIMStorage` 错误，不清数据或阻断应用启动。

原理依据：[SQLite 临时文件及目录搜索顺序](https://www.sqlite.org/tempfiles.html#temporary_file_storage_locations)。
