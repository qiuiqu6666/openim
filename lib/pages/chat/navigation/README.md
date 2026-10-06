# 消息导航

`ChatMessageNavigation` 通过现有导航入口处理用户资料、联系人名片、链接和提及 ID 查找。会话提供只读群资料与权限、关闭状态；本模块不持有消息列表或发送队列。

普通文字中的 `@公开账号名` 通过当前业务服务的用户搜索接口解析，使用公共账号规范化规则精确匹配返回的 `account`，再用真实 `userID` 打开资料。带或不带 `@` 的账号均可匹配；缺少真实用户 ID、昵称相同或账号仅部分相同的结果不作为目标。原有内部用户 ID、群 ID 的精确匹配和群资料优先级继续保留。

`ChatMessageFocusController` 拥有搜索定位后的短暂高亮和取消世代；`ChatMessageFocusTokens` 集中定义时长与透明度。真正定位复用 `history/date_jump/ChatDateWindowController` 与公共 viewport，加载已存在目标时直接定位，否则安装 SDK 目标前后的有界连续窗口。手指拖动、清空和关闭取消高亮；旧定位、账号切换及消息过期不能恢复高亮。

搜索入口的账号、精确 SDK 记录和路由身份验证属于 `history_search/navigation/`。`ChatLogic` 仅提供当前账号/会话有效性、实际聊天路由绑定和定位的兼容接口，原控制器的生命周期与草稿订阅继续由它持有。独立高亮状态和计时器留在本模块，避免继续扩大主控制器职责。

测试：`test/pages/chat/navigation/`，提及 ID 解析测试位于 `test/pages/chat/composer/`。
