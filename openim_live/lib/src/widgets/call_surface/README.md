# 全屏通话外观

`CallFullScreenSurface` 为单聊通话浮层提供独立背景和局部主题。日间、夜间均使用 99chat 的 `#2D2D2D` 通话底色，文字复用公共 `AppTokens.onAccent`，次级文字使用其 72% 透明度。普通聊天页的 `surface` 不再决定通话底色。

系统栏复用 `AppSystemBars`，只在全屏分支中设置浅色系统图标。切换应用内小窗、系统 PiP 或结束浮层时，该注解随组件移除，底层页面恢复自己的系统栏样式。

`pages/single/widgets/controls.dart` 使用同一套通话前景色，按钮仍复用现有 `LiveButton`。六个按钮原图来自参考仓库 `assets/call_ui/`，存放在公共包同名资源目录，由 `ImageRes` 管理路径。启用态使用浅色圆形按钮与深色图案，关闭态使用深色圆形按钮与浅色图案；不对原图统一染色。

本模块不持有信令、媒体轨道、账号或通话状态，也不改变现有响应式布局、接听、挂断和设备切换回调。

测试归属：`test/pages/chat/calling/appearance/call_appearance_test.dart`。它使用真实控件和 PNG 资源验证主题、状态、图标、系统栏、窄屏及字体放大；实际两端通话与系统 PiP 仍需设备验收。
