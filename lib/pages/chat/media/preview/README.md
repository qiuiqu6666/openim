# 长截图顶部预览

`ChatTopPicturePreview` 为相册、相机发送流程生成独立顶部预览，接入现有
`ChatMediaUpload` 和认证上传，不替换完整附件，也不依赖对象存储的裁剪参数。
宽高比超过 1:1.8 的静态图片取顶部 1.8 倍宽度，缩至最多 480×864，
PNG 保留文字边缘及透明度；使用独立 isolate，跨批次最多一个准备任务。
原图、完整大图 URL 保留，只有 snapshot 指向实际裁剪结果。

协议位于公共包 `models/media/chat_picture_preview_metadata.dart`：把版本、
类型、原图及预览 URL 合并到 SDK `Message.ex`，保留其他扩展字段。
接收方严格核对协议、URL 与尺寸；没有有效标记的旧消息沿用原有清晰度策略。
旧客户端、SDK 直接发送等未走该上传流程的消息不会自动获得新预览。
完整查看、保存、转发继续使用完整附件，气泡与引用预览优先使用顶部小图。

GIF（包括实际内容为 GIF 但文件名不符）、多帧文件、超过 32 MiB 文件或
32 MiPixels 图片不生成预览。编码、预览上传或扩展字段解析失败时保留原发送
路径；预览只写入自有临时目录，上传完成或取消后清理。账号失效后不发布部分
媒体 URL，已接受发送任务的页面退出语义仍由 outbox 控制。

测试：`test/pages/chat/media/preview/` 验证像素、透明度、方向与原件保留；
`test/pages/chat/media/upload/chat_top_picture_upload_test.dart` 验证 SDK 上传、
失败降级和取消；`test/widgets/chat/picture/` 验证协议及真实解码。
