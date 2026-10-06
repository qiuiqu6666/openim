import '../../../services/favorite_repository.dart';

/// Refreshes expired prepare credentials while preserving the logical attempt
/// and immutable revision. Grants are returned to the current call only.
class FavoritePrepareLease {
  FavoritePrepareLease(this.repository, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final FavoriteRepository repository;
  final DateTime Function() _clock;

  Future<FavoritePreparedSend> prepare({
    required String favoriteID,
    required String contentRevision,
    required String sendAttemptID,
    required String clientRequestID,
    required Future<String> Function() renewRequestID,
    required void Function() guard,
  }) async {
    var requestID = clientRequestID;
    for (var attempt = 0; attempt < 2; attempt++) {
      guard();
      try {
        final prepared = await repository.prepareForSend(favoriteID,
            expectedContentRevision: contentRevision,
            sendAttemptID: sendAttemptID,
            clientRequestID: requestID);
        guard();
        if (prepared.contentRevision != contentRevision) {
          throw const FavoriteApiException(20061, '收藏发送版本已变化，请重新选择内容');
        }
        final now = _clock();
        if (prepared.expiresAt.isAfter(now) &&
            prepared.downloads.every((grant) =>
                grant.expiresAt == null || grant.expiresAt!.isAfter(now))) {
          return prepared;
        }
        throw const FavoriteApiException(20063, '发送准备已过期，请重试');
      } on FavoriteApiException catch (error) {
        if (!isExpired(error.code) || attempt != 0) rethrow;
        guard();
        // The caller persists the new UUID before a replacement request.
        requestID = await renewRequestID();
        guard();
      }
    }
    throw const FavoriteApiException(20063, '发送准备已过期，请重试');
  }

  static bool isExpired(Object? code) =>
      code?.toString() == '20063' || code == 'PREPARE_EXPIRED';
}
