import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/group/announcements/group_announcement_banner.dart';
import 'package:openim/pages/chat/group/chat_group_controller.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';
import 'package:openim/pages/group_features/live/widgets/live_banner.dart';
import 'package:openim/pages/group_features/models/group_features.dart';
import 'package:openim/pages/group_features/widgets/group_chat_feature_surface.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../group_features/live/live_test_support.dart';

const _groupID = 'group#1';
const _userID = 'self';
const _notice = '欢迎加入群聊，请遵守群规。';
const _messageBodyKey = ValueKey('group-entry-message-body');
const _sdk = MethodChannel('flutter_openim_sdk');

GroupInfo _metadata({String notice = _notice, int version = 42}) => GroupInfo(
      groupID: _groupID,
      groupName: '测试群聊',
      ownerUserID: 'another-member',
      memberCount: 12,
      notification: notice,
      notificationUpdateTime: version,
      ex: '',
    );

Map<String, dynamic> _current({bool active = true}) => {
      'active': active,
      if (active)
        'session': {
          ...liveDTO(),
          'roomName': '每日直播',
          'description': '和大家边看边聊',
          'anchorUserId': '',
        },
    };

class _EntryFixture {
  _EntryFixture() {
    transport = LiveTransport((request) {
      if (request.path.endsWith('/current')) {
        final reply = Completer<Map<String, dynamic>>();
        currentReplies.add(reply);
        return reply.future;
      }
      if (request.path.endsWith('/feature-capabilities')) {
        return {
          'groupID': _groupID,
          'capabilityVersion': 1,
          'live': {},
          'sangong': {},
          'markSix': {},
        };
      }
      throw StateError('Unexpected group entry request: ${request.path}');
    });
    store = GroupFeatureStore(
      api: transport.api(),
      sessionCurrent: () => active,
      fetchGroups: (_) async => [],
    )
      ..seed(_metadata())
      // /current may be the only source of live state on deployed SDK mirrors.
      // Re-entry must reuse this projection without granting any private role.
      ..applyLiveState(
          _groupID,
          const GroupLiveFeature(
            status: 'ready',
            sessionID: 'live-1',
            roomName: '每日直播',
            description: '和大家边看边聊',
          ));
    open();
  }

  late final LiveTransport transport;
  late final GroupFeatureStore store;
  final currentReplies = <Completer<Map<String, dynamic>>>[];
  final metadataReplies = <Completer<List<GroupInfo>>>[];
  final groupChanges = StreamController<GroupInfo>.broadcast(sync: true);
  late ChatGroupController controller;
  bool active = true;
  int metadataCompleted = 0;

  void open() {
    final reply = Completer<List<GroupInfo>>();
    metadataReplies.add(reply);
    controller = ChatGroupController.withSources(
      groupID: () => _groupID,
      currentUserID: () => _userID,
      messages: <Message>[].obs,
      clearInput: () {},
      onGroupProfileChanged: (_, __) {},
      onGroupInfoApplied: store.seed,
      readCachedGroupInfo: store.cachedGroupInfo,
      events: ChatGroupEvents(
        joined: const Stream.empty(),
        left: const Stream.empty(),
        memberAdded: const Stream.empty(),
        memberDeleted: const Stream.empty(),
        memberChanged: const Stream.empty(),
        groupChanged: groupChanges.stream,
      ),
      queries: ChatGroupQueries(
        isJoined: (_) async => true,
        groupInfo: (_) => reply.future,
        selfMember: (_, __) async => [],
        ownerAndAdmin: (_) async => [],
      ),
    )..initialize();
    unawaited(controller.loadAfterHistory().whenComplete(() {
      metadataCompleted++;
    }));
  }

  void completeMetadata() {
    for (final reply in metadataReplies) {
      if (!reply.isCompleted) reply.complete([_metadata()]);
    }
  }

  void completeCurrent({bool active = true}) {
    for (final reply in currentReplies) {
      if (!reply.isCompleted) reply.complete(_current(active: active));
    }
  }

  void dispose() {
    controller.close();
    active = false;
    completeMetadata();
    completeCurrent(active: false);
    store.dispose();
    // Futures created in the widget test's fake-async zone must be drained by
    // pump in that zone, not awaited from addTearDown's outer zone.
    unawaited(groupChanges.close());
  }
}

Future<void> _mount(
    WidgetTester tester, _EntryFixture fixture, SharedPreferences preferences,
    {bool dark = false}) async {
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => MaterialApp(
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      home: Scaffold(
        appBar: AppBar(title: const Text('测试群聊')),
        body: Column(children: [
          Obx(() => GroupAnnouncementBanner(
                text: fixture.controller.announcement.value,
                version: fixture.controller.announcementVersion.value,
                groupID: _groupID,
                userID: _userID,
                preferences: preferences,
              )),
          Expanded(
            child: ListenableBuilder(
              listenable: fixture.store,
              builder: (_, __) => GroupChatFeatureSurface(
                store: fixture.store,
                featureContext: fixture.store.context(
                  id: _groupID,
                  name: '测试群聊',
                  userID: _userID,
                  admin: fixture.controller.isAdminOrOwner,
                  current: () => !fixture.controller.isClosed && fixture.active,
                ),
                child: const SizedBox.expand(
                  key: _messageBodyKey,
                  child:
                      Align(alignment: Alignment.topLeft, child: Text('聊天记录')),
                ),
              ),
            ),
          ),
        ]),
      ),
    ),
  ));
}

(Rect, Rect, Rect) _geometry(WidgetTester tester) {
  final notice = find.byKey(const ValueKey('group-announcement-row'));
  final live = find.byType(GroupLiveBanner);
  expect(notice, findsOneWidget);
  expect(live, findsOneWidget);
  final noticeBounds = tester.getRect(notice);
  final liveBounds = tester.getRect(live);
  final messageBounds = tester.getRect(find.byKey(_messageBodyKey));
  expect(liveBounds.top, greaterThanOrEqualTo(noticeBounds.bottom));
  expect(messageBounds.top, closeTo(liveBounds.bottom, .01));
  return (noticeBounds, liveBounds, messageBounds);
}

Future<void> _frame(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({
      'group_announcement_read:$_userID:$_groupID': _notice,
    });
    await DataSp.init();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sdk, (_) async => '[]');
  });
  tearDown(() {
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sdk, null);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'cached announcement and live retain first-paint geometry through refresh and re-entry dark=$dark',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final previousDark = Styles.isDark;
      Styles.isDark = dark;
      addTearDown(() => Styles.isDark = previousDark);
      final preferences = await SharedPreferences.getInstance();
      final fixture = _EntryFixture();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.dispose();
        await tester.pump();
      });

      await _mount(tester, fixture, preferences, dark: dark);
      final firstPaint = _geometry(tester);
      expect(fixture.controller.isAdminOrOwner, isFalse);
      for (var frame = 0; frame < 6; frame++) {
        await _frame(tester);
        expect(_geometry(tester), firstPaint,
            reason: 'An unchanged pending read cannot collapse either row.');
      }
      expect(fixture.currentReplies, hasLength(1));
      fixture.completeMetadata();
      fixture.completeCurrent();
      for (var frame = 0; frame < 6; frame++) {
        await _frame(tester);
        expect(_geometry(tester), firstPaint);
      }
      expect(fixture.metadataCompleted, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      fixture.controller.close();
      fixture.open();
      await _mount(tester, fixture, preferences, dark: dark);
      expect(_geometry(tester), firstPaint,
          reason: 'The second route must paint both cached rows immediately.');
      for (var frame = 0; frame < 6; frame++) {
        await _frame(tester);
        expect(_geometry(tester), firstPaint);
      }
      expect(fixture.currentReplies, hasLength(2),
          reason: 'Cache-first rendering must still calibrate live freshness.');
      fixture.completeMetadata();
      fixture.completeCurrent();
      for (var frame = 0; frame < 6; frame++) {
        await _frame(tester);
        expect(_geometry(tester), firstPaint);
      }
      expect(fixture.metadataCompleted, 2);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('fresh notice and ended live apply without an intermediate gap',
      (tester) async {
    final preferences = await SharedPreferences.getInstance();
    final fixture = _EntryFixture();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
      await tester.pump();
    });
    await _mount(tester, fixture, preferences);
    final original = _geometry(tester);
    for (var frame = 0; frame < 6; frame++) {
      await _frame(tester);
    }
    expect(fixture.metadataCompleted, 0);
    fixture.completeMetadata();
    for (var frame = 0; frame < 6; frame++) {
      await _frame(tester);
    }
    expect(fixture.metadataCompleted, 1);

    const updatedNotice = '群公告已经更新，请查看。';
    await preferences.setString(
        'group_announcement_read:$_userID:$_groupID', updatedNotice);
    fixture.groupChanges.add(_metadata(notice: updatedNotice, version: 43));
    await tester.pump();
    expect(fixture.controller.announcementVersion.value, '43');
    expect(_geometry(tester), original,
        reason: 'A new revision must not first hide the visible notice.');
    expect(find.text(updatedNotice), findsOneWidget);

    fixture.completeCurrent(active: false);
    for (var frame = 0; frame < 6; frame++) {
      await _frame(tester);
    }
    expect(find.byType(GroupLiveBanner), findsNothing);
    expect(
        find.byKey(const ValueKey('group-announcement-row')), findsOneWidget);
    final messageBounds = tester.getRect(find.byKey(_messageBodyKey));
    expect(
        messageBounds.top, closeTo(original.$3.top - original.$2.height, .01),
        reason: 'A confirmed end removes exactly the live row.');
    expect(fixture.store.liveFeature(_groupID).isActive, isFalse);
    expect(tester.takeException(), isNull);
  });
}
