# 会话变化合并

`ConversationUpdateBuffer` 只合并 SDK 会话元数据；每个会话 ID 保留窗口内的最后一次变化。实时窗口为 16ms，同步窗口为 80ms，固定时间发布，持续有消息也不会无限等待。消息正文的 SDK 接收、存储不经过这个缓冲。

读取会话分页时，入口立即记下变化以保护查询期间的新状态；同步结束主动发布，删除、清空和关闭时清理对应缓冲。置顶、免打扰写入完成前先应用积累的 SDK 快照，避免旧缓冲撤销用户操作。未读仍由 `ConversationReadProjection` 校准。

列表单次排序仍随总会话数增长；本模块降低重复次数，不承诺任意吞吐量。会话页一次遍历生成分组计数，隐藏的主页标签保留已构建子树和滚动位置，切回时重新读取当前数据。

测试：`test/pages/conversation/updates/`、会话恢复生命周期、删除屏障、已读投影与分组页面回归。

初次本地快照为空或读取失败时，普通登录的同步完成也必须重新读取 SDK 列表，不能仅在 `reInstall=true` 时读取。连续重复的同步完成回调不重复扫描；新的同步周期仍刷新。重连成功、回到前台时只对失败且没有正在读取的列表重试，继续遵守账号、token 和请求代次隔离。失败保留已显示会话，加载期间的实时变化仍合并到最新快照。产品行为参考 99Chat `conversation_sync_service.dart` 的同步结束恢复与重复结束事件抑制，保留本项目 OpenIM/GetX 数据链路。

`test/pages/conversation/conversation_startup_recovery_test.dart` 覆盖普通同步恢复、结束事件先于页面构建、旧首屏响应、实时增量、重复结束、重连/前台重试及账号切换。Android 大列表的 `read-only file system` 则由原生 `io/openim/storage/OpenIMApplication` 的 SQLite 临时目录配置修复；客户端重试本身不能修复错误的文件路径。
