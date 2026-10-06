# 朋友圈页面模块

入口是「我的 → 社区广场」。`moments_page.dart` 组合好友动态流及个人相册，`moments_detail_page.dart` 组合当前授权的详情与评论分页。页面继续使用 `MomentsRepository`、当前登录的业务 token、真实能力握手及 OpenIM 好友关系；样式调整不替换后端契约。

## 页面与组件归属

| 目录 / 文件 | 职责 |
| --- | --- |
| `presentation/moments_theme.dart` | 99chat 对照尺寸、字体、亮暗主题颜色 |
| `presentation/moments_scaffold.dart` | 页面容器、原有毛玻璃导航、安全区域与大屏宽度 |
| `presentation/moments_cover_header.dart` | 250 高封面、回弹、头像、发布及通知入口 |
| `presentation/moments_post_card.dart` | 动态卡片及详情正文 |
| `presentation/moments_engagement_panel.dart` | 当前查看者可见的点赞头像及评论预览 |
| `presentation/moments_detail_comment_row.dart` | 详情评论、回复目标及已删除目标显示 |
| `presentation/moments_profile_timeline.dart` | 相册日期分组、104 方形拼图及当天发布入口 |
| `presentation/moments_secondary_layout.dart` | 设置、通知等次级页面尺寸 |
| `presentation/moments_composer_*` | 发布正文、媒体选择及权限展示 |
| `presentation/moments_friend_picker_list.dart` | 好友索引、搜索及字母分组 |
| `media/` | 鉴权图片、比例排布及预览，见目录内 README |
| `interactions/` | 保留原有点赞、评论按钮，以及幂等评论编辑弹层 |
| `privacy/` | 两类真实名单写入及按账号、服务器隔离的本机确认记录 |
| `moments_draft_store.dart` | 稳定发布任务、上传恢复及未知结果查询 |
| `moments_widgets.dart` | 既有调用方的导出兼容入口，不持有实现或状态 |

组件按展示、媒体和互动职责独立维护。模块内引用具体实现文件，避免反向引用兼容导出入口造成循环。测试假 API、照片及账号仅在 `test/pages/moments/support/`，生产页面没有演示数据。

## 对照与验证

视觉依据为本地 `reference-99chat/lib/src/pages/moments/` 及对应设置页面。动态流、个人相册、详情、发布、通知和隐私设置按其源码尺寸还原；依用户要求，点赞和评论按钮保留既有样式与行为。当前工程的毛玻璃导航、无权限状态、发布恢复和撤权保护继续保留。

设计参数、已核对差异、预览和验证结果见 [99chat 对齐记录](../../../docs/moments-99chat-validation.md)。接口字段及上线联调边界见 [客户端接入契约](../../../docs/moments-client-integration.md)。
