import 'package:openim/pages/contacts/group_requests/data/group_notices_api.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/contacts/friend_requests/friend_requests_logic.dart';
import 'package:openim/pages/contacts/friend_requests/friend_requests_view.dart';
import 'package:openim/pages/contacts/group_requests/group_requests_logic.dart';
import 'package:openim/pages/contacts/group_requests/group_requests_view.dart';
import 'package:openim/pages/contacts/request_history/widgets/request_history_status.dart';
import 'package:openim/pages/home/home_logic.dart';
import 'package:openim_common/openim_common.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _IM extends GetxController implements IMController {
  @override
  final imSdkStatusPublishSubject =
      PublishSubject<({IMSdkStatus status, bool reInstall, int? progress})>();
  @override
  final groupApplicationChangedSubject = PublishSubject<GroupApplicationInfo>();
  @override
  final friendApplicationChangedSubject =
      PublishSubject<FriendApplicationInfo>();
  @override
  void onClose() {
    groupApplicationChangedSubject.close();
    imSdkStatusPublishSubject.close();
    friendApplicationChangedSubject.close();
    super.onClose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Home extends GetxController implements HomeLogic {
  @override
  void getUnhandledGroupApplicationCount() {}
  @override
  void getUnhandledFriendApplicationCount() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const sdk = MethodChannel('flutter_openim_sdk');
  final export = Platform.environment['EXPORT_REQUEST_HISTORY_PREVIEW'] == '1';
  setUp(() async {
    Get.reset();
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'me',
      'imToken': 'test-im',
      'chatToken': 'test-chat',
    }));
    OpenIM.iMManager.userID = 'me';
    Get.put<IMController>(_IM());
    Get.put<HomeLogic>(_Home());
    final time = DateTime.now().millisecondsSinceEpoch;
    Get.create<GroupNoticesApi>(
        () => GroupNoticesApi(request: (path, body) async {
              if (!path.endsWith('/list')) return <String, dynamic>{};
              final raw = await sdk
                  .invokeMethod<String>('getGroupApplicationListAsRecipient');
              final rows = (jsonDecode(raw!) as List)
                  .map((r) => <String, dynamic>{
                        ...Map<String, dynamic>.from(r as Map),
                        'handlerNickname': '京东财务_小群对接上下分',
                      })
                  .toList();
              return {
                'items': rows,
                'snapshotTime': time,
                'revision': 0,
                'nextCursor': ''
              };
            }),
        permanent: false);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, (call) async {
      switch (call.method) {
        case 'getGroupApplicationListAsRecipient':
          return jsonEncode([
            for (var i = 0; i < 3; i++)
              {
                'groupID': 'group-$i',
                'groupName': '京东群聊 · 群通知示例',
                'groupFaceURL': 'group-avatar-$i',
                'userFaceURL': 'applicant-avatar-$i',
                'userID': 'peer-$i',
                'nickname': ['专业户000', '789🌹🌷', '莱福'][i],
                'reqTime': time - i * 3600000,
                'handleResult': [0, 1, -1][i],
                'handleUserID': i == 0 ? '' : 'admin',
              }
          ]);
        case 'getFriendApplicationListAsRecipient':
          return jsonEncode([
            for (var i = 0; i < 3; i++)
              {
                'fromUserID': 'peer-$i',
                'toUserID': 'me',
                'fromNickname': ['煞笔', '云糯糯认蓝贝贝', '矿泉水认兔兔'][i],
                'fromFaceURL': 'user-avatar-$i',
                'reqMsg': '[99chat_src:AddSource_Type_Group] 我是：好友申请人',
                'handleResult': [0, 1, -1][i],
                'createTime': time - i * 3600000,
              }
          ]);
        case 'getFriendApplicationListAsApplicant':
          return jsonEncode([
            {
              'fromUserID': 'me',
              'toUserID': 'sent',
              'toNickname': '蓝贝贝',
              'toFaceURL': 'sent-avatar',
              'handleResult': 0,
              'createTime': time,
              'reqMsg': '你好，一起交流吧'
            }
          ]);
        case 'getUsersInfo':
          return jsonEncode([
            {'userID': 'admin', 'nickname': '京东财务_小群对接上下分'}
          ]);
        case 'getGroupApplicationListAsApplicant':
        case 'getJoinedGroupList':
        case 'getGroupMembersInfo':
          return '[]';
        default:
          throw StateError('Unexpected API: ${call.method}');
      }
    });
  });
  tearDown(() async {
    await EasyLoading.dismiss(animation: false);
    Get.reset();
    Styles.isDark = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, null);
    await DataSp.removeLoginCertificate();
  });

  for (final group in [true, false]) {
    for (final dark in [false, true]) {
      for (final compact in [false, true]) {
        testWidgets(
            '${group ? 'group' : 'friends'} actual page theme=$dark compact=$compact',
            (tester) async {
          Styles.isDark = dark;
          tester.view.physicalSize = Size(compact ? 320 : 375, 812);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          if (export) {
            await tester.runAsync(() async {
              final bytes = ByteData.sublistView(
                  await File('C:/Windows/Fonts/msyh.ttc').readAsBytes());
              await (FontLoader('RequestPreview')..addFont(Future.value(bytes)))
                  .load();
              await (FontLoader('MaterialIcons')
                    ..addFont(
                        rootBundle.load('fonts/MaterialIcons-Regular.otf')))
                  .load();
              await (FontLoader(
                      'packages/font_awesome_flutter/FontAwesomeSolid')
                    ..addFont(rootBundle.load(
                        'packages/font_awesome_flutter/lib/fonts/fa-solid-900.ttf')))
                  .load();
            });
          }
          if (group) {
            Get.put(GroupRequestsLogic(syncInterval: Duration.zero));
          } else {
            Get.put(FriendRequestsLogic());
          }
          final key = GlobalKey();
          await tester.pumpWidget(ScreenUtilInit(
            designSize: const Size(375, 812),
            builder: (_, __) => GetMaterialApp(
              locale: const Locale('zh', 'CN'),
              translations: TranslationService(),
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              supportedLocales: const [Locale('zh', 'CN')],
              theme: ThemeData(
                  brightness: dark ? Brightness.dark : Brightness.light,
                  fontFamily: export ? 'RequestPreview' : null),
              builder: EasyLoading.init(
                  builder: (context, child) => MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                            textScaler: TextScaler.linear(compact ? 2 : 1)),
                        child: child!,
                      )),
              home: RepaintBoundary(
                  key: key,
                  child: group ? GroupRequestsPage() : FriendRequestsPage()),
            ),
          ));
          await tester.pumpAndSettle();
          expect(find.text(group ? '审核' : '验证'), findsOneWidget);
          expect(find.byType(RequestHistoryStatus), findsWidgets);
          expect(find.textContaining('[99chat_src:'), findsNothing);
          final avatars =
              tester.widgetList<AvatarView>(find.byType(AvatarView)).toList();
          expect(avatars.first.url, group ? 'group-avatar-0' : 'user-avatar-0');
          expect(avatars.first.isGroup, group);
          if (!group) {
            expect(find.text('对方添加我'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
          if (export && !compact) {
            await tester.runAsync(() async {
              final boundary = key.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
              final image = await boundary.toImage(pixelRatio: 2);
              final png =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              final path = File(
                  'artifacts/request-history-${group ? 'groups' : 'friends'}-${dark ? 'dark' : 'light'}.png');
              await path.writeAsBytes(png!.buffer.asUint8List());
              image.dispose();
            });
          }
        });
      }
    }
  }
}
