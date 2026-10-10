# 群名称样式

`GroupNameLabel` 只根据现有 `GroupInfo.ex.gameType` 标记公开群名称：1（三公游戏）和 3（六合彩开奖）使用红色；普通群、代理群及非法／未知类型保留调用方样式。浅色复用 `AppTokens.danger`，深色复用现有较亮红色 `AppTokens.paymentErrorDark`。

列表通过账号隔离的 `GroupFeatureStore.gameType` 读取已解析缓存，并监听 SDK 群资料更新；已有 `GroupInfo` 的页面可直接传入 `ex`。组件 build 不查询 SDK、不读取业务权限、不发网络请求。聊天标题通过通用 `TitleBar.chat.titleColor` 参数复用同一规则。单聊、公众号认证标记、群成员昵称和消息文字不受影响。

全局搜索将既有群搜索结果写入同一缓存，供群会话名称复用；不为着色额外加载全部搜索结果的群资料。资料尚未到达时先使用原色。

参考 99chat `conversation_group_title_color.dart` 的共享群名着色方式；具体类型条件采用本次产品要求，不套用参考仓库的 Community 类型或火焰图标。
