# 账号安全短信策略

`sms_policy_state.dart` 复用 `SettingsService.refreshSecurity()`，在密码、支付密码、手机号表单进入和提交前读取当前用户的 `smsVerificationExempt`。缺失字段默认为关闭；加载失败禁用提交并显示重试。

开关只由后台管理员修改，客户端仅改变表单，不授予权限。免短信时发送空验证码，不生成或填充测试验证码。接口仍检查会话和服务端用户设置；提现使用原资金安全预检的 `smsRequired`。

相关测试：`test/pages/mine/settings/account_security/sms_exemption_test.dart`，覆盖日夜主题、空验证码提交、关闭开关后的恢复和策略读取失败。
