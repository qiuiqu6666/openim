# 异步状态与性能根因修复记录

日期：2026-10-03。范围为本轮审查已经复现的聊天、登录退出、联系人、会话列表和媒体性能问题。保留现有 Flutter、GetX、OpenIM SDK、HTTP 客户端与路由。

## 改动与维护归属

| 问题 | 根因处理 | 维护入口 |
| --- | --- | --- |
| 聊天首屏等待、重复读取历史 | 导航阶段启动 SDK 本地首批读取，路由复用请求；保留安全快照与最新消息，群资料不阻挡正文 | [历史模块](../lib/pages/chat/history/README.md) |
| 旧历史快照覆盖发送状态、发送回调更新已脱离列表的对象 | 请求前保存状态值，合并时保留较新的发送状态与本地对象身份 | [历史模块](../lib/pages/chat/history/README.md) |
| 发送构造期间编辑的草稿被清空、重复点击发送 | 输入与引用分别记录版本；只清理本次提交拥有的输入，锁定 SDK 构造而不锁网络发送 | [输入模块](../lib/pages/chat/composer/README.md) |
| 群资料尚未就绪时点击头像报错 | 群成员入口等待必要资料和权限，再执行现有导航 | [群模块](../lib/pages/chat/group/README.md) |
| 表情管理页面关闭后加载循环不停、游标不推进 | 页面和 Store 共同检查生命周期，分页必须推进；停滞返回可重试错误 | [表情模块](../lib/pages/chat/stickers/README.md) |
| SDK 退出挂起拖住界面、旧退出影响新登录 | 本地退出与 native 清理解耦，SDK login/logout 串行执行，代次保护返回结果；排队和残留账号清理重试共用 15 秒准备上限，保持 native 原序 | [会话生命周期](../lib/core/session/README.md) |
| 旧账号资料、旧登录错误与旧搜索结果影响新状态 | 请求绑定账号、令牌、查询与代次，返回和错误处理均检查所属会话；旧异常不能清凭据、导航或弹出反馈 | `core/session/`、`contacts/search/`、`contacts/add_by_search/`、`contacts/select_contacts/search_contacts/`、`pages/login/` |
| 进入主页等待 400 条会话、旧列表快照覆盖 SDK 新事件 | 主页导航不等待会话列表；后台读取按代次与事件合并，并保留删除保护 | `pages/splash/`、`pages/login/`、`pages/conversation/` |
| 群搜索结果被错误索引丢弃 | 按各结果的明确位置与类型接收，避免依赖错误的结果数量 | `contacts/select_contacts/search_contacts/` |
| 好友事件重复读取全目录、拼音计算占用界面线程 | 事件增量更新，合并目录变化；名字索引移到 worker isolate，复用未变化名字的拼音 | [联系人索引](../lib/pages/contacts/directory/README.md) |
| 存储页一次构建同月上千媒体项、拖选反复排序 | 使用 SliverGrid 按可见区域布局；目录、分组与容量按数据修订缓存，格子独立维护选择状态 | [聊天存储](../lib/pages/mine/settings/storage/README.md) |
| 朋友圈一页数据反复复制列表和通知 | 一页数据批量应用，保留版本、删除记录与权限检查 | `services/moments_repository.dart` |
| 预览当前图等待整个相册、其他图片失败阻挡当前图 | 当前原图优先显示，其他缩略图独立加载，失败可单独重试；晚到缩略图不覆盖已完成原图 | `pages/moments/moments_media_preview.dart` |
| 公共媒体界面同步检查磁盘、缩略图解码原图 | 文件可用性异步检查；格子优先缩略图并限制解码尺寸，完整预览保留原图质量与当前页 | `openim_common/lib/src/widgets/media_browser/` |

聊天缓存只保留进程内少量非私密消息，没有新增持久化消息库。账号、令牌、全局清理代次、会话清理版本和删除记录共同防止旧请求或旧页面写回失效数据。

会话删除期间保留最后事件用于失败恢复；成功后只保存消息时间、草稿时间和 seq，不继续持有已删除的消息正文或媒体元数据。

独立复核后还补齐同账号令牌更换时的最终快照保护、全局清理与会话版本判断顺序，以及有界删除记录溢出后的旧预读/最新消息种子失效。超过 1024 条删除记录时仍保持记录上限，通过重新读取 SDK 防止旧页恢复被删除消息。

## 性能测量

同一测试数据与视口下，存储页同月 1000 项的首屏实际缩略图挂载由 1000 项降至 6 项；朋友圈已有 1000 条动态时，继续加载 20 条的状态通知由 22 次降至 2 次，中间重复替换整个 1000 条列表由 20 次降至 0 次。当前选中原图完成后可以显示，其他图片加载挂起或失败不阻挡它。

十个已访问作者的前后台权限刷新保留，未将它误认为已证实的卡顿。聊天长列表的可见区域构建原本有效，也没有替换其正常实现。

## 验证要求

正规测试分别位于 `test/pages/chat/`、`test/integration/chat/`、`test/core/session/`、`test/pages/contacts/`、`test/pages/conversation/`、`test/pages/splash/`、`test/pages/mine/settings/storage/`、`test/pages/moments/media/`、`test/services/moments/` 和 `test/widgets/media_browser/`。历史复现脚本保存在忽略目录 `.dart_tool/`，不计入正规测试结果。

| 最终检查 | 结果 |
| --- | --- |
| 新增正规根因回归 | 132 项全部通过：历史与导航 22、通讯录 15、输入/分页/预读与缓存 28、全局异步生命周期 49、渲染与媒体 18 |
| 全量正规测试 | 950 项通过、18 项失败；比拆分基线增加 132 项通过，18 个失败标题全部与基线一致，无新增失败 |
| 扩大范围静态检查 | 0 errors、3 个既有 warnings、171 个 infos；退出码 2 来自保留警告，不应表述为完全无警告 |
| Android debug APK | 最终源码构建成功；`build/app/outputs/flutter-apk/app-debug.apk` |
| 差异空白检查 | 通过 |
| 独立只读复核 | 历史预读/缓存、SDK 队列和页面批量更新边界复核完成；复现边界已补修和回归 |

18 个剩余失败涉及玻璃底栏、我的页面、朋友圈菜单、昵称入口、群成员菜单、登录设备、账号安全、字体预览、关于与支付密码页面。它们与 [拆分验证记录](chat-module-refactor-validation.md) 的失败标题完全一致；主要失败点是既有界面查找及外观断言，本轮未为了通过这些测试改变相关产品界面。

静态检查保留的三个警告：`select_contacts_logic.dart` 对 RxMap.value 的保护成员访问、`user_profile _panel_logic.dart` 未使用的 `_resetAvatar`、`photo_browser.dart` 现有的 `SystemChrome.latestStyle` 测试可见性。新增会话、搜索与删除控制模块的局部检查无错误或警告。

本地忽略日志：

- [最终全量测试](../.dart_tool/logic-audit-20261003/root-fixes-full-tests.txt)
- [失败基线对照](../.dart_tool/logic-audit-20261003/failure-baseline-comparison.txt)
- [最终静态检查](../.dart_tool/logic-audit-20261003/all-fixes-analyze.txt)
- [最终 Android 构建](../.dart_tool/logic-audit-20261003/root-fixes-android-build.txt)
- [缓存边界回归](../.dart_tool/logic-audit-20261003/cache-final-regressions.txt)
- [性能测量与媒体回归](../.dart_tool/performance-audit/render_hot_paths_after_fix_result.txt)
- [SDK 清理重试准备边界](../.dart_tool/global-fixes-session-final-tests.txt)

本轮使用请求顺序、迟到回调、实际格子挂载量和状态通知次数验证根因；实机帧率、网络端到端耗时和 iOS 构建需要单独测量。
