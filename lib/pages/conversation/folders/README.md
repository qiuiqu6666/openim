# 消息分组

样式与入口对照 `reference-99chat` 的 `d7c3c65`：
`lib/src/conversation.dart` 中分组创建、重命名、删除、选择流程，以及
`lib/src/widgets/conversation_feed/conversation_folder_chip_bar.dart` 与
`conversation_folder_swipe_region.dart`。

`ConversationFolderBar` 负责胶囊栏、未读徽标、平台阴影和拖动动画，
`FolderNameDialog` 负责 Cupertino 名称输入，`ConversationFolderController`
负责页面的选择、弹窗和排序预览。原有名称弹窗路径只导出兼容，不保留第二套实现。
菜单与删除确认复用已有 `showSettingsActionSheet` / `showSettingsConfirm`，
共享菜单仅增加副标题能力。

列表区域沿用参考的大幅横滑切换分组，不循环；短滑仍可操作会话侧滑菜单，
纵向滑动仍滚动列表。会话编辑、分组排序与提交期间禁用横滑切组。

没有分组时隐藏胶囊栏，首个分组从会话右滑“分组”或长按预览的“添加至分组”进入，
选择“新建分组”后创建并加入该会话。栏右侧＋创建空组并选中。名称上限16字符，
去首尾空白后提交；本地忽略大小写检查重名，最终仍由服务端校验。分组长按菜单
包含重命名、删除、重新排序，删除始终确认并说明不会删除聊天记录。

所有数据来自 OpenIM SDK 会话与现有 ChatOrganizerApi。选中分组显示该组的
单聊、群聊，排除已归档；未选择分组时按首页当前单聊/群聊标签显示。
未读数统计相同范围，静音会话使用灰色徽标。加入分组写入 `archived:false`，
当前分组内右滑“移出分组”写入 `folderID:null`。归档继续保留已有 folderID
契约，避免改变归档页取消归档后的恢复行为。

排序拖动只在页面内预览，点击勾或退出排序后通过现有
`PATCH /chat/folders/:id` 的 `sortOrder` 字段保存。创建、重命名、删除、排序
由 ConversationLogic 检查当前账号及 token，回包使用服务端对象与版本；
排序部分失败后重新同步服务端顺序，不假装全部成功。
后端字段依据公开 [会话归档和分组文档](http://8.217.191.236:10018/client/conversation-folder.md)。

页面销毁时释放该页的选择、排序、动画和弹窗流程状态，不注销共享会话控制器，
不另建 SDK 监听或本地分组存储。亮暗主题使用 Theme/ColorScheme，尺寸与参考
一致使用逻辑像素；iOS 浅色保留原阴影，Android 和深色无阴影。

会话行通过共享 `ConversationSlideScope` 持有自己的滑动控制器；父页仅登记当前
挂载的控制器用于关闭面板。过滤或列表位置变化后不复用旧行控制器，避免当前
flutter_slidable 3.1.2 在旧通知监听上调用已销毁的上下文。该改动保留原侧滑操作。

测试位于 `test/pages/conversation/folders/` 与
`test/pages/conversation/conversation_folder_bar_test.dart`；名称弹窗兼容测试在
`test/folder_name_dialog_test.dart`。测试数据只在测试中替换 API 和 SDK。

本轮验证：会话模块、名称弹窗及侧滑回归合计130项通过；分组相关生产文件与
测试静态检查通过，debug 资源构建通过。真实页面的亮暗预览在
`docs/previews/folders-light.png`、`folders-dark.png`，预览数据仅来自测试 fixture。
未执行真机与在线账号联调。
