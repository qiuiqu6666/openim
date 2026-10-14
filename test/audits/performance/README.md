# 性能热点审计

`runtime_hotspots_audit_test.dart` 包含隐藏页面的回归断言及耗时观测；耗时不是 CI 通过门槛。

- 验证 `Offstage` 且 `TickerMode` 禁用时，开奖卡片没有周期计时或重建。
- 使用现有客服测试替身，分别加载及重复刷新 100、1,000、5,000 条历史，输出真实控制器合并逻辑的耗时。
- 测量来自桌面 Flutter 测试进程，包含运行时/JIT影响，不能代替手机 profile 模式、真实网络及帧时间测量。
- 隐藏刷新已改为零工作断言；客服不变历史使用重新构造的消息对象模拟网络解码，避免只测对象引用命中。

运行：`flutter test --no-pub test/audits/performance/runtime_hotspots_audit_test.dart --reporter expanded`

2026-10-14 的日志及检查报告位于工作区外层 `artifacts/performance-audit-20261014/`。
