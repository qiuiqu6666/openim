import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/im_callback.dart';

import '../../../support/chat/chat_entry_sdk.dart';

class _NotificationApp extends EntryTestApp {
  final notifications = <Message>[];

  @override
  Future<void> showNotification(Message message,
      {bool showNotification = true}) async {
    notifications.add(message);
  }
}

Message _stream() => Message(
    contentType: MessageType.custom,
    customElem: CustomElem(description: 'assistantStream', data: '{'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _NotificationApp app;
  late EntryTestIM im;

  setUp(() {
    Get.testMode = true;
    app = _NotificationApp();
    Get.put<AppController>(app);
    im = EntryTestIM();
  });

  tearDown(() {
    im.close();
    Get.reset();
  });

  test('normal SDK callback forwards even malformed stream data without notice',
      () {
    final received = <Message>[];
    im.onRecvNewMessage = received.add;
    final fragment = _stream();
    im.recvNewMessage(fragment);
    expect(received, [fragment]);
    expect(app.notifications, isEmpty);
    final ordinary = Message(contentType: MessageType.text);
    im.recvNewMessage(ordinary);
    expect(received, [fragment, ordinary]);
    expect(app.notifications, [ordinary]);
  });

  test('offline callback routes stream data to the same transient receiver',
      () {
    final received = <Message>[];
    final offline = <Message>[];
    im.onRecvNewMessage = received.add;
    im.onRecvOfflineMessage = offline.add;
    im.imSdkStatus(IMSdkStatus.syncEnded);
    final fragment = _stream();
    im.recvOfflineMessage(fragment);
    expect(received, [fragment]);
    expect(offline, isEmpty);
    expect(app.notifications, isEmpty);
    final ordinary = Message(contentType: MessageType.text);
    im.recvOfflineMessage(ordinary);
    expect(offline, [ordinary]);
    expect(app.notifications, [ordinary]);
  });
}
