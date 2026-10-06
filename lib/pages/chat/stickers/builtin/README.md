# 内置 99CHAT 表情包

`chat_builtin_sticker.dart` 只维护资源目录和不可变的表情目录。公开入口为
`ChatBuiltinStickerCatalog.stickers`、`menuAssetPath` 和 `byID`。表情有稳定 ID、
原始文件名、资源路径、真实像素宽高和用于辅助阅读的中文标签；不启动网络请求、
账号状态、SDK 监听或全局缓存。

`assets/4351/` 的 16 张透明 PNG 及 `menu@2x.png` 原样来自 99chat 的同名资源目录，
按照 `Const.emojiList` 的 `ys00` 至 `ys15` 排列。每张图的实际尺寸为 240×240。
来源与许可证见 [third-party-assets.md](../../../../../docs/third-party-assets.md)。
标签描述画面；参考仓库没有为这 16 个文件提供动作名称或翻译表。

聊天面板与发送适配在此功能目录分别维护。原图属于应用资源，由主应用
`pubspec.yaml` 声明；公共聊天组件通过入口回调展示面板，不反向导入业务目录。
实际消息仍通过现有 OpenIM SDK、消息发送管线与图片/表情渲染能力。

`chat_builtin_sticker_panel.dart` 展示四列网格，入口为聊天表情栏的 99CHAT 图标。
点击图片直接发送，等待期间阻止重复点击；不清空输入草稿，也不关闭表情面板。
普通 Unicode 表情和个人收藏表情继续使用各自的入口。

`chat_builtin_sticker_sender.dart` 读取打包原图，写入独立的临时文件，再调用
OpenIM `uploadFile` 获取真实远程地址。使用现有 `StickerImageData` 携带 URL 和
240×240 尺寸，创建 `index: -1` 的 face 消息后交给当前聊天的发送管线。
接收方复用现有表情显示、预览和收藏协议，不依赖发送方的本地资源路径。
同一表情的并发请求合并，后续点击重新上传；完成或取消后清理本次临时文件。
每个异步阶段都检查页面、账号、禁言和群成员状态，旧账号的完成或失败不继续发送。

`chat_builtin_sticker_image_cache.dart` 负责上传后的首帧复用。原先发送气泡只拿到
URL，重新下载、解码期间会显示公共 `ChatImageSticker` 的灰色笑脸占位。
现在先将本次已加载的打包 PNG 解码为首帧，按相同
`ExtendedNetworkImageProvider(url, cache: true)` 的真实 key 放入 Flutter 图片缓存，
再交付消息。无需第二次下载即可显示刚发出的表情；发送回执更新同 URL 时也复用
该缓存。只处理目录中已验证的静态 PNG，不改变个人 GIF 或视频表情的动画行为。

该适配器不创建额外全局映射或持久化文件，缓存容量、淘汰与设置页的清缓存操作
沿用 Flutter 现有机制。已存在的 URL 缓存不覆盖；解码后发现页面或账号已失效时
释放本次图片，不写入缓存。预热失败仍交付正常远程 URL，由公共组件继续加载。
退出登录目前没有全局图片缓存清理，不能把该机制当作账号隔离存储。

资源完整性测试：`test/pages/chat/stickers/builtin/chat_builtin_sticker_test.dart`。
测试核对原图 SHA256、目录顺序、资源打包可用性及 PNG 解码尺寸。
面板测试覆盖网格、发送及重试；发送测试覆盖 SDK 参数、原始资源字节、消息协议、
并发和阶段取消；公共聊天组件的页签测试覆盖草稿保留与禁言、退群关闭行为。
`chat_builtin_sticker_image_cache_test.dart` 验证实际资源与发送器产生的消息在首次
绘制、回执更新及重新挂载时复用首帧，以及缓存清理后的远程加载回退。
