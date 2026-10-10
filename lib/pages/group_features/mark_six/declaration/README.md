# 本群宣言

`MarkSixDeclarationPanel` 由开奖页的「本群宣言」tab 挂载，文案和布局对照 99chat `lib/src/pages/settings/lottery_dashboard.dart` 的宣言区域（Apache-2.0）。固定显示完整宣言、右侧标语和底部说明，不依赖接口中的 `declaration`。

复用 `MarkSixStyle` 的亮暗主题与现有喇叭图片。下载链接使用父页面传入的 `MarkSixRepository` 读取 `/chat/platform`，优先 `downloadURL`，回退 `officialURL`；加载时禁用点击，失败或为空可重试，成功点击复制。组件不拥有仓储；异步响应检查 mounted 与当前账号上下文，退出后不更新状态。

入口、亮暗主题、Android/iOS 与窄屏回归位于 `test/pages/group_features/mark_six/mark_six_widget_test.dart`。实际页面预览沿用 `mark_six_preview_test.dart`。
