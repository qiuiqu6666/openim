# iOS 音量观察与音频会话所有权补丁

来源：pub.dev `volume_controller 3.4.0`。保留上游许可证及所有平台运行代码；`upstream-sha256.json` 记录复制时的逐文件哈希，`patches/audio-session-ownership.patch` 可直接审阅本地差异。

Xcode 运行时调用栈确认：原版 `applicationWillEnterForeground` 在主线程调用 `setActive(true)` 和 `setCategory(.playback, .mixWithOthers)`，触发 `AVAudioSession Hang Risk`。原版音量查询、KVO 订阅及取消也会激活、修改或关闭共享音频会话。这会越过播放器、CallKit 和 WebRTC 的音频所有权。

本补丁仅修改 iOS 三个文件：

- 音量查询只读取真实 `AVAudioSession.outputVolume`。
- 前台恢复只向已有订阅者通知最新音量，不主动激活或改 category。
- 订阅/取消只管理 KVO，不激活、关闭或修改会话；KVO 回调切回主线程再发送 Flutter 事件。

播放器、录音和通话仍负责其自身音频会话；不把 CallKit/WebRTC 调用搬到后台，也不抢占或提前关闭它们。`MPVolumeView` 调节音量和 Dart API 保持原版，其余平台源码保持上游哈希。

应用根 `pubspec.yaml` 使用路径 override，不修改本机 pub 缓存。播放尚未激活时 `outputVolume` 的更新时机由 iOS 决定；不能通过激活共享会话来强制刷新观察值。实际物理音量键、蓝牙、录音和通话切换仍需真机验收。

验证：`python3 ios/tests/Volume/run.py <已启动模拟器UDID>` 编译运行生产原生类，检查前台恢复、音量查询、监听、取消不会改变共享会话 category/mode，并核对监听注册、取消、初始事件及主线程事件。iOS 27.1 模拟器已通过；测试宿主不播放音频，不改变系统音量，不代表硬件音频链路已经验收。
