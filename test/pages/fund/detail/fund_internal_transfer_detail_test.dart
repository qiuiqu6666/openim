import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/fund/fund_detail_page.dart';
import 'package:openim/services/fund_api.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
  });

  for (final brightness in Brightness.values) {
    for (final viewer in ['sender', 'receiver']) {
      testWidgets('internal IM transfer card opens for $viewer in $brightness',
          (tester) async {
        final requests = <RequestOptions>[];
        final client = Dio();
        addTearDown(() => client.close(force: true));
        client.interceptors
            .add(InterceptorsWrapper(onRequest: (request, handler) {
          requests.add(request);
          handler.resolve(Response(
            requestOptions: request,
            statusCode: 200,
            data: {
              'errCode': 0,
              'data': {
                'order': {
                  'orderID': 'internal-order',
                  'clientOrderID': 'internal-client',
                  'biz': 'transfer',
                  'scene': 'internal',
                  'currency': 'USDT',
                  'amount': '12.5',
                  'status': 'done',
                  'senderID': 'sender',
                  'recvID': 'receiver',
                  'groupID': '',
                  'remark': '内部转账',
                  'recipientType': 'account',
                  'recipient': '@abcdefgh12',
                  'recipientAreaCode': '',
                  'fee': '0',
                }
              }
            },
          ));
        }));
        await tester.pumpWidget(MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData(brightness: brightness),
          home: FundDetailPage(
            message: FundMessageData(
              orderID: 'internal-order',
              biz: 'transfer',
              currency: 'USDT',
              amount: '12.5',
              status: 'done',
            ),
            api: FundApi(
                client: client,
                baseUrl: 'https://chat.example.test',
                tokenProvider: () => 'chat-token'),
            currentUserID: viewer,
            profileResolver: (_, __) async => const {},
          ),
        ));
        await tester.pumpAndSettle();
        expect(
            find.byKey(const ValueKey('fund-detail-load-error')), findsNothing);
        expect(find.byKey(const ValueKey('fund-transfer-success')),
            findsOneWidget);
        expect(find.text('已接收'), findsOneWidget);
        expect(find.text('12.50'), findsOneWidget);
        expect(find.text('内部转账'), findsOneWidget);
        expect(find.byKey(const ValueKey('fund-detail-open')), findsNothing);
        expect(find.byKey(const ValueKey('fund-payment-sheet')), findsNothing);
        expect(requests, hasLength(1));
        expect(requests.single.method, 'GET');
        expect(requests.single.uri.path, '/chat/fund/orders/internal-order');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
