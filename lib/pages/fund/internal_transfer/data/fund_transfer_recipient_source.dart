import 'package:openim_common/openim_common.dart';

import '../../../../services/fund_api.dart';
import '../../../contacts/search/contact_search_source.dart';
import 'fund_transfer_recipient_policy.dart';

enum FundTransferAccountType { uid, email, phone, account }

typedef FundRecipientResolver = Future<UserFullInfo?> Function({
  required String recipientType,
  required String recipient,
  String? areaCode,
});

class FundTransferRecipient {
  const FundTransferRecipient({
    required this.userID,
    this.nickname = '',
    this.faceURL = '',
    this.account = '',
    this.recipientType,
    this.recipient,
    this.areaCode,
  });

  final String userID, nickname, faceURL, account;

  /// The exact descriptor confirmed by the fund service. UID lookup has no
  /// descriptor because the fund resolver supports account, phone and email.
  final String? recipientType, recipient, areaCode;
}

/// An exact authenticated profile supplies the IM receiver ID for payment.
/// UID lookup uses the existing profile API; other types use the fund resolver.
class FundTransferRecipientSource {
  FundTransferRecipientSource({
    FundApi? api,
    FundRecipientResolver? resolver,
    // Explicit legacy injection keeps existing exact-search fixtures usable.
    // Production never creates a ContactSearchSource for fund resolution.
    ContactSearchSource? source,
    Future<List<UserFullInfo>?> Function(String userID)? uidLoader,
    String Function()? owner,
    String? Function()? tokenProvider,
    String Function()? serverProvider,
  })  : _api = api,
        _resolver = resolver,
        _source = source,
        _uidLoader = uidLoader ?? _loadUID,
        _owner = owner ?? (() => DataSp.userID ?? ''),
        _tokenProvider = tokenProvider ?? (() => DataSp.chatToken),
        _serverProvider = serverProvider ?? (() => Config.appAuthUrl) {
    _scope = _session;
  }

  final FundApi? _api;
  final FundRecipientResolver? _resolver;
  final ContactSearchSource? _source;
  final Future<List<UserFullInfo>?> Function(String userID) _uidLoader;
  final String Function() _owner;
  final String? Function() _tokenProvider;
  final String Function() _serverProvider;
  late final (String, String?, String) _scope;
  int _generation = 0;
  bool _closed = false;
  bool _invalidated = false;

  (String, String?, String) get _session =>
      (_owner(), _tokenProvider(), _serverProvider());

  bool get isCurrentSession {
    if (_closed || _invalidated) return false;
    if (_scope.$1.trim().isEmpty ||
        _scope.$2?.isNotEmpty != true ||
        _scope != _session) {
      _invalidated = true;
      ++_generation;
      return false;
    }
    return true;
  }

  void _requireCurrent(int generation) {
    if (!isCurrentSession || generation != _generation) {
      throw StateError('收款人查询已失效，请重新查询');
    }
  }

  Future<FundTransferRecipient> resolve(
    FundTransferAccountType type,
    String input, {
    String? areaCode,
  }) async {
    final generation = ++_generation;
    _requireCurrent(generation);
    final area =
        type == FundTransferAccountType.phone ? _area(areaCode ?? '+86') : null;
    final value = type == FundTransferAccountType.phone
        ? _nationalPhone(input, area)
        : _normalize(type, input);
    if (value == null) {
      throw FormatException(switch (type) {
        FundTransferAccountType.uid => '请填写有效的收款人UID',
        FundTransferAccountType.email => '请填写有效的收款人邮箱',
        FundTransferAccountType.phone => '请填写有效的收款人手机号',
        FundTransferAccountType.account => '请填写有效的99Chat账号',
      });
    }
    final keyword = type == FundTransferAccountType.account ? '@$value' : value;
    UserFullInfo? user;
    try {
      if (type == FundTransferAccountType.uid || _source != null) {
        final users = type == FundTransferAccountType.uid
            ? await _uidLoader(value)
            : await _source!.users(keyword, 1,
                way: switch (type) {
                  FundTransferAccountType.email => 3,
                  FundTransferAccountType.phone => 2,
                  _ => null,
                });
        _requireCurrent(generation);
        user = _exactProfile(type, value, users, area: area);
      } else {
        // The resolver intentionally returns only public profile fields; an
        // omitted phone/email is not a failed match after server confirmation.
        user = _resolver != null
            ? await _resolver(
                recipientType: type.name, recipient: keyword, areaCode: area)
            : await _resolveProfile(type.name, keyword, area);
      }
    } catch (_) {
      _requireCurrent(generation);
      rethrow;
    }
    _requireCurrent(generation);
    final userID = user?.userID?.trim() ?? '';
    if (user == null || userID.isEmpty) {
      throw const FormatException('未找到该账号对应的收款人');
    }
    if (userID == _scope.$1.trim()) {
      throw const FormatException('不能向自己转账');
    }
    if (!FundTransferRecipientPolicy.allowsUser(userID: userID, ex: user.ex)) {
      throw const FormatException('官方账号不能作为收款人，请选择其他用户');
    }
    return FundTransferRecipient(
      userID: userID,
      nickname: user.nickname?.trim() ?? '',
      faceURL: user.faceURL?.trim() ?? '',
      account: user.account?.trim() ?? '',
      recipientType: type == FundTransferAccountType.uid ? null : type.name,
      recipient: type == FundTransferAccountType.uid ? null : keyword,
      areaCode: area,
    );
  }

  Future<UserFullInfo?> _resolveProfile(
      String type, String recipient, String? area) async {
    final api =
        _api ?? FundApi(baseUrl: _scope.$3, tokenProvider: () => _scope.$2);
    final data = await api.requestData('/chat/fund/recipients/resolve', data: {
      'recipientType': type,
      'recipient': recipient,
      if (area != null) 'areaCode': area,
    });
    final profile = data['user'];
    if (profile is! Map || profile['userID'] is! String) {
      throw const FormatException('收款人信息不完整，请重新确认');
    }
    try {
      return UserFullInfo.fromJson(Map<String, dynamic>.from(profile));
    } catch (_) {
      throw const FormatException('收款人信息不完整，请重新确认');
    }
  }

  static UserFullInfo _exactProfile(
      FundTransferAccountType type, String value, List<UserFullInfo>? users,
      {String? area}) {
    final matches = <String, UserFullInfo>{};
    for (final user in users ?? <UserFullInfo>[]) {
      final id = user.userID?.trim() ?? '';
      if (id.isNotEmpty && _matches(type, value, user, area: area)) {
        matches[id] = user;
      }
    }
    if (matches.isEmpty) throw const FormatException('未找到该账号对应的收款人');
    if (matches.length != 1) {
      throw const FormatException('收款人信息不唯一，请确认账号后重试');
    }
    return matches.values.single;
  }

  static String? _normalize(FundTransferAccountType type, String input) =>
      switch (type) {
        FundTransferAccountType.uid => _uid(input),
        FundTransferAccountType.email => _email(input),
        FundTransferAccountType.phone => _phone(input),
        FundTransferAccountType.account => normalizePublicAccountSearch(input),
      };

  static Future<List<UserFullInfo>?> _loadUID(String userID) =>
      Apis.getUserFullInfo(userIDList: [userID], showErrorToast: false);

  static String? _uid(String input) {
    final value = input.trim();
    return value.isNotEmpty && !RegExp(r'\s').hasMatch(value) ? value : null;
  }

  static String? _email(String input) {
    final value = input.trim();
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value) ? value : null;
  }

  static String? _phone(String input) {
    final value = input.trim().replaceAll(RegExp(r'[\s()\-]'), '');
    return RegExp(r'^\+?\d{5,15}$').hasMatch(value) ? value : null;
  }

  static String? _area(String input) {
    final value = input.trim();
    if (!RegExp(r'^\+?\d{1,4}$').hasMatch(value)) return null;
    return value.startsWith('+') ? value : '+$value';
  }

  static String? _nationalPhone(String input, String? area) {
    if (area == null) return null;
    final number = _phone(input);
    if (number == null) return null;
    final national = number.startsWith('+')
        ? number.startsWith(area)
            ? number.substring(area.length)
            : ''
        : number;
    if (_phone(national) == null || national.startsWith('+')) return null;
    return _phone('$area$national') != null ? national : null;
  }

  static String? _userArea(UserFullInfo user) {
    final area = user.areaCode?.trim() ?? '';
    return _area(area.isEmpty ? user.mobileAreaCode ?? '' : area);
  }

  static bool _matches(
    FundTransferAccountType type,
    String value,
    UserFullInfo user, {
    String? area,
  }) {
    switch (type) {
      case FundTransferAccountType.uid:
        return user.userID?.trim() == value;
      case FundTransferAccountType.email:
        return _email(user.email ?? '') == value;
      case FundTransferAccountType.account:
        return normalizePublicAccountSearch(user.account ?? '') == value;
      case FundTransferAccountType.phone:
        final number = _phone(user.phoneNumber ?? '');
        if (number == null) return false;
        if (area != null) {
          final storedArea = _userArea(user);
          if (number.startsWith('+')) {
            return (storedArea == null || storedArea == area) &&
                number == '$area$value';
          }
          return storedArea == area && number == value;
        }
        if (number == value) return true;
        // International input can match a separately stored area code. Never
        // infer a country from an unqualified local phone number.
        if (!value.startsWith('+') || number.startsWith('+')) return false;
        final prefix = _userArea(user);
        if (prefix == null) return false;
        return _phone('$prefix$number') == value;
    }
  }

  /// Cancels a superseded lookup while allowing a new lookup in this session.
  void cancel() => ++_generation;

  void close() {
    _closed = true;
    cancel();
  }
}
