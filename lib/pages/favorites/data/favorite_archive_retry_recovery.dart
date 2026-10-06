import 'package:dio/dio.dart';

import '../../../services/favorite_api.dart';
import 'favorite_mutation_outbox.dart';

/// Completes a retry acknowledgement using authoritative detail reads. A saved
/// receipt prevents POST replay when only the following GET failed.
class FavoriteArchiveRetryRecovery {
  const FavoriteArchiveRetryRecovery(this.api);
  final FavoriteApi api;

  Future<FavoriteItem> recover(FavoriteMutationEntry entry, CancelToken cancel,
      {required Future<void> Function(FavoriteArchiveRetryAck) acknowledge,
      required void Function() guard}) async {
    if (entry.operation != FavoriteMutationOperation.retryArchive ||
        entry.itemID == null) {
      throw const FormatException('Invalid archive retry recovery');
    }
    final id = entry.itemID!;
    guard();
    if (entry.archiveRetryAck != null) {
      await acknowledge(entry.archiveRetryAck!);
      guard();
      return api.getDetail(id, cancelToken: cancel);
    }

    // Older servers check status before request replay. Recheck a recovered
    // intent first so pending/ready work is not submitted again with a new ID.
    final current = await api.getDetail(id, cancelToken: cancel);
    guard();
    if (current.status == FavoriteStatus.pendingArchive || current.isReady) {
      return current;
    }
    FavoriteArchiveRetryAck ack;
    try {
      ack = await api.retryArchive(id,
          clientRequestID: entry.clientRequestID, cancelToken: cancel);
      guard();
    } on FavoriteApiException catch (error) {
      if (error.code != 20057) rethrow;
      try {
        guard();
        final checked = await api.getDetail(id, cancelToken: cancel);
        guard();
        if (checked.status == FavoriteStatus.pendingArchive ||
            checked.isReady) {
          return checked;
        }
      } on FavoriteApiException catch (readingError) {
        if (readingError.isCancelled) rethrow;
        throw const FavoriteApiException(
            'ARCHIVE_RETRY_NEEDS_RECHECK', '归档状态已变化，请刷新收藏确认结果',
            isUncertain: true);
      }
      rethrow;
    }
    await acknowledge(ack);
    guard();
    return api.getDetail(id, cancelToken: cancel);
  }
}
