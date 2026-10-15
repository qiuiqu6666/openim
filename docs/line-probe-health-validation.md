# 线路健康探活修改验收

日期：2026-10-15（UTC+8）。适用当前 `E:/openim/openim-flutter-demo` 源码；尚未与线上已安装包的哈希及构建产物建立对应关系，不能认定所有线上缺少 token 告警均来自此实现。

## 调用定位

确认旧 `lib/core/server_nodes/node_availability_probe.dart` 的 `_api()` 使用独立 Dio，POST 空对象到候选 IM API 的 `/user/get_users_info`，仅发送 operationID，故意以 `errCode:1001` 与含 token 的 errDlt 判断可用。

其调用者包括：`StartupNodeSelector` / `TimedNodeProbe` 的启动选线、`AutomaticNodeRuntime` 的自动恢复、`ManualNodeSwitchRuntime` 的切换前预检、`ShieldReadiness` 的转发就绪验证，以及 `ApiConnectionHealth` 的当前线路检查。后者正常约每 5 秒检查，自动选线正常约每 30 秒检查；失败沿用既有有上限退避。

本地手动测速 `NodeProbeController` 原实现仍为 `/chat/platform`，本次也改为对应 Chat 基础地址的 `/healthz`，不将它冒认为旧 POST 的来源。

核对本地原生源码：`sdk-source/openim-sdk-core-recovery/internal/user/server_api.go` 的资料查询经 `api.GetUsersInfo.Invoke` → `network.ApiPost`，后者使用上下文的 token 设置请求头。该真实业务链路没有修改，未取得截图账号的有效登录请求，未声称已验证其线上鉴权。

## 变更

- 新增模块内 `public_health_check.dart`，供现有探测点复用；现有 UI、线路候选、SDK、登录、WebSocket 心跳和消息补拉架构保持原归属。
- 每条候选分别使用自己的 Chat 与 OpenIM API 地址，保留地址前缀；不从 WebSocket 地址推导 IM API 地址。
- 严格验证健康协议，拒绝业务错误、错误服务、HTML、非 200、重定向及 TLS 错误；不回退到业务接口。
- 独立请求隔离账号凭据，携带唯一探测标识、来源及可获得的真实安装版本。
- 共享单个所有者的重复在途检测，取消过期网络任务，阻止旧结果发布；退避增加有上限抖动。
- HTTP 存活不代表数据库、RPC、登录、网关连接或消息同步成功。独立网关可达性预检仍沿用现有协议。

## 验证

定向测试 120 项通过，覆盖启动/自动/手动切线、API 连接健康、游戏盾预检、非法健康响应、凭据隔离、版本标识、多候选、总超时、取消、重复触发及前后台恢复。定向 `flutter analyze --no-pub` 无问题。

日志：`E:/openim/health-probe-final-tests-20261015.log`、`E:/openim/health-probe-analyze-20261015.log`。测试包含现有线路页布局回归；本次未增加或调整视觉组件和设计 token。

从本机直接请求生产两个域名及备用主机 10002/10008 的 GET/HEAD：均取得过 HTTP 200、正确服务标识（GET）和 `Cache-Control:no-store`；首轮生产 OpenIM HEAD 与 Chat GET 各发生一次 5 秒超时，后续复测成功。这是 HTTP 可达性自检，不是登录态或 SDK 联调。

Android Debug 构建成功，日志见 `E:/openim/health-probe-apk-build-20261015.log`。测试包：`E:/openim/artifacts/line-probe-health-20261015/99chat-health-probe-debug.apk`；SHA256：`6E2DFACD0BE11C52D2675D0A8231B1630B50789EDBE278EF2EE8B75028F9C85A`。构建使用当前完整工作区，包含其他尚未提交的改动，不是仅此修复的隔离生产发布包。iOS、桌面与 Web 的实际运行，以及跨 Wi-Fi/蜂窝、登录态、WebSocket 和补拉的真机联调尚未完成。

## 灰度与回滚

尚未发布。先核对线上应用版本/SDK 版本及产物哈希与源码，分配正式构建号并按已有分发流程灰度。服务端按 `X-Client-Source:line-probe`、版本声明及 `line-probe-` 请求标识核对 `/healthz` 流量；结合客户端检测次数、成功率及取消情况观察，确认缺少 token 的业务请求告警是否下降。诊断头只是声明，不用于授权。

旧版仍可能继续发起原探测，不要求全站告警立即清零。异常时回退客户端本次改动；新客户端依赖 `/healthz` 后不要单独撤销服务端健康接口，也不要降低原业务接口鉴权。
