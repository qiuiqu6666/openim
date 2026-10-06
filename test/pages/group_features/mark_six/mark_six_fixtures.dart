import 'dart:async';
import 'package:dio/dio.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';

typedef MarkSixResponse = FutureOr<Map<String, dynamic>> Function(String method,
    String path, Map<String, dynamic> query, Map<String, dynamic> body);

/// Server fixtures exist only in tests, never in the production module.
class MarkSixFakeApi extends GroupFeatureApi {
  MarkSixFakeApi({this.respond});
  MarkSixResponse? respond;
  final calls = <({
    String method,
    String path,
    Map<String, dynamic> query,
    Map<String, dynamic> body,
    Map<String, dynamic> headers
  })>[];
  Future<Map<String, dynamic>> _call(
      String method,
      String path,
      Map<String, dynamic>? query,
      Map<String, dynamic>? body,
      Map<String, dynamic>? headers) async {
    final q = {...?query}, b = {...?body};
    calls.add((
      method: method,
      path: path,
      query: q,
      body: b,
      headers: {...?headers}
    ));
    return respond == null
        ? markSixFixtureResponse(path, q)
        : await respond!(method, path, q, b);
  }

  @override
  Future<Map<String, dynamic>> get(String path,
          {Map<String, dynamic>? query,
          Map<String, dynamic>? headers,
          CancelToken? cancelToken}) =>
      _call('GET', path, query, null, headers);
  @override
  Future<Map<String, dynamic>> getEnvelope(String path,
          {Map<String, dynamic>? query,
          Map<String, dynamic>? headers,
          CancelToken? cancelToken}) =>
      _call('GET', path, query, null, headers);
  @override
  Future<Map<String, dynamic>> post(String path,
          {Map<String, dynamic>? body,
          Map<String, dynamic>? query,
          Map<String, dynamic>? headers,
          CancelToken? cancelToken}) =>
      _call('POST', path, query, body, headers);
}

GroupFeatureContext markSixContext(MarkSixFakeApi api,
        {bool Function()? sessionCurrent,
        bool Function()? capabilitiesCurrent,
        bool enabled = true,
        bool agent = true,
        String machine = 'machine-test',
        int revision = 1,
        Stream<Map<String, dynamic>> events = const Stream.empty()}) =>
    GroupFeatureContext(
      groupID: 'group-test',
      groupName: '极速六合彩',
      currentUserID: 'self',
      api: api,
      sessionCurrent: sessionCurrent ?? () => true,
      capabilitiesCurrent: capabilitiesCurrent ?? () => true,
      onFeaturesChanged: (_) {},
      events: events,
      features: GroupFeatures(
          revision: revision,
          valid: true,
          markSix: GroupGameFeature(
              enabled: enabled,
              drawHistoryEntry: true,
              agentEntry: agent,
              rebateHistoryEntry: agent,
              machineCode: machine)),
      capabilities: GroupFeatureCapabilities(
          markSix: GroupGameCapabilities(
              canOpenAgent: agent,
              canViewRebateHistory: agent,
              machineCode: machine)),
    );

Map<String, dynamic> markSixFixtureDraw(int issue, {String wave = '红'}) => {
      'issue': '$issue',
      'issueLabel': '$issue',
      'sequence': issue,
      'status': 'drawn',
      'drawAt': DateTime.utc(2026, 10, 4, 10, 30).millisecondsSinceEpoch -
          issue * 60000,
      'attributes': {
        'special': '08',
        'zodiac': '马',
        'parity': '双',
        'size': '小',
        'head': '0',
        'tail': '8',
        'sumParity': '双',
        'fiveElement': '土',
        'wave': wave
      },
    };

const markSixFixtureSummary = <String, dynamic>{
  'agentName': '团队汇总',
  'agentNo': '1008',
  'agentCount': 3,
  'playerCount': 18,
  'totalBalance': 12680.5,
  'totalFlow': 268500,
  'playerProfitLoss': -1250,
  'platformProfitLoss': 1250,
  'totalUp': 26800,
  'totalDown': 18200,
  'totalRebated': 1850,
  'pendingRebate': 180,
  'agentPendingRebate': 120,
};

Map<String, dynamic> markSixFixtureResponse(
    String path, Map<String, dynamic> query) {
  if (path.endsWith('/apply/status')) return {'status': 'NONE'};
  if (path.endsWith('/config')) {
    return {
      'code': 'OK',
      'groupUid': 'game-test',
      'serverTime': DateTime.utc(2026, 10, 4, 10, 31).millisecondsSinceEpoch,
      'data': {
        'windowOptions': [6, 12, 20, 30, 40],
        'declaration': '本群信息以实际开奖结果为准。\n请理性参与，及时查看历史记录。'
      }
    };
  }
  if (path.endsWith('/draws')) {
    return {
      'code': 'OK',
      'groupUid': 'game-test',
      'serverTime': DateTime.utc(2026, 10, 4, 10, 31).millisecondsSinceEpoch,
      'data': [
        for (var i = 108; i > 98; i--)
          markSixFixtureDraw(i, wave: ['红', '蓝', '绿'][i % 3])
      ]
    };
  }
  if (path.endsWith('/predictions')) {
    return {
      'code': 'OK',
      'groupUid': 'game-test',
      'data': {
        'window': query['window'],
        'page': query['page'],
        'pageSize': 20,
        'returnedCount': 1,
        'totalCount': 1,
        'hasMore': false,
        'mode': 'all',
        'items': [
          {
            'issue': '109',
            'items': [
              {
                'attribute': 'special',
                'values': ['08', '12', '23'],
                'result': 'pending'
              }
            ]
          }
        ]
      }
    };
  }
  if (path == '/chat/platform') {
    return {'downloadURL': 'https://example.invalid/app'};
  }
  if (path.endsWith('/current')) {
    return {
      'userId': 'self',
      'summary': {...markSixFixtureSummary},
      'personal': {
        'balance': 520,
        'totalFlow': 12600,
        'totalProfitLoss': -280,
        'totalRebate': 120,
        'pendingRebate': 28,
        'agentPendingRebate': 120
      }
    };
  }
  if (path.endsWith('/history') || path.endsWith('/personal-history')) {
    return {
      'userId': 'self',
      'startDate': query['startDate'],
      'endDate': query['endDate'],
      'days': [
        {'businessDate': query['startDate'], ...markSixFixtureSummary}
      ],
      'total': {...markSixFixtureSummary}
    };
  }
  if (path.endsWith('/descendants')) {
    return {
      'userId': 'self',
      'page': query['page'],
      'scope': query['scope'],
      'total': 2,
      'hasMore': false,
      'items': [
        {
          'userId': 'child-1',
          'displayName': '小林',
          'playerNo': '1009',
          'directParentUserId': 'self',
          'balance': 860,
          'totalFlow': 23800,
          'playerProfitLoss': -320
        },
        {
          'userId': 'child-2',
          'displayName': '小秋',
          'playerNo': '1010',
          'directParentUserId': 'child-1',
          'balance': 520,
          'totalFlow': 16800,
          'playerProfitLoss': 180
        }
      ]
    };
  }
  throw StateError('No fixture for $path');
}
