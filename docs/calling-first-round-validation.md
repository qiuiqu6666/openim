# 单聊通话与系统 PiP 首轮补齐

核对日期：2026-10-05。复用 OpenIM 200–204 在线信令、原 RTC token 接口、LiveKit 2.5.0+hotfix.3 和 flutter_webrtc 1.1.0，不发起真实呼叫、不修改远端服务。

## 已落地

- 独立连接租约、重复接听/结束去重、邀请及连接/重连期限。权限、凭证或媒体异步结果在取消后失效。
- 当前账号、房间和真实发送人的信令校验，忙线安全拒绝，旧房间终态去重。双方超时通知目标各自正确。
- 仅实际远端身份和媒体就绪后接通；重连保留原计时，后台暂停不影响以实际时间计算的时长。
- 媒体操作串行化和释放等待：前后台恢复、麦克风、相机、翻转及扬声器均通过房间适配器。发布失败前捕获的轨道仍被持有并清理。
- 结束同时发送终态和释放媒体，清理完成再关闭浮层、释放常亮及 busy。旧关闭回调或平台事件不能结束新通话。
- RTC 凭证请求复用原接口及 Chat 鉴权，失败不能清除登录。用户只看到已有简短提示。
- 最近通话持久化、账号隔离、终态/方向/本地时间、重拨、筛选与本设备隐藏记录。服务端同步、分页、通知及失败待上报队列见 [最近通话模块](../lib/pages/mine/secondary/calls/README.md)。
- Android 8+ 真正系统 PiP、桌面自动进入、恢复和关闭；iOS 15+ 真实远端视频 AVKit PiP。具体限制见 [平台核对](call-pip-platform-validation.md)。

实现入口及资源归属见 [通话模块](../openim_live/README.md)。

## 验证状态

通话、最近通话、会话生命周期、会话预览及聊天集成共 **194 项通过**。包括实际 SignalState 的权限/凭证晚到、连接过程中进入后台、系统 PiP 拒绝/超时后的摄像头暂停与恢复。日期选择器另有 **17 项通过**；SDK 测试替身补齐真实月份查询及点击后二次核验，保留分页、草稿、关闭后晚到结果的原断言。

定向静态检查 **无错误、无警告**，有 33 条 info（代码风格、旧组件与测试依赖提示）。Android 原生桥 javac 编译及 JVM 退出/进入策略 **14 项通过**。包含最终原生超时修复的 Android debug APK **构建通过**，安装包为 `build/app/outputs/flutter-apk/app-calling-pip-debug.apk`。

日志：`E:/openim/.temp/call-final-regression.log`、`call-final-analyze.log`、`call-datepicker-compatibility-test.log`、`call-pip-native-compile.log`、`call-pip-apk-build.log`。

独立安装包 SHA-256：`B3AAC81966FB65E5D9C9874E06F74441A6B4C1A3DE643CC57825A310BE5F93DB`。使用该文件，避免其它本地构建覆盖通用 `app-debug.apk`。

`docs/previews/call-light.png` 为实际 Flutter 控件测试预览，采用测试联系人、320px、2 倍字号和安全区。亮暗布局测试均通过；Windows 测试截图的暗色图仍出现部分白色内容未栅格化，不作为完整真机视觉证据。

## 尚未完成的验证和业务

- Android/iPhone 双端真机：音视频、权限拒绝、弱网、重连、蓝牙/听筒、锁屏、回到桌面、点击小窗恢复/X、远端挂断及快速重复呼叫。
- iOS 原生仅完成公开接口与参考实现核对；当前 Windows 无法进行 Xcode 编译、签名或 iPhone 验证。
- 当前单 Activity Android 结构在远端结束系统 PiP 时会恢复应用一次，以收起窗口。设备实际行为待验收。
- Chat `/chat/call-records` 同步路径已接入客户端，后端部署及联调未验证；失败保留本地记录和待上报队列。
- SDK 信令仍为 online-only，离线推送、PushKit/CallKit、群通话和多端抢接服务端协调未实现；后台在线邀请保留原有效期，不能视为完整离线来电。
