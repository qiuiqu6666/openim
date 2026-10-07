# 好友备注编辑

`SetFriendRemarkLogic` 从当前资料页的真实用户资料初始化原备注。已有备注显示为可编辑正文，可在末尾追加或从中间修改；没有备注时正文为空，以原昵称作为 Placeholder，占位文字不计入字符数量。未修改直接返回，不会把占位昵称写为备注。

`SetFriendRemarkPage.editor` 是已有共享编辑器，个人昵称、群名称、群昵称继续复用其头像、输入框和确定入口，以及现有亮暗主题。`widgets/name_editor_input.dart` 集中维护原有输入框，提供可选的 `hintText` 和 `showClearButton`；草稿控制器仍由各业务管理。备注及群昵称未设置时传入原昵称作为占位文字，有文字时显示「×」按钮，点击只清空草稿、恢复占位文字，确定后才保存；保存期间禁用清空。个人昵称编辑保持原行为。本地 99chat 的 `lib/src/pages/profile_nickname_edit_page.dart` 作为编辑与清空图标参考；空值占位、已有值直接编辑按用户要求实现，数据和保存仍使用 OpenIM。

修改或清空已有备注仍通过 SDK `updateFriends` 保存，失败保留草稿。该方法与 SDK 旧 `setFriendRemark` 的实际底层调用相同。页面关闭后的异步结果不再操作路由。

真实控制器及 SDK 通道回归位于 `test/pages/contacts/user_profile_panel/set_remark/`；共享编辑器、个人昵称入口和群昵称回归仍位于各自既有测试文件。
