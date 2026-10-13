# 悠梦网络保护接入

Android 供应包：`E:/下载/悠梦游戏盾`。采用包内纯 Java 源码 `cn.gameshield.sdk.GameShieldClient`，不同时引入 AAR。源码版本标记 android/1.4.6；无 Go 桥接类、JNI 或 SO。iOS 采用后来提供的 `E:/下载/悠梦游戏盾IOS` Swift 源码，接入说明见 `ios/Runner/Youmeng/README.md`；已添加桥接与本地监听，尚未经过 Xcode 编译和真机验证。

应用在 Config 初始化网络客户端前启动 Android 前台服务或 iOS App 内转发层。SDK 在工作队列拉取配置、启动监听；四个 TCP 监听端口全部就绪后，进程内安装 127.0.0.1 转发地址。失败时显示重试页，不继续初始化聊天应用。当前默认业务地址也是本地回环地址，关闭开关不会自动改回远端域名。

## 配置

复制 `tool/youmeng/youmeng.example.json` 为同目录 `youmeng.local.json`（Git 忽略），填写供应商提供的 HTTPS 调度地址、SDK Token 和配套 32 字节 AES 密钥（64 位十六进制），准备好规则后把 YOUMENG_ENABLED 改为 true。

原 GS2 Token 不适用于此 API。后台必须配置 TCP 本地端口 10008、10002、10001、8815，分别指向业务 API、IM API、消息 WebSocket 和客服源站；源站需接受对应的 HTTP/WS 流量。通话接口跟随业务 API。SDK 的规则配置决定真实源站，客户端不会自行修改后台。

构建：`flutter build apk --debug --dart-define-from-file=tool/youmeng/youmeng.local.json`。

本地转发配置不写入服务器偏好。自定义服务器不允许套用这些生产规则。前台服务拥有 SDK，Activity 重建不重新启动；系统终止服务/进程不保证连接继续，未实现无凭据后台自动重启。

## 对供应商源码的修正

- TCP 监听在 start 返回前同步绑定，端口占用会抛出错误。
- 增加 boundTcpPorts 查询实际监听，避免仅凭远端规则或 UDP 端口报告就绪。
- stop 显式关闭 TCP 监听和已登记会话的游戏 socket、主备隧道。
- 已完成会话从登记列表释放。

未修改隧道协议、加密算法和节点调度。上游源码保留在 Android app 的 cn/gameshield/sdk 目录。后续升级需保留这些修正并复测。

## 验证边界

需要真实凭据和设备验证首次启动、端口占用与重试、登录/收发消息、客服上传与 WebSocket、Wi-Fi/移动网络切换、息屏恢复、系统杀进程及前台服务通知。前台服务不能保证系统不终止应用。当前未验证远端认证、流量转发及 iOS；文档中的商店审核承诺不是本项目的验证结论。
