# OpenIM → 99Chat Migration Rules

## 项目定位

当前工作区基于 OpenIM 开发，是一个即时通讯客户端。

本项目目标不是简单修改 OpenIM 的颜色或布局，而是：

在保留 OpenIM 稳定底层能力、SDK、数据链路和核心架构的基础上，
逐步将：

- UI
- UX
- 页面结构
- 交互方式
- 功能表现
- 业务入口
- 视觉语言

调整为与以下目标仓库一致：

https://github.com/qiuiqu6666/99chat

99chat 是产品体验和功能形态的主要参考源。

OpenIM 当前代码是底层能力和迁移基础。

---

## 1. 参考优先级

遇到 UI / UX / 功能实现冲突时，按照以下优先级判断：

1. 99chat 已确认的产品行为和交互
2. 当前 OpenIM 已稳定运行的底层能力
3. 当前项目已有的公共组件和设计系统
4. 新增实现

不要为了“看起来更接近 99chat”而破坏 OpenIM 已稳定的数据链路、SDK 行为或生命周期。

---

## 2. 页面改造目标

所有新增或重构页面，应尽量做到：

- 页面结构与 99chat 一致
- 功能入口与 99chat 一致
- 用户操作路径与 99chat 一致
- 弹窗、菜单、列表、空状态、错误态风格一致
- 图标、字号、间距、圆角、颜色体系一致
- 亮色 / 暗色主题一致
- Android / iOS 体验一致

不要机械复制代码。

应迁移的是：

产品行为
+ 交互逻辑
+ 视觉体系
+ 功能体验

而不是直接照搬与当前架构不兼容的实现。

---

## 3. 组件复用优先

新增页面或功能前，必须先搜索当前项目是否已经存在可复用的：

- Widget
- Button
- ListItem
- Avatar
- AppBar
- Dialog
- BottomSheet
- Menu
- EmptyState
- LoadingState
- ErrorState
- Input
- SearchBar
- Card
- Divider
- Badge
- Switch
- Theme helper
- Color token
- TextStyle token
- Router
- Store
- Service
- Repository
- Controller
- ViewModel

有现成组件时：

优先复用或扩展。

禁止为了局部页面重新创建功能重复的组件。

如果现有组件只缺少少量能力：

优先增加参数或抽象可复用能力，
而不是复制出一个新 Widget。

只有以下情况才允许新建组件：

- 当前项目确实不存在等价能力
- 扩展现有组件会显著破坏其语义
- 新组件具备明确的跨页面复用价值

---

## 4. Design System 统一

所有页面必须使用统一设计系统。

禁止在页面中随意硬编码：

- Color
- TextStyle
- fontSize
- radius
- padding
- margin
- shadow
- iconSize

优先使用项目现有：

- Theme
- ThemeExtension
- Design Token
- ColorScheme
- TextTheme
- spacing constants
- radius constants
- component tokens

如果当前项目缺少统一 Token：

优先补充 Design System，
不要在不同页面各自写一套数值。

---

## 5. 日夜主题

所有新增页面和组件必须同时支持：

- Light Theme
- Dark Theme

禁止：

- 直接写 Colors.white
- 直接写 Colors.black
- 用固定浅色背景
- 用固定深色文字
- 只在亮色主题下测试

必须通过：

Theme
ColorScheme
ThemeExtension
项目已有 Token

获取颜色。

至少检查：

- 页面背景
- 卡片背景
- 弹窗背景
- 文字主色
- 次级文字
- Divider
- Border
- Icon
- Disabled
- Selected
- Loading
- Error
- Overlay
- Scrim
- Toast
- BottomSheet

确保亮暗主题都可读、层级正确。

---

## 6. 图标统一

新增图标必须与当前 99chat 风格保持一致。

统一：

- Outline / Filled 规则
- stroke width
- roundness
- visual weight
- icon size
- optical alignment
- selected state
- disabled state

禁止：

- 同一页面混用完全不同风格图标
- 一部分 3D，一部分线性
- 描边粗细不一致
- 图标视觉大小明显不同

优先复用当前项目已有 icon assets / icon components。

---

## 7. 功能迁移规则

当目标功能在 99chat 存在，而当前 OpenIM 没有：

先分析：

1. 99chat 的用户行为是什么
2. 当前 OpenIM 是否已有底层能力
3. 是否已有 SDK/API 可直接支持
4. 是否只需要 UI 层改造
5. 是否需要新增 Service / Store / API
6. 是否会影响消息、会话、联系人、群组等核心链路

如果 OpenIM 已有等价能力：

复用现有能力，只调整 UI/交互。

如果没有：

再新增最小必要实现。

---

## 8. 数据源规则

页面外观可以参考 99chat。

但正式数据源必须优先使用当前项目真实：

- OpenIM SDK
- OpenIM API
- 当前 Backend
- 当前本地数据库
- 当前缓存
- 当前 Store / Repository

禁止为了快速完成 UI：

- 长期使用假数据
- 复制 99chat 假数据
- 用静态 JSON 替代真实状态
- 绕过 SDK / Repository 直接造状态

Mock 只允许用于：

- Preview
- Test
- Story / Demo

生产逻辑必须接真实数据源。

---

## 9. 状态和生命周期

UI 改造不能破坏：

- 页面状态
- 会话状态
- 草稿
- 滚动位置
- 未读数
- 选中状态
- 输入内容
- 加载状态
- 返回恢复
- SDK listener
- Stream
- Controller
- Route lifecycle

新增页面必须检查：

init
→ active
→ covered
→ resume
→ background
→ foreground
→ dispose

不能因为 UI 重构导致：

- 重复请求
- 重复 listener
- dispose 后写状态
- 页面返回丢状态
- 页面切换重新拉全量数据

---

## 10. 交互一致性

以下交互必须统一：

- Back
- Gesture back
- Long press
- Swipe
- Pull to refresh
- Search
- Dialog
- BottomSheet
- Toast
- Snackbar
- Loading
- Retry
- Empty
- Error
- Disabled
- Selection

同类交互不应每个页面自己发明一套。

---

## 11. 页面新增流程

新增页面前必须：

1. 先检查 99chat 对应页面
2. 检查当前 OpenIM 是否已有等价页面
3. 检查已有可复用组件
4. 检查已有路由
5. 检查已有数据源
6. 检查 Theme / Design Token
7. 明确亮色/暗色表现
8. 再开始开发

---

## 12. 页面重构流程

重构现有页面时：

不要只改视觉。

同时检查：

- 页面功能是否完整
- 功能是否与 99chat 对齐
- 数据是否来自正确来源
- 交互是否一致
- 状态是否正确
- 返回后是否保持
- 异常态是否完整

---

## 13. 页面全链路检查

用户说：

“检查这个页面”
“深入检查这个页面”
“全面检查这个页面”

默认执行 Page Full Audit。

必须检查：

页面
→ 子组件
→ Controller/ViewModel
→ Store
→ Service
→ Repository
→ SDK/API
→ Cache/DB
→ 状态
→ 路由
→ 生命周期
→ 异步任务
→ 错误处理
→ 性能
→ UI/UX
→ 主题
→ 测试

页面是产品功能边界，
不是单个 Dart 文件边界。

---

## 14. 性能要求

所有迁移和新增实现必须避免：

- 无意义全量 rebuild
- 高频全列表排序
- 重复 API 请求
- 重复 SDK 查询
- 重复 listener
- build 中执行重计算
- 主 isolate 同步 IO
- 大量临时对象

但不要为了理论性能进行过度复杂优化。

先测量，再优化。

---

## 15. 不允许随意重构核心架构

除非用户明确要求，禁止因为迁移 UI：

- 重写 OpenIM SDK 层
- 重写消息核心链
- 重写会话状态管理
- 替换整个状态管理框架
- 重写数据库层
- 重写路由框架

优先最小、安全迁移。

---

## 16. 99chat 对照原则

实现某页面或功能时：

需要对照 99chat 仓库实际实现。

优先确认：

- 页面结构
- 功能入口
- 用户操作
- 状态
- 数据行为

不要凭印象说“和 99chat 一样”。

如果目标仓库对应功能不存在或无法确认：

明确说明，
不要自行编造“99chat 的做法”。

---

## 17. 视觉一致性

整个程序最终必须像同一个 App。

禁止出现：

- 一个页面 Material 风格
- 一个页面 Cupertino 风格
- 一个页面渐变重
- 一个页面纯白极简
- 图标风格完全不同
- 圆角、间距、字号各自一套

新页面必须先适配现有 Design System。

---

## 18. 主题验收

每个新增/重构页面至少检查：

Light:
- normal
- selected
- disabled
- loading
- empty
- error

Dark:
- normal
- selected
- disabled
- loading
- empty
- error

不能只验证主页面正常状态。

---

## 19. 平台验收

所有新增页面至少考虑：

- Android
- iOS

重点检查：

- SafeArea
- Keyboard
- StatusBar
- NavigationBar
- Back
- Gesture Back
- Scroll Physics
- Dialog
- BottomSheet
- Native Picker
- Permission

平台差异可以存在，
但产品风格应统一。

---

## 20. 修改原则

每次修改前：

- 先理解当前实现
- 先找复用点
- 再修改

每次修改后：

- 检查功能
- 检查主题
- 检查路由
- 检查状态
- 检查异常态
- 检查 Android/iOS
- 运行相关测试/analyze

不要只验证“页面能打开”。

---

## 21. 输出要求

每次完成页面或功能迁移后，简要报告：

- 对照了 99chat 哪个实现
- 复用了哪些现有组件
- 新增了哪些组件
- 为什么必须新增
- 数据源是什么
- 是否支持 Light/Dark
- 是否影响现有业务
- 测试/验证结果
- 尚未验证的边界

如果新增了功能重复组件，
必须主动解释为什么无法复用已有组件。

---

## 22. 模块目录与长期维护

用户已要求：大小模块都要有独立目录和文件，方便后续长期维护。

所有新增、扩展和重构工作必须遵守 [模块目录与长期维护规范](docs/module-organization.md)。新功能立即按规范组织，现有文件按功能边界逐步迁移。

必须执行：

- 每个独立功能都有归属目录；大模块下的独立功能继续建立子目录。
- 同一模块的页面、状态、业务组件、API、模型、仓储与本地持久化集中维护。
- 一个实现文件承担一个明确职责；独立页面、弹窗、组件和业务流程分别有可定位的实现文件。
- 新增独立职责不得继续堆入超长页面、控制器或通用工具文件。
- 业务专用能力归业务模块；真正跨业务使用的能力归明确的共享子目录。
- 跨模块使用公开入口、接口或现有导航能力；数据层不依赖页面，不新增循环导入。
- 公共包保持现有边界，不能反向依赖应用页面；共享消息协议模型保留公共归属。
- 手写实现文件超过 500 行检查职责，超过 800 行时新增功能先拆分职责或记录合理保留原因。生成代码、资源正文及局部修错按文档中的例外处理。
- 新测试按模块对应目录组织，跨模块流程测试独立归类；复杂模块提供维护说明。
- 移动文件时同时核对所有引用、路由、GetX 绑定、导出、资源及测试路径，保留 SDK 订阅所有权、异步关闭保护、草稿、未读数、私密消息及账号退出清理。
- 目录拆分不能通过 part 文件或共享全部私有状态的 extension 伪装成职责拆分。
- 完成一个模块后运行相关测试和 analyze；影响应用入口、路由或原生资源时验证构建，并报告尚未迁移的范围。

当前优先整理聊天子模块、收藏、设置独立功能和业务专用服务。继续使用现有 OpenIM、GetX、路由和公共组件，按功能逐个处理。
