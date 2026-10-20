# Location messages

`ChatLocationMessageCard` renders the location name, optional address, real map
thumbnail, and existing message time/delivery status. `ChatItemView` owns the
surrounding message actions; the card does not add a second colored bubble.

Tapping opens `ChatLocationDetailPage` inside the app. The map can pan and zoom,
but cannot change the shared coordinate. Recenter returns to that coordinate;
each visit requests the viewer's location once after the map is ready (and after
Android map consent). Existing grants are reused; missing permission uses the
system prompt. The device dot/camera target are separate from the shared
coordinate. A late automatic fix does not override an explicit recenter. Closing the page ignores a pending GPS completion.

Android reuses the existing AMap privacy consent gate. Before consent, the card
shows a location placeholder without creating an AMap view. The detail page
offers the existing consent flow. Returning refreshes the thumbnail consent.
Android uses AMap snapshots; iOS retains MapKit with MKMapSnapshotter. Mobile
thumbnail map views are released after capture or timeout. An in-memory cache
retains at most 32 snapshots, keyed by coordinate and theme. Failed snapshots
show a placeholder; no street map or address is fabricated. Desktop retains
the existing map implementation. Android x86/x86_64 processes also use this
OpenStreetMap compatibility renderer, behind the same consent gate: the bundled
AMap 11.3 SDK contains ARM libraries only. Runtime selection checks the actual
process ABI, not the device's advertised ARM translation support. Compatibility
thumbnails do not wait for a native snapshot or run the native snapshot timeout.

Descriptions remain plain text: name followed by an optional newline and
provider address. Legacy single-line and `/////` descriptions are readable.
Raw coordinates remain message data and are not printed in the card.

Validation: location message/picker widget tests cover theme, narrow/large-text
layouts, in-app navigation, read-only points, privacy gating and snapshot
release/cache reuse. Preview tests use a clearly marked local map fixture,
not production map imagery. Android compilation is verified; live map/network
rendering and iOS native execution still require device validation.


## Immersive detail

`detail/` owns action adapters, localized labels, glass chrome and tokens. The
page reuses `LiquidGlassSurface` with the floating treatment (refraction, edge
lighting, translucent tint), initializes the existing renderer and uses bounded
implicit press scaling. High contrast and reduced motion retain the existing
accessible fallback. Map thumbnails and the picker retain their original pin.

Directions offer installed Apple/Google/AMap/Baidu apps and a browser fallback.
The destination and shared URL always use the message's WGS84 coordinate; AMap
receives `dev=1`, Baidu receives `coord_type=wgs84`. The public platform interface
is awaited because map_launcher 4.4.2's convenience wrapper drops launch errors.
Sharing opens the OS share sheet with a valid iPad anchor, not an automatic send.
No weather data is fabricated. Native maps support standard/satellite styles;
the desktop/Android x86 OpenStreetMap renderer exposes only its supported style.

Map controls stay above the bottom card; short landscapes use a horizontal
control row. The card scrolls with large fonts. Map provider attribution stays
above the card. GPS failures keep the shared location usable and permanent
permission/service failures offer settings. Tests use an explicitly synthetic
map for layout previews; they are not real map or device verification.


## Missing addresses

`detail/chat_location_address_source.dart` resolves the shared WGS84 coordinate
through `openim/location-address` after map readiness/consent. Android uses the
system Geocoder (API 33 asynchronous callback, older versions on a worker);
iOS uses CLGeocoder for compatibility with the project's deployment target.
Both native requests and Dart have bounded waiting. No new GPS permission is
needed for address lookup. Provider/network availability is not guaranteed.
Existing message addresses and custom names are preserved. Results update only
the detail presentation and its share/navigation labels, never stored messages.
Loading, missing results and failures are explicit; retry is user initiated.
A closed page ignores late callbacks. The system geocoder also works independently
of the Android x86 OpenStreetMap renderer. Desktop without a registered service
shows the same recoverable unavailable state instead of fabricating an address.
# 地图天气

详情地图就绪后，左上角液态玻璃胶囊查询**分享地点**的天气；用户定位或拖动地图不会改变天气对应的地点。显示摄氏温度和天气图标，点击温度不打开弹窗；天气描述及 MET Norway / CC BY 4.0 来源信息保留在长按提示中。加载失败显示重试，不使用示例或过期温度。

数据来自 MET Norway Locationforecast 2.0 的当前附近时段预报，并非现场实测。请求坐标保留四位小数，同地点并发合并，成功结果缓存一小时（最多 32 个地点），超过当前时间 90 分钟的数据不展示。请求最长等待 15 秒。服务无需 API Key；`WEATHER_USER_AGENT` 可通过 `--dart-define` 配置，发布时应保留有效的项目联系地址。

接口：https://api.met.no/weatherapi/locationforecast/2.0/documentation
许可与署名：https://www.met.no/en/free-meteorological-data/Licensing-and-crediting

