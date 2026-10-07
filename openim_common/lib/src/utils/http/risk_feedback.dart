/// Display policy only. A silent rejection is still a failed request.
class RiskFeedback {
  RiskFeedback._();

  static const _friendPaths = {
    '/chat/friend-apply',
    '/chat/friend-grants',
    '/chat/friend-invites',
  };

  static bool isSilent({
    required int code,
    required String? path,
    String? detail,
  }) {
    final endpoint =
        Uri.tryParse(path ?? '')?.path.replaceFirst(RegExp(r'/+$'), '');
    if (!_friendPaths.contains(endpoint)) return false;
    // The older friend grant limiter returns 20020 with this exact reason.
    // Other 20020 reasons (expired invite, privacy settings) remain visible.
    return code == 20201 || (code == 20020 && detail == 'too frequent');
  }
}
