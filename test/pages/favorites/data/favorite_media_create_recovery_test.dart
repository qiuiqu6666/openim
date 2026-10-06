import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/favorite_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'favorite_media_recovery_test.dart' show CleanupFault, MediaCloud;

class CreateRecoveryCloud extends MediaCloud {
  Object? nextCreateError;
  final createBodies = <Map<String, dynamic>>[];
  Completer<void>? createEntered;
  Completer<void>? releaseCreate;

  @override
  Future<FavoriteItem> create(
      {required FavoriteKind kind,
      required FavoriteContent content,
      required String clientRequestID,
      String title = '',
      List<String> uploadIDs = const [],
      List<String> assetIDs = const [],
      CancelToken? cancelToken}) async {
    createBodies.add({
      'clientRequestID': clientRequestID,
      'uploadIDs': uploadIDs,
      'assetID': content.blocks.single.assetID,
    });
    createEntered?.complete();
    createEntered = null;
    await releaseCreate?.future;
    if (nextCreateError != null) {
      final failure = nextCreateError!;
      nextCreateError = null;
      createIDs.add(clientRequestID);
      createdAssets.add(content.blocks.single.assetID!);
      throw failure;
    }
    return super.create(
        kind: kind,
        content: content,
        clientRequestID: clientRequestID,
        title: title,
        uploadIDs: uploadIDs,
        assetIDs: assetIDs,
        cancelToken: cancelToken);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File original;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('favorite-create-retry-');
    original =
        await File('${directory.path}/original.mp4').writeAsBytes([1, 2, 3, 4]);
  });
  tearDown(() async {
    final target = directory.absolute.path;
    final parent = Directory.systemTemp.absolute.path;
    expect(target.startsWith('$parent${Platform.pathSeparator}'), isTrue);
    await directory.delete(recursive: true);
  });

  Future<FavoriteItem> create(FavoriteRepository repo) =>
      repo.createMedia(kind: FavoriteKind.video, filePath: original.path);

  TypeMatcher<FavoriteApiException> code(Object value) =>
      isA<FavoriteApiException>()
          .having((failure) => failure.code, 'code', value);

  test('confirmed create 20056 renews only on the next explicit operation',
      () async {
    final api = CreateRecoveryCloud()
      ..nextCreateError = const FavoriteApiException(20056, 'original missing');
    final repo = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(repo.dispose);
    await expectLater(
        create(repo),
        throwsA(code(20056).having(
            (failure) => failure.message, 'message', contains('再次添加以重新上传'))));
    expect(api.initIDs, hasLength(1));
    expect(api.uploads, 1);
    expect(api.completeIDs, hasLength(1));
    expect(api.createIDs, hasLength(1));
    expect(repo.pendingRecovery, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    final cache =
        jsonDecode(prefs.getString('${repo.accountNamespace}:metadata:v1')!)
            as Map;
    expect(cache['mediaTasks'], isEmpty);
    expect(cache['requests'], isEmpty);

    final restarted = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(restarted.dispose);
    await create(restarted);
    expect(api.uploads, 2);
    expect(api.initIDs.first, isNot(api.initIDs.last));
    expect(api.completeIDs.first, isNot(api.completeIDs.last));
    expect(api.createIDs.first, isNot(api.createIDs.last));
    expect(api.createdAssets, ['asset-u1', 'asset-u2']);
    expect(api.createBodies.last['uploadIDs'], ['u2']);
  });

  for (final failure in [
    const FavoriteApiException('NETWORK_ERROR', 'unknown', isUncertain: true),
    const FavoriteApiException(20066, 'temporary'),
    const FavoriteApiException(20056, 'unconfirmed', isUncertain: true),
  ]) {
    test('unconfirmed create ${failure.code} retains its exact completed body',
        () async {
      final api = CreateRecoveryCloud()..nextCreateError = failure;
      final repo = FavoriteRepository(api: api, userIDProvider: () => 'me');
      addTearDown(repo.dispose);
      await expectLater(create(repo), throwsA(isA<FavoriteApiException>()));
      final before = jsonEncode(api.createBodies.single);
      expect(repo.pendingRecovery, hasLength(1));
      await original.delete();
      final restarted =
          FavoriteRepository(api: api, userIDProvider: () => 'me');
      addTearDown(restarted.dispose);
      await create(restarted);
      expect(api.uploads, 1);
      expect(api.initIDs, hasLength(1));
      expect(api.completeIDs, hasLength(1));
      expect(jsonEncode(api.createBodies.last), before);
      expect(api.createBodies.last['uploadIDs'], ['u1']);
      expect(api.createdAssets, ['asset-u1', 'asset-u1']);
    });
  }

  test('replayed rejected media clears its checkpoint before the next action',
      () async {
    final api = CreateRecoveryCloud()
      ..nextCreateError = const FavoriteApiException('NETWORK_ERROR', 'unknown',
          isUncertain: true);
    final repo = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(repo.dispose);
    await expectLater(create(repo), throwsA(code('NETWORK_ERROR')));
    final oldBody = jsonEncode(api.createBodies.single);
    final restarted = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(restarted.dispose);
    api.nextCreateError = const FavoriteApiException(20056, 'original missing');
    await restarted.replayPendingMutations();
    expect(jsonEncode(api.createBodies.last), oldBody);
    expect(api.uploads, 1);
    expect(restarted.pendingRecovery, isEmpty);
    expect(restarted.replayError, contains('再次添加以重新上传'));
    final cache = jsonDecode((await SharedPreferences.getInstance())
        .getString('${restarted.accountNamespace}:metadata:v1')!) as Map;
    expect(cache['mediaTasks'], isEmpty);
    expect(cache['requests'], isEmpty);

    await create(restarted);
    expect(api.uploads, 2);
    expect(api.initIDs.first, isNot(api.initIDs.last));
    expect(api.completeIDs.first, isNot(api.completeIDs.last));
    expect(api.createIDs.first, isNot(api.createIDs.last));
    expect(api.createdAssets, ['asset-u1', 'asset-u1', 'asset-u2']);
    expect(api.createBodies.last['uploadIDs'], ['u2']);
  });

  test('replayed media reset failure keeps the old task and suffix identities',
      () async {
    final api = CreateRecoveryCloud()
      ..nextCreateError = const FavoriteApiException('NETWORK_ERROR', 'unknown',
          isUncertain: true);
    final repo = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(repo.dispose);
    await expectLater(create(repo), throwsA(code('NETWORK_ERROR')));
    var denyReset = true;
    final restarted = FavoriteRepository(
        api: api,
        userIDProvider: () => 'me',
        cacheWriter: (key, value) async {
          final parsed = jsonDecode(value) as Map;
          if (denyReset && (parsed['mediaTasks'] as Map).isEmpty) return false;
          return (await SharedPreferences.getInstance()).setString(key, value);
        });
    addTearDown(restarted.dispose);
    api.nextCreateError = const FavoriteApiException(20056, 'original missing');
    await expectLater(
        restarted.replayPendingMutations(), throwsA(code('LOCAL_SAVE_FAILED')));
    expect(restarted.pendingRecovery, isEmpty);
    expect(restarted.replayError, contains('存储'));
    final cache = jsonDecode((await SharedPreferences.getInstance())
        .getString('${restarted.accountNamespace}:metadata:v1')!) as Map;
    expect(
        (cache['mediaTasks'] as Map).values.single['asset']['id'], 'asset-u1');
    expect((cache['requests'] as Map).values,
        containsAll([api.initIDs.single, api.completeIDs.single]));
    denyReset = false;
    api.nextCreateError = const FavoriteApiException(20056, 'original missing');
    await expectLater(create(restarted), throwsA(code(20056)));
    expect(api.uploads, 1);
    expect(api.completeIDs, hasLength(1));
    expect(api.createIDs.last, isNot(api.createIDs.first));
    await create(restarted);
    expect(api.uploads, 2);
    expect(api.initIDs.first, isNot(api.initIDs.last));
    expect(api.completeIDs.first, isNot(api.completeIDs.last));
  });

  test('rejected replay leaves another completed media checkpoint intact',
      () async {
    final api = CreateRecoveryCloud()
      ..nextCreateError = const FavoriteApiException('NETWORK_ERROR', 'unknown',
          isUncertain: true);
    final repo = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(repo.dispose);
    await expectLater(create(repo), throwsA(code('NETWORK_ERROR')));
    final other =
        await File('${directory.path}/other.mp4').writeAsBytes([5, 6, 7, 8]);
    api.nextCreateError = const FavoriteApiException('NETWORK_ERROR', 'unknown',
        isUncertain: true);
    await expectLater(
        repo.createMedia(kind: FavoriteKind.video, filePath: other.path),
        throwsA(code('NETWORK_ERROR')));
    final otherRequest = api.createIDs.last;
    final otherInit = api.initIDs.last;
    final otherComplete = api.completeIDs.last;
    final restarted = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(restarted.dispose);
    api.nextCreateError = const FavoriteApiException(20056, 'original missing');
    await restarted.replayPendingMutations();
    final cache = jsonDecode((await SharedPreferences.getInstance())
        .getString('${restarted.accountNamespace}:metadata:v1')!) as Map;
    expect(
        (cache['mediaTasks'] as Map).values.single['asset']['id'], 'asset-u2');
    expect((cache['requests'] as Map).values,
        containsAll([otherInit, otherComplete]));
    expect(api.createIDs.last, otherRequest);
    expect(api.uploads, 2);
    await create(restarted);
    expect(api.uploads, 3);
    expect(api.createBodies.last['uploadIDs'], ['u3']);
  });

  test('failed outbox acknowledgement keeps the asset and original UUID',
      () async {
    final api = CreateRecoveryCloud()
      ..nextCreateError = const FavoriteApiException(20056, 'original missing');
    final fault = CleanupFault();
    final repo = FavoriteRepository(
        api: api,
        userIDProvider: () => 'me',
        outbox: FavoriteMutationOutbox(store: fault));
    addTearDown(repo.dispose);
    await expectLater(create(repo), throwsA(code(20056)));
    expect(repo.pendingRecovery, hasLength(1));
    final oldBody = jsonEncode(api.createBodies.single);
    fault.denyComplete = false;
    api.nextCreateError = const FavoriteApiException(20056, 'original missing');
    await expectLater(create(repo), throwsA(code(20056)));
    expect(jsonEncode(api.createBodies.last), oldBody);
    expect(api.uploads, 1);
    expect(api.completeIDs, hasLength(1));
    await create(repo);
    expect(api.uploads, 2);
    expect(api.createIDs.last, isNot(api.createIDs.first));
  });

  test('failed renewal checkpoint preserves completed media and upload UUIDs',
      () async {
    final api = CreateRecoveryCloud()
      ..nextCreateError = const FavoriteApiException(20056, 'original missing');
    var denyReset = true;
    final repo = FavoriteRepository(
        api: api,
        userIDProvider: () => 'me',
        cacheWriter: (key, value) async {
          final parsed = jsonDecode(value) as Map;
          if (denyReset &&
              api.createIDs.isNotEmpty &&
              (parsed['mediaTasks'] as Map).isEmpty) {
            return false;
          }
          return (await SharedPreferences.getInstance()).setString(key, value);
        });
    addTearDown(repo.dispose);
    await expectLater(create(repo), throwsA(code('LOCAL_SAVE_FAILED')));
    final prefs = await SharedPreferences.getInstance();
    final before =
        jsonDecode(prefs.getString('${repo.accountNamespace}:metadata:v1')!)
            as Map;
    expect(
        (before['mediaTasks'] as Map).values.single['asset']['id'], 'asset-u1');
    expect((before['requests'] as Map).values,
        containsAll([api.initIDs.single, api.completeIDs.single]));
    denyReset = false;
    api.nextCreateError = const FavoriteApiException(20056, 'original missing');
    await expectLater(create(repo), throwsA(code(20056)));
    expect(api.uploads, 1);
    expect(api.completeIDs, hasLength(1));
    await create(repo);
    expect(api.uploads, 2);
    expect(api.initIDs.first, isNot(api.initIDs.last));
    expect(api.completeIDs.first, isNot(api.completeIDs.last));
  });

  test('lost original after rejection asks for reselection before any request',
      () async {
    final api = CreateRecoveryCloud()
      ..nextCreateError = const FavoriteApiException(20056, 'original missing');
    final repo = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(repo.dispose);
    await expectLater(create(repo), throwsA(code(20056)));
    await original.delete();
    await expectLater(
        create(repo),
        throwsA(code(20056).having(
            (failure) => failure.message, 'message', contains('请重新选择'))));
    expect(api.initIDs, hasLength(1));
    expect(api.createIDs, hasLength(1));
  });

  test('missing local bytes never retry an incomplete upload', () async {
    final api = CreateRecoveryCloud()..failComplete = true;
    final repo = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(repo.dispose);
    await expectLater(create(repo), throwsA(isA<FavoriteApiException>()));
    // An unfinished PUT requires the local original; it cannot be recovered
    // merely because the checkpoint retains an upload reservation ID.
    api.failComplete = false;
    await original.delete();
    final incomplete = jsonDecode((await SharedPreferences.getInstance())
        .getString('${repo.accountNamespace}:metadata:v1')!) as Map;
    for (final task in (incomplete['mediaTasks'] as Map).values) {
      (task as Map)['uploaded'] = false;
    }
    await (await SharedPreferences.getInstance()).setString(
        '${repo.accountNamespace}:metadata:v1', jsonEncode(incomplete));
    final restarted = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(restarted.dispose);
    await expectLater(create(restarted), throwsA(code(20056)));
    expect(api.uploads, 1);
    expect(api.completeIDs, hasLength(1));
  });

  test(
      'account switch before rejected create leaves old media checkpoint intact',
      () async {
    var user = 'me';
    final api = CreateRecoveryCloud()
      ..nextCreateError = const FavoriteApiException(20056, 'original missing')
      ..createEntered = Completer<void>()
      ..releaseCreate = Completer<void>();
    final entered = api.createEntered!;
    final repo = FavoriteRepository(api: api, userIDProvider: () => user);
    addTearDown(repo.dispose);
    final operation = create(repo);
    await entered.future;
    final namespace = repo.accountNamespace;
    user = 'other';
    api.releaseCreate!.complete();
    await expectLater(operation, throwsA(isA<FavoriteApiException>()));
    final prefs = await SharedPreferences.getInstance();
    final old = jsonDecode(prefs.getString('$namespace:metadata:v1')!) as Map;
    expect((old['mediaTasks'] as Map).values.single['asset']['id'], 'asset-u1');
    expect(api.uploads, 1);
  });
}
