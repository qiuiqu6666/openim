# 消息导航

`ChatMessageNavigation` 通过现有导航入口处理用户资料、联系人名片、链接和提及 ID 查找。会话提供只读群资料与权限、关闭状态；本模块不持有消息列表或发送队列。

普通文字中的 `@公开账号名` 通过当前业务服务的用户搜索接口解析，使用公共账号规范化规则精确匹配返回的 `account`，再用真实 `userID` 打开资料。带或不带 `@` 的账号均可匹配；缺少真实用户 ID、昵称相同或账号仅部分相同的结果不作为目标。原有内部用户 ID、群 ID 的精确匹配和群资料优先级继续保留。

`ChatMessageFocusController` 拥有搜索定位后的短暂高亮和取消世代；`ChatMessageFocusTokens` 集中定义时长与透明度。真正定位复用 `history/date_jump/ChatDateWindowController` 与公共 viewport，加载已存在目标时直接定位，否则安装 SDK 目标前后的有界连续窗口。手指拖动、清空和关闭取消高亮；旧定位、账号切换及消息过期不能恢复高亮。

搜索入口的账号、精确 SDK 记录和路由身份验证属于 `history_search/navigation/`。`ChatLogic` 仅提供当前账号/会话有效性、实际聊天路由绑定和定位的兼容接口，原控制器的生命周期与草稿订阅继续由它持有。独立高亮状态和计时器留在本模块，避免继续扩大主控制器职责。

测试：`test/pages/chat/navigation/`，提及 ID 解析测试位于 `test/pages/chat/composer/`。

引用定位按实际布局距离分档：一屏内 220ms、三屏内 300ms，使用 easeOutCubic。未布局的相邻消息最多测量三屏缓存；仍在范围外的目标直接切换稳定 sliver 中心，再执行约 200ms、至多 0.28 屏的短程移动，不按固定消息高度推算偏移。目标默认位于可用列表高度的中间偏上位置；最新/最旧边界不足以居中时保持可见。定位完成后只在目标气泡覆盖淡色高亮，保持 600ms，再以 250ms 淡出，动画不重建媒体子树。

回到底部复用 `ChatLatestScrollController` 和 `ChatListPositionController.returnToLatest`：一屏内 220ms，三屏内 300ms，远距离按最新消息身份重置中心，随后短程滚动。更换 SDK 历史窗口前请求最新布局及短程入口，在第一次绘制前完成锚点切换，不淡出成空白页。消息同步、补洞、读回执与草稿所有权不变。自动返回期间保留新消息按钮状态，实际到达最新边界才清除计数；手动滚动取消入口查询、定位和自动返回世代。

距离验收位于 `chat_viewport_seek_test.dart` 和 `chat_date_window_controller_test.dart`：覆盖 1、10、50、500、5000 条动态高度消息，断言定位可见、远距离构建有界、目标两侧读取及恢复最新窗口次数固定。普通和 reverse 滚动的最新边界、取消、动态布局、减少动画与高亮子树复用由 scrolling/navigation 测试覆盖。测试数据是内存夹具，不代表真机帧率或热量测量。
