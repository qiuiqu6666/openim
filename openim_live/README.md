# 单聊音视频通话

保留应用现有 OpenIM 在线信令、RTC token 接口、LiveKit 房间和 WebRTC 采集。聊天、资料页和最近通话重拨继续使用 `OpenIMLive.call`，并由 `OpenIMLiveClient` 持有唯一浮层及忙碌状态。

## 资源归属

- `signaling/` 校验 200–204 消息身份、房间和邀请有效期，处理忙线、终态去重、铃声及 SDK 聊天记录。RTC 凭证错误只结束本次通话，不能清除登录。
- `signaling/call_ringtone.dart` 持有来电铃声/呼出回铃的唯一播放器、装载队列和取消代次；控制器决定当前账号、房间和呼叫方向。音频资源及离线生成说明放在 [assets/audio/ringtone/](assets/audio/ringtone/README.md)。
- `session/single_call_session.dart` 持有连接租约、30 秒呼叫期限、20 秒连接/重连期限、真实接通计时和唯一终态。取消立即使异步权限、凭证及媒体连接结果失效。
- `session/call_media_operations.dart` 串行执行媒体操作；结束时立即关闭入口、等待进行中的操作，并清理尚未成功发布的采集资源。
- `pages/single/room.dart` 持有 LiveKit Room、事件监听及本地轨道。仅在媒体就绪且目标远端身份真实存在后接通；重连保留原计时。
- `pages/single/widgets/` 展示通话状态、媒体及操作。控件通过房间适配器切换麦克风、相机、扬声器，不自行持有媒体资源。视频保持父容器尺寸、裁剪并使用 cover；全屏右上预览单独持有切换手势，等待接听时也能切换，缺失轨道显示公共头像占位并保留切回入口。
- `platform/call_picture_in_picture.dart` 管理当前会话的系统 PiP。每次配置带独立会话编号，迟到的旧窗口事件不能恢复或结束新通话。
- `widgets/call_compact_surface.dart` 用于应用内小窗和 Android 系统小窗，视频使用实际 TrackRenderer；音频显示计时及通话图标。小窗视频只负责展示，由外层统一持有点击恢复和拖动手势，避免摄像头对焦/缩放抢走操作。
- `widgets/call_surface/` 持有全屏通话独立底色、文字色及局部系统栏样式。日夜均使用 99chat 深灰通话背景，按钮复用公共包的六个原图资源，避免普通页面主题使浅色图标消失。
- `models/incoming_call_preferences.dart` 是应用提供的来电选项契约。`OpenIMLive.preferencesForIncomingCall(accountID)` 读取当前邀请账号，`refreshIncomingCallPreferences()` 应用保存后的变化；来电铃声开关不影响出站回铃。`widgets/incoming_call/` 复用公共 `BottomSheetView/AvatarView` 展示快捷接听，关闭时保留全屏入口。所有操作使用同一个通话 session；接听开始立即停止来电等待音，设置变化不能让接听中的来电重新响铃。

通话进入终态后立即移除全屏、小窗、快捷接听和返回拦截，恢复下层页面操作；对方通知、记录保存及媒体释放继续使用同一个结束任务。等待清理完成后才释放常亮及忙碌占用，避免新通话抢占尚未释放的媒体。外部退出在页面尚未挂载时也会先移除浮层，不等待取消信令。离开聊天页不会误挂断全局浮层；退出账号先结束通话再退出 SDK。控制器销毁关闭订阅、铃声及信令源。

该退出顺序对照本地 99chat `lib/src/services/livekit_call_session.dart` 的立即关闭 UI 行为。保留原 `onClosed` 的清理完成时机，避免提前清空连接时间与信令信息而损坏通话记录。慢信令、记录保存及原生释放的退出回归测试归属 `test/pages/chat/calling/termination/`。

RTC 凭证请求同时兼容公共 HTTP 层保留的 `DioException`，将网络失败映射为通话专用的简短网络提示；业务错误码继续交给原处理流程，临时 RTC 失败不会清除 IM 登录。直接声明已使用的 Dio 依赖，版本约束与当前公共包一致。

2026-10-06 验证：通话与最近通话共 213 项测试通过，其中新增 16 项覆盖清理和信令阻塞时退出、下层点击及系统返回、重复挂断、对方终止、迟到连接、全屏/小窗/PiP/快捷接听和挂载前退出。修改范围及新增测试目录 analyze 通过；不连接线上 RTC，设备实际弱网及原生媒体释放仍需真机验证。

## 平台小窗

Android 8+ 支持系统 PiP，通过真实设备能力和 AppOps 权限判断，接通后可点击按钮或回到桌面进入；系统关闭小窗结束当前通话。程序结束当前系统小窗时恢复现有 Activity 一次，避免聊天页遗留在 PiP 中。

iOS 15+ 视频通话采用 AVKit 视频通话 PiP，原生显示真实远端 WebRTC 帧。音频通话使用应用内小窗；后台音频复用系统音频会话。后台摄像头仅在实际设备支持时保持，不支持则暂停采集，返回前台恢复原开关。

详细平台限制、原生实现与实机清单见 [PiP 验证](../../docs/call-pip-platform-validation.md)。iOS 代码尚需 macOS 编译及 iPhone 验证。

## 通话记录与边界

通话结束先保存现有 901 聊天记录及账号隔离的最近通话缓存。应用的 [最近通话模块](../../lib/pages/mine/secondary/calls/README.md) 接管 Chat HTTP 同步、待上报队列、通知、分页及本设备隐藏记录。

信令仍为 SDK online-only；本轮未实现服务器离线来电推送、PushKit/CallKit 或群通话媒体房间。群入口安全拒绝，不进入未实现的连接流程。服务端通话记录接口需在相应后端部署后联调。

RTC 凭证继续通过现有 `POST /user/rtc/get_token` 获取，提交 `room/identity` 并使用 Chat token 鉴权。当前服务端返回 `data.token/serverUrl`；公共 `SignalingCertificate` 将 `serverUrl` 映射到客户端已有的 `liveURL`。非空旧字段 `liveURL` 优先，缺省或空白时回退；`roomID` 缺省时绑定请求房间，服务端返回其他房间、缺少凭证或字段类型错误仍拒绝连接。不会改用 99chat 的另一套信令接口。

## 等待音频

对照 99chat `LiveKitCallRingtone` 来电/回铃分离与接听/终止时停止的行为，继续复用 `just_audio` 和现有来电 WAV。
呼出回铃使用本模块原创的 `outgoing_ringback.wav`，为 425 Hz、1 秒响/4 秒停的循环纯音，文件开头即有首音；
客户端只装载静态资源，不在界面线程合成或下载音频。包清单只登记 WAV，不打包生成脚本和维护文档。

权限检查、在线邀请发送和 RTC 证书都成功后才异步启动回铃，不等待装载完成阻塞媒体连接；
音频装载/播放失败只记精简日志，不使正常通话失败。来电只播放原来的来电铃，不能误播呼出回铃。
接听、接通、拒绝、取消、超时、媒体错误、退出账号及控制器销毁都会使本次音频失效。
对方响应在信令派发前标记，迟到的证书/房间回调不能重新响铃；旧房间响应不能停止新房间的回铃。

`CallRingtone.stop/dispose` 不排在原生装载之后，立即使代次失效并停止/销毁播放器。
播放器关闭自动音乐会话配置：Android 仅设置该播放器的通信提示音/通知铃声音频属性，系统决定实际音量流和路由；
iOS 仅激活当前会话，不覆盖 RTC 的类别、麦克风、听筒、扬声器或蓝牙，也不在停止音效时停用 RTC 会话。
此播放器不独立抢占/释放 Android 音频焦点；RTC 启动前的 iOS 音频类别可能为默认 SoloAmbient。

定向验证入口为 `flutter test --no-pub test/pages/chat/calling/ringtone`，28 项测试通过。
覆盖 PCM 首音/节奏、重复启动、装载中停止、迟到重启、错误恢复、实际控制器邀请/证书边界及账号退出。
测试使用本地平台/HTTP 模拟，不开启摄像头或真实 RTC；Android/iPhone 实际声音、静音开关、听筒/外放/蓝牙和焦点交接仍需手机验证。

## 回归

应用根目录运行 `flutter test --no-pub test/pages/chat/calling test/pages/mine/calls`。测试模拟 SDK、平台通道与 HTTP，不拨打真实电话。覆盖重复接听/结束、超时、迟到结果、释放屏障、发布失败清理、PiP 会话隔离、日夜布局及账号记录隔离。实际两端通话、蓝牙/听筒、锁屏、弱网及后台系统行为需真机验收。
