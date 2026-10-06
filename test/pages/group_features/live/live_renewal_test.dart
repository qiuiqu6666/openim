import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/live/models/live_models.dart';
import 'package:openim/pages/group_features/live/models/live_summary_events.dart';
import 'package:openim/pages/group_features/live/playback/live_credential_renewal.dart';
import 'package:openim/pages/group_features/live/playback/live_watch_state.dart';
import 'package:openim/pages/group_features/models/group_features.dart';
import 'live_test_support.dart';

Future<void> _flush() async {
  for (var index = 0; index < 12; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _Task implements LiveScheduledTask {
  _Task(this.at, this.callback);
  final DateTime at;
  final VoidCallback callback;
  bool cancelled = false;
  @override
  void cancel() => cancelled = true;
}

/// Only the credential clock advances; HTTP completion and native work are real
/// asynchronous futures. Tests never depend on wall time or periodic polling.
class _Clock {
  DateTime value = DateTime.utc(2030, 1, 1);
  final tasks = <_Task>[];
  DateTime now() => value;
  LiveScheduledTask schedule(Duration delay, VoidCallback callback) {
    final task = _Task(value.add(delay), callback);
    tasks.add(task);
    return task;
  }

  int get pending => tasks.where((task) => !task.cancelled).length;
  Future<void> advance(Duration duration) async {
    final target = value.add(duration);
    for (var iteration = 0; iteration < 100; iteration++) {
      final due = tasks
          .where((task) => !task.cancelled && !task.at.isAfter(target))
          .toList()
        ..sort((left, right) => left.at.compareTo(right.at));
      if (due.isEmpty) {
        value = target;
        await _flush();
        return;
      }
      final task = due.first;
      task.cancelled = true;
      value = task.at;
      task.callback();
      await _flush();
    }
    fail('Credential requests created an unbounded deadline loop');
  }
}

class _CancelableTransport extends LiveTransport {
  _CancelableTransport(super.handler);
  final cancelledPaths = <String>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    unawaited(cancelFuture?.then((_) => cancelledPaths.add(options.path)) ??
        Future<void>.value());
    return super.fetch(options, requestStream, cancelFuture);
  }
}

class _Harness {
  _Harness({this.withExpiry = true}) {
    transport = _CancelableTransport((request) {
      if (deniedCode != null &&
          denyOnPlay == request.path.endsWith('/play-info')) {
        return {'errCode': deniedCode, 'errMsg': 'read denied'};
      }
      if (request.path.endsWith('/play-info')) {
        playCount++;
        if (failPlay) throw StateError('temporary unavailable');
        if (playGate != null) return playGate!.future;
        return playDTO();
      }
      detailCount++;
      return detailGate?.future ?? liveDTO(status: 'LIVE');
    });
    state = createState();
  }
  final clock = _Clock();
  final bool withExpiry;
  bool current = true, failPlay = false;
  bool denyOnPlay = false;
  String? deniedCode;
  int playCount = 0, detailCount = 0;
  DateTime? fixedExpiry;
  Completer<Map<String, dynamic>>? detailGate, playGate;
  late final _CancelableTransport transport;
  late final LiveWatchState state;
  final videos = <TestLiveVideo>[];

  Map<String, dynamic> playDTO() => {
        'liveSessionId': 'live-1',
        'roomName': '直播间',
        'protocol': 'hls',
        'playUrl': 'https://video.test/$playCount.m3u8',
        if (withExpiry)
          'expiresAt':
              (fixedExpiry ?? clock.now().add(const Duration(seconds: 60)))
                  .toIso8601String(),
      };
  LiveWatchState createState() => LiveWatchState(
          liveContext(transport.api(), current: () => current),
          liveSession(status: LiveStatus.live),
          now: clock.now,
          schedule: clock.schedule, videoFactory: (uri) {
        final video = TestLiveVideo(uri);
        videos.add(video);
        return video;
      });
  Future<void> start() async {
    await state.load();
    await _flush();
    expect(state.playback?.ready, isTrue);
  }

  Future<void> dispose() async {
    state.dispose();
    await _flush();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a 60-second credential renews at 50 seconds and keeps one shared owner',
      () async {
    final fixture = _Harness();
    addTearDown(fixture.dispose);
    await fixture.start();
    final decoder = fixture.state.playback!;
    await fixture.clock.advance(const Duration(seconds: 49));
    expect(fixture.playCount, 1);
    await fixture.clock.advance(const Duration(seconds: 1));
    expect(fixture.playCount, 2);
    expect(fixture.detailCount, 2);
    expect(identical(fixture.state.playback, decoder), isTrue);
    expect(fixture.videos.first.closes, 1);
    expect(fixture.videos.last.plays, 1);
    await fixture.clock.advance(const Duration(seconds: 50));
    expect(fixture.playCount, 3);
    expect(decoder.current, isTrue);
    expect(decoder.ready, isTrue);
    expect(fixture.videos.where((video) => video.closes == 0).length, 1);
  });

  test('missing expiresAt does not invent a repeating credential request',
      () async {
    final fixture = _Harness(withExpiry: false);
    addTearDown(fixture.dispose);
    await fixture.start();
    expect(fixture.clock.pending, 0);
    await fixture.clock.advance(const Duration(hours: 6));
    expect(fixture.playCount, 1);
    expect(fixture.detailCount, 1);
  });

  test(
      'two watch states use one renewal callback and survive one lease leaving',
      () async {
    final fixture = _Harness();
    addTearDown(fixture.dispose);
    await fixture.start();
    final second = fixture.createState();
    var secondDisposed = false;
    addTearDown(() {
      if (!secondDisposed) second.dispose();
    });
    await second.load();
    await _flush();
    expect(identical(second.playback, fixture.state.playback), isTrue);
    final decoder = second.playback!;
    final inline = Object(), fullscreen = Object();
    await decoder.setSurfaceVisible(inline, true, owner: fixture.state);
    await decoder.setSurfaceVisible(fullscreen, true, owner: second);
    await decoder.setSurfaceVisible(inline, false, owner: fixture.state);
    final before = fixture.playCount;
    await fixture.clock.advance(const Duration(seconds: 50));
    expect(fixture.playCount, before + 1);
    expect(decoder.paused, isFalse);
    await decoder.removeSurface(fullscreen);
    await decoder.setSurfaceVisible(inline, true, owner: fixture.state);
    await _flush();
    second.dispose();
    secondDisposed = true;
    await fixture.clock.advance(const Duration(seconds: 50));
    expect(fixture.playCount, before + 2);
    expect(decoder.current, isTrue);
  });

  test('fullscreen handoff does not pause or request another credential',
      () async {
    final fixture = _Harness();
    addTearDown(fixture.dispose);
    await fixture.start();
    final decoder = fixture.state.playback!;
    final inline = Object(), fullscreen = Object();
    await decoder.setSurfaceVisible(inline, true, owner: fixture.state);
    await decoder.setSurfaceVisible(fullscreen, true, owner: fixture.state);
    fixture.state.setSurfaceActive(false);
    await decoder.setSurfaceVisible(inline, false, owner: fixture.state);
    expect(decoder.paused, isFalse);
    expect(fixture.videos.single.pauses, 0);
    expect(fixture.playCount, 1);
    await fixture.clock.advance(const Duration(seconds: 50));
    expect(fixture.playCount, 2);
    await decoder.setSurfaceVisible(inline, true, owner: fixture.state);
    fixture.state.setSurfaceActive(true);
    await decoder.removeSurface(fullscreen);
    expect(decoder.paused, isFalse);
    expect(fixture.playCount, 2);
  });

  test('covered player cancels its deadlines and merges resume calibration',
      () async {
    final fixture = _Harness();
    addTearDown(fixture.dispose);
    await fixture.start();
    final decoder = fixture.state.playback!;
    final surface = Object();
    await decoder.setSurfaceVisible(surface, true, owner: fixture.state);
    fixture.state.setSurfaceActive(false);
    await decoder.setSurfaceVisible(surface, false, owner: fixture.state);
    expect(decoder.paused, isTrue);
    expect(fixture.clock.pending, 0);
    await fixture.clock.advance(const Duration(minutes: 3));
    expect(fixture.playCount, 1);
    fixture.state.setSurfaceActive(true);
    final first =
        decoder.setSurfaceVisible(surface, true, owner: fixture.state);
    final second = decoder.resume();
    await Future.wait([first, second]);
    await _flush();
    expect(fixture.detailCount, 2);
    expect(fixture.playCount, 2);
    expect(decoder.ready, isTrue);
    expect(decoder.paused, isFalse);
  });

  test('background cancels an in-flight renewal and ignores its late response',
      () async {
    final fixture = _Harness();
    addTearDown(fixture.dispose);
    await fixture.start();
    final decoder = fixture.state.playback!;
    fixture.playGate = Completer<Map<String, dynamic>>();
    await fixture.clock.advance(const Duration(seconds: 50));
    expect(fixture.playCount, 2);
    fixture.state.setForeground(false);
    await _flush();
    expect(decoder.paused, isTrue);
    expect(
        fixture.transport.cancelledPaths.any((p) => p.endsWith('/play-info')),
        isTrue);
    fixture.playGate!.complete(fixture.playDTO());
    fixture.playGate = null;
    await _flush();
    expect(fixture.videos.length, 1);
    expect(fixture.state.error, isNull);
    await fixture.clock.advance(const Duration(seconds: 120));
    expect(fixture.playCount, 2);
    fixture.state.setForeground(true);
    await decoder.setForeground(true);
    await _flush();
    expect(fixture.playCount, 3);
    expect(fixture.detailCount, 3);
    expect(decoder.ready, isTrue);
  });

  for (final changedSession in [false, true]) {
    test('SDK ${changedSession ? 'session change' : 'end'} cancels renewal',
        () async {
      final fixture = _Harness();
      addTearDown(fixture.dispose);
      await fixture.start();
      fixture.playGate = Completer<Map<String, dynamic>>();
      await fixture.clock.advance(const Duration(seconds: 50));
      final summaries = LiveSummaryEvents(fixture.state.context.features);
      final summary = summaries.accept({
        'groupID': 'group#1',
        'data': {
          'groupFeatures': {
            'schemaVersion': 1,
            'revision': 2,
            'live': {
              'sessionID': changedSession ? 'live-2' : 'live-1',
              'status': changedSession ? 'live' : 'ended'
            }
          }
        }
      }, 'group#1')!;
      fixture.state.acceptSummary(summary);
      expect(fixture.state.playback, isNull);
      expect(fixture.clock.pending, 0);
      fixture.playGate!.complete(fixture.playDTO());
      await _flush();
      expect(fixture.videos.length, 1);
      expect(fixture.videos.single.closes, 1);
      await fixture.clock.advance(const Duration(minutes: 10));
      expect(fixture.playCount, 2);
      expect(fixture.state.session.version, 1);
    });
  }

  test('failed renewal backs off and stops expired native credentials',
      () async {
    final fixture = _Harness();
    addTearDown(fixture.dispose);
    await fixture.start();
    final decoder = fixture.state.playback!;
    fixture.failPlay = true;
    await fixture.clock.advance(const Duration(seconds: 50));
    expect(fixture.playCount, 2);
    await fixture.clock.advance(const Duration(seconds: 10));
    expect(decoder.ready, isFalse);
    expect(decoder.error.toString(), contains('过期'));
    expect(fixture.videos.single.pauses, 1);
    await fixture.clock.advance(const Duration(seconds: 19));
    expect(fixture.playCount, 2);
    await fixture.clock.advance(const Duration(seconds: 1));
    expect(fixture.playCount, 3);
    await fixture.clock.advance(const Duration(seconds: 59));
    expect(fixture.playCount, 3);
    fixture.failPlay = false;
    await fixture.clock.advance(const Duration(seconds: 1));
    expect(fixture.playCount, 4);
    expect(decoder.ready, isTrue);
    expect(decoder.error, isNull);
    expect(fixture.videos.length, 2);
  });

  test('unchanged expiry cannot produce one-second HTTP retry loops', () async {
    final fixture = _Harness();
    addTearDown(fixture.dispose);
    fixture.fixedExpiry = fixture.clock.now().add(const Duration(seconds: 60));
    await fixture.start();
    await fixture.clock.advance(const Duration(seconds: 50));
    expect(fixture.playCount, 2);
    await fixture.clock.advance(const Duration(seconds: 29));
    expect(fixture.playCount, 2);
    await fixture.clock.advance(const Duration(seconds: 1));
    expect(fixture.playCount, 3);
    expect(fixture.state.error.toString(), contains('过期'));
  });

  test('leaving cancels actual HTTP and no late response creates a decoder',
      () async {
    final fixture = _Harness();
    fixture.detailGate = Completer<Map<String, dynamic>>();
    final request = fixture.state.load();
    await _flush();
    fixture.state.dispose();
    await request;
    expect(fixture.transport.cancelledPaths, isNotEmpty);
    fixture.detailGate!.complete(liveDTO(status: 'LIVE'));
    await _flush();
    expect(fixture.playCount, 0);
    expect(fixture.videos, isEmpty);
    expect(fixture.clock.pending, 0);
  });

  test('account change during renewal cannot install late credentials',
      () async {
    final fixture = _Harness();
    addTearDown(fixture.dispose);
    await fixture.start();
    fixture.playGate = Completer<Map<String, dynamic>>();
    await fixture.clock.advance(const Duration(seconds: 50));
    fixture.current = false;
    fixture.playGate!.complete(fixture.playDTO());
    await _flush();
    expect(fixture.videos.length, 1);
    expect(fixture.state.error, isNull);
    await fixture.clock.advance(const Duration(minutes: 10));
    expect(fixture.playCount, 2);
  });

  test('same LIVE SDK summary preserves a matching in-flight renewal',
      () async {
    final fixture = _Harness();
    addTearDown(fixture.dispose);
    await fixture.start();
    fixture.playGate = Completer<Map<String, dynamic>>();
    await fixture.clock.advance(const Duration(seconds: 50));
    final summaries = LiveSummaryEvents(fixture.state.context.features);
    fixture.state.acceptSummary(summaries.accept({
      'groupID': 'group#1',
      'data': {
        'groupFeatures': {
          'schemaVersion': 1,
          'revision': 2,
          'live': {'sessionID': 'live-1', 'status': 'live'}
        }
      }
    }, 'group#1')!);
    fixture.playGate!.complete(fixture.playDTO());
    fixture.playGate = null;
    await _flush();
    expect(fixture.playCount, 2);
    expect(fixture.videos.length, 2);
    expect(fixture.transport.cancelledPaths, isEmpty);
    expect(fixture.state.playback?.ready, isTrue);
  });

  test('rapid background and resume ignores the abandoned calibration',
      () async {
    final fixture = _Harness();
    addTearDown(fixture.dispose);
    await fixture.start();
    final decoder = fixture.state.playback!;
    fixture.state.setForeground(false);
    await _flush();
    final oldReply = Completer<Map<String, dynamic>>();
    fixture.detailGate = oldReply;
    fixture.state.setForeground(true);
    await _flush();
    fixture.state.setForeground(false);
    fixture.detailGate = null;
    fixture.state.setForeground(true);
    await decoder.setForeground(true);
    await _flush();
    final created = fixture.videos.length;
    oldReply.complete(liveDTO(status: 'LIVE'));
    await _flush();
    expect(fixture.videos.length, created);
    expect(decoder.ready, isTrue);
    expect(decoder.paused, isFalse);
    expect(fixture.state.error, isNull);
  });

  for (final status in ['scheduled', 'ready']) {
    test('same-session $status SDK lag does not block authoritative LIVE',
        () async {
      final fixture = _Harness();
      addTearDown(fixture.dispose);
      fixture.state
          .acceptSummary(GroupLiveFeature(sessionID: 'live-1', status: status));
      await fixture.start();
      expect(fixture.playCount, 1);
      fixture.state
          .acceptSummary(GroupLiveFeature(sessionID: 'live-1', status: status));
      expect(fixture.state.playback?.ready, isTrue);
      expect(fixture.state.session.status, LiveStatus.live);
      expect(fixture.state.acceptSession(liveSession()), isFalse);
      await fixture.clock.advance(const Duration(seconds: 50));
      expect(fixture.playCount, 2);
    });
  }

  for (final denial in [
    ('20068', false),
    ('20070', true),
    ('20012', false),
    ('1002', true),
    ('FORBIDDEN', false)
  ]) {
    test('confirmed read denial ${denial.$1} stops the shared decoder',
        () async {
      final fixture = _Harness();
      addTearDown(fixture.dispose);
      await fixture.start();
      fixture.deniedCode = denial.$1;
      fixture.denyOnPlay = denial.$2;
      await fixture.clock.advance(const Duration(seconds: 50));
      expect(fixture.state.playback, isNull);
      expect(fixture.videos.single.closes, 1);
      expect(fixture.state.error, isNotNull);
      expect(fixture.state.session.status, LiveStatus.live);
      expect(fixture.state.session.version, 1);
      final requests = fixture.transport.requests.length;
      await fixture.clock.advance(const Duration(minutes: 5));
      expect(fixture.transport.requests.length, requests);
      expect(fixture.clock.pending, 0);
    });
  }
}
