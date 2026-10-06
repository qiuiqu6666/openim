import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/date_day_images_test_support.dart';

void main() {
  test('history search keeps image reads disabled unless explicitly requested',
      () async {
    final source = DayImageSource()
      ..pictures = (_) => throw StateError('unused');
    final controller = imageController(source, include: false);
    addTearDown(controller.dispose);
    await controller.loadMonth(imageDay);
    expect(controller.hasMessages(imageDay), isTrue);
    expect(controller.imageForDate(imageDay), isNull);
    expect(source.calls, hasLength(1));
  });

  test(
      'pictures use one bounded day-specific SDK page after record confirmation',
      () async {
    var length = 0;
    final source = DayImageSource()
      ..pictures =
          (_) => List.generate(25, (index) => dayPicture('image-$index'));
    final controller = imageController(source, choose: (count) {
      length = count;
      return count - 1;
    });
    addTearDown(controller.dispose);
    await controller.loadMonth(imageDay);
    expect(length, 20);
    expect(controller.imageForDate(imageDay)!.messageID, 'image-19');
    expect(source.calls, hasLength(2));
    expect(source.calls.last.query.messageTypes, [MessageType.picture]);
    expect(source.calls.last.query.searchTimePosition,
        DateTime(2026, 10, 5).millisecondsSinceEpoch ~/ 1000);
    expect(source.calls.last.query.searchTimePeriod,
        DateTime(2026, 10, 5).difference(imageDay).inSeconds);
  });

  test(
      'dates without records do not read photos and cannot expose a background',
      () async {
    final source = DayImageSource()
      ..records = ((_) => [])
      ..pictures = (_) => [dayPicture('unused')];
    final controller = imageController(source);
    addTearDown(controller.dispose);
    await controller.loadMonth(imageDay);
    expect(controller.hasMessages(imageDay), isFalse);
    expect(controller.imageForDate(imageDay), isNull);
    expect(source.calls, hasLength(1));
  });

  test(
      'random choice stays stable across getters, cache hits and valid refreshes',
      () async {
    var choices = 0;
    var photos = [dayPicture('a'), dayPicture('b')];
    final source = DayImageSource()..pictures = (_) => photos;
    final controller = imageController(source, choose: (length) {
      choices++;
      return length - 1;
    });
    addTearDown(controller.dispose);
    await controller.loadMonth(imageDay);
    expect(controller.imageForDate(imageDay)!.messageID, 'b');
    for (var count = 0; count < 10; count++) {
      expect(controller.imageForDate(imageDay)!.messageID, 'b');
    }
    await controller.loadMonth(imageDay);
    expect(choices, 1);
    expect(source.calls, hasLength(2));
    photos = [
      dayPicture('b', snapshot: 'https://media.example/new.webp'),
      dayPicture('a')
    ];
    await controller.loadMonth(imageDay, force: true);
    expect(controller.imageForDate(imageDay)!.messageID, 'b');
    expect(controller.imageForDate(imageDay)!.url,
        'https://media.example/new.webp');
    expect(choices, 1);
    photos = [dayPicture('c')];
    await controller.loadMonth(imageDay, force: true);
    expect(controller.imageForDate(imageDay)!.messageID, 'c');
    expect(choices, 2);
  });

  test('confirmation verifies records without repeatedly sampling photos',
      () async {
    final source = DayImageSource()
      ..pictures = (_) => [dayPicture('background')];
    final controller = imageController(source, choose: (_) => 0);
    addTearDown(controller.dispose);
    await controller.loadMonth(imageDay);
    expect(await controller.verifyDate(imageDay), isTrue);
    expect(source.calls.where((call) => call.picture), hasLength(1));
    expect(controller.imageForDate(imageDay)!.messageID, 'background');
  });

  test('photo errors preserve usable dates and clear a previously cached image',
      () async {
    var fail = false;
    final source = DayImageSource()
      ..pictures = (_) {
        if (fail) throw StateError('photo query unavailable');
        return [dayPicture('previous-photo')];
      };
    final controller = imageController(source, choose: (_) => 0);
    addTearDown(controller.dispose);
    await controller.loadMonth(imageDay);
    expect(controller.imageForDate(imageDay), isNotNull);
    fail = true;
    final refreshed = controller.loadMonth(imageDay, force: true);
    expect(controller.imageForDate(imageDay), isNull);
    await refreshed;
    expect(controller.hasMessages(imageDay), isTrue);
    expect(controller.failed, isFalse);
    expect(controller.imageForDate(imageDay), isNull);
  });

  test('no eligible pictures clears old backgrounds without disabling the day',
      () async {
    var photos = [dayPicture('old-photo')];
    final source = DayImageSource()..pictures = (_) => photos;
    final controller = imageController(source, choose: (_) => 0);
    addTearDown(controller.dispose);
    await controller.loadMonth(imageDay);
    photos = [];
    await controller.loadMonth(imageDay, force: true);
    expect(controller.hasMessages(imageDay), isTrue);
    expect(controller.imageForDate(imageDay), isNull);
  });

  test('private/deleted/removed/missing-thumbnail rows never enter the sample',
      () async {
    final source = DayImageSource()
      ..pictures = (_) => [
            dayPicture('private', private: true),
            dayPicture('deleted')..status = MessageStatus.deleted,
            dayPicture('locally-removed'),
            dayPicture('no-image', snapshot: null, big: null, original: null),
            dayPicture('safe-image'),
          ];
    var candidateCount = 0;
    final controller = imageController(source,
        choose: (count) {
          candidateCount = count;
          return 0;
        },
        isRemoved: (message) => message.clientMsgID == 'locally-removed');
    addTearDown(controller.dispose);
    await controller.loadMonth(imageDay);
    expect(candidateCount, 1);
    expect(controller.imageForDate(imageDay)!.messageID, 'safe-image');
  });

  test('getter rechecks removal and private state of a cached actual message',
      () async {
    var removed = false;
    final image = dayPicture('cached-image');
    final source = DayImageSource()..pictures = (_) => [image];
    final controller = imageController(source,
        choose: (_) => 0,
        isRemoved: (message) =>
            removed && message.clientMsgID == 'cached-image');
    addTearDown(controller.dispose);
    await controller.loadMonth(imageDay);
    expect(controller.imageForDate(imageDay), isNotNull);
    removed = true;
    expect(controller.imageForDate(imageDay), isNull);
    removed = false;
    image.attachedInfoElem!.isPrivateChat = true;
    expect(controller.imageForDate(imageDay), isNull);
    expect(controller.hasMessages(imageDay), isTrue);
  });

  test('deleting the chosen image reselects only from fresh valid candidates',
      () async {
    final removed = <String>{};
    final source = DayImageSource()
      ..pictures =
          (_) => [dayPicture('old-choice'), dayPicture('still-present')];
    var choices = 0;
    final controller = imageController(source,
        choose: (_) {
          choices++;
          return 0;
        },
        isRemoved: (message) => removed.contains(message.clientMsgID));
    addTearDown(controller.dispose);
    await controller.loadMonth(imageDay);
    expect(controller.imageForDate(imageDay)!.messageID, 'old-choice');
    removed.add('old-choice');
    expect(controller.imageForDate(imageDay), isNull);
    await controller.loadMonth(imageDay, force: true);
    expect(controller.imageForDate(imageDay)!.messageID, 'still-present');
    expect(choices, 2);
  });

  test('a full next-midnight photo page is skipped without losing the last ms',
      () async {
    final next = DateTime(2026, 10, 5);
    final source = DayImageSource()
      ..pictures = (call) => call.pageIndex == 1
          ? List.generate(20, (index) => dayPicture('next-$index', time: next))
          : [
              dayPicture('last-ms',
                  time: next.subtract(const Duration(milliseconds: 1)))
            ];
    final controller = imageController(source, choose: (_) => 0);
    addTearDown(controller.dispose);
    await controller.loadMonth(imageDay);
    expect(controller.imageForDate(imageDay)!.messageID, 'last-ms');
    expect(
        source.calls
            .where((call) => call.picture)
            .map((call) => call.pageIndex),
        [1, 2]);
  });

  test('a private-only sample is not followed by a scan of all day pictures',
      () async {
    final source = DayImageSource()
      ..pictures = (_) => List.generate(
          20, (index) => dayPicture('private-$index', private: true));
    final controller = imageController(source);
    addTearDown(controller.dispose);
    await controller.loadMonth(imageDay);
    expect(controller.hasMessages(imageDay), isTrue);
    expect(controller.imageForDate(imageDay), isNull);
    expect(source.calls.where((call) => call.picture), hasLength(1));
  });

  test('repeated boundary pages safely fall back to a plain day', () async {
    final source = DayImageSource()
      ..pictures = (_) => List.generate(20,
          (index) => dayPicture('same-$index', time: DateTime(2026, 10, 5)));
    final controller = imageController(source);
    addTearDown(controller.dispose);
    await controller.loadMonth(imageDay);
    expect(controller.hasMessages(imageDay), isTrue);
    expect(controller.failed, isFalse);
    expect(controller.imageForDate(imageDay), isNull);
    expect(source.calls.where((call) => call.picture), hasLength(2));
  });

  test('an invalid injected choice affects only cosmetic photo selection',
      () async {
    final source = DayImageSource()..pictures = (_) => [dayPicture('photo')];
    final controller = imageController(source, choose: (_) => -1);
    addTearDown(controller.dispose);
    await controller.loadMonth(imageDay);
    expect(controller.hasMessages(imageDay), isTrue);
    expect(controller.failed, isFalse);
    expect(controller.imageForDate(imageDay), isNull);
  });

  test('stale photo responses cannot overwrite a newer force-refresh choice',
      () async {
    final oldPhoto = Completer<List<Message>>();
    var photoReads = 0;
    final source = DayImageSource()
      ..pictures = (_) =>
          ++photoReads == 1 ? oldPhoto.future : [dayPicture('fresh-photo')];
    final controller = imageController(source, choose: (_) => 0);
    addTearDown(controller.dispose);
    final oldMonth = controller.loadMonth(imageDay);
    await flushImageReads();
    expect(photoReads, 1);
    await controller.loadMonth(imageDay, force: true);
    expect(controller.imageForDate(imageDay)!.messageID, 'fresh-photo');
    oldPhoto.complete([dayPicture('stale-photo')]);
    await oldMonth;
    expect(controller.imageForDate(imageDay)!.messageID, 'fresh-photo');
  });

  test('photo and record reads share a total concurrency limit of three',
      () async {
    final photos = <Completer<List<Message>>>[];
    final source = DayImageSource()
      ..pictures = (_) {
        final pending = Completer<List<Message>>();
        photos.add(pending);
        return pending.future;
      };
    final controller = imageController(source,
        first: DateTime(2026, 9), last: DateTime(2026, 10, 31));
    addTearDown(controller.dispose);
    final october = controller.loadMonth(DateTime(2026, 10));
    await flushImageReads();
    expect(photos, hasLength(3));
    final september = controller.loadMonth(DateTime(2026, 9));
    expect(photos, hasLength(3));
    while (controller.loading) {
      for (final pending in photos) {
        if (!pending.isCompleted) pending.complete([]);
      }
      await flushImageReads();
    }
    await Future.wait([october, september]);
    expect(source.peak, lessThanOrEqualTo(3));
    expect(
        source.calls
            .where((call) => call.query.startDate!.month == 10 && call.picture),
        hasLength(3));
    expect(controller.hasMessages(DateTime(2026, 9, 1)), isTrue);
    expect(controller.imageForDate(DateTime(2026, 10, 1)), isNull);
  });

  test('account loss clears all month photos and stops a pending photo queue',
      () async {
    var current = true;
    final source = DayImageSource()
      ..records = ((call) => call.query.startDate!.day == 1
          ? [dayRecord(call.query.startDate!)]
          : [])
      ..pictures = (call) => [
            dayPicture('photo-${call.query.startDate!.month}',
                time: call.query.startDate!)
          ];
    final controller = imageController(source,
        first: DateTime(2026, 9),
        last: imageDay,
        choose: (_) => 0,
        isCurrent: () => current);
    addTearDown(controller.dispose);
    await controller.loadMonth(DateTime(2026, 9));
    await controller.loadMonth(DateTime(2026, 10));
    expect(controller.imageForDate(DateTime(2026, 9, 1)), isNotNull);
    expect(controller.imageForDate(DateTime(2026, 10, 1)), isNotNull);
    final requests = source.calls.length;
    current = false;
    expect(controller.imageForDate(DateTime(2026, 9, 1)), isNull);
    expect(controller.imageForDate(DateTime(2026, 10, 1)), isNull);
    current = true;
    await controller.loadMonth(DateTime(2026, 10));
    expect(source.calls, hasLength(requests));
    expect(controller.imageForDate(DateTime(2026, 10, 1)), isNull);
  });

  test('dispose during photo sampling ignores the late response', () async {
    final photo = Completer<List<Message>>();
    final source = DayImageSource()..pictures = (_) => photo.future;
    final controller = imageController(source);
    var notifications = 0;
    controller.addListener(() => notifications++);
    final request = controller.loadMonth(imageDay);
    await flushImageReads();
    controller.dispose();
    photo.complete([dayPicture('late-private')]);
    await request;
    expect(controller.imageForDate(imageDay), isNull);
    expect(notifications, 1);
    expect(source.calls, hasLength(2));
  });
}
