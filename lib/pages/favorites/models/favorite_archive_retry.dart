import '../../../services/favorite_models.dart';

/// The retry endpoint acknowledges a job, not a favorite detail response.
class FavoriteArchiveRetryAck {
  const FavoriteArchiveRetryAck({required this.jobID, required this.status});

  final String jobID;
  final FavoriteStatus status;

  factory FavoriteArchiveRetryAck.fromJson(Map<String, dynamic> json) {
    final jobID = json['jobID'];
    if (jobID is! String ||
        jobID.trim().isEmpty ||
        json['status'] != 'pending_archive') {
      throw const FormatException(
          'Invalid favorite archive retry acknowledgement');
    }
    return FavoriteArchiveRetryAck(
        jobID: jobID, status: FavoriteStatus.pendingArchive);
  }

  Map<String, dynamic> toJson() => {'jobID': jobID, 'status': status.wireName};
}
