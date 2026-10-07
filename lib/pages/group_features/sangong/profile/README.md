# 三公资料页管理与流水

资料页通过 `SangongProfileSurface` 接入，原有好友、群成员、身份隐私和添加好友流程保持由联系人模块管理。三公模块不从公开聊天号推算身份，所有用户操作使用当前资料的原始 IM userID；游戏内部数字编号仅来自已确认的运营用户报告。

## 页面与权限

- 打开详细资料刷新当前登录账号完整资料；严格 `isPrivileged == true` 且目标不是自己时显示管理区，普通资料重建不重复刷新。不要求目标用户也是特权账号，也不依赖共同群聊数量。
- 手机位置与 99chat `user_profile.dart` 一致：身份资料后、通话／发消息按钮前。按用户要求去掉参考中的外层大卡片，只保留 `UserProfileGameAdminPanel` 的三块独立紧凑卡片：积分、庄门／限额、合庄占股与庄池摘要；字号、颜色、输入框、文字链接、分隔线与卡片尺寸见独立视觉 token。没有额外“三公服务”标题、下拉框或胶囊按钮网格。
- 无加入的群、当前租户或聚合权限读取失败时，保留三块表单并在上方显示原因／重试。尚未确认业务权限时，输入与动作禁用，缺失的业务数据显示“—”；当前游戏群缺少旧 `groupFeatures` 摘要本身不代表无运营权限。
- 积分上分／下分、定庄／展示限额、合庄／取消合庄和两类通知调用既有真实 API；使用输入框当前值，确认后提交。失败或未知结果不自动重发；重试只读取最新状态。分组、可负额度等其他功能沿用已有游戏用户详情与管理页面。
- 手机流水采用 99chat 的58像素圆形“流”浮窗：可拖动、左右吸边、按当前登录账号与API地址隔离保存位置。已验证特权账号点击时始终打开窗口；无群、未绑定或业务权限失败时，公开窗口显示原因及重试／选群，关闭窗口后再读取最新权限。业务授权后复用既有真实流水详情。两种窗口均刷新账号特权并受撤权守卫保护，高度为屏幕82%，未授权窗口不请求私人流水。
- 可用宽度达到900时，使用 99chat 的360宽右栏与56高“游戏管理”标题，下面为紧凑表单和有界流水；低高度窗口允许右栏滚动，避免内容溢出。
- 群成员资料只确认当前群；单聊资料从当前登录账号已加入的群中准备。单群自动准备，多个群通过独立选择窗口明确选择，不跨群复用租户；成功选中单群时不额外显示群选择栏。选择时刷新群能力再校验绑定，失败显示具体原因。
- 私人数据及写操作沿用共享 GroupFeatureStore。需要当前群租户查询的 `gameType=1` 运营分支，要求当前账号特权、定点查询确认租户 `active:true`、聚合 `canManage` 与真实逻辑绑定租户，无需 `ex.groupFeatures` 或旧公开 enabled/manageEntry。`gameType` 仅描述类型，租户 active 仅判断配置存在且启用，运营权来自当前聚合能力；公共群信息、OpenIM群主身份、对方昵称及特权字段均不单独构成业务授权。普通／legacy 运营仍保留公开 enabled/manageEntry，代理／个人报表继续沿用原 enabled、agentEntry、canOpenAgent 及私人历史条件。
- 权限变化更新资料运行实例；已覆盖的流水与操作确认窗口也监听实例。撤权或销毁立即隐藏私人内容、清空输入；晚到请求不能重新展示。

实际视觉来源：`E:/openim/reference-99chat/lib/src/widgets/user_profile/user_profile_game_admin_panel.dart`、`user_profile_game_ledger_floating_entry.dart`、`user_profile_game_privilege_side_column.dart`，以及 `lib/src/user_profile.dart` 的手机外卡与插入顺序（d7c3c65）。数据源和权限判断继续使用 OpenIM 与本模块接口。

## 文件归属

| 文件 | 职责 |
| --- | --- |
| sangong_profile_surface.dart | 群选择、共享能力读取、运行实例和响应式布局 |
| sangong_profile_entry_scope.dart | 已验证账号的公开服务发现状态，不携带私人报告或推断权限 |
| sangong_profile_panel.dart | 公开准备态、无额外底色的手机布局与独立群选择窗口 |
| sangong_profile_admin_panel.dart | 授权后的真实用户报告、局状态、输入与操作确认 |
| sangong_profile_admin_layout.dart / sangong_profile_admin_tokens.dart | 99chat三块独立紧凑卡片的共享视觉布局与尺寸 |
| sangong_profile_ledger_floating_entry.dart / sangong_profile_ledger_tokens.dart | 圆形流水入口、拖动吸边与账号隔离位置 |
| sangong_profile_ledger.dart | 先读取真实游戏账号再打开已有流水详情 |
| sangong_profile_ledger_unavailable.dart | 流水入口未准备好时的公开说明、重试及真实群选择，不读取私人数据 |
| sangong_authorized_view.dart | 覆盖路由在撤权与销毁时隐藏私人内容 |

消息菜单接线在 `../widgets/sangong_message_actions.dart`，由真实聊天消息行调用，复用聊天当前运行实例。统计使用服务端业务messageId或OpenIM seq；不计入仅在有服务端业务messageId时显示，不把clientMsgID当数字。定庄仅对非空文本和真实发送者开放，输入最终由服务端解析，提交前确认，响应未确认时不能提示成功。

现有群浮窗、状态条及我的配置页继续复用，不新增另一套权限接口或服务端凭据。当前客户端完成不代表线上三公接口已发布；联调仍按父目录README的真实接口合同进行。

测试位于 `test/pages/group_features/sangong/profile/` 及 `sangong_profile_test.dart`，覆盖资料页刷新、空群与旧摘要缺失、服务错误、实际手机／宽屏入口、亮暗布局、写入确认与原始身份、权限撤销、晚到结果、实例销毁及消息ID条件。
