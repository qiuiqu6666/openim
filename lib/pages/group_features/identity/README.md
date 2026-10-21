# 群名称样式

GroupNameLabel 只使用 GroupInfo.ex.groupPersonalization 中群主保存的颜色和图标。游戏类型不再影响名称颜色；未设置或恢复默认时使用调用方主题文字样式。

列表使用账号隔离的 GroupFeatureStore 缓存并监听群资料更新；已有 GroupInfo 的页面直接传入 ex。所有群成员共享同一份群资料，与观看者角色无关。聊天标题通过 TitleBar.chat.titleWidget 复用同一组件，单聊与成员昵称不受影响。渲染名称不发起额外请求。
