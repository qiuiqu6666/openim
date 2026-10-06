# 好友／入群申请

2026-10-05 将旧好友验证页的整块空白编辑区和右上角发送，调整为资料卡、验证信息卡与表单下方发送按钮。好友标题为“添加好友”，入群标题保留“群验证”。亮暗主题、键盘下滚动和大字体布局共用同一实现。

## 参考与适配

参考本地 `E:/openim/reference-99chat`，版本 `d7c3c65`：

- `third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitAddFriend/tim_uikit_send_application.dart:88` 的 SendApplication：对方资料、48 头像、验证信息四行编辑区、表单下方发送。
- `lib/src/pages/add_friend_page.dart:1026` 的主操作按钮：蓝色、最小高度 48、17 号半粗体、圆角 6。

使用项目原有 GlassAppBar、AvatarView、FilledButton 和 AppTokens，专属尺寸归 VerificationApplicationTokens。新增表单文件是独立的界面职责，便于测试和复用好友／入群场景，不增加第二套请求或发送服务。

参考页的备注和好友分组不在本次范围内。现有 FriendAddRequest 申请只提交验证消息，未建立备注保存流程，因此不添加没有实际保存能力的输入框。保留原客户端 20 个完整字符上限，支持中文组合输入和表情。

## 状态与数据

`SendVerificationApplicationPage` 负责连接 GetX 控制器和表单；`widgets/verification_application_form.dart` 只负责显示与输入；既有 logic 继续管理申请来源、授权、错误映射和提交。

资料入口通过原路由传递已有的昵称、头像和公开账号，不新增用户查询，也不把内部 userID 显示成账号。昵称和头像缺失不影响具备完整入口信息的申请；单聊资料、昵称或 IM 号不能直接充当添加来源。本人昵称可生成“我是：昵称”的可编辑验证消息，默认内容同样按完整字符限制长度。

资料页和申请页共用 `FriendAddRequest.canSend` 与真实提交相同的八来源必填规则。无有效入口时，资料页引导使用聊天号搜索；旧申请页会提前说明需要聊天号、二维码或名片，并禁用发送，不启动加载或发请求。显示的 `targetAccount` 不补成申请字段，旧名片缺邀请码时也不会使用 IM 号绕过规则。二维码、链接、名片和群来源保留原字段，入群申请不受好友入口校验影响。

发送时冻结当前验证消息，禁用编辑与再次发送。好友继续执行 FriendAddRequest 的 grant→apply；入群继续执行原 joinGroup，二维码来源 4，其他来源 3。成功、失败、权限拒绝仍走原提示；失败保留输入。页面关闭后释放文本控制器，迟到结果不返回或提示旧页面。

## 验证与边界

本模块界面回归位于 `test/pages/contacts/send_verification_application/`，包含亮暗主题、发送中、完整表情计数、群验证及窄屏大字体键盘布局。测试预览位于 `build/verification-preview/`，使用示例资料；它们不是线上用户截图。

好友来源与资料页既有回归已通过 21 项，界面专项 8 项和申请逻辑专项 9 项通过，共 38 项；HTTP 与 SDK 均截获，不发送真实申请。本模块源码与测试静态分析无问题，Android debug APK 构建成功。证据、预览和修复包记录于 [本次修改记录](../../../../docs/friend-verification-99chat-2026-10-05.md)。

路由文件及旧资料控制器还有此前的 lint 提示，本次只追加资料参数，未整理无关旧代码。没有发送真实好友申请、安装到设备、部署或重启服务；真实设备键盘与线上服务结果尚未验收。
