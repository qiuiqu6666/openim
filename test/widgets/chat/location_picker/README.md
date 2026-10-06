# 聊天位置选择测试

`chat_location_picker_controller_test.dart` 使用本地定位接口和 Geolocator 平台替身，覆盖权限、20 秒定位限制、手动选点优先、后台迟回、经纬度边界及销毁保护，不调用设备 GPS 或权限弹窗。

页面和布局测试使用真实 `ChatLocationPicker`，通过 `mapBuilder` 注入 `support/location_street_map_fixture.dart` 的本地街道画布。点击和拖动产生选点回调，再核对页面坐标、名称及返回给聊天页的 record。街道画布仅属于测试与预览，不能用于正式应用，也不代表已渲染 Android 高德地图或 iOS 苹果地图。

设置环境变量 `EXPORT_CHAT_LOCATION_PREVIEWS=true` 后，布局测试可导出 `.temp/chat-location-picker/*.png`。导出使用 Windows Microsoft YaHei 和本机 Flutter SDK 原版 MaterialIcons 字体。键盘场景模拟 viewInsets，截图不绘制系统键盘。

WidgetTest 无法验证原生地图 SDK 的实际瓦片、手势渲染和设备授权弹窗。Android 需要有效高德 Key 与对应签名；Android 高德及 iOS MapKit 都需在真机完成地图显示、点选、拖动、定位、后台返回和资源释放验收。平台通信测试仅验证 Dart 与原生桥的契约，不替代这项真机验收。
