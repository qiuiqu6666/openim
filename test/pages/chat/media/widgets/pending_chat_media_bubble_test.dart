import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/media/preparation/pending_chat_media.dart';
import 'package:openim/pages/chat/media/widgets/pending_chat_media_bubble.dart';
import 'package:openim_common/openim_common.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

class _Asset extends AssetEntity {
  _Asset(int type)
      : super(id: 'selected', typeInt: type, width: 100, height: 200);
  final thumbnail = Completer<Uint8List?>();
  @override
  Future<Uint8List?> thumbnailDataWithSize(ThumbnailSize size,
          {ThumbnailFormat format = ThumbnailFormat.jpeg,
          int quality = 100,
          PMProgressHandler? progressHandler,
          int frame = 0}) =>
      thumbnail.future;
}

void main() {
  setUp(() {
    OpenIM.iMManager.userID = 'self';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'self', nickname: 'Me');
  });
  for (final type in [MessageType.picture, MessageType.video]) {
    testWidgets('upload sector is centered in media bubble type=$type',
        (tester) async {
      final status = ValueNotifier<ChatTransferStatus?>(
          const ChatTransferStatus(ChatTransferStage.uploading, 51));
      addTearDown(status.dispose);
      addTearDown(Get.reset);
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
          home: Scaffold(
            body: ChatItemView(
              message: Message.fromJson({
                'clientMsgID': 'upload',
                'sendID': 'self',
                'recvID': 'peer',
                'contentType': type,
                'sessionType': ConversationType.single,
                'sendTime': 1000000,
                'status': MessageStatus.sending,
              }),
              transferStatus: status,
              showAvatar: false,
              mediaItemBuilder: (_, __) => const SizedBox(
                  key: ValueKey('media-preview'), width: 120, height: 200),
              onTapUserProfile: (_) {},
            ),
          ),
        ),
      ));
      expect(find.byType(ChatTransferStatusView), findsOneWidget);
      expect(
          (tester.getCenter(find.byType(ChatTransferStatusView)) -
                  tester.getCenter(find.byKey(const ValueKey('media-preview'))))
              .distance,
          lessThan(0.01));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  for (final channel in [false, true]) {
    testWidgets(
        'video preparation and SDK bubble retain geometry channel=$channel',
        (tester) async {
      final asset = _Asset(2);
      asset.thumbnail.complete(null);
      final phase = ValueNotifier<int>(0);
      addTearDown(phase.dispose);
      addTearDown(Get.reset);
      final pending = PendingChatMedia(
          asset: asset, conversationID: 'chat', visible: () => true);
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
            home: Scaffold(
                body: ValueListenableBuilder<int>(
                    valueListenable: phase,
                    builder: (_, value, __) {
                      if (value == 0) {
                        return PendingChatMediaBubble(
                            pending: pending, isChannel: channel);
                      }
                      return ChatItemView(
                        message: Message.fromJson({
                          'clientMsgID': 'video',
                          'sendID': 'self',
                          'recvID': 'peer',
                          'contentType': MessageType.video,
                          'sessionType': ConversationType.single,
                          'sendTime': 1000000,
                          'status': value == 1
                              ? MessageStatus.sending
                              : MessageStatus.succeeded,
                          'videoElem': {
                            'snapshotWidth': 100,
                            'snapshotHeight': 200
                          },
                        }),
                        avatarSize: 36,
                        alignLeft: channel,
                        showAvatar: !channel,
                        showLeftNickname: false,
                        mediaItemBuilder: (_, __) =>
                            SizedBox(width: videoWidth, height: videoWidth * 2),
                        onTapUserProfile: (_) {},
                      );
                    }))),
      ));
      await tester.pump();
      final before = tester.getRect(find.byType(ChatMessageContentAnchor));
      final rowBefore = tester.getRect(find.byType(ChatItemContainer));
      for (final value in [1, 2]) {
        phase.value = value;
        await tester.pump();
        expect(tester.getRect(find.byType(ChatMessageContentAnchor)), before);
        expect(tester.getRect(find.byType(ChatItemContainer)), rowBefore);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  for (final dark in [false, true]) {
    for (final type in [1, 2]) {
      testWidgets('bubble appears before thumbnail: dark=$dark type=$type',
          (tester) async {
        final asset = _Asset(type);
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(Get.reset);
        await tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (_, __) => GetMaterialApp(
            translations: TranslationService(),
            locale: const Locale('zh', 'CN'),
            theme: dark ? ThemeData.dark() : ThemeData.light(),
            home: Scaffold(
                body: MediaQuery(
              data: const MediaQueryData(
                  textScaler: TextScaler.linear(2), disableAnimations: true),
              child: PendingChatMediaBubble(
                  pending: PendingChatMedia(
                      asset: asset,
                      conversationID: 'chat',
                      visible: () => true)),
            )),
          ),
        ));
        expect(find.byType(ChatItemContainer), findsOneWidget);
        expect(
            tester
                .widget<ChatItemContainer>(find.byType(ChatItemContainer))
                .isSending,
            isTrue);
        expect(find.textContaining('等待压缩'), findsNothing);
        expect(find.text('取消待处理'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 1));
        final spinner = find.byType(CupertinoActivityIndicator);
        expect(spinner, findsOneWidget);
        final preview = find.descendant(
            of: find.byType(PendingChatMediaBubble),
            matching: find.byType(FutureBuilder<Uint8List?>));
        expect(
            (tester.getCenter(spinner) - tester.getCenter(preview)).distance,
            lessThan(0.01));
        asset.thumbnail.completeError(StateError('unavailable thumbnail'));
        await tester.pump();
        expect(
            find.byIcon(
                type == 2 ? Icons.videocam_outlined : Icons.image_outlined),
            findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
