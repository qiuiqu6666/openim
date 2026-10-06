import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim/pages/chat/messages/selection/message_selection_controller.dart';
import 'package:openim/pages/chat/messages/widgets/chat_message_tile.dart';
import 'package:openim/pages/chat/voice/voice_transcription_controller.dart';
import 'package:openim_common/openim_common.dart';
import 'package:rxdart/rxdart.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'support/selection_test_messages.dart';

class _SelectionTileLogic extends GetxController implements ChatLogic {
  _SelectionTileLogic(Message message, {required VoidCallback onStart}) {
    messageList.add(message);
    messageSelection = MessageSelectionController(
      messages: () => messageList,
      isClosed: () => false,
      onStart: onStart,
      deleteMessages: (_) async => true,
      forwardMessages: (_, {required merged}) async => false,
    );
    voiceTranscriptions = VoiceTranscriptionController(
      transcribe: (_, {cancelToken}) async => '',
    );
    voicePlayback = VoicePlaybackController(messages: () => messageList);
  }

  @override
  final messageList = <Message>[].obs;
  @override
  final scaleFactor = 1.0.obs;
  @override
  final copyTextMap = <String?, String?>{};
  @override
  final sendStatusSub = PublishSubject<MsgStreamEv<bool>>();
  @override
  late final MessageSelectionController messageSelection;
  @override
  late final VoicePlaybackController voicePlayback;
  @override
  late final VoiceTranscriptionController voiceTranscriptions;
  @override
  bool get isSingleChat => true;
  @override
  bool get isGroupChat => false;
  @override
  bool get isOfficialNotificationChat => false;
  @override
  String? get senderName => '我';
  @override
  ValueKey itemKey(Message message) => ValueKey(message.clientMsgID!);
  @override
  Map<String, String> getAtMapping(Message message) => {};
  @override
  String? getShowTime(Message message) => null;
  @override
  String? getNewestNickname(Message message) => message.senderNickname;
  @override
  String? getNewestFaceURL(Message message) => '';
  @override
  bool canForward(Message message) =>
      message.status == MessageStatus.succeeded &&
      message.attachedInfoElem?.isPrivateChat != true;
  @override
  bool canFavorite(Message message) => false;
  @override
  bool canAddMessageToStickers(Message message) => false;
  @override
  bool canRevoke(Message message) => false;
  @override
  bool canTranscribeVoice(Message message) => false;
  @override
  VoiceTranscriptionState? displayedVoiceTranscription(Message message) => null;
  @override
  void markMessageAsRead(Message message, bool visible) {}
  @override
  void setFundMessageVisible(Message message, bool visible) {}
  @override
  void onTapRightAvatar() {}
  @override
  void clickLinkText(String url, Object? type) {}

  void disposeFixture() {
    messageSelection.dispose();
    voiceTranscriptions.dispose();
    voicePlayback.dispose();
    sendStatusSub.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    Get.testMode = true;
    final previousInterval =
        VisibilityDetectorController.instance.updateInterval;
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    addTearDown(() => VisibilityDetectorController.instance.updateInterval =
        previousInterval);
    OpenIM.iMManager.userID = 'me';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'me', nickname: '我');
  });
  tearDown(Get.reset);

  for (final variant in ['normal', 'failed', 'private']) {
    testWidgets(
        '$variant tile places selection after delete and closes the menu before entry',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final message = selectionMessage('menu-$variant',
          status: variant == 'failed'
              ? MessageStatus.failed
              : MessageStatus.succeeded,
          private: variant == 'private');
      var startedAfterClosing = false;
      late CustomPopupMenuController popup;
      final logic = _SelectionTileLogic(message, onStart: () {
        startedAfterClosing = !popup.menuIsShowing;
      });
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        logic.disposeFixture();
      });
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
          translations: TranslationService(),
          locale: const Locale('zh', 'CN'),
          theme: ThemeData.light(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.only(top: 200),
              child: ChatMessageTile(logic: logic, message: message),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final item = tester.widget<ChatItemView>(find.byType(ChatItemView));
      popup = tester
          .widget<ChatMessageMenu>(find.byType(ChatMessageMenu))
          .controller!;
      final ids = item.messageMenus.map((menu) => menu.id).toList();
      expect(ids.indexOf('delete'), lessThan(ids.indexOf('multiSelect')));
      expect(ids.last, 'multiSelect');
      expect(ids, isNot(contains('mergeForward')));
      if (variant != 'normal') {
        expect(ids, isNot(contains('forwardMessage')));
      }
      await tester.longPress(find.text('消息 menu-$variant'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat-message-menu-panel')),
          findsOneWidget);
      await tester.tap(
          find.byKey(const ValueKey('chat-message-menu-action-multiSelect')));
      await tester.pumpAndSettle();
      expect(startedAfterClosing, isTrue);
      expect(logic.messageSelection.active, isTrue);
      expect(logic.messageSelection.selectedMessages, [message]);
      expect(
          find.byKey(const ValueKey('chat-message-menu-panel')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
