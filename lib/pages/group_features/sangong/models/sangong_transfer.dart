// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
class SangongTransfer {
  const SangongTransfer({
    required this.id,
    required this.referenceId,
    required this.sessionId,
    required this.amount,
    required this.direction,
    required this.counterpartImUserId,
    required this.counterpartNickname,
    required this.counterpartAvatarUrl,
    required this.createdAt,
  });

  final int id;
  final String referenceId;
  final int sessionId;
  final num amount;
  final String direction;
  final String counterpartImUserId;
  final String counterpartNickname;
  final String counterpartAvatarUrl;
  final String createdAt;

  bool get isOutgoing => direction == 'out';
  String get displayName => counterpartNickname.trim().isNotEmpty
      ? counterpartNickname.trim()
      : counterpartImUserId.trim().isNotEmpty
          ? counterpartImUserId.trim()
          : '未知用户';

  factory SangongTransfer.fromJson(Map<String, dynamic> json) {
    num number(String key) => num.tryParse('${json[key]}') ?? 0;
    String text(String key) => json[key]?.toString() ?? '';
    final direction = text('direction');
    if (direction != 'in' && direction != 'out') {
      throw const FormatException('Invalid transfer direction');
    }
    final prefix = direction == 'out' ? 'to' : 'from';
    String counterpart(String suffix) {
      final value = text('counterpart$suffix').trim();
      return value.isEmpty ? text('$prefix$suffix').trim() : value;
    }

    return SangongTransfer(
      id: number('id').toInt(),
      referenceId: text('referenceId'),
      sessionId: number('sessionId').toInt(),
      amount: number('amount'),
      direction: direction,
      counterpartImUserId: counterpart('ImUserId'),
      counterpartNickname: counterpart('Nickname'),
      counterpartAvatarUrl: counterpart('AvatarUrl'),
      createdAt: text('createdAt'),
    );
  }
}
