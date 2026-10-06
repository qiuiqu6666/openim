import 'customer_service_attachment.dart';
import 'customer_service_config.dart';

class CustomerServiceMessage {
  CustomerServiceMessage({
    required this.id,
    required this.content,
    required this.messageType,
    required this.echoId,
    required List<CustomerServiceAttachment> attachments,
    this.createdAt,
    this.conversationId = '',
  }) : attachments = List.unmodifiable(attachments);

  final String id, content, echoId, conversationId;
  final int messageType;
  final List<CustomerServiceAttachment> attachments;
  final DateTime? createdAt;

  factory CustomerServiceMessage.fromJson(Map<String, dynamic> json,
      {CustomerServiceConfig config = const CustomerServiceConfig()}) {
    final rows = json['attachments'];
    final conversation = json['conversation'];
    return CustomerServiceMessage(
      id: json['id']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      echoId: (json['echo_id'] ?? json['echoId'])?.toString() ?? '',
      conversationId: (json['conversation_id'] ??
                  json['conversationId'] ??
                  (conversation is Map ? conversation['id'] : null))
              ?.toString() ??
          '',
      messageType: _messageType(json),
      createdAt: _date(json['created_at'] ?? json['createdAt']),
      attachments: rows is List
          ? rows.whereType<Map>().map((row) {
              return CustomerServiceAttachment.fromJson(
                  Map<String, dynamic>.from(row),
                  config: config);
            }).toList()
          : const [],
    );
  }
}

int _messageType(Map<String, dynamic> json) {
  final sender = json['sender'];
  if (sender is Map) {
    final type = sender['type']?.toString().trim().toLowerCase();
    if (type == 'contact') return 0;
    if (const ['user', 'agent', 'agent_bot'].contains(type)) return 1;
  }
  final raw = json['message_type'] ?? json['messageType'];
  return switch (raw?.toString().trim().toLowerCase()) {
    'incoming' => 0,
    'outgoing' => 1,
    'activity' => 2,
    'template' => 3,
    final value => int.tryParse(value ?? '') ?? 0,
  };
}

DateTime? _date(dynamic value) {
  if (value == null) return null;
  final number = value is num ? value : num.tryParse(value.toString());
  if (number != null) {
    final milliseconds = number.abs() < 100000000000 ? number * 1000 : number;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds.toInt(),
        isUtc: true);
  }
  return DateTime.tryParse(value.toString());
}
