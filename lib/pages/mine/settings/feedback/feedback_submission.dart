import '../settings_service.dart';

/// Optional report context for the shared feedback form. The caller owns data access.
class FeedbackSubmission {
  const FeedbackSubmission(
      {required this.target, required this.reason, required this.submit});
  final String target;
  final String reason;
  final Future<String> Function(String requestID, String content,
      List<SettingsFeedbackAttachment> attachments) submit;
}
