# 代理群绑定入口

`RobotGroupBindingController` 由当前聊天的 `MarkSixFeatureHost` 创建和释放，仅用于 `gameType=2`。进群读取当前 App 群绑定，前台恢复校准，没有定时轮询、持久化绑定缓存或独立认证客户端。

- API：`GET /me/robot/groups/{Uri.encodeComponent(groupID)}`；通过 `GroupFeatureApi` 自动附 Chat token 和 operationID，群 ID 在路径中，不附代理业务的群头。
- DTO：成功外壳解包后读取 `groupId`、boolean `bound/enabled`、可空字符串 `machineCodeMasked`。错群、错误状态和非法 DTO 不生成绑定。
- `bound` 只控制代理浮动入口，`enabled` 不控制此入口；个人业务权限由原能力接口和服务端检查。
- 读取合并同一 pending；能力更新不重新读取。群／账号／API／类型变化释放旧控制器。后台和 dispose 取消请求，旧响应忽略。
- 遮蔽机器码保留在模型，不传入开奖请求或权限摘要。

回归测试：`test/pages/group_features/mark_six/agent/binding`，以及原开奖入口和代理页面测试。
