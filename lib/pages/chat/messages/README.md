# 消息发送与操作

`ChatDeliveryController` 持有发送状态流，协调已有 `ChatMessageSender`、当前会话的消息窗口、输入重置及失败提示。关闭与账号变化后停止提交操作，并拒绝迟到结果修改页面。测试可注入真实发送接口的替代实现。

`ChatMessageActions` 管理转发/撤回菜单策略、SDK 撤回删除以及成功后的本地失效通知。`forwarding/` 管理单条/批量/合并转发和联系人名片；`selection/` 管理当前聊天的多选、全选和操作栏；`presentation/` 管理通知/失败提示气泡策略；`widgets/` 管理聊天消息行、菜单和内容展示。

资金卡片仍由资金模块及后端创建，不能通过 IM 撤回、普通转发或重发制造订单状态变化。收藏发送状态契约仍复用已有共享服务，后续整理收藏模块时处理其历史依赖关系。

测试：`test/pages/chat/messages/`；跨模块入口验证：`test/integration/chat/`。
