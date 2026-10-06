# 创建群聊

界面参考本地 99chat revision `d7c3c65` 的
`lib/src/create_group.dart` 移动确认页。按用户要求只展示群头像、群名称、
群成员和规范提示，不展示群类型、容量、配额或费用。

- `create_group_view.dart`：页面布局、顶栏创建动作及提交期间的交互状态。
- `create_group_logic.dart` / `create_group_binding.dart`：保留现有 OpenIM
  SDK 创建、联系人选择、图片上传、默认群名和聊天跳转。
- `create_group_tokens.dart` / `create_group_strings.dart`：参考尺寸、亮暗主题
  颜色及页面本地化文案。
- `widgets/create_group_members.dart`：全部已选成员、两个添加成员入口及
  规范提示，使用 Wrap 适配窄屏和大字号。
- `assets/`：参考仓库的默认群头像，出处见根目录第三方资源说明。

规范提示复用设置模块公开的 `LegalDocumentPage(terms)`，与参考页的
服务条款跳转一致。名称、头像和成员由原控制器持有，往返规范页和成员
选择器时不重置。类型仍由原 SDK 创建流程使用 `GroupType.work`。

创建群聊和添加群成员共用联系人选择策略，隐藏 AI助理及其他官方账号。
识别依据稳定用户 ID（包含 `assistant`、`99Message`、`99Pay`）和 SDK
用户资料中的 `accountType == official`，普通好友即使昵称为「AI助理」
仍可选择。创建确认页初始化、成员选择返回及创建提交时也过滤成员集合，
避免原始默认预选或旧选中状态重新带回官方账号；其他好友数据保持来自
现有 OpenIM SDK。

行为和布局回归测试位于 `test/pages/contacts/create_group/`；实际页面的
字体及亮暗主题预览入口为 `artifacts/create_group_reference_preview.dart`。
`create_group_member_filter_test.dart` 使用真实控制器与路由参数，覆盖
默认预选、已选成员及提交前重新加入官方账号的清理，并保留普通同名好友。
