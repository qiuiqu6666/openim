# 聊天位置选择

公开入口仍是 `../location_picker.dart` 的 `ChatLocationPicker`。调用方 `lib/pages/chat/media/chat_media_controller.dart:onTapLocation` 继续使用原 OpenIM SDK 创建和发送位置消息。

## 归属与数据

- `chat_location_picker.dart`：页面、路由/前后台可见性、发送现有位置 record。
- `chat_location_picker_controller.dart`：选点和定位状态；请求串行、退出/后台和晚到定位结果隔离。
- `data/chat_location_source.dart`：现有 Geolocator 定位。自动定位只使用已有权限；用户点击定位后才可申请权限，20 秒超时。
- `widgets/`：地图操作层与所选位置/名称/发送面板。复用 GlassAppBar、AppTokens、现有导航，支持亮暗、小屏、大字、横屏和键盘。
- `native/`：平台地图桥接及 Android 高德隐私同意。无公共包到应用页面的反向依赖。
- Android 原生归属 `android/app/src/main/java/io/openim/location/`；iOS 原生归属 `ios/Runner/NativeChatLocationMap.swift`。

Android 内嵌高德地图，iOS 内嵌 MapKit。Web/桌面继续使用原 FlutterMap + OpenStreetMap 数据源。生产页面不使用测试地图或预置地点作为可发送的选点。未选点时禁用发送。

调用方及 Dart/native 边界坐标均为 **WGS84**，保持既有消息协议。Android GPS 显示通过高德官方 `CoordinateConverter.GPS` 转换，地图选点经 GCJ-02 逆变换回 WGS84；官方可用范围与中国范围外的点不偏移。iOS 使用 MapKit 坐标 API 原始值。地图 SDK 不主动申请定位权限或启动自己的定位服务。

人工选点保留名称输入，覆盖晚到的定位成功/失败。后台、被不透明路由覆盖或销毁后不接收旧定位/选点结果，恢复不重复启动尚未完成的定位。

## Android 稍后配置 Key

复制仓库中的 `android/amap.properties.example` 为 `android/amap.properties`，填写：

```properties
AMAP_ANDROID_KEY=你的高德Android SDK Key
```

本地文件已加入 `.gitignore`。也可从 Gradle project property 或环境变量 `AMAP_ANDROID_KEY` 提供；优先级为 project property → 环境变量 → 本地文件。不会使用原有 Web Key，不在日志中打印 Key。

当前 applicationId：`chat.chat99.chatpro`。本地导入的签名证书 SHA1：

```text
A0:7D:E7:94:6C:C2:12:D1:9D:89:F8:65:05:AD:E1:ED:53:60:BD:56
```

如发布签名或 applicationId 变更，需按实际发布 APK 重新绑定。配置后重新运行 `flutter build apk --debug`，Key 在构建时写入 Manifest，不是运行时开关。

Android SDK Key 已存入本地忽略文件 `android/amap.properties`。签名凭据保存在本地忽略文件 `android/key.properties` 和 `android/upload-keystore.jks`。当前项目推送类型默认为 `none`；项目仍保留可选 FCM 接线，`android/app/google-services.json` 已替换为匹配新包名的配置。空 Key 状态不会实例化高德 SDK 地图，显示“地图暂时不可用”并禁止发送，避免使用错误地图坐标。Android 首次使用先展示高德隐私政策并由用户明确同意，再创建地图；仅成功存储严格布尔 `true` 后进入 SDK。iOS 的 MapKit 不需要高德 Key。

SDK 固定为 Maven Central `com.amap.api:3dmap-location-search:11.3.100_loc11.3.000_sea9.8.1`。该官方组合包含地图/定位/搜索，本功能只调用地图。地图 native 库支持 arm64-v8a/armeabi-v7a，当前工程保留原 arm64-v8a/x86_64 ABI 设置；x86_64 模拟器不支持此高德渲染库，会显示不可用，需 ARM64 真机/模拟器验收。

官方配置依据：[Android Key](https://developer.amap.com/api/maps-sdk-for-android/guide/create-project/get-key)、[隐私初始化](https://developer.amap.com/api/maps-sdk-for-android/guide/create-project/dev-attention)、[MapKit](https://developer.apple.com/documentation/mapkit/mkmapview)。

## 原生桥接

Platform view：`openim/chat-location-map`。每个实例通道：`openim/chat-location-map/<viewId>`。

创建参数包含可选 WGS84 经纬度、`dark`、`privacyAgreed`。Flutter 调用 `status`、`move`、`style`、`setActive`、`dispose`；原生事件 `onSelected`、`onReady`、`onError`。`status.error` 为空表示已创建，无 Key/无同意/初始化错误均明确返回。

仅 `centerRequest` 改变才回传程序移图请求；人工选点不回声移图，避免打断原生拖动。原生停用/销毁时移除监听和手势、关闭地图生命周期，异步事件有实例/活动代数隔离。

## 对照与验证

99chat 实际位置消息组件中的地图逻辑为注释/维护状态，未确认可复用的聊天选点页。本页按用户明确的平台地图选择和工程公共视觉组件实现，不声称复制了不存在的参考实现。拆出状态、原生边界和页面局部组件是为了保持职责可维护，未新增另一套消息发送链路。

相关 Flutter 测试位于 `test/widgets/chat/location_picker/`，覆盖定位授权/超时、晚到结果、关闭/后台/路由覆盖、坐标边界、返回 record、取消、加载布局稳定、亮暗、小屏/大字/横屏/键盘及原生平台通道。

布局预览通过测试注入街道画布，不代表原生 SDK 或实机地图渲染。原生坐标独立 JVM 检查位于 `test/widgets/chat/location_picker/native/ChatLocationCoordinatesCheck.java`，验证国内参考点、境外恒等、边界和非法输入。

2026-10-06 验证：本模块 17 项 Flutter 测试全部通过，相关页面/状态/原生桥/测试 scoped analyze 无问题；独立 JVM 坐标检查通过；Android debug 构建成功。亮暗、键盘、小屏、大字和横屏预览已检查，地图画布为明确标注的测试替身。

当前 Android debug 安装包为 `build/app/outputs/flutter-apk/app-debug.apk`，包名 `chat.chat99.chatpro`，签名 SHA1 与上方证书一致，Manifest 已包含本地高德 Key，Firebase 配置包名也匹配。SHA256：`4028E5AE7759235AB1FAE2A851362632F83A69AC698E2788724D65013FAB0374`。

Windows 环境不能编译或实机验证 iOS；Android 已配置本地 Key 并完成新包名构建；真实地图瓦片、签名授权和 SDK 地图点击仍需在 ARM64 真机验收。构建成功不代表已完成原生地图实机验收。
