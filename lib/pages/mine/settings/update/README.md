# 升级弹窗

参照 99chat 的 `lib/src/widgets/app_dialog.dart` 中专用图片升级弹窗，复用其 `assets/images/renew.webp`。此目录负责主题、布局、关闭与更新按钮状态；版本检查继续由 `widgets/platform_update.dart` 调用现有 Chat 平台配置接口。

可选升级提供右上角关闭按钮，下载页成功打开后关闭。强制升级不提供关闭按钮，系统返回与遮罩不关闭，点击立即更新后保留弹窗。失败在弹窗内提示，进行中的更新不能重复点击。

同一根 Navigator 上的升级弹窗共用进行中的 Future，避免自动和手动检查叠加。显示前校验下载地址，无效地址不呈现强制升级弹窗。

说明优先展示平台配置的 `changelog`，未配置时展示目标版本。复用 AppTokens、SettingsResponsive 与 Flutter 按钮；暗色模式使用原版调色与渐变。正文可滚动，更新按钮保持可见。未接入其他仓库的下载器或新增后台升级接口。
