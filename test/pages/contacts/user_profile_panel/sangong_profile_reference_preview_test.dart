import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';
import 'package:openim/pages/group_features/sangong/profile/sangong_profile_ledger_floating_entry.dart';
import 'package:openim_common/openim_common.dart';
import '../../group_features/sangong/sangong_test_support.dart';
import 'support/profile_panel_fixture.dart';
import 'support/profile_panel_host.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
        'actual profile puts compact reference forms before calls dark=$dark',
        (tester) async {
      final export = Platform.environment['PROFILE_SERVICES_CAPTURE'] == '1';
      final previousShadows = debugDisableShadows;
      if (export) {
        debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = previousShadows);
        await tester.runAsync(() async {
          final bytes = ByteData.sublistView(
              await File('C:/Windows/Fonts/msyh.ttc').readAsBytes());
          for (final family in [
            'SangongProfileCjk',
            'CupertinoSystemText',
            'CupertinoSystemDisplay'
          ]) {
            await (FontLoader(family)..addFont(Future.value(bytes))).load();
          }
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        });
      }
      OpenIM.iMManager.userID = 'owner';
      final api = SangongTestApi()
        ..respond = (call) {
          if (call.path.endsWith('/feature-capabilities')) {
            return {
              'groupID': 'g',
              'capabilityVersion': 1,
              'sangong': {'canManage': true, 'tenantID': 'tenant-authorized'}
            };
          }
          if (call.path.endsWith('/reports/users')) {
            return {
              'users': [
                {
                  'userId': 19,
                  'imUserId': 'target',
                  'nickname': '秋啊',
                  'balance': 420,
                  'rebatePer10000': 8
                }
              ],
              'page': 1,
              'totalPages': 1
            };
          }
          if (call.path.endsWith('/user-detail')) {
            return {
              'parent': {'nickname': '上级甲'}
            };
          }
          if (call.path.endsWith('/session')) {
            return {
              'round': {
                'id': 18,
                'bankerDoor': 2,
                'bankerLimit': 2000,
                'coBank': {
                  'poolTotal': 800,
                  'members': [
                    {
                      'userId': 19,
                      'imUserId': 'target',
                      'nickname': '秋啊',
                      'amount': 200,
                      'sharePercent': 25
                    }
                  ]
                }
              }
            };
          }
          return sangongFixtureResponse(call);
        };
      final store = GroupFeatureStore(
          api: api,
          accountPrivilege: FixtureAccountPrivilege(),
          sessionCurrent: () => true,
          fetchGroups: (_) async => []);
      final group = GroupInfo.fromJson({
        'groupID': 'g',
        'groupName': '测试群聊',
        'ex': jsonEncode({
          'groupFeatures': {
            'schemaVersion': 1,
            'revision': 1,
            'games': {
              'sangong': {'enabled': true, 'manageEntry': true}
            }
          }
        })
      });
      final fixture = ProfilePanelFixture(
          user: UserFullInfo(
              userID: 'target',
              nickname: '秋啊',
              account: '3pwvy2b0jg',
              isFriendship: true));
      final moments = profileMomentsRepository(peerUserId: 'target');
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        store.dispose();
        moments.dispose();
      });
      final capture = GlobalKey();
      await mountProfilePanel(tester,
          fixture: fixture,
          moments: moments,
          dark: dark,
          fontFamily: export ? 'SangongProfileCjk' : null,
          previewKey: capture,
          groupFeatureStore: store,
          loadGameGroups: () async => [group]);
      expect(find.text('三公服务'), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.textContaining('当前积分 420'), findsOneWidget);
      expect(find.text('庄2门 限额2000'), findsOneWidget);
      expect(find.text('合庄占股 25.00%'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(3));
      expect(find.byType(SangongProfileLedgerFloatingEntry), findsOneWidget);
      final panelRect = tester
          .getRect(find.byKey(const ValueKey('sangong-profile-services')));
      final voiceRect =
          tester.getRect(find.byKey(const ValueKey('user_profile_voice')));
      expect(panelRect.bottom, lessThanOrEqualTo(voiceRect.top));
      expect(tester.takeException(), isNull);
      if (export) {
        await tester.runAsync(() async {
          final boundary = capture.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          try {
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            await File('.temp/profile-99chat-${dark ? 'dark' : 'light'}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
        debugDisableShadows = previousShadows;
      }
    });
  }
}
