# 单聊与群聊投诉

入口：聊天设置的投诉项与群资料的投诉项。`ComplaintReasonPage` 提供七类原因，表单复用设置模块的 `FeedbackPage`，通过 `FeedbackSubmission` 注入目标、原因和提交回调；未复制表单、图片选择器、预览和成功页。原有大表单仅新增可选配置，投诉协议与会话校验独立放在本目录，不向表单加入网络职责。

参考 `reference-99chat/lib/src/pages/complaint/complaint_reason_page.dart`、`complaint_form_page.dart`、`complaint_form_view.dart` 和 `pages/settings/feedback_form_view.dart` 的原因列表、目标信息、原因标签、可选说明、五张截图和提交结果；复用当前项目亮暗主题和客服入口。

`ComplaintApi` 使用现有 Chat 地址、chatToken 与 operationID，提交 `/complaints/c2c` 或 `/complaints/group`。服务端实现及上线信息见 `server/complaints/README.md`。

群资料入口投诉整个群，由服务端校验当前群成员身份并绑定实际群主；客户端不加载完整成员名单。单聊拒绝投诉自己。每次表单实例持有提交状态，重复点击被锁定；失败保留说明、截图和同一请求 ID，修改后产生新 ID。发起请求前和收到响应后均校验账号与 token，防止账号切换后使用旧会话提交或显示成功。

测试：`test/pages/chat/complaints/` 覆盖请求协议、账号切换、错误成功响应、可选说明、重复点击、亮暗主题、大字体和原意见反馈必填行为。Android 调试构建已通过；iOS 真机相册权限、键盘及手势返回仍需设备验收。
