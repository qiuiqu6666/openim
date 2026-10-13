# 高频使用性能检查

**当前状态：** 用户随后授权“开始优化”，聊天与会话列表的实现已更新；最新落实范围见文末“聊天与会话列表优化落地”。此前各节保留的是修改前的检查证据，不能当作当前实现仍完全相同。本轮优化未构建、未运行测试或真机性能测量。

检查日期为 2026 年 10 月 11 日，范围为当前 OpenIM Flutter 客户端。较值得优先处理的区域是表情面板的大图解码、同屏视频表情并行播放，以及大量消息下的数据集合更新。相册与定位同步原先会在前台空闲时执行，本轮已按要求改为仅后台允许执行。

下文区分已经复现的额外工作量与推断的卡顿、耗电风险。本次没有取得 Android 或 iPhone 真机的温升、功耗或 profile 帧耗时，不能把桌面测试耗时换算成手机帧率或认定已经发生过热。当前连接的是 Android 模拟器，安装的是 debug 程序。

## 相册与定位同步的本轮修改

- 前台一律暂停，包括聊天、群聊、其他页面和无人操作的静置状态；不启动相册扫描、同步定位和上传。
- 退到系统后台后等待 5 秒，再按账号状态、通话状态、权限及网络设置决定是否执行。后台保留的聊天路由不再阻止同步。
- 返回前台即撤销执行资格并发送取消，取消令牌传递到定位订阅、文件哈希和上传请求。晚到结果不能将被取消的任务标记完成。
- 同一轮资源释放前不会另起一轮上传。待传定位保留原编号，媒体保留既有分片续传机制。
- 前台的高频触摸事件直接返回，不再不断取消和重建同步等待计时器。
- 定位同步要求系统已经授予后台定位权限；仅“使用期间允许”时跳过，不自动申请权限。iOS 增加后台定位能力，仍限定每次登录一次新定位、10 秒超时和结束后停止订阅。

主要修改位于 [同步调度](E:/openim/openim-flutter-demo/lib/core/device_sync/device_sync_runtime.dart:136)、[应用前后台回调](E:/openim/openim-flutter-demo/lib/core/controller/app_controller.dart:80)、[平台定位入口](E:/openim/openim-flutter-demo/lib/core/device_sync/platform/device_sync_platform_source.dart:183)。复用既有 DeviceSyncRuntime、Runner、存储、取消令牌和平台接口，没有替换 IM 消息链路。

这是进程内的后台执行策略。系统挂起或结束进程后，不保证继续上传；当前没有 Android WorkManager 或 iOS 后台 URLSession 任务。后台定位也受系统权限和节流限制。[Android 后台定位限制](https://developer.android.com/about/versions/oreo/background-location-limits)、[Apple 定位授权说明](https://developer.apple.com/documentation/corelocation/cllocationmanager/requestwheninuseauthorization())。

收尾时读取到 iOS 两项 Always 定位权限说明为“用于聊天时发送位置”，与本轮先前写入的后台定位说明不同。这处后续变动已保留；该文案尚不能完整解释后台同步用途，需与最终产品文案一起核对。iOS 未编译或真机验收。

## 优先处理的剩余问题

### 表情面板完整解码原图

优先级高。打开个人表情面板、快速翻看大量大图或动图时，容易增加瞬时内存、解码和回收开销。

图片表情的 `previewURL` 直接返回原图，忽略图片缩略图；面板和管理页的 `Image.network` 没有指定解码尺寸。[图片来源](E:/openim/openim-flutter-demo/lib/pages/chat/stickers/personal_sticker_store.dart:40)、[面板图片](E:/openim/openim-flutter-demo/lib/pages/chat/stickers/personal_sticker_panel.dart:183)、[管理页图片](E:/openim/openim-flutter-demo/lib/pages/chat/stickers/personal_sticker_management_page.dart:97)。

专项探针向真实面板提供一张 3000×2000 PNG，在 57×57 的格子中仍得到 3000×2000 的解码图像。单张 RGBA 像素约 24 MB，不含其他对象、缓存或多帧开销。此数值不是进程总内存。

建议统一使用缩略图，并根据格子尺寸和设备像素比限制解码尺寸。动图网格可另设首帧预览策略。聊天中的图片表情气泡已有尺寸限制，本结论针对个人面板和管理页。

### 同屏视频表情各自循环播放

优先级高，尤其影响连续刷含多个视频表情的聊天记录。每个可见气泡都会创建自己的播放器并静音循环；只要露出一点就可以开始播放，没有全局并发上限。[播放器创建和循环](E:/openim/openim-flutter-demo/lib/pages/chat/stickers/sticker_video_bubble.dart:135)、[可见性判断](E:/openim/openim-flutter-demo/lib/pages/chat/stickers/sticker_video_bubble.dart:287)。

现有测试确认：三个同屏气泡同时有三个播放器；1% 可见就启动，变为 0 后释放，再露出时重新创建。这会增加解码资源需求，边缘反复滚动还会产生播放器反复初始化的成本。

后台、页面覆盖和离屏停止已有保护，不能将此项称为播放器泄漏。建议在保留视频表情体验的前提下评估并发上限、可见比例阈值及短暂驻留时间。

### 高频群消息仍导致全会话合并排序

优先级中，主要影响会话很多且群消息持续活跃的账号。正常在线回调合并窗口为 16 毫秒，批次发布仍会重新建立全会话映射、投影、排序和替换列表。[批次窗口](E:/openim/openim-flutter-demo/lib/pages/conversation/conversation_logic.dart:84)、[合并排序](E:/openim/openim-flutter-demo/lib/pages/conversation/conversation_logic.dart:295)。

使用真实控制器与模拟 SDK 回调，在 1000 条会话、每秒 20 条消息、60 秒模拟时间下，发生 1200 次合并排序发布，至少遍历 120 万条会话记录。健康回调的额外会话快照查询为 0，说明此前重复查询问题已有保护。

桌面探针处理这些回调总计约 295 毫秒，单凭这个结果不能认定手机会掉帧。确认的问题是工作量随会话数和回调次数增长；隐藏页面已有渲染保护，但控制器的数据处理继续发生。建议按会话 ID 增量更新，仅在影响排序的字段变化时调整顺序，并评估更合理的发布节奏。

### 长时间翻历史会累积大量消息对象

优先级中。普通历史分页保留全部已加载消息，每次继续合并去重并排序；列表还会为整个消息集合重建索引。[历史合并](E:/openim/openim-flutter-demo/lib/pages/chat/history/chat_history_loader.dart:328)、[全量排序](E:/openim/openim-flutter-demo/lib/pages/chat/history/chat_history_loader.dart:442)、[列表索引](E:/openim/openim-flutter-demo/lib/pages/chat/messages/widgets/chat_message_list.dart:82)。

真实加载器探针连续加载 200 页、每页 40 条后保留 8000 条消息。各次发布快照的记录数累计为 804000；这表示重复处理量，不是同时存活的对象数。前十页平均约 854 微秒，最后十页约 2252 微秒，仅作桌面趋势参考。

最新消息模式已有约 600 条的自动裁剪；阅读旧记录、选择消息等状态会暂缓裁剪。因此风险集中在长历史阅读，不是所有聊天无限增长。建议设计保留阅读锚点的历史窗口，兼顾向前向后翻页、选中和引用跳转。

### 光标变化也重复发送正在输入状态

优先级中，修改成本较低。输入控制器的监听器每次触发都发送 `true`，文字相同的过滤只用于草稿逻辑，不能拦住光标或输入法组合状态变化。[输入监听](E:/openim/openim-flutter-demo/lib/pages/chat/composer/chat_composer_controller.dart:154)、[单聊 SDK 调用](E:/openim/openim-flutter-demo/lib/pages/chat/chat_logic.dart:989)。

专项探针保持文字不变，仅移动光标 120 次，得到 120 次 `true` 回调、空闲后一次 `false`，草稿写入为 0。普通单聊会将这些回调传给 SDK；尚未证明底层实际产生同样数量的网络包。

建议只在有意义的文本编辑时报告输入，并对连续 `true` 限频或只发送状态边沿，同时保留停止输入的超时通知。

### AI 长回复逐片段生成完整文本并解析 Markdown

优先级中，主要出现在长回复和快速流式输出。每个片段触发一次状态通知并生成完整文本快照，展示层把完整文本交给 MarkdownBody；依赖库在文本变化时重新解析。[流状态更新](E:/openim/openim-flutter-demo/lib/pages/ai_assistant/streaming/assistant_stream_state.dart:96)、[完整文本快照](E:/openim/openim-flutter-demo/lib/pages/ai_assistant/streaming/assistant_stream_state.dart:209)、[Markdown 展示](E:/openim/openim-flutter-demo/lib/pages/ai_assistant/presentation/messages/ai_assistant_text.dart:95)。

探针输入 1200 个片段、每片 30 个文本单元：最终文本 36000 个单元，通知 1200 次，历次快照长度累计 21618000 个单元。累计长度不代表峰值内存，通知次数也不等于渲染帧数，Flutter 会合并同帧更新。

建议按帧或短时间窗口合并发布，并缓存已经完成的 Markdown 区块，只更新尾部。现有实现已将流式气泡更新与列表增删分开，不应笼统认定整个聊天列表每个片段都重建。

### 隐藏页面的阅后即焚倒计时继续刷新

优先级低。每个组件自己的周期计时器每秒调用 `setState`，没有页面可见性或 TickerMode 判断。[倒计时实现](E:/openim/openim-flutter-demo/openim_common/lib/src/widgets/chat/chat_expiring_content.dart:38)。

真实组件放在 Offstage 且关闭 TickerMode 后，10 秒仍额外构建 10 次。这里指 App 仍运行、组件仍挂载的隐藏页面，不代表操作系统挂起后仍不停绘制。

建议只刷新可见内容，必要时使用共享时钟；重新显示时根据绝对截止时间计算剩余时间。隐藏页面不能延长实际过期时间或改变 SDK 删除规则。

### 后台同步被中断后的重复扫描和哈希

前台竞争问题已按要求处理，后台重试的重复工作仍存在。每轮相册扫描从第一页开始；文件已有 prepared 记录、但未完成上传时，仍会再次读取并计算完整哈希。[分页起点](E:/openim/openim-flutter-demo/lib/core/device_sync/platform/device_sync_platform_source.dart:58)、[重复哈希入口](E:/openim/openim-flutter-demo/lib/core/device_sync/device_sync_runner.dart:142)。

使用真实 Runner、隔离存储及小文件夹具，在完成哈希后中断 5 次、第六次完成，同一文件被打开和哈希 6 次，扫描启动 6 次。这个实验验证调用次数；没有对真实大视频测量吞吐和温升。

哈希已有独立 isolate、流式读和取消保护，不能称为主线程同步读取。后续若优化，应在校验文件身份和内容未变的前提下复用摘要及扫描进度，保留现有内容一致性和分片校验。

## 已有保护的区域

本次核对到以下保护，不列为当前确定的重复工作缺陷：已读回执限频、群成员查询缓存、通知音间隔、会话最新消息修复的回调抵消、隐藏会话页缓存、聊天图片尺寸限制、媒体预加载边界，以及部分游戏和钱包轮询的页面可见性限制。相册哈希与二维码图像分析已有后台 isolate。

这些结论只针对核对到的调用链；视频编解码器、GPU、原生 SDK、网络和设备热管理仍需真机数据判断。

## 验证记录与边界

性能检查阶段，185 项既有相关测试与 7 项专项探针通过。探针覆盖会话批次、历史累积、AI 文本快照、隐藏倒计时、表情图像解码、同步重试及输入事件。

后台策略修改后、用户要求停止构建测试前，最后一轮相关测试为 151 项通过、1 项既有失败。失败为设置首页缺少测试所要求的 `settings-device-sync` 入口：从 HEAD 提取的原测试同样失败，首页本轮没有修改。未恢复入口或删除该断言。同步核心、取消、快速切换、延迟成功响应、偏好持久化和后台权限用例通过。

停止要求前的静态检查无问题，Android debug 构建曾成功。其后还有前台触摸快速返回的小调整，最终源码未再次构建；遵照要求，后续不再运行构建或测试。没有安装生成的安装包、进行 iOS 编译、访问真实相册或执行真实上传。

本地证据保存在忽略目录 `.dart_tool/performance-audit/`，清理构建缓存可能删除它们：

- [性能专项结果](E:/openim/openim-flutter-demo/.dart_tool/performance-audit/current-probes-20261011.log)
- [表情图片解码](E:/openim/openim-flutter-demo/.dart_tool/performance-audit/current-sticker-20261011.log)
- [输入事件探针](E:/openim/openim-flutter-demo/.dart_tool/performance-audit/current-typing-20261011.log)
- [后台策略回归](E:/openim/openim-flutter-demo/.dart_tool/performance-audit/background-policy-regression-20261011.log)
- [既有设置入口失败复核](E:/openim/openim-flutter-demo/.dart_tool/performance-audit/background-policy-existing-entry-failure-20261011.log)

下一轮性能优化建议先处理表情面板解码，再评估视频表情并发，随后处理会话增量更新与输入状态限频。真机测量应分场景观察帧耗时、内存、CPU、播放器数量和温升，避免用一个整体温度结果推断具体根因。

## 第二轮静态检查的新增发现

本轮继续检查收藏、朋友圈、客服、直播和游戏页面。仅阅读当前源码与调用链，没有运行构建、测试或负载探针，也没有修改业务代码。以下优先级按触发场景和资源开销判断，尚未量化掉帧或温升。

### 收藏文件先完整计算哈希再判断是否超限

优先级高。添加文件或视频收藏时，选择器检查文件存在、非空及文件头，但没有在入口限制文件大小；`createMedia` 读取文件长度后，直接对完整文件计算 SHA-256。20 MiB 或 100 MiB 的大小限制在后续上传器中才执行。因此，首次选择一个最终不允许上传的超大文件，也会先承担整文件读取和校验成本。

哈希使用异步文件流，但摘要计算仍在调用方 isolate 上，没有独立 worker；校验期间也没有接收取消令牌。异步读取不等于 CPU 计算已移出 UI isolate，切换页面或账号只会在哈希结束后的 guard 中拦住后续动作。

来源：[选择器检查](E:/openim/openim-flutter-demo/lib/pages/favorites/media/favorite_picked_media.dart:20)、[先计算完整哈希](E:/openim/openim-flutter-demo/lib/services/favorite_repository.dart:1343)、[后检查大小](E:/openim/openim-flutter-demo/lib/pages/favorites/data/favorite_media_upload.dart:73)。

建议把大小限制移到摘要计算之前，并将大文件校验放入可取消、限制并发的 worker。收藏预览和转发也在调用方 isolate 上执行文件哈希，适合一起整理为有明确所有权的公共能力：[预览校验](E:/openim/openim-flutter-demo/lib/pages/favorites/media/favorite_preview_loader.dart:78)、[转发校验](E:/openim/openim-flutter-demo/lib/services/favorite_message_builder.dart:268)。

### 收藏缩略图重新出现时重新下载和校验

优先级高，影响反复上下滚动图片收藏和多次打开收藏列表。列表项初始化时创建独立 loader，申请访问授权、下载文件、计算哈希、完整读取压缩字节，再解码成不超过 160 像素的预览。加载结束即关闭 loader 并清理临时原件；列表项销毁时再移除预览图缓存。列表项重新创建后，这条链路会重走。

这里已经有限制解码尺寸，问题主要是下载、校验和临时文件的重复工作。缺少缩略图资源的图片收藏还会选择原图作为来源。多个列表项可以独立启动，没有看到列表级的统一并发限制。只有行真正销毁再创建才会重新加载，普通 rebuild 不会重新执行 initState。

来源：[资源选择和列表项初始化](E:/openim/openim-flutter-demo/lib/pages/favorites/media/favorite_item_thumbnail.dart:11)、[下载后读取与缩图](E:/openim/openim-flutter-demo/lib/pages/favorites/media/favorite_item_thumbnail.dart:90)、[授权下载与清理](E:/openim/openim-flutter-demo/lib/pages/favorites/media/favorite_preview_loader.dart:41)。

建议保留私密资源校验，在账号、资源版本和授权范围内使用有容量上限的短期缩略图缓存，统一限制下载及校验并发；退出账号或权限失效时清理，不能直接改为无限公共缓存。

### 收藏增量同步仍重写整份本地元数据

优先级中。分页、上传检查点和增量同步都调用 `_saveCache`，将已加载收藏、请求编号、媒体任务及同步状态统一序列化为 JSON，再写入一个 SharedPreferences 键。处于搜索或分类视图时，为保留原列表还会读取并解析旧 JSON。写入虽然串行，但没有合并冗余队列；JSON 转换在调用方 isolate 上执行。

收藏同步默认每分钟触发一次，按账号持有、只区分应用前后台，不要求收藏页面仍可见。变更接口即便返回空事件页，也会执行 commit 和保存。因此打开过收藏后返回聊天，仍可能在前台产生整份缓存序列化和写入；具体成本取决于已加载收藏量。

来源：[账号级同步绑定](E:/openim/openim-flutter-demo/lib/services/favorite_runtime.dart:58)、[一分钟轮询](E:/openim/openim-flutter-demo/lib/pages/favorites/data/favorite_sync_binding.dart:16)、[每页提交](E:/openim/openim-flutter-demo/lib/pages/favorites/data/favorite_change_synchronizer.dart:31)、[整份缓存写入](E:/openim/openim-flutter-demo/lib/services/favorite_repository.dart:626)。

建议将列表缓存和必须持久化的同步水位、幂等编号、上传检查点分开。普通展示缓存可以合并更新，关键持久化不能为了限频而丢失原子性或续传保证。前台账号级增量同步本身有必要，问题是每次都重做与变更量无关的工作。

### 上传进度触发大范围界面刷新

优先级中。朋友圈每次上传进度回调都会通知整个草稿 store，发布页监听后调用页面级 `setState`。收藏也把每次上传进度广播到整个 repository，收藏列表通过 AnimatedBuilder 监听它；列表 getter 还会复制已加载条目。

因此上传进度很密集时，文本、图片网格、筛选栏或收藏列表等不依赖当前进度的内容也会重新构建。Flutter 会合并同帧刷新，不能把网络回调次数直接等同于实际绘制次数。

来源：[朋友圈进度通知](E:/openim/openim-flutter-demo/lib/pages/moments/moments_draft_store.dart:513)、[发布页整体刷新](E:/openim/openim-flutter-demo/lib/pages/moments/moments_compose_page.dart:134)、[收藏进度广播](E:/openim/openim-flutter-demo/lib/services/favorite_repository.dart:1390)、[收藏列表监听](E:/openim/openim-flutter-demo/lib/pages/mine/secondary/favorites_page.dart:1654)。

建议只让进度组件监听进度，按帧或有意义的百分比变化合并通知。成功、失败和完成状态必须即时发布；不需要因此降低真实上传速度。

### 客服聊天的小图片没有限制解码尺寸

优先级中到高，取决于发送图片的分辨率。客服媒体气泡显示为 200×160，但本地 `Image.file` 没有 cacheWidth/cacheHeight，远程 ImageUtil 调用也没有传解码尺寸或开启 lowMemory。文件大小限制是 40 MB，不能限制展开后的像素内存。

以 4000×3000 图片为例，单帧 RGBA 像素理论上约 48 MB；这是尺寸计算，未做本轮实测。连续发送多张手机原图时，会增加解码、缓存和垃圾回收压力。客服选择器允许一次选择最多 9 个附件，但并不意味着 9 张一定同时完整解码。

来源：[气泡图片](E:/openim/openim-flutter-demo/lib/pages/customer_service/widgets/customer_service_message_view.dart:158)、[显示尺寸](E:/openim/openim-flutter-demo/lib/pages/customer_service/customer_service_tokens.dart:44)、[选择器和附件限制](E:/openim/openim-flutter-demo/lib/pages/customer_service/media/customer_service_media_picker.dart:23)、[ImageUtil 默认参数](E:/openim/openim-flutter-demo/openim_common/lib/src/utils/image_util.dart:29)。

建议按气泡实际尺寸和设备像素比限制解码，完整原图留给打开预览后的有界查看流程。

### 客服历史合并会反复扫描已有消息

优先级中，集中在长客服会话、重连或 WebSocket 不可用时。历史返回的每条消息都分别执行 `_entries.where`、`removeWhere` 和 `indexWhere`。若已有 N 条、一次刷新 M 条，合并的扫描工作近似随 N×M 增长；客户端没有看到条目数量上限。

WebSocket 未连接时使用 15 秒历史轮询，连接成功后停止轮询；页面覆盖和 App 后台也有 suspend 保护，不能称为全局永久轮询。后端实际返回多少历史记录决定风险大小，源码不足以认定每次都返回完整历史。

来源：[历史刷新](E:/openim/openim-flutter-demo/lib/pages/customer_service/customer_service_controller.dart:168)、[逐条多次扫描](E:/openim/openim-flutter-demo/lib/pages/customer_service/customer_service_controller.dart:248)、[历史接口](E:/openim/openim-flutter-demo/lib/pages/customer_service/data/customer_service_api.dart:96)。

建议维护消息 ID 和本地回声 ID 索引，整批合并后统一排序与发布；在接口支持时增加增量游标或有界历史窗口。

### 游戏倒计时缺少页面可见性条件

优先级低。六合彩最新开奖卡片每秒 setState，条件只有 mounted 和 controller.current；current 只表示控制器、账号和业务范围仍有效，不包含页面是否被覆盖、TickerMode 或应用是否前台。

卡片即便显示已开奖或没有可用倒计时，也继续定时构建；页面仍挂载但被覆盖时亦然。控制器的网络刷新有后台保护，但这不能停止卡片自己的 Timer。此处与第一轮阅后即焚计时器属于同类问题，涉及另一个实际组件。

来源：[卡片周期刷新](E:/openim/openim-flutter-demo/lib/pages/group_features/mark_six/widgets/mark_six_latest_card.dart:72)、[current 的定义](E:/openim/openim-flutter-demo/lib/pages/group_features/mark_six/data/mark_six_controller.dart:37)。建议仅在可见且倒计时确实变化时刷新，恢复显示后按服务端时钟重新计算。

### 直播播放器的进度通知扩散到整个播放界面

优先级低到中。播放器所有 value 变化都进入控制器 `_changed`，即使已经进入稳定播放、只是播放位置变化，也会 notifyListeners。LivePlayerView 的整个播放层和控件通过 AnimatedBuilder 监听控制器，因此纯进度变化也会重建不需要变化的界面。

来源：[播放器监听与广播](E:/openim/openim-flutter-demo/lib/pages/group_features/live/playback/live_playback_controller.dart:135)、[无条件通知](E:/openim/openim-flutter-demo/lib/pages/group_features/live/playback/live_playback_controller.dart:155)、[界面整体监听](E:/openim/openim-flutter-demo/lib/pages/group_features/live/playback/live_player_view.dart:177)。

建议区分首次就绪、缓冲、错误、静音等业务状态变化，纯播放位置交给需要进度的局部组件。现有前后台和播放界面所有权已有保护，本项不表示离开直播后播放器泄漏。

## 补充优化顺序

先处理收藏的大小校验顺序及可取消哈希，再处理收藏缩略图重复下载和客服图片解码；随后拆分收藏持久化及上传进度通知。游戏倒计时和直播控件刷新可以作为低风险的后续优化。第一轮的个人表情解码与视频表情并发仍属于高优先级，不因本轮新增发现而降低。

## 聊天对话页与消息会话列表专项复核

按最新要求，范围收紧到这两个页面。本轮只阅读源码及本地 Flutter 实现，没有运行构建、测试或性能探针，也没有修改这两个页面的业务代码。下面的优先顺序针对处理价值；实际掉帧及温升仍未在真机测量。

### 会话列表：全量处理叠加排序后的行重建

1. **全量更新链路。** `ConversationLogic.onChanged` 对每批变化建立所有会话的映射、进行群状态投影、排序并替换整个列表。页面随后再次遍历全部会话，生成筛选结果、归档集合和分组未读统计；首页未读汇总也读取完整会话集合。16 毫秒的合并窗口无法把相隔 50 毫秒的消息合成一批。会话多、活跃群多时，少量会话的变化仍造成成片工作。隐藏会话页有缓存保护，但控制器仍处理数据。建议维护按 ID 的数据与排序索引，区分内容变化和排序变化，并增量维护统计。参见 [控制器](E:/openim/openim-flutter-demo/lib/pages/conversation/conversation_logic.dart:295)、[页面扫描](E:/openim/openim-flutter-demo/lib/pages/conversation/conversation_view.dart:250)、[首页汇总](E:/openim/openim-flutter-demo/lib/pages/home/home_view.dart:208)。

2. **新增发现：排序缺少行位置映射。** 主列表使用 `ListView.builder`，外层 `ConversationSlideScope` 有稳定的会话 key，但没有 `findChildIndexCallback`。新消息把会话顶到前面、置顶或筛选改变顺序时，框架不能依靠该回调把旧行映射到新位置，移动的行存在销毁并重建的风险。行持有的滑动控制器随挂载创建、卸载释放，子组件也可能重新初始化。这是与全量排序叠加的额外开销，不能直接断言头像必然重新下载。建议基于最终可见列表建立 key → index 映射，考虑顶部归档入口的偏移；不应通过跨行复用滑动控制器绕过生命周期。参见 [列表入口](E:/openim/openim-flutter-demo/lib/pages/conversation/conversation_view.dart:406)、[行 key](E:/openim/openim-flutter-demo/lib/pages/conversation/conversation_view.dart:532)、[控制器生命周期](E:/openim/openim-flutter-demo/lib/pages/conversation/widgets/conversation_slide_scope.dart:25)。本地 Flutter `scroll_delegate.dart` 对缺失回调明确说明可能丢失重排行的状态；本轮未运行重排实验，发生频率和耗时未量化。

### 聊天页：媒体解码和长历史下的重复工作

3. **同屏视频表情同时解码循环。** 每个可见气泡独立启动播放器，可见比例大于零就播放，尚无统一并发限制或驻留门槛。多个视频表情同屏和边缘反复滚动比普通文字聊天更值得优先优化。建议统一播放调度，只允许有限数量的充分可见气泡播放，其余使用封面。当前离屏、后台和路由覆盖已有停止保护。参见 [可见性入口](E:/openim/openim-flutter-demo/lib/pages/chat/stickers/sticker_video_bubble.dart:287)。

4. **长历史与列表索引反复重建。** 历史分页保留已加载集合，合并时去重和排序；`ChatMessageList` 每次响应式构建重新生成整份 ID 数组、索引映射与集合。这些构建还依赖焦点消息、加载状态等，不局限于消息增删。新消息动画完成也通知父列表刷新，但不是每个动画帧都重建全列表。同帧通知可能被 Flutter 合并，不能直接按回调次数计算构建次数。建议优先缓存按消息结构版本生成的索引，将焦点、状态和单条内容更新隔离；较大的历史窗口再做保留阅读锚点的分页裁剪。最新模式已有约 600 条裁剪，不能简单把相同上限强加给正在阅读和多选的历史。参见 [索引生成](E:/openim/openim-flutter-demo/lib/pages/chat/messages/widgets/chat_message_list.dart:80)、[动画结束通知](E:/openim/openim-flutter-demo/lib/pages/chat/messages/arrival/chat_message_arrival_animations.dart:53)。

5. **个人表情面板原图解码。** 小格子仍取原图且未限制解码尺寸，频繁打开和滚动面板可能造成内存尖峰及回收压力。优先使用缩略图并限制目标像素；普通图片表情气泡已有解码尺寸保护。参见 [面板](E:/openim/openim-flutter-demo/lib/pages/chat/stickers/personal_sticker_panel.dart:183)。

6. **单聊输入状态重复上报 SDK。** 光标与输入法状态变化也触发正在输入回调；文本相同的过滤没有作用于这条链路。建议只对实际文本编辑报告输入，并合并连续状态。此问题涉及普通单聊，不能泛化为所有群聊都在发送输入状态，也未确认底层网络包数。参见 [输入监听](E:/openim/openim-flutter-demo/lib/pages/chat/composer/chat_composer_controller.dart:154)。

7. **隐藏聊天页的阅后即焚计时器。** 仍挂载的倒计时组件每秒更新，即使页面被覆盖或关闭 TickerMode；挂载数量增加时产生额外唤醒和构建。建议暂停不可见组件的显示刷新，恢复时按绝对截止时间重算，不改变消息到期删除规则。参见 [倒计时](E:/openim/openim-flutter-demo/openim_common/lib/src/widgets/chat/chat_expiring_content.dart:38)。

### 本轮排除的误判

- 新消息入场动画最多同时 4 个；动画帧使用局部 `AnimatedBuilder` 并复用 child，不是整份聊天列表每帧重新构建。
- 滚动可见性测量合并到帧末，只扫描已挂载行，且有前后台与当前路由检查，并未对全部历史消息逐条测量。
- 归档和分组状态通过会话 ID 查映射，不是每一行再次遍历整个分组集合。
- 聊天消息列表已有 key 到索引映射；本轮指出的缺失发生在主会话列表，两者不能混同。
- 已读回执限频、群成员缓存、通知音间隔及媒体离屏释放已有保护，本轮没有证据把它们列作首要缺陷。

处理顺序建议：会话列表的增量更新与重排映射；视频表情并发和面板图片解码；聊天索引缓存与长历史窗口；输入状态限频及隐藏倒计时。若主要反馈是发热，先处理媒体并行解码；若主要反馈是大量群消息下列表卡顿，先处理会话更新链路。

## 聊天与会话列表优化落地

2026-10-11，按用户“开始优化”实施，继续遵守“不构建测试”。复用现有 SDK、GetX、分页和媒体组件，没有重写数据源或消息传输。

| 项目 | 当前修改 |
| --- | --- |
| 会话处理 | 普通回调合并窗口从 16 毫秒改为 80 毫秒；只排序本批变化/新增行，再与未变化顺序合并；完整首次加载仍采用 SDK 排序。保留旧群身份投影、删除保护和已读投影。 |
| 分组与未读 | 新增控制器所属的共享派生快照，单聊/群聊页及首页角标共用；会话、归档或分组改变时失效，无关 UI 更新复用统计。 |
| 重排行 | 为最终筛选列表提供稳定 key 到 index 的映射，包含顶部归档入口偏移；继续由每个行组件拥有和释放滑动控制器。 |
| 视频表情 | 全局最多两个行内播放名额，初始化/释放也占用名额；50% 可见、180 毫秒驻留后申请，低于 30% 停止，避免边缘反复启停；等待时显示封面，离屏/覆盖/后台/销毁撤销等待，释放完成后移交名额。全屏预览不计入行内名额。 |
| 历史窗口 | 旧/新方向分页完成时，符合当前路由、非多选/日期定位、仍靠近对应边缘等条件才保留该端 600 条非待发消息。发送中/失败对象额外保留；裁剪较新端建立 newer 游标，裁剪较旧端恢复 older 游标和 hasMore，继续从 SDK 回读，不删除历史。 |
| 聊天索引 | 列表通知标记待核对；ID 顺序没变时复用数组、索引和集合。加载、焦点和入场结束刷新不再重建 SDK 索引，临时展示行保持独立处理。 |
| 图片表情 | 面板、管理和拖拽统一尺寸受限的图片组件，优先缩略图，缺失时回退图片原图；按布局和 DPR 解码，上限 1024 像素。大图预览保留原地址。 |
| 输入状态 | 光标和仅组合区变化不报告输入；实际文字变化时，连续 true 最多每秒一次，停止编辑一秒后仍发 false。 |
| 阅后即焚 | 隐藏/后台停止每秒显示刷新；仍保留一次绝对截止时间回调遮盖过期内容，恢复时重算。SDK 的删除规则未改。 |

新增职责分别归属 conversation/summary、chat/history、chat/messages 和 chat/stickers，模块维护说明同步更新。超长控制器仅增加既有模块接线与资格判断，独立排序、快照、裁剪和播放名额逻辑放在专用文件；没有借性能优化迁移整份控制器。

源码复核覆盖了回调合并、排序键、归档偏移、缓存失效、账号控制器关闭、候播取消、播放器初始化/释放、历史双向游标、多选保护及过期遮盖。Dart 格式化能够解析修改文件，差异空白检查通过；这不等同编译、静态类型检查或运行通过。没有执行 analyzer、构建、测试、性能探针或安装。

剩余边界：会话映射、旧群投影和派生快照仍有线性扫描，尚未变成完全逐行的 O(1) 更新；会话列表仍通过原有响应式列表发布。历史裁剪在多选、离开边缘或页面非当前时会暂缓，因此 600 是符合资格时的目标窗口，不是任意状态下的总内存硬上限。新分页窗口的锚点恢复、实际播放资源上限及 Android/iOS 真机帧耗时、内存和温升尚未运行验证，不报告具体提升比例。
