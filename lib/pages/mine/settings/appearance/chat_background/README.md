# 聊天背景

menu 为三个入口，picker 为取消/完成和三列网格；tokens 保存视觉值与内置资源清单。复用项目设置组件、AppTokens、相册与相机组件。

pages/chat_background_page.dart 保留入口兼容与保存编排，ChatBackgroundLocalService 继续拥有持久化。设置入口修改全局默认；会话入口修改当前会话。选中只更新本页草稿，完成后持久化，取消和系统返回不保存。保存期间防重复提交和返回，失败保留选择供重试。

旧预览、作用域切换和折叠分组已移除。UI 以用户截图为准，资源为九张 1440×2560 风景壁纸，均已本地提供，无下载标记；来源见 wallpaper_sources.md。网格按 384px 宽解码缩略图，聊天仍使用高清资源。

测试：chat_background_picker_test.dart 验证亮暗主题下确认和取消；chat_background_menu_test.dart 验证三个入口、大字体及无障碍；chat_background_local_service_test.dart 验证背景值。真机视觉、相机和相册权限尚待验证。
