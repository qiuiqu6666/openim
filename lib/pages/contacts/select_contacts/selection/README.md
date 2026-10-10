# 选择策略与单选返回

`ContactSelectionPolicy` 继续定义转发、名片、建群与邀请的官方账号限制。

`ContactSingleSelection` 是现有群选择页和通讯录选择页的生命周期适配入口，没有单独的列表 UI。调用方提供标题、选择类型、有效范围和范围变更通知；控制器由该路由持有，退出时释放，不注册或覆盖 Get 中已有的选择器。数据继续使用现有 `SelectContactsFromGroupLogic` / `FriendListLogic`。

`SelectContactsLogic.single` 点击后直接返回 SDK 对象，不显示发送确认、不发消息。此模式可用于选择机器人，允许通讯录里的机器人账号；原有转发、名片和群成员选择策略不变。返回 SDK 原始 ID，名称仅用于展示。
