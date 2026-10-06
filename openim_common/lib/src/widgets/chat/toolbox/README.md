# 聊天更多面板

`../chat_toolbox.dart` 是兼容公开入口，继续接受现有工具回调和 `ToolboxItemInfo`。此目录只负责界面：统一尺寸与主题、图标、工具格子、页内布局及输入栏展开槽位，不依赖应用业务模块。

布局对照 99chat `d7c3c65` 的生产 `TIMUIKitMorePanel` 与手机 `TIMUIKitTextFieldLayoutNarrow`。手机父容器实际约束是 248px 加安全区，覆盖参考面板内层的 174px；不能按内层数字截掉第二排。每页八项、四列两排，64px 图标槽、60px 高圆角底色、56px 原图画布、12px 单行文案。原图自带留白，程序符号单独用 26px，避免补充入口比原图大一倍。

单聊顺序为相册、拍摄、收藏、音视频通话、个人名片、文件、红包、转账。群聊隐藏通话，现有群直播入口使用 `id: 'group_live'` 显示原图；其他群功能和录音、音频、位置等原有入口继续分页。未注入的回调隐藏对应项；相册保留原有的可见禁用兼容行为。权限检查继续调用公共 `Permissions`，所有业务、SDK、资金、群权限及媒体选择流程由原回调处理。

音视频通话的二次选择仍由 `IMViews.openIMCallSheet` 提供，复用联系人更多菜单等入口使用的公共 `BottomSheetView`。语音通话、视频通话和取消统一为居中文字，选择后先关闭弹窗，再按原来的索引 0/1 进入语音/视频通话，取消不发起通话。

`ChatComposerToolboxSlot` 使用 200ms easeOutCubic 增减高度，在裁剪范围内保持内容终态约束。安全区只由面板底部内边距承担；关闭时普通输入槽保留相同安全区，切到表情或语音后槽位归零，由对应面板承担安全区。外部输入与焦点控制器、草稿和关闭 stream 仍归 `ChatInputBox` 的调用方。焦点恢复、强制关闭或输入失效会关闭面板，表情、语音和工具互斥。

`ChatToolboxGrid` 按实际父宽度分配间距，小屏、大字或受限高度可以在页内纵向滚动；页数因群能力变化减少时重置到第一页并释放旧控制器。SVG/PNG 资源在公共包 `assets/chat_toolbox/`，来源和许可见 `docs/third-party-assets.md`。

应用测试位于 `test/widgets/chat/toolbox/`，另有兼容分页、输入、名片和资金入口回归。`CHAT_TOOLBOX_PREVIEW=true` 可生成 `.dart_tool/chat-toolbox-{light,dark}-page-{1,2}.png`，预览使用正式组件与测试回调。
