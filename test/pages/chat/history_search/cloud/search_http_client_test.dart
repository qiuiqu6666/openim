import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history_search/cloud/search_http_client.dart';

void main() {
  test('search clients share one paced queue and skip stale queued work',
      () async {
    final times = <DateTime>[];
    final first = Completer<dynamic>();
    var active = true;
    SearchHttpClient client() => SearchHttpClient(
        paced: true,
        session: () =>
            (user: 'self', token: 'im', server: 'https://example.test'),
        post: (_, __, ___) async {
          times.add(DateTime.now());
          if (times.length == 1) return first.future;
          return {'errCode': 0, 'data': <String, dynamic>{}};
        });
    final a = client().request('/msg/search_messages', {});
    final b = client().request('/msg/search_message_context', {});
    final c = client()
        .request('/msg/search_messages_global', {}, isCurrent: () => active);
    final cancelled = expectLater(c, throwsA(isA<SearchApiException>()));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(times.length, 1);
    active = false;
    first.complete({'errCode': 0, 'data': <String, dynamic>{}});
    await Future.wait([a, b]);
    await cancelled;
    expect(times.length, 2);
    expect(times[1].difference(times[0]).inMilliseconds,
        greaterThanOrEqualTo(1000));
  });
}
