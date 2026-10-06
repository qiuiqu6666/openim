import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/navigation/chat_message_navigation.dart';
import 'package:openim/routes/app_pages.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/chat/contact_card/contact_card_identity_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _preview = bool.fromEnvironment('CONTACT_CARD_MESSAGE_PREVIEW');
const _previewKey = ValueKey('contact-card-message-preview');

Message _message({
  String id = 'contact-card-message',
  bool sent = true,
  bool read = false,
  int sessionType = ConversationType.single,
  int status = MessageStatus.succeeded,
  String target = 'im_target-routing',
  String account = '2138014845',
  String inviteCode = 'fi_test',
  String name = '卡片联系人',
}) =>
    Message.fromJson({
      'clientMsgID': id,
      'contentType': MessageType.card,
      'sendID': sent ? 'me' : 'sender-im-independent',
      'recvID': sessionType == ConversationType.single ? 'peer' : 'group',
      'senderNickname': sent ? 'Me' : 'Sender',
      'sessionType': sessionType,
      if (sessionType != ConversationType.single) 'groupID': 'group',
      'sendTime': 1700000000000,
      'isRead': read,
      'status': status,
      'cardElem': {
        'userID': target,
        'nickname': name,
        'ex': jsonEncode({
          'inviteCode': inviteCode,
          'contactCard': {'userID': target, 'account': account},
        }),
      },
    });

Widget _item(Message message, {VoidCallback? retry, VoidCallback? onTap}) =>
    ChatItemView(
      key: ValueKey(message.clientMsgID),
      message: message,
      showLeftNickname: false,
      onTapUserProfile: (_) {},
      onFailedToResend: retry,
      onClickItemView: onTap,
    );

Finder _row(String id) => find.byWidgetPredicate(
    (widget) => widget is ChatItemView && widget.message.clientMsgID == id);
Finder _inRow(String id, Type type) =>
    find.descendant(of: _row(id), matching: find.byType(type));
Finder _footer(String id) => find.descendant(
    of: _row(id), matching: find.byKey(const ValueKey('contact-card-footer')));

void _within(Rect item, Rect parent) {
  expect(item.left, greaterThanOrEqualTo(parent.left - .01));
  expect(item.top, greaterThanOrEqualTo(parent.top - .01));
  expect(item.right, lessThanOrEqualTo(parent.right + .01));
  expect(item.bottom, lessThanOrEqualTo(parent.bottom + .01));
}

void _statusInsideFooter(WidgetTester tester, Message message, Type type) {
  final id = message.clientMsgID!;
  final status = _inRow(id, type);
  final footer = _footer(id);
  final card = _inRow(id, ContactCardView);
  expect(status, findsOneWidget);
  expect(footer, findsOneWidget);
  expect(
      find.descendant(of: footer, matching: find.byType(type)), findsOneWidget);
  _within(tester.getRect(status), tester.getRect(footer));
  _within(tester.getRect(footer), tester.getRect(card));
  final time = tester.widget<ContactCardView>(card).time;
  final timeText = find.descendant(of: footer, matching: find.text(time));
  expect(timeText, findsOneWidget);
  expect(tester.getRect(status).left,
      greaterThanOrEqualTo(tester.getRect(timeText).right));
}

Future<void> _mount(WidgetTester tester, Widget child,
    {Brightness brightness = Brightness.light,
    Size size = const Size(375, 812),
    double textScale = 1,
    bool settle = true,
    List<Map<String, dynamic>>? openedProfiles}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final previousDark = Styles.isDark;
  Styles.isDark = brightness == Brightness.dark;
  addTearDown(() => Styles.isDark = previousDark);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      theme: ThemeData(
          brightness: brightness,
          fontFamily: _preview ? 'ContactCardMessagePreviewFont' : null),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!),
      getPages: [
        GetPage<dynamic>(
          name: AppRoutes.userProfilePanel,
          page: () {
            openedProfiles
                ?.add(Map<String, dynamic>.from(Get.arguments as Map));
            return const Scaffold(body: Text('联系人资料'));
          },
        ),
      ],
      home: Scaffold(
        body: RepaintBoundary(
          key: _previewKey,
          child: Builder(
            builder: (context) => ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: Align(alignment: Alignment.topLeft, child: child),
            ),
          ),
        ),
      ),
    ),
  ));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));
}

Future<void> _loadPreviewFont() async {
  if (!_preview) return;
  for (final entry in {
    'ContactCardMessagePreviewFont': 'C:/Windows/Fonts/msyh.ttc',
    'MaterialIcons':
        'E:/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  }.entries) {
    final loader = FontLoader(entry.key)
      ..addFont(File(entry.value)
          .readAsBytes()
          .then((bytes) => ByteData.sublistView(bytes)));
    await loader.load();
  }
}

Future<void> _capture(WidgetTester tester, Brightness brightness,
    {bool large = false}) async {
  if (!_preview) return;
  await tester.runAsync(() async {
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(_previewKey));
    final image = await boundary.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final suffix = large ? '-large' : '';
    await File('.dart_tool/contact-card-message-${brightness.name}$suffix.png')
        .writeAsBytes(png!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(_loadPreviewFont);
  setUp(() async {
    Get.testMode = true;
    OpenIM.iMManager.userID = 'me';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'me', nickname: 'Me');
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    expect(DataSp.getLoginCertificate(), isNull);
  });
  tearDown(Get.reset);

  for (final brightness in Brightness.values) {
    testWidgets(
        '${brightness.name} read and unread receipts stay in the card footer while received cards have none',
        (tester) async {
      final unread = _message(id: 'unread');
      final read = _message(id: 'read', read: true);
      final received = _message(id: 'received', sent: false, read: true);
      await _mount(
          tester,
          Column(mainAxisSize: MainAxisSize.min, children: [
            _item(unread),
            _item(read),
            _item(received),
          ]),
          brightness: brightness);
      for (final message in [unread, read]) {
        _statusInsideFooter(tester, message, ChatReadReceiptIcon);
        final receipt = tester.widget<ChatReadReceiptIcon>(
            _inRow(message.clientMsgID!, ChatReadReceiptIcon));
        expect(receipt.isRead, message.isRead);
        expect(receipt.color, ContactCardTokens.footerText);
        expect(receipt.semanticLabel,
            message.isRead! ? StrRes.hasRead : StrRes.unread);
        expect(
            find.descendant(
                of: _row(message.clientMsgID!),
                matching: find.text('2138014845')),
            findsOneWidget);
        expect(
            find.descendant(
                of: _row(message.clientMsgID!),
                matching: find.text('im_target-routing')),
            findsNothing);
      }
      expect(_inRow('received', ChatReadReceiptIcon), findsNothing);
      expect(_inRow('received', ChatSendFailedView), findsNothing);
      expect(_inRow('received', ChatDelayedStatusView), findsNothing);
      expect(_footer('received'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capture(tester, brightness);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('hiding read receipts keeps a sent check inside the card',
      (tester) async {
    final message = _message(read: true);
    await _mount(tester, _item(message));
    expect(
        tester
            .widget<ChatReadReceiptIcon>(find.byType(ChatReadReceiptIcon))
            .isRead,
        isTrue);
    FriendDisplayPreferences.setReadReceipts(false);
    await tester.pumpAndSettle();
    final receipt =
        tester.widget<ChatReadReceiptIcon>(find.byType(ChatReadReceiptIcon));
    expect(receipt.isRead, isFalse);
    expect(receipt.semanticLabel, StrRes.sentSuccessfully);
    _statusInsideFooter(tester, message, ChatReadReceiptIcon);
    expect(tester.takeException(), isNull);
  });

  testWidgets('group cards keep the sent check despite message read flags',
      (tester) async {
    final message =
        _message(sessionType: ConversationType.superGroup, read: true);
    await _mount(tester, _item(message));
    final receipt =
        tester.widget<ChatReadReceiptIcon>(find.byType(ChatReadReceiptIcon));
    expect(receipt.isRead, isFalse);
    expect(receipt.semanticLabel, StrRes.sentSuccessfully);
    _statusInsideFooter(tester, message, ChatReadReceiptIcon);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the failed in-card action retries without opening the profile',
      (tester) async {
    final message = _message(status: MessageStatus.failed);
    var retries = 0;
    var profileTaps = 0;
    await _mount(tester,
        _item(message, retry: () => retries++, onTap: () => profileTaps++));
    _statusInsideFooter(tester, message, ChatSendFailedView);
    expect(find.byType(ChatReadReceiptIcon), findsNothing);
    final failed = find.byType(ChatSendFailedView);
    expect(failed.hitTestable(), findsOneWidget);
    await tester.tap(failed);
    await tester.pumpAndSettle();
    expect(retries, 1);
    expect(profileTaps, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'snapshot updates and a sender account switch preserve SDK-target profile navigation and invite tokens',
      (tester) async {
    final message = _message();
    late StateSetter rebuild;
    final opened = <Map<String, dynamic>>[];
    final navigation = ChatMessageNavigation(
      isClosed: () => false,
      isGroupChat: () => false,
      isSingleChat: () => true,
      isAdminOrOwner: () => false,
      groupID: () => null,
      groupInfo: () => null,
    );
    void tapCard() => IMUtils.parseClickEvent(message,
        onViewUserInfo: (user) => navigation.viewUserInfo(user,
            isCard: true,
            inviteCode: friendCardInviteCode(message.cardElem?.ex)));
    await _mount(tester, StatefulBuilder(builder: (_, setState) {
      rebuild = setState;
      return _item(message, onTap: tapCard);
    }), openedProfiles: opened);
    expect(find.text('2138014845'), findsOneWidget);
    await tester.tap(find.byType(ContactCardView));
    await tester.pumpAndSettle();
    expect(opened.single['userID'], 'im_target-routing');
    expect(opened.single['addSource'], FriendAddSource.card);
    expect(opened.single['friendAddFields'], {'inviteCode': 'fi_test'});
    Get.back<void>();
    await tester.pumpAndSettle();

    OpenIM.iMManager.userID = 'another-sender-account';
    OpenIM.iMManager.userInfo =
        UserInfo(userID: 'another-sender-account', nickname: 'Another');
    rebuild(() {
      // SDK elements may be updated in place. The display snapshot must change
      // without changing the native recipient used by profile navigation.
      message.cardElem!.ex = jsonEncode({
        'inviteCode': 'fi_next',
        'contactCard': {
          'userID': 'im_target-routing',
          'account': '9988776655',
        },
      });
    });
    await tester.pumpAndSettle();
    expect(find.text('9988776655'), findsOneWidget);
    expect(find.text('2138014845'), findsNothing);
    expect(find.text('im_target-routing'), findsNothing);
    expect(find.byType(ChatReadReceiptIcon), findsNothing);
    await tester.tap(find.byType(ContactCardView));
    await tester.pumpAndSettle();
    expect(opened, hasLength(2));
    expect(opened.last['userID'], 'im_target-routing');
    expect(opened.last['addSource'], FriendAddSource.card);
    expect(opened.last['friendAddFields'], {'inviteCode': 'fi_next'});
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'an old opaque card gains its real profile account without a height jump',
      (tester) async {
    const target = 'im_old-profile-target';
    final profile = Completer<List<UserFullInfo>?>();
    final requested = <String>[];
    final resolver = ContactCardProfileResolver(
      currentUserID: () => 'me',
      currentToken: () => 'fixture-chat-token',
      fetchProfile: (userID) {
        requested.add(userID);
        return profile.future;
      },
    );
    await _mount(
        tester,
        ContactCardIdentityView(
          card: CardElem(userID: target, nickname: 'Alice'),
          isSelf: true,
          time: '18:29',
          resolver: resolver,
        ));
    final before = tester.getSize(find.byType(ContactCardView));
    expect(requested, [target]);
    expect(find.text(target), findsNothing);
    expect(find.text('2138014845'), findsNothing);
    profile.complete([
      UserFullInfo(userID: target, account: '2138014845', nickname: 'Alice'),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('2138014845'), findsOneWidget);
    expect(find.text(target), findsNothing);
    final after = tester.getSize(find.byType(ContactCardView));
    expect(after.height, closeTo(before.height, .01));
    expect(after.width, closeTo(before.width, .01));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'late profiles cannot overwrite a mutated card or update a disposed card',
      (tester) async {
    final pending = <String, Completer<List<UserFullInfo>?>>{};
    final resolver = ContactCardProfileResolver(
      currentUserID: () => 'me',
      currentToken: () => 'fixture-chat-token',
      fetchProfile: (userID) =>
          (pending[userID] = Completer<List<UserFullInfo>?>()).future,
    );
    final card = CardElem(userID: 'im_old', nickname: 'Alice');
    late StateSetter rebuild;
    await _mount(tester, StatefulBuilder(builder: (_, setState) {
      rebuild = setState;
      return ContactCardIdentityView(
        card: card,
        isSelf: true,
        time: '18:29',
        resolver: resolver,
      );
    }));
    expect(pending.keys, ['im_old']);
    rebuild(() {
      card.userID = 'im_latest';
      card.ex = jsonEncode({
        'inviteCode': 'fi_latest',
        'contactCard': {'userID': 'im_latest', 'account': '9988776655'},
      });
    });
    await tester.pumpAndSettle();
    expect(find.text('9988776655'), findsOneWidget);
    pending['im_old']!.complete([
      UserFullInfo(userID: 'im_old', account: '1111111111'),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('9988776655'), findsOneWidget);
    expect(find.text('1111111111'), findsNothing);
    expect(find.text('im_latest'), findsNothing);

    rebuild(() {
      card.userID = 'im_disposed';
      card.ex = null;
    });
    await tester.pumpAndSettle();
    expect(pending.containsKey('im_disposed'), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    pending['im_disposed']!.complete([
      UserFullInfo(userID: 'im_disposed', account: '2222222222'),
    ]);
    await tester.pumpAndSettle();
    expect(find.byType(ContactCardIdentityView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'card refreshes retain the sending delay and footer spinner color',
      (tester) async {
    var sending = true;
    var revision = 0;
    Color color = Colors.blue;
    late StateSetter rebuild;
    DateTime? sendingStartedAt;
    final card = _message().cardElem!;
    await _mount(tester, StatefulBuilder(builder: (_, setState) {
      rebuild = setState;
      sendingStartedAt ??= tester.binding.clock.now();
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Text('content-$revision'),
        ContactCardIdentityView(
          card: card,
          isSelf: true,
          time: '18:29',
          status: ChatDelayedStatusView(isSending: sending, color: color),
        ),
      ]);
    }), settle: false);
    Future<void> pumpTo(Duration elapsed) async {
      final remaining =
          sendingStartedAt!.add(elapsed).difference(tester.binding.clock.now());
      expect(remaining.isNegative, isFalse,
          reason:
              'Measure from the sending widget mount, including setup pumps.');
      await tester.pump(remaining);
    }

    await pumpTo(const Duration(milliseconds: 600));
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    rebuild(() {
      revision++;
      color = ContactCardTokens.footerText;
    });
    await tester.pump();
    expect(find.text('content-1'), findsOneWidget);
    await pumpTo(const Duration(milliseconds: 800));
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    // A content/color refresh at 600ms must retain the original 1000ms delay.
    // Give completion a margin while staying well before a restarted 1600ms.
    await pumpTo(const Duration(milliseconds: 1050));
    await tester.pump();
    final spinner = find.byType(CupertinoActivityIndicator);
    expect(spinner, findsOneWidget);
    expect(tester.widget<CupertinoActivityIndicator>(spinner).color,
        ContactCardTokens.footerText);
    _within(tester.getRect(spinner),
        tester.getRect(find.byKey(const ValueKey('contact-card-footer'))));
    rebuild(() => revision++);
    await tester.pump();
    expect(spinner, findsOneWidget);
    rebuild(() => sending = false);
    await tester.pump();
    await tester.pump();
    expect(spinner, findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        '${brightness.name} narrow large-text long accounts fit the card',
        (tester) async {
      const account = '@abcdefgh1234567890abcdefgh1234567890';
      final message = _message(
          name: '一个很长的真实联系人名称需要省略而不能挤出卡片', account: account, read: true);
      await _mount(tester, _item(message),
          brightness: brightness, size: const Size(320, 568), textScale: 2);
      final card = find.byType(ContactCardView);
      final cardRect = tester.getRect(card);
      expect(cardRect.left, greaterThanOrEqualTo(0));
      expect(cardRect.right, lessThanOrEqualTo(320));
      final label = find.text(account);
      expect(label, findsOneWidget);
      final labelWidget = tester.widget<Text>(label);
      expect(labelWidget.maxLines, 1);
      expect(labelWidget.overflow, TextOverflow.ellipsis);
      _within(tester.getRect(label), cardRect);
      _statusInsideFooter(tester, message, ChatReadReceiptIcon);
      expect(tester.takeException(), isNull);
      await _capture(tester, brightness, large: true);
      expect(tester.takeException(), isNull);
    });
  }
}
