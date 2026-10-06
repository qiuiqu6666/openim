import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim_live/src/session/call_media_operations.dart';

void main() {
  test('shutdown waits for running media and skips queued and late changes',
      () async {
    final media = CallMediaOperations();
    final pending = Completer<void>();
    final events = <String>[];
    final first = media.run(() async {
      events.add('capture');
      await pending.future;
      events.add('settled');
    });
    await Future<void>.delayed(Duration.zero);
    final queued = media.run(() async => events.add('camera'));
    var released = false;
    final drain = media.close().then((_) => released = true);
    expect(media.closed, true);
    expect(await media.run(() async => events.add('speaker')), false);
    expect(released, false);
    pending.complete();
    expect(await first, true);
    expect(await queued, false);
    await drain;
    expect(events, ['capture', 'settled']);
    expect(released, true);
  });

  test('media failure does not block the next operation or cleanup', () async {
    final media = CallMediaOperations();
    await expectLater(
        media.run(() async => throw StateError('native')), throwsStateError);
    var next = false;
    expect(await media.run(() async => next = true), true);
    await media.close();
    expect(next, true);
  });

  test('cancel during capture releases the late resource without publishing',
      () async {
    final media = CallMediaOperations();
    final created = Completer<Object>();
    final disposed = <Object>[];
    final tracks = CallMediaResources<Object>(
        disposeResource: (track) async => disposed.add(track));
    var published = false;
    final work = media.run(() => tracks.captureAndPublish(
          capture: () => created.future,
          publish: (_) async => published = true,
          isCurrent: () => !media.closed,
        ));
    await Future<void>.delayed(Duration.zero);
    final drain = media.close();
    final resource = Object();
    created.complete(resource);
    await work;
    await drain;
    await tracks.release();
    expect(published, false);
    expect(disposed, [resource]);
  });

  test(
      'publication failure disposes a capture absent from SDK publication maps',
      () async {
    final disposed = <Object>[];
    final tracks = CallMediaResources<Object>(
        disposeResource: (track) async => disposed.add(track));
    final resource = Object();
    await expectLater(
        tracks.captureAndPublish(
          capture: () async => resource,
          publish: (_) async => throw StateError('negotiation'),
          isCurrent: () => true,
        ),
        throwsStateError);
    await tracks.release();
    expect(disposed, [resource]);
  });

  test('cancel during publication releases before the next call can begin',
      () async {
    final media = CallMediaOperations();
    final publishing = Completer<void>();
    var disposed = 0;
    final tracks =
        CallMediaResources<Object>(disposeResource: (_) async => disposed++);
    final work = media.run(() => tracks.captureAndPublish(
          capture: () async => Object(),
          publish: (_) => publishing.future,
          isCurrent: () => !media.closed,
        ));
    await Future<void>.delayed(Duration.zero);
    final drain = media.close();
    expect(disposed, 0);
    publishing.complete();
    await work;
    await drain;
    await tracks.release();
    expect(disposed, 1);
  });

  test('successful captures remain owned and repeated cleanup runs once',
      () async {
    var disposed = 0;
    final tracks =
        CallMediaResources<Object>(disposeResource: (_) async => disposed++);
    await tracks.captureAndPublish(
        capture: () async => Object(),
        publish: (_) async {},
        isCurrent: () => true);
    expect(disposed, 0);
    await Future.wait([tracks.release(), tracks.release()]);
    expect(disposed, 1);
  });

  test('one cleanup failure cannot leave another media capture alive',
      () async {
    var disposed = 0;
    final tracks = CallMediaResources<Object>(disposeResource: (_) async {
      disposed++;
      if (disposed == 1) throw StateError('stop');
    });
    for (var index = 0; index < 2; index++) {
      await tracks.captureAndPublish(
          capture: () async => Object(),
          publish: (_) async {},
          isCurrent: () => true);
    }
    await expectLater(tracks.release(), throwsStateError);
    expect(disposed, 2);
  });
}
