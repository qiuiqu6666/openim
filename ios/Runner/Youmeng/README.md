# 悠梦 iOS 接入

来源：用户提供的 `E:/下载/悠梦游戏盾IOS/ios-sdk/Sources/GameShield/GameShieldClient.swift`。纯 Swift、Network 和 CryptoKit，不引入旧 Go SDK。由 Runner 编译，不需要额外 Pod；AppDelegate 持有 YoumengBridge。

桥接通过 openim/youmeng 接收现有 YOUMENG 配置。在专用串行队列完成配置校验与节点加载，再用 NWListener 仅绑定 127.0.0.1 的 10008、10002、10001、8815。四个监听全部 ready 才返回启动成功。每条进入的 TCP 连接单独建立 SDK 隧道，转发 HTTP/WS 字节，保持 OpenIM 原生接口不变。调度配置映射决定每个本地端口对应的源站端口。

启动有 40 秒超时；缺规则、无节点、端口被占用或初始化错误关闭全部监听并回到重试页。流量缓冲设置上限，超限关闭连接而非静默丢弃数据。监听就绪仅代表本地启动完成，不能代表远端隧道认证和业务请求成功。

对供应商源码的必要修正：
- 修正 NWConnection.receive 回调参数数目、节点 JSON 类型转换和 HMAC 结果转 Data。
- 合并并发初始化，完成调度校验后才标记 started；失败可重试，停止使旧初始化失效。
- 调度、隧道及桥接共享串行队列，避免并发访问节点表、隧道池和接收回调。
- 持有未完成连接的隧道；停止时取消隧道，阻止延迟 TCP ready 回调复活连接。
- 接收处理器注册前暂存有界数据，修正上行缓冲超限时静默丢帧行为。

Windows 上无法编译 Network/CryptoKit 或运行 Xcode。必须在 Mac 上执行：

    flutter pub get
    cd ios && pod install && cd ..
    flutter build ios --debug --no-codesign --dart-define-from-file=tool/youmeng/youmeng.local.json

本地凭据文件不会随 Git 同步，Mac 需单独配置。iOS 当前版本的 OpenIM 自定义 Framework 也需按项目原有方式准备。

待验证：Xcode 编译、真机首启/重试、四端口 HTTP/WS 往返、账号登录及收发消息、客服附件、切网、息屏与恢复。iOS 挂起时不能保证本地转发继续，保留现有 APNs/PushKit，不新增虚假后台模式。未取得商店审核或真机可用性结论。
