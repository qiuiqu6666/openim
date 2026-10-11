# 头像查看与更换

`AvatarActions` 复用现有 iOS 风格 `showAppActionSheet` 和图片预览，不负责选择、裁剪或上传。已有网络头像或本地图片可查看、缩放、保存；没有图片时不提供无效的查看入口。只读资料/昵称/备注编辑器可直接调用 `preview`，可修改入口使用 `open` 并传入原有选择回调。`isActive` 用于菜单关闭后重新确认页面状态和权限；取消不执行回调。

群设置和群名称编辑、注册时已选的本地头像复用此入口。`IMViews.openPhotoSheet` 保留既有相册、相机、裁剪和上传逻辑，增加 `avatarUrl` 查看入口并使用相同的 iOS 菜单；个人资料、个人昵称、建群和旧注册资料页传入当前头像。公共组件不改变 SDK 更新权限。

共享姓名编辑器没有更换回调时直接查看头像，保存期间不响应。现有聊天头像点击仍按原逻辑打开用户资料，不在全局改变 `AvatarView` 默认行为。

对照 99chat 的 `group_info_detail.dart` 头像查看/管理分离及 `my_profile_detail.dart` 查看、相册、相机菜单；保留 OpenIM 的图片和资料数据源。回归测试在 `test/widgets/avatar/`，业务页面的既有测试保留各自位置。

## 显示与内存

`AvatarView` 的网络与本地头像按实际显示尺寸 × 设备像素比限制解码，并保持图片比例；例如 54 逻辑像素、3 倍屏只需 162 像素。此限制只作用于列表头像，点击后的全屏查看仍使用原始 URL/文件，保存和头像裁剪继续走原文件及原生裁剪器。

公共 `ImageUtil.networkImage/fileImage` 默认不保留原始压缩字节，仅复用 Flutter 有容量限制的解码缓存和已有磁盘缓存。`extended_image` 的全局 `rawImageDataMap` 无淘汰上限，因此只有确实读取 `provider.rawImageData` 的编辑器才能显式传 `cacheRawData: true`，由该编辑器在完成后释放。现有生产头像裁剪不依赖此全局数据。

旧版累积的原始字节只存在进程内，更新后完整重启会释放；不要在用户正在编辑图片时执行全局 `rawImageDataMap.clear()`。不改变图片文件、磁盘缓存或高清预览来源。

回归测试：`test/utils/media/image_raw_cache_lifecycle_test.dart` 连续加载/卸载 75 张不同图片，原始缓存保持为 0，并验证编辑显式保留可用；`test/widgets/avatar/avatar_decode_size_test.dart` 验证 1/2/3 倍屏实际解码尺寸及原图预览。
