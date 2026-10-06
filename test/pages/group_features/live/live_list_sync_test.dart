import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';
import 'package:openim/pages/group_features/live/data/live_list_sync.dart';

import 'live_test_support.dart';

Map<String, dynamic> _current(String group,
        {bool active = true, String status = 'AUTHORIZED', int? revision}) =>
    {
      'active': active,
      if (active) 'session': {...liveDTO(status: status), 'groupId': group},
      if (revision != null) 'groupFeatures': _summary(revision, status: status),
    };

Map<String, dynamic> _summary(int revision, {String status = 'AUTHORIZED'}) => {
      'schemaVersion': 1,
      'revision': revision,
      'live': {
        'sessionID': 'live-1',
        'status': status == 'LIVE' ? 'live' : 'ready',
      },
    };

String _group(RequestOptions request) =>
    Uri.decodeComponent(request.uri.pathSegments[4]);

class _Fixture {
  _Fixture(FakeAsync time,
      FutureOr<Map<String, dynamic>> Function(RequestOptions) response) {
    transport = LiveTransport(response);
    store = GroupFeatureStore(
      api: transport.api(),
      sessionCurrent: () => session,
      fetchGroups: (_) async => [],
    );
    sync = GroupLiveListSync(
      store: store,
      userID: 'self',
      sessionCurrent: () => session,
      clock: () => DateTime(2026, 10, 5).add(time.elapsed),
    );
  }
  bool session = true;
  late final LiveTransport transport;
  late final GroupFeatureStore store;
  late final GroupLiveListSync sync;
  List<RequestOptions> get reads => transport.requests
      .where((request) => request.path.endsWith('/live/current'))
      .toList();

  void event(String group, {String key = 'groupLiveChanged', int? revision}) =>
      store.receiveBusiness(
        '{"key":"$key","data":{"groupID":"$group"${revision == null ? '' : ',"groupFeatures":{"schemaVersion":1,"revision":$revision,"live":{"sessionID":"live-1","status":"live"}}'}}}',
      );

  void dispose() {
    sync.dispose();
    store.dispose();
  }
}

void _run(
  FutureOr<Map<String, dynamic>> Function(RequestOptions) handler,
  void Function(FakeAsync time, _Fixture fixture) body,
) {
  fakeAsync((time) {
    final fixture = _Fixture(time, handler);
    try {
      body(time, fixture);
    } finally {
      fixture.dispose();
      _flush(time);
      expect(time.pendingTimers, isEmpty);
    }
  });
}

void _flush(FakeAsync time) {
  for (var i = 0; i < 5; i++) {
    time.flushMicrotasks();
    time.elapse(Duration.zero);
  }
  time.flushMicrotasks();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('visible groups load when the list becomes active, without credentials',
      () {
    _run((request) => _current(_group(request)), (time, fixture) {
      fixture.sync.setVisible('row', 'group#1', true);
      _flush(time);
      expect(fixture.reads, isEmpty);
      fixture.sync.setActive(true);
      _flush(time);
      expect(fixture.reads, hasLength(1));
      expect(fixture.store.liveFeature('group#1').status, 'ready');
      expect(fixture.transport.requests, hasLength(1));
    });
  });

  test('becoming visible after activation starts one read shared by both rows',
      () {
    late Completer<Map<String, dynamic>> reply;
    _run((_) => reply.future, (time, fixture) {
      reply = Completer<Map<String, dynamic>>();
      fixture.sync.setActive(true);
      _flush(time);
      expect(fixture.reads, isEmpty);
      fixture.sync.setVisible('first', 'group#1', true);
      fixture.sync.setVisible('second', 'group#1', true);
      _flush(time);
      fixture.sync.refreshVisible();
      _flush(time);
      expect(fixture.reads, hasLength(1));
      fixture.sync.setVisible('first', 'group#1', false);
      expect(fixture.reads.single.cancelToken!.isCancelled, isFalse);
      fixture.sync.setVisible('second', 'group#1', false);
      expect(fixture.reads.single.cancelToken!.isCancelled, isTrue);
      reply.complete(_current('group#1'));
      _flush(time);
      expect(fixture.store.liveFeature('group#1').isActive, isFalse);
    });
  });

  test(
      'a true no-live response clears an old badge without a fabricated summary',
      () {
    _run((_) => _current('group#1', active: false), (time, fixture) {
      fixture.store.apply('group#1', _summary(8));
      fixture.sync.setVisible('row', 'group#1', true);
      fixture.sync.setActive(true);
      _flush(time);
      expect(fixture.store.liveFeature('group#1').isActive, isFalse);
      expect(fixture.store.features('group#1').revision, 8);
      expect(fixture.store.features('group#1').live.isActive, isTrue);
    });
  });

  test(
      'a current response publishing its full summary does not query itself again',
      () {
    _run((_) => _current('group#1', revision: 2), (time, fixture) {
      fixture.sync.setVisible('row', 'group#1', true);
      fixture.sync.setActive(true);
      _flush(time);
      time.elapse(const Duration(seconds: 1));
      _flush(time);
      expect(fixture.reads, hasLength(1));
      expect(fixture.store.features('group#1').revision, 2);
    });
  });

  test(
      'incomplete business notices are directed and merge over 250 milliseconds',
      () {
    var live = false;
    _run(
        (request) =>
            _current(_group(request), status: live ? 'LIVE' : 'AUTHORIZED'),
        (time, fixture) {
      fixture.sync.setVisible('row', 'group#1', true);
      fixture.sync.setActive(true);
      _flush(time);
      fixture.event('other');
      fixture.event('group#1');
      fixture.event('group#1', key: 'groupFeatureCapabilitiesChanged');
      fixture.event('group#1', key: 'groupFeaturesChanged');
      _flush(time);
      time.elapse(const Duration(milliseconds: 249));
      _flush(time);
      expect(fixture.reads, hasLength(1));
      live = true;
      time.elapse(const Duration(milliseconds: 1));
      _flush(time);
      expect(fixture.reads, hasLength(2));
      expect(fixture.store.liveFeature('group#1').status, 'live');
    });
  });

  test('many notices during an in-flight read cause one follow-up', () {
    late Completer<Map<String, dynamic>> reply;
    var calls = 0;
    _run(
        (_) =>
            ++calls == 1 ? reply.future : _current('group#1', status: 'LIVE'),
        (time, fixture) {
      reply = Completer<Map<String, dynamic>>();
      fixture.sync.setVisible('row', 'group#1', true);
      fixture.sync.setActive(true);
      _flush(time);
      for (var i = 0; i < 20; i++) {
        fixture.event('group#1');
      }
      _flush(time);
      time.elapse(const Duration(seconds: 1));
      _flush(time);
      expect(fixture.reads, hasLength(1));
      reply.complete(_current('group#1'));
      _flush(time);
      expect(fixture.store.liveFeature('group#1').status, 'ready');
      time.elapse(const Duration(milliseconds: 250));
      _flush(time);
      expect(fixture.reads, hasLength(2));
      time.elapse(const Duration(seconds: 1));
      _flush(time);
      expect(fixture.reads, hasLength(2));
    });
  });

  test(
      'complete newer business summary updates the badge without a current query',
      () {
    _run((_) => _current('group#1'), (time, fixture) {
      fixture.sync.setVisible('row', 'group#1', true);
      fixture.sync.setActive(true);
      _flush(time);
      fixture.event('group#1', revision: 10);
      _flush(time);
      time.elapse(const Duration(seconds: 1));
      _flush(time);
      expect(fixture.reads, hasLength(1));
      expect(fixture.store.liveFeature('group#1').status, 'live');
    });
  });

  test('polling runs only while a group is visible in an active list', () {
    _run((request) => _current(_group(request)), (time, fixture) {
      fixture.sync.setVisible('row', 'group#1', true);
      fixture.sync.setActive(true);
      _flush(time);
      time.elapse(const Duration(seconds: 45));
      _flush(time);
      expect(fixture.reads, hasLength(2));
      fixture.sync.setVisible('row', 'group#1', false);
      time.elapse(const Duration(minutes: 2));
      _flush(time);
      expect(fixture.reads, hasLength(2));
      fixture.sync.setVisible('row', 'group#1', true);
      _flush(time);
      expect(fixture.reads, hasLength(3));
      fixture.sync.setActive(false);
      time.elapse(const Duration(minutes: 2));
      _flush(time);
      expect(fixture.reads, hasLength(3));
      fixture.sync.setActive(true);
      _flush(time);
      expect(fixture.reads, hasLength(4));
    });
  });

  test('brief row visibility changes reuse the success cache', () {
    _run((_) => _current('group#1'), (time, fixture) {
      fixture.sync.setVisible('row', 'group#1', true);
      fixture.sync.setActive(true);
      _flush(time);
      for (var i = 0; i < 100; i++) {
        fixture.sync.setVisible('row', 'group#1', false);
        fixture.sync.setVisible('row', 'group#1', true);
        _flush(time);
      }
      expect(fixture.reads, hasLength(1));
      time.elapse(const Duration(seconds: 46));
      fixture.sync.setVisible('row', 'group#1', false);
      fixture.sync.setVisible('row', 'group#1', true);
      _flush(time);
      expect(fixture.reads, hasLength(2));
    });
  });

  test('returning to an initially empty visible scope refreshes the first row',
      () {
    _run((_) => _current('group#1'), (time, fixture) {
      fixture.sync.setVisible('row', 'group#1', true);
      fixture.sync.setActive(true);
      _flush(time);
      expect(fixture.reads, hasLength(1));
      fixture.sync.setVisible('row', 'group#1', false);
      fixture.sync.setActive(false);
      fixture.sync.setActive(true);
      _flush(time);
      expect(fixture.reads, hasLength(1));
      fixture.sync.setVisible('row', 'group#1', true);
      _flush(time);
      expect(fixture.reads, hasLength(2));
    });
  });

  test('queue never exceeds two concurrent group requests', () {
    final replies = <String, Completer<Map<String, dynamic>>>{};
    var inFlight = 0, highest = 0;
    _run((request) async {
      inFlight++;
      if (inFlight > highest) highest = inFlight;
      final reply = Completer<Map<String, dynamic>>();
      replies[_group(request)] = reply;
      try {
        return await reply.future;
      } finally {
        inFlight--;
      }
    }, (time, fixture) {
      fixture.sync.setActive(true);
      for (var i = 0; i < 12; i++) {
        fixture.sync.setVisible('row$i', 'g$i', true);
      }
      _flush(time);
      expect(fixture.reads, hasLength(2));
      fixture.sync.setVisible('row11', 'g11', false);
      for (var i = 0; i < 11; i++) {
        final id = 'g$i';
        expect(replies.containsKey(id), isTrue);
        replies[id]!.complete(_current(id));
        _flush(time);
      }
      expect(fixture.reads, hasLength(11));
      expect(highest, 2);
      expect(replies.containsKey('g11'), isFalse);
    });
  });

  for (final action in ['hidden', 'inactive', 'session', 'disposed']) {
    test('late current result cannot update the store after $action', () {
      late Completer<Map<String, dynamic>> reply;
      _run((_) => reply.future, (time, fixture) {
        reply = Completer<Map<String, dynamic>>();
        fixture.sync.setVisible('row', 'group#1', true);
        fixture.sync.setActive(true);
        _flush(time);
        switch (action) {
          case 'hidden':
            fixture.sync.setVisible('row', 'group#1', false);
          case 'inactive':
            fixture.sync.setActive(false);
          case 'session':
            fixture.session = false;
          case 'disposed':
            fixture.sync.dispose();
        }
        reply.complete(_current('group#1', revision: 9));
        _flush(time);
        expect(fixture.store.features('group#1').valid, isFalse);
        expect(fixture.store.liveFeature('group#1').isActive, isFalse);
      });
    });
  }

  test('an old cancelled request cannot overwrite a resumed list request', () {
    late Completer<Map<String, dynamic>> reply;
    var calls = 0;
    _run(
        (_) =>
            ++calls == 1 ? reply.future : _current('group#1', status: 'LIVE'),
        (time, fixture) {
      reply = Completer<Map<String, dynamic>>();
      fixture.sync.setVisible('row', 'group#1', true);
      fixture.sync.setActive(true);
      _flush(time);
      fixture.sync.setActive(false);
      fixture.sync.setActive(true);
      _flush(time);
      expect(fixture.store.liveFeature('group#1').status, 'live');
      reply.complete(_current('group#1'));
      _flush(time);
      expect(fixture.store.liveFeature('group#1').status, 'live');
      expect(fixture.reads, hasLength(2));
    });
  });

  for (final error in ['network', '404', '403']) {
    test('$error preserves the badge and negatively caches scrolling retries',
        () {
      var fail = false;
      _run((_) {
        if (!fail) return _current('group#1', status: 'LIVE');
        if (error == 'network') throw StateError('offline');
        return {'errCode': error == '403' ? 1002 : 0, 'data': {}};
      }, (time, fixture) {
        fixture.sync.setVisible('row', 'group#1', true);
        fixture.sync.setActive(true);
        _flush(time);
        fail = true;
        if (error == '404') fixture.transport.status = 404;
        if (error == '403') fixture.transport.status = 403;
        fixture.sync.refreshVisible();
        _flush(time);
        expect(fixture.reads, hasLength(2));
        expect(fixture.store.liveFeature('group#1').status, 'live');
        for (var i = 0; i < 20; i++) {
          fixture.sync.setVisible('row', 'group#1', false);
          fixture.sync.setVisible('row', 'group#1', true);
          fixture.sync.refreshVisible();
        }
        _flush(time);
        expect(fixture.reads, hasLength(2));
        time.elapse(const Duration(seconds: 30));
        fail = false;
        fixture.transport.status = 200;
        fixture.sync.refreshVisible();
        _flush(time);
        expect(fixture.reads, hasLength(3));
        expect(fixture.store.liveFeature('group#1').status, 'live');
      });
    });
  }
}
