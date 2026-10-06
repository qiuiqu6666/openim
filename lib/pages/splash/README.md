# 启动页

`splash_view.dart` 仍通过现有 GetX 绑定取得 `SplashLogic`，初始化订阅、自动登录和进入登录页/首页的流程不变。`widgets/splash_artwork.dart` 只负责显示启动画面，不执行网络请求，也不增加等待时间。

启动图来自 99chat `d7c3c65` 的 `assets/splash_new.webp`，原图保存在 `assets/splash_99chat.webp`。按参考 `lib/src/launch_page.dart` 居中、等比铺满整个视口，亮暗主题共用同一品牌图，复用 `AppSystemBars` 处理透明系统栏和浅色图标。图片裁切遵循 `BoxFit.cover`，不拉伸，也不在图上额外叠加内容。

原生启动资源位于 Android `res` 和 iOS `LaunchScreen.storyboard`/启动图片集；配置入口是根目录的 `flutter_native_splash.yaml`。更新原生资源时保留已有系统栏、通话和平台配置，不能直接用生成器覆盖整个原生目录。Android 12 及以上的系统阶段采用品牌蓝底和透明占位图，随后进入 Flutter 全屏启动图；Android 12 以下按参考原生配置使用 `bitmap gravity="fill"`，与 Flutter 的等比裁切可能存在比例差异。iOS 原生启动图使用 `scaleAspectFill`。

宽屏沿用参考的居中铺满规则，会裁切原图上下部分，底部 `99CHAT` 字样可能不可见。没有迁移参考仓库的远端启动图服务；当前启动图完全来自打包资源。

自动登录回归位于 `test/pages/splash/splash_startup_test.dart`。原生启动资源修改后需要重新构建；iOS 启动屏需在 macOS/Xcode 和 iPhone 上确认。

2026-10-05 验证：自动登录回归 1/1 通过；实际 `SplashArtwork` 在 390×844 亮/暗、320×640、1024×768 四种视口渲染无异常，透明系统栏样式使用浅色图标；修改范围静态检查通过；Android x86_64 调试 APK 构建通过。原生 PNG 与源 WEBP 逐像素一致，亮暗竖屏预览一致。尚未实测 Android 冷启动帧衔接及 iOS 编译/真机启动。
