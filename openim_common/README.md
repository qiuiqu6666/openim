<!--
This README describes the package. If you publish this package to pub.dev,
this README's contents appear on the landing page for your package.

For information about how to write a good package README, see the guide for
[writing package pages](https://dart.dev/guides/libraries/writing-package-pages).

For general information about developing packages, see the Dart guide for
[creating packages](https://dart.dev/guides/libraries/create-library-packages)
and the Flutter guide for
[developing packages and plugins](https://flutter.dev/developing-packages).
-->

TODO: Put a short description of the package here that helps potential users
know whether this package might be useful for them.

共享离线消息推送协议位于 `lib/src/push/apns/apns_offline_push_info.dart`，通过 `openim_common.dart` 导出 `APNsOfflinePushInfo`。工厂只接收真实 SDK 发送者和目标会话类型，生成通用 APNs 提示及导航扩展；不读取应用状态、不请求服务、不包含消息正文。应用发送入口负责查询未知目标群类型与校验会话所有权，契约及回归测试见 [iOS APNs](../docs/ios-apns-push.md) 和 `test/core/push/apns/apns_offline_push_info_test.dart`。

## Features

TODO: List what your package can do. Maybe include images, gifs, or videos.

## Getting started

TODO: List prerequisites and provide or point to information on how to
start using the package.

## Usage

TODO: Include short and useful examples for package users. Add longer examples
to `/example` folder.

```dart
const like = 'sample';
```

## Additional information

TODO: Tell users more about the package: where to find more information, how to
contribute to the package, how to file issues, what response they can expect
from the package authors, and more.
