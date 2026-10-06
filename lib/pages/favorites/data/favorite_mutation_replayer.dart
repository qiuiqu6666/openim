import 'package:dio/dio.dart';
import '../../../services/favorite_api.dart';
import 'favorite_mutation_outbox.dart';
import 'favorite_archive_retry_recovery.dart';

class FavoriteMutationReplayResult {
  const FavoriteMutationReplayResult(
      {this.item, this.batch, this.deletedID, this.deletedVersion});
  final FavoriteItem? item;
  final FavoriteBatchDeleteResult? batch;
  final String? deletedID;
  final int? deletedVersion;
}

/// Replays only authenticated favorites writes through the validated API. IM
/// messages, prepare grants and signed storage requests are never replayed here.
class FavoriteMutationReplayer {
  const FavoriteMutationReplayer(this.api,
      {this.onArchiveRetryAcknowledged, this.guard});
  final FavoriteApi api;
  final void Function()? guard;
  final Future<void> Function(FavoriteMutationEntry, FavoriteArchiveRetryAck)?
      onArchiveRetryAcknowledged;

  Future<FavoriteMutationReplayResult> replay(
      FavoriteMutationEntry entry, CancelToken cancel) async {
    final body = entry.body;
    switch (entry.operation) {
      case FavoriteMutationOperation.createMessage:
        return FavoriteMutationReplayResult(
            item: await api.createFromMessage(
                source:
                    FavoriteSource.fromJson(favoriteJsonMap(body['source'])),
                clientRequestID: entry.clientRequestID,
                cancelToken: cancel));
      case FavoriteMutationOperation.create:
        final kind = FavoriteKind.parse(body['kind'] as String);
        return FavoriteMutationReplayResult(
            item: await api.create(
                kind: kind,
                content: FavoriteContent.fromJson(
                    favoriteJsonMap(body['content']),
                    kind: kind),
                title: body['title'] as String? ?? '',
                uploadIDs: List<String>.from(body['uploadIDs'] as List? ?? []),
                assetIDs: List<String>.from(body['assetIDs'] as List? ?? []),
                clientRequestID: entry.clientRequestID,
                cancelToken: cancel));
      case FavoriteMutationOperation.update:
        return FavoriteMutationReplayResult(
            item: await api.update(entry.itemID!,
                expectedVersion: body['expectedVersion'] as int,
                title: body['title'] as String?,
                content: body['content'] == null
                    ? null
                    : FavoriteContent.fromJson(favoriteJsonMap(body['content']),
                        kind: FavoriteKind.note),
                clientRequestID: entry.clientRequestID,
                cancelToken: cancel));
      case FavoriteMutationOperation.delete:
        final version = body['expectedVersion'] as int;
        await api.delete(entry.itemID!,
            expectedVersion: version,
            clientRequestID: entry.clientRequestID,
            cancelToken: cancel);
        return FavoriteMutationReplayResult(
            deletedID: entry.itemID, deletedVersion: version + 1);
      case FavoriteMutationOperation.batchDelete:
        final items = (body['items'] as List).map((value) {
          final item = favoriteJsonMap(value);
          return FavoriteItem(
              id: item['id'] as String,
              kind: FavoriteKind.unknown,
              title: '',
              version: item['expectedVersion'] as int,
              status: FavoriteStatus.ready);
        }).toList();
        return FavoriteMutationReplayResult(
            batch: await api.batchDelete(items,
                clientRequestID: entry.clientRequestID, cancelToken: cancel));
      case FavoriteMutationOperation.retryArchive:
        final checkpoint = onArchiveRetryAcknowledged;
        if (checkpoint == null || guard == null) {
          throw StateError('Archive retry requires a durable acknowledgement');
        }
        return FavoriteMutationReplayResult(
            item: await FavoriteArchiveRetryRecovery(api).recover(entry, cancel,
                guard: guard!, acknowledge: (ack) => checkpoint(entry, ack)));
    }
  }
}
