# 99chat 群功能页面预览

这些图片由应用实际页面生成，数据来自独立测试 fixture，便于核对迁移效果。生产页面只使用 SDK 与业务接口的真实数据。

参考源码：`E:/openim/reference-99chat`，提交 `d7c3c65`。

| 预览 | 图片 |
| --- | --- |
| 三个模块同时显示的聊天页 | [Android 浅色](chat-android-light.png)、[Android 深色](chat-android-dark.png)、[iOS 浅色](chat-iOS-light.png)、[iOS 深色](chat-iOS-dark.png) |
| 直播创建 | [浅色](live-create-light.png)、[深色](live-create-dark.png) |
| 直播推流信息 | [浅色](live-push-light.png)、[深色](live-push-dark.png) |
| 直播教程弹窗 | [浅色](live-guide-light.png)、[深色](live-guide-dark.png) |
| 直播等待观看 | [浅色](live-waiting-light.png)、[深色](live-waiting-dark.png) |
| 三公浮窗、运营、群配置、规则、代理 | [Android／iOS、320／390 宽、浅色／深色对照](sangong.png) |
| 开奖页面 | [Android 浅色](../mark-six-draws-android-390-light.png)、[iOS 深色](../mark-six-draws-ios-390-dark.png) |
| 代理反水 | [Android 浅色](../mark-six-agent-current-android-390-light.png)、[iOS 深色](../mark-six-agent-current-ios-390-dark.png) |

直播图使用 99chat 原图，三公和六合彩直接迁移其页面结构。三个模块保留本应用的身份验证、主题、消息与支付组件。截图测试使用微软雅黑显示中文；应用本身的字体未改动。

## 重建预览

在仓库根目录依次运行，避免多个 Flutter 任务同时写构建缓存。

```powershell
$env:EXPORT_GROUP_FEATURE_PREVIEW='1'
flutter test --no-pub test/pages/group_features/group_chat_feature_surface_test.dart
Remove-Item Env:EXPORT_GROUP_FEATURE_PREVIEW

flutter test --no-pub test/pages/group_features/live/live_widgets_test.dart --dart-define=GROUP_LIVE_PREVIEW=E:/openim/openim-flutter-demo/docs/previews/group-features/live

flutter test --no-pub test/pages/group_features/live/live_obs_guide_test.dart --dart-define=GROUP_LIVE_GUIDE_PREVIEW=E:/openim/openim-flutter-demo/docs/previews/group-features/live-guide

flutter test --no-pub test/pages/group_features/sangong/sangong_preview_test.dart --dart-define=SANGONG_PREVIEW=E:/openim/openim-flutter-demo/docs/previews/group-features/sangong.png

$env:EXPORT_MARK_SIX_PREVIEW='1'
flutter test --no-pub test/pages/group_features/mark_six/mark_six_preview_test.dart
Remove-Item Env:EXPORT_MARK_SIX_PREVIEW
```

业务接口与尚未迁移的差异见 [模块说明](../../../lib/pages/group_features/README.md)。
