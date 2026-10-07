import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import 'host/wallet_i18n.dart';
import 'host/wallet_navigation.dart';
import 'host/wallet_qr_scanner.dart';
import 'operations/wallet_friend_transfer_navigation.dart';
import 'wallet_repository.dart';
import 'wallet_repository_provider.dart';
import 'widgets/wallet_page_colors.dart';
import 'widgets/wallet_tip.dart';
import 'withdraw_transfer_target_validator.dart';
import 'withdrawal/form/wallet_chain_withdrawal_screen.dart';

enum _WithdrawTargetTab { wallet, friends }

class WithdrawAddressScreen extends StatefulWidget {
  final CoinDto coin;
  final WalletPayMethodDto payMethod;
  final WithdrawTransferTargetKind initialTargetKind;

  const WithdrawAddressScreen({
    super.key,
    required this.coin,
    required this.payMethod,
    this.initialTargetKind = WithdrawTransferTargetKind.friend,
  });

  @override
  State<WithdrawAddressScreen> createState() => _WithdrawAddressScreenState();
}

class _WithdrawAddressScreenState extends State<WithdrawAddressScreen> {
  final TextEditingController _addrCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _addrFocus = FocusNode();

  List<ISUserInfo> _friends = const [];
  bool _friendsLoading = true;
  late _WithdrawTargetTab _activeTab;
  String _walletAddress = '';
  bool _walletLoading = true;
  ISUserInfo? _selectedFriend;

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTargetKind == WithdrawTransferTargetKind.chain
        ? _WithdrawTargetTab.wallet
        : _WithdrawTargetTab.friends;
    if (widget.initialTargetKind == WithdrawTransferTargetKind.chain) return;
    _loadFriends();
    _loadWalletAddress();
  }

  @override
  void dispose() {
    _addrCtrl.dispose();
    _searchCtrl.dispose();
    _addrFocus.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    try {
      final list = <FriendInfo>[];
      var count = 10000;
      for (;;) {
        final page = await OpenIM.iMManager.friendshipManager.getFriendListPage(
          offset: list.length,
          count: count,
          filterBlack: true,
        );
        list.addAll(page);
        if (page.length < count) break;
        count = 1000;
      }
      final users = list
          .map((item) => ISUserInfo.fromJson(item.toJson()))
          .where((item) => (item.userID ?? '').trim().isNotEmpty)
          .toList(growable: false)
        ..sort((a, b) => a.showName.compareTo(b.showName));
      if (!mounted) return;
      setState(() {
        _friends = users;
        _friendsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _friends = const [];
        _friendsLoading = false;
      });
    }
  }

  Future<void> _loadWalletAddress() async {
    try {
      final wallet = await createWalletRepository().getWallet();
      if (!mounted) return;
      setState(() {
        _walletAddress = wallet.trxAddr.trim();
        _walletLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _walletAddress = '';
        _walletLoading = false;
      });
    }
  }

  String _displayName(ISUserInfo item) {
    final name = item.showName.trim();
    return name.isEmpty ? (item.userID ?? '') : name;
  }

  bool _matchesFriend(ISUserInfo item, String keyword) {
    if (keyword.isEmpty) return true;
    final k = keyword.toLowerCase();
    return _displayName(item).toLowerCase().contains(k) ||
        (item.userID ?? '').toLowerCase().contains(k);
  }

  ISUserInfo? _findFriendByTarget(String value) {
    final normalized =
        WithdrawTransferTargetValidator.normalizePlainText(value);
    if (normalized.isEmpty) return null;
    final id = WithdrawTransferTargetValidator.normalizeChatUserId(normalized);
    if (id != null) {
      for (final item in _friends) {
        if ((item.userID ?? '').trim() == id) return item;
      }
    }
    final lower = normalized.toLowerCase();
    ISUserInfo? match;
    for (final item in _friends) {
      if (_displayName(item).toLowerCase() == lower) {
        if (match != null) return null;
        match = item;
      }
    }
    return match;
  }

  String? _resolveFriendUserId(String value) =>
      _findFriendByTarget(value)?.userID?.trim();

  WithdrawTransferTarget? get _resolvedTransferTarget =>
      WithdrawTransferTargetValidator.resolve(
        raw: _addrCtrl.text,
        isBlockedUserId: (_) => false,
        resolveFriendUserId: _resolveFriendUserId,
      );

  String? get _addressError {
    final raw =
        WithdrawTransferTargetValidator.normalizePlainText(_addrCtrl.text);
    if (raw.isEmpty) return null;
    final target = _resolvedTransferTarget;
    if (target == null) {
      return AppI18n.current.t(
        zhHans: '请输入有效的 TRON 地址或 99Chat 号/昵称',
        zhHant: '請輸入有效的 TRON 地址或 99Chat 號/暱稱',
        en: 'Enter a valid TRON address or 99Chat ID/nickname.',
        ja: '有効な TRON アドレスまたは 99Chat ID/ニックネームを入力してください。',
        ko: '유효한 TRON 주소 또는 99Chat ID/닉네임을 입력하세요.',
      );
    }
    if (target.isChain &&
        _walletAddress.isNotEmpty &&
        target.value ==
            WithdrawTransferTargetValidator.normalizePlainText(
                _walletAddress)) {
      return AppI18n.current.t(
        zhHans: '提现地址不能和转出地址相同',
        zhHant: '提現地址不能和轉出地址相同',
        en: 'The withdrawal address cannot be the same as the sending address.',
        ja: '出金先アドレスは送金元アドレスと同じにできません。',
        ko: '출금 주소는 보내는 주소와 같을 수 없습니다.',
      );
    }
    return null;
  }

  bool get _canNext =>
      _addrCtrl.text.trim().isNotEmpty && _addressError == null;

  void _handleAddressChanged(String value) {
    setState(() {
      _selectedFriend = _findFriendByTarget(value);
    });
  }

  void _fillAddress(String value, {ISUserInfo? friend}) {
    final text = WithdrawTransferTargetValidator.normalizedTargetValue(value);
    if (text.isEmpty) return;
    _addrCtrl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() {
      _selectedFriend = friend ?? _findFriendByTarget(text);
    });
  }

  Future<void> _openScanner() async {
    final scanned = await openWalletPage<String>(
      context,
      const WalletQrScannerPage(),
    );
    if (!mounted || scanned == null || scanned.trim().isEmpty) return;
    _fillAddress(scanned);
    FocusScope.of(context).requestFocus(_addrFocus);
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text ?? '';
    if (text.trim().isNotEmpty) _fillAddress(text);
  }

  Future<void> _openNext() async {
    final target = _resolvedTransferTarget;
    if (target == null || _addressError != null) return;
    final friend = _selectedFriend ?? _findFriendByTarget(_addrCtrl.text);
    if (target.isFriend) {
      // A display account/short number is not a transfer receiver user ID.
      if (friend == null || (friend.userID ?? '').trim() != target.value) {
        WalletTip.show(context, '请从联系人中选择收款人');
        return;
      }
      await openWalletFriendTransfer(context,
          userID: target.value,
          coinCode: widget.payMethod.coin,
          name: _displayName(friend),
          faceURL: friend.faceURL?.trim());
      return;
    }
    await openWalletPage<void>(
      context,
      WalletChainWithdrawalScreen(
        coin: widget.coin,
        payMethod: widget.payMethod,
        initialAddress: target.value,
      ),
      activityPage: 'wallet_withdraw',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.initialTargetKind == WithdrawTransferTargetKind.chain) {
      return WalletChainWithdrawalScreen(
          coin: widget.coin, payMethod: widget.payMethod);
    }
    final i18n = AppI18n.of(context);
    final cs = WalletPageColors.of(context);
    final appBar = WalletAppBarColors.of(context);
    return wrapWalletPage(
      context,
      Scaffold(
        backgroundColor: cs.dark ? cs.bg : Colors.white,
        appBar: AppBar(
          leading: const AppBackButton(),
          centerTitle: true,
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          backgroundColor: appBar.background,
          foregroundColor: appBar.title,
          systemOverlayStyle: walletPageOverlayStyle(context),
          title: Text(
            i18n.t(
              zhHans: '收款地址',
              zhHant: '收款地址',
              en: 'Receiving Address',
              ja: '受取アドレス',
              ko: '수령 주소',
            ),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: appBar.title,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusScope.of(context).unfocus(),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        decoration: BoxDecoration(
                          color: cs.inputFill,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cs.line),
                        ),
                        child: SizedBox(
                          height: 56,
                          child: TextField(
                            controller: _addrCtrl,
                            focusNode: _addrFocus,
                            maxLines: 1,
                            keyboardType: TextInputType.text,
                            textInputAction: TextInputAction.done,
                            enableSuggestions: false,
                            autocorrect: false,
                            smartDashesType: SmartDashesType.disabled,
                            smartQuotesType: SmartQuotesType.disabled,
                            inputFormatters: [
                              FilteringTextInputFormatter.deny(
                                RegExp(r'[\r\n]'),
                              ),
                            ],
                            cursorColor: cs.inputCursor,
                            onChanged: _handleAddressChanged,
                            style: TextStyle(
                              fontSize: 16,
                              color: cs.text,
                              fontWeight: FontWeight.w500,
                              height: 1.4,
                            ),
                            decoration: InputDecoration(
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              isCollapsed: true,
                              contentPadding: EdgeInsets.zero,
                              hintText: i18n.t(
                                zhHans: '请输入接收转账钱包地址/99Chat号',
                                zhHant: '請輸入接收轉帳錢包地址/99Chat號',
                                en: 'Enter wallet address or 99Chat ID',
                                ja: '受取ウォレットアドレス/99Chat IDを入力',
                                ko: '수령 지갑 주소/99Chat ID 입력',
                              ),
                              hintStyle: TextStyle(
                                fontSize: 16,
                                color: cs.inputHint,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_addressError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _addressError!,
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.red,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          if (!kIsWeb) ...[
                            Expanded(
                              child: _AddressAction(
                                icon: Icon(
                                  Icons.qr_code_scanner_rounded,
                                  size: 17,
                                  color: cs.text,
                                ),
                                label: i18n.t(
                                  zhHans: '扫一扫',
                                  zhHant: '掃一掃',
                                  en: 'Scan',
                                  ja: 'スキャン',
                                  ko: '스캔',
                                ),
                                onTap: _openScanner,
                              ),
                            ),
                            const SizedBox(width: 14),
                          ],
                          Expanded(
                            child: _AddressAction(
                              icon: Icon(
                                Icons.content_copy_rounded,
                                size: 16,
                                color: cs.text,
                              ),
                              label: i18n.t(
                                zhHans: '粘贴',
                                zhHant: '貼上',
                                en: 'Paste',
                                ja: '貼り付け',
                                ko: '붙여넣기',
                              ),
                              onTap: _paste,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),
                      _AddressTabs(
                        activeTab: _activeTab,
                        onSelectWallet: () => setState(
                            () => _activeTab = _WithdrawTargetTab.wallet),
                        onSelectFriends: () => setState(
                          () => _activeTab = _WithdrawTargetTab.friends,
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (_activeTab == _WithdrawTargetTab.friends) ...[
                        _AddressSearchField(
                          controller: _searchCtrl,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                        Divider(height: 1, color: cs.line),
                        const SizedBox(height: 8),
                        ..._buildFriendItems(cs, i18n),
                      ] else ...[
                        Divider(height: 1, color: cs.line),
                        const SizedBox(height: 8),
                        ..._buildWalletItems(cs, i18n),
                      ],
                    ],
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: cs.dark ? cs.bg : Colors.white,
                    border: cs.dark
                        ? null
                        : Border(top: BorderSide(color: cs.line)),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _canNext ? _openNext : null,
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: cs.blue,
                        disabledBackgroundColor: cs.dark
                            ? cs.disabledButton
                            : cs.blue.withValues(alpha: 0.32),
                        foregroundColor: Colors.white,
                        disabledForegroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        i18n.t(
                          zhHans: '下一步',
                          zhHant: '下一步',
                          en: 'Next',
                          ja: '次へ',
                          ko: '다음',
                        ),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildFriendItems(WalletPageColors cs, AppI18n i18n) {
    if (_friendsLoading) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ];
    }
    final keyword = _searchCtrl.text.trim();
    final list = _friends
        .where((item) => _matchesFriend(item, keyword))
        .toList(growable: false);
    if (list.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text(
              keyword.isEmpty
                  ? i18n.t(
                      zhHans: '暂无好友',
                      zhHant: '暫無好友',
                      en: 'No friends yet',
                      ja: '友達がいません',
                      ko: '친구가 없습니다',
                    )
                  : i18n.t(
                      zhHans: '未找到相关联系人',
                      zhHant: '未找到相關聯絡人',
                      en: 'No matching contacts',
                      ja: '該当する連絡先が見つかりません',
                      ko: '관련 연락처를 찾을 수 없습니다',
                    ),
              style: TextStyle(
                fontSize: 14,
                color: cs.subText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ];
    }
    return list.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;
      final id = (item.userID ?? '').trim();
      final name = _displayName(item);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (index > 0) Divider(height: 1, indent: 52, color: cs.line),
          InkWell(
            onTap: () => _fillAddress(id, friend: item),
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 60,
              child: Row(
                children: [
                  AvatarView(
                    width: 42,
                    height: 42,
                    url: item.faceURL,
                    text: name,
                    isCircle: true,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            color: cs.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          id,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.subText,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }).toList(growable: false);
  }

  List<Widget> _buildWalletItems(WalletPageColors cs, AppI18n i18n) {
    if (_walletLoading) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ];
    }
    if (_walletAddress.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text(
              i18n.t(
                zhHans: '暂无钱包地址',
                zhHant: '暫無錢包地址',
                en: 'No wallet address yet',
                ja: 'ウォレットアドレスがありません',
                ko: '지갑 주소가 없습니다',
              ),
              style: TextStyle(
                fontSize: 14,
                color: cs.subText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ];
    }
    return [
      InkWell(
        onTap: () => _fillAddress(_walletAddress),
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: cs.blue.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.account_balance_wallet_rounded,
                  color: cs.blue,
                  size: 23,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      i18n.t(
                        zhHans: '我的钱包',
                        zhHant: '我的錢包',
                        en: 'My Wallet',
                        ja: 'マイウォレット',
                        ko: '내 지갑',
                      ),
                      style: TextStyle(
                        fontSize: 15,
                        color: cs.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _walletAddress,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.subText,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }
}

class _AddressAction extends StatelessWidget {
  const _AddressAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Widget icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    final borderColor = cs.dark ? cs.line : const Color(0xFFDDE1E6);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: cs.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
          boxShadow: cs.dark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: cs.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddressSearchField extends StatelessWidget {
  const _AddressSearchField(
      {required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final cs = WalletPageColors.of(context);
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: cs.inputFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.line),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: cs.inputHint, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              cursorColor: cs.inputCursor,
              textInputAction: TextInputAction.search,
              onChanged: onChanged,
              decoration: InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isCollapsed: true,
                hintText: i18n.t(
                  zhHans: '搜索联系人',
                  zhHant: '搜尋聯絡人',
                  en: 'Search contacts',
                  ja: '連絡先を検索',
                  ko: '연락처 검색',
                ),
                hintStyle: TextStyle(color: cs.inputHint, fontSize: 15),
              ),
              style: TextStyle(color: cs.text, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressTabs extends StatelessWidget {
  const _AddressTabs({
    required this.activeTab,
    required this.onSelectWallet,
    required this.onSelectFriends,
  });

  final _WithdrawTargetTab activeTab;
  final VoidCallback onSelectWallet;
  final VoidCallback onSelectFriends;

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    return Row(
      children: [
        _AddressTabItem(
          label: i18n.t(
            zhHans: '我的钱包',
            zhHant: '我的錢包',
            en: 'My Wallet',
            ja: 'マイウォレット',
            ko: '내 지갑',
          ),
          selected: activeTab == _WithdrawTargetTab.wallet,
          onTap: onSelectWallet,
        ),
        const SizedBox(width: 28),
        _AddressTabItem(
          label: i18n.t(
            zhHans: '我的好友',
            zhHant: '我的好友',
            en: 'My Friends',
            ja: 'マイ友達',
            ko: '내 친구',
          ),
          selected: activeTab == _WithdrawTargetTab.friends,
          onTap: onSelectFriends,
        ),
      ],
    );
  }
}

class _AddressTabItem extends StatelessWidget {
  const _AddressTabItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    final selectedColor = cs.dark ? cs.filterActiveText : cs.blue;
    final inactiveColor =
        cs.dark ? const Color(0xFFADB0B8) : const Color(0xFF8E9399);
    final indicatorColor = cs.dark ? cs.inputCursor : cs.blue;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              color: selected ? selectedColor : inactiveColor,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 3,
            width: selected ? 28 : 0,
            decoration: BoxDecoration(
              color: indicatorColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}
