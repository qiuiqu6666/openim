# 头像查看与更换

`AvatarActions` 复用现有 iOS 风格 `showAppActionSheet` 和图片预览，不负责选择、裁剪或上传。已有网络头像或本地图片可查看、缩放、保存；没有图片时不提供无效的查看入口。只读资料/昵称/备注编辑器可直接调用 `preview`，可修改入口使用 `open` 并传入原有选择回调。`isActive` 用于菜单关闭后重新确认页面状态和权限；取消不执行回调。

群设置和群名称编辑、注册时已选的本地头像复用此入口。`IMViews.openPhotoSheet` 保留既有相册、相机、裁剪和上传逻辑，增加 `avatarUrl` 查看入口并使用相同的 iOS 菜单；个人资料、个人昵称、建群和旧注册资料页传入当前头像。公共组件不改变 SDK 更新权限。

共享姓名编辑器没有更换回调时直接查看头像，保存期间不响应。现有聊天头像点击仍按原逻辑打开用户资料，不在全局改变 `AvatarView` 默认行为。

对照 99chat 的 `group_info_detail.dart` 头像查看/管理分离及 `my_profile_detail.dart` 查看、相册、相机菜单；保留 OpenIM 的图片和资料数据源。回归测试在 `test/widgets/avatar/`，业务页面的既有测试保留各自位置。
