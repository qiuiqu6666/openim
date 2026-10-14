# 悠梦 iOS 接入

来源：用户提供的 `E:/下载/悠梦游戏盾IOS/ios-sdk/Sources/GameShield/GameShieldClient.swift`。纯 Swift、Network 和 CryptoKit，不引入旧 Go SDK。由 Runner 编译，不需要额外 Pod；AppDelegate 持有 YoumengBridge。

桥接通过 openim/youmeng 接收现有 YOUMENG 配置。在专用串行队列完成配置校验与节点加载，再用 NWListener 仅绑定 127.0.0.1 的 10008、10002、10001、8815。四个监听全部 ready 才返回启动成功。每条进入的 TCP 连接单独建立 SDK 隧道，转发 HTTP/WS 字节，保持 OpenIM 原生接口不变。调度配置映射决定每个本地端口对应的源站端口。

启动有 40 秒超时；缺规则、无节点、端口被占用或初始化错误关闭全部监听并自动重试。首次冷启动等待超过 1.2 秒才显示共用加载提示；应用内重试保持当前页面，由顶部连接状态展示。流量缓冲设置上限，超限关闭连接而非静默丢弃数据。监听就绪仅代表本地启动完成，不能代表远端隧道认证和业务请求成功。

对供应商源码的必要修正：
- 修正 NWConnection.receive 回调参数数目、节点 JSON 类型转换和 HMAC 结果转 Data。
- 合并并发初始化，完成调度校验后才标记 started；失败可重试，停止使旧初始化失效。
- 调度、隧道及桥接共享串行队列，避免并发访问节点表、隧道池和接收回调。
- 持有未完成连接的隧道；停止时取消隧道，阻止延迟 TCP ready 回调复活连接。
- 接收处理器注册前暂存有界数据，修正上行缓冲超限时静默丢帧行为。

## 2026-10-14：备通道待命但恢复连接不结束

原实现 TCP ready 后发送 HELLO 就标记 live、打印 backup_up，并未等服务端 PONG 确认；6 秒超时只判断 HELLO 是否发出，也不会清理 TCP 已通但握手未确认的连接。首选通道还在拨号时，备用通道即使成功也不能及时接替；备用升主后仍按创建时的“备用”身份处理故障，会留下失效的主通道。候选节点全部被摘除后，启动阶段又缺少重新调度，后续重试可一直没有节点。

修复后的职责：

- `GameShieldClient.swift`：配置、节点列表与隧道所有权；候选池耗尽时合并重新获取请求，最小间隔 5 秒，无需等待业务隧道已连接。
- `TunnelConnection.swift`：帧解析与主备连接；收到 HELLO 的 PONG 才就绪，第一个确认成功的通道立即承担主通道。按当前身份处理故障，跟踪并取消尚未完成的拨号，重试只有一个计时链；握手 6 秒超时、无可用通道 30 秒收口。
- `YoumengBridge.swift`：本地 TCP 转发；握手阶段即读取本地输入并有界暂存，客户端取消请求时取消未完成的建盾，防止反复探测积累悬挂连接。
- `ShieldReadiness`：首次/切入游戏盾的三项业务检测预算为 15 秒，成功立即结束；正常直连的 1/1.25/2.25 秒选择时点不变。业务验证仍要求三个服务全部通过；客服不参与判定。

日志分层：`local TCP listeners ready` 仅表示监听；`tunnel_ready`/`backup_up` 表示对应端口的 HELLO 已确认；`[Youmeng] business_ready` 才表示三项业务探测通过。`business_probe_failed` 提供失败服务和脱敏原因；`tunnel_err` 区分 TCP、HELLO、心跳、读写失败。不要将 nw_connection 的未连接元数据警告或单独的 backup_up 当作业务恢复成功。

本机只读协议实测：两个候选中的一个完成真实 HELLO/AES-GCM 转发，10008 返回业务 errCode=0、10002 返回缺 token 的预期 errCode=1001、10001 返回预期 errCode=1602；另一个 TCP 连接超时。这是当前 Windows 网络上的协议验证，不代表 iPhone 上的实际网络或登录结果。

原生回归脚本（Mac，无真实凭据）：`sh ios/tests/Youmeng/run.sh`。使用实际 Swift 隧道源码和本地 TCP 模拟节点，覆盖握手前不报告就绪、分片/连续空 PONG 与 DATA、备用先成功、升主后再次故障、取消未完成拨号、HELLO 超时和重复回调。Windows 无法执行这个 Network/CryptoKit 测试，需在 Mac 验证后安装真机包。

Windows 上无法编译 Network/CryptoKit 或运行 Xcode。必须在 Mac 上执行：

    flutter pub get
    cd ios && pod install && cd ..
    flutter build ios --debug --no-codesign

默认启用游戏盾，凭据从应用内的 `tool/youmeng/youmeng.local.json` 资源读取，该配置文件已被仓库跟踪。不要把凭据写入日志。iOS 当前版本的 OpenIM 自定义 Framework 也需按项目原有方式准备。

待验证：Xcode 编译、真机首启/重试、四端口 HTTP/WS 往返、账号登录及收发消息、客服附件、切网、息屏与恢复。iOS 挂起时不能保证本地转发继续，保留现有 APNs/PushKit，不新增虚假后台模式。未取得商店审核或真机可用性结论。
