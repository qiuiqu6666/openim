# 后台意见反馈用户昵称

列表正文补充：Admin API 按当前页反馈 ID 一次查询 `feedback` 集合，仅取 ID 与 content，附加 `content` 字段；详情保留原正文。列表新增「反馈正文」列，按原换行显示并最多展示三行，点击行可在详情阅读全文。已使用已有反馈记录验证返回正文及身份与数据库一致，并通过 Admin API race 测试、后台及二进制构建。此次备份与上线记录位于 `/home/ubuntu/feedback-content-20261015/`。

2026-10-15：后台反馈列表和详情同时展示用户昵称及现有公开 ID。Admin API 在原反馈响应中增加 `userNickname`，通过投诉模块既有批量资料查询回调补齐当前名称，优先使用 OpenIM 用户资料，保留业务库回退。原反馈存储、筛选、公开 ID 转换、截图、SDK 日志及处理状态不变，历史反馈无需迁移。

`internal/api/admin/feedback_identity.go` 负责附加展示字段，现有反馈处理器仅在列表及详情响应时调用；`web/admin/src/views/Feedback.vue` 以两行显示昵称与公开 ID。测试覆盖列表、详情原字段及空列表不查询目录，Admin API race 测试、后台前端构建和二进制构建通过。

服务器工作、部署与备份记录：`/home/ubuntu/feedback-names-20261015/`。此次仅更新 Admin API，部署前校验源代码漂移，失败自动恢复。客户端无需重新安装。
