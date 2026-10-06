# 好友验证页对齐 99chat

日期：2026-10-05。

## 已修改

- 好友页面标题改为“添加好友”，蓝色返回按钮复用公共 GlassAppBar。
- 顶部显示已有的对方头像、昵称与公开账号；不显示内部 userID，缺少资料的旧入口不造默认用户资料。
- 验证信息改为四行卡片输入区，保留原客户端 20 个完整字符限制，支持中文组合输入及完整表情。
- 资料入口使用当前登录者真实昵称预填“我是：昵称”，可修改；没有已知本人昵称时不制造身份。
- 发送按钮移到表单下方，采用蓝色主按钮，发送中显示进度并禁用编辑和重复提交。
- 亮暗主题、窄屏大字体和键盘下的滚动共用同一界面。

参考 `E:/openim/reference-99chat` 版本 `d7c3c65` 的 `third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitAddFriend/tim_uikit_send_application.dart` 资料与验证表单，以及 `lib/src/pages/add_friend_page.dart` 的蓝色主按钮。没有复制参考项目的腾讯 SDK、好友请求接口或演示数据。

参考表单的备注和分组未添加：当前好友申请只提交验证消息，需要实际备注保存流程后才能开放对应输入。本次保留 OpenIM 的申请能力和限制，不宣称复制了参考页全部功能。

## 维护与业务

实现归属 `lib/pages/contacts/send_verification_application/`。主 view 接线，logic 管理申请状态；纯表单位于 `widgets/verification_application_form.dart`，视觉常量位于 `verification_application_tokens.dart`。复用已有 GlassAppBar、AvatarView、AppTokens 和 Flutter 表单控件。

原资料页与路由只追加已知的资料和本人昵称参数，没有新增查询。好友申请继续按原来源字段完成 grant→apply；入群继续调用原 joinGroup，二维码来源 4，其他来源 3。点击时冻结当前验证消息，失败保留输入；退出页面释放控制器，迟到结果不操作旧页面。

## 验证

- 原好友来源协议与资料页：21 项回归通过。
- 本模块界面：8 项通过，覆盖亮暗主题、发送中状态、完整表情长度、群验证标题、320 宽度＋2 倍字体＋键盘滚动。
- 本模块申请逻辑：9 项通过，覆盖资料与问候初始化、原好友来源／名片字段、验证消息快照、重复点击、失败保留草稿、退出后迟到结果，以及二维码／搜索入群来源。HTTP 与 SDK 均由测试截获，没有真实申请。
- 合计 38 项相关测试通过。
- 本模块源码与测试静态分析无问题。路由文件及旧资料控制器存在此前的 lint 提示，本次未整理无关旧代码。
- Android debug APK 构建成功。
- 已查看下方亮暗测试预览。预览使用示例资料；未在真实设备安装，没有提交真实好友／入群申请，没有部署或重启服务。线上结果与真实设备键盘尚未验收。

[亮色测试预览](../build/verification-preview/verification-99chat-light.png) · [暗色测试预览](../build/verification-preview/verification-99chat-dark.png)

## 修复包

[Android 调试修复包](../build/app/outputs/flutter-apk/app-debug-friend-verification-99chat-20261005-3cb4cffc482b.apk)

SHA-256：`3cb4cffc482bfc1fead0ad25add14a928003fe4cd51a9ea7a1c51cd3678b3eac`

此包包含当前共享工作区状态及此前收藏界面修改。
