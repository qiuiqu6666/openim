# 群直播投屏

对照 `reference-99chat` 的 `group_live_cast_service.dart`、
`group_live_cast_button.dart` 和 `GroupLiveAirPlayViewFactory.swift`，复用现有播放器。

- Android：`LiveCastService` 经 `openim_group_live_cast` 通道调用
  `LiveCastBridge`，打开系统投屏设置；仅系统投屏设置/厂商 Wi-Fi Display 设置
  真正打开才算成功。缺少入口、权限拒绝或桥接未注册时显示可操作的提示。
- iOS：`LiveCastButton` 内嵌系统 `AVRoutePickerView`，优先显示视频设备。
  当前 `video_player_avfoundation` 使用 `AVPlayer`，未禁用其默认允许的外部播放。
  实际可用设备、协议和视频格式由系统与接收设备决定；等待开播时可选择路由，
  屏幕镜像仍由系统控制中心管理。
- web/桌面：隐藏当前未支持的应用内投屏入口。

投屏桥接不建立独立播放器，不抓取或缓存播放签名，不接收或手动转发播放 URL，
不造设备列表，不申请额外权限。外部播放传输由系统 AVPlayer/AirPlay 管理。
Android 从系统设置返回仍由现有播放器生命周期
恢复播放。`onError` 可注入业务提示/测试，默认使用现有 `IMViews.showToast`。

两个平台的原生代码分别在
`android/app/src/main/java/io/openim/live/LiveCastBridge.java` 与
`ios/Runner/LiveCasting/LiveAirPlayViewFactory.swift`，后者已加入 Xcode Runner Sources。
可运行回归位于 `test/pages/group_features/live/casting`；设备发现与视频实际到达
接收端需使用同一网络下的真机/电视验证。

原生接口依据：
[Android ACTION_CAST_SETTINGS](https://developer.android.com/reference/android/provider/Settings#ACTION_CAST_SETTINGS)、
[AVRoutePickerView](https://developer.apple.com/documentation/avkit/avroutepickerview)、
[AVPlayer allowsExternalPlayback](https://developer.apple.com/documentation/avfoundation/avplayer/allowsexternalplayback)。
