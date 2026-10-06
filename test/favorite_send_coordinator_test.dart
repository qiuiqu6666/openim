import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/favorite_message_builder.dart';
import 'package:openim/services/favorite_models.dart';
import 'package:openim/services/favorite_send_coordinator.dart';

import 'support/favorite_test_fakes.dart';

void main() {
  late Directory directory;
  late FakeFavoriteFactory factory;
  late MemoryFavoriteTaskStore store;
  const target = FavoriteTarget(
      conversationID: 'target-conversation', userID: 'recipient');
  setUp(() async {
    directory =
        await Directory.systemTemp.createTemp('favorite-coordinator-test-');
    factory = FakeFavoriteFactory();
    store = MemoryFavoriteTaskStore();
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });
  FavoriteMessageBuilder builder() => FavoriteMessageBuilder(
      messageFactory: factory,
      downloader: FakeFavoriteDownloader({}),
      directoryProvider: () async => directory);
  FavoriteSendCoordinator coordinator(
          FakeFavoriteRepository repository, FavoriteSendCallback sender) =>
      FavoriteSendCoordinator(
          repository: repository,
          builder: builder(),
          taskStore: store,
          lookup: (message, _) async =>
              FavoriteSendResult.unknown(clientMsgID: message.clientMsgID),
          sender: sender);
  FavoriteSendResult success(Message message) => FavoriteSendResult.success(
      message: Message.fromJson(message.toJson())
        ..status = MessageStatus.succeeded);

  test(
      'concurrent clicks create and send once; confirmed new clicks send again',
      () async {
    final item = favoriteTextItem();
    final repo = FakeFavoriteRepository(item);
    final receipt = Completer<FavoriteSendResult>();
    final started = Completer<Message>();
    var sent = 0;
    final sender = coordinator(repo, (message, destination) {
      sent++;
      expect(destination.key, target.key);
      if (!started.isCompleted) {
        started.complete(message);
        return receipt.future;
      }
      return Future.value(success(message));
    });
    final first = sender.send(item, target);
    final message = await started.future;
    final second = sender.send(item, target);
    receipt.complete(success(message));
    expect((await first).status, FavoriteSendStatus.success);
    expect((await second).status, FavoriteSendStatus.success);
    expect(sent, 1);
    expect(factory.count, 1);
    expect(
        (await sender.send(item, target)).status, FavoriteSendStatus.success);
    expect(sent, 2);
    expect(factory.count, 2);
  });
  test('unknown survives app restart and never rebuilds or resubmits',
      () async {
    final item = favoriteTextItem();
    final repo = FakeFavoriteRepository(item);
    var sent = 0;
    final first = coordinator(repo, (message, _) async {
      sent++;
      return FavoriteSendResult.unknown(clientMsgID: message.clientMsgID);
    });
    final unknown = await first.send(item, target);
    expect(unknown.status, FavoriteSendStatus.unknown);
    final restored = coordinator(repo, (message, _) async {
      sent++;
      return success(message);
    });
    expect(
        (await restored.send(item, target)).status, FavoriteSendStatus.unknown);
    expect((await restored.retry(unknown.sendAttemptID!)).status,
        FavoriteSendStatus.unknown);
    expect(sent, 1);
    expect(factory.count, 1);
    expect(repo.prepareCalls, 1);
    expect(jsonEncode(store.values), isNot(contains('privateSignature')));
    expect(jsonEncode(store.values), isNot(contains('private-source')));
    expect(
        (await restored.reconcile(unknown.sendAttemptID!,
                lookup: (message, _) async => success(message)))
            .status,
        FavoriteSendStatus.success);
    expect(
        (await restored.send(item, target)).status, FavoriteSendStatus.success);
    expect(sent, 2);
    expect(factory.count, 2);
  });
  test('crash after durable submitting also restores unknown', () async {
    final item = favoriteTextItem();
    final repo = FakeFavoriteRepository(item);
    final submitted = Completer<void>();
    final receipt = Completer<FavoriteSendResult>();
    final first = coordinator(repo, (message, _) {
      submitted.complete();
      return receipt.future;
    });
    final pending = first.send(item, target);
    await submitted.future;
    var resubmitted = 0;
    final restored = coordinator(repo, (message, _) async {
      resubmitted++;
      return success(message);
    });
    expect(
        (await restored.send(item, target)).status, FavoriteSendStatus.unknown);
    expect(resubmitted, 0);
    expect(factory.count, 1);
    receipt.complete(FavoriteSendResult.unknown(clientMsgID: 'new-1'));
    await pending;
  });
  test('partial failures retry only failed steps with their original IDs',
      () async {
    final item = favoriteTextItem(blocks: const [
      FavoriteBlock(id: '1', type: 'text', text: 'first'),
      FavoriteBlock(id: '2', type: 'text', text: 'second')
    ]);
    final repo = FakeFavoriteRepository(item);
    final submitted = <String>[];
    var rejected = false;
    final sender = coordinator(repo, (message, _) async {
      submitted.add(message.clientMsgID!);
      if (message.clientMsgID == 'new-2' && !rejected) {
        rejected = true;
        return FavoriteSendResult.failed(
            clientMsgID: message.clientMsgID,
            retryable: true,
            errorCode: 'EXPLICIT_REJECTION');
      }
      return success(message);
    });
    final partial = await sender.send(item, target);
    expect(partial.status, FavoriteSendStatus.failed);
    expect(partial.sentCount, 1);
    expect(partial.totalCount, 2);
    final retried = await sender.retry(partial.sendAttemptID!);
    expect(retried.status, FavoriteSendStatus.success);
    expect(retried.sentCount, 2);
    expect(submitted, ['new-1', 'new-2', 'new-2']);
    expect(factory.count, 2);
    expect(repo.prepareCalls, 1);
  });
  test('account changes during preparation prevent SDK sending', () async {
    final item = favoriteTextItem();
    final repo = FakeFavoriteRepository(item);
    var sent = 0;
    final sender = coordinator(repo, (message, _) async {
      sent++;
      return success(message);
    });
    final result = await sender.send(item, target, onProgress: (progress) {
      if (progress.stage == 'building') {
        repo.owner = 'other';
        sender.resetSession();
      }
    });
    expect(result.status, FavoriteSendStatus.failed);
    expect(sent, 0);
    expect(result.errorCode, 'SESSION_CHANGED');
  });
  test('new account cannot see or resume old unresolved sends', () async {
    final item = favoriteTextItem();
    final repo = FakeFavoriteRepository(item);
    var sent = 0;
    final sender = coordinator(repo, (message, _) async {
      sent++;
      return FavoriteSendResult.unknown(clientMsgID: message.clientMsgID);
    });
    final old = await sender.send(item, target);
    repo.owner = 'other';
    sender.resetSession();
    final other = await sender.send(item, target, onSend: (message, _) async {
      sent++;
      return success(message);
    });
    expect(other.status, FavoriteSendStatus.success);
    expect(other.sendAttemptID, isNot(old.sendAttemptID));
    expect(sent, 2);
  });
  test('mismatched receipt cannot be mistaken for accepted success', () async {
    final item = favoriteTextItem();
    final repo = FakeFavoriteRepository(item);
    var sent = 0;
    final sender = coordinator(repo, (message, _) async {
      sent++;
      return FavoriteSendResult.success(message: Message(clientMsgID: 'wrong'));
    });
    expect(
        (await sender.send(item, target)).status, FavoriteSendStatus.unknown);
    expect(
        (await sender.send(item, target)).status, FavoriteSendStatus.unknown);
    expect(sent, 1);
  });

  test('a fixed batch attempt reuses confirmed success after restart',
      () async {
    final item = favoriteTextItem();
    final repo = FakeFavoriteRepository(item);
    var sent = 0;
    const attempt = 'stable-batch-attempt';
    final first = coordinator(repo, (message, _) async {
      sent++;
      return success(message);
    });
    expect((await first.send(item, target, sendAttemptID: attempt)).isSuccess,
        isTrue);
    expect(jsonEncode(store.values), isNot(contains('hello')));
    final restored = coordinator(repo, (message, _) async {
      sent++;
      return success(message);
    });
    final result = await restored.send(item, target, sendAttemptID: attempt);
    expect(result.status, FavoriteSendStatus.success);
    expect(result.sendAttemptID, attempt);
    expect(result.sentCount, 1);
    expect(result.totalCount, 1);
    expect(result.clientMsgID, 'new-1');
    expect(sent, 1);
    expect(factory.count, 1);
    final conflict = await restored.send(
        favoriteTextItem(id: 'different'), target,
        sendAttemptID: attempt);
    expect(conflict.errorCode, 'IDEMPOTENCY_CONFLICT');
    expect(sent, 1);
  });

  test(
      'terminal rejection does not permanently lock intentional future actions',
      () async {
    final item = favoriteTextItem();
    final repo = FakeFavoriteRepository(item);
    var sent = 0;
    final sender = coordinator(repo, (message, _) async {
      sent++;
      if (sent == 1) {
        return FavoriteSendResult.failed(
            clientMsgID: message.clientMsgID,
            errorCode: 'EXPLICIT_PERMISSION_REJECTION');
      }
      return success(message);
    });
    expect((await sender.send(item, target)).status, FavoriteSendStatus.failed);
    expect(
        (await sender.send(item, target)).status, FavoriteSendStatus.success);
    expect(sent, 2);
    expect(factory.count, 2);
  });

  test('a fixed batch ID durably adopts a reconciled manual unknown send',
      () async {
    final item = favoriteTextItem();
    final repo = FakeFavoriteRepository(item);
    var sent = 0;
    const batchID = 'batch-adopts-manual-unknown';
    final manual = coordinator(repo, (message, _) async {
      sent++;
      return FavoriteSendResult.unknown(clientMsgID: message.clientMsgID);
    });
    final original = await manual.send(item, target);
    final batch = FavoriteSendCoordinator(
        repository: repo,
        builder: builder(),
        taskStore: store,
        sender: (message, _) async {
          sent++;
          return success(message);
        },
        lookup: (message, _) async {
          // The batch cell ID must already be durable before confirming IM.
          expect(store.values[repo.accountNamespace]!.single['aliasAttemptIDs'],
              contains(batchID));
          return success(message);
        });
    expect((await batch.send(item, target, sendAttemptID: batchID)).isSuccess,
        isTrue);
    // Simulate a crash before the parent batch wrote its completed-cell count.
    final restored = coordinator(repo, (message, _) async {
      sent++;
      return success(message);
    });
    final accepted = await restored.send(item, target, sendAttemptID: batchID);
    expect(accepted.isSuccess, isTrue);
    expect(accepted.sendAttemptID, original.sendAttemptID);
    expect(accepted.clientMsgID, original.clientMsgID);
    expect(sent, 1);
    expect(factory.count, 1);
    expect((await restored.retry(batchID)).isSuccess, isTrue);
    expect((await restored.reconcile(batchID)).isSuccess, isTrue);
    final conflict = await restored.send(
        favoriteTextItem(id: 'another-favorite'), target,
        sendAttemptID: batchID);
    expect(conflict.errorCode, 'IDEMPOTENCY_CONFLICT');
  });

  test('a fixed batch ID adopts an active send before its receipt is returned',
      () async {
    final item = favoriteTextItem();
    final repo = FakeFavoriteRepository(item);
    final entered = Completer<Message>();
    final response = Completer<FavoriteSendResult>();
    var sent = 0;
    const batchID = 'batch-adopts-active-manual';
    final sender = coordinator(repo, (message, _) {
      sent++;
      entered.complete(message);
      return response.future;
    });
    final manual = sender.send(item, target);
    final message = await entered.future;
    final batch = sender.send(item, target, sendAttemptID: batchID);
    response.complete(success(message));
    expect((await manual).isSuccess, isTrue);
    expect((await batch).isSuccess, isTrue);
    final restored = coordinator(repo, (message, _) async {
      sent++;
      return success(message);
    });
    expect(
        (await restored.send(item, target, sendAttemptID: batchID)).isSuccess,
        isTrue);
    expect(sent, 1);
    expect(factory.count, 1);
  });

  test('an unsaved batch alias must persist before a later receipt is returned',
      () async {
    final item = favoriteTextItem();
    final repo = FakeFavoriteRepository(item);
    final journal = _FailAliasSaveStore();
    var lookups = 0;
    var sent = 0;
    final sender = FavoriteSendCoordinator(
        repository: repo,
        builder: builder(),
        taskStore: journal,
        sender: (message, _) async {
          sent++;
          return FavoriteSendResult.unknown(clientMsgID: message.clientMsgID);
        },
        lookup: (message, _) async {
          lookups++;
          expect(
              journal.values[repo.accountNamespace]!.single['aliasAttemptIDs'],
              contains('alias-after-write-failure'));
          return success(message);
        });
    await sender.send(item, target);
    expect(
        (await sender.send(item, target,
                sendAttemptID: 'alias-after-write-failure'))
            .errorCode,
        'TASK_SAVE_FAILED');
    expect(lookups, 0);
    expect(
        (await sender.send(item, target,
                sendAttemptID: 'alias-after-write-failure'))
            .isSuccess,
        isTrue);
    expect(lookups, 1);
    expect(sent, 1);
  });

  test(
      'partial permission rejection resumes without duplicating the accepted block',
      () async {
    final item = favoriteTextItem(blocks: const [
      FavoriteBlock(id: '1', type: 'text', text: 'first'),
      FavoriteBlock(id: '2', type: 'text', text: 'second')
    ]);
    final repo = FakeFavoriteRepository(item);
    final submitted = <String>[];
    var rejected = false;
    final sender = coordinator(repo, (message, _) async {
      submitted.add(message.clientMsgID!);
      if (message.clientMsgID == 'new-2' && !rejected) {
        rejected = true;
        return FavoriteSendResult.failed(
            clientMsgID: message.clientMsgID,
            errorCode: 'EXPLICIT_PERMISSION_REJECTION');
      }
      return success(message);
    });
    final failure = await sender.send(item, target);
    expect(failure.sentCount, 1);
    expect((await sender.send(item, target)).isSuccess, isTrue);
    expect(submitted, ['new-1', 'new-2', 'new-2']);
    expect(factory.count, 2);
  });

  test('a restored bubble resolves its unknown task and accepted tombstone',
      () async {
    final item = favoriteTextItem();
    final repo = FakeFavoriteRepository(item);
    var sent = 0;
    final original = coordinator(repo, (message, _) async {
      sent++;
      return FavoriteSendResult.unknown(clientMsgID: message.clientMsgID);
    });
    final unknown = await original.send(item, target);
    final restored = coordinator(repo, (message, _) async {
      sent++;
      return success(message);
    });
    expect(await restored.pendingAttemptForMessage(unknown.clientMsgID!),
        unknown.sendAttemptID);
    expect((await restored.retry(unknown.sendAttemptID!)).status,
        FavoriteSendStatus.unknown);
    expect(
        (await restored.reconcile(unknown.sendAttemptID!,
                lookup: (message, _) async => success(message)))
            .isSuccess,
        isTrue);
    final accepted = coordinator(repo, (message, _) async {
      sent++;
      return success(message);
    });
    expect(await accepted.pendingAttemptForMessage(unknown.clientMsgID!),
        unknown.sendAttemptID);
    expect(await accepted.pendingAttemptForMessage('unrelated'), isNull);
    expect(sent, 1);
    expect(factory.count, 1);
  });

  test('unknown click may confirm a receipt but cannot submit remaining blocks',
      () async {
    final item = favoriteTextItem(blocks: const [
      FavoriteBlock(id: '1', type: 'text', text: 'first'),
      FavoriteBlock(id: '2', type: 'text', text: 'second')
    ]);
    final repo = FakeFavoriteRepository(item);
    var sent = 0;
    final first = coordinator(repo, (message, _) async {
      sent++;
      return FavoriteSendResult.unknown(clientMsgID: message.clientMsgID);
    });
    final unknown = await first.send(item, target);
    final restored = FavoriteSendCoordinator(
        repository: repo,
        builder: builder(),
        taskStore: store,
        sender: (message, _) async {
          sent++;
          return success(message);
        },
        lookup: (message, _) async => success(message));
    final confirmed = await restored.send(item, target);
    expect(confirmed.errorCode, 'PARTIAL_READY');
    expect(confirmed.sentCount, 1);
    expect(sent, 1);
    expect(factory.count, 2);
    expect((await restored.retry(unknown.sendAttemptID!)).isSuccess, isTrue);
    expect(sent, 2);
    expect(factory.count, 2);
  });

  test('token generation changes reload an in-flight submission as unknown',
      () async {
    final item = favoriteTextItem();
    final repo = FakeFavoriteRepository(item);
    final entered = Completer<Message>();
    final response = Completer<FavoriteSendResult>();
    var sent = 0;
    final sender = coordinator(repo, (message, _) {
      sent++;
      entered.complete(message);
      return response.future;
    });
    final pending = sender.send(item, target);
    final message = await entered.future;
    repo.sessionVersion++;
    expect(
        (await sender.send(item, target)).status, FavoriteSendStatus.unknown);
    response.complete(success(message));
    expect((await pending).status, FavoriteSendStatus.unknown);
    expect(
        (await sender.send(item, target)).status, FavoriteSendStatus.unknown);
    expect(sent, 1);
    expect(factory.count, 1);
  });

  test('receipt journal failure retains an unknown barrier in this process',
      () async {
    final item = favoriteTextItem();
    final repo = FakeFavoriteRepository(item);
    final journal = _FailReceiptSaveStore();
    var sent = 0;
    final sender = FavoriteSendCoordinator(
        repository: repo,
        builder: builder(),
        taskStore: journal,
        sender: (message, _) async {
          sent++;
          return success(message);
        },
        lookup: (message, _) async =>
            FavoriteSendResult.unknown(clientMsgID: message.clientMsgID));
    expect(
        (await sender.send(item, target)).status, FavoriteSendStatus.unknown);
    expect(
        (await sender.send(item, target)).status, FavoriteSendStatus.unknown);
    expect(sent, 1);
    expect(factory.count, 1);
  });

  test('media rows with blocks still resolve complete detail asset metadata',
      () async {
    final asset = favoriteAsset('original-image', [1, 2, 3]);
    const content = FavoriteContent(kind: FavoriteKind.image, blocks: [
      FavoriteBlock(id: 'b1', type: 'image', assetID: 'original-image')
    ]);
    const row = FavoriteItem(
        id: 'photo',
        kind: FavoriteKind.image,
        title: 'photo',
        version: 1,
        contentRevision: 'revision-1',
        status: FavoriteStatus.ready,
        content: content);
    final detail = FavoriteItem(
        id: row.id,
        kind: row.kind,
        title: row.title,
        version: row.version,
        contentRevision: row.contentRevision,
        status: row.status,
        content: content,
        assets: [asset]);
    final repo = FakeFavoriteRepository(detail,
        prepared: favoritePrepared(content.blocks,
            kind: FavoriteKind.image, downloads: [favoriteGrant(asset)]));
    final downloader = FakeFavoriteDownloader({
      'original-image': [1, 2, 3]
    });
    var submitted = 0;
    final sender = FavoriteSendCoordinator(
        repository: repo,
        taskStore: store,
        builder: FavoriteMessageBuilder(
            messageFactory: factory,
            downloader: downloader,
            directoryProvider: () async => directory),
        sender: (message, _) async {
          submitted++;
          return success(message);
        });
    expect((await sender.send(row, target)).isSuccess, isTrue);
    expect(downloader.downloaded, ['original-image']);
    expect(submitted, 1);
  });

  test(
      'reopening an unknown send uses the caller query callback without resubmission',
      () async {
    final item = favoriteTextItem();
    final repo = FakeFavoriteRepository(item);
    var sent = 0, defaultLookups = 0, visibleChatLookups = 0;
    final sender = FavoriteSendCoordinator(
        repository: repo,
        builder: builder(),
        taskStore: store,
        sender: (message, _) async {
          sent++;
          return FavoriteSendResult.unknown(clientMsgID: message.clientMsgID);
        },
        lookup: (message, _) async {
          defaultLookups++;
          return FavoriteSendResult.unknown(clientMsgID: message.clientMsgID);
        });
    await sender.send(item, target);
    final result = await sender.send(item, target, lookup: (message, _) async {
      visibleChatLookups++;
      return success(message);
    });
    expect(result.isSuccess, isTrue);
    expect(visibleChatLookups, 1);
    expect(defaultLookups, 0);
    expect(sent, 1);
    expect(factory.count, 1);
  });
}

class _FailReceiptSaveStore extends MemoryFavoriteTaskStore {
  bool failed = false;
  @override
  Future<void> save(String namespace, List<Map<String, dynamic>> tasks) async {
    if (!failed &&
        tasks.any((task) => (task['result'] as Map?)?['status'] == 'success')) {
      failed = true;
      throw const FavoriteBuildException('TASK_SAVE_FAILED', '无法保存发送状态',
          retryable: true);
    }
    await super.save(namespace, tasks);
  }
}

class _FailAliasSaveStore extends MemoryFavoriteTaskStore {
  bool failed = false;
  @override
  Future<void> save(String namespace, List<Map<String, dynamic>> tasks) async {
    if (!failed &&
        tasks.any((task) => (task['aliasAttemptIDs'] as List).isNotEmpty)) {
      failed = true;
      throw const FavoriteBuildException('TASK_SAVE_FAILED', '无法保存发送状态',
          retryable: true);
    }
    await super.save(namespace, tasks);
  }
}
