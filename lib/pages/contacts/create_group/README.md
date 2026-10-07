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

群名称留空或仅包含空白时，按当前成员顺序取前两位昵称，以「、」连接；
两人群例如「秋的测试号、秋啊」，超过两人例如「秋的测试号、秋啊等4人」。
人数包含创建者，成员增删后按最新列表生成；昵称缺失时沿用成员卡片的
用户 ID 兜底。手动输入的非空群名优先使用。这是用户指定的默认命名行为，
不同于参考 99chat 页面要求群名称必填的校验，仍复用原 OpenIM 创建流程。

群名称输入框为空时，以上述自动名称作为 Placeholder；成员增删后即时更新
占位文字。已输入的群名作为可编辑正文保留，支持追加和中间修改。占位文字
不计入 30 字限制，提交时仍按原控制器选择手动群名或自动群名。
有文字时显示「×」按钮，一键清空后恢复自动群名占位文字；创建期间禁用清空。

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
同时覆盖默认群名、手动群名、空白输入、成员增删和缺失昵称。
