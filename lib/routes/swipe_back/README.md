# 统一右滑返回

对照本地 `reference-99chat` 的 `full_screen_back_route.dart`、
`app_chat_route.dart`、`app_route_depth_transition.dart`（`d7c3c65`）。
复用并抽出原钱包里的实现，原来的 GetX / Navigator、业务参数、绑定、
订单结果与页面状态仍由各自入口管理，不修改 SDK 或数据源。

## 行为

- 普通页左边缘 24、三种聊天页 40、聊天资金卡片详情 96 逻辑像素起手。
- 向右距离超过视口宽度 16%，或向右速度超过 320 逻辑像素/秒，松手返回。
- 页面随手势线性平移；松手后用承接当前速度的临界阻尼运动完成返回或回弹。正常切页统一 480ms，前段快速展开、末段柔和停稳。
- 上一页最多左移屏宽 25%，覆盖最高 8% 的主题 scrim；新页带轻微边缘阴影，不缩放。返回时恢复。
- 日夜主题沿用 Theme；减少动态效果时取消页面平移、背景变暗与边缘阴影。
- 页面内容保留稳定子树，避免返回动画重建消息列表或重置滚动位置。

## 接入与边界

- `AppPages._pageBuilder` 配置命名 GetX 路由；首页、登录、启动页禁用。
- `ChatApp.customTransition` 接管匿名 `Get.to`。不要设置
  `defaultTransition: Transition.native`，GetX 4.7.2 的该分支会跳过
  全局自定义 transition。命名页和应用入口关闭原生 `popGesture`，
  避免两个手势识别器并存；是否启用由 `AppGetTransition` 管理。
- 普通 Navigator 入口使用 `AppMaterialPageRoute`，保留 PageRouteBuilder
  的既有契约。其 Cupertino mixin 用于与 GetX 的前一页同步次级动画，
  视觉和手势仍由本模块提供。
- 设置、钱包仍使用 root Navigator；三公路由保留原有权限与 scope。
- 主题中的 `AppPageTransitionsBuilder` 兼容普通 Material 路由。表情管理接入公共页面路由；合并消息详情使用同一个 Navigator 上的 GetPageRoute，继承全局转场，确保与 GetX 前一页同步。
- 资金详情保留透明红包封面、领取动画和 `currentResult`，关闭后仍返回
  最新已验证订单。抽屉展开、贴纸弹层、通话、聊天图片预览等专用 Route
  保留原实现。朋友圈/客服图片及直播全屏 Material 路由使用
  `AppSwipeBackTokens.mediaRouteName` 排除全局手势。
- `fullscreenDialog` 保留模态动画；不增加右滑识别器。

## 返回保护

起手和松手都会检查当前路由、首层路由、局部历史、`PopScope`、旧版
`WillPopScope` 和路由动画状态。多选、编辑未保存、进行中操作等业务
限制仍生效。手指取消只回弹；第二根手指不接管；系统/按钮返回已经
开始后不再回弹复活页面。Navigator 的手势生命周期只结束一次。

Flutter/GetX 没有公开交互式路由控制器接口，受保护成员的访问集中在
`AppSwipeBackInteractor`，升级 Flutter/GetX 时需重跑本模块测试。

## 验证

`test/routes/swipe_back/` 覆盖 Android/iOS、日夜主题、起手范围、距离/
速度门槛、取消、返回拦截、滚动冲突、双指、混合路由动画与 GetX
控制器/滚动状态。关联回归还包括设置、钱包、登录验证、联系人、
群功能、图片预览、资金详情与资金消息入口。

2026-10-11 验证：关联回归 345 项通过、5 项跳过。另有一项既有
`privilege_route_guard_test.dart` 的 profile revocation 用例失败：它用
独立 MaterialApp 测试资料页操作，没有使用本次修改的路由，仍期待旧
确认弹窗，当前提交路径还会触发未初始化的 EasyLoading 提示。
补充钱包路由契约回归时，另有一项原有流水测试仍断言旧标题
`余额变动明细`，当前页面不再显示该文案；路由跳转及订单实例测试通过。
保留这两项失败，未改动业务及其断言。本模块与入口定向 analyze、
Flutter debug bundle 构建通过；全库 analyze 另有既有 lint，未扩展处理。
Android/iOS 是 widget 测试平台覆盖，尚未进行真机手势验收。
## 2026-10-12 参考视频动效调整

以用户提供的 IMG_0076.MP4（30fps）中 12 个新页边缘位置为参考，
采用 480ms 的 fastEaseInToSlowEaseOut 曲线，抽样位置误差控制在屏宽
3% 内。这是画面拟合，不代表已知参考应用的内部算法。普通返回使用
翻转曲线，保持及时响应、平缓停稳；CurvedAnimation 避免进入中途返回
时突然切换曲线造成跳位。

AppBackSettlement 接续手指松开速度（按页面宽度归一化），使用临界
阻尼运动，完成和取消返回均精确停在终点，不添加弹跳。快速甩动到达
边界时立即结束，避免页面已退出而手势生命周期仍被占用。

定向回归 104 项通过，静态检查及 Android debug APK 构建通过。
测试覆盖位移曲线、速度衔接、亮暗主题、进入中途返回、混合路由、
回弹、返回拦截、状态保留、媒体预览、表情管理和资金详情。

可选组件帧导出：
`flutter test test/routes/swipe_back/app_reference_motion_test.dart --dart-define=MOTION_CAPTURE_DIR=<absolute-directory>`。
组件截图只用于检查几何和层次；真实触感及帧率仍需 Android/iOS 的
profile/release 模式实机验收。
