# 内置表情发送灰占位修复

## 原因

表情面板使用本地打包 PNG。此前发送器读取、上传 PNG 后，只将远程 URL 与
240×240 尺寸交给普通 OpenIM face 消息。气泡的 `ChatImageSticker` 用
`ExtendedNetworkImageProvider(url, cache: true)` 重新下载、解码；首帧尚未就绪时，
`frameBuilder` 显示灰色笑脸占位。该占位也用于图片加载失败。

成功回执沿现有消息发送链更新同一消息。URL 未改变时，图片组件不会主动重置来源；
此次问题来自首次显示缺少图片缓存。

本次排查基于 `E:/openim/openim-flutter-demo` 当前源码。GitNexus 的仓库列表中没有
该项目索引，因此未使用其他仓库的索引推断调用链。对照了本地 99chat 的
`lib/src/widgets/sticker/sticker_face_bubble.dart`，其内置表情可通过已知资源路径展示；
本项目继续使用已有 OpenIM URL 消息协议与公共图片组件。

## 修改

- `lib/pages/chat/stickers/builtin/chat_builtin_sticker_image_cache.dart`：上传后将本次
  已加载的真实 PNG 解码首帧，按现有网络 provider 的真实 key 写入 Flutter 图片缓存。
- `chat_builtin_sticker_sender.dart`：等待预热后再创建、交付普通 face 消息；解码期间
  和交付前检查当前账号、页面、禁言及群状态。
- 缓存命中时不覆盖现有图片；取消时释放本次解码图片。预热失败继续交付远程 URL，
  保留公共组件的加载与失败回退。
- 缓存沿用 Flutter 的容量、淘汰和设置页清理机制，没有额外全局映射或持久化文件。
  消息中不携带本地文件或资源路径。

只预热目录中已验证的内置静态 PNG。个人图片、GIF、视频表情、图片预览、收藏、
SDK 消息类型、回执、草稿与发送面板行为继续使用现有能力。接收方和缓存已被淘汰的
历史表情仍通过远程 URL 加载。

## 验证

2026-10-06 的验证结果：

| 检查 | 结果 |
| --- | --- |
| 修改相关源码与测试静态检查 | 通过 |
| 发送参数、资源字节、并发、失败重试及各异步阶段取消 | 31 项通过 |
| 公共表情显示、GIF 动画、预览、尺寸、元数据、面板与真实资源 | 49 项通过 |
| 真实资源和默认发送器的首帧专项 | 8 项通过 |
| Android 调试包构建 | 通过 |

共 88 项通过；两个既有可选面板导图测试因未指定输出路径而跳过。专项测试在亮暗
主题下将实际发送消息序列化后挂载生产组件，首次绘制就有真实 240×240 图片，
没有笑脸占位，图片下载请求数为 0。成功回执及列表行重新挂载后保持同一图片。
清理标准图片缓存后，能按原有流程等待远程图片并完成显示。还覆盖缓存已存在、
坏 PNG 和解码期间账号失效。

测试记录：

- `build/builtin-sticker-warm-sender-tests-20261006.log`
- `build/builtin-sticker-warm-display-tests-20261006.log`
- `build/builtin-sticker-first-frame-tests-20261006.log`
- `build/builtin-sticker-first-frame-build-20261006.log`

修复包：`build/app/outputs/flutter-apk/app-debug-builtin-sticker-first-frame-20261006-045812f86aa6.apk`。

SHA-256：`045812f86aa6574c977b37d9f1e7d7203b1f89437b96681809f89820760a3d94`。

未安装或部署；真机网络与显示体验仍需在设备上复测。
