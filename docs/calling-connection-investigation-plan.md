# RTC 连接中断修复与验证

目标：定位最近两场 iOS 呼叫进房约 10 秒后断开的客户端触发链，修复经验证的问题。
边界：复用 OpenIM/LiveKit/GetX 与现有通话模块；保留其他未提交修改；不部署服务器。
验收：可重复回归、相关通话测试和 analyze；明确真实设备未验证部分，不能仅凭服务端断开记录宣称线上根因已证实。

## 证据与定位

- 本地 origin 为用户提供的 `qiuiqu6666/openim`，排查开始时 HEAD 与远端 HEAD 均为 `e6ed8d64ad002d5fb49f45b08cbb1ecd9c171e91`。
- 服务端 2026-10-16（UTC+8）两次 RTC 会话：02:19:27.704 → 02:19:37.678（9.974 秒）；02:19:41.068 → 02:19:51.086（10.018 秒），随后服务器记录 SCTP `User Initiated Abort: Close called`。此术语不能解读为用户手动挂断。
- 两场都未见媒体轨道发布，随后以 `PEER_CONNECTION_DISCONNECTED` 清理；相关 webhook 为 200。通话时段未见服务重启。用户确认是通话页面关闭回到聊天，并非 App 崩溃。
- 应用 SingleCallSession 连接期限 20 秒，默认振铃 30 秒，CallKit 音频等待 15 秒，不能仅凭时长将故障归因于这些计时器。
- 实际依赖 LiveKit `2.5.0+hotfix.3` 的连接等待为 10 秒。Engine.connect 在发起信令之后才等待 Join，在 Join 完成之后才等待主 PeerConnection。事件流为不重放的 broadcast，提前事件会丢失。
- 对原版真实 Engine 的确定性回归分别复现 Join 超时和媒体连接超时：两个正向用例失败，一个真正未连接的负向用例通过。只替换信令事件时序，将测试等待期限缩短为 40ms，没有替换 Engine 的连接逻辑。
- 原版同版本 Flutter SDK 在 Chrome 的隔离真实 WSS 房间中约 1.453 秒完成连接，并保持超过 12 秒；因此不能认定服务器存在普遍协议不兼容。该测试没有验证 iOS、CallKit、媒体发布或双向音视频。临时测试及短效凭证已删除。

## 修复范围

本地保存当前固定版本 LiveKit 运行代码及许可证，通过根 pubspec override 使用。
唯一运行实现差异是 Engine.connect 的连接事件等待：提前订阅，保留事件，失效提前就绪后又断开的状态，在成功/失败 finally 释放监听。没有延长超时，没有绕过真实连接检查，没有改原生代码、媒体发布、CallKit 或生产数据源。

复用 SingleCallOwner、SingleCallSession、SingleCallMedia、原信令/SDK/路由；无新增 UI 组件，不改变 Light/Dark。上游 1357 行 engine 文件属于第三方局部修错例外，未拆改其核心架构。复制目录及逐文件校验见 `local_plugin/livekit_client/README.md` 和 `upstream-sha256.json`；可审阅补丁见 `patches/connection-event-order.patch`。

## 进度

- [x] 核对服务器时间线与本地仓库来源。
- [x] 追踪呼叫、RTC、CallKit、信令及超时/退出入口；复现 SDK 事件顺序竞态。
- [x] 修复已复现的竞态；补充提前事件、过期就绪、副连接、真实未连上、信令失败回归。
- [x] 完整通话回归：`flutter test --no-pub --concurrency=1 test/pages/chat/calling test/core/calling`，276 项全部通过（含 6 项新增 RTC 时序回归）。
- [x] 修改范围 analyze：No issues found。
- [x] iOS 无签名 Release 构建：`flutter build ios --release --no-codesign --no-pub` 成功，201.0 秒，生成 `build/ios/iphoneos/Runner.app`（141.6 MB）。未签名、未安装到故障手机。

## 环境与限制

首次完整测试编译因磁盘不足失败（errno 28），不是代码断言失败。中止本次工具进程后清理 Flutter 临时编译文件与可再生成缓存，重新串行验证；不删除源码或已有 IPA。

服务器历史日志缺少故障客户端堆栈，当前已证实的是可导致同类 10 秒误超时的代码缺陷。不能声称两次线上自动退出已被真机证实解决。最终仍需受影响 iPhone 安装修复构建，复测呼出/接听、音频/视频、Wi-Fi/蜂窝、后台/恢复、正常取消与双向媒体，核对是否仍约 10 秒退出。

Android 原生文件逐个校验与固定上游版本一致；本次未执行 Android 构建或 Android 真机测试。未修改服务端配置或部署业务服务，未推送 GitHub。
