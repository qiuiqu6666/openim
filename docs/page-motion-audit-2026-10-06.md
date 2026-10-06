# 页面抖动与布局位移审计（2026-10-06）

本次找到多处局部或整段内容位移。主要原因是异步数据改变布局高度、刷新卸载已有列表、图片占位与真实比例不同；没有证据表明所有页面都存在统一的导航或安全区故障。

这是排查报告，尚未修复下表的业务 UI 问题。诊断测试通过表示成功复现、记录了现状，不表示页面已经稳定。

## 范围和证据等级

- 当前工作区快照：`lib/pages` 共 749 份 Dart；另扫描 `openim_live/lib/src/pages` 4 份、公共 widgets 121 份、应用 widgets 10 份。枚举到 141 个满足命名与基类条件的 public Page/Screen 定义。这个数字不等于独立路由数，排除了部分 View、Sheet、Picker 和继承自业务基类的入口；通话、选择器和弹层另沿调用链检查。
- 检查路由、主标签页、头像/媒体尺寸、异步分支、分页、刷新、前后台恢复、在线状态、输入提示、键盘与安全区域。各模块完整文件和入口定义见 [入口清单](E:/openim/openim-flutter-demo/test/audits/page_motion/page_entry_inventory.json)。设置/朋友圈/群扩展的细分清单见 [模块清单](E:/openim/openim-flutter-demo/test/audits/page_motion/settings_moments_motion_inventory.json)。
- **动态复现**：实际生产页面或组件在 Widget Test 中测得位置或尺寸变化，网络和 SDK 回复用本地夹具控制。没有用测试替代布局。
- **源码确认的风险**：已找到会改变布局或列表的条件分支，但尚未测量其最终屏幕位移。主聊天列表有锚点修正时尤其不能把组件增高直接等同于可见页面跳动。
- **待验证候选**：需要设备时序、额外数据或完整路由链才能确定，不能当作已发生的故障。
- 本次未逐页安装 APK、未逐机型验证，也未运行真实后端、真实通话或 iOS/Web。数值是指定夹具下的 Flutter 逻辑像素；不同字体、数据、宽度和平台可能不同。
- 工作区存在其他任务的并发修改，因此清单和行号是本次读取快照。当前仓库没有可用的 GitNexus 索引，采用当前源码与测试证据，没有借用其他仓库的索引结论。

## 已动态复现

P2 表示应修复的日常使用体验问题；P3 表示幅度较小、局部或较窄触发条件。没有确认 P1。

| 编号 / 优先级 | 页面或组件 | 触发与实测 | 根因及证据 |
| --- | --- | --- | --- |
| D01 / P2 | 群成员非好友详细资料 | 已固定入群时间、邀请人；账号从无到有时，两项都下移 **57px**。清空再返回同一账号会往返移动。头像 **0px**。 | [条件插入账号详情行](E:/openim/openim-flutter-demo/lib/pages/contacts/user_profile_panel/user_profile_panel_view.dart:111)；[刷新先撤销旧账号](E:/openim/openim-flutter-demo/lib/pages/contacts/user_profile_panel/identity/group_profile_account_state.dart:59)。前台恢复、权限或资料更新可触发重查。此前修复的顶部身份区域已预留空间，当前问题在下方详情。 |
| D02 / P2 | 共同群聊 | 30 项列表滚动到 400；刷新期间 **400 → 0**，相同数据返回仍为 **0**。 | [刷新清表并通知](E:/openim/openim-flutter-demo/lib/pages/contacts/common_groups/common_groups_store.dart:39)。[从聊天返回会自动刷新](E:/openim/openim-flutter-demo/lib/pages/contacts/common_groups/common_groups_page.dart:90)。测试直接调用同一 Store.refresh，隔离导航和 SDK；完整设备返回链未执行。 |
| D03 / P2 | 全局搜索「全部」 | 同一查询的会话先回；好友、群分类后回，各推动已显示会话结果 **115px**，累计 **230px**；标题不动。 | [分类分别发布](E:/openim/openim-flutter-demo/lib/pages/global_search/global_search_logic.dart:124)，[按固定分类顺序插入](E:/openim/openim-flutter-demo/lib/pages/global_search/global_search_view.dart:106)。不是用户换分类或修改查询。 |
| D04 / P2 | 朋友圈列表、详情的单图组件 | 缺少 width/height 时，样本竖图解码让后续内容下移 **123.70px**；横图上移 **56.30px**。相同图有尺寸时均 **0px**。 | [默认比例切换到实际比例](E:/openim/openim-flutter-demo/lib/pages/moments/media/moments_single_media_frame.dart:49)。测量的是真实组件和其后方固定标记，页面滚动锚点的最终表现需设备观察。 |
| D05 / P2 | SDK AI 聊天页 | 没有新增消息，typing 提示出现/消失；长历史已有气泡往返 **37px**，亮暗一致。短历史气泡 **0px**。 | [提示位于 Expanded 消息区域之外](E:/openim/openim-flutter-demo/lib/pages/ai_assistant/ai_assistant_chat_page.dart:195)，缩小消息 viewport；底部锚定的长列表随之移动。 |
| D06 / P2 | 独立 AI 聊天的私有 Markdown 图片 | 200px 宽、方形 PNG 下载/解码前后，真实组件 **200×147 → 200×222**，增高 **75px**。 | [占位 16:10](E:/openim/openim-flutter-demo/lib/pages/ai_assistant/presentation/messages/ai_assistant_text.dart:176)，[成功图片不固定高度](E:/openim/openim-flutter-demo/lib/pages/ai_assistant/presentation/messages/ai_assistant_text.dart:148)。PosterCard 不属于这个问题。 |
| D07 / P2 | 钱包首页 | 保留原余额的刷新失败时，总金额及下面内容下移 **56px**，亮暗一致；重试清除提示后再上移。 | [顶部条件错误提示](E:/openim/openim-flutter-demo/lib/pages/wallet/home/widgets/wallet_load_notice.dart:19)，放在资产区之前。错误提示必要，但当前会改变已显示内容的位置。 |
| D08 / P2，压力条件 | 钱包首页 | 320px 宽，`--` 变为夹具长金额 `123,456,789,012,345,678.99`，金额多一行，操作按钮下移 **38px**；亮暗一致。 | [金额文字自然换行](E:/openim/openim-flutter-demo/lib/pages/wallet/home/widgets/wallet_balance_overview.dart:106)。使用 Windows 微软雅黑真实字体；不是用 Ahem 的夸大结果。这是现有显示能力的长值压力测试，未证明线上用户具有这笔余额，也不是计算精度错误。 |
| D09 / P2 | 收藏详情 | 内容不变，发送进行中正文下移 **4px**，发送结束回到原位。 | [正文上方插入进度条](E:/openim/openim-flutter-demo/lib/pages/mine/secondary/favorite_detail_page.dart:564)。 |
| D10 / P3 | 创建群组选择成员 | unknown → online，姓名在固定行内上移 **10px**；整行和头像均 **0px**。 | [居中文字栈条件增加状态行](E:/openim/openim-flutter-demo/lib/pages/contacts/select_contacts/friend_list/group_contact_picker.dart:224)。不是整页或列表行高抖动。普通转发好友选择、名片选择已有副标题占位。 |
| D11 / P2，组件条件 | 注册/找回密码共用容器；登录有相同链 | 注入 keyboard viewInsets=300，bottom padding **24 → 0**，滚动到底部的真实 RegisterBgView viewport 增高 **24px**、offset 减少 **24px**；亮暗一致。 | [公共 SafeArea](E:/openim/openim-flutter-demo/openim_common/lib/src/widgets/touch_close_keyboard.dart:43) 默认不保持底部 viewPadding；[注册容器](E:/openim/openim-flutter-demo/lib/widgets/register_page_bg.dart:17) 没有 Scaffold 键盘布局。**该注入证明容器条件变化，不等同于已验证 Android adjustResize 或 iOS 键盘动画。** 登录同构但未逐个表单动态执行。 |
| D12 / P3 | 钱包子页共享返回手势 | 从左边 10px 开始，先移动 (2,−1)，再主要向上移动 (20,−80)；页面横移约 **0.51px**，列表仍 offset=0，松开后归位。 | [返回识别阈值仅 0.1px](E:/openim/openim-flutter-demo/lib/pages/wallet/host/wallet_navigation.dart:520)，首次略偏横向就接受，抢先于竖向滚动。实际监听左侧 **24px** 带，**不是全屏误触**；主要影响边缘滚动，不应夸大为明显整页大幅晃动。 |

## 源码确认的条件风险，尚未动态复现

| 优先级 | 页面 / 条件 | 源码依据和边界 |
| --- | --- | --- |
| P2 | 客服聊天：对方 typing 出现和 8 秒超时消失 | [typing 在列表外](E:/openim/openim-flutter-demo/lib/pages/customer_service/customer_service_page.dart:335)；[超时清除](E:/openim/openim-flutter-demo/lib/pages/customer_service/customer_service_controller.dart:289)。与 AI 相似，但使用普通反向 ListView；影响全页及 Sheet。不能直接套用 AI 的 37px。 |
| P3 | 客服消息：发送中 → 成功 | [移除独立状态行](E:/openim/openim-flutter-demo/lib/pages/customer_service/widgets/customer_service_message_view.dart:100)，同一气泡可能缩小；无新消息时不会因消息数触发滚动。 |
| P2 | 聊天历史结果、选择发送者：继续分页 | [结果页列表上方进度条](E:/openim/openim-flutter-demo/lib/pages/chat/history_search/chat_history_results_page.dart:394)、[发送者页](E:/openim/openim-flutter-demo/lib/pages/chat/history_search/selection/chat_history_sender_page.dart:270)。默认约 4px，空页/失败也会插入再移除；幅度尚未实测。 |
| P2 | 消息保留设置：读配置、保存、错误提示 | [反馈块放在设置前](E:/openim/openim-flutter-demo/lib/pages/chat/chat_setup/message_retention_page.dart:202)，会改变已有设置的位置。反馈本身正常，位置是否保持是这里的风险。 |
| P2 | 群成员列表：已有公开 account，再收到 presence | [条件添加第三行](E:/openim/openim-flutter-demo/lib/pages/chat/group_setup/group_member_list/group_member_list_view.dart:185)，文字栈可超过 40px 头像，下方行移动；列表没有主聊天的尺寸补偿。 |
| P2 | 主聊天：旧 URL-only 图片贴纸、缺 snapshot 尺寸的视频 | [图片](E:/openim/openim-flutter-demo/openim_common/lib/src/widgets/chat/stickers/chat_image_sticker.dart:153)、[视频](E:/openim/openim-flutter-demo/lib/pages/chat/stickers/sticker_video_bubble.dart:271) 可能从方形占位变真实比例。**组件尺寸有变化不代表主列表一定可见跳动**；需要同时验证主聊天锚点补偿。 |
| P2 | 登录设备：恢复前台后自动刷新 | [恢复监听](E:/openim/openim-flutter-demo/lib/pages/mine/settings/pages/login_devices_page.dart:37)，[将已有列表替换成 spinner](E:/openim/openim-flutter-demo/lib/pages/mine/settings/pages/login_devices_page.dart:322)。短内容或卸载 controller 可能丢失阅读位置。 |
| P2 | 聊天存储：媒体逐批扫描 | [批次追加](E:/openim/openim-flutter-demo/lib/pages/mine/settings/pages/chat_storage_page.dart:111)，[每次按累计容量重新排序](E:/openim/openim-flutter-demo/lib/pages/mine/settings/pages/chat_storage_page.dart:168)。风险是阅读中的旧会话被换位置，不是正常新增条目。另 [扫描进度](E:/openim/openim-flutter-demo/lib/pages/mine/settings/pages/chat_storage_page.dart:422) 在列表前插入 2px。 |
| P2 | 三公下级列表、六合彩代理历史/详情：重新加载 | [三公刷新分支](E:/openim/openim-flutter-demo/lib/pages/group_features/sangong/pages/sangong_agent_team_page.dart:254)、[六合彩查询先清数据](E:/openim/openim-flutter-demo/lib/pages/group_features/mark_six/agent/data/agent_query_controller.dart:44)。已有列表卸载后换 spinner，没有外部滚动 controller 保持原位置。 |
| P2 | 转账详情：金额先回、姓名后回且昵称很长 | [异步补姓名](E:/openim/openim-flutter-demo/lib/pages/fund/fund_detail_page.dart:296)、[标题不限行数](E:/openim/openim-flutter-demo/lib/pages/fund/widgets/fund_transfer_detail.dart:64)。标题多一行会推动金额和交易资料；普通短昵称未证明会动。 |
| P2 | 收藏列表、最近通话：已有数据刷新 | [收藏进度](E:/openim/openim-flutter-demo/lib/pages/mine/secondary/favorites_page.dart:1645)、[最近通话进度](E:/openim/openim-flutter-demo/lib/pages/mine/secondary/calls/recent_calls_page.dart:355) 位于列表前，默认约 4px。这里没有直接动态测量，不将收藏详情的测量当作列表实测。 |
| P2，首帧揭示 | 会话列表：已有分组元数据后回 | [分组初始为空](E:/openim/openim-flutter-demo/lib/pages/conversation/conversation_logic.dart:31)，[空栏为 0 高](E:/openim/openim-flutter-demo/lib/pages/conversation/folders/conversation_folder_bar.dart:85)。SDK 会话先出现时，后来恢复分组栏会推动列表约 45px。用户主动创建分组属于正常交互；这里是恢复已有配置。 |
| P2，首帧揭示 | 群设置：首次确定自己是成员 | [初始成员状态 false](E:/openim/openim-flutter-demo/lib/pages/chat/group_setup/group_setup_logic.dart:69)，[后续出现多组设置](E:/openim/openim-flutter-demo/lib/pages/chat/group_setup/group_setup_view.dart:40)。已有删除操作会移到后面并变退出操作；是否接受初次加载揭示需要结合实际体验。 |

## 仍需设备或额外夹具确认的候选

1. 表情/语音面板与系统键盘切换：IME 收起尚未完成时，可能短暂同时占据空间。需要滞后 viewInsets 的逐帧测试或设备录屏，不能把正常键盘缩小 viewport 当作异常。
2. 通话页：[用户资料异步回来](E:/openim/openim-flutter-demo/openim_live/lib/src/pages/single/widgets/call_state.dart:137) 后，长昵称可能让[居中身份块](E:/openim/openim-flutter-demo/openim_live/lib/src/pages/single/widgets/controls.dart:197)增高。尚未实测；接通、挂断和视频轨道切换本身是正常状态变化。
3. 普通好友列表及继承它的选择流程：[直接订阅 cached Add/Del](E:/openim/openim-flutter-demo/lib/pages/contacts/friend_list/friend_list_logic.dart:23)，过时重播可能先出现旧好友，再被首个 SDK 快照替换。需要人为构造过期事件；当前没有动态证据。名片目录已去重，不推断重复名片行。
4. 群管理读取说明换成开关行：有条件分支，但开关自身高度足以吸收部分文本差，不能仅凭分支称为大幅位移。

## 覆盖矩阵

下表表示扫描、源码审查范围；“未确认”不是保证任意设备/数据都不会动。所有 Page/Screen 定义及文件清单保存在 JSON，View/Sheet 等按实际入口链补充。

| 模块 | Dart 文件 | 检查结果 |
| --- | ---: | --- |
| 首页 | 8 | PersistentTabView 缓存标签页；切页没有额外动画。主题容器自身未发现几何改变。 |
| 启动页 | 4 | 启动图片及原生启动资源沿现有约束；没有确认页面上下抖动。启动旋转/系统栏逐帧仍需设备。 |
| 登录 | 3 | SafeArea/键盘同构风险 D11；没有逐个平台验证。 |
| 注册 | 12 | 实际共用容器 D11；4 个注册步骤共用；表单输入带来的正常滚动另计。 |
| 找回密码 | 6 | 两个步骤复用同一容器，D11 源码适用。 |
| 会话 | 32 | 分组恢复风险；行高、头像、Peek 外框固定。 |
| 聊天/群设置/历史 | 144 | 历史分页、retention、群成员第三行、旧媒体候选；主列表有稳定 ID、双 sliver center、锚点与尺寸修正。 |
| AI | 48 | D05/D06；短历史 typing 和 PosterCard 稳定。 |
| 客服 | 23 | typing、发送状态两项源码风险；媒体预留尺寸。 |
| 公众号 | 7 | 标题高度预计算、输入占位含安全区，未确认意外位移。 |
| 联系人 | 97 | D01/D02/D10；其它在线字幕、头像、普通选择/名片选择已预留。 |
| 全局搜索 | 4 | D03；标题稳定，分类分批更新推动结果。 |
| 我的/设置/收藏详情 | 99 | D09；设备恢复刷新、存储排序、收藏/通话进度候选。 |
| 收藏公共组件 | 27 | 与 mine/secondary 实际页面一起追踪；不是 27 个独立收藏页面。 |
| 朋友圈 | 39 | D04；有尺寸单图、多图格子、相册等待初始范围时保持结构。 |
| 群扩展 | 123 | 三公/六合彩刷新卸载列表候选；浮层恢复先隐藏、再按边界放置，未确认乱跳。 |
| 转账/资金 | 18 | 长昵称补齐候选；正常金额状态、收款/取消动作不列为故障。 |
| 钱包 | 55 | D07/D08/D12；币种图标、收款 QR 外框固定。正常返回的缩放/遮罩是现有路由效果。 |
| 通话 pages | 4 | 另沿 widgets/session/platform 审读共 28 份 live Dart；视频与画中画外框固定，长昵称及原生恢复时序待测。 |
| 公共 widgets / 应用 widgets | 121 / 10 | SafeArea D11、媒体比例与共享导航重点审查；不把每个 widget 算作独立页面。 |

## 没有列作故障的情况

- 用户展开/收起、选择筛选条件、新消息/新申请真实插入、评论新增、红包开启动画以及下拉封面伸展。
- 标准 Cupertino 水平页面过渡。钱包子页深度缩放和遮罩是当前设计的导航效果，不能据此断言垂直抖动。
- 普通 ChatPage typing 只替换固定标题。AI 短历史消息位置为 0px；朋友圈已有尺寸单图为 0px；群资料头像在账号变化时为 0px。
- 常规图片、视频缩略图、聊天历史网格、客服媒体、AI PosterCard、72×72 个人头像和 QR 容器已预留外框。
- 现有导航/安全区 27 个测试通过，覆盖亮暗、24/44 状态栏、普通/嵌入/固定设置结构。不能据此覆盖原生键盘和全部机型。
- 应用根节点当前使用 Config.textScaleFactor=1.0；系统大字号不会直接作用于普通页面。聊天字号另有设置。因此不把 200% 独立测试简单当作线上系统字号表现，也没有修改这一行为。

## 修复建议及顺序

1. **先保护阅读位置**：共同群聊、设备和代理查询刷新保留旧数据；成功后原位替换，保持稳定 ID 与滚动锚点。搜索可以先汇总同一查询，或明确保留分类位置，避免迟到分类在已读结果前插入。
2. **稳定异步高度**：图片在首帧使用可信尺寸，或整个生命周期采用统一约束；资料行、在线字幕、输入提示应预留必要空间或放在不挤压已有内容的位置。
3. **进度与错误反馈不挤列表**：已有内容刷新时使用既定高度、覆盖层或合适位置的提示；保留必要反馈，不改变接口及隐私判定。群账号不能为稳定布局而保留已撤销的敏感字段。
4. **再处理长值与边缘输入**：金额保持精度，使用能容纳长字符串的确定布局；姓名既可读也要有行数/区域策略。键盘需按原生最终 insets 验证后调整，返回手势使用标准触发距离和方向判定。

## 验证和本次改动

- 新增 4 份诊断测试，共 **21 项通过**：聊天 5、联系人 4、朋友圈/收藏 5、钱包/容器/路由 7；联系人夹具 getter 清理后单独复跑 4 项通过。
- 另执行现有导航/安全区 **27 项通过**。与上述诊断共 48 个不同测试，分批运行；没有声称 48 项在一次命令执行。
- 静态分析诊断目录与两个 import 修复文件：**No issues found**。
- 诊断代码见 [测试目录](E:/openim/openim-flutter-demo/test/audits/page_motion)；原始本地日志见 `.temp/page-motion-audit/final-motion.log`、`contacts-motion-final.log`、`chat-navigation-motion.log`。
- 保留全部已有工作区修改。未修改上述页面业务布局、数据、接口、路由行为或金额计算，没有提交、推送或安装。
- 为使现有依赖链可编译，补了两处必要 import：来电快捷回复组件补 SDK UserInfo 类型 import；迁移后的通知设置页修正声音选择页相对 import。没有顺带调整这些组件的 UI。
- 没有实测原生键盘/系统栏动画、Android/iOS 旋转及恢复、真实后端慢网与真实语音/视频通话；这些是设备复验边界。

### 本地重现入口

```powershell
flutter test test/audits/page_motion --reporter expanded
dart analyze test/audits/page_motion
```

这些测试刻意断言当前可复现的位移。后续修复相应页面时，应把对应断言改成稳定位置，并保留正常交互的负对照。
