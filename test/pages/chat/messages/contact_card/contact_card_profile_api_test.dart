import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/utils/http_util.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const _target = 'im_contact-card-target';

class _ControlledProfileAdapter implements HttpClientAdapter {
  final started = Completer<RequestOptions>();
  final response = Completer<ResponseBody>();

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    started.complete(options);
    return response.future;
  }

  void authError(int code) {
    response.complete(ResponseBody.fromString(
      jsonEncode({
        'errCode': code,
        'errMsg': 'Authentication failed',
        'errDlt': '',
        'data': null,
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    ));
  }

  @override
  void close({bool force = false}) {
    if (!response.isCompleted) {
      response.complete(ResponseBody.fromString(
        jsonEncode({
          'errCode': 0,
          'errMsg': '',
          'errDlt': '',
          'data': {'users': []},
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      ));
    }
  }
}

Future<void> _login(String owner, String token) async {
  await DataSp.putLoginCertificate(LoginCertificate.fromJson({
    'userID': owner,
    'chatToken': token,
    'imToken': 'im-$token',
  }));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Dio previousDio;
  late _ControlledProfileAdapter adapter;
  late List<int> kickoffs;
  late StreamSubscription<int> kickoffSubscription;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await _login('owner-A', 'token-A');
    previousDio = http.dio;
    http.dio = Dio();
    // Exercise both production auth paths, including the response interceptor.
    HttpUtil.init();
    adapter = _ControlledProfileAdapter();
    http.dio.httpClientAdapter = adapter;
    kickoffs = [];
    kickoffSubscription =
        Apis.kickoffController.stream.cast<int>().listen(kickoffs.add);
  });

  tearDown(() async {
    http.dio.close(force: true);
    await kickoffSubscription.cancel();
    http.dio = previousDio;
    await DataSp.removeLoginCertificate();
    Get.reset();
  });

  Future<RequestOptions> expectTargetRequest() async {
    final request = await adapter.started.future;
    expect(request.uri.toString(), Urls.getUsersFullInfo);
    expect((request.data as Map)['userIDs'], [_target]);
    expect(request.headers['token'], 'token-A');
    return request;
  }

  for (final code in [1501, 1506, 20101]) {
    for (final invalidation in ['account', 'token']) {
      testWidgets(
          'late $code after $invalidation change cannot kick the new session',
          (tester) async {
        await tester.pumpWidget(GetMaterialApp(home: const SizedBox.shrink()));
        await tester.runAsync(() async {
          final lookup = Apis.getUserFullInfo(
              userIDList: [_target], showErrorToast: false);
          await expectTargetRequest();
          await _login(
              invalidation == 'account' ? 'owner-B' : 'owner-A', 'token-B');
          expect(DataSp.chatToken, 'token-B');

          adapter.authError(code);
          expect(await lookup, isNull);
          await Future<void>.delayed(Duration.zero);

          expect(kickoffs, isEmpty);
        });
      });
    }

    testWidgets('current-session $code emits exactly one kickoff',
        (tester) async {
      await tester.pumpWidget(GetMaterialApp(home: const SizedBox.shrink()));
      await tester.runAsync(() async {
        final lookup =
            Apis.getUserFullInfo(userIDList: [_target], showErrorToast: false);
        await expectTargetRequest();
        adapter.authError(code);

        expect(await lookup, isNull);
        await Future<void>.delayed(Duration.zero);

        expect(kickoffs, [code]);
      });
    });
  }
}
