# 聊天位置选择

视觉按用户确认的微信式位置选择设计实施。保留 `ChatLocationPicker` 公共入口与返回的 WGS84 经纬度/description record，聊天消息发送链路不变。

## 职责与复用

- 页面复用 `GlassAppBar`、`AppTokens`、定位控制器、地图 overlay、选点面板与高德授权组件。发送移到右上角，名称输入折叠到地点列表末尾。
- `chat_location_places_controller.dart` 负责搜索防抖、加载/失败状态及过期回复隔离；`data/chat_location_place.dart` 定义地点与原生搜索接口。搜索与 GPS 状态分开，搜索失败不影响手动选点发送。
- Android `ChatLocationPlaceSearch.java` 使用现有高德组合依赖中的 PoiSearchV2，无新增依赖或 Web API key。附近查询半径 1km，关键词在已有选点周围 50km 内搜索；无选点的关键词查询使用提供方默认范围。返回最多 20 个真实地点，GCJ-02 转 WGS84 后交给 Flutter。
- iOS 保留 MapKit，使用 MKLocalSearch/MKLocalPointsOfInterestRequest。桌面保留现有地图选点，不显示不可用的搜索输入。
- 地图、列表、隐私面板和状态使用亮/暗主题 token；小屏大字增加列表可用空间，横屏采用左右布局。

## 授权与生命周期

Android 页面正文由 `ChatLocationAmapConsent` 门控：同意并成功保存前，不挂载地图、不请求 GPS、不搜索。隐私链接保留高德官方地址，暂不使用返回空结果。地图组件单独使用时仍默认要求授权，页面内部仅在外层已授权时关闭重复门控。

GPS 仍由现有 source 负责。地图/列表手动选点优先于延迟 GPS 返回；选中地点触发地图居中并以地点名作为默认发送描述，用户自定义名称优先。地图拖动不反向触发相机居中。

搜索输入与自定义名称随页面保存。搜索防抖 350ms；换关键词、换地图点、页面覆盖/后台和销毁都会拒收过期回复。Android 查询在独立工作线程，原生视图暂停和销毁会取消待返回结果。

## 验证（2026-10-14）

- `flutter analyze --no-pub openim_common/lib/src/widgets/chat/location_picker test/widgets/chat/location_picker`：无问题。
- `flutter test --no-pub test/widgets/chat/location_picker`：32 项通过，覆盖权限、坐标发送、异步竞争、地图通道、真实搜索接口的测试替身、授权同意/拒绝、小屏大字、键盘、横屏及亮/暗布局。
- Android 修改的地图、坐标转换、地点搜索类使用当前高德/Flutter/Android 依赖单独 javac 编译通过。
- 整体 Android Gradle 编译尝试未通过：现有 flutter_webrtc 插件缺少 `SimulcastVideoEncoderFactoryWrapper`，另有 Kotlin 增量缓存警告。未把单独 Java 编译视为整包成功。
- 当前 Windows 环境未执行 iOS 编译或手机实测；真实高德 key 的搜索权限、网络响应和设备地图仍需真机验证。
- Flutter 预览由测试开关 `EXPORT_CHAT_LOCATION_PREVIEWS=true` 导出至 `.temp/chat-location-picker/`；地图和地点为测试夹具，不能作为在线地图验证证据。

已检索本地 99chat 的位置相关文件，仅发现位置消息展示与其他业务定位服务，没有可对照的同类位置选择页面；本次布局以用户确认设计为准。

原生搜索 API 依据：[高德 PoiSearchV2](https://a.amap.com/lbs/static/unzip/Android_Map_Doc/Search/com/amap/api/services/poisearch/PoiSearchV2.html)、[Apple MKLocalSearch](https://developer.apple.com/documentation/mapkit/mklocalsearch)。
