# 邮箱账号管理

`EmailAccountPage` 管理绑定和更换邮箱，`EmailAccountService` 隔离接口、会话归属及个人资料刷新。账号安全和个人资料的邮箱入口共用此模块。

- 对照本地 `reference-99chat/lib/src/pages/settings/account_security_page.dart` 和 `change_phone_page.dart` 的设置入口和验证码交互；参考仓库未提供完整邮箱管理流程。
- 复用 SettingsScaffold、AuthTextField、AuthCompoundField、AuthCodeAction、SettingsPrimaryButton 和现有阿里云验证码弹窗。使用现有主题与布局，不新增依赖。
- 首次绑定要求当前登录密码及新邮箱验证码；更换要求旧邮箱和新邮箱验证码。不提供无验证解绑或绕过旧邮箱的客户端入口。
- 提交、加载、错误重试均保留输入；请求期间禁用重复提交；账号切换或页面关闭后不导航、不刷新其他账号资料。
- 成功后更新 IMController 资料、匹配的邮箱登录记忆；手机号登录记忆不变。
- 注册、验证码登录、找回密码使用共享 `lib/widgets/auth/auth_identity_selector.dart`；密码登录继续自动识别手机号、公开账号与邮箱。

相关测试位于 `test/pages/mine/settings/account_security/email/`，另外复用 login、register、forget_password、auth_credentials、friend_add_source 测试。

本地已验证亮暗主题和 375 宽度、两倍文字缩放布局。未执行 Android/iOS 真机操作或屏幕阅读器检查；未验证真实 SMTP 投递。后端部署说明见 `E:/openim/compensation-work/chat/docs/client/email-account.md`。
