# 聊天外观状态

`ChatAppearanceController` 拥有聊天页的字体比例和当前背景。页面在会话参数就绪后调用 `initialize()`，从设置页返回时调用 `reload()`，退出时调用 `close()`；页面只读取模块的 `scaleFactor` 和 `background`。

字体仍从公共 `DataSp` 获取。背景解析和失效文件清理复用设置模块公开的 `ChatBackgroundLocalService`，保留会话背景 → 全局背景 → 默认背景的顺序。模块不拥有持久化实现，不移动共享服务。

背景文件检查保持异步。关闭、会话变化或更新的 reload 会使先前查询结果失效；如果设置在文件检查期间替换了背景，重新解析当前值，避免根据过期值清理新设置。模块不改变聊天 UI。
