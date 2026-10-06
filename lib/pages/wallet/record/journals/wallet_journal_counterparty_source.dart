import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../../data/wallet_session_source.dart';
import '../../order/wallet_order_events.dart';

abstract interface class WalletJournalCounterpartySource {
  Future<Map<String, String>> getNicknames(Set<String> userIDs);
}

/// Optional richer capability, resolved in the same batch as the nickname.
abstract interface class WalletJournalCounterpartyProfileSource {
  Future<Map<String, WalletJournalCounterpartyProfile>> getProfiles(
      Set<String> userIDs);
}

class WalletJournalCounterpartyProfile {
  const WalletJournalCounterpartyProfile(
      {this.nickname = '', this.faceURL = ''});
  final String nickname;
  final String faceURL;
}

typedef WalletJournalProfileLoader = Future<List<PublicUserInfo>> Function(
    List<String> userIDs);

/// Resolves current public nicknames through the existing batched SDK method.
/// No account, friend remark, UID fallback or cross-session cache is retained.
class OpenIMWalletJournalCounterpartySource
    implements
        WalletJournalCounterpartySource,
        WalletJournalCounterpartyProfileSource {
  OpenIMWalletJournalCounterpartySource({
    WalletJournalProfileLoader? loadProfiles,
    String Function()? accountProvider,
    String? Function()? tokenProvider,
    this.lookupTimeout = const Duration(seconds: 2),
  })  : _loadProfiles = loadProfiles ?? _sdkProfiles,
        _accountProvider =
            accountProvider ?? (() => WalletOrderEvents.currentAccountKey),
        _tokenProvider = tokenProvider ?? (() => DataSp.imToken) {
    ownerAccountKey = _accountProvider();
    _ownerToken = _tokenProvider();
  }

  final WalletJournalProfileLoader _loadProfiles;
  final String Function() _accountProvider;
  final String? Function() _tokenProvider;
  final Duration lookupTimeout;
  late final String ownerAccountKey;
  late final String? _ownerToken;

  bool get isCurrentAccount =>
      ownerAccountKey.isNotEmpty &&
      !ownerAccountKey.endsWith(':') &&
      _ownerToken?.isNotEmpty == true &&
      _accountProvider() == ownerAccountKey &&
      _tokenProvider() == _ownerToken;

  void _requireCurrentAccount() {
    if (!isCurrentAccount) throw const WalletAccountChangedException();
  }

  static Future<List<PublicUserInfo>> _sdkProfiles(List<String> userIDs) =>
      OpenIM.iMManager.userManager.getUsersInfo(userIDList: userIDs);

  @override
  Future<Map<String, String>> getNicknames(Set<String> userIDs) async {
    final profiles = await getProfiles(userIDs);
    return Map.unmodifiable({
      for (final entry in profiles.entries)
        if (entry.value.nickname.isNotEmpty) entry.key: entry.value.nickname,
    });
  }

  @override
  Future<Map<String, WalletJournalCounterpartyProfile>> getProfiles(
      Set<String> userIDs) async {
    _requireCurrentAccount();
    final requested =
        userIDs.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet();
    if (requested.isEmpty) return const {};
    final profiles = await Future.sync(
            () => _loadProfiles(requested.toList(growable: false)))
        .timeout(lookupTimeout);
    _requireCurrentAccount();
    return Map.unmodifiable({
      for (final profile in profiles)
        if (requested.contains(profile.userID))
          profile.userID!: WalletJournalCounterpartyProfile(
            nickname: profile.nickname?.trim() ?? '',
            faceURL: profile.faceURL?.trim() ?? '',
          ),
    });
  }
}
