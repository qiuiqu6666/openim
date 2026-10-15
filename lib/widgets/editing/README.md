# 编辑页面返回保护

`UnsavedChangesGuard` 统一保护未提交编辑和正在执行的提交。
复用公共 `showAppAlert` / `showAppConfirm`，没有新增弹窗样式或持久化协议。
顶部返回使用 `Navigator.maybePop`，系统返回遵循 `PopScope`；受保护期间
自定义侧滑遵循路由 popDisposition。业务确认保存成功后仍可由页面直接 pop 返回结果。

此组件不保存草稿，不缓存账号数据，也不代替页面自己的请求去重和生命周期保护。
