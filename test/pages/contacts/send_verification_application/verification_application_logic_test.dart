import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:openim/pages/contacts/group_profile_panel/group_profile_panel_logic.dart';
import 'package:openim/pages/contacts/send_verification_application/send_verification_application_logic.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/utils/http_util.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _openVerification(
  WidgetTester tester,
  SendVerificationApplicationLogic logic,
  Map<String, dynamic> arguments, {
  Locale locale = const Locale('zh', 'CN'),
}) async {
  await tester.pumpWidget(GetMaterialApp(
    locale: locale,
    translations: TranslationService(),
    builder: EasyLoading.init(),
    home: const Scaffold(body: Text('origin')),
    getPages: [
      GetPage(
        name: '/verification',
        binding: BindingsBuilder(() {
          Get.put<SendVerificationApplicationLogic>(logic);
        }),
        page: () => Scaffold(
          body: Column(children: [
            const Text('verification'),
            TextField(controller: logic.inputCtrl),
          ]),
        ),
      ),
      GetPage(
        name: '/another',
        page: () => const Scaffold(body: Text('another page')),
      ),
    ],
  ));
  Get.toNamed<void>('/verification', arguments: arguments);
  await tester.pumpAndSettle();
  addTearDown(() async {
    await LoadingView.singleton.dismiss();
    await EasyLoading.dismiss(animation: false);
    await tester.pumpWidget(const SizedBox());
    Get.reset();
  });
}

Future<void> _advanceRequest(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 2));
  await tester.pump();
  await tester.pump();
}

Future<void> _finishRequest(
  WidgetTester tester,
  Completer<void> gate,
  Future<void> pending,
) async {
  await tester.runAsync(() async {
    gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 30));
  });
  await tester.pumpAndSettle();
  await pending;
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sdkChannel = MethodChannel('flutter_openim_sdk');
  late Dio previousClient;
  late Dio client;
  late Completer<void> applyGate;
  late Completer<void> groupGate;
  final requests = <RequestOptions>[];
  final groupRequests = <MethodCall>[];
  var reject = false;
  var rejectCode = 20020;
  var rejectReason = 'too frequent';
  var rejectAt = 'friend-grants';
  var rejectHttp = false;

  setUp(() async {
    Get.reset();
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'applicant-private-id',
      'chatToken': 'test-chat-token',
      'imToken': 'test-im-token',
    }));
    requests.clear();
    groupRequests.clear();
    applyGate = Completer<void>();
    groupGate = Completer<void>();
    reject = false;
    rejectCode = 20020;
    rejectReason = 'too frequent';
    rejectAt = 'friend-grants';
    rejectHttp = false;
    previousClient = http.dio;
    client = Dio();
    client.interceptors.add(InterceptorsWrapper(
      onRequest: (request, handler) async {
        requests.add(request);
        if (request.path.endsWith('friend-apply')) await applyGate.future;
        final rejected = reject && request.path.endsWith(rejectAt);
        final response = Response(
          requestOptions: request,
          statusCode: rejected && rejectHttp ? 429 : 200,
          data: rejected
              ? {
                  'errCode': rejectCode,
                  'errMsg': 'FriendGrantRejected',
                  'errDlt': rejectReason,
                }
              : {
                  'errCode': 0,
                  'data': request.path.endsWith('friend-grants')
                      ? {'friendGrant': 'fg_test'}
                      : {},
                },
        );
        if (rejected && rejectHttp) {
          handler.reject(DioException(
              requestOptions: request,
              response: response,
              type: DioExceptionType.badResponse));
        } else {
          handler.resolve(response);
        }
      },
    ));
    http.dio = client;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdkChannel, (call) async {
      if (call.method != 'joinGroup') {
        throw StateError('Unexpected native method: ${call.method}');
      }
      groupRequests.add(call);
      await groupGate.future;
      return null;
    });
  });

  tearDown(() {
    http.dio = previousClient;
    client.close(force: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdkChannel, null);
  });

  testWidgets(
      'route metadata uses real names and never substitutes private IDs',
      (tester) async {
    final logic = SendVerificationApplicationLogic();
    await _openVerification(tester, logic, {
      'userID': 'target-private-id',
      'targetName': '秋',
      'targetAvatarURL': 'https://example.test/avatar.png',
      'targetAccount': '@public-account',
      'selfNickname': '  冬  ',
    });
    expect(logic.targetName, '秋');
    expect(logic.targetAvatarURL, 'https://example.test/avatar.png');
    expect(logic.targetAccount, '@public-account');
    expect(logic.inputCtrl.text, '我是：冬');
    expect(logic.inputCtrl.text, isNot(contains('private-id')));
    expect(requests, isEmpty);
    expect(groupRequests, isEmpty);
  });

  testWidgets('greeting caps complete emoji characters at the message limit',
      (tester) async {
    final logic = SendVerificationApplicationLogic();
    const emoji = '👨‍👩‍👧‍👦';
    await _openVerification(tester, logic, {
      'userID': 'target-private-id',
      'selfNickname': List.filled(30, emoji).join(),
    });
    expect(logic.inputCtrl.text.characters.length, 20);
    expect(logic.inputCtrl.text, '我是：${List.filled(17, emoji).join()}');
    expect(logic.targetName, isEmpty);
    expect(logic.targetAccount, isEmpty);
    expect(logic.targetAvatarURL, isNull);
  });

  testWidgets('English greeting uses the current locale', (tester) async {
    final logic = SendVerificationApplicationLogic();
    await _openVerification(
      tester,
      logic,
      {'userID': 'target-private-id', 'selfNickname': '  Alice  '},
      locale: const Locale('en', 'US'),
    );
    expect(logic.inputCtrl.text, 'Hi, I’m Alice');
  });

  for (final source in [FriendAddSource.chat, FriendAddSource.card]) {
    testWidgets('${source.name} without entry details never starts submission',
        (tester) async {
      final logic = SendVerificationApplicationLogic();
      await _openVerification(tester, logic, {
        'userID': 'target-private-id',
        'targetName': '测试好友',
        'targetAccount': '@visible-account',
        'addSource': source,
        if (source == FriendAddSource.card)
          'friendAddFields': {'inviteCode': '  '},
      });
      logic.inputCtrl.text = '保留我的申请';
      expect(logic.canSubmit, isFalse);
      expect(logic.unavailableMessage, contains('聊天号'));
      expect(logic.targetAccount, '@visible-account');
      await logic.send();
      await _advanceRequest(tester);
      expect(logic.sending.value, isFalse);
      expect(find.byType(SpinKitCircle), findsNothing);
      expect(logic.inputCtrl.text, '保留我的申请');
      expect(requests, isEmpty);
      expect(groupRequests, isEmpty);
      expect(find.text('verification'), findsOneWidget);
      expect(find.textContaining('凭证'), findsNothing);
      expect(find.textContaining('FriendGrantRequired'), findsNothing);
    });
  }

  testWidgets('QR invitation allows submission using the original invite',
      (tester) async {
    final logic = SendVerificationApplicationLogic();
    await _openVerification(tester, logic, {
      'userID': 'target-private-id',
      'addSource': FriendAddSource.qrcode,
      'friendAddFields': {'inviteCode': ' fi_qr_entry '},
    });
    expect(logic.canSubmit, isTrue);
    expect(logic.unavailableMessage, isNull);
    final pending = logic.send();
    await _advanceRequest(tester);
    expect(requests[0].data, {'source': 'qrcode', 'inviteCode': 'fi_qr_entry'});
    expect(requests[1].data, {'friendGrant': 'fg_test', 'message': ''});
    await _finishRequest(tester, applyGate, pending);
    expect(find.text('origin'), findsOneWidget);
  });

  testWidgets('group grant preserves source and target and deduplicates send',
      (tester) async {
    final logic = SendVerificationApplicationLogic();
    await _openVerification(tester, logic, {
      'userID': 'target-private-id',
      'friendGroupID': 'group-source',
      'addSource': FriendAddSource.group,
      'friendAddFields': {'groupID': 'forged', 'nickname': 'forged'},
    });
    logic.inputCtrl.text = '  申请理由  ';
    final pending = logic.send();
    logic.inputCtrl.text = '发送后修改的草稿';
    final duplicate = logic.send();
    expect(logic.sending.value, isTrue);
    await _advanceRequest(tester);
    expect(requests, hasLength(2));
    expect(requests[0].path, endsWith('/chat/friend-grants'));
    expect(requests[0].headers['token'], 'test-chat-token');
    expect(requests[0].data, {
      'source': 'group',
      'groupID': 'group-source',
      'targetUserID': 'target-private-id',
    });
    expect(requests[1].path, endsWith('/chat/friend-apply'));
    expect(requests[1].data, {'friendGrant': 'fg_test', 'message': '申请理由'});
    await duplicate;
    expect(logic.sending.value, isTrue);
    await _finishRequest(tester, applyGate, pending);
    expect(find.text('verification'), findsNothing);
    expect(find.text('origin'), findsOneWidget);
    expect(requests, hasLength(2));
  });

  testWidgets('card invite fields still exchange a grant only on submission',
      (tester) async {
    final logic = SendVerificationApplicationLogic();
    await _openVerification(tester, logic, {
      'userID': 'target-private-id',
      'addSource': FriendAddSource.card,
      'friendAddFields': {
        'inviteCode': ' fi_real_entry ',
        'userID': 'forged',
        'account': '@forged',
      },
    });
    expect(requests, isEmpty);
    final pending = logic.send();
    await _advanceRequest(tester);
    expect(requests[0].data, {'source': 'card', 'inviteCode': 'fi_real_entry'});
    expect(requests[1].data, {'friendGrant': 'fg_test', 'message': ''});
    await _finishRequest(tester, applyGate, pending);
    expect(find.text('origin'), findsOneWidget);
  });

  testWidgets(
      'legacy limit quietly restores busy state and preserves the draft',
      (tester) async {
    reject = true;
    final logic = SendVerificationApplicationLogic();
    await _openVerification(tester, logic, {
      'userID': 'target-private-id',
      'addSource': FriendAddSource.account,
      'friendAddFields': {'account': '@real-account'},
    });
    logic.inputCtrl.text = '  保留我的申请  ';
    final pending = logic.send();
    await _advanceRequest(tester);
    await pending;
    await tester.pumpAndSettle();
    expect(logic.sending.value, isFalse);
    expect(logic.inputCtrl.text, '  保留我的申请  ');
    expect(requests, hasLength(1));
    expect(find.text('verification'), findsOneWidget);
    expect(EasyLoading.isShow, isFalse);
    expect(find.text(StrRes.sendSuccessfully), findsNothing);
    reject = false;
    final retry = logic.send();
    await _advanceRequest(tester);
    expect(requests, hasLength(3));
    expect(requests.last.data['message'], '保留我的申请');
    await _finishRequest(tester, applyGate, retry);
    expect(find.text('origin'), findsOneWidget);
  });

  for (final endpoint in ['friend-grants', 'friend-apply']) {
    testWidgets('risk block at $endpoint ends loading without toast or success',
        (tester) async {
      reject = true;
      rejectCode = 20201;
      rejectReason = '操作过于频繁，请稍后再试';
      rejectAt = endpoint;
      rejectHttp = true;
      final logic = SendVerificationApplicationLogic();
      await _openVerification(tester, logic, {
        'userID': 'target-private-id',
        'addSource': FriendAddSource.account,
        'friendAddFields': {'account': '@real-account'},
      });
      logic.inputCtrl.text = '保留我的申请';
      final pending = logic.send();
      await _advanceRequest(tester);
      await tester.runAsync(() async {
        applyGate.complete();
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await pending;
      await tester.pumpAndSettle();
      expect(logic.sending.value, isFalse);
      expect(logic.inputCtrl.text, '保留我的申请');
      expect(find.text('verification'), findsOneWidget);
      expect(find.byType(SpinKitCircle), findsNothing);
      expect(EasyLoading.isShow, isFalse);
      expect(find.text(StrRes.sendSuccessfully), findsNothing);
      expect(requests, hasLength(endpoint == 'friend-grants' ? 1 : 2));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('expired invitation still explains how to recover',
      (tester) async {
    reject = true;
    rejectReason = 'invite invalid';
    final logic = SendVerificationApplicationLogic();
    await _openVerification(tester, logic, {
      'userID': 'target-private-id',
      'addSource': FriendAddSource.account,
      'friendAddFields': {'account': '@real-account'},
    });
    final pending = logic.send();
    await _advanceRequest(tester);
    await pending;
    await tester.pumpAndSettle();
    expect(find.text('邀请已失效，请获取新的邀请'), findsOneWidget);
    expect(logic.sending.value, isFalse);
    expect(find.text('verification'), findsOneWidget);
    await EasyLoading.dismiss(animation: false);
    await tester.pumpAndSettle();
  });

  testWidgets('late application completion cannot pop a newer page',
      (tester) async {
    final logic = SendVerificationApplicationLogic();
    await _openVerification(tester, logic, {
      'userID': 'target-private-id',
      'addSource': FriendAddSource.account,
      'friendAddFields': {'account': '@real-account'},
    });
    final pending = logic.send();
    await _advanceRequest(tester);
    Get.back<void>();
    await Get.delete<SendVerificationApplicationLogic>();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(logic.isClosed, isTrue);
    Get.toNamed<void>('/another');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _finishRequest(tester, applyGate, pending);
    expect(find.text('another page'), findsOneWidget);
    expect(find.text('发送成功'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final method in [JoinGroupMethod.qrcode, JoinGroupMethod.search]) {
    testWidgets(
        'group join keeps ${method.name} source and rejects repeat taps',
        (tester) async {
      final logic = SendVerificationApplicationLogic();
      await _openVerification(tester, logic, {
        'groupID': 'real-group',
        'joinGroupMethod': method,
        'selfNickname': '不得生成好友问候',
      });
      expect(logic.inputCtrl.text, isEmpty);
      expect(logic.canSubmit, isTrue);
      expect(logic.unavailableMessage, isNull);
      logic.inputCtrl.text = '  入群理由  ';
      final pending = logic.send();
      final duplicate = logic.send();
      await _advanceRequest(tester);
      expect(groupRequests, hasLength(1));
      expect(requests, isEmpty);
      final arguments = groupRequests.single.arguments as Map;
      expect(arguments['groupID'], 'real-group');
      expect(arguments['reason'], '入群理由');
      expect(arguments['joinSource'], method == JoinGroupMethod.qrcode ? 4 : 3);
      expect(logic.sending.value, isTrue);
      await duplicate;
      await _finishRequest(tester, groupGate, pending);
      expect(find.text('origin'), findsOneWidget);
    });
  }
}
