import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/data/wallet_fund_repository.dart';
import 'package:openim/pages/wallet/data/wallet_trend_data.dart';
import 'package:openim/pages/wallet/data/wallet_session_source.dart';
import 'package:openim/pages/wallet/home/trend/wallet_trend_chart.dart';
import 'package:openim/pages/wallet/home/trend/wallet_trend_geometry.dart';
import 'package:openim/pages/wallet/home/trend/wallet_trend_display_points.dart';
import 'package:openim/pages/wallet/home/widgets/wallet_balance_overview.dart';
import 'package:openim/pages/wallet/wallet_repository.dart';
import 'package:openim/pages/wallet/wallet_controller.dart';
import 'package:provider/provider.dart';

import '../data/wallet_fund_test_api.dart';
import '../data/wallet_fund_test_transport.dart';

WalletTrendPoint point(int time, String? value, [String id = 'id']) =>
    WalletTrendPoint(id: id, createdAt: time, totalCny: value);

const _displaySlots = WalletTrendDisplayPoints.slotCount;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('trend GET has authentication, no body or currency, and actual count',
      () async {
    final transport = WalletFundTestTransport();
    addTearDown(transport.close);
    transport.respond({
      'currentCny': '999.00',
      'count': 2,
      'limit': 100,
      'points': [
        {
          'id': '1',
          'createdAt': 100,
          'totalCny': '110.00',
          'priceStatus': 'ready'
        },
        {
          'id': '2',
          'createdAt': 100,
          'totalCny': null,
          'priceStatus': 'unavailable'
        },
      ]
    });
    final data = await transport.wallet.fetchTrend();
    expect(data.points, hasLength(2));
    expect(data.points.last.totalCny, isNull);
    expect(data.currentCny, '999.00');
    final request = transport.requests.single;
    expect(request.path, 'https://chat.example.test/chat/fund/trend');
    expect(request.method, 'GET');
    expect(request.data, isNull);
    expect(request.queryParameters, isEmpty);
    expect(request.headers['token'], 'chat-token');
    expect(request.headers['operationID'], isNotEmpty);
  });

  test('geometry retains gaps, ties, timestamps, singleton and flat series',
      () {
    final geometry = WalletTrendGeometry([
      point(100, '10.00'),
      point(100, '20.00'),
      point(200, null),
      point(400, '30.00'),
    ], const Size(300, 100));
    expect(geometry.xs[1], greaterThan(geometry.xs[0]));
    expect(geometry.xs[2], lessThan(150));
    expect(geometry.offsets[2], isNull);
    expect(geometry.paths, hasLength(2));
    expect(geometry.nearest(geometry.xs[1]), 1);
    final single =
        WalletTrendGeometry([point(1, '0.00')], const Size(300, 100));
    expect(single.offsets.single, const Offset(150, 50));
    final flat = WalletTrendGeometry(
        [point(1, '5.00'), point(2, '5.00')], const Size(300, 100));
    expect(flat.offsets.every((p) => p!.dy == 50), isTrue);
    expect(WalletTrendGeometry([], const Size(300, 100)).paths, isEmpty);
  });

  test('smooth interpolation stays inside real endpoint values', () {
    final geometry = WalletTrendGeometry(
        [point(1, '1.00'), point(2, '100.00'), point(3, '2.00')],
        const Size(300, 100));
    final metric = geometry.paths.single.computeMetrics().single;
    for (var d = 0.0; d < metric.length; d += 0.5) {
      final pos = metric.getTangentForOffset(d)!.position;
      expect(pos.dy, inInclusiveRange(-0.001, 100.001));
    }
  });

  test('keeps latest 40 records and prepends zero slots without mutating them',
      () {
    expect(_displaySlots, 40);
    for (final count in [0, 1, 2, 20, 39, 40, 50, 100]) {
      final data = WalletTrendData.fromJson({
        'currentCny': '9999.00',
        'points': List.generate(
            count,
            (i) => {
                  'id': '$i',
                  'createdAt': i,
                  'totalCny': '1.00',
                  'priceStatus': 'ready',
                }),
      });
      final display = WalletTrendDisplayPoints(data.points);
      final firstRetained = count > _displaySlots ? count - _displaySlots : 0;
      final recent = data.points.skip(firstRetained);
      expect(display.points, hasLength(_displaySlots));
      expect(display.paddingCount, _displaySlots - recent.length);
      expect(
          display.points
              .take(display.paddingCount)
              .every((p) => p.totalCny == '0.00'),
          isTrue);
      expect(display.points.skip(display.paddingCount), recent);
      if (count > _displaySlots) {
        expect(display.points.first.id, '$firstRetained');
        expect(display.points.last.id, '${count - 1}');
      }
      expect(data.points, hasLength(count));
      final geometry = WalletTrendGeometry(display.points, const Size(390, 100),
          evenlySpaced: true);
      expect(geometry.offsets, hasLength(_displaySlots));
      for (var i = 0; i < _displaySlots; i++) {
        expect(geometry.xs[i], closeTo(i * 10, 0.001));
        expect(geometry.nearest(i * 10), i);
      }
    }
    final records = [point(1, '10.00'), point(2, null), point(3, '20.00')];
    final display = WalletTrendDisplayPoints(records);
    final geometry = WalletTrendGeometry(display.points, const Size(390, 100),
        evenlySpaced: true);
    expect(display.points[_displaySlots - 2].totalCny, isNull);
    expect(geometry.offsets[_displaySlots - 2], isNull);
    expect(geometry.paths, hasLength(2));
  });

  testWidgets('scrubbing updates top total, preserves gaps and restores on up',
      (tester) async {
    final haptics = _captureHaptics(tester);
    final controller = await _loadedController();
    final data = WalletTrendData(currentCny: '999.00', points: [
      point(1, '84.00'),
      point(2, null),
      point(3, '112.00'),
    ]);
    await _pumpTrendOverview(tester, controller, data);
    expect(_topAmount(tester), '¥110.00');
    final rect = tester.getRect(_chart);
    final gesture = await tester.startGesture(_slot(rect, _displaySlots - 3));
    await tester.pump(const Duration(milliseconds: 600));
    expect(_topAmount(tester), '¥84.00');
    expect(haptics, hasLength(1));
    expect(find.byKey(const ValueKey('wallet-trend-selected-balance')),
        findsNothing,
        reason: 'The inspected amount belongs in the top total.');
    await gesture.moveTo(_slot(rect, _displaySlots - 2));
    await tester.pump();
    expect(_topAmount(tester), '历史价格暂缺');
    await gesture.moveTo(_slot(rect, _displaySlots - 1));
    await tester.pump();
    expect(_topAmount(tester), '¥112.00');
    await gesture.moveTo(_slot(rect, 20));
    await tester.pump();
    expect(_topAmount(tester), '¥0.00');
    expect(haptics, hasLength(4));
    await gesture.up();
    await tester.pump();
    expect(_topAmount(tester), '¥110.00');
    expect(controller.totalBal, '110.00');
    expect(controller.inspectingTrend, isFalse);
    expect(find.byKey(const ValueKey('wallet-trend-cursor')), findsNothing);
    expect(data.points, hasLength(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('all 40 slots are selectable and tick once per entered slot',
      (tester) async {
    final haptics = _captureHaptics(tester);
    final controller = await _loadedController();
    final data =
        WalletTrendData(points: [point(1, '84.00'), point(2, '112.00')]);
    await _pumpTrendOverview(tester, controller, data);
    final rect = tester.getRect(_chart);
    final cursor = find.byKey(const ValueKey('wallet-trend-cursor'));
    final gesture = await tester.startGesture(_slot(rect, 0));
    await tester.pump(const Duration(milliseconds: 600));
    for (var i = 0; i < _displaySlots; i++) {
      await gesture.moveTo(_slot(rect, i));
      await tester.pump();
      expect(
          _topAmount(tester),
          i < _displaySlots - 2
              ? '¥0.00'
              : i == _displaySlots - 2
                  ? '¥84.00'
                  : '¥112.00');
      expect(tester.getCenter(cursor).dx, closeTo(_slot(rect, i).dx, 1));
      expect(haptics, hasLength(i + 1));
      await gesture.moveTo(
          _slot(rect, i, fraction: i == _displaySlots - 1 ? -0.1 : 0.1));
      await tester.pump();
      expect(haptics, hasLength(i + 1),
          reason: 'Moving inside one slot must not tick again.');
    }
    expect(
        haptics.every(
            (call) => call.arguments == 'HapticFeedbackType.lightImpact'),
        isTrue);
    await gesture.cancel();
    await tester.pump();
    expect(_topAmount(tester), '¥110.00');
    expect(cursor, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'normal horizontal swipe selects immediately and vertical scroll cancels',
      (tester) async {
    final haptics = _captureHaptics(tester);
    final controller = await _loadedController();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final data =
        WalletTrendData(points: [point(1, '84.00'), point(2, '112.00')]);
    await _pumpTrendOverview(tester, controller, data, scroll: scroll);
    final rect = tester.getRect(_chart);
    final gesture = await tester.startGesture(_slot(rect, 10));
    await tester.pump();
    expect(_topAmount(tester), '¥0.00');
    // Adjacent slots are narrower than the normal drag recognition threshold.
    await gesture.moveTo(_slot(rect, 11));
    await tester.pump();
    expect(haptics, hasLength(2));
    expect(
        tester.getCenter(find.byKey(const ValueKey('wallet-trend-cursor'))).dx,
        closeTo(_slot(rect, 11).dx, 1));
    await gesture.moveTo(_slot(rect, _displaySlots - 2));
    await tester.pump();
    expect(_topAmount(tester), '¥84.00');
    await gesture.moveTo(_slot(rect, _displaySlots - 1));
    await tester.pump();
    expect(_topAmount(tester), '¥112.00');
    expect(scroll.offset, 0);
    await gesture.up();
    await tester.pump();
    expect(_topAmount(tester), '¥110.00');

    final vertical = await tester.startGesture(rect.center);
    await tester.pump();
    expect(_topAmount(tester), '¥0.00');
    await vertical.moveBy(const Offset(0, -120));
    await tester.pump();
    expect(_topAmount(tester), '¥110.00');
    await vertical.moveBy(const Offset(0, -40));
    await tester.pump();
    await vertical.up();
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  test('privacy, collapse, deactivation and trend refresh clear the preview',
      () async {
    final repo = _TrendRepo()..fail = false;
    final controller = await _loadedController(repo);
    controller.inspectTrendBalance('84.00');
    expect(controller.inspectingTrend, isTrue);
    controller.toggleBal();
    expect(controller.inspectingTrend, isFalse);
    expect(controller.inspectedTrendCny, isNull);
    controller.inspectTrendBalance('84.00');
    expect(controller.inspectingTrend, isFalse);
    controller.toggleBal();
    controller.inspectTrendBalance('84.00');
    controller.setTrendEnabled(false);
    expect(controller.inspectingTrend, isFalse);
    controller.inspectTrendBalance('84.00');
    controller.setActive(false);
    expect(controller.inspectingTrend, isFalse);
    controller.inspectTrendBalance('84.00');
    expect(controller.inspectingTrend, isFalse);
    controller.setActive(true);
    controller.inspectTrendBalance('84.00');
    await controller.loadTrend();
    expect(controller.inspectingTrend, isFalse);
    expect(controller.totalBal, '110.00');
    controller.inspectTrendBalance('84.00');
    repo.fail = true;
    await controller.loadTrend();
    expect(controller.inspectingTrend, isFalse);
    expect(controller.inspectedTrendCny, isNull);
  });

  test('late trend cannot publish after account switch', () async {
    var account = 'old';
    final pending = Completer<WalletTrendData>();
    final api = _TrendApi(pending.future);
    final repo = WalletFundRepository(api: api, accountProvider: () => account);
    final request = repo.getTrend();
    account = 'new';
    pending.complete(const WalletTrendData(points: []));
    await expectLater(request, throwsA(isA<WalletAccountChangedException>()));
  });

  test('trend failure leaves wallet balances available and can retry',
      () async {
    final repo = _TrendRepo();
    final controller = WalletController(repo: repo);
    addTearDown(controller.dispose);
    await controller.load();
    await controller.loadTrend();
    expect(controller.totalBal, '110.00');
    expect(controller.trendFailed, isTrue);
    repo.fail = false;
    await controller.loadTrend();
    expect(controller.trendFailed, isFalse);
    expect(controller.trend!.points, hasLength(1));
  });
}

final _chart = find.byKey(const ValueKey('wallet-trend-chart'));

String? _topAmount(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('wallet-total-amount'))).data;

Offset _slot(Rect rect, int index, {double fraction = 0}) => Offset(
    rect.left +
        rect.width *
            ((index + fraction) / (_displaySlots - 1)).clamp(0.001, 0.999),
    rect.center.dy);

List<MethodCall> _captureHaptics(WidgetTester tester) {
  final calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'HapticFeedback.vibrate') calls.add(call);
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
  return calls;
}

Future<WalletController> _loadedController([_TrendRepo? repo]) async {
  final controller = WalletController(repo: repo ?? _TrendRepo());
  addTearDown(controller.dispose);
  await controller.load();
  return controller;
}

Future<void> _pumpTrendOverview(
    WidgetTester tester, WalletController controller, WalletTrendData data,
    {ScrollController? scroll}) async {
  final content = Column(children: [
    WalletBalanceOverview(onRecords: () {}, onOverview: () {}),
    SizedBox(
        width: 400,
        height: 240,
        child: WalletTrendChart(
            data: data,
            onInspect: controller.inspectTrendBalance,
            onInspectEnd: controller.endTrendInspection)),
    if (scroll != null) const SizedBox(height: 1200),
  ]);
  await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider<WalletController>.value(
          value: controller,
          child: Scaffold(
              body: scroll == null
                  ? content
                  : SingleChildScrollView(
                      controller: scroll, child: content)))));
  await tester.pump();
}

class _TrendApi extends WalletTestFundApi {
  _TrendApi(this.response);
  final Future<WalletTrendData> response;
  @override
  Future<WalletTrendData> fetchTrend() => response;
}

class _TrendRepo extends UnavailableWalletRepository
    implements WalletTrendSource {
  bool fail = true;
  @override
  Future<WalletDto> getWallet() async =>
      const WalletDto(totalBal: '110.00', trxAddr: '', coins: []);
  @override
  Future<WalletTrendData> getTrend() async {
    if (fail) throw Exception('offline');
    return WalletTrendData(points: [point(1, '110.00')]);
  }
}
