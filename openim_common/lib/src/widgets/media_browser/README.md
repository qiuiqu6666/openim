# 媒体预览子组件

`media_page_gesture.dart` 统一新旧图库的翻页方向判定：仅单指横向位移大于纵向位移的 1.5 倍时接受翻页，斜向阅读和双指手势留给图片处理。复用 ExtendedImage 的手势竞争机制；参考 99chat 长图优先纵向阅读的交互。回归覆盖斜向长图滚动后继续横向翻页。

`../photo_browser.dart` 保留公开 `MediaBrowser`/`VideoPlayerView` 入口，并兼容导出 `media_source.dart` 中的 `MediaSource`。

- `local_media_availability.dart` 是每个浏览路由独有的异步文件存在性缓存，原图和网格共用一次检查；来源更新重新检查缺失或未完成的文件，已失效请求不能写入新缓存；关闭页面释放缓存，异步结果不直接写页面状态。
- `media_grid_thumbnail.dart` 优先缩略图，按格子逻辑尺寸 × DPR 及 `ResizeImagePolicy.fit` 限制解码；全屏缩放仍使用原质量图片。
- `MediaSource.loading/onRetry` 可选参数供受保护、内存媒体显示独立加载/失败状态。不会替调用方请求受保护资源，默认行为兼容现有调用。
- 浏览页持有唯一页控制器，媒体字节升级不会重置当前页；网格选择显式跳转到对应页。
- `adaptive_media_image.dart` 统一网络、文件和内存原图的全屏适配及双击缩放。参照 99chat `image_preview_resolution_utils.dart` 的 2.2 高宽比阈值，长图超出视口高度时按可用宽度展开、从顶部阅读；其他图片等比例完整居中。缩放上限相对阅读尺寸计算，超长图不受原有固定 3 倍上限限制，双指仍可缩回整图。根据实际布局约束重新适配横竖屏，保留等比例解码、图库翻页与拖动退出能力，网络预览遵循下述像素预算。旧头像预览和收藏全屏也复用此组件，各业务继续持有资源访问权限和保存流程。

长图惯性沿用现有 `ExtendedImage` 手势：按阅读视口高度的 1.25 倍设置松手后的滑行距离（400–1200 逻辑像素），避免依赖库默认的 100 像素使超长图必须反复拖动。99chat 的 `image_preview_resolution_utils.dart` 同样显式增强惯性（400）；这里按现有按宽展开的阅读视口适配。慢速拖动仍跟手，不调整会同时影响缩放的 `speed`；再次触摸停止滑行、图片边界限制、图库翻页与缩放继续由原组件处理。普通图片保留原有惯性。

接近屏幕比例的图片保持 `contain` 的 1 倍初始缩放：仅当图片高宽比达到 2.2，且按宽展开后的高度超过当前视口高度 20% 时，才自动进入长图阅读。否则轻微自动放大会触发 ExtendedImage 的“缩放时禁止滑出”条件，导致手机截图无法上下滑动退出。该规则由共享 `AdaptiveMediaImage` 执行，网络、文件、内存图片及旧版预览都生效。实际手势回归覆盖上下退出、短拖取消后再次退出、放大后平移/还原退出、图库翻页、小屏/横屏/平板、1×1、8192×1、1×8192、4096×4096 及长图边界；保留长图阅读时不误退出的行为。大尺寸测试验证布局与手势，不代表所有真机的原图解码内存上限。

自适应尺寸与手势回归见 `test/widgets/media_browser/adaptive_media_image_test.dart`：普通横竖图、方图、小图、全景图、网络/文件/内存长图、旧预览原图、竖向阅读、Android/iOS 长图惯性和边界、慢拖与触摸停止、左右翻页、双击和视口变化。

`../photo_browser_hero.dart` 在飞行动画期间保留全屏图片子树，避免动画结束时重新执行文件检查、解码并闪回加载占位；飞行副本使用独立子树，快速返回仍交由原有 Hero 处理。网络加载占位也复用 `AdaptiveMediaImage`，缩略图和原图按相同规则从长图顶部显示，使用与预加载一致的缓存配置。逐帧交接、动画中返回和缩略图升级的回归见 `test/widgets/media_browser/media_browser_transition_test.dart`。

`media_action_sheet.dart` 只组装媒体的可用操作，复用程序共享的
`AppAction` / `showAppActionSheet`，不另画底部菜单。外观对照 99chat 的
`media_preview_chrome.dart` 和 `media_preview_video_chrome.dart` 的手机菜单：
独立取消、保存/转发与红色删除，随系统亮暗主题切换。

`MediaBrowser.onViewInChat` 是可选消息定位回调，`IMUtils.previewMediaFile`
保留同名透传参数。菜单打开时固定媒体索引和来源身份；取消、页面关闭或
来源替换不执行业务。选择“在聊天中查看”先关闭菜单和媒体路由，再由
原聊天调用既有消息定位能力。没有原聊天消息的头像等预览不传该回调。
保存与转发只关闭菜单，删除继续关闭预览并交给原调用方处理。

菜单回归在应用 `test/widgets/media_browser/media_browser_actions_test.dart`，覆盖亮暗主题、Android/iOS、滑动及网格选择后的索引、回调前关闭预览、取消、来源替换和新页面覆盖保护。

文件与手势回归见 `test/widgets/media_browser/media_browser_availability_test.dart` 及既有 `media_browser_swipe_test.dart`、`media_browser_grid_test.dart`。涉及实际文件的 Widget 测试需让 `runAsync` 等待系统 IO；不能仅靠 FakeAsync 的帧时间推进。

`photo_browser.dart` 仍包含既有桌面/移动视频入口和全屏手势，超过 800 行。来源契约、异步路径检查、网格缩略图和菜单组装已拆出；共享弹窗归公共 `action_sheet`，消息定位归应用聊天媒体模块。本次浏览器只增加参数和委托，保留播放器生命周期。后续整理边界是将 `VideoPlayerView` 独立到此目录，并保留原公开导出。

查看器只请求当前页原图与缩略图；切页/退出主动取消所属 HTTP 请求并释放图片缓存，不再预加载沿途所有原图。网络原图按 16M 像素、缩略图按 1M 像素限制解码并保持比例（保存仍使用原文件）。原生/桌面视频成功串流后不再额外下载整段视频，iOS 串流失败的下载播放回退保留。
