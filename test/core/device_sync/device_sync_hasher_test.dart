import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/device_sync/platform/device_sync_hasher.dart';

void main() {
  late Directory fixtureDirectory;
  late DeviceSyncHasher hasher;
  final generated = <File>[];

  Future<File> fixture(String name, List<int> bytes) async {
    final file = File('${fixtureDirectory.path}/$name');
    generated.add(file);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  setUp(() async {
    fixtureDirectory =
        await Directory.systemTemp.createTemp('device-sync-hash-');
    hasher = DeviceSyncHasher();
  });

  tearDown(() async {
    hasher.dispose();
    // Delete only files created by this test, never recurse through another
    // caller's library or temporary directory.
    for (final file in generated) {
      if (await file.exists()) await file.delete();
    }
    generated.clear();
    await fixtureDirectory.delete();
  });

  test('hashes original bytes to the known SHA-256 vector', () async {
    final file = await fixture('abc.bin', [97, 98, 99]);
    expect(await hasher.hash(file, cancelToken: CancelToken()),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    expect(await file.readAsBytes(), [97, 98, 99]);
  });

  test('streams a binary file across many IO chunks', () async {
    final bytes = Uint8List(4 * 1024 * 1024);
    for (var index = 0; index < bytes.length; index++) {
      bytes[index] = index % 256;
    }
    final file = await fixture('many-chunks.bin', bytes);
    // Independently generated with .NET SHA256, not the worker implementation.
    expect(await hasher.hash(file, cancelToken: CancelToken()),
        '2b07811057df887086f06a67edc6ebf911de8b6741156e7a2eb1416a4b8b1b2e');
  });

  test('cancellation releases original handle and permits the next hash',
      () async {
    final file = await fixture('cancel.bin', []);
    final handle = await file.open(mode: FileMode.write);
    await handle.truncate(64 * 1024 * 1024);
    await handle.close();
    final token = CancelToken();
    final flight = hasher.hash(file, cancelToken: token);
    final cancelled = expectLater(
        flight,
        throwsA(isA<DioException>()
            .having((e) => CancelToken.isCancel(e), 'cancelled', true)));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    token.cancel('Test cancellation');
    await cancelled;
    await file
        .delete(); // Windows fails here if the worker still owns a handle.
    final next = await fixture('next.bin', [97, 98, 99]);
    expect(await hasher.hash(next, cancelToken: CancelToken()),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  });

  test('enforces a single worker and handles cancellation during spawn',
      () async {
    final file = await fixture('single.bin', [97, 98, 99]);
    final token = CancelToken();
    final first = hasher.hash(file, cancelToken: token);
    final cancelled = expectLater(first, throwsA(isA<DioException>()));
    await expectLater(hasher.hash(file, cancelToken: CancelToken()),
        throwsA(isA<StateError>()));
    token.cancel('Cancel first');
    await cancelled;
    expect(await hasher.hash(file, cancelToken: CancelToken()),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  });

  test('a missing file does not poison the next worker', () async {
    await expectLater(
        hasher.hash(File('${fixtureDirectory.path}/missing'),
            cancelToken: CancelToken()),
        throwsA(isA<FileSystemException>()));
    final file = await fixture('after-error.bin', [97, 98, 99]);
    expect(await hasher.hash(file, cancelToken: CancelToken()),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  });

  test('dispose cancels worker and rejects future work', () async {
    final file = await fixture('disposed.bin', [97, 98, 99]);
    final flight = hasher.hash(file, cancelToken: CancelToken());
    final cancelled = expectLater(flight, throwsA(isA<DioException>()));
    hasher.dispose();
    await cancelled;
    await file.delete();
    await expectLater(hasher.hash(file, cancelToken: CancelToken()),
        throwsA(isA<StateError>()));
  });
}
