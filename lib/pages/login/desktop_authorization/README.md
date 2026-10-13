# 手机扫码登录

按用户提供的 2026-10-13 OpenAPI 1.0.0 接入。

- 二维码仅接受 99chat-login:v1:<43位公开标识>，拒绝 URL 和旧 JSON 草案。
- 使用当前 Config.appAuthUrl，强制 HTTPS。独立无日志 Dio，不跟随重定向；token 仅放请求头。
- scan 保存 confirmNonce 于内存；手机输入电脑上的六位数字，confirm 提交原 nonce；关闭未确认页面调用 reject。
- HTTP 200 仍检查 errCode，202 不能当成功；不显示服务器原始错误正文。网络结果不确定时可使用原参数重试。
- 页面和服务绑定当前账号及业务 Token，切换账号后禁止继续授权。
- 手机没有 DesktopProof，不调用桌面 status/exchange/complete/cancel。确认成功只表示 approved，不声称电脑已连接。
- 设备横幅沿用 login_records 的 online 字段；长期退出调用 device/remove。
- 复用现有主题、布局和原 99Chat 电脑素材，输入六位数字替代此前展示模拟码。

尚需真实电脑二维码及受管手机账号验证完整链路。当前接口未提供手机查询最终授权状态的能力。
