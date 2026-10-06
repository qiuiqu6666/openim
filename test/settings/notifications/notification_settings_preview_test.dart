import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/notifications/message_notification_sound_picker_page.dart';
import 'package:openim/pages/mine/settings/settings_draft_store.dart';
import 'package:openim/pages/mine/settings/widgets/settings_widgets.dart';
import 'package:permission_handler/permission_handler.dart';

import 'notification_test_support.dart';

// Actual production widget export with test-only account and platform fixtures.
// flutter test test/settings/notifications/notification_settings_preview_test.dart
//   --dart-define=NOTIFICATION_PREVIEW_DIR=docs/previews/notifications
const _directory = String.fromEnvironment('NOTIFICATION_PREVIEW_DIR');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(resetNotificationTestAccount);
  setUpAll(() async {
    if (_directory.isEmpty) return;
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (font.existsSync()) {
      final bytes = ByteData.sublistView(await font.readAsBytes());
      for (final family in ['NotificationPreviewCjk', 'CupertinoSystemText', 'CupertinoSystemDisplay']) {
        await (FontLoader(family)..addFont(Future.value(bytes))).load();
      }
    }
    final icons = File(
        'E:/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      await (FontLoader('MaterialIcons')
            ..addFont(
                Future.value(ByteData.sublistView(await icons.readAsBytes()))))
          .load();
    }
  });

  for (final brightness in Brightness.values) {
    for (final scene in [
      'normal',
      'permission',
      'disabled',
      'content',
      'error'
    ]) {
      testWidgets('export actual notification $scene ${brightness.name}',
          skip: _directory.isEmpty, (tester) async {
        final store = _store();
        final permission = TestNotificationPermissionGateway();
        final service = TestNotificationService()..remote = false;
        if (scene == 'permission') {
          permission.permission = PermissionStatus.denied;
        }
        if (scene == 'disabled') {
          store.updateNotifications(
              opened: false,
              openedPreview: 'sender',
              messageSoundEnabled: false,
              messageSound: 'crisp',
              vibration: false);
        }
        if (scene == 'error') {
          service
            ..remote = true
            ..closedResponse = (_) => Future.error(StateError('test failure'));
        }
        final boundary = GlobalKey();
        await pumpNotificationPage(tester,
            store: store,
            service: service,
            permission: permission,
            brightness: brightness,
            boundaryKey: boundary,
            fontFamily: 'NotificationPreviewCjk');
        if (scene == 'content') {
          await tapNotificationRow(tester, 'notification-closed-preview');
        }
        if (scene == 'error') {
          tester
              .widget<SettingsSwitchCell>(
                  notificationKey('notification-closed-enabled'))
              .onChanged!(false);
          await tester.pumpAndSettle();
        }
        await _export(
            tester, boundary, 'notification-$scene-${brightness.name}.png');
      });
    }

    testWidgets('export actual sound picker ${brightness.name}',
        skip: _directory.isEmpty, (tester) async {
      final store = _store()..updateNotifications(messageSound: 'crisp');
      final boundary = GlobalKey();
      await pumpNotificationPage(tester,
          store: store,
          brightness: brightness,
          boundaryKey: boundary,
          fontFamily: 'NotificationPreviewCjk',
          page: MessageNotificationSoundPickerPage(
              store: store,
              preview: TestNotificationSoundPreview(),
              isCallActive: () => false));
      await _export(
          tester, boundary, 'notification-sounds-${brightness.name}.png');
    });
  }
}

Future<void> _export(
    WidgetTester tester, GlobalKey key, String filename) async {
  expect(tester.takeException(), isNull);
  final render =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final output = Directory(_directory)..createSync(recursive: true);
    await File('${output.path}/$filename')
        .writeAsBytes(data!.buffer.asUint8List());
    await File('${output.path}/preview-notes.txt').writeAsString(
      '通知设置与声音选择页真实 Flutter Widget 渲染。\n'
      '逻辑尺寸 390×844；亮色/暗色；字体 Microsoft YaHei。\n'
      '正常、权限未开启、依赖项禁用、内容选择与保存失败状态。\n'
      '账户、权限和保存失败为测试夹具，不调用真实消息/后端/系统权限。\n',
    );
    image.dispose();
  });
}

SettingsDraftStore _store() {
  final store = SettingsDraftStore();
  addTearDown(store.dispose);
  return store;
}
