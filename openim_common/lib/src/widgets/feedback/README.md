# 全局提示的点击行为

继续使用现有 EasyLoading 和 `IMViews.showToast`，不创建第二套 Toast。

- `AppView` 初始化时调用 `configureEasyLoadingInteractions()`：取消全局强制拦截开关，交由每次展示的 mask 决定。
- 默认 `clear` mask 保持加载/进度提示的透明遮罩与点击拦截。
- `IMViews.showToast` 显式使用 `none` mask、关闭点击消失，显示期间页面可操作。
- 淡入淡出动画中的 `IgnorePointer` 让提示框本体也透传点击；仅设置 `none` mask 只能解决提示框外的区域。颜色、原有内容样式、动画和定时消失仍由 EasyLoading 实现。
- 原库 status 文本统一最多三行，超长内容显示省略号，避免异常堆栈撑满提示。可用区域考虑安全区和键盘，各边取两者的较大值，不叠加扣除。
- 动画只限制内容的布局宽度，让原库的 Column 按自然高度布局；可用高度不足时通过 `FittedBox(scaleDown)` 缩小整个内容，避免横屏、大字号或键盘下的 RenderFlex 溢出。正常空间不放大或缩小内容，不改变字号配置。全屏 mask 独立保持模态行为。
- 不在异步 Toast 前后修改、恢复全局 `userInteractions`，避免连续提示或加载时相互污染。

测试：`test/widgets/feedback/toast_interaction_test.dart`，覆盖日夜主题、淡入/显示/淡出期间内外点击、覆盖区域滚动、后续加载与进度的拦截、替换提示的消失时间，以及长异常堆栈在窄屏、二倍字号、短横屏与键盘下的尺寸边界。Android/iOS 真机点击与滑动仍需验收。
