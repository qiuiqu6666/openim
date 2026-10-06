# 通讯录头部导航

`ContactsHeader` 对照本地 99chat `lib/src/pages/home_page.dart` 的主通讯录 Tab 实现；`contactPage.dart` 是“联系我们”页，不是参考对象。

正常标题复用 `MainTabTitle`：左对齐、手机 22/桌面 20、粗体，附蓝色短线与圆点。连接与同步状态仅通过标题的 `StreamBuilder` 更新，不重建联系人列表；连接中、失败时隐藏装饰。顶部安全区由标准 AppBar/Scaffold 管理；字体放大时页面增加导航高度。

`MainTabPlusButton` 位于公共包的 `widgets/navigation/`，由消息页和通讯录复用。点击区域 48×48，图标 24；菜单打开与关闭各顺时针转 45°，220ms，关闭动画偏好下直接切换。既有 `GlassAppBar`、系统栏和亮暗主题配置继续复用。

菜单复用 `showHomeQuickActions`，参考顺序为搜索添加、创建群聊、创建频道、扫一扫。联系人控制器负责真实导航，搜索与创建群使用既有 OpenIM 入口；扫一扫复用 `scanning/FriendQrScanner`，返回邀请码后验证账号与登录状态再打开好友资料。频道缺少当前产品能力，明确禁用并显示“暂未开放”，不会伪造创建结果。

扫描组件与“我的二维码”页共享，邀请码继续经过公共 `parseFriendInvite` 校验。相机跟随前后台和页面覆盖状态暂停/恢复；扫码页面的 `ModalRoute.isCurrentOf` 依赖监听避免增加全局路由订阅。关闭后忽略晚到结果，扫码返回时两个入口均校验账号和登录令牌；原生 QRView 管理自身控制器释放。

头部测试归 `test/pages/contacts/navigation/`；扫描生命周期测试归 `test/pages/contacts/scanning/`；原通讯录目录、搜索和控制器测试继续各自维护。头部复用既有 SDK 状态流，未增加好友数据请求、目录排序和好友数据订阅。

## 2026-10-05 验证

- 头部 17 项普通测试与 2 项亮暗截图测试通过；安全区、英文、放大字体、减少动画、连接中/连接失败状态、菜单顺序及点击均有覆盖。
- 聚合通讯录页面、搜索反馈、联系人控制器、消息页头部、快捷菜单、邀请二维码解析测试：48 项通过，2 项截图测试因未设置导出目录而跳过；截图已单独执行通过。
- 使用真实 QRView 与模拟原生方法通道的 3 项测试通过：页面覆盖和恢复、前后台状态与覆盖状态交叉、退出过程中的迟到二维码和平台视图创建回调。
- 新增头部、扫码、公共加号及本次集成代码静态检查无问题。既有 `qr_profile_page.dart` 保留未使用的 `_QrBackdropPainter` 警告和已有的 if 大括号提示，无新增检查问题。
- 最新源码 Android debug 构建通过（最终 `assembleDebug` 13.1 秒）；安装包为 `build/app/outputs/flutter-apk/app-debug.apk`。当前 Flutter 构建器将 minSdk 自动提升为 API 24，生成的安装包适用于 Android 7.0+；构建后已恢复项目原有 `minSdkVersion 23` 配置。
- 头部预览保存在 `.dart_tool/contacts-header-preview/contacts-{header,menu}-{light,dark}.png`，仅展示导航组件。
- 相关日志：`.dart_tool/contacts-header-regression-tests.txt`、`contacts-header-tests.txt`、`contacts-header-preview-tests.txt`、`contacts-scanner-lifecycle-tests.txt`、`contacts-header-analyze.txt`、`contacts-header-build.txt`。

真实相机权限拒绝、相机硬件暂停/恢复以及 iOS 设备尚未验证。测试不创建好友/群组、不读取真实通讯录、不启用硬件相机。
