# 通话背景与图标修复验收

日期：2026-10-05。范围：用户截图中的单聊音频呼出页面背景、文字及操作图标；保留现有通话状态、媒体、响应式布局和小窗链路。

## 原因

此前补齐通话功能时，全屏 `SignalState` 背景从独立深色通话底色改成普通页面的 `Theme.colorScheme.surface`。日间 `surface` 是白色，而旧扬声器关闭资源仍是浅色图案和半透明浅色底，所以图标加载成功却在白底上不可辨认。`LiveButton.foreground` 只修改文字，并不染色 PNG/WebP，因此把按钮文字改为深色并不能修复图标。

这不是 SDK 音频路由、网络或对方头像数据造成的。原资源路径能加载，视觉颜色契约发生了变化。

## 修复

- 全屏背景由独立 `CallFullScreenSurface` 管理，日夜统一 `#2D2D2D`，姓名和操作文字复用公共白色 token，提示为白色 72%。参照当前 99chat `livekit_call_page.dart` 的深灰底色；当前响应式控件布局保留，并非重新复制整个参考页面。
- 麦克风开/关、扬声器开/关、挂断和接听共六个 PNG 直接复用参考仓库原图。启用态为浅底深图案，关闭态为深底浅图案，六个 SHA256 与源文件逐一一致。资源由公共包 `pubspec.yaml` 注册、`ImageRes` 统一引用，现有 `LiveButton` 及媒体回调继续使用。
- 系统栏复用公共 `AppSystemBars` 的局部注解。全屏显示浅色系统图标；应用内小窗和系统 PiP 分支不包裹该组件，移除全屏时释放样式，普通页面主题仍由页面持有。
- 本轮没有修改 SDK 信令、LiveKit 发布、拨号、接听、挂断、权限、超时或 PiP 平台实现。

归属及参考授权见 `openim_live/lib/src/widgets/call_surface/README.md`、`docs/third-party-assets.md` 和 `docs/licenses/99chat-APACHE-2.0.txt`。

## 验证

运行 `flutter test --no-pub --dart-define=CALL_APPEARANCE_PREVIEW=true test/pages/chat/calling test/pages/mine/calls`：**130 项通过**，包含本轮新增 18 项视觉回归。

新增测试真实解码六个生产 PNG，按 alpha 合成后的按钮/背景及图案/按钮对比验证可辨认性；使用实际 `ControlsView` 和全屏组件绘制并检测每个按钮的像素，覆盖呼出等待、连接中、来电、接通的日夜主题。还覆盖 320px 宽度、2 倍文字、上下安全区、真实麦克风/扬声器回调及 on/off 资源、全屏局部系统栏注解移除。

既有真实 `SignalState` 测试覆盖连接中禁止重复接听、终态禁止操作、取消后迟到权限/凭证结果失效，以及 PiP 拒绝/超时后的摄像头暂停和恢复。

对本轮生产文件及新增测试执行定向静态检查：没有 error 或 warning；仅 `call_state.dart` 的原有单行 `if` 花括号格式 info。Android `flutter build apk --debug --no-pub` 成功，独立保留包：

`build/app/outputs/flutter-apk/app-call-appearance-debug.apk`

- 大小：383266505 字节。
- SHA256：`E24B689924CA2D7D2CCD90EAC7EAE1AC331FCDF8F9C71B74331AA23324611BA2`。

## 实际组件预览

以下由 Flutter 测试绘制真实组件和生产资源导出，为本地页面预览，未拨打真实电话：

- [日间呼出](previews/call-appearance-light-waiting.png)
- [夜间呼出](previews/call-appearance-dark-waiting.png)
- [静音与扬声器关闭](previews/call-appearance-muted-speaker-off.png)

三张图已逐一检查：深灰底、浅色文字、扬声器图案和开关态可见。日夜呼出图相同是预期行为，通话具有独立深色表面。系统栏平台图标仅验证注解参数，Flutter widget 光栅预览不绘制实际系统状态栏。

尚未完成：更新包安装后的 Android 真机两端通话、实际听筒/扬声器和蓝牙切换、实际系统 PiP 恢复、iPhone 系统栏及视频通话背景验证。本环境不能编译 iOS；不以组件预览替代上述设备验收。

## 测试资源缓存说明

首次新增依赖包资产时，旧 `build/unit_test_assets` 清单没有包含该目录。参考图片复制保留了早于清单的修改时间，Flutter 测试增量判断未触发重建，产生资源找不到的失败。将六个新资源的修改时间更新后，测试工具重新生成资产清单，六个文件内容不变，解码及页面测试通过。后续新增依赖包资源如遇同类情况，应先核对测试资产清单和增量缓存，不要修改生产路径来绕过。
