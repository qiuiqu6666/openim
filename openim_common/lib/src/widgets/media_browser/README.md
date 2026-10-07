# 媒体预览子组件

`../photo_browser.dart` 保留公开 `MediaBrowser`/`VideoPlayerView` 入口，并兼容导出 `media_source.dart` 中的 `MediaSource`。

- `local_media_availability.dart` 是每个浏览路由独有的异步文件存在性缓存，原图和网格共用一次检查；来源更新重新检查缺失或未完成的文件，已失效请求不能写入新缓存；关闭页面释放缓存，异步结果不直接写页面状态。
- `media_grid_thumbnail.dart` 优先缩略图，按格子逻辑尺寸 × DPR 及 `ResizeImagePolicy.fit` 限制解码；全屏缩放仍使用原质量图片。
- `MediaSource.loading/onRetry` 可选参数供受保护、内存媒体显示独立加载/失败状态。不会替调用方请求受保护资源，默认行为兼容现有调用。
- 浏览页持有唯一页控制器，媒体字节升级不会重置当前页；网格选择显式跳转到对应页。
- `adaptive_media_image.dart` 统一网络、文件和内存原图的全屏适配及双击缩放。参照 99chat `image_preview_resolution_utils.dart` 的 2.2 高宽比阈值，长图超出视口高度时按可用宽度展开、从顶部阅读；其他图片等比例完整居中。缩放上限相对阅读尺寸计算，超长图不受原有固定 3 倍上限限制，双指仍可缩回整图。根据实际布局约束重新适配横竖屏，保留原图解码质量、图库翻页与拖动退出能力。旧头像预览和收藏全屏也复用此组件，各业务继续持有资源访问权限和保存流程。

自适应尺寸与手势回归见 `test/widgets/media_browser/adaptive_media_image_test.dart`：普通横竖图、方图、小图、全景图、网络/文件/内存长图、旧预览原图、竖向阅读、左右翻页、双击和视口变化。

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
