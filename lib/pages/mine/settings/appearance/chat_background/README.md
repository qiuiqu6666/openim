# 聊天背景

当前入口由 `chat_background_editor.dart` 展示，对照 `reference-99chat/lib/src/pages/chat_background_page.dart` 恢复范围切换、范围说明、实时预览、相册、清除、可折叠纯色与推荐背景。宽屏为选项与预览双栏。复用 SettingsGroup、SettingsCell、AppTokens 和现有相册选择能力。标题栏使用原版不透明 AppBar，避免公共 GlassAppBar 改变原版滚动和背景表现。

`pages/chat_background_page.dart` 保留入口兼容与保存编排，ChatBackgroundLocalService 继续拥有持久化。设置入口只修改全局默认；会话入口可切换当前聊天与全部聊天。点击颜色或推荐图片立即保存并更新预览，与参考仓库一致。清除会话专属背景后继承全局默认。保存期间防重复提交、范围切换和系统返回，保存失败提示重试。编辑器独立文件只管理分组展开状态，不承担存储职责。预览独立到 chat_background_preview.dart；原版专用视觉参数归 chat_background_reference_tokens.dart。编辑器保留同一设置页的布局编排，不包含存储或图片文件读取。

按用户要求保留现有九张 1440×2560 风景壁纸，替代参考仓库的人物、风景、汽车三张推荐图。全部本地提供，无下载标记；来源见 wallpaper_sources.md。网格按 384px 宽解码缩略图，聊天仍使用高清资源。旧 menu/picker 独立组件保留兼容，但主入口不再使用它们。

测试：chat_background_editor_test.dart 验证亮暗主题的范围切换、即时保存、清除继承、九图选择及小屏双倍字号；chat_background_local_service_test.dart 验证背景值。真机视觉、相册权限和 iOS 交互尚未验证。

视觉对照：范围按钮 36 高、18 圆角；预览 168 高、12 圆角、180 气泡最大宽；颜色与推荐图间距 14，推荐单元比例 1.05，并保留图下名称。标准字号对齐参考；大字号仅按缩放扩展预览与范围按钮，防止溢出。
