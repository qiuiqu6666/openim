# 群名颜色的本地恢复

`GroupNameCache` 复用 Hive，保存账号、群 ID 对应的公开 `GroupGameType`。
`main` 在 `Config.init` 完成后、`runApp` 之前打开数据库，因此
`GroupFeatureStore.gameType` 可以同步读取首屏颜色，不必等待 SDK。

缓存仅用于群名显示，不恢复群成员身份、功能配置或权限。颜色仍由
`GroupNameLabel` 的现有亮暗主题 token 决定。

- `seed` 收到 SDK 元数据时写入类型，包括恢复普通群时的类型。
- `hydrate` 不因存在磁盘缓存而跳过 SDK 刷新。
- 离线读取失败保留上次颜色，成功刷新后使用最新类型。
- 退群删除对应记录；会话销毁仅清理内存，磁盘按账号隔离保留。
- 数据库不可用时沿用 SDK 加载流程。

首次安装或升级到本实现后，需要先成功获取一次群元数据，后续冷启动
才能恢复该群颜色。

回归测试：`test/pages/group_features/group_name_cache_test.dart`。
