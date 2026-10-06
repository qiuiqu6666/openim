import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/contacts/select_contacts/select_contacts_logic.dart';
import 'package:openim_common/openim_common.dart';

import 'support/friend_picker_presence_fixture.dart';

// Actual page exports are opt-in; no production contacts or presence are added.
// --dart-define=FRIEND_PICKER_PRESENCE_PREVIEW_DIR=E:/openim/.temp/friend-picker-presence-preview
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFriendPickerPresencePreviewFonts);
  for (final brightness in Brightness.values) {
    for (final action in [SelAction.forward, SelAction.addMember]) {
      for (final (width, scale, suffix) in const [
        (390.0, 1.0, ''),
        (320.0, 2.0, '-large'),
      ]) {
        testWidgets('export ${brightness.name} ${action.name} picker$suffix',
            skip: friendPickerPreviewDirectory.isEmpty, (tester) async {
          final data = friendPickerSamples();
          if (suffix.isNotEmpty) {
            data[0] = ISUserInfo.fromJson({
              ...data[0].toJson(),
              'remark': friendPickerLongName,
            });
          }
          final fixture =
              FriendPickerPresenceFixture(action: action, data: data);
          await fixture.open(tester,
              brightness: brightness,
              width: width,
              textScale: scale,
              fontFamily: 'FriendPickerPreviewCjk');
          await tester.tap(friendPickerRow('1001'));
          await tester.pumpAndSettle();
          final images = tester.widgetList<Image>(find.byType(Image)).toList();
          await tester.runAsync(() async {
            for (final image in images) {
              await precacheImage(
                  image.image, fixture.boundary.currentContext!);
            }
          });
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final render = fixture.boundary.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final output = Directory(friendPickerPreviewDirectory);
            await output.create(recursive: true);
            final image = await render.toImage(pixelRatio: 2);
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            final prefix = action == SelAction.addMember
                ? 'friend-picker-add-member'
                : 'friend-picker';
            await File('${output.path}/$prefix-${brightness.name}$suffix.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
            await File('${output.path}/preview-notes.txt').writeAsString(
              '真实我的好友/加成员页面，真实选择与全选 Controller，测试好友与在线状态。\n'
              '标准390×844；large320×844、200%字号；2倍输出；微软雅黑。\n'
              '已通过实际点击选中Alice；包含在线、3小时前在线、隐私隐藏和未知状态。\n'
              '数据只在测试中使用，未访问服务器或修改真实好友。\n',
            );
          });
        });
      }
    }
  }
}
