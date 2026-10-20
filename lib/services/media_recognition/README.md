# 预览图片识别

图片预览打开更多菜单时，由 `MediaImageRecognition.start` 建立一次识别请求。
公共包负责菜单、复制和生命周期；应用层负责本地识别、分类和业务跳转。
视频不启动图片识别，原有菜单动作不变。

- `media_image_file.dart`：本地文件、内存图片和已有缓存优先；缺失时限量下载原图。
  取消时关闭自身网络连接，只清理自己创建的临时文件。
- `media_image_recognition_host.dart`：复用 `QrGalleryService`；通过本地
  `qr_image_decoder` 插件提取文字，不上传图片。结果受菜单生命周期和账号保护。
- `media_recognition_parser.dart`：复用好友／群邀请解析、HTTP(S) 链接解析和
  TRON Base58Check 校验。多码分别展示、去重；不修正地址字符，不执行任意二维码指令。
- Android 使用随包提供的 ML Kit Latin 识别模型，iOS 使用 Vision。
  两端 OCR 实现在 `local_plugin/qr_image_decoder`，需完整重建安装，热重载不生效。
  OCR 不可用时仍保留成功的二维码结果，不显示失败提示；重新打开菜单时再次识别。

参考了 99chat `qr_code_scanner_page.dart` 的群／好友结果分流和钱包地址校验流程。
本菜单由当前产品需求扩展，不声称 99chat 已有同款预览菜单。
TRON 地址只提供复制；不会发起转账。群／好友入口打开资料页，保留现有申请流程。

验证：`test/services/media_recognition/` 及
`test/widgets/media_browser/media_browser_actions_test.dart`。
原生构建：Android `:qr_image_decoder:assembleDebug`；iOS 需 macOS/Xcode 验证。
