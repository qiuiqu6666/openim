import 'package:dio/dio.dart';
import '../../../services/favorite_api.dart';

/// Consumes time-watermark pages, including complete same-millisecond groups.
/// The owner commits each page atomically before requesting the next watermark.
class FavoriteChangeSynchronizer {
  const FavoriteChangeSynchronizer(this.api);
  final FavoriteApi api;

  Future<void> run(
      {required int updatedAfter,
      required CancelToken cancelToken,
      required Future<void> Function(FavoriteChangesPage) commit,
      required Future<void> Function() rebuild,
      int limit = 100}) async {
    var watermark = updatedAfter;
    var rebuilt = false;
    while (!cancelToken.isCancelled) {
      FavoriteChangesPage page;
      try {
        page = await api.changes(
            updatedAfter: watermark, limit: limit, cancelToken: cancelToken);
      } on FavoriteApiException catch (failure) {
        if (!failure.isCursorExpired || rebuilt || watermark == 0) rethrow;
        await rebuild();
        watermark = 0;
        rebuilt = true;
        continue;
      }
      await commit(page);
      watermark = page.syncAt;
      if (!page.hasMore) return;
    }
    throw const FavoriteApiException('CANCELLED', '操作已取消', isCancelled: true);
  }
}
