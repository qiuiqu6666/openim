# 申请角标刷新

`HomeLogic` 保留好友、群申请的 SDK 查询、已读/隐藏过滤与计数发布；`ApplicationBadgeRefresh` 只管理刷新调度。

- 连续事件在 80ms 窗口合并，持续事件不会无限推迟首个请求。
- 进行中的读取复用 `RequestLoadCoordinator`，后来的事件最多排一个补刷，不并发查询同类申请。
- 页面关闭取消定时器和补刷；账号或令牌变更不再查询、不发布旧结果。读取失败保留已有角标，下一次事件可重试。
- 不改变 SDK 申请和审批流程，不截断计数数据，不以首屏的 20 条代替总未读数。

回归：`test/pages/home/application_badges/`，包括真实 HomeLogic 事件入口与 SDK 通道计数。
