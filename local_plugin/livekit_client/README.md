# LiveKit 连接事件顺序补丁

来源：pub.dev `livekit_client 2.5.0+hotfix.3`，包校验值
`011affc0fca22b2f9b0e8827219dad9948f84f2bf057980693de13039de904c7`。
保留上游 LICENSE、NOTICE、Dart 和各平台运行代码；不包含示例与上游测试。
`upstream-sha256.json` 记录复制时每个运行文件的 SHA-256。

唯一运行实现改动为 `lib/src/core/engine.dart` 的 `Engine.connect`：
先订阅 Join 和主 PeerConnection 就绪事件，再发起信令连接。提前到达的
广播事件通过 Completer 保留，避免已连接却等不到第二次事件而在默认
10 秒后报错。提前就绪后又断开的状态会使缓存失效。成功和失败均释放
本次监听；超时值、凭证、媒体发布、CallKit 和原生代码保持原版本行为。

可审阅的上游差异见 `patches/connection-event-order.patch`。SDK 是现有
依赖的本地修补，并未另建 RTC 引擎。应用通过根 pubspec 的路径 override
使用此目录；不依赖开发机器的 pub 缓存修改。未来升级需重跑以下测试，
确认上游修复后再移除本地 override。

验证入口：

```sh
flutter test test/pages/chat/calling/rtc/livekit_connection_order_test.dart
flutter test test/pages/chat/calling test/core/calling
```

回归直接运行真实 SDK Engine，只替换信令时序，不使用网络、账号或假
生产数据。两项正向用例在原版 SDK 分别复现 Join 和媒体连接超时。
服务端历史会话没有客户端堆栈，因此该竞态与线上两次断开的对应关系
仍需故障 iPhone 安装修复版本后验证；不能把单元测试当作真机复测。

本次应用验证：276 项通话相关测试通过；补丁与新增测试 analyze 无问题；iOS 无签名 Release 构建成功。Android 构建和故障 iPhone 真机复测尚未执行。
