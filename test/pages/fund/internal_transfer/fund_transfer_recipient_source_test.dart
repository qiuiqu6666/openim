import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/contacts/search/contact_search_source.dart';
import 'package:openim/pages/fund/internal_transfer/data/fund_transfer_recipient_source.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/utils/http_util.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class _Search extends ContactSearchSource {
  final queries = <({String keyword, int page, int? way})>[];
  List<UserFullInfo>? usersToReturn = [];
  Future<List<UserFullInfo>?> Function()? response;

  @override
  Future<List<UserFullInfo>?> users(String keyword, int page,
      {int? way}) async {
    queries.add((keyword: keyword, page: page, way: way));
    return response != null ? await response!() : usersToReturn;
  }
}

class _Session {
  String owner = 'sender',
      token = 'chat-token',
      server = 'https://chat.example';

  FundTransferRecipientSource source(_Search search,
          {Future<List<UserFullInfo>?> Function(String)? uidLoader}) =>
      FundTransferRecipientSource(
          source: search,
          uidLoader: uidLoader,
          owner: () => owner,
          tokenProvider: () => token,
          serverProvider: () => server);
}

class _HTTP implements HttpClientAdapter {
  _HTTP({this.users = const []});

  final List<Map<String, dynamic>> users;
  RequestOptions? request;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? body,
      Future<void>? cancel) async {
    request = options;
    return ResponseBody.fromString(
      jsonEncode({
        'errCode': 0,
        'data': {'users': users}
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      },
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('UID loads the exact IM profile without account search', () async {
    final search = _Search();
    final queried = <String>[];
    final source = _Session().source(search, uidLoader: (uid) async {
      queried.add(uid);
      return [
        UserFullInfo(userID: 'other-id', account: '@im_receiver'),
        UserFullInfo(
            userID: 'im_receiver',
            nickname: ' 收款人 ',
            faceURL: ' https://images.example/avatar.png ',
            account: '@abcdefgh12'),
      ];
    });
    final recipient =
        await source.resolve(FundTransferAccountType.uid, ' im_receiver ');
    expect(queried, ['im_receiver']);
    expect(search.queries, isEmpty);
    expect(recipient.userID, 'im_receiver');
    expect(recipient.nickname, '收款人');
    expect(recipient.faceURL, 'https://images.example/avatar.png');
    expect(recipient.account, '@abcdefgh12');
  });

  for (final uid in ['', '   ', 'im receiver']) {
    test('invalid UID $uid is rejected before profile API access', () async {
      var loads = 0;
      final source = _Session().source(_Search(), uidLoader: (_) async {
        ++loads;
        return [];
      });
      await expectLater(source.resolve(FundTransferAccountType.uid, uid),
          throwsA(isA<FormatException>()));
      expect(loads, 0);
    });
  }

  for (final users in <List<UserFullInfo>?>[
    null,
    [],
    [UserFullInfo(userID: 'im_other', nickname: 'im_receiver')],
    [UserFullInfo(userID: 'IM_receiver')],
  ]) {
    test('UID refuses a missing or different exact IM ID', () async {
      final source =
          _Session().source(_Search(), uidLoader: (_) async => users);
      await expectLater(
          source.resolve(FundTransferAccountType.uid, 'im_receiver'),
          throwsA(isA<FormatException>()));
    });
  }

  for (final user in [
    UserFullInfo(userID: 'sender'),
    UserFullInfo(userID: '99Pay'),
    UserFullInfo(userID: 'custom-service', ex: '{"accountType":"official"}'),
  ]) {
    test('UID rejects self or official profile ${user.userID}', () async {
      final source =
          _Session().source(_Search(), uidLoader: (_) async => [user]);
      await expectLater(
          source.resolve(FundTransferAccountType.uid, user.userID!),
          throwsA(isA<FormatException>().having((e) => e.message, 'message',
              contains(user.userID == 'sender' ? '自己' : '官方账号'))));
    });
  }

  for (final action in ['cancel', 'close', 'owner', 'token', 'server']) {
    test('UID cannot return a late profile after $action', () async {
      final reply = Completer<List<UserFullInfo>?>();
      final session = _Session();
      final source = session.source(_Search(), uidLoader: (_) => reply.future);
      final result = source.resolve(FundTransferAccountType.uid, 'im_receiver');
      final rejected = expectLater(result, throwsA(isA<StateError>()));
      switch (action) {
        case 'cancel':
          source.cancel();
        case 'close':
          source.close();
        case 'owner':
          session.owner = 'different-sender';
        case 'token':
          session.token = 'different-token';
        case 'server':
          session.server = 'https://different.example';
      }
      reply.complete([UserFullInfo(userID: 'im_receiver')]);
      await rejected;
    });
  }

  test('email preserves case and resolves only an exact profile', () async {
    final search = _Search()
      ..usersToReturn = [
        UserFullInfo(userID: 'wrong', email: 'alice2@example.com'),
        UserFullInfo(
            userID: ' im_receiver ',
            email: 'Alice@Example.COM',
            nickname: ' 小明 ',
            faceURL: ' https://images.example/avatar.png ',
            account: '@abcdefgh12'),
      ];
    final recipient = await _Session()
        .source(search)
        .resolve(FundTransferAccountType.email, ' Alice@Example.COM ');
    expect(recipient.userID, 'im_receiver');
    expect(recipient.nickname, '小明');
    expect(recipient.faceURL, 'https://images.example/avatar.png');
    expect(recipient.account, '@abcdefgh12');
    expect(
        search.queries.single, (keyword: 'Alice@Example.COM', page: 1, way: 3));
  });

  test('a ten-digit phone explicitly requests phone search', () async {
    final search = _Search()
      ..usersToReturn = [
        UserFullInfo(
            userID: 'im_receiver', phoneNumber: '0012345678', areaCode: '+86')
      ];
    final recipient = await _Session()
        .source(search)
        .resolve(FundTransferAccountType.phone, '00 1234-5678');
    expect(recipient.userID, 'im_receiver');
    expect(search.queries.single, (keyword: '0012345678', page: 1, way: 2));
  });

  test('international phone matches the exact stored area code and number',
      () async {
    final search = _Search()
      ..usersToReturn = [
        UserFullInfo(
            userID: 'wrong-country', phoneNumber: '912345678', areaCode: '+86'),
        UserFullInfo(
            userID: 'im_receiver', phoneNumber: '912345678', areaCode: '+886'),
      ];
    final recipient = await _Session().source(search).resolve(
        FundTransferAccountType.phone, '+886 (912) 345-678',
        areaCode: '+886');
    expect(recipient.userID, 'im_receiver');
    expect(search.queries.single.keyword, '912345678');
    expect(search.queries.single.way, 2);
  });

  test('selected phone area filters identical national numbers by country',
      () async {
    final search = _Search()
      ..usersToReturn = [
        UserFullInfo(
            userID: 'wrong-country', phoneNumber: '912345678', areaCode: '+86'),
        UserFullInfo(
            userID: 'im_receiver', phoneNumber: '912345678', areaCode: '886'),
      ];
    final recipient = await _Session().source(search).resolve(
        FundTransferAccountType.phone, '(912) 345-678',
        areaCode: '+886');
    expect(recipient.userID, 'im_receiver');
    expect(search.queries.single, (keyword: '912345678', page: 1, way: 2));
  });

  test('explicit international input uses national phone search with area',
      () async {
    final search = _Search()
      ..usersToReturn = [
        UserFullInfo(userID: 'im_receiver', phoneNumber: '+8618828838848')
      ];
    final recipient = await _Session().source(search).resolve(
        FundTransferAccountType.phone, '+86 (188) 2883-8848',
        areaCode: '86');
    expect(recipient.userID, 'im_receiver');
    expect(search.queries.single, (keyword: '18828838848', page: 1, way: 2));
  });

  test('selected area matches mobileAreaCode when areaCode is empty', () async {
    final search = _Search()
      ..usersToReturn = [
        UserFullInfo(
            userID: 'im_receiver',
            phoneNumber: '18828838848',
            areaCode: '',
            mobileAreaCode: '+86')
      ];
    final recipient = await _Session()
        .source(search)
        .resolve(FundTransferAccountType.phone, '18828838848', areaCode: '+86');
    expect(recipient.userID, 'im_receiver');
  });

  for (final user in [
    UserFullInfo(
        userID: 'wrong-country', phoneNumber: '912345678', areaCode: '86'),
    UserFullInfo(userID: 'unknown-country', phoneNumber: '912345678'),
    UserFullInfo(userID: 'international-other', phoneNumber: '+86912345678'),
    UserFullInfo(
        userID: 'inconsistent', phoneNumber: '+886912345678', areaCode: '+86'),
  ]) {
    test('selected area refuses mismatched or unverified area ${user.userID}',
        () async {
      final search = _Search()..usersToReturn = [user];
      await expectLater(
          _Session().source(search).resolve(
              FundTransferAccountType.phone, '912345678',
              areaCode: '+886'),
          throwsA(isA<FormatException>()));
      expect(search.queries.single, (keyword: '912345678', page: 1, way: 2));
    });
  }

  for (final phone in [
    (value: '18828838848', area: ''),
    (value: '18828838848', area: 'invalid'),
    (value: '+886912345678', area: '+86'),
    (value: '123456789012345', area: '+86'),
  ]) {
    test('invalid selected phone or area is rejected before search $phone',
        () async {
      final search = _Search();
      await expectLater(
          _Session().source(search).resolve(
              FundTransferAccountType.phone, phone.value,
              areaCode: phone.area),
          throwsA(isA<FormatException>()));
      expect(search.queries, isEmpty);
    });
  }

  test('public account resolves an exact account rather than a display ID',
      () async {
    final search = _Search()
      ..usersToReturn = [
        UserFullInfo(userID: 'abcdefgh12', account: '@otheruser1'),
        UserFullInfo(userID: 'im_receiver', account: '@abcdefgh12'),
      ];
    final recipient = await _Session()
        .source(search)
        .resolve(FundTransferAccountType.account, 'abcdefgh12');
    expect(recipient.userID, 'im_receiver');
    expect(search.queries.single, (keyword: '@abcdefgh12', page: 1, way: null));
  });

  for (final entry in [
    (type: FundTransferAccountType.email, input: ''),
    (type: FundTransferAccountType.email, input: 'invalid-email'),
    (type: FundTransferAccountType.phone, input: '123'),
    (type: FundTransferAccountType.phone, input: '+886 abc'),
    (type: FundTransferAccountType.account, input: 'short'),
    (type: FundTransferAccountType.account, input: 'im_receiver'),
  ]) {
    test('invalid ${entry.type.name} input never sends a query: ${entry.input}',
        () async {
      final search = _Search();
      await expectLater(
          _Session().source(search).resolve(entry.type, entry.input),
          throwsA(isA<FormatException>()));
      expect(search.queries, isEmpty);
    });
  }

  for (final entry in [
    (
      type: FundTransferAccountType.email,
      input: 'alice@example.com',
      user: UserFullInfo(userID: 'receiver', email: 'a***@example.com')
    ),
    (
      type: FundTransferAccountType.phone,
      input: '18828838848',
      user: UserFullInfo(userID: 'receiver', phoneNumber: '188****8848')
    ),
    (
      type: FundTransferAccountType.account,
      input: '@abcdefgh12',
      user: UserFullInfo(userID: 'abcdefgh12', nickname: 'abcdefgh12')
    ),
  ]) {
    test('${entry.type.name} refuses hidden or unverified identity fields',
        () async {
      final search = _Search()..usersToReturn = [entry.user];
      await expectLater(
          _Session().source(search).resolve(entry.type, entry.input),
          throwsA(isA<FormatException>()));
    });
  }

  for (final response in <List<UserFullInfo>?>[
    null,
    [],
    [UserFullInfo(userID: '', email: 'alice@example.com')],
    [UserFullInfo(userID: 'receiver', email: 'other@example.com')],
  ]) {
    test('missing exact recipient fails instead of fabricating an IM ID',
        () async {
      final search = _Search()..usersToReturn = response;
      await expectLater(
          _Session()
              .source(search)
              .resolve(FundTransferAccountType.email, 'alice@example.com'),
          throwsA(isA<FormatException>()));
    });
  }

  test('different IM IDs matching one account are rejected', () async {
    final search = _Search()
      ..usersToReturn = [
        UserFullInfo(userID: 'receiver-1', email: 'alice@example.com'),
        UserFullInfo(userID: 'receiver-2', email: 'alice@example.com'),
      ];
    await expectLater(
        _Session()
            .source(search)
            .resolve(FundTransferAccountType.email, 'alice@example.com'),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('不唯一'))));
  });

  test('duplicate profiles with the same exact IM ID are deduplicated',
      () async {
    final user = UserFullInfo(userID: 'receiver', email: 'alice@example.com');
    final search = _Search()..usersToReturn = [user, user];
    final recipient = await _Session()
        .source(search)
        .resolve(FundTransferAccountType.email, 'alice@example.com');
    expect(recipient.userID, 'receiver');
  });

  test('self transfer is rejected using the resolved IM ID', () async {
    final search = _Search()
      ..usersToReturn = [
        UserFullInfo(userID: 'sender', account: '@abcdefgh12')
      ];
    await expectLater(
        _Session()
            .source(search)
            .resolve(FundTransferAccountType.account, '@abcdefgh12'),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('自己'))));
  });

  for (final id in ['99Message', '99Pay', 'assistant']) {
    test('matching email cannot resolve reserved official recipient $id',
        () async {
      final search = _Search()
        ..usersToReturn = [
          UserFullInfo(userID: id, email: 'service@example.com')
        ];
      await expectLater(
          _Session()
              .source(search)
              .resolve(FundTransferAccountType.email, 'service@example.com'),
          throwsA(isA<FormatException>()
              .having((e) => e.message, 'message', contains('官方账号'))));
      expect(
          search.queries, [(keyword: 'service@example.com', page: 1, way: 3)]);
    });
  }

  for (final role in ['assistant', 'unknown']) {
    test('matching email rejects official metadata with $role role', () async {
      final search = _Search()
        ..usersToReturn = [
          UserFullInfo(
              userID: 'custom-service',
              email: 'service@example.com',
              ex: '{"accountType":"official","officialRole":"$role"}')
        ];
      await expectLater(
          _Session()
              .source(search)
              .resolve(FundTransferAccountType.email, 'service@example.com'),
          throwsA(isA<FormatException>()
              .having((e) => e.message, 'message', contains('官方账号'))));
      expect(
          search.queries, [(keyword: 'service@example.com', page: 1, way: 3)]);
    });
  }

  for (final name in ['99Pay', 'AI助理']) {
    test('ordinary user named $name resolves without extra identity requests',
        () async {
      final search = _Search()
        ..usersToReturn = [
          UserFullInfo(
              userID: 'personal-recipient',
              email: 'friend@example.com',
              nickname: name,
              ex: '{"accountType":"user"}')
        ];
      final recipient = await _Session()
          .source(search)
          .resolve(FundTransferAccountType.email, 'friend@example.com');
      expect(recipient.userID, 'personal-recipient');
      expect(recipient.nickname, name);
      expect(
          search.queries, [(keyword: 'friend@example.com', page: 1, way: 3)]);
    });
  }

  for (final field in ['owner', 'token', 'server']) {
    test('late result after $field changes cannot supply a recipient',
        () async {
      final reply = Completer<List<UserFullInfo>?>();
      final search = _Search()..response = () => reply.future;
      final session = _Session();
      final source = session.source(search);
      final pending =
          source.resolve(FundTransferAccountType.email, 'alice@example.com');
      final assertion = expectLater(pending, throwsA(isA<StateError>()));
      switch (field) {
        case 'owner':
          session.owner = 'other-sender';
        case 'token':
          session.token = 'new-token';
        case 'server':
          session.server = 'https://other-chat.example';
      }
      reply.complete(
          [UserFullInfo(userID: 'receiver', email: 'alice@example.com')]);
      await assertion;
      expect(source.isCurrentSession, isFalse);
    });
  }

  test('a session already changed rejects before network access', () async {
    final search = _Search();
    final session = _Session();
    final source = session.source(search);
    session.owner = 'another-sender';
    await expectLater(
        source.resolve(FundTransferAccountType.email, 'alice@example.com'),
        throwsA(isA<StateError>()));
    expect(search.queries, isEmpty);
  });

  test('cancelled lookup cannot return a recipient; a new lookup can',
      () async {
    final reply = Completer<List<UserFullInfo>?>();
    final search = _Search()..response = () => reply.future;
    final source = _Session().source(search);
    final pending =
        source.resolve(FundTransferAccountType.email, 'alice@example.com');
    final assertion = expectLater(pending, throwsA(isA<StateError>()));
    source.cancel();
    reply.complete(
        [UserFullInfo(userID: 'receiver', email: 'alice@example.com')]);
    await assertion;
    search.response = null;
    search.usersToReturn = [
      UserFullInfo(userID: 'receiver', email: 'alice@example.com')
    ];
    final recipient = await source.resolve(
        FundTransferAccountType.email, 'alice@example.com');
    expect(recipient.userID, 'receiver');
  });

  test('a newer lookup invalidates an earlier in-flight result', () async {
    final first = Completer<List<UserFullInfo>?>();
    final second = Completer<List<UserFullInfo>?>();
    var request = 0;
    final search = _Search()
      ..response = () => ++request == 1 ? first.future : second.future;
    final source = _Session().source(search);
    final old =
        source.resolve(FundTransferAccountType.email, 'old@example.com');
    final rejected = expectLater(old, throwsA(isA<StateError>()));
    final next =
        source.resolve(FundTransferAccountType.email, 'new@example.com');
    first.complete(
        [UserFullInfo(userID: 'old-receiver', email: 'old@example.com')]);
    second.complete(
        [UserFullInfo(userID: 'new-receiver', email: 'new@example.com')]);
    await rejected;
    expect((await next).userID, 'new-receiver');
  });

  test('closed source rejects before network access', () async {
    final search = _Search();
    final source = _Session().source(search)..close();
    await expectLater(
        source.resolve(FundTransferAccountType.email, 'alice@example.com'),
        throwsA(isA<StateError>()));
    expect(search.queries, isEmpty);
  });

  test('network failures remain failures rather than a false no-match',
      () async {
    final failure = StateError('network unavailable');
    final search = _Search()
      ..response = () => Future<List<UserFullInfo>?>.error(failure);
    await expectLater(
        _Session()
            .source(search)
            .resolve(FundTransferAccountType.email, 'alice@example.com'),
        throwsA(same(failure)));
  });

  test('transport explicit phone way overrides ten-digit account detection',
      () async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    final originalDio = http.dio;
    http.dio = Dio();
    HttpUtil.init();
    final adapter = _HTTP();
    http.dio.httpClientAdapter = adapter;
    try {
      await ContactSearchSource().users('0012345678', 1, way: 2);
      expect(adapter.request?.data, {
        'pagination': {'pageNumber': 1, 'showNumber': 20},
        'keyword': '0012345678',
        'way': 2,
      });
    } finally {
      http.dio.close(force: true);
      http.dio = originalDio;
    }
  });

  test('default UID transport calls authenticated exact-profile API', () async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'sender',
      'chatToken': 'chat-token',
      'imToken': 'im-token',
    }));
    final originalDio = http.dio;
    http.dio = Dio();
    HttpUtil.init();
    final adapter = _HTTP(users: [
      {'userID': 'im_receiver', 'nickname': '收款人'},
    ]);
    http.dio.httpClientAdapter = adapter;
    try {
      final source = _Session().source(_Search());
      final recipient =
          await source.resolve(FundTransferAccountType.uid, 'im_receiver');
      expect(recipient.userID, 'im_receiver');
      expect(adapter.request?.uri.path, endsWith('/user/find/full'));
      expect(adapter.request?.headers['token'], 'chat-token');
      final data = adapter.request?.data as Map;
      expect(data['userIDs'], ['im_receiver']);
      expect(data['pagination'], {'pageNumber': 0, 'showNumber': 10});
      expect(data.containsKey('keyword'), isFalse);
      expect(data.containsKey('way'), isFalse);
    } finally {
      http.dio.close(force: true);
      http.dio = originalDio;
      await DataSp.removeLoginCertificate();
    }
  });
}
