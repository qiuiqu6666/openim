# 好友扫一扫

`FriendQrScanner` 是通讯录及个人二维码页的 Stateful 兼容入口，复用
`lib/widgets/qr_scanner/QrScannerPage<Map<String, String>>`。共享界面参考
`reference-99chat/lib/src/qr_code_scanner_page.dart` 的全屏相机、提示、扫描网格、
闪光灯和底部入口。短屏、横屏和放大字体会调整扫描区域以保留操作空间。
亮暗主题均使用沉浸式深色相机界面；视觉参数归公共 `QrScannerTokens`。

- `friend_qr_scanner.dart`：仅注入原有 `parseFriendInvite`、好友错误文案及
  `friend-qr-*` 操作键，保留旧 Widget/State 身份和公开入口。
- `widgets/friend_qr_scanner_overlay.dart`：保留旧布局别名、Overlay 类和导入路径，
  实际布局、遮罩、扫描框、动画及操作组件归共享目录。
- `friend_qr_gallery_service.dart`：`FriendQrGalleryService` 兼容别名指向共享
  `QrGalleryService`，既有构造和测试子类仍可使用。
- 共享页面拥有相机订阅、串行原生命令及前后台/路由状态；页面被覆盖、
  相册识别或查看个人二维码时暂停相机，返回后恢复。原生选图或识别结果
  先于前景恢复时等待恢复后处理；关闭页面取消等待。图库仍使用现有
  `image_picker` 与 `compute` 内的纯 Dart ZXing 解码，不解释业务数据。
- 相机和相册结果均经公共 `parseFriendInvite` 校验，仅返回合法好友邀请；
  调用方继续验证当前登录账号与令牌后打开好友资料。
- “我的二维码”通过调用方提供的异步回调导航，避免扫码页依赖个人资料页。
  相机控制器由 `QRView` 释放；页面只释放订阅、定时器与动画控制器。

此模块只处理好友邀请码。钱包可复用共享界面，但保留自己的协议与入口；
共享层不依赖好友或钱包模块。控件和提示支持简繁中文、英语、日语、韩语。
测试位于 `test/pages/contacts/scanning/`；原生通道假实现位于
`test/support/contacts/native_qr_scanner.dart`，实际设备相机及相册权限需另行验收。

可选预览设置 `FRIEND_QR_SCANNER_PREVIEW` 为输出 PNG 的完整路径，运行 UI 测试；
保留原并排预览，同时在相同目录导出 `friend-qr-scanner-light.png` 与
`friend-qr-scanner-dark.png` 两张真实页面。
