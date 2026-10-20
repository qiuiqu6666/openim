# 登录设备二次验证

## 发送一直加载的修复（2026-10-11）

旧图形验证在脚本加载后固定等待 2.1 秒，先通知 Flutter `ready` 再调用 `captcha.show()`。网络较慢时实例尚未建立，异步回调抛错且原生加载超时已被取消，透明弹层会让底层页面一直等待。

现在由 SDK 的 `getInstance` 回调触发展示，成功打开后才发送 `ready`，同步异常和异步失败都进入恢复界面。加载超时保持为 25 秒，失败后可以重新加载或返回，迟到的旧页面回调不能覆盖失败状态。验证码请求最多等待 40 秒，向 WebView 回传结果最多等待 5 秒；短信接口确认已发送后，即使桥接回调失效也会返回已发送结果并开始冷却。

发送阶段显示「发送中…」，确认登录按钮仅在真正提交登录时显示进度。沿用当前认证组件与验证接口，不跳过图形验证、短信验证或设备检查。这部分 HTML 随客户端打包，需要更新客户端才能生效。

回归验证：`flutter test test/aliyun_captcha_bridge_test.dart test/captcha_dialog_layout_test.dart test/pages/login/device_verification`；嵌入 JavaScript 的慢初始化、异常及桥接测试：`node --test test/pages/mine/settings/widgets/aliyun_captcha_html_test.mjs`。桥接测试覆盖 Android/iOS 模拟平台与亮暗主题；仍需真机检查网络较慢时的第三方验证弹窗。

参考 99chat `d7c3c65` 的 `lib/src/pages/login.dart` 中 `DeviceChallengePage`，以及 `src/ui/auth_widgets.dart` 中普通认证页和提示条。保留原布局、文案、字号、间距、颜色和圆角，沿用现有亮暗主题。账号或邮箱入口直接使用冻结的登录身份发送到绑定手机号，不再要求输入手机号或区号。

## 职责与入口

- `device_verification.dart`：页面公开入口。
- `device_verification_page.dart`、`device_verification_copy.dart`：界面、输入、反馈和重发冷却。页面不保存登录凭证，不持有账号密码。
- `device_verification_flow.dart`：从一次密码请求进入验证页，协调现有阿里云验证、发送和确认，持有所属页面及验证码弹层路由。父登录控制器关闭或输入改变时取消所属路由。
- `data/password_device_login_attempt.dart`：仅在内存冻结一次密码登录的请求，负责提交原请求和携带验证码重新提交；结束时 `close()` 释放快照。
- `data/device_verification_code_result.dart`：设备短信发送结果，缺失布尔字段按失败处理。

共用 `AuthCompoundField`、`AuthFieldLabel`、`AuthPrimaryButton`。新增共用 `AuthFormScaffold` 和 `AuthInfoBanner`，因为已有蓝白欢迎页不具备参考普通白底认证页的头部及盾牌提示。共享组件样式扩展均为可选参数，原调用方默认视觉不变。

## 当前接口（2026-10-20）

1. 原密码登录收到 `20081` 后，以冻结的登录身份、密码和设备信息请求 `/account/device/verification`，由服务器返回 `phone`／`email` 可用方式。无绑定用户的正常密码登录直接成功。
2. 双绑定显示手机号／邮箱选择，单绑定直接使用该方式；切换清空验证码、保留独立倒计时。
3. 点击获取验证码直接请求 `/account/device/code/send`，携带原登录字段和 `deviceVerificationMethod`，无需滑块参数。服务器决定接收地址；客户端不接受任意目标邮箱或手机号。
4. 确认向原 `/account/login` 提交冻结请求，增加 `verifyCode` 和 `deviceVerificationMethod`。成功取得完整 Chat/IM 凭据后才进入已有登录流程。
5. 新接口不带 token，保留旧密码加密重试、独立 operationID、请求归属检查和取消保护。账号服务端已发布，客户端仍需重新构建发布。

下面的测试与预览为历史记录；最新定向回归包含双方式选择、单邮箱默认、切换清码和冷却、原身份提交、过期请求及既有手机号登录。

## 生命周期与验证

发送与确认互斥且禁止重复点击。号码或区号变更清空验证码及冷却，光标变化不算号码变化。异步结果必须同时属于原登录账号、输入版本和页面；取消时只移除本流程自己的路由，迟到结果不能保存凭证或退出其他页面。验证码弹层结束时检查所属路由，不会误关闭覆盖它的新路由。

新增测试位于 `test/pages/login/device_verification/`，覆盖 HTTP 请求冻结、完整凭据校验、错误分流、账号切换及关闭、验证码冷却和实际界面。实际预览输出 `.temp/device-verification-previews/`，包含亮/暗父主题、已知/未知手机号、输入/加载/错误、小屏、横屏、大字体和键盘。

`LoginLogic` 超过 500 行的职责检查：其既有表单、记住密码与 SDK 登录协调继续保留；新增独立的验证页面、路由协调、短信解析及密码请求快照已拆到本目录。公共 `Apis` 只扩展既有登录门面以复用设备元数据和严格凭证校验，设备业务状态不放入公共包。未重构 SDK、会话、数据库或既有路由框架。

## 本次验收（2026-10-06）

- 新模块 41 项测试通过：8 项请求契约、13 项页面与实际预览、20 项完整登录流程。验证了手机号／公开账号／邮箱、错误重试、取消、切换账号、控制器关闭、页面覆盖、跨会话迟到响应、缺失凭据和未绑定手机号的中英文指引。
- 原有登录生命周期、表单反馈、认证校验、共享认证控件、验证码结果及错误提示 83 项回归通过；现有验证码弹窗布局和阿里云桥接 8 项回归通过。共 132 项相关测试通过。
- 登录模块、共享认证组件、验证码弹窗、API／HTTP／错误提示以及新测试目录的定向静态检查通过。无关文件既有提示未调整。
- 实际 Flutter 界面导出 16 种预览，核对了亮／暗父主题、已知／未知手机号、输入、发送、确认、错误、小屏、横屏、大字体和键盘状态，无布局溢出。认证页面沿用 99chat 固定白底，不随父应用切成暗底。
- Android debug APK 构建通过，交付路径为 `E:/openim/release-artifacts/app-device-verification-debug.apk`。页面预览位于 `docs/previews/device-verification/`。

尚未验证：服务端新协议部署后的真实短信与新设备联调，以及 iOS 构建和实机表现。本次没有请求真实登录服务或发送短信。
