# Flutter OpenIM 全局性能审计

2026 年 10 月 11 日。本报告审计当前工作区，包括上一轮尚未运行验证的优化。当前没有足够证据确定 Android/iOS 真机“偶发完全卡死”的根因；优先候选是无期限的原生任务等待与全屏等待层、大文件处理和图片内存峰值。会话、聊天列表仍有线性处理，但不能仅凭遍历代码认定其为首要热点。

用户在审计阶段明确保留“不构建、不运行测试，只静态审计并读取现有采集数据”。审计阶段没有修改业务代码、运行 analyzer、构建、测试、安装、启动 App 或新采集性能数据。以下原审计条目的方案是根据源码提出的小范围建议，实施进度见文末更新。

后续更新：用户随后要求“开始优化”，已按下文“第一批源码优化”完成 7 项局部改动，仍未构建、运行测试或 analyzer。原审计结论描述的是该批改动前的状态；F05 经完整调用链复核已撤回，不能继续作为已确认缺陷。

2026 年 10 月 12 日补充：已取得用户提供的 iOS Release SDK 日志，确认 305 次零角标网络请求和大量原生详细日志，并完成角标合并、正式包日志策略及首页未读查询竞态修复。实际计数、源码位置、原生耗时基线及待验证项见 [iOS Release 日志核查与局部优化](E:/openim/openim-flutter-demo/docs/performance-ios-release-log-2026-10-12.md)。这份日志不包含 DevTools 帧、CPU 或 Memory 数据。

## 范围与证据可信度

- 仓库：`E:/openim/openim-flutter-demo`；HEAD `249f067786b91518ac2ba0438d22dd0cdab9d609`，另有未提交修改，因此 HEAD 不能单独代表本报告审计的源码。
- 扫描应用、公共包及本地插件约 1451 个非测试、非指定生成后缀的 Dart 文件，并针对命中项追踪调用方、异步边界和释放路径；这不是逐行审阅全部文件的声明。也检查了 Android/iOS 桥接相关源码。
- 仓库 `.flutter-version` 为 3.41.6；实际依赖解析指向 OpenIM Flutter SDK `3.8.3+hotfix.12`、GetX `4.7.2`、video_player `2.10.0`。图片库和 Android 播放器存在本地覆盖，不能用上游默认行为代替本地实现。
- 用户指定的 `performance-speedup`、`systematic-debugging` 在可用目录及仓库内未找到；没有可直接应用的专门 Flutter 性能、并发、缓存 Skill。沿用已读取的 `gitnexus-debugging` 排查方法；GitNexus 列出的 6 个索引均不属于本 Flutter 仓库，故没有用它们推导本项目调用链，也没有重建索引。
- 当前连接设备只有 `emulator-5554`，无可用于本次审计的 Android/iOS 真机。工作区未找到 Timeline JSON、CPU profile、Memory heap snapshot、Perfetto trace 或 ANR 导出；未接入新的 DevTools 会话。
- 找到 `.dart_tool/performance-audit/` 内既有桌面测试/探针日志。它们可证明相应旧代码路径的工作量，不能提供真机帧耗时、CPU 占比、RSS、温升或当前改动后的性能。

下文 **P1** 表示优先定位/修复风险，**P2** 表示按场景采样后优化，**P3** 表示低优先级额外工作。优先级不是发生率。除特别标注旧探针外，证据均为源码；所有真机影响和优化效果均待验证。`await` 本身不会同步阻塞主 Isolate，任务不完成与主线程死锁需分别判断。

## 优先定位的等待与队列问题

### F01 媒体准备可长期占用等待层和附件入口

**P1，静态确认缺少完成时限，实际卡住待验证。** [视频压缩](E:/openim/openim-flutter-demo/lib/pages/chat/media/video/chat_video_preparation.dart:23) 通过 [全局 LoadingView.wrap](E:/openim/openim-flutter-demo/openim_common/lib/src/widgets/loading_view.dart:36) 等待原生压缩。透明全屏 Overlay 覆盖触摸区域，只有 Future 结束后才 dismiss；没有操作级超时或取消入口。[附件入口](E:/openim/openim-flutter-demo/lib/pages/chat/media/chat_media_controller.dart:158) 一直等待整批发送后才释放 `_pickingAttachment`，[有序发送](E:/openim/openim-flutter-demo/lib/pages/chat/media/upload/ordered_media_batch.dart:24) 又依次等待准备结果和发送结果。

触发条件：云端相册原件提取、压缩、缩略图生成或 SDK 创建消息迟迟不回调；某个靠前的任务挂起。后续媒体会排队，压缩等待层可能造成“点击都没反应”，即使渲染线程仍在转动。上传本身已有 10 分钟 await 超时，不能说整条上传链完全没有超时。

方案：为相册提取、压缩、SDK 创建分别记录开始/结束和取消状态；等待界面改为所属操作可取消、可恢复的状态。超时后隔离迟到结果，使用原生支持的取消接口，不对全局压缩器无差别取消。验证时记录每个阶段的最长等待、取消到界面恢复时间及后续条目是否继续。

### F02 历史读取 Future 不结束会让分页一直处于 loading

**P1，条件性停滞。** [读取入口](E:/openim/openim-flutter-demo/lib/pages/chat/chat_logic.dart:426) 直接等待 SDK；[loader](E:/openim/openim-flutter-demo/lib/pages/chat/history/chat_history_loader.dart:118) 仅在请求完成后清除 `_request/loading`，后续 `loadOlder()` 会复用原请求。[首屏预取](E:/openim/openim-flutter-demo/lib/pages/chat/history/chat_history_prefetcher.dart:74) 也会等待已接管的 Future；预取的缓存过期计时器不等于 SDK 请求超时。

触发条件：原生历史读取或通道响应永久不返回。表现是历史首屏/分页长期等待，不足以证明整个 App 线程死锁。

方案：只对可重试的读取增加有界等待、错误展示和请求代次隔离；旧响应失效后不能覆盖新窗口。限制未完成原生查询数量，避免仅用 Dart 超时后不断补发 SDK 查询。验证首屏、旧页、反向页和日期跳转的失联、恢复及迟到响应。

### F03 登录退出队列可能被未完成的原生操作占住

**P1，条件性会话停滞。** [SdkSessionQueue](E:/openim/openim-flutter-demo/lib/core/session/sdk_session_queue.dart:26) 的 15 秒计时器约束等待启动/准备阶段，`started` 后取消；`operation()` 没有结束时限，后续任务继续等待 `_tail`。[退出](E:/openim/openim-flutter-demo/lib/core/controller/im_controller.dart:382) 还串行等待通话清理、SDK 登录状态及 logout。

触发条件：任一原生清理/login/logout 永久不结束。后续登录可能反复收到 busy，账号切换无法完成。异常被捕获后队列可以继续，当前风险是“不完成”，不是普通错误导致队列永久拒绝。

方案：增加分阶段 watchdog、可见故障状态及原生清理确认。**不能在 Dart timeout 后让新账号越过仍运行的旧 logout**；需要 SDK 允许的重置或明确完成信号再恢复。验证原生回调缺失、后台切换和账号切换的时序。

### F04 新视频表情名额可能被挂起的播放器占满

**P2，上一轮优化新增的待验证边界。** [播放名额池](E:/openim/openim-flutter-demo/lib/pages/chat/stickers/sticker_video_playback_pool.dart:9) 限制两个名额，含初始化和释放；[播放器初始化](E:/openim/openim-flutter-demo/lib/pages/chat/stickers/sticker_video_bubble.dart:154) 和 [释放](E:/openim/openim-flutter-demo/lib/pages/chat/stickers/sticker_video_bubble.dart:207) 没有操作级 watchdog。

触发条件：两个播放器 initialize/dispose 一直不完成，后续视频表情只能等待封面。它不会自行阻塞文字聊天，不能称为全 App 卡死。

方案：记录持有名额时长，超时显示可重试封面，明确原生初始化失败/取消与释放完成的接口；不能未确认释放就归还名额，否则破坏并发上限。验证坏视频、断网、快速进出和退后台，观察原生播放器存活数量，而非只看 Dart 对象数。

### F05 收藏增量同步游标保护（复核后撤回缺陷判断）

**现有正式入口已有保护，不列为 P1。** 原审计只根据 [FavoriteChangeSynchronizer](E:/openim/openim-flutter-demo/lib/pages/favorites/data/favorite_change_synchronizer.dart:18) 循环本体判断缺少游标推进检查，遗漏了注入的 commit 调用链。

实际调用是 repository 的 commit → [FavoriteSyncState.apply](E:/openim/openim-flutter-demo/lib/pages/favorites/data/favorite_sync_state.dart:12)，其中原本就拒绝倒退水位和 `hasMore=true` 的不推进水位；异常会终止本轮同步。此次不重复增加相同保护，也没有把该项计入优化成果。

继续保留同毫秒完整分页和严格持久化顺序。实际优化的是 F08 中空页面、相同水位的重复缓存工作。

## 主 Isolate 图片与缓存压力

### F06 通用网络图片磁盘缓存仍使用同步文件检查

**P2，同步 I/O 已确认。** [本地覆盖图片库](E:/openim/openim-flutter-demo/local_plugin/extended_image_library/lib/src/network/network_image_io.dart:208) 在缓存加载中使用 `existsSync`，配置 cacheMaxAge 时还有 `statSync/deleteSync`。入口在普通图片加载调用链上，没有转入 worker；函数标为 async 不会把这些同步部分移走。[ImageUtil](E:/openim/openim-flutter-demo/openim_common/lib/src/utils/image_util.dart:48) 的通用网络图片启用磁盘缓存。

触发条件：快速滚动多图页面、磁盘慢或缓存目录压力大。现有入口未普遍传 cacheMaxAge，不能认为每张图片都会 stat/delete。

方案：将这些检查改成异步文件 API，合并重复路径查询并妥善处理目录创建竞争。先在 Timeline 中确认 `_loadCache` 是否与慢帧重叠，比较缓存命中时的 p95/p99 耗时和 I/O 等待。

### F07 收藏文件先完整哈希 后检查大小限制

**P1，大文件场景。** [createMedia](E:/openim/openim-flutter-demo/lib/services/favorite_repository.dart:1343) 读取文件长度后立即 `sha256.bind(original.openRead()).first`；真正的 20/100 MiB 限制在后续 [上传器](E:/openim/openim-flutter-demo/lib/pages/favorites/data/favorite_media_upload.dart:73)。流式读取不是同步读全文件，但摘要计算仍在调用它的 Isolate，且这段读取没有接入取消令牌。

触发条件：选择超过上限的大视频/文件，或有效大文件与聊天操作并行。即使最终拒绝上传，也已经遍历了文件内容。

方案：哈希前先校验类型/大小；对有效大文件复用可取消的 worker 流式摘要能力，校验文件未变后才复用摘要。验证被拒绝文件的实际读取字节、主 Isolate CPU 样本及取消后的读取停止时间。

### F08 收藏同步反复序列化整份缓存

**P2。** [缓存写入](E:/openim/openim-flutter-demo/lib/services/favorite_repository.dart:626) 逐次串行排队；`_writeCache` 构造全量 metadata、读取旧 JSON、过滤、`jsonEncode` 后写入 SharedPreferences。[同步提交](E:/openim/openim-flutter-demo/lib/services/favorite_repository.dart:202) 每页调用严格持久化，包括空事件页。[绑定](E:/openim/openim-flutter-demo/lib/pages/favorites/data/favorite_sync_binding.dart:62) 在前台每分钟轮询；收藏仓储已创建后，回到聊天并不会按聊天活跃度暂停它。

触发条件：收藏数据多、连续分页、上传检查点或同步通知密集。普通 JSON 编解码和集合构造仍在主 Isolate，多个排队写入会放大累计工作。

方案：先比较数据/水位变化，合并可覆盖的缓存写入；操作 outbox 与幂等检查点保留严格顺序，不能全部防抖。必要时分离元数据与水位持久化，较大序列化交给 worker。比较编码 CPU、单次字节、写入次数和队列最长等待。

### F09 客服聊天缩略图没有像素解码限制

**P1，内存峰值风险。** [客服消息媒体](E:/openim/openim-flutter-demo/lib/pages/customer_service/widgets/customer_service_message_view.dart:162) 对本地图片、远程图片及视频封面使用 Image.file/ImageUtil，但没有 cacheWidth/cacheHeight；外部小尺寸 SizedBox 只约束布局，不约束解码。[附件允许的压缩文件大小](E:/openim/openim-flutter-demo/lib/pages/customer_service/data/customer_service_api.dart:25) 上限为 40 MiB，不能代替像素限制。

触发条件：连续接收/选择高分辨率图片，快速滚动或预览返回。4000×3000 的单帧 RGBA 理论像素数据约 48 MB，只是量级说明，不是实测 RSS，也没有证明这类图片实际出现过。

方案：按气泡尺寸与 DPR 限制解码，视频使用受限封面，原图只在预览按需要加载。Memory 需同时看 Dart heap、external/native 和图片存活情况；比较同一组图片的峰值及关闭后的回落。

### F10 原图预览限制解码像素 但没有编码字节上限

**P2。** [ViewerImageProvider](E:/openim/openim-flutter-demo/openim_common/lib/src/widgets/media_browser/viewer_image_provider.dart:49) 从缓存整文件读入，网络侧 `consolidateHttpClientResponseBytes` 聚合完整响应，没有 Content-Length/累计字节上限；随后才按 maxPixels 降采样。默认原图上限 16×1024×1024 像素，单帧 RGBA 理论约 64 MiB，另有压缩字节与原生缓冲。

触发条件：特大原图、体积很大的动图、弱内存设备。现有请求有连接/响应超时，离开当前图与关闭预览会取消；不能继续引用旧日志声称当前实现无限预加载原图。

方案：缓存与网络都校验编码字节上限，渐进显示当前屏幕所需清晰度，放大后再提高预算；动图另设帧/资源策略。比较原图首帧延迟、峰值 external/RSS 和取消后的内存回落。

### F11 收藏列表行重挂载会重走下载 校验和缩略流程

**P2。** [缩略图组件](E:/openim/openim-flutter-demo/lib/pages/favorites/media/favorite_item_thumbnail.dart:52) 每次 init 启动 loader；[loader](E:/openim/openim-flutter-demo/lib/pages/favorites/media/favorite_preview_loader.dart:76) 下载后读取哈希，组件又读文件并生成至多 160 像素缩略图。加载结束清理临时目录，dispose 时驱逐 MemoryImage。没有跨行生命周期的缩略图复用。

触发条件：在较大收藏列表反复上下滚动，行被卸载后再创建。不是普通 build 每次下载，也不是已证实内存泄漏。

方案：增加按账号、资源版本与访问有效性隔离的有界缩略图缓存和请求合并；注销/授权失效立即清理，保留私有原件校验。比较重挂载下载次数、哈希字节与 CPU，不把私人原件放入公共持久缓存。

### F12 朋友圈封面重复整文件摘要

**P2。** [选择封面](E:/openim/openim-flutter-demo/lib/pages/moments/moments_cover_page.dart:136) 整文件读入后同步 `sha256.convert(bytes)`；[确认上传](E:/openim/openim-flutter-demo/lib/pages/moments/moments_cover_page.dart:217) 再读一次和计算一次。选择前已有大小限制，默认 10 MiB，因此不是无界文件处理。

触发条件：接近限制的大封面，尤其在页面动画或预览同时发生时。方案：保留上传前文件一致性验证，将摘要移到 worker 或使用可验证的文件身份缓存。比较选择/确认阶段主 Isolate 采样、字节分配和首帧延迟。

## 聊天 列表与高频刷新

### F13 AI 流式长回复反复生成完整文本与 Markdown

**P2，有旧探针工作量证据。** [流状态](E:/openim/openim-flutter-demo/lib/pages/ai_assistant/streaming/assistant_stream_state.dart:114) 每个有效片段通知，209 行 `_text.toString()` 建完整快照；[展示](E:/openim/openim-flutter-demo/lib/pages/ai_assistant/presentation/messages/ai_assistant_text.dart:95) 将完整文本交给 MarkdownBody。

触发条件：长文本和密集片段。旧桌面探针 1200 个片段、最终 36000 文本单元，1200 次通知，累计快照长度 21618000。累计长度不是峰值内存，通知次数不是帧数；Flutter 同帧可合并构建，流式气泡也已与消息增删分开。

方案：按帧/短窗口合并发布、缓存稳定 Markdown 区块，尾段单独解析。比较 parser CPU、分配量和 UI p95；最终输出、引用及流结束状态需保持一致。

### F14 会话优化后仍有多轮全集合扫描与整体发布

**P2，当前剩余成本。** [onChanged](E:/openim/openim-flutter-demo/lib/pages/conversation/conversation_logic.dart:298) 建全映射并做旧群投影；[增量排序辅助](E:/openim/openim-flutter-demo/lib/pages/conversation/summary/conversation_incremental_order.dart:5) 仍构造 rank、byID、unchanged 和结果；[共享快照](E:/openim/openim-flutter-demo/lib/pages/conversation/summary/conversation_feed_snapshot.dart:41) 失效后遍历全部会话。仍以整份 RxList 发布。

上一轮已经改成 80 毫秒合批、只排序变化项、统计共享及重排行映射，不能再写成“每次完整排序、多个页面分别统计”。触发条件是会话很多且群消息持续活跃。方案：先测改后热点是否仍在这些扫描，再考虑复用长期 ID/排序索引或缩小行刷新范围，不重写 SDK 会话管理。验证总回调数、合批发布数、每批扫描/分配量及可见行 build 数。

### F15 文字气泡的 IntrinsicWidth 可能增加布局成本

**P2，布局候选，尚不能判为缺陷。** [ChatTextBubbleLayout](E:/openim/openim-flutter-demo/openim_common/lib/src/widgets/chat/chat_text_bubble_layout.dart:44) 非独立 footer 分支使用 IntrinsicWidth；[调用方](E:/openim/openim-flutter-demo/openim_common/lib/src/widgets/chat/chat_item_container.dart:328) 用它对齐正文与消息元信息。

触发条件：大量可见长文本/富文本、键盘改变可用高度或横竖屏切换。当前样式需要按真实正文确定气泡宽度，不能直接删掉 IntrinsicWidth 或凭估算替换。

方案：先用 Timeline 的 layout/intrinsic 事件及 CPU 样本确认贡献；只有占比显著才改为可证明等价的单次布局。验证不同字体、emoji、缩放、长链接及时间/已读标记，比较慢帧中的布局时长。

### F16 打开图片前仍同步复制整份媒体集合

**P2。** [图库构造](E:/openim/openim-flutter-demo/lib/pages/chat/media/chat_picture_gallery.dart:40) 在第一个 await 前对全部图片/视频消息做递归 Map/List 拷贝和 Message.fromJson；123 行定义快照转换。[普通聊天媒体查询](E:/openim/openim-flutter-demo/lib/pages/chat/media/chat_media_controller.dart:76) 当前 count=500，不能把 5000 条压力夹具直接说成普通聊天必达场景。

触发条件：媒体较多时点击图片，或搜索结果累积较多后进入图库。已有旧探针显示集合越大构造越慢，但当前普通入口有 500 条查询边界。

方案：先展示所点击项目及有限邻居，再分页建立只含浏览必需字段的不可变快照；保持索引与撤回/删除安全，不能让图库操作错指另一条消息。比较点击到首帧耗时和快照 CPU，分别测普通入口与历史搜索入口。

### F17 SDK 回调在主 Isolate 解析 且输出完整回调日志

**P2，原生数据库因果关系未确认。** 实际依赖中的 [回调入口](E:/openim/.pub-cache/hosted/pub.dev/flutter_openim_sdk-3.8.3+hotfix.12/lib/src/manager/im_manager.dart:37) 对 call 做字符串插值；消息/会话回调在当前 Isolate 转模型，[Utils](E:/openim/.pub-cache/hosted/pub.dev/flutter_openim_sdk-3.8.3+hotfix.12/lib/src/utils.dart:5) 使用同步 jsonDecode。Android [OnBaseListener](E:/openim/.pub-cache/hosted/pub.dev/flutter_openim_sdk-3.8.3+hotfix.12/android/src/main/java/io/openim/flutter_openim_sdk/listener/OnBaseListener.java:29) 会把完整成功响应拼入 Log.i。[项目日志等级](E:/openim/openim-flutter-demo/openim_common/lib/src/config.dart:122) 默认 5，没有按构建模式在这里切换。

触发条件：重连/离线同步、大回调列表、大量消息或历史查询响应。Release 不应被假定会自动消除所有插件日志；实际输出及优化结果需在对应包验证。

方案：先量化 callback payload 字节、JSON/模型解析及日志 CPU；在受控 SDK 适配/上游修复中限制日志内容与频率，必要时对大 payload 使用保序 worker 解析。不能随意并行打乱消息/撤回/已读回调，也不能直接改共享 pub-cache 作为长期修复。

### F18 上传进度向较大页面广播

**P2。** [朋友圈进度](E:/openim/openim-flutter-demo/lib/pages/moments/moments_draft_store.dart:513) 每次回调 `_changed()`，发布页 [监听](E:/openim/openim-flutter-demo/lib/pages/moments/moments_compose_page.dart:134) 直接 setState。收藏 [进度](E:/openim/openim-flutter-demo/lib/services/favorite_repository.dart:1390) 通知仓储，[列表](E:/openim/openim-flutter-demo/lib/pages/mine/secondary/favorites_page.dart:1654) 监听整个仓储。

触发条件：上传进度频繁且页面含多项媒体。不是每次回调都一定产生独立渲染帧，但会重复触发较广的构建。

方案：进度单独通知对应条目，按可见百分比/帧限频，结束和错误立即发布。比较上传期间页面 build 次数、输入延迟及 layout CPU。

### F19 直播纯播放进度也刷新整个播放器视图

**P2。** [控制器](E:/openim/openim-flutter-demo/lib/pages/group_features/live/playback/live_playback_controller.dart:155) 每次播放器通知都会 notifyListeners，即使只是 position 改变；[视图](E:/openim/openim-flutter-demo/lib/pages/group_features/live/playback/live_player_view.dart:177) AnimatedBuilder 重建播放器容器和覆盖控件。监听在换播放器和 dispose 时有移除，不能称为监听泄漏。

触发条件：长时间观看直播，尤其控件隐藏而位置继续通知时。方案：分离 ready/error/buffering/mute 等状态与纯 position，只订阅 UI 真正使用的字段。比较每分钟 notify/build 次数与 CPU；不影响首帧判定、凭证过期或错误恢复。

### F20 页面仍挂载时的低频无效计时刷新

**P3。** [六合彩卡片](E:/openim/openim-flutter-demo/lib/pages/group_features/mark_six/widgets/mark_six_latest_card.dart:72) 每秒 setState，`controller.current` 仅检查账号/销毁，不检查页面可见；已开奖也继续刷新。[在线标签](E:/openim/openim-flutter-demo/lib/pages/contacts/presence_store.dart:57) 每分钟全体 users.refresh，没有该计时器自己的前后台门禁。两者 dispose 均取消计时器。

触发条件：覆盖页面仍挂载、App 仍运行，或标签没有实际变化。不是操作系统挂起后仍持续运行的证据。方案：只在可见且截止/标签会变化时刷新，恢复时按绝对时间重算。验证隐藏状态回调/build 数；没有证据把此项排在大图或长等待之前。

## SQLite 资源释放及页面切换的结论边界

1. **SQLite：尚无已证实的慢 SQL 或数据库锁死。** 应用层未发现直接操作 OpenIM SQL 的 Dart 链路；Android 历史方法转交原生 `Open_im_sdk`，不能从异步 API 名称判断数据库耗时。通用缓存依赖 flutter_cache_manager/sqflite，其异步接口也不能证明没有 I/O 竞争。缺少 SQL 耗时、锁等待、查询计划、数据库大小及系统线程样本，禁止据此改索引、WAL、事务或数据库架构。
2. **没有确认聊天/会话主控制器存在重复监听泄漏。** ChatLogic 在 onClose 取消会话、用户、连接等订阅并释放滚动/输入/消息模块；ConversationLogic 取消订阅和观察者，新快照 cache 也释放 worker。不能仅凭全局 grep 的 listen 数量判泄漏。仍需路由反复进出后的 Heap diff/retaining path 验证。
3. **缓存并非全面无界。** ChatHistoryCache 当前限制 12 个会话×40 条，删除/撤回记录有限；ImageUtil 默认 `cacheRawData=false`。旧 `media_cache_audit.log` 的原始字节缓存增长不是当前默认路径仍泄漏的证据。
4. **二维码同步读文件在 compute worker 内。** [入口](E:/openim/openim-flutter-demo/lib/widgets/qr_scanner/qr_gallery_service.dart:20) 已转到 worker，不能把搜索到的 readAsBytesSync 直接列为主线程问题。设备同步摘要同样已有 worker，前台同步门禁已在此前修改。
5. **普通消息页不是所有状态变化都整页重建。** 标题、公告、输入、多选等有局部监听；新消息入场上限 4 个，动画有 child 复用；viewport 测量只扫描挂载行且合并到帧末。消息身份索引已缓存，回执更新仍需核对 ID 顺序，未宣称完全 O(1)。
6. **键盘、导航与玻璃效果尚缺帧证据。** Scaffold 因键盘调整高度是正常行为；[气泡布局](E:/openim/openim-flutter-demo/openim_common/lib/src/widgets/chat/chat_text_bubble_layout.dart:44)、[导航模糊](E:/openim/openim-flutter-demo/openim_common/lib/src/widgets/liquid_glass_surface.dart:131) 和图库构造是待采样点。玻璃效果已限制在导航区域，不能见到 BackdropFilter 就删除设计；要区分 UI build/layout 与 raster 工作。
7. **没有取得 Android ANR 或 iOS hang 栈。** 真正的完全无响应必须同时看 Dart、平台主线程和原生工作线程。CPU 高、GPU 慢、Overlay 拦截、异步等待及锁互等有不同证据，当前没有证实某一条链路已经导致真实设备 ANR。

## 上一轮优化前后对比

下表严格区分旧探针结果与改后源码。改后没有同条件采样，因此**不能计算性能提升百分比，也不能宣称卡顿或温升已改善**。

| 项目 | 修改前已有证据 | 当前源码变化 | 修改后实测 |
| --- | --- | --- | --- |
| 会话更新 | 1000 会话、20 条/秒、60 秒模拟时间：1200 次合并排序发布，至少 120 万条遍历；桌面总处理约 295ms | 80ms 合批，只排序变化项，统计共享；仍有线性扫描 | 待验证，不能从窗口推算固定提升率 |
| 个人表情面板 | 57×57 格子解码 3000×2000，单帧 RGBA 24000000 字节 | 优先缩略图，按布局/DPR 限制解码，上限 1024 | 待验证，不能把尺寸上限当实测 RSS |
| 长历史 | 200 页×40 条保留 8000 条；旧探针前十页均值 854µs，后十页 2252µs | 符合资格时 600 条窗口，待发/失败额外保留；索引缓存 | 待验证，特别是边缘裁剪、反向分页、锚点和多选 |
| 输入状态 | 文字不变，120 次光标变化产生 120 次 true 回调 | 过滤非文本变化，持续 true 每秒最多一次 | 待验证，旧数字不是网络包数 |
| 隐藏倒计时 | Offstage/TickerMode 关闭 10 秒仍额外构建 10 次 | 隐藏停止每秒刷新，保留一次到期遮盖 | 待验证，尤其透明覆盖和恢复前台 |
| 视频表情 | 此前源码允许任何正可见比例启动，各气泡独立播放 | 最多两个行内名额，50%/30%门槛，180ms 驻留 | 待验证，包括 F04 的挂起边界 |
| 重排行 | 原会话列表无 findChildIndexCallback | 已按会话 key/归档偏移提供映射 | 待验证，缺少前后创建/销毁计数 |
| AI 长流 | 1200 片段，最终 36000 单元，累计快照长度 21618000，1200 次通知 | 本项未修改 | 无改后值，不能称有改善 |

原日志：[集合/历史/AI/倒计时探针](E:/openim/openim-flutter-demo/.dart_tool/performance-audit/current-probes-20261011.log)、[表情解码](E:/openim/openim-flutter-demo/.dart_tool/performance-audit/current-sticker-20261011.log)、[输入事件](E:/openim/openim-flutter-demo/.dart_tool/performance-audit/current-typing-20261011.log)。这些日志没有完整真机环境及当前补丁 hash，不能作为可复现的真机 A/B 基线。另有 `media_remaining_probe.log` 的 100/1000/5000 项图库构造压力数据，但其大样本不代表当前普通入口 count=500 的实际工作量。

## DevTools 数据定位与后续验收规格

本节是待执行规格，本轮未运行。Flutter 官方建议在真实设备使用 Profile 定位性能；Debug 包含调试/JIT 等开销，不能据其卡顿量推导 Release 表现。Profile 接近 Release 的执行形态并保留性能采集能力；Release 用来复核实际用户体验，不默认提供普通 DevTools 调试连接。[Flutter 性能分析](https://docs.flutter.dev/perf/ui-performance)、[构建模式](https://docs.flutter.dev/testing/build-modes)。

| 数据 | 当前可用情况 | 要定位的内容 |
| --- | --- | --- |
| Timeline / Performance | 无导出，待验证 | 慢帧 UI 与 raster 分开；消息回调、JSON/哈希、layout/intrinsic、图片解码与慢帧对齐 |
| CPU Profiler | 无采样，待验证 | `_loadCache`、SHA、JSON、Markdown、图库快照、会话投影的 inclusive/exclusive 时间与样本数 |
| Memory | 无快照，待验证 | Dart heap、external、RSS、图片/播放器存活；关闭路由后的 retained objects 和保留链 |
| 原生诊断 | 无 ANR/hang/系统 trace，待验证 | 平台主线程、I/O/SQLite、编解码器及 SDK 回调停在哪一步 |

Performance 用于帧关联，CPU profiler 用于调用树和热点，Memory 的差异快照用于分析对象保留；原生纹理/解码器占用不能只靠 Dart heap 判断。[Performance](https://docs.flutter.dev/tools/devtools/performance)、[CPU Profiler](https://docs.flutter.dev/tools/devtools/cpu-profiler)、[Memory](https://docs.flutter.dev/tools/devtools/memory)。Android 无响应还需 ANR/线程与系统证据，不能只依据 Dart 的 Future 等待。[Android ANR 诊断](https://developer.android.com/topic/performance/issues/anr)。

建议在同一 Android 真机及同一 iPhone 上分别做基线/候选，不跨平台混算；固定 SDK、Flutter、包模式、账号数据规模、媒体文件、刷新率、网络与设备温度区间。基线须明确包括哪些先前改动，不能把当前 HEAD 当作未经确认的“优化前”。首次进入/冷缓存与重复进入/热缓存分开，每个场景重复至少 3 次。60Hz/120Hz 分别按约 16.7ms/8.3ms 的帧预算统计，记录实际刷新率；UI 和 raster 各自比较，不简单相加两条并行流水线耗时。

| 场景 | 固定操作与规模 | 前后需对比的指标 | 当前结果 |
| --- | --- | --- | --- |
| 群消息与会话列表 | 100/1000/5000 会话分档，固定消息到达速率，滚动与静置分开 | UI/raster p50/p95/p99、超预算帧率、发布/排序/行创建次数、CPU | 均待验证 |
| 聊天历史 | 连续翻旧记录，再反向翻页，穿插多选、撤回与实时消息 | 页加载/合并耗时、存活消息数、峰值内存、锚点偏移、游标连续性 | 均待验证 |
| 图片及表情 | 同一组原图/动图/视频，快速滚动及打开关闭预览 | 点击到首帧、解码像素、并行播放器、external/RSS 峰值和回落 | 均待验证 |
| 键盘与切页 | 固定长文本群聊，反复开关键盘及进出页面 20 次 | 慢帧分布、layout 次数、控制器/监听器保留链、基线内存漂移 | 均待验证 |
| 收藏和上传 | 大收藏、正常/超限文件、同步空页和异常游标 | 哈希字节/CPU、JSON 字节、写入与请求次数、等待队列长度 | 均待验证 |
| 卡住恢复 | 在受控测试条件下模拟原生不回调或网络停滞 | 最长阶段等待、遮罩解除、取消确认、迟到响应、后续操作恢复 | 均待验证 |

一次只修改一个已证实热点并重复相同操作。精细 build/layout 跟踪本身会增加开销，定位采样与最终对比采样分开；性能快照保存源码版本、未提交补丁 hash、设备和场景元数据。遵照当前限制，本轮不执行以上操作。

## 建议处理顺序

先核实 F01/F02/F03 与真实“卡死”反馈的操作场景和阶段日志，修复有证据的等待恢复问题。随后优先采样 F07/F09 的大文件与像素内存风险，再评估 F06/F08/F13 的主 Isolate 工作。会话增量优化和布局调整需以改后 Timeline/CPU 为依据；没有数据时不继续扩大上一轮改动范围。

审计阶段交付的是源码问题清单、已有证据核对和可执行的对比规格。**真机热点归因、优化前后量化对比及完全卡死根因仍未完成实测，均标为待验证。**

## 第一批源码优化（用户随后授权实施）

以下为代码路径和约束的前后对照，**不是性能实测结果**。所有 UI/raster 帧耗时、CPU、RSS、温升和真机恢复效果均待验证。

| 项目 | 改前 | 改后源码行为 | 仍需验证 |
| --- | --- | --- | --- |
| F02 历史加载等待 | SDK Future 不返回时持续 loading | 默认 30 秒内等待；超时走现有错误/重试。每个路由最多两个原生在途读取，超时仍占额度，同窗口同游标重试复用 Future。日期定位等待额度也计入时限，失效窗口不再启动排队查询 | 正常首屏、定位/分页竞争、超时重试、清空/离页与迟到回包；原生永久挂起仍需 SDK 恢复 |
| F06 图片磁盘缓存 | 命中路径同步检查目录/文件，过期时同步 stat/delete | 命中路径全部改为异步 I/O；少做一次目录检查，目录由已有写缓存入口创建 | 冷/热缓存、过期、读写/清理竞争、磁盘失败回退和慢帧 |
| F07 收藏文件摘要 | 超限原件也读完整内容计算摘要，摘要在主 Isolate | 复用 20/100 MiB 规则，先拒绝超限/空文件再哈希；合法文件由串行、可取消的流式 worker 处理。账号切换/销毁取消当前任务，旧队列不会启动旧账号的哈希 | 文件中途变化、并发选择、退出取消、缺失原件的已完成上传恢复、幂等键兼容 |
| F08 收藏空轮询 | 每页复制状态、整包 JSON 写入，含无变化页 | 空事件且水位未变时不复制集合、不执行本页缓存写入；仅水位变化时复用不可变集合但继续严格持久化 | 空页/水位推进、写入失败回滚、同毫秒分页、待提交操作恢复；其他变更仍有整包写入 |
| F09 客服聊天小图 | 小布局也可能解码原图 | 本地/远程图片及视频封面按显示尺寸×DPR 限制解码，宽高各至多 1024，使用 fit 保持比例；点开仍传原件地址 | 不同 DPR、长图、动图、本地转远程、预览；内存峰值与回落 |
| F12 朋友圈封面 | 选择和确认各读全文件字节并在 UI Isolate 计算 SHA | 保留两次一致性校验，改为 worker 流式摘要；页面关闭或账号失效取消任务，不向 UI Isolate 传整份原图字节 | 大封面、文件变化、上传未知结果恢复、关闭取消；Isolate 启动成本及 CPU |
| F19 群直播刷新 | 每次 position/buffered 更新向外广播 | 仅初始化、比例、错误或首次有效进度变化触发该回调的页面通知；纯进度更新不广播。静音、可见性和凭证的原有通知继续保留 | 边看边聊、全屏切换、首播、比例变化、重连、凭据过期和声音切换 |

实现入口：

- [历史等待与在途额度](E:/openim/openim-flutter-demo/lib/pages/chat/history/chat_history_read_gate.dart)、[接入 loader](E:/openim/openim-flutter-demo/lib/pages/chat/history/chat_history_loader.dart)。额度只约束本 loader，不宣称全应用原生查询已限制为两个；超时也不是原生取消。
- [异步图片缓存](E:/openim/openim-flutter-demo/local_plugin/extended_image_library/lib/src/network/network_image_io.dart)、[客服气泡解码](E:/openim/openim-flutter-demo/lib/pages/customer_service/widgets/customer_service_message_view.dart)。例如 200×160 布局、DPR=3 时目标边界为 600×480；这是源码限制，不是测得的实际解码尺寸或 RSS。
- [共享摘要 worker](E:/openim/openim-flutter-demo/lib/services/media/file_hasher.dart)、[收藏摘要队列](E:/openim/openim-flutter-demo/lib/pages/favorites/data/favorite_media_fingerprint.dart)、[收藏大小规则](E:/openim/openim-flutter-demo/lib/pages/favorites/data/favorite_media_upload.dart)、[收藏状态](E:/openim/openim-flutter-demo/lib/pages/favorites/data/favorite_sync_state.dart)、[仓储接入](E:/openim/openim-flutter-demo/lib/services/favorite_repository.dart)。共享 worker 从现有设备同步实现提取，设备同步保留兼容类和独立生命周期；没有建立第二套哈希实现。
- [封面校验](E:/openim/openim-flutter-demo/lib/pages/moments/moments_cover_page.dart)、[直播通知筛选](E:/openim/openim-flutter-demo/lib/pages/group_features/live/playback/live_playback_controller.dart)。

本批保持 SDK、存储格式、幂等键及主题体系；FavoriteRepository 的改动限于现有协调接线，独立摘要队列放入收藏 data 子目录。未修改 SDK 原生取消、登录退出队列、视频播放器销毁或缓存数据库架构。F01/F03/F04 等需要原生完成/取消证据的项继续保留；F13/F14/F15 等更大范围的文本、列表与布局优化等待改后采样，不靠猜测扩大改动。

验证仅做源码调用链、相对导入、共享实现迁移差异及补丁检查。28 处相对导入/导出均能定位；共享 worker 与提取前实现经纯命名替换后文本一致；本批已跟踪文件的 `git diff --check` 无错误。未新增或运行测试、analyzer、构建、安装或性能采集，这些静态结果不代表已通过编译或行为回归。之前日志没有这些改动后的值，因此不提供虚构的提升百分比。
