import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:openim/pages/fund/fund_detail_page.dart';
import 'package:openim/pages/fund/widgets/fund_packet_detail.dart';
import 'package:openim/services/fund_api.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _orderFixture(String name) =>
    jsonDecode(File('test/fixtures/fund/$name').readAsStringSync())
        as Map<String, dynamic>;

/// Real Dio JSON decoding and FundApi parsing, with no network or live writes.
class _FundFixtureTransport implements HttpClientAdapter {
  _FundFixtureTransport(this.orderResponse) {
    client.httpClientAdapter = this;
    api = FundApi(
        client: client,
        baseUrl: 'https://fund.example.test',
        tokenProvider: () => 'fixture-chat-token');
    addTearDown(() => client.close(force: true));
  }

  final Dio client = Dio();
  late final FundApi api;
  final Map<String, dynamic> orderResponse;
  final List<RequestOptions> requests = [];
  Map<String, dynamic> Function()? onClaim;

  Iterable<RequestOptions> get claims => requests.where(
      (request) => request.method == 'POST' && request.path.endsWith('/claim'));

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final Map<String, dynamic> response;
    if (options.path.endsWith('/balances')) {
      response = {
        'errCode': 0,
        'data': {
          'balances': [
            for (final currency in FundCurrency.values)
              {'currency': currency.code, 'available': '100', 'frozen': '0'}
          ]
        }
      };
    } else if (options.method == 'POST') {
      if (!options.path.endsWith('/claim') || onClaim == null) {
        throw StateError('Unexpected financial fixture request');
      }
      response = onClaim!();
    } else {
      response = orderResponse;
    }
    return ResponseBody.fromString(jsonEncode(response), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

class _FakeFundApi extends FundApi {
  _FakeFundApi({required this.load, this.claim});

  Future<FundOrder> Function(String orderID) load;
  Future<FundClaimResult> Function(String orderID)? claim;
  final List<String> reads = [];
  final List<String> claims = [];
  int balanceReads = 0;

  @override
  Future<FundOrder> getOrder(String orderID) {
    reads.add(orderID);
    return load(orderID);
  }

  @override
  Future<FundClaimResult> claimPacket(String orderID) {
    claims.add(orderID);
    return claim?.call(orderID) ??
        Future.value(FundClaimResult(amount: '2.5', orderID: orderID));
  }

  @override
  Future<List<FundBalance>> fetchBalances() async {
    balanceReads++;
    return const [];
  }
}

FundOrder _order({
  String id = 'packet-1',
  String biz = 'packet_lucky',
  FundScene scene = FundScene.group,
  FundCurrency currency = FundCurrency.usdt,
  String status = 'open',
  String sender = 'sender',
  String receiver = '',
  String amount = '10',
  String remark = '',
  List<FundShare> shares = const [],
  int shareCount = 4,
  DateTime? expires,
  DateTime? createdAt,
}) =>
    FundOrder(
      orderID: id,
      biz: biz,
      scene: scene,
      currency: currency,
      amount: FundAmount.parse(amount, currency),
      senderID: sender,
      recvID: receiver,
      remark: remark,
      groupID: scene == FundScene.group ? 'group-1' : '',
      status: status,
      shareCount: shareCount,
      shares: shares,
      expireAt: expires,
      createdAt: createdAt,
    );

FundShare _ownShare({String user = 'me'}) => FundShare(
      index: 0,
      amount: FundAmount.parse('2.5', FundCurrency.usdt),
      claimerID: user,
      claimedAt: DateTime.utc(2026, 10, 2, 12),
    );

FundMessageData _message({
  String id = 'packet-1',
  String biz = 'packet_lucky',
  String currency = 'USDT',
  String amount = '10',
  String remark = '',
}) =>
    FundMessageData(
      orderID: id,
      biz: biz,
      currency: currency,
      amount: amount,
      remark: remark,
      // An arbitrary bubble status must never authorize a claim.
      status: 'open',
    );

Widget _host(
  Widget child, {
  Brightness brightness = Brightness.light,
  double textScale = 1,
  bool disableAnimations = false,
  GlobalKey<NavigatorState>? navigatorKey,
}) =>
    MaterialApp(
      navigatorKey: navigatorKey,
      theme: ThemeData(brightness: brightness),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: child!,
      ),
      home: child,
    );

Future<void> _openCover(WidgetTester tester) async {
  final open = find.byKey(const ValueKey('fund-detail-open'));
  await tester.ensureVisible(open);
  await tester.tap(open);
  await tester.pump();
}

Future<void> _refreshDetails(WidgetTester tester) async {
  final menu = find.byKey(const ValueKey('fund-detail-menu'));
  if (menu.evaluate().isNotEmpty) {
    await tester.tap(menu);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const ValueKey('fund-detail-refresh')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
  });

  for (final viewer in ['fixture-sender', 'fixture-recipient']) {
    testWidgets('real packet GET without sender opens for $viewer',
        (tester) async {
      final response = _orderFixture('packet-order-without-sender.json');
      final epoch = response['data']['order']['createdAt'] as int;
      final expectedLocalTime = DateFormat('yyyy-MM-dd HH:mm').format(
          DateTime.fromMillisecondsSinceEpoch(epoch, isUtc: true).toLocal());
      final transport = _FundFixtureTransport(response);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(_host(const SizedBox(), navigatorKey: navigator));
      final route = FundDetailRoute(
          message: _message(
              id: 'packet-fixture-1', biz: 'packet_normal', currency: 'BI99'),
          api: transport.api,
          currentUserID: viewer,
          messageSender: const FundDetailMessageSender(
              userID: 'fixture-sender', nickname: '小林'),
          profileResolver: (_, __) async => {});
      final result = navigator.currentState!.push<FundOrder>(route);
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('fund-detail-load-error')), findsNothing);
      expect(find.text('测试祝福'), findsOneWidget);
      expect(find.text(viewer == 'fixture-sender' ? '我的红包' : '小林的红包'),
          findsOneWidget);
      expect(find.byType(FundPacketDetail), findsOneWidget);
      expect(find.byKey(const ValueKey('fund-detail-packet-header')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('fund-detail-amount')), findsOneWidget);
      expect(find.byKey(const ValueKey('fund-detail-open')), findsNothing);
      expect(transport.claims, isEmpty);
      expect(route.currentResult?.senderID, isEmpty);
      expect(route.currentResult?.shares, isEmpty);
      final recipient =
          find.byKey(const ValueKey('fund-detail-direct-recipient'));
      await tester.ensureVisible(recipient);
      expect(
          find.descendant(
              of: recipient,
              matching: find.byKey(
                  const ValueKey('fund-detail-avatar-fixture-recipient'))),
          findsOneWidget);
      expect(find.descendant(of: recipient, matching: find.text('10.00 99BI')),
          findsOneWidget);
      expect(
          find.descendant(
              of: recipient, matching: find.text(expectedLocalTime)),
          findsOneWidget);
      expect(find.textContaining('发送时间'), findsNothing);
      expect(find.byKey(const ValueKey('fund-detail-share-0')), findsNothing);
      expect(
          find.byKey(const ValueKey('fund-detail-order-info')), findsNothing);
      expect(find.text('红包信息'), findsNothing);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect((await result)?.senderID, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('real group transfer GET without sender opens for an observer',
      (tester) async {
    final transport = _FundFixtureTransport(
        _orderFixture('group-transfer-order-without-sender.json'));
    await tester.pumpWidget(_host(FundDetailPage(
        message: _message(id: 'transfer-fixture-1', biz: 'group_transfer'),
        api: transport.api,
        currentUserID: 'fixture-observer',
        profileResolver: (_, __) async => {})));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fund-detail-load-error')), findsNothing);
    expect(find.byKey(const ValueKey('fund-transfer-success')), findsOneWidget);
    expect(find.text('测试备注'), findsOneWidget);
    expect(find.text('已接收'), findsOneWidget);
    expect(transport.claims, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing sender displays a neutral sender and skips empty lookup',
      (tester) async {
    final transport = _FundFixtureTransport(
        _orderFixture('packet-order-without-sender.json'));
    final queries = <List<String>>[];
    await tester.pumpWidget(_host(FundDetailPage(
        message: _message(
            id: 'packet-fixture-1', biz: 'packet_normal', currency: 'BI99'),
        api: transport.api,
        currentUserID: 'fixture-recipient',
        profileResolver: (_, ids) async {
          queries.add(ids);
          return {};
        })));
    await tester.pumpAndSettle();
    expect(find.text('发送人的红包'), findsOneWidget);
    expect(find.text('我的红包'), findsNothing);
    expect(queries.expand((ids) => ids), ['fixture-recipient']);
    final avatar = tester
        .widget<AvatarView>(find.byKey(const ValueKey('fund-detail-avatar-')));
    expect(avatar.url, isNull);
    expect(avatar.text, '发送人');
    expect(transport.claims, isEmpty);
  });

  testWidgets('missing group sender still needs an explicit open before claim',
      (tester) async {
    final response = _orderFixture('packet-order-without-sender.json');
    final data = response['data'] as Map<String, dynamic>;
    final order = data['order'] as Map<String, dynamic>;
    order.addAll({
      'scene': 'group',
      'groupID': 'fixture-group',
      'recvID': '',
      'status': 'open',
      'shareAmount': '5',
      'shareCount': 2,
    });
    data['shares'] = [
      {'index': 0, 'amount': '5', 'claimerID': ''},
      {'index': 1, 'amount': '5', 'claimerID': ''}
    ];
    final transport = _FundFixtureTransport(response);
    transport.onClaim = () {
      (data['shares'] as List).first['claimerID'] = 'fixture-member';
      return {
        'errCode': 0,
        'data': {'orderID': 'packet-fixture-1', 'amount': '5'}
      };
    };
    await tester.pumpWidget(_host(
        FundDetailPage(
            message: _message(
                id: 'packet-fixture-1', biz: 'packet_normal', currency: 'BI99'),
            api: transport.api,
            currentUserID: 'fixture-member',
            messageSender: const FundDetailMessageSender(
                userID: 'fixture-sender', nickname: '小林'),
            profileResolver: (_, __) async => {}),
        disableAnimations: true));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fund-detail-open')), findsOneWidget);
    expect(transport.claims, isEmpty);
    await _openCover(tester);
    await tester.pumpAndSettle();
    expect(transport.claims, hasLength(1));
    expect(transport.claims.single.data, isNull);
    expect(find.text('5.00 99BI'), findsWidgets);
    expect(find.text('小林的红包'), findsOneWidget);
    await _refreshDetails(tester);
    expect(transport.claims, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('verified server sender ignores conflicting message profile',
      (tester) async {
    final response = _orderFixture('packet-order-without-sender.json');
    (response['data']['order'] as Map<String, dynamic>)['senderID'] =
        'verified-sender';
    final transport = _FundFixtureTransport(response);
    final queried = <String>[];
    await tester.pumpWidget(_host(FundDetailPage(
        message: _message(
            id: 'packet-fixture-1', biz: 'packet_normal', currency: 'BI99'),
        api: transport.api,
        currentUserID: 'fixture-recipient',
        messageSender: const FundDetailMessageSender(
            userID: 'wrong-sender',
            nickname: '错误人物',
            faceURL: 'https://example.invalid/wrong.png'),
        profileResolver: (_, ids) async {
          queried.addAll(ids);
          return {
            'verified-sender': const FundPartyProfile(
                name: '真实发送人', faceURL: 'https://example.invalid/verified.png')
          };
        })));
    await tester.pumpAndSettle();
    expect(find.text('真实发送人的红包'), findsOneWidget);
    expect(find.textContaining('错误人物'), findsNothing);
    expect(queried, contains('verified-sender'));
    expect(queried, isNot(contains('wrong-sender')));
    final avatar = tester.widget<AvatarView>(
        find.byKey(const ValueKey('fund-detail-avatar-verified-sender')));
    expect(avatar.url, 'https://example.invalid/verified.png');
    expect(transport.claims, isEmpty);
  });

  testWidgets('message sender cannot authorize an unrelated single order',
      (tester) async {
    final response = _orderFixture('packet-order-without-sender.json');
    (response['data']['order'] as Map<String, dynamic>)['senderID'] =
        'verified-sender';
    final transport = _FundFixtureTransport(response);
    await tester.pumpWidget(_host(FundDetailPage(
        message: _message(
            id: 'packet-fixture-1', biz: 'packet_normal', currency: 'BI99'),
        api: transport.api,
        currentUserID: 'stranger',
        messageSender: const FundDetailMessageSender(
            userID: 'stranger', nickname: '伪造发件人'),
        profileResolver: (_, __) async => {})));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('fund-detail-load-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('fund-detail-amount')), findsNothing);
    expect(transport.claims, isEmpty);
  });

  for (final invalidAmount in [false, true]) {
    testWidgets(
        'missing sender does not bypass ${invalidAmount ? 'amount' : 'ID'} match',
        (tester) async {
      final transport = _FundFixtureTransport(
          _orderFixture('packet-order-without-sender.json'));
      await tester.pumpWidget(_host(FundDetailPage(
          message: _message(
              id: invalidAmount ? 'packet-fixture-1' : 'wrong-order',
              biz: 'packet_normal',
              currency: 'BI99',
              amount: invalidAmount ? '999' : '10'),
          api: transport.api,
          currentUserID: 'fixture-recipient',
          messageSender: const FundDetailMessageSender(
              userID: 'fixture-sender', nickname: '小林'),
          profileResolver: (_, __) async => {})));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('fund-detail-load-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('fund-detail-amount')), findsNothing);
      expect(transport.claims, isEmpty);
    });
  }

  testWidgets(
      'display context update preserves a pending claim and verified order',
      (tester) async {
    final claim = Completer<FundClaimResult>();
    final api = _FakeFundApi(
        load: (_) async => _order(
            sender: '', shares: claim.isCompleted ? [_ownShare()] : const []),
        claim: (_) => claim.future);
    Future<Map<String, FundPartyProfile>> profileResolver(
            FundOrder _, List<String> __) async =>
        <String, FundPartyProfile>{};
    FundDetailPage page(String nickname) => FundDetailPage(
        message: _message(),
        api: api,
        currentUserID: 'me',
        messageSender: FundDetailMessageSender(
            userID: 'display-sender', nickname: nickname),
        profileResolver: profileResolver);
    await tester.pumpWidget(_host(page('旧昵称'), disableAnimations: true));
    await tester.pumpAndSettle();
    await _openCover(tester);
    expect(api.claims, ['packet-1']);
    await tester.pumpWidget(_host(page('新昵称'), disableAnimations: true));
    await tester.pump();
    final open =
        tester.widget<InkWell>(find.byKey(const ValueKey('fund-detail-open')));
    expect(open.onTap, isNull);
    expect(api.reads, ['packet-1']);
    claim.complete(const FundClaimResult(orderID: 'packet-1', amount: '2.5'));
    await tester.pumpAndSettle();
    expect(api.claims, ['packet-1']);
    expect(find.text('新昵称的红包'), findsOneWidget);
    expect(find.textContaining('旧昵称'), findsNothing);
    expect(find.text('2.50 USDT'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'verified packet remark replaces bubble text in cover and details',
      (tester) async {
    final api = _FakeFundApi(load: (_) async => _order(remark: '旅途愉快🚀'));
    await tester.pumpWidget(_host(FundDetailPage(
      message: _message(remark: '卡片祝福'),
      api: api,
      currentUserID: 'me',
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fund-packet-cover')), findsOneWidget);
    expect(find.text('旅途愉快🚀'), findsOneWidget);
    expect(find.text('卡片祝福'), findsNothing);
    expect(find.text('恭喜发财，大吉大利'), findsNothing);
    expect(api.claims, isEmpty);
    await tester.tap(find.byKey(const ValueKey('fund-detail-view-details')));
    await tester.pumpAndSettle();
    expect(find.text('旅途愉快🚀'), findsOneWidget);
    expect(find.text('卡片祝福'), findsNothing);
    expect(api.claims, isEmpty);
    expect(api.balanceReads, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('directly credited packet shows its verified greeting',
      (tester) async {
    final api = _FakeFundApi(
        load: (_) async => _order(
            biz: 'packet_normal',
            scene: FundScene.single,
            receiver: 'me',
            status: 'done',
            remark: '平安喜乐'));
    await tester.pumpWidget(_host(FundDetailPage(
      message: _message(biz: 'packet_normal', remark: '卡片祝福'),
      api: api,
      currentUserID: 'me',
    )));
    await tester.pumpAndSettle();
    expect(find.text('平安喜乐'), findsOneWidget);
    expect(find.text('卡片祝福'), findsNothing);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('fund-detail-amount')))
            .textSpan!
            .toPlainText(),
        '10.00 USDT');
    expect(find.text('已到账，已存入余额'), findsOneWidget);
    expect(api.claims, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('transfer displays verified remark in the reference memo row',
      (tester) async {
    final api = _FakeFundApi(
        load: (_) async => _order(
            biz: 'transfer',
            scene: FundScene.single,
            receiver: 'me',
            status: 'done',
            remark: '晚餐AA🍜'));
    await tester.pumpWidget(_host(FundDetailPage(
      message: _message(biz: 'transfer', remark: '卡片备注'),
      api: api,
      currentUserID: 'me',
    )));
    await tester.pumpAndSettle();
    expect(find.text('转账备注'), findsOneWidget);
    expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey('fund-detail-transfer-remark')))
            .data,
        '晚餐AA🍜');
    expect(find.text('卡片备注'), findsNothing);
    expect(find.text('10.00'), findsOneWidget);
    expect(find.text('已接收'), findsOneWidget);
    expect(find.text('确认收款'), findsNothing);
    expect(api.claims, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('red packet cover and view details never claim without opening',
      (tester) async {
    final api = _FakeFundApi(load: (_) async => _order());
    await tester.pumpWidget(_host(FundDetailPage(
      message: _message(remark: '卡片祝福'),
      api: api,
      currentUserID: 'me',
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fund-packet-cover')), findsOneWidget);
    expect(find.text('開'), findsOneWidget);
    expect(find.text('恭喜发财，大吉大利'), findsOneWidget);
    expect(find.text('卡片祝福'), findsNothing);
    expect(api.claims, isEmpty);
    await tester.tap(find.byKey(const ValueKey('fund-detail-view-details')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fund-packet-cover')), findsNothing);
    expect(find.byKey(const ValueKey('fund-detail-share-progress')),
        findsOneWidget);
    expect(api.claims, isEmpty);
    await tester.tap(find.byKey(const ValueKey('fund-detail-back-cover')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fund-detail-open')), findsOneWidget);
    expect(api.claims, isEmpty);
  });

  testWidgets('verifies the server order and claims only after explicit open',
      (tester) async {
    final read = Completer<FundOrder>();
    final claim = Completer<FundClaimResult>();
    final api = _FakeFundApi(
      load: (_) => read.future,
      claim: (_) => claim.future,
    );
    await tester.pumpWidget(_host(FundDetailPage(
      message: _message(),
      api: api,
      currentUserID: 'me',
    )));
    expect(api.reads, ['packet-1']);
    expect(api.claims, isEmpty);
    read.complete(_order());
    await tester.pump();
    await tester.pump();
    expect(api.claims, isEmpty);
    await _openCover(tester);
    await tester.pump();
    expect(api.claims, ['packet-1']);
    await tester.tap(find.byKey(const ValueKey('fund-detail-open')));
    await tester.pump();
    expect(api.claims, ['packet-1']);
    expect(
        tester
            .widget<InkWell>(find.byKey(const ValueKey('fund-detail-open')))
            .onTap,
        isNull);
    api.load = (_) async => _order(shares: [_ownShare()]);
    claim.complete(const FundClaimResult(orderID: 'packet-1', amount: '2.5'));
    await tester.pumpAndSettle();
    expect(find.text('2.50 USDT'), findsWidgets);
    expect(find.textContaining('红包已领取'), findsWidgets);
    expect(api.balanceReads, 1);
    await _refreshDetails(tester);
    expect(api.claims, ['packet-1']);
    expect(find.textContaining('999'), findsNothing);
  });

  for (final invalid in [
    _order(id: 'different-order'),
    _order(currency: FundCurrency.trx),
    _order(biz: 'packet_normal'),
    _order(scene: FundScene.single, receiver: 'me'),
  ]) {
    testWidgets(
        'rejects mismatched order ${invalid.orderID}/${invalid.biz}/${invalid.currency.code}/${invalid.scene.name}',
        (tester) async {
      final api = _FakeFundApi(load: (_) async => invalid);
      await tester.pumpWidget(_host(FundDetailPage(
        message: _message(),
        api: api,
        currentUserID: 'me',
      )));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('fund-detail-load-error')), findsOneWidget);
      expect(api.claims, isEmpty);
      expect(find.byKey(const ValueKey('fund-detail-amount')), findsNothing);
    });
  }

  for (final direct in [
    _order(
        biz: 'transfer',
        scene: FundScene.single,
        receiver: 'me',
        status: 'done'),
    _order(biz: 'group_transfer', receiver: 'me', status: 'done'),
    _order(
        biz: 'packet_exclusive',
        receiver: 'me',
        status: 'done',
        createdAt: DateTime(2026, 1, 2, 12, 34)),
    _order(
        biz: 'packet_exclusive',
        scene: FundScene.single,
        receiver: 'me',
        status: 'done',
        createdAt: DateTime(2026, 1, 2, 12, 34)),
    _order(
        biz: 'packet_normal',
        scene: FundScene.single,
        receiver: 'me',
        status: 'done',
        createdAt: DateTime(2026, 1, 2, 12, 34)),
  ]) {
    for (final viewer in direct.isTransfer ? ['me'] : ['sender', 'me']) {
      testWidgets(
          '${direct.scene.name}/${direct.biz} shows real direct arrival for $viewer without claiming',
          (tester) async {
        final api = _FakeFundApi(load: (_) async => direct);
        await tester.pumpWidget(_host(FundDetailPage(
          message: _message(biz: direct.biz),
          api: api,
          currentUserID: viewer,
          profileResolver: (_, __) async => {},
        )));
        await tester.pumpAndSettle();
        expect(api.claims, isEmpty);
        expect(
            find.text(direct.isTransfer
                ? '已接收'
                : viewer == 'me'
                    ? '已到账，已存入余额'
                    : '红包已发送，对方已到账'),
            findsOneWidget);
        if (direct.isTransfer) {
          expect(find.byKey(const ValueKey('fund-detail-menu')), findsNothing);
          expect(
              find.byKey(const ValueKey('fund-detail-status')), findsOneWidget);
          expect(find.text('已到账，已存入余额'), findsNothing);
          expect(find.text('转账备注'), findsNothing);
          expect(find.byKey(const ValueKey('fund-detail-transfer-remark')),
              findsNothing);
          expect(find.byKey(const ValueKey('fund-detail-order-info')),
              findsOneWidget);
          expect(find.text('交易信息'), findsOneWidget);
          expect(find.text('10.00'), findsOneWidget);
        } else {
          expect(find.byType(FundPacketDetail), findsOneWidget);
          expect(find.byKey(const ValueKey('fund-detail-packet-header')),
              findsOneWidget);
          final amount = tester
              .widget<Text>(find.byKey(const ValueKey('fund-detail-amount')));
          expect(amount.textSpan!.toPlainText(), '10.00 USDT');
          final spans = (amount.textSpan! as TextSpan).children!;
          expect((spans.first as TextSpan).style?.fontSize,
              FundTokens.packetAmountFontSize);
          expect(find.text('已到账 1/1 个，共 10.00/10.00 USDT'), findsOneWidget);
          final recipient =
              find.byKey(const ValueKey('fund-detail-direct-recipient'));
          await tester.ensureVisible(recipient);
          expect(
              find.descendant(
                  of: recipient,
                  matching:
                      find.byKey(const ValueKey('fund-detail-avatar-me'))),
              findsOneWidget);
          expect(
              find.descendant(of: recipient, matching: find.text('10.00 USDT')),
              findsOneWidget);
          expect(
              find.descendant(
                  of: recipient, matching: find.text('2026-01-02 12:34')),
              findsOneWidget);
          expect(find.textContaining('发送时间'), findsNothing);
          expect(find.textContaining('领取时间'), findsNothing);
          expect(find.text('手气最佳'), findsNothing);
          expect(
              find.byKey(const ValueKey('fund-detail-share-0')), findsNothing);
          expect(find.byKey(const ValueKey('fund-detail-order-info')),
              findsNothing);
          expect(find.text('红包信息'), findsNothing);
          expect(direct.shares, isEmpty);
        }
        expect(find.text('确认收款'), findsNothing);
        expect(find.byKey(const ValueKey('fund-detail-claim')), findsNothing);
        if (!direct.isTransfer) {
          final avatar =
              find.byKey(const ValueKey('fund-detail-avatar-sender'));
          expect(tester.widget<AvatarView>(avatar).isCircle, isTrue);
          expect(find.descendant(of: avatar, matching: find.byType(ClipOval)),
              findsOneWidget);
        }
      });
    }
  }

  testWidgets(
      'direct packet keeps six-decimal amount with empty shares and no invented time',
      (tester) async {
    final response = _orderFixture('packet-order-without-sender.json');
    final data = response['data'] as Map<String, dynamic>;
    final order = data['order'] as Map<String, dynamic>;
    order.addAll({'currency': 'USDT', 'amount': '0.000001'});
    order.remove('createdAt');
    data['shares'] = <Map<String, dynamic>>[];
    final transport = _FundFixtureTransport(response);
    await tester.pumpWidget(_host(FundDetailPage(
        message: _message(
            id: 'packet-fixture-1', biz: 'packet_normal', amount: '0.000001'),
        api: transport.api,
        currentUserID: 'fixture-recipient',
        profileResolver: (_, __) async => {})));
    await tester.pumpAndSettle();
    expect(find.byType(FundPacketDetail), findsOneWidget);
    final amount =
        tester.widget<Text>(find.byKey(const ValueKey('fund-detail-amount')));
    expect(amount.textSpan!.toPlainText(), '0.000001 USDT');
    final spans = (amount.textSpan! as TextSpan).children!;
    expect((spans.first as TextSpan).style?.fontSize,
        FundTokens.packetAmountFontSize);
    expect((spans.last as TextSpan).style?.fontSize,
        FundTokens.detailUnitFontSize);
    final recipient =
        find.byKey(const ValueKey('fund-detail-direct-recipient'));
    await tester.ensureVisible(recipient);
    expect(find.descendant(of: recipient, matching: find.text('0.000001 USDT')),
        findsOneWidget);
    expect(find.textContaining('发送时间'), findsNothing);
    expect(find.textContaining('领取时间'), findsNothing);
    expect(find.byKey(const ValueKey('fund-detail-share-0')), findsNothing);
    expect(find.byKey(const ValueKey('fund-detail-order-info')), findsNothing);
    expect(find.text('红包信息'), findsNothing);
    expect(transport.claims, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final biz in ['packet_normal', 'packet_lucky']) {
    testWidgets(
        '$biz retains actual claim records and only lucky maximum gets best luck',
        (tester) async {
      final ownAmount = biz == 'packet_lucky' ? '4' : '5';
      final otherAmount = biz == 'packet_lucky' ? '6' : '5';
      final api = _FakeFundApi(
          load: (_) async =>
              _order(biz: biz, status: 'done', shareCount: 2, shares: [
                FundShare(
                    index: 0,
                    amount: FundAmount.parse(ownAmount, FundCurrency.usdt),
                    claimerID: 'me',
                    claimedAt: DateTime(2026, 1, 2, 12, 34)),
                FundShare(
                    index: 1,
                    amount: FundAmount.parse(otherAmount, FundCurrency.usdt),
                    claimerID: 'other',
                    claimedAt: DateTime(2026, 1, 2, 12, 35))
              ]));
      await tester.pumpWidget(_host(FundDetailPage(
          message: _message(biz: biz),
          api: api,
          currentUserID: 'me',
          nameResolver: (_, __) async => {'sender': '张三', 'other': '李四'})));
      await tester.pumpAndSettle();
      expect(find.byType(FundPacketDetail), findsOneWidget);
      expect(find.byKey(const ValueKey('fund-detail-packet-header')),
          findsOneWidget);
      expect(find.text('已领取 2/2 个，共 10.00/10.00 USDT'), findsOneWidget);
      final ownRow = find.byKey(const ValueKey('fund-detail-share-0'));
      final otherRow = find.byKey(const ValueKey('fund-detail-share-1'));
      await tester.scrollUntilVisible(ownRow, 200,
          scrollable: find.byType(Scrollable).first);
      expect(
          find.descendant(of: ownRow, matching: find.text('我')), findsWidgets);
      expect(
          find.descendant(
              of: ownRow, matching: find.text('$ownAmount.00 USDT')),
          findsOneWidget);
      expect(
          find.descendant(of: ownRow, matching: find.text('2026-01-02 12:34')),
          findsOneWidget);
      expect(find.descendant(of: ownRow, matching: find.text('手气最佳')),
          findsNothing);
      await tester.scrollUntilVisible(otherRow, 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.descendant(of: otherRow, matching: find.text('李四')),
          findsOneWidget);
      expect(
          find.descendant(
              of: otherRow, matching: find.text('$otherAmount.00 USDT')),
          findsOneWidget);
      expect(find.descendant(of: otherRow, matching: find.text('手气最佳')),
          biz == 'packet_lucky' ? findsOneWidget : findsNothing);
      expect(find.byKey(const ValueKey('fund-detail-direct-recipient')),
          findsNothing);
      expect(find.textContaining('发送时间'), findsNothing);
      expect(
          find.byKey(const ValueKey('fund-detail-order-info')), findsNothing);
      expect(find.text('红包信息'), findsNothing);
      expect(api.claims, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('forged bubble amount cannot authorize a group claim',
      (tester) async {
    final api = _FakeFundApi(load: (_) async => _order());
    await tester.pumpWidget(_host(FundDetailPage(
      message: _message(amount: '999'),
      api: api,
      currentUserID: 'me',
    )));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('fund-detail-load-error')), findsOneWidget);
    expect(api.claims, isEmpty);
  });

  for (final status in ['open', 'refunded']) {
    testWidgets('direct transfer $status cannot display received or success',
        (tester) async {
      final api = _FakeFundApi(
          load: (_) async => _order(
              biz: 'transfer',
              scene: FundScene.single,
              receiver: 'me',
              status: status));
      await tester.pumpWidget(_host(FundDetailPage(
        message: _message(biz: 'transfer'),
        api: api,
        currentUserID: 'me',
      )));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('fund-detail-load-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('fund-transfer-success')), findsNothing);
      expect(find.text('已接收'), findsNothing);
      expect(find.textContaining('已到账'), findsNothing);
      expect(api.claims, isEmpty);
      expect(api.balanceReads, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('group normal packet sender can claim their own packet',
      (tester) async {
    final api = _FakeFundApi(
        load: (_) async => _order(
              biz: 'packet_normal',
              sender: 'me',
            ));
    await tester.pumpWidget(_host(FundDetailPage(
      message: _message(biz: 'packet_normal', amount: '10.000000'),
      api: api,
      currentUserID: 'me',
    )));
    await tester.pumpAndSettle();
    expect(api.claims, isEmpty);
    await _openCover(tester);
    await tester.pumpAndSettle();
    expect(api.claims, ['packet-1']);
    expect(find.byKey(const ValueKey('fund-detail-amount')), findsOneWidget);
  });

  testWidgets(
      'backend group membership denial is displayed without retry claim',
      (tester) async {
    final api = _FakeFundApi(
      load: (_) async => _order(),
      claim: (_) async => throw const FundApiException(20029, 'FundNotInGroup'),
    );
    await tester.pumpWidget(_host(FundDetailPage(
      message: _message(),
      api: api,
      currentUserID: 'me',
    )));
    await tester.pumpAndSettle();
    await _openCover(tester);
    await tester.pumpAndSettle();
    expect(api.claims, ['packet-1']);
    expect(
        find.byKey(const ValueKey('fund-detail-claim-error')), findsOneWidget);
    expect(
        tester
            .widget<InkWell>(find.byKey(const ValueKey('fund-detail-open')))
            .onTap,
        isNull);
    await tester.tap(find.byKey(const ValueKey('fund-detail-open')));
    await tester.pumpAndSettle();
    expect(api.claims, ['packet-1']);
  });

  testWidgets('single order belonging to other users is rejected',
      (tester) async {
    final api = _FakeFundApi(
        load: (_) async => _order(
              biz: 'transfer',
              scene: FundScene.single,
              receiver: 'other',
              status: 'done',
            ));
    await tester.pumpWidget(_host(FundDetailPage(
      message: _message(biz: 'transfer'),
      api: api,
      currentUserID: 'me',
    )));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('fund-detail-load-error')), findsOneWidget);
    expect(api.claims, isEmpty);
  });

  testWidgets(
      'group observers see recipient delivery instead of an outgoing transfer',
      (tester) async {
    final api = _FakeFundApi(
        load: (_) async => _order(
              biz: 'group_transfer',
              receiver: 'other',
              status: 'done',
            ));
    await tester.pumpWidget(_host(FundDetailPage(
      message: _message(biz: 'group_transfer'),
      api: api,
      currentUserID: 'me',
      nameResolver: (_, __) async => {'sender': '张三', 'other': '李四'},
    )));
    await tester.pumpAndSettle();
    expect(find.text('已接收'), findsOneWidget);
    expect(find.text('张三群转账给李四'), findsOneWidget);
    expect(find.text('李四'), findsOneWidget);
    expect(find.text('已转账，对方已到账'), findsNothing);
    expect(api.claims, isEmpty);
  });

  for (final closed in [
    _order(status: 'done'),
    _order(status: 'refunded'),
    _order(expires: DateTime.utc(2000)),
    _order(shares: [_ownShare()]),
  ]) {
    testWidgets(
        'no claim for ${closed.status}/${closed.isExpired}/${closed.shares.length}',
        (tester) async {
      final api = _FakeFundApi(load: (_) async => closed);
      await tester.pumpWidget(_host(FundDetailPage(
        message: _message(),
        api: api,
        currentUserID: 'me',
      )));
      await tester.pumpAndSettle();
      expect(api.claims, isEmpty);
      expect(find.byKey(const ValueKey('fund-detail-status')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('fund-detail-load-error')), findsNothing);
    });
  }

  for (final status in ['done', 'refunded']) {
    testWidgets(
        'closed group packet $status shows missing details without claiming',
        (tester) async {
      final api = _FakeFundApi(load: (_) async => _order(status: status));
      await tester.pumpWidget(_host(FundDetailPage(
          message: _message(),
          api: api,
          currentUserID: 'me',
          profileResolver: (_, __) async => {})));
      await tester.pumpAndSettle();
      expect(api.claims, isEmpty);
      final viewDetails =
          find.byKey(const ValueKey('fund-detail-view-details'));
      if (viewDetails.evaluate().isNotEmpty) {
        await tester.tap(viewDetails);
        await tester.pumpAndSettle();
      }
      expect(find.byType(FundPacketDetail), findsOneWidget);
      expect(find.text('暂无领取明细'), findsOneWidget);
      expect(find.text('还没有人领取这个红包'), findsNothing);
      expect(find.text('共 4 个，总额 10.00 USDT'), findsOneWidget);
      expect(find.textContaining('已领取 0/'), findsNothing);
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('fund-detail-status')))
              .data,
          status == 'done' ? '红包已领完' : '未领取金额已退回');
      expect(find.byKey(const ValueKey('fund-detail-share-0')), findsNothing);
      expect(find.byKey(const ValueKey('fund-detail-direct-recipient')),
          findsNothing);
      expect(
          find.byKey(const ValueKey('fund-detail-order-info')), findsNothing);
      expect(find.text('红包信息'), findsNothing);
      expect(api.claims, isEmpty);
      expect(api.reads, ['packet-1']);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('already-claimed error reloads own amount without another claim',
      (tester) async {
    late _FakeFundApi api;
    api = _FakeFundApi(
      load: (_) async =>
          api.claims.isEmpty ? _order() : _order(shares: [_ownShare()]),
      claim: (_) async =>
          throw const FundApiException(20033, 'FundAlreadyClaimed'),
    );
    await tester.pumpWidget(_host(FundDetailPage(
      message: _message(),
      api: api,
      currentUserID: 'me',
    )));
    await tester.pumpAndSettle();
    await _openCover(tester);
    await tester.pumpAndSettle();
    expect(api.claims.length, 1);
    expect(api.reads.length, 2);
    expect(find.text('2.50 USDT'), findsWidgets);
    expect(find.byKey(const ValueKey('fund-detail-claim')), findsNothing);
    expect(find.byKey(const ValueKey('fund-detail-claim-error')), findsNothing);
  });

  testWidgets(
      'retry checks refreshed shares before repeating an uncertain claim',
      (tester) async {
    final api = _FakeFundApi(
      load: (_) async => _order(),
      claim: (_) async => throw const FundApiException(
        -1,
        'Timed out',
        isUncertain: true,
      ),
    );
    await tester.pumpWidget(_host(FundDetailPage(
      message: _message(),
      api: api,
      currentUserID: 'me',
    )));
    await tester.pumpAndSettle();
    await _openCover(tester);
    await tester.pumpAndSettle();
    expect(api.claims.length, 1);
    api.load = (_) async => _order(shares: [_ownShare()]);
    await tester.tap(find.byKey(const ValueKey('fund-detail-claim')));
    await tester.pumpAndSettle();
    expect(api.claims.length, 1);
    expect(find.text('2.50 USDT'), findsWidgets);
  });

  testWidgets('load error exposes retry then uses the current server order',
      (tester) async {
    final api = _FakeFundApi(
        load: (_) async =>
            throw const FundApiException(20032, 'FundOrderNotFound'));
    await tester.pumpWidget(_host(FundDetailPage(
      message: _message(),
      api: api,
      currentUserID: 'me',
    )));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('fund-detail-load-error')), findsOneWidget);
    api.load = (_) async => _order(status: 'refunded');
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('未领取金额已退回'), findsOneWidget);
    expect(api.claims, isEmpty);
  });

  testWidgets(
      'older order response cannot claim after the page reference changes',
      (tester) async {
    final oldRead = Completer<FundOrder>();
    final api = _FakeFundApi(
        load: (id) => id == 'packet-1'
            ? oldRead.future
            : Future.value(
                _order(id: id, status: 'refunded', remark: '新红包祝福')));
    const pageKey = ValueKey('detail-page');
    await tester.pumpWidget(_host(FundDetailPage(
      key: pageKey,
      message: _message(),
      api: api,
      currentUserID: 'me',
    )));
    await tester.pumpWidget(_host(FundDetailPage(
      key: pageKey,
      message: _message(id: 'packet-2'),
      api: api,
      currentUserID: 'me',
    )));
    await tester.pumpAndSettle();
    oldRead.complete(_order(remark: '旧红包祝福'));
    await tester.pumpAndSettle();
    expect(api.claims, isEmpty);
    expect(find.text('未领取金额已退回'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fund-detail-view-details')));
    await tester.pumpAndSettle();
    expect(find.text('新红包祝福'), findsOneWidget);
    expect(find.text('旧红包祝福'), findsNothing);
    expect(find.byKey(const ValueKey('fund-detail-order-info')), findsNothing);
    expect(find.text('红包信息'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposed load does not update state or claim', (tester) async {
    final read = Completer<FundOrder>();
    final api = _FakeFundApi(load: (_) => read.future);
    await tester.pumpWidget(_host(FundDetailPage(
      message: _message(),
      api: api,
      currentUserID: 'me',
    )));
    await tester.pumpWidget(_host(const SizedBox()));
    read.complete(_order());
    await tester.pumpAndSettle();
    expect(api.claims, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'endpoint switch rejects old order and blocks further fund requests',
      (tester) async {
    final previousConfig = Map<String, String>.from(
        DataSp.getServerConfig() ?? const <String, String>{});
    final previousURL = Config.appAuthUrl;
    addTearDown(() async => await DataSp.putServerConfig(previousConfig));
    final read = Completer<FundOrder>();
    final api = _FakeFundApi(load: (_) => read.future);
    await tester.pumpWidget(_host(FundDetailPage(
      message: _message(),
      api: api,
      currentUserID: 'me',
    )));
    await tester.runAsync(() async {
      await DataSp.putServerConfig({
        ...previousConfig,
        'authUrl': '$previousURL/changed-node',
      });
    });
    read.complete(_order());
    await tester.pump();
    await tester.pump();
    expect(api.claims, isEmpty);
    expect(find.byKey(const ValueKey('fund-detail-amount')), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(api.reads, ['packet-1']);
    expect(api.claims, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(_host(const SizedBox()));
  });

  testWidgets('endpoint switch blocks refresh even for an already loaded order',
      (tester) async {
    final previousConfig = Map<String, String>.from(
        DataSp.getServerConfig() ?? const <String, String>{});
    final previousURL = Config.appAuthUrl;
    addTearDown(() async => await DataSp.putServerConfig(previousConfig));
    final api = _FakeFundApi(load: (_) async => _order(status: 'refunded'));
    await tester.pumpWidget(_host(FundDetailPage(
      message: _message(),
      api: api,
      currentUserID: 'me',
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fund-detail-view-details')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await DataSp.putServerConfig({
        ...previousConfig,
        'authUrl': '$previousURL/changed-node',
      });
    });
    await _refreshDetails(tester);
    expect(api.reads, ['packet-1']);
    expect(api.claims, isEmpty);
    await tester.pumpWidget(_host(const SizedBox()));
  });

  testWidgets('resolves verified parties in one batch and hides raw user IDs',
      (tester) async {
    final requests = <List<String>>[];
    final api = _FakeFundApi(
        load: (_) async => _order(
              status: 'done',
              shares: [
                _ownShare(),
                FundShare(
                    index: 1,
                    amount: FundAmount.parse('2', FundCurrency.usdt),
                    claimerID: 'other'),
              ],
            ));
    await tester.pumpWidget(_host(FundDetailPage(
      message: _message(),
      api: api,
      currentUserID: 'me',
      nameResolver: (order, userIDs) async {
        expect(order.orderID, 'packet-1');
        requests.add(userIDs);
        return {'sender': '张三', 'other': '李四'};
      },
    )));
    await tester.pumpAndSettle();
    expect(requests, [
      ['sender', 'other']
    ]);
    expect(find.text('张三的红包'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('李四'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('李四'), findsOneWidget);
    expect(find.text('other'), findsNothing);
    expect(find.text('me（我）'), findsNothing);
    await _refreshDetails(tester);
    expect(requests.length, 1);
  });

  testWidgets(
      'name enrichment caps each batch and failures keep readable fallback',
      (tester) async {
    final api = _FakeFundApi(
        load: (_) async => _order(
              status: 'done',
              shareCount: 100,
              shares: List.generate(
                  100,
                  (index) => FundShare(
                        index: index,
                        amount: FundAmount.parse('0.1', FundCurrency.usdt),
                        claimerID: 'member-$index',
                      )),
            ));
    var nameRequests = 0;
    await tester.pumpWidget(_host(FundDetailPage(
      message: _message(),
      api: api,
      currentUserID: 'me',
      nameResolver: (_, userIDs) async {
        nameRequests++;
        expect(userIDs.length, lessThanOrEqualTo(FundTokens.memberPageSize));
        throw StateError('Profiles unavailable');
      },
    )));
    await tester.pumpAndSettle();
    expect(nameRequests, 1);
    await tester.tap(find.byKey(const ValueKey('fund-detail-view-details')));
    await tester.pumpAndSettle();
    expect(find.text('群成员的红包'), findsOneWidget);
    expect(find.text('sender'), findsNothing);
    expect(find.text('member-0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'old post-claim refresh cannot clear a new order claim in progress',
      (tester) async {
    final oldRefresh = Completer<FundOrder>();
    final newClaim = Completer<FundClaimResult>();
    var oldReads = 0;
    late _FakeFundApi api;
    api = _FakeFundApi(
      load: (id) {
        if (id == 'packet-1') {
          oldReads++;
          return oldReads == 1 ? Future.value(_order()) : oldRefresh.future;
        }
        return Future.value(_order(
          id: id,
          shares: newClaim.isCompleted ? [_ownShare()] : const [],
          status: newClaim.isCompleted ? 'done' : 'open',
        ));
      },
      claim: (id) => id == 'packet-1'
          ? Future.value(FundClaimResult(amount: '2.5', orderID: id))
          : newClaim.future,
    );
    const pageKey = ValueKey('detail-claim-page');
    await tester.pumpWidget(_host(FundDetailPage(
      key: pageKey,
      message: _message(),
      api: api,
      currentUserID: 'me',
    )));
    await tester.pump();
    await tester.pump();
    await _openCover(tester);
    await tester.pump();
    expect(oldReads, 2);
    await tester.pumpWidget(_host(FundDetailPage(
      key: pageKey,
      message: _message(id: 'packet-2'),
      api: api,
      currentUserID: 'me',
    )));
    await tester.pump();
    await tester.pump();
    await _openCover(tester);
    await tester.pump();
    expect(api.claims, ['packet-1', 'packet-2']);
    oldRefresh.complete(_order(shares: [_ownShare()]));
    await tester.pump();
    await tester.pump();
    expect(
        tester
            .widget<InkWell>(find.byKey(const ValueKey('fund-detail-open')))
            .onTap,
        isNull);
    expect(find.text('正在领取红包'), findsOneWidget);
    newClaim
        .complete(const FundClaimResult(amount: '2.5', orderID: 'packet-2'));
    await tester.pumpAndSettle();
    expect(find.text('红包已领完'), findsOneWidget);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('fund-detail-amount')))
            .textSpan!
            .toPlainText(),
        '2.50 USDT');
    expect(tester.takeException(), isNull);
  });

  testWidgets('system route pop returns the latest server order',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    final serverOrder = _order(status: 'refunded');
    final api = _FakeFundApi(load: (_) async => serverOrder);
    await tester.pumpWidget(_host(const SizedBox(), navigatorKey: navigator));
    final result = navigator.currentState!.push<FundOrder>(FundDetailRoute(
      message: _message(),
      api: api,
      currentUserID: 'me',
    ));
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(await result, same(serverOrder));
  });

  for (final closeFromScrim in [false, true]) {
    testWidgets(
        'modal keeps chat visible and ${closeFromScrim ? 'scrim' : 'outside close'} returns verified order',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final navigator = GlobalKey<NavigatorState>();
      final serverOrder = _order();
      final api = _FakeFundApi(load: (_) async => serverOrder);
      await tester.pumpWidget(_host(
          const Scaffold(body: Center(child: Text('原聊天内容'))),
          navigatorKey: navigator));
      final route =
          FundDetailRoute(message: _message(), api: api, currentUserID: 'me');
      final result = navigator.currentState!.push<FundOrder>(route);
      await tester.pumpAndSettle();
      expect(route.opaque, isFalse);
      expect(find.text('原聊天内容'), findsOneWidget);
      final envelope =
          tester.getRect(find.byKey(const ValueKey('fund-packet-cover')));
      expect(
          envelope.width,
          closeTo(
              375 *
                  (1 - FundTokens.previewSidePaddingRatio * 2) *
                  FundTokens.previewMobileWidthRatio,
              .01));
      expect(envelope.width / envelope.height,
          closeTo(FundTokens.previewAspectRatio, .001));
      expect(envelope.center.dx, closeTo(375 / 2, .01));
      final image = tester.widget<Image>(
          find.byKey(const ValueKey('fund-reference-cover-art')));
      expect((image.image as AssetImage).assetName,
          'assets/img/red_packet_preview_cover_v2.png');
      expect(find.byKey(const ValueKey('fund-detail-avatar-sender')),
          findsNothing);
      final coin =
          tester.getRect(find.byKey(const ValueKey('fund-detail-open')));
      expect(
          coin.center.dy - envelope.top,
          closeTo(
              envelope.height * (1 - FundTokens.previewCoinBottomRatio) -
                  coin.height / 2,
              .01));
      final details = tester
          .getRect(find.byKey(const ValueKey('fund-detail-view-details')));
      expect(details.top, greaterThanOrEqualTo(envelope.bottom));
      final close =
          tester.getRect(find.byKey(const ValueKey('fund-detail-close')));
      expect(
          close.top - envelope.bottom,
          greaterThanOrEqualTo(
              details.height + 375 * FundTokens.previewCloseGapRatio));
      expect(
          tester.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor,
          FundTokens.transparent);
      if (closeFromScrim) {
        await tester.tapAt(const Offset(12, 12));
      } else {
        await tester.tap(find.byKey(const ValueKey('fund-detail-close')));
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('fund-packet-cover')), findsNothing);
      expect(await result, same(serverOrder));
      expect(api.claims, isEmpty);
    });
  }

  testWidgets('open flips before transitioning while claim locks immediately',
      (tester) async {
    final claim = Completer<FundClaimResult>();
    final api =
        _FakeFundApi(load: (_) async => _order(), claim: (_) => claim.future);
    await tester.pumpWidget(_host(FundDetailPage(
      message: _message(),
      api: api,
      currentUserID: 'me',
    )));
    await tester.pumpAndSettle();
    await _openCover(tester);
    expect(api.claims, ['packet-1']);
    expect(find.byKey(const ValueKey('fund-packet-cover')), findsOneWidget);
    await tester.pump(FundTokens.openingDuration ~/ 4);
    final transform = tester.renderObject<RenderBox>(
        find.byKey(const ValueKey('fund-detail-open-animation')));
    final coin = tester.renderObject<RenderBox>(
        find.byKey(const ValueKey('fund-detail-open')));
    expect(coin.getTransformTo(transform), isNot(Matrix4.identity()));
    await tester.tap(find.byKey(const ValueKey('fund-detail-open')));
    expect(api.claims, ['packet-1']);
    claim.complete(const FundClaimResult(orderID: 'packet-1', amount: '2.5'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fund-packet-cover')), findsNothing);
    expect(find.text('2.50 USDT'), findsOneWidget);
  });

  testWidgets('reduced motion bypasses flip without changing claim behavior',
      (tester) async {
    final api = _FakeFundApi(load: (_) async => _order());
    await tester.pumpWidget(_host(
        FundDetailPage(
          message: _message(),
          api: api,
          currentUserID: 'me',
        ),
        disableAnimations: true));
    await tester.pumpAndSettle();
    await _openCover(tester);
    await tester.pump();
    expect(api.claims, ['packet-1']);
    expect(find.byKey(const ValueKey('fund-packet-cover')), findsNothing);
    expect(
        find.byKey(const ValueKey('fund-detail-open-animation')), findsNothing);
    expect(find.text('2.50 USDT'), findsOneWidget);
  });

  testWidgets('verified profile batch binds sender and claimant avatars',
      (tester) async {
    final requests = <List<String>>[];
    final api = _FakeFundApi(load: (_) async => _order(shares: [_ownShare()]));
    await tester.pumpWidget(_host(FundDetailPage(
      message: _message(),
      api: api,
      currentUserID: 'me',
      profileResolver: (order, ids) async {
        requests.add(ids);
        return {
          for (final id in ids)
            id: FundPartyProfile(
                name: id == 'sender' ? '小林' : '我的昵称',
                faceURL: 'https://example.invalid/$id.png'),
        };
      },
    )));
    await tester.pumpAndSettle();
    expect(requests, [
      ['sender', 'me']
    ]);
    final sender = tester.widget<AvatarView>(
        find.byKey(const ValueKey('fund-detail-avatar-sender')));
    expect(sender.url, 'https://example.invalid/sender.png');
    expect(sender.isCircle, isTrue);
    expect(sender.width, FundTokens.detailSenderAvatarSize);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('fund-detail-avatar-sender')),
            matching: find.byType(ClipOval)),
        findsOneWidget);
    expect(find.text('小林的红包'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('fund-detail-share-0')), 200,
        scrollable: find.byType(Scrollable).first);
    final mine = tester.widget<AvatarView>(
        find.byKey(const ValueKey('fund-detail-avatar-me')));
    expect(mine.url, 'https://example.invalid/me.png');
    expect(mine.width, FundTokens.recordAvatarSize);
    expect(mine.isCircle, isTrue);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('fund-detail-avatar-me')),
            matching: find.byType(ClipOval)),
        findsOneWidget);
    expect(api.claims, isEmpty);
  });

  testWidgets(
      'loaded group page blocks claim and refresh after SDK account changes',
      (tester) async {
    var previousUser = '';
    try {
      previousUser = OpenIM.iMManager.userID;
    } catch (_) {
      // The SDK has not logged in inside this widget test process.
    }
    addTearDown(() => OpenIM.iMManager.userID = previousUser);
    OpenIM.iMManager.userID = 'me';
    final api = _FakeFundApi(load: (_) async => _order());
    await tester
        .pumpWidget(_host(FundDetailPage(message: _message(), api: api)));
    await tester.pumpAndSettle();
    OpenIM.iMManager.userID = 'new-account';
    await _openCover(tester);
    expect(api.claims, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(api.reads, ['packet-1']);
    expect(api.claims, isEmpty);
    await tester.pumpWidget(_host(const SizedBox()));
  });

  testWidgets(
      'amount uses exact two-decimal display with a smaller baseline currency',
      (tester) async {
    final api = _FakeFundApi(load: (_) async => _order(shares: [_ownShare()]));
    await tester.pumpWidget(_host(FundDetailPage(
      message: _message(),
      api: api,
      currentUserID: 'me',
    )));
    await tester.pumpAndSettle();
    final amount =
        tester.widget<Text>(find.byKey(const ValueKey('fund-detail-amount')));
    final spans = (amount.textSpan! as TextSpan).children!;
    expect((spans.first as TextSpan).text, '2.50');
    final unit = spans.last as TextSpan;
    expect(unit.text, ' USDT');
    expect(unit.style!.fontSize, FundTokens.detailUnitFontSize);
    expect((spans.first as TextSpan).style!.fontSize,
        FundTokens.packetAmountFontSize);
    expect(api.claims, isEmpty);
  });

  testWidgets(
      'packet ellipsis refreshes without claiming or exposing order information',
      (tester) async {
    final api = _FakeFundApi(load: (_) async => _order(shares: [_ownShare()]));
    await tester.pumpWidget(_host(FundDetailPage(
      message: _message(),
      api: api,
      currentUserID: 'me',
    )));
    await tester.pumpAndSettle();
    expect(find.text('红包详情'), findsOneWidget);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('fund-detail-status')))
            .data,
        '红包已领取');
    expect(find.text('红包待领取'), findsNothing);
    expect(find.text('订单号'), findsNothing);
    expect(find.byKey(const ValueKey('fund-detail-order-info')), findsNothing);
    expect(find.text('红包信息'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('fund-detail-menu')));
    await tester.pumpAndSettle();
    expect(api.reads, ['packet-1']);
    expect(api.claims, isEmpty);
    await tester.tap(find.byKey(const ValueKey('fund-detail-refresh')));
    await tester.pumpAndSettle();
    expect(api.reads, ['packet-1', 'packet-1']);
    expect(api.claims, isEmpty);
    expect(find.text('订单号'), findsNothing);
    expect(find.byKey(const ValueKey('fund-detail-order-info')), findsNothing);
    expect(find.text('红包信息'), findsNothing);
  });

  for (final brightness in Brightness.values) {
    testWidgets('narrow ${brightness.name} red cover supports large text',
        (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _FakeFundApi(load: (_) async => _order());
      await tester.pumpWidget(_host(
          FundDetailPage(
            message: _message(),
            api: api,
            currentUserID: 'me',
          ),
          brightness: brightness,
          textScale: 2));
      await tester.pumpAndSettle();
      await tester
          .ensureVisible(find.byKey(const ValueKey('fund-detail-open')));
      expect(tester.takeException(), isNull);
      expect(api.claims, isEmpty);
      expect(
          tester.getSize(find.byKey(const ValueKey('fund-detail-open'))),
          Size.square(tester
                  .getSize(find.byKey(const ValueKey('fund-packet-cover')))
                  .width *
              FundTokens.previewCoinSizeRatio));
      expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
          FundTokens.transparent);
    });

    testWidgets(
        'narrow ${brightness.name} detail supports large text and scrolling',
        (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _FakeFundApi(
          load: (_) async => _order(
                status: 'done',
                shares: [_ownShare()],
              ));
      await tester.pumpWidget(_host(
          FundDetailPage(
            message: _message(),
            api: api,
            currentUserID: 'me',
          ),
          brightness: brightness,
          textScale: 2));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('fund-detail-share-0')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
          find.byWidgetPredicate((widget) =>
              widget is Text &&
              widget.data == '我' &&
              widget.style?.fontSize == FundTokens.detailTitleFont),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      final header = scaffold.appBar! as AppBar;
      expect(header.backgroundColor, FundTokens.luckyHeader);
      expect(header.scrolledUnderElevation, 0);
      expect(header.flexibleSpace, isNull);
      expect(
          scaffold.backgroundColor,
          brightness == Brightness.dark
              ? FundTokens.luckySurfaceDark
              : AppTokens.onAccent);
    });
  }
}
