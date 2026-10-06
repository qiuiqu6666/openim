class AiAssistantException implements Exception {
  const AiAssistantException(this.code, this.message);

  final String code;
  final String message;
  bool get isBusy => code == 'CHAT_BUSY';
  bool get cancelled => code == 'CANCELLED';
  bool get unavailable => code == 'SERVICE_UNAVAILABLE' || code == 'MAIN_UNAVAILABLE';
  bool get authRequired => code == 'UNAUTHORIZED' || code == 'SESSION_CHANGED';

  @override
  String toString() => message.isEmpty ? code : message;
}
