import '../../apis.dart';
import '../../models/user_full_info.dart';
import '../../utils/data_sp.dart';

/// Resolves a card's public account using the same profile source as user detail.
class ContactCardProfileResolver {
  ContactCardProfileResolver({
    Future<List<UserFullInfo>?> Function(String userID)? fetchProfile,
    String? Function()? currentUserID,
    String? Function()? currentToken,
  })  : _fetchProfile = fetchProfile ??
            ((userID) => Apis.getUserFullInfo(
                userIDList: [userID], showErrorToast: false)),
        _currentUserID = currentUserID ?? (() => DataSp.userID),
        _currentToken = currentToken ?? (() => DataSp.chatToken);

  static final shared = ContactCardProfileResolver();
  static const _maximumCachedProfiles = 256;

  final Future<List<UserFullInfo>?> Function(String userID) _fetchProfile;
  final String? Function() _currentUserID;
  final String? Function() _currentToken;
  final _cache = <String, String?>{};
  final _pending = <String, Future<String?>>{};
  String? _sessionUserID;
  String? _sessionToken;
  int _generation = 0;
  bool _sessionInitialized = false;

  void _syncSession() {
    final userID = _currentUserID();
    final token = _currentToken();
    if (_sessionInitialized &&
        userID == _sessionUserID &&
        token == _sessionToken) {
      return;
    }
    _sessionInitialized = true;
    _sessionUserID = userID;
    _sessionToken = token;
    ++_generation;
    _cache.clear();
    _pending.clear();
  }

  bool get _authenticated =>
      _sessionUserID?.trim().isNotEmpty == true &&
      _sessionToken?.isNotEmpty == true;

  String? _readCache(String userID) {
    if (!_cache.containsKey(userID)) return null;
    final account = _cache.remove(userID);
    _cache[userID] = account;
    return account;
  }

  String? peek(String userID) {
    _syncSession();
    if (!_authenticated || userID.trim().isEmpty) return null;
    return _readCache(userID);
  }

  Future<String?> resolve(String userID) {
    _syncSession();
    if (!_authenticated || userID.trim().isEmpty) return Future.value();
    if (_cache.containsKey(userID)) return Future.value(_readCache(userID));
    final pending = _pending[userID];
    if (pending != null) return pending;
    final generation = _generation;
    late final Future<String?> request;
    request = _fetchAccount(userID, generation).whenComplete(() {
      if (identical(_pending[userID], request)) _pending.remove(userID);
    });
    _pending[userID] = request;
    return request;
  }

  Future<String?> _fetchAccount(String userID, int generation) async {
    final List<UserFullInfo>? profiles;
    try {
      profiles = await _fetchProfile(userID);
    } catch (_) {
      // Keep rendering usable; another mounted card can retry a failed lookup.
      return null;
    }
    _syncSession();
    if (generation != _generation || !_authenticated) return null;
    if (profiles == null) return null;
    String? account;
    for (final profile in profiles) {
      if (profile.userID != userID) continue;
      final publicAccount = profile.account?.trim() ?? '';
      if (publicAccount.isNotEmpty) account = publicAccount;
      break;
    }
    _cache[userID] = account;
    while (_cache.length > _maximumCachedProfiles) {
      _cache.remove(_cache.keys.first);
    }
    return account;
  }
}
