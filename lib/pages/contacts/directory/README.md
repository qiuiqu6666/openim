# 通讯录名字索引

`contact_directory_indexer.dart` 只处理显示名称、拼音、A–Z/# 分组和分组首行。真实好友、备注、头像及 SDK 订阅由 `ContactsLogic` 持有，后台 worker 不接触 GetX 列表或 SDK 模型。

- 默认通过 Flutter `compute` 在后台 isolate 转换拼音及排序，复用原 `SuspensionUtil` 的排序与分组标题逻辑，包括同首字母的原有排序行为。
- 以用户 ID 和当前显示名称复用拼音；备注/昵称改变后重新计算，删除后的索引释放。
- `ContactsLogic` 合并好友增删改，80 ms 批次只发布本地目录；初始化、同步结束和显式刷新仍从 OpenIM SDK 分页读取，保留 `filterBlack: true`。
- 索引任务串行合并；查询期间的增删改覆盖旧查询，关闭或账号/登录凭证变化后不发布结果。控制器关闭时释放名字缓存。

测试位于 `test/pages/contacts/directory/` 和 `test/pages/contacts/contacts_logic_test.dart`，全局事件流程保留在 `test/global_performance_regression_test.dart`。
