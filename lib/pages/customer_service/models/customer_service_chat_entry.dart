import '../data/data.dart';

enum CustomerServiceSendState { sending, sent, failed }

class CustomerServiceUpload {
  const CustomerServiceUpload({
    required this.path,
    required this.filename,
    required this.fileType,
    this.width = 0,
    this.height = 0,
    this.thumbnailPath = '',
  });

  final String path, filename, fileType, thumbnailPath;
  final int width, height;
}

/// Keeps a local attachment available while the server acknowledges its echo.
class CustomerServiceChatEntry {
  const CustomerServiceChatEntry({
    required this.echoId,
    this.text = '',
    this.upload,
    this.message,
    this.state = CustomerServiceSendState.sent,
  });

  final String echoId, text;
  final CustomerServiceUpload? upload;
  final CustomerServiceMessage? message;
  final CustomerServiceSendState state;

  String get key => message?.id.isNotEmpty == true
      ? 'message-${message!.id}'
      : 'echo-$echoId';
  String get content =>
      message?.content.isNotEmpty == true ? message!.content : text;
  bool get outgoing => message == null || message!.messageType == 0;
  bool get system => message != null && message!.messageType >= 2;
  List<CustomerServiceAttachment> get attachments =>
      message?.attachments ?? const [];

  CustomerServiceChatEntry withState(CustomerServiceSendState value) =>
      CustomerServiceChatEntry(
        echoId: echoId,
        text: text,
        upload: upload,
        message: message,
        state: value,
      );
}
