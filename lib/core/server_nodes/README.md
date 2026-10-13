# 启动节点选择

`StartupNodeSelection.prepare` 在 `Config.init` 中完成本地配置加载后、HTTP 客户端和 OpenIM SDK 初始化前执行。每次进程启动重新检查，后台恢复、页面切换、聊天和通话期间不切换节点。

内置节点使用 `lhins-14l2mj2j.3w3hbb07j0xz.eo.dnse5.com`，Chat 为 HTTP `10008`、OpenIM API 为 HTTP `10002`、WebSocket 为 WS `10001`。旧版保存的 `129.226.192.93` 三个节点地址及早期三个内置域名在读取时迁移到新主机，自定义服务器地址保持原样。页面将唯一的节点显示为节点01。

启动只检测当前直连节点或自定义服务器，每个节点整体最多等待 3 秒。Chat 使用现有公共平台接口；OpenIM API 使用无 token 的只读请求并确认缺少 token 的标准响应；WebSocket 网关确认其未鉴权参数响应。检测不发送账号凭据、不创建用户连接，不代替 SDK 的实际鉴权登录。重定向、超时、异常响应和任一服务不可达均视为该节点不可用。

全部不可用时保留上次配置和登录凭据，不阻止 App 继续启动。自定义服务器只检测自身，不回退到生产节点。现有节点页面复用该目录的地址模型和启动检测结果，手动测速并行检测所有候选节点的 Chat 公共接口，各节点独立更新结果，不切换当前连接。

测试位于 `test/core/server_nodes/`，覆盖完整节点检测、超时、单节点启动、离线、配置持久化和自定义服务器隔离；`test/node_endpoint_config_test.dart` 覆盖旧域名配置的读取兼容。

显式手动切换由 `ManualNodeSwitchService` 负责串行协调、三服务预检、账号校验与失败回退，`ManualNodeSwitchRuntime` 复用当前 IMController 及共享 HTTP 客户端完成实际连接变更。它只在用户点击节点时执行，通话中拒绝操作。连接成功后页面才更新勾选；未成功恢复时提示重启，不能将已保存配置当作连接成功。初始化 SDK 时关闭启动通知，避免重入启动页登录；沿用 SDK 同一有序 MethodChannel 的 unInitSDK/initSDK，不修改原生插件。
