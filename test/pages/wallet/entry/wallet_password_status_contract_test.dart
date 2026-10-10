import 'package:dio/dio.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/pages/mine/settings/openim_profile_service.dart';
import 'package:openim/pages/mine/settings/pages/trade_password_page.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/wallet_entry_fixture.dart';

class _Account extends GetxController implements IMController {
  @override
  final userInfo = UserFullInfo(userID: 'viewer').obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Dio original;
  late OpenIMProfileService service;
  late Map<String, dynamic> response;
  late List<RequestOptions> requests;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    OpenIM.iMManager.userID = 'viewer';
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'viewer',
      'imToken': 'im-token',
      'chatToken': 'chat-token',
    }));
    original = dio;
    dio = Dio();
    requests = [];
    response = {'errCode': 0, 'data': <String, dynamic>{}};
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests.add(options);
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: response,
      ));
    }));
    service = OpenIMProfileService(_Account());
  });

  tearDown(() {
    dio = original;
    Get.reset();
  });

  for (final ready in [false, true]) {
    test('payment status reads exact bool $ready with authenticated GET',
        () async {
      response['data'] = {'set': ready};
      expect(await service.hasTradePassword(), ready);
      final request = requests.single;
      expect(request.path, '${Config.appAuthUrl}/chat/fund/pay-password');
      expect(request.method, 'GET');
      expect(request.headers['token'], 'chat-token');
      expect(request.headers['operationID'], isA<String>());
      expect(request.headers['operationID'], isNotEmpty);
    });
  }

  test('server omits the default false field and returns an empty object',
      () async {
    response['data'] = <String, dynamic>{};
    expect(await service.hasTradePassword(), isFalse);
  });

  testWidgets('omitted false reaches password setup instead of a failed gate',
      (tester) async {
    response['data'] = <String, dynamic>{};
    final settings = WalletEntrySettings()
      ..check = (_) => service.hasTradePassword();
    final fixture = WalletEntryFixture(settings);
    await fixture.mount(tester);
    final pending = fixture.enter();
    await tester.pumpAndSettle();
    expect(find.byType(TradePasswordPage), findsOneWidget);
    expect(fixture.allowed, isEmpty);
    expect(requests.single.method, 'GET');
    fixture.rootNavigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(await pending, isFalse);
  });

  final malformed = <String, dynamic>{
    'unknown fields without set': {'ready': true},
    'null data': null,
    'list data': <dynamic>[],
    'string data': '{}',
    'string set': {'set': 'true'},
    'integer set': {'set': 1},
    'null set': {'set': null},
  };
  for (final entry in malformed.entries) {
    test('${entry.key} is rejected as an invalid payment status', () async {
      response['data'] = entry.value;
      await expectLater(service.hasTradePassword(), throwsFormatException);
    });
  }

  test('HTTP 200 business error is propagated before reading password status',
      () async {
    response = {
      'errCode': 20037,
      'errMsg': 'FundPayPasswordNotSet',
      'errDlt': 'status unavailable',
      'data': {'set': true},
    };
    await expectLater(
      service.hasTradePassword(),
      throwsA((20037, 'status unavailable')),
    );
    expect(requests, hasLength(1));
  });

  test('business failure with empty data never becomes an unset password',
      () async {
    response = {'errCode': 20037, 'errMsg': 'unavailable', 'data': {}};
    await expectLater(
        service.hasTradePassword(), throwsA((20037, 'unavailable')));
  });
}
