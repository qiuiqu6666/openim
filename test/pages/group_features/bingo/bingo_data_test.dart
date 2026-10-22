import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/bingo/bingo_draw.dart';
import 'package:openim/pages/group_features/bingo/bingo_repository.dart';
import 'package:openim/pages/group_features/bingo/bingo_controller.dart';
import 'package:openim/pages/group_features/bingo/bingo_live_card.dart';
import 'bingo_fixture.dart';

class _Adapter implements HttpClientAdapter {
  Map<String, dynamic>? response;
  RequestOptions? request;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancelFuture) async {
    request = options;
    return ResponseBody.fromString(jsonEncode(response ?? bingoResponse()), 200,
        headers: {
          'content-type': ['application/json']
        });
  }

  @override
  void close({bool force = false}) {}
}

class _Repository extends BingoRepository {
  int calls = 0;
  bool fail = false;
  Completer<BingoDraw>? pending;
  @override
  Future<BingoDraw> fetch() async {
    calls++;
    if (pending != null) return pending!.future;
    if (fail) throw StateError('offline');
    return BingoDraw.fromResponse(bingoResponse());
  }
}

void main() {
  test('final element mapping and 49 tie codes decode from the feed', () {
    final response = bingoResponse();
    final result = Map<String, dynamic>.from(response['data']['result']);
    response['data']['result'] = result;
    for (final entry in {
      '1': '金',
      '2': '木',
      '3': '水',
      '4': '火',
      '5': '土',
      '99': '—'
    }.entries) {
      result['fiveElement7'] = entry.key;
      expect(BingoDraw.fromResponse(response).special.fiveElement, entry.value);
    }
    response['data']['preDrawCode'] = '35,4,32,12,28,30,49';
    result['nums'] = response['data']['preDrawCode'];
    result['bigSmall7'] = 0;
    result['oddEven7'] = '0';
    final draw = BingoDraw.fromResponse(response);
    expect(draw.special.number, 49);
    expect(draw.special.bigSmall, '平');
    expect(draw.special.oddEven, '平');
    result['nums'] = '1,2,3,4,5,6,7';
    result['fiveElement7'] = '3';
    expect(BingoDraw.fromResponse(response).special.fiveElement, '—');
  });
  test('confirmed composite tail and total codes preserve provider meanings',
      () {
    final response = bingoResponse();
    final result = Map<String, dynamic>.from(response['data']['result']);
    response['data']['result'] = result;
    for (final code in ['1', '2', '99']) {
      for (final field in [
        'bigSmallMantissa7',
        'bigSmallComposite7',
        'oddEvenComposite7',
        'sumBigSmall',
        'sumOddEven'
      ]) {
        result[field] = code;
      }
      final draw = BingoDraw.fromResponse(response);
      final index = code == '1'
          ? 0
          : code == '2'
              ? 1
              : 2;
      expect(draw.special.tailSize, ['尾大', '尾小', '—'][index]);
      expect(draw.special.compositeSize, ['合大', '合小', '—'][index]);
      expect(draw.special.compositeParity, ['合单', '合双', '—'][index]);
      expect(draw.sumBigSmall, ['大', '小', '—'][index]);
      expect(draw.sumOddEven, ['单', '双', '—'][index]);
    }
    result['sumBigSmall'] = '1';
    result['bigSmallComposite7'] = '2';
    result['nums'] = '1,2,3,4,5,6,7';
    final mismatched = BingoDraw.fromResponse(response);
    expect(mismatched.sumBigSmall, '—');
    expect(mismatched.special.compositeSize, '—');
  });
  test('provider size and parity codes are mapped only for matching numbers',
      () {
    final response = bingoResponse();
    response['data']['result'] =
        Map<String, dynamic>.from(response['data']['result']);
    for (final code in [1, 2, '1', '2', 99, null]) {
      response['data']['result']['bigSmall7'] = code;
      response['data']['result']['oddEven7'] = code;
      final ball = BingoDraw.fromResponse(response).special;
      expect(
          ball.bigSmall,
          '$code' == '1'
              ? '大'
              : '$code' == '2'
                  ? '小'
                  : '—');
      expect(
          ball.oddEven,
          '$code' == '1'
              ? '单'
              : '$code' == '2'
                  ? '双'
                  : '—');
    }
    response['data']['result']['bigSmall7'] = 1;
    response['data']['result']['oddEven7'] = 1;
    response['data']['result']['nums'] = '1,2,3,4,5,6,7';
    expect(BingoDraw.fromResponse(response).special.bigSmall, '—');
    expect(BingoDraw.fromResponse(response).special.oddEven, '—');
  });
  test('history uses published issue and zero-based pagination', () async {
    final data = bingoResponse()['data'];
    final adapter = _Adapter()
      ..response = {
        'code': 0,
        'data': {
          'pageNum': 0,
          'pageCount': 2,
          'list': [
            {
              'groupCode': 'sixmark',
              'drawIssue': data['preDrawIssue'],
              'drawTime': data['preDrawTime'],
              'drawCode': data['preDrawCode'],
              'result': data['result'],
            }
          ],
        }
      };
    final repository =
        BingoRepository(client: Dio()..httpClientAdapter = adapter);
    addTearDown(repository.dispose);
    final history = await repository.fetchHistory(0);
    expect(history.draws.single.issue, '115059821');
    expect(history.draws.single.special.number, 1);
    expect(history.hasMore, isTrue);
    expect(adapter.request!.queryParameters,
        {'lotCode': '10214', 'pageSize': 100, 'pageNum': 0});
    adapter.response!['data']['pageNum'] = 1;
    expect((await repository.fetchHistory(1)).hasMore, isFalse);
    adapter.response!['data']['list'][0]['drawCode'] = '1,2';
    await expectLater(repository.fetchHistory(1), throwsFormatException);
  });
  test('pairs previous period with seventh special ball and six regulars', () {
    final draw = BingoDraw.fromResponse(bingoResponse());
    expect(draw.issue, '115059821');
    expect(draw.nextIssue, '115059822');
    expect(draw.regular.map((v) => v.number), [35, 4, 32, 12, 28, 30]);
    expect(draw.special.number, 1);
    expect(draw.special.zodiac, '马');
    expect(draw.special.color, Colors.red);
    expect(draw.regular[1].zodiac, '兔');
    expect(draw.regular[1].color, Colors.blue);
    expect(draw.regular[2].color, Colors.green);
    expect(draw.serverTime, DateTime.utc(2026, 10, 22, 10, 38, 20));
    expect(bingoCountdown(draw, draw.serverTime), '开奖 1:40');
    expect(bingoCountdown(draw, draw.closeTime), '等待开奖');
  });

  test('unverified or mismatched attributes are not guessed', () {
    final response = bingoResponse();
    response['data']['result']['zodiac7'] = '99';
    response['data']['result']['ballColor7'] = '99';
    final unknown = BingoDraw.fromResponse(response);
    expect(unknown.special.zodiac, '—');
    expect(unknown.special.color, Colors.grey);
    response['data']['result']['nums'] = '1,2,3,4,5,6,7';
    expect(BingoDraw.fromResponse(response).regular.first.zodiac, '—');
  });

  test('invalid response never falls back to current drawCode', () {
    for (final code in ['', '1,2,3', '1,2,3,4,5,6,50', '1,1,2,3,4,5,6']) {
      final response = bingoResponse();
      response['data']['preDrawCode'] = code;
      response['data']['drawCode'] = '35,4,32,12,28,30,1';
      expect(() => BingoDraw.fromResponse(response), throwsFormatException);
    }
    final other = bingoResponse();
    other['data']['lotCode'] = '10215';
    expect(() => BingoDraw.fromResponse(other), throwsFormatException);
    expect(() => parseBingoTime('2026-02-30 12:00:00'), throwsFormatException);
  });

  test('public client uses exact endpoint and no chat credentials', () async {
    final adapter = _Adapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final repository = BingoRepository(client: dio);
    addTearDown(repository.dispose);
    final draw = await repository.fetch();
    expect(draw.issue, '115059821');
    expect(adapter.request!.uri.toString(),
        '${BingoRepository.endpoint}?lotCode=10214');
    expect(
        adapter.request!.headers.keys.map((k) => k.toLowerCase()),
        isNot(
            contains(anyOf('authorization', 'token', 'cookie', 'x-group-id'))));
  });

  testWidgets('polls only while visible and keeps last good result on failure',
      (tester) async {
    final repository = _Repository();
    final controller =
        BingoController(repository: repository, current: () => true);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: BingoLiveCard(controller: controller, preview: true))));
    await tester.pump();
    expect(find.text('第 115059822 期'), findsOneWidget);
    expect(find.text('01'), findsOneWidget);
    expect(repository.calls, 1);
    repository.fail = true;
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(repository.calls, 2);
    expect(controller.draw!.issue, '115059821');
    expect(controller.error, isNotNull);
    controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 30));
    expect(repository.calls, 2);
    repository.fail = false;
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(repository.calls, 3);
    expect(controller.error, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 30));
    expect(repository.calls, 3);
    expect(tester.takeException(), isNull);
  });

  test('late response after disposal cannot restore stale data', () async {
    final repository = _Repository()..pending = Completer<BingoDraw>();
    final controller =
        BingoController(repository: repository, current: () => true);
    final work = controller.refresh();
    controller.dispose();
    repository.pending!.complete(BingoDraw.fromResponse(bingoResponse()));
    await work;
    expect(controller.draw, isNull);
  });
}
