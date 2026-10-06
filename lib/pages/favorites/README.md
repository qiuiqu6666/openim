# 收藏界面维护入口

`navigation/favorites_app_bar.dart` 统一正式收藏、草稿与能力检测页的导航配置，复用公共 `GlassAppBar` 的玻璃背景、状态栏和安全区。对照 99chat 收藏列表的居中标题及返回入口，编辑／完成使用主题色与明确的禁用状态；大字号时导航高度随文字增长。路由返回和编辑回调仍由现有页面持有。

`widgets/favorite_capability_gate.dart` 复用仓储的账号级 quota 能力，双能力确认前不构建正式收藏内容；错误可重试，不使用本地收藏替代。`favorite_p0.dart` 集中定义当前开放类型。

`widgets/favorite_recovery_banner.dart` 展示同步、待提交操作恢复和版本冲突提示；刷新复用仓储同步，不阻断已确认的收藏。`widgets/favorite_search_formatter.dart` 按 API 的 64 个 Unicode 标量限制搜索词，同时保留中文输入组合和完整表情。

`widgets/favorite_conflict_review_dialog.dart` 让用户审阅服务器最新正文并保留自己的编辑；审阅不保存，下一次点击完成才按最新版本提交，成功后才清理已确定的旧冲突记录。`widgets/favorite_note_byte_formatter.dart` 按 64 KiB UTF-8 限制笔记输入与提交，原有长正文不会被字符数上限截断。

`media/favorite_picked_media.dart` 从所选原件文件头及实际文件名取得上传 MIME，保留原文件路径；服务端负责最终解码。管理与详情遇到删除版本冲突后先读取最新内容，读取失败时保留选择并阻止再次提交旧版本。预览只展示脱敏错误，不重写授权 URL。

聊天适配位于 `../chat/favorites/`。现有管理、详情和笔记编辑暂保留 `../mine/secondary/` 路径，本轮只做 P0 协议与能力门禁局部修正，避免和聊天拆分及服务协议改造交叉迁移；后续分别迁移公共列表、详情及编辑职责。

`data/favorite_media_upload.dart` 管理原件上传检查点；确定拒绝后严格保存清理结果，存储失败回滚，未知结果保留身份。`models/favorite_archive_retry.dart` 描述服务端归档任务确认，`data/favorite_archive_retry_recovery.dart` 按已保存回执补读正式详情。确认回执位于既有账号级 outbox，不更改原请求正文；详情读取失败不重放已确认的 POST。

2026-10-05 媒体失效检查点修复和归档确认接线保留在既有 FavoriteRepository：它们依赖仓储私有账号代次、请求身份和严格缓存写入，共用这些机制可避免建立第二套恢复状态。此次不迁移仓储路径，不改变 SDK 发送日志键。证据和生产部署边界见 [本次检查记录](../../../docs/favorites-original-unavailable-2026-10-05.md)。

新增界面测试位于 `test/pages/favorites/`；聊天选择器回归位于 `test/pages/chat/favorites/`。能力请求、缓存和错误由正式 FavoriteRepository 管理，组件不直接请求 API，不发送 SDK 消息。

收藏详情的展示职责归 `detail/`：`favorite_detail_footer.dart` 统一底部操作、窄屏大字号布局和安全区；`favorite_detail_metadata.dart` 展示来源及手机本地时间；尺寸归 `favorite_detail_tokens.dart`。现有 `mine/secondary/favorite_detail_page.dart` 继续持有仓储、发送、删除与编辑流程，入口不变。语音详情复用 `media/favorite_audio_preview.dart`，同一布局覆盖原件下载、播放器加载、失败重试及播放，避免重复附件信息和两套时长。

2026-10-05 媒体预览职责独立在 `media/`：`favorite_item_thumbnail.dart` 展示图片缩略图、视频封面和语音时长；`favorite_asset_preview.dart` 管理原件加载、图片全屏与音视频预览；`favorite_audio_preview.dart` 管理语音播放控件；`favorite_preview_loader.dart` 申请既有仓储授权并校验下载文件、清理独立临时目录。管理页与聊天选择器复用同一列表入口，详情页复用同一预览组件。视频复用公共导出的 NativeMediaVideo，使用校验后的本地文件。私有授权 URL 不进入通用图片/视频 URL 缓存。验证和修复包见 [媒体预览修改记录](../../../docs/favorites-media-preview-2026-10-05.md)。
