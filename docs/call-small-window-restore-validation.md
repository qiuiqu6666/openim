# 应用内通话小窗恢复验收

日期：2026-10-06。用户截图为等待接听中的应用内视频小窗。

## 根因与修复范围

`SignalState` 最小化分支持有恢复全屏的 `onTap` 和拖动 `onPanUpdate`，展示内容由现有 `CallCompactSurface` 管理。等待接听时没有远端轨道，小窗使用 `remote ?? local` 的本地摄像头预览。

当前固定的 LiveKit `2.5.0+hotfix.3` 在移动平台的本地视频 `VideoTrackRenderer` 中内嵌对焦点击 `onTapDown` 和缩放 `onScaleStart/onScaleUpdate`，会参与并赢得与父小窗的手势竞争。点击视频无法调用父层的 `onTapMaximize`，拖动也可能被缩放识别器影响。原有蓝色 `Container` 视频布局测试无法覆盖这类竞争。

当前 OpenIM 工作区未在 GitNexus 中建立索引。本次依据当前生产源码、安装的依赖源码及参考仓库实际实现追踪，没有使用其他仓库的旧索引推断。

修复沿用现有两个组件：

- `CallCompactSurface` 的视频分支通过 `IgnorePointer` 只展示视频，避免对焦、缩放和子层点击参与小窗操作。视频轨道、画面渲染和通话状态仍由原模块持有。
- `SignalState` 应用内小窗外层手势采用 `HitTestBehavior.opaque`，确保小窗完整矩形内可以点击和拖动。命中范围仍受小窗尺寸限制，不覆盖整页；小窗外的页面继续收到点击。

参考仓库 `desktop_call_float_overlay.dart` 对等待时本地视频和接通时远端视频均使用 `IgnorePointer`；`livekit_call_page.dart` 的小视频也由外层统一持有手势。本次复用这一行为，没有引入新的小窗组件或另一条恢复链路。

`onTapMaximize` 继续只修改当前 `SignalState.minimize`，恢复同一通话全屏。SDK 信令、接听、挂断、权限、媒体采集、轨道发布和原生系统 PiP 实现不变。

集成回归另外发现：组件销毁期间 `session.dispose()` 会同步停止 PiP 并通知旧监听，此时 Flutter 元素已退出有效生命周期，仍然进入 `_onPipChanged.setState`。调整为在会话释放前移除 PiP 监听，保留原有会话结束及媒体清理。主动销毁未结束的小窗也纳入回归，不能靠测试提前结束会话掩盖这个问题。

## 平台边界

等待接听尚未配置系统 PiP；截图中的应用内浮窗与原生系统小窗是不同分支。已接通系统 PiP 的原生 `restored` 回调仍调用原 `onTapMaximize`，不额外退出系统 PiP 或再次拨号。

Windows 的 LiveKit 平台判断直接读取 `dart:io Platform`，单独设置 Flutter 目标平台不能让 Windows widget test 进入 Android/iOS 本地视频手势分支。因此回归需要分别验证真实 `SignalState`/轨道组件集成和移动端同型手势竞争，不能声称 Windows 测试模拟了真实手机摄像头。

## 已复现的回归证据

`test/pages/chat/calling/window/compact_gesture_routing_test.dart` 使用实际 `CallCompactSurface`，给视频子层放入与 SDK 移动端相同的 `onTapDown`、`onScaleStart/onScaleUpdate`，父层持有恢复和拖动回调。

修改前运行结果：3 项中 2 项失败。点击视频后恢复次数为 0，拖动更新次数也为 0；点击底部文字可以恢复，说明并非 `onTapMaximize` 本身失效。

仅应用视频 `IgnorePointer` 和外层 `opaque` 两处修复后，同三项测试全部通过：点击调用父恢复且不触发对焦，拖动移动浮窗且不恢复/缩放，底部文字仍可恢复。回归测试断言未降低。

`call_window_restore_test.dart` 另外提供 8 项真实 `SignalState` 集成回归，覆盖音频/视频和等待/已接通。视频使用真实 `LocalVideoTrack`、`LocalParticipant`、`ParticipantWidget`、`VideoTrackRenderer` 及 `Texture`，仅模拟原生 WebRTC 通道；确认小窗视频确实被忽略指针，重复点击画面、文字和圆角边缘能恢复同一全屏组件，拖动不恢复，窗外点击到达底层页面。凭证及连接仍各一次，同一会话/轨道不变，切换过程中不结束会话、不停止采集。另两项主动移除活动音频/视频小窗，验证监听先移除、释放与结束只执行一次。

Windows 原生通道启动与最终释放使用 `tester.runAsync`；状态操作、动画帧和会话断言仍使用测试时钟。集成测试在 body 的 `finally` 中结束并清理 fixture，避免 Flutter 自动卸载后再等待已经退出的 fakeAsync 任务。这不改变生产媒体或点击流程。

运行 `flutter test --no-pub --timeout=60s test/pages/chat/calling test/pages/mine/calls`：**141 项全部通过**，包含上述 11 项新增回归及现有信令、生命周期、系统 PiP、日夜/窄屏布局、图标和通话记录检查。

## 构建

Android `flutter build apk --debug --no-pub` 成功，独立保留包：`build/app/outputs/flutter-apk/app-call-window-debug.apk`。

- 大小：383243552 字节。
- SHA256：`6B4363C2F37B5E4F4812AA74A3C4972C457F2BFBA6B57600D004D8D31E7353D4`。

修改文件与整个 `window` 回归目录的定向静态检查没有 error 或 warning；`call_state.dart` 的单行 `if` 花括号格式 info 为既有项。

尚未完成：安装新包后的 Android 真机小窗点击/拖动及真实两端视频通话、Android 系统 PiP 恢复、iPhone 实际视频手势和系统小窗验证。本环境不能编译 iOS；Windows 组件测试不替代上述设备验收。
