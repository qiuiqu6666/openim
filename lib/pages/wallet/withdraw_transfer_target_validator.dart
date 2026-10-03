import 'tron_address_validator.dart';

enum WithdrawTransferTargetKind { chain, friend }

class WithdrawTransferTarget {
  const WithdrawTransferTarget._({required this.kind, required this.value});

  final WithdrawTransferTargetKind kind;
  final String value;

  factory WithdrawTransferTarget.chain(String address) =>
      WithdrawTransferTarget._(
        kind: WithdrawTransferTargetKind.chain,
        value: address,
      );

  factory WithdrawTransferTarget.friend(String userId) =>
      WithdrawTransferTarget._(
        kind: WithdrawTransferTargetKind.friend,
        value: userId,
      );

  bool get isChain => kind == WithdrawTransferTargetKind.chain;
  bool get isFriend => kind == WithdrawTransferTargetKind.friend;
}

class WithdrawTransferTargetValidator {
  WithdrawTransferTargetValidator._();

  static final RegExp _chatUserIdRegExp = RegExp(r'^[A-Za-z0-9]{10}$');

  static String normalizePlainText(String value) {
    return value
        .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
        .replaceAll(RegExp(r'[\r\n\t]'), '')
        .trim();
  }

  static String? normalizeChatUserId(String value) {
    var id = normalizePlainText(value);
    if (id.isEmpty) return null;
    if (id.startsWith('@')) id = id.substring(1).trim();
    if (id.isEmpty || id.startsWith('@TOA#_') || id.contains('@TGS#')) {
      return null;
    }
    return id;
  }

  static bool isTronAddress(String value) => TronAddressValidator.isValid(value);

  static String? extractTronAddress(String rawValue) {
    final trimmed = rawValue
        .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
        .trim();
    if (trimmed.isEmpty) return null;
    if (isTronAddress(trimmed)) return trimmed;
    final compact = trimmed.replaceAll(RegExp(r'\s+'), '');
    if (isTronAddress(compact)) return compact;
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.scheme.toLowerCase() == 'tron') {
      final candidate = (uri.path.isNotEmpty ? uri.path : uri.host)
          .replaceAll(RegExp(r'\s+'), '');
      if (isTronAddress(candidate)) return candidate;
    }
    final pattern = RegExp(r'T[1-9A-HJ-NP-Za-km-z]{33}');
    for (final match in pattern.allMatches(trimmed)) {
      final candidate = match.group(0);
      if (candidate != null && isTronAddress(candidate)) return candidate;
    }
    return null;
  }

  static String normalizedTargetValue(String value) {
    final tronAddress = extractTronAddress(value);
    if (tronAddress != null) return tronAddress;
    return normalizeChatUserId(value) ?? normalizePlainText(value);
  }

  static bool isValidChatUserId(String value) {
    final id = normalizeChatUserId(value);
    if (id == null || id.isEmpty || isTronAddress(id)) return false;
    return _chatUserIdRegExp.hasMatch(id);
  }

  static WithdrawTransferTarget? resolve({
    required String raw,
    required bool Function(String userId) isBlockedUserId,
    String? Function(String target)? resolveFriendUserId,
  }) {
    final tron = extractTronAddress(raw);
    if (tron != null) return WithdrawTransferTarget.chain(tron);

    final plain = normalizePlainText(raw);
    if (plain.isEmpty) return null;

    final friendUserId = resolveFriendUserId?.call(plain)?.trim() ?? '';
    if (friendUserId.isNotEmpty) {
      if (isBlockedUserId(friendUserId)) return null;
      return WithdrawTransferTarget.friend(friendUserId);
    }

    final chatUserId = normalizeChatUserId(plain);
    if (chatUserId != null &&
        isValidChatUserId(plain) &&
        !isBlockedUserId(chatUserId)) {
      return WithdrawTransferTarget.friend(chatUserId);
    }
    return null;
  }
}
