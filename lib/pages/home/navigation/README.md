# 首页液态玻璃底部导航

本模块负责首页五个入口的玻璃外观、选中指示和底部布局。导航仍使用 `PersistentTabView` 提供的 `NavBarConfig`；标签、图标、未读数据和点击回调来自原有首页配置。

## 文件与边界

- `glass_bottom_nav_bar.dart`：圆角玻璃底栏与滑动选中胶囊。
- `home_navigation_tokens.dart`：本模块的尺寸、颜色、透明度和阴影。
- 上级 `glass_bottom_nav_bar.dart`：兼容导出，原有引用无需迁移。
- 公共 `LiquidGlassSurface` 与 `NavigationGlassController`：复用项目已有玻璃渲染和偏好管理，通过可选的 `opacity` / `preferLiquid` 参数支持首页；其他页面保持原有默认行为。

底栏内容高度为 56，水平留白为 12，圆角为 28。底部安全区只计算一次，因此会话多选操作条替换底栏时仍保持原来的占位高度。首页已有的导航覆盖配置让列表可以滚入玻璃背后，不添加新的导航或数据来源。

## 渲染与交互

首页在自动模式下也请求液态玻璃，并使用共享控制器的单次初始化机制。Android 不再因自动模式直接跳过首页的液态渲染。用户明确选择普通半透明模式、系统高对比度或减少动画，以及渲染器初始化失败时，继续使用公共组件的回退策略。亮色、暗色分别使用 0.44、0.40 的表面透明度；高对比度沿用公共组件的不透明背景。

选中胶囊使用 220 毫秒平滑移动，支持从右到左的布局；减少动画时即时切换。胶囊忽略点击事件，由原有导航按钮接收点击。未读数字所在的固定图标区域限制为正常字号，避免系统大字体把紧凑徽标裁切；页面正文继续使用系统文字缩放。

参考了本地 `reference-99chat/lib/src/pages/home_page.dart` 的五个入口和导航行为。该参考实现使用普通底栏，本次液态玻璃效果按用户的新要求实现。

## 验证（2026-10-05）

- 6 个修改相关 Dart 文件静态检查通过。
- 导航、公共玻璃、安全区、系统栏和真实首页多选操作条共 61 项测试通过。最后一轮中 57 项先通过；首页测试因并行开发中的群缓存方法暂缺未能编译，方法补齐后单独重跑的 4 项通过。
- 覆盖 Android / iOS 的亮暗主题、五个入口点击、未读 8 / 99+、大字体、安全区、选中移动、减少动画、初始化失败回退及列表滚动位置。
- 实际玻璃着色器初始化和栅格化通过，未使用伪造的就绪状态。导出 9 张实际组件预览至 `build/home-liquid-glass-preview/`；预览列表使用测试数据，并非线上会话截图。
- Android 调试包构建成功。未安装、未部署；真机观感和性能仍需在设备上复测。

测试记录：`build/home-liquid-glass-final-tests-20261005.log`、`build/home-liquid-glass-edit-host-final-tests-20261005.log`、`build/home-liquid-glass-navigation-tests-20261005.log`。构建记录：`build/home-liquid-glass-build-20261005.log`。

最终调试包：`build/app/outputs/flutter-apk/app-debug-home-liquid-glass-20261005-b03433399736.apk`。

SHA-256：`b03433399736e2d02b346fb4909f3685cae18d5391dad7f2bdf08b9ae45e86bf`。
