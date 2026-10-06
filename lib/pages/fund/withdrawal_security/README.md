# 本次资金短信验证

公开入口为 `withdrawal_security.dart`。资金提交页面先保留原 `clientOrderID` 和业务字段，恢复已有结果后，再调用 `authorizeFundSecurity`，最终把 `proof.toJson()` 加到原交易请求。模块只调用当前 Chat API 的安全预检查与发送短信接口；不扣款、冻结或保存密码和验证码。

`data/` 管理参数白名单与严格响应解析，`presentation/` 管理等待期提示、短信弹窗、倒计时与现有账号安全导航。业务参数不可变，检查与发送使用相同值。取消、页面关闭、账号/令牌/服务变更均不返回有效凭证；调用方通过 `isCurrent` 持有其生命周期和会话检查，不能仅判断被短信弹窗覆盖后会变为 false 的页面 `ModalRoute.isCurrent`。

短信弹窗只保留最新 challenge，重新发送立即使旧输入失效，过期必须重新发送。验证码由提交接口验证和消费，本模块不伪造“验证成功”状态。使用已有资金颜色与公共设计 token 支持亮暗主题；99Chat 现有提币确认页没有本次安全短信接口，交互以用户提供的接口文档为准。

对应测试位于 `test/pages/fund/withdrawal_security/`。
