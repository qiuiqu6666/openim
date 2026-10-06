// Adapted from qiuiqu6666/99chat, revision d7c3c65 (Apache-2.0).
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../core/controller/im_controller.dart';
import '../../services/fund_api.dart';
import '../../services/fund_pending_store.dart';
import '../../widgets/payment/password_payment_sheet.dart';
import '../mine/settings/openim_profile_service.dart';
import '../mine/settings/pages/trade_password_page.dart';
import '../mine/settings/settings_service.dart';
import '../mine/settings/widgets/settings_widgets.dart';
import 'fund_recipient_picker.dart';
import 'internal_transfer/internal_transfer.dart';
import 'payment/fund_payment_draft.dart';
import 'payment/fund_payment_preferences.dart';
import 'payment/fund_transfer_authorization.dart';
import 'withdrawal_security/withdrawal_security.dart';
import 'widgets/fund_page_colors.dart';
import 'widgets/fund_send_form.dart';
import 'widgets/fund_pay_sheet.dart';
import 'widgets/fund_pay_method_sheet.dart';

class FundSendPage extends StatefulWidget {
  const FundSendPage({
    super.key,
    required this.isRedPacket,
    this.userID,
    this.groupID,
    this.recipientName,
    this.recipientFaceURL,
    this.initialPacketBiz,
    this.api,
    this.settingsService,
    this.pendingStore,
    this.paymentPreferences,
    this.currentUserID,
    this.internalWithdrawal = false,
    this.initialCurrency,
    this.transferRecipientSource,
    this.transferFriendPicker,
    this.transferAreaCodePicker,
  }) : assert(!internalWithdrawal || (!isRedPacket && groupID == null));

  final bool isRedPacket;
  final String? userID, groupID, recipientName, currentUserID;
  final String? recipientFaceURL;

  /// Wallet internal withdrawals reuse the same durable transfer/payment owner.
  final bool internalWithdrawal;
  final FundCurrency? initialCurrency;
  final FundTransferRecipientSource? transferRecipientSource;
  final Future<FundTransferRecipient?> Function(BuildContext)?
      transferFriendPicker;
  final Future<String?> Function(BuildContext, String)? transferAreaCodePicker;

  /// Group entry can preselect the existing exclusive packet form and use
  /// userID/recipientName/recipientFaceURL as its initial recipient.
  final FundPacketBiz? initialPacketBiz;
  final FundApi? api;
  final SettingsService? settingsService;
  final FundPendingStore? pendingStore;
  final FundPaymentPreferences? paymentPreferences;

  @override
  State<FundSendPage> createState() => _FundSendPageState();
}

class _FundSendPageState extends State<FundSendPage>
    with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _amountFocus = FocusNode();
  final _count = TextEditingController(text: '1');
  final _remark = TextEditingController();
  final _recipientInput = TextEditingController();
  late final FundTransferRecipientSource _transferRecipients;
  FundTransferAccountType _accountType = FundTransferAccountType.account;
  String _phoneAreaCode = '+86';
  bool _resolvingRecipient = false;
  bool _choosingTransferAccount = false;
  late final FundApi _api;
  late final FundTransferAuthorization _transferAuthorization;
  late final SettingsService _settings;
  late final FundPendingStore _store;
  late final FundPaymentPreferences _paymentPreferences;
  late final String _accountID;
  late final String _serverURL;
  String? _sessionToken;
  FundCurrency _currency = FundCurrency.usdt;
  FundPacketBiz _biz = FundPacketBiz.normal;
  List<FundBalance> _balances = [];
  Map<String, dynamic>? _pending;
  String? _recvID, _recvName, _error;
  String? _recvFaceURL;
  String? _recipientType, _recipientAccount, _recipientAreaCode;
  bool _loading = true, _submitting = false, _passwordSet = false;
  bool _sheetOpen = false;
  bool _currencyInitialized = false, _choosingCurrency = false;
  bool _pendingEntryConflict = false;
  Future<FundOrder>? _paymentAttempt;
  FundOrder? _completedOrder;

  bool get _group => (widget.groupID ?? '').isNotEmpty;
  bool get _multiple =>
      widget.isRedPacket && _group && _biz != FundPacketBiz.exclusive;
  bool get _needsRecipient => !_multiple;
  bool get _locked =>
      _submitting ||
      _resolvingRecipient ||
      _choosingTransferAccount ||
      _sheetOpen ||
      _choosingCurrency ||
      _pendingEntryConflict ||
      _pending != null ||
      _completedOrder != null;
  bool get _canChangeCurrency =>
      mounted &&
      _sameAccount &&
      !_loading &&
      !_submitting &&
      !_pendingEntryConflict &&
      _pending == null &&
      _completedOrder == null;
  bool get _canChangePaymentCurrency =>
      !widget.internalWithdrawal && _canChangeCurrency && _sheetOpen;
  String? get _singleRecipient =>
      widget.internalWithdrawal ? _recvID : widget.userID;
  String get _scope =>
      '${widget.isRedPacket ? 'packet' : 'transfer'}:${_group ? 'group:${widget.groupID}' : 'single:$_singleRecipient'}';
  bool get _sameAccount =>
      Config.appAuthUrl == _serverURL &&
      (widget.currentUserID != null || _sessionToken == DataSp.chatToken) &&
      (widget.currentUserID != null || DataSp.userID == _accountID) &&
      (!widget.internalWithdrawal || _transferRecipients.isCurrentSession);
  String _text(String zh, String en) => settingsText(context, zh: zh, en: en);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _api = widget.api ?? FundApi();
    _transferAuthorization = FundTransferAuthorization(_api);
    _sessionToken = DataSp.chatToken;
    _settings = widget.settingsService ??
        OpenIMProfileService(Get.find<IMController>());
    _accountID = widget.currentUserID ?? DataSp.userID ?? '';
    _serverURL = Config.appAuthUrl;
    _transferRecipients =
        widget.transferRecipientSource ?? FundTransferRecipientSource();
    if (widget.initialCurrency != null) {
      _currency = widget.initialCurrency!;
      _currencyInitialized = true;
    }
    _store = widget.pendingStore ??
        FundPendingStore(accountKey: '$_serverURL:$_accountID');
    _paymentPreferences = widget.paymentPreferences ??
        FundPaymentPreferences(accountID: _accountID, serverURL: _serverURL);
    if (widget.isRedPacket && _group) {
      _biz = widget.initialPacketBiz ?? FundPacketBiz.lucky;
    }
    final initialRecipientID = widget.userID?.trim() ?? '';
    final preselectedGroupRecipient = _group &&
        widget.isRedPacket &&
        _biz == FundPacketBiz.exclusive &&
        initialRecipientID.isNotEmpty &&
        initialRecipientID != _accountID;
    final hasInitialRecipient = !_group || preselectedGroupRecipient;
    _recvID = preselectedGroupRecipient
        ? initialRecipientID
        : hasInitialRecipient
            ? widget.userID
            : null;
    _recvName = hasInitialRecipient ? widget.recipientName : null;
    _recvFaceURL = hasInitialRecipient ? widget.recipientFaceURL : null;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _pendingEntryConflict = false;
    });
    try {
      if (_accountID.isEmpty || !_sameAccount) {
        throw StateError('Please sign in again');
      }
      final pending = widget.internalWithdrawal && (_recvID ?? '').isEmpty
          ? null
          : await _store.read(_scope);
      if (!mounted) return;
      if (!_sameAccount) throw StateError('The account changed');
      if (pending != null) {
        _validatePending(pending);
        // A shortcut for one member must never recover a different member's
        // or packet type's unresolved payment under the shared group scope.
        if (_group &&
            widget.isRedPacket &&
            widget.initialPacketBiz == FundPacketBiz.exclusive &&
            (pending['biz'] != FundPacketBiz.exclusive.code ||
                pending['recvID'] != widget.userID?.trim())) {
          _pendingEntryConflict = true;
          throw const FundPendingConflict();
        }
        _pending = pending;
        _currency = FundCurrency.values
            .firstWhere((c) => c.code == pending['currency']);
        if (widget.isRedPacket) {
          _biz =
              FundPacketBiz.values.firstWhere((b) => b.code == pending['biz']);
        }
        _amount.text = (pending['shareAmount'] ?? pending['amount']).toString();
        _count.text = (pending['shareCount'] ?? 1).toString();
        _remark.text = pending['remark'] as String? ?? '';
        _recvID = pending['recvID'] as String?;
        _recvName = pending['recipientName'] as String?;
      }
      FundCurrency? preferredCurrency;
      if (!_currencyInitialized && _pending == null) {
        try {
          preferredCurrency = await _paymentPreferences.read();
        } catch (_) {
          // A preference read failure must not prevent loading real balances.
        }
      }
      if (!mounted) return;
      if (!_sameAccount) throw StateError('The account changed');
      final results = await Future.wait<Object>(
          [_api.fetchBalances(), _settings.hasTradePassword()]);
      if (!mounted) return;
      if (!_sameAccount) throw StateError('The account changed');
      setState(() {
        _balances = results[0] as List<FundBalance>;
        _passwordSet = results[1] as bool;
        if (!_currencyInitialized) {
          if (_pending == null) {
            final available = _balances.map((balance) => balance.currency);
            _currency = available.contains(preferredCurrency)
                ? preferredCurrency!
                : available.contains(FundCurrency.usdt) || _balances.isEmpty
                    ? FundCurrency.usdt
                    : _balances.first.currency;
          }
          _currencyInitialized = true;
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _balances = [];
          _error = error is FundPendingConflict
              ? _text('群内已有其他红包待确认，请返回原红包入口重试',
                  'Another group packet is pending. Return to its original entry to retry.')
              : _sameAccount
                  ? _text('加载失败，请重试', 'Could not load funds. Please retry.')
                  : _text('登录状态已变更，请重新打开页面',
                      'Your account changed. Please reopen this page.');
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _validatePending(Map<String, dynamic> pending) {
    if (pending.containsKey('remark')) {
      final remark = pending['remark'];
      if (remark is! String || FundRemark.normalize(remark) != remark) {
        throw const FormatException('Invalid pending payment remark');
      }
    }
    final expectedScene = _group ? 'group' : 'single';
    if (pending['clientOrderID'] is! String ||
        (pending['clientOrderID'] as String).trim().isEmpty ||
        (pending['scene'] != expectedScene &&
            !(widget.internalWithdrawal && pending['scene'] == 'internal')) ||
        (_group && pending['groupID'] != widget.groupID) ||
        (!_group && pending['recvID'] != _singleRecipient) ||
        pending.containsKey('payPassword') ||
        pending.containsKey('password') ||
        pending.containsKey('verifyCode') ||
        pending.containsKey('verifyChallengeID')) {
      throw const FormatException('Invalid pending payment');
    }
    final currency = FundCurrency.parse(pending['currency'] as String);
    final biz = widget.isRedPacket
        ? FundPacketBiz.values.firstWhere((b) => b.code == pending['biz'])
        : null;
    if (!widget.isRedPacket && pending.containsKey('biz')) {
      throw const FormatException('Invalid pending payment business');
    }
    final multiple = _group && biz != null && biz != FundPacketBiz.exclusive;
    final normal = multiple && biz == FundPacketBiz.normal;
    if ((!_group && biz == FundPacketBiz.lucky) ||
        (normal ? pending['shareAmount'] : pending['amount']) is! String ||
        (normal && pending.containsKey('amount')) ||
        (!normal && pending.containsKey('shareAmount')) ||
        (multiple && pending.containsKey('recvID')) ||
        (!multiple &&
            (pending['recvID'] is! String ||
                (pending['recvID'] as String).isEmpty ||
                pending['recvID'] == _accountID))) {
      throw const FormatException('Invalid pending payment fields');
    }
    final amount = FundAmount.parse(
        (normal ? pending['shareAmount'] : pending['amount']) as String,
        currency);
    final count = pending['shareCount'];
    if ((multiple && (count is! int || count <= 0 || count > 2147483647)) ||
        (!multiple && count != null)) {
      throw const FormatException('Invalid pending packet count');
    }
    final total = normal ? amount.multipliedBy(count as int) : amount;
    if (!amount.isPositive ||
        total.units > BigInt.parse('9223372036854775807') ||
        (biz == FundPacketBiz.lucky &&
            amount.units < BigInt.from(count as int))) {
      throw const FormatException('Invalid pending payment amount');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !_sheetOpen &&
        !_choosingCurrency &&
        !_submitting &&
        !_resolvingRecipient &&
        !_choosingTransferAccount &&
        !_loading &&
        _completedOrder == null) {
      _load();
    }
  }

  FundAmount? get _total {
    try {
      final value = FundAmount.parse(_amount.text.trim(), _currency);
      return _multiple && _biz == FundPacketBiz.normal
          ? value.multipliedBy(int.tryParse(_count.text) ?? 0)
          : value;
    } catch (_) {
      return null;
    }
  }

  String? _validateAmount(String? raw) {
    try {
      final value = FundAmount.parse(raw?.trim() ?? '', _currency);
      if (!value.isPositive) {
        return _text('金额必须大于 0', 'Enter an amount greater than zero');
      }
      if (value.units > BigInt.parse('9223372036854775807') ||
          (_total?.units ?? BigInt.zero) >
              BigInt.parse('9223372036854775807')) {
        return _text('金额超出可处理范围', 'Amount exceeds the supported range');
      }
      if (_multiple &&
          _biz == FundPacketBiz.lucky &&
          value.units < BigInt.from(int.tryParse(_count.text) ?? 1)) {
        return _text(
            '总金额不足以分配这些红包', 'Total amount is too small for this packet count');
      }
      return null;
    } catch (_) {
      return _text('请输入有效金额，最多 ${_currency.decimals} 位小数',
          'Enter a valid amount with up to ${_currency.decimals} decimal places');
    }
  }

  String? _validateRemark(String? raw) {
    try {
      FundRemark.normalize(raw ?? '');
      return null;
    } on FormatException {
      return _text('最多输入12个字符', 'Use at most 12 characters');
    }
  }

  String? _validateInternalAmount(String? raw) {
    final error = _validateAmount(raw);
    if (error != null) return error;
    // An uncertain payment may already have spent this balance. Retry its
    // original ID so the server can resolve it without creating a new order.
    if (_pending != null) return null;
    final value = FundAmount.parse(raw!.trim(), _currency);
    final available = _balance?.available;
    return available == null || value.compareTo(available) > 0
        ? _text('可用余额不足', 'Insufficient available balance')
        : null;
  }

  String? _validateTransferRecipient(String? raw) =>
      (_recvID ?? '').isNotEmpty || (raw ?? '').trim().isNotEmpty
          ? null
          : _text('请填写收款人账号或选择好友', 'Enter an account or select a friend');

  void _recipientEdited() {
    if (_locked || _loading) return;
    _transferRecipients.cancel();
    setState(() {
      _recvID = null;
      _recvName = null;
      _recvFaceURL = null;
      _recipientType = null;
      _recipientAccount = null;
      _recipientAreaCode = null;
      _error = null;
    });
  }

  Future<void> _chooseAccountType() async {
    if (_locked || _loading || !_sameAccount) return;
    FocusManager.instance.primaryFocus?.unfocus();
    FundTransferAccountType? selected;
    setState(() => _choosingTransferAccount = true);
    try {
      selected = await showFundTransferAccountTypes(context, _accountType);
    } finally {
      if (mounted) setState(() => _choosingTransferAccount = false);
    }
    final choice = selected;
    if (!mounted ||
        !_sameAccount ||
        _locked ||
        choice == null ||
        choice == _accountType) {
      return;
    }
    _recipientInput.clear();
    _recipientEdited();
    setState(() => _accountType = choice);
  }

  Future<void> _chooseTransferFriend() async {
    if (_locked || _loading || !_sameAccount) return;
    setState(() => _resolvingRecipient = true);
    try {
      final Future<FundTransferRecipient?> selection;
      if (widget.transferFriendPicker != null) {
        selection = widget.transferFriendPicker!(context);
      } else {
        selection = Navigator.of(context).push<FundTransferRecipient>(
            MaterialPageRoute(
                builder: (_) => const FundTransferFriendPicker()));
      }
      final recipient = await selection;
      if (!mounted ||
          !_sameAccount ||
          recipient == null ||
          recipient.userID.trim().isEmpty ||
          recipient.userID == _accountID) {
        return;
      }
      setState(() {
        _accountType = FundTransferAccountType.account;
        _recipientInput.text = recipient.account;
        _recvID = recipient.userID;
        _recvName = recipient.nickname.isNotEmpty
            ? recipient.nickname
            : _text('收款人', 'Recipient');
        _recvFaceURL = recipient.faceURL;
        _recipientType = null;
        _recipientAccount = null;
        _recipientAreaCode = null;
      });
      await _load();
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            _text('无法加载收款人，请重试', 'Could not load recipient. Please retry.'));
      }
    } finally {
      if (mounted) setState(() => _resolvingRecipient = false);
    }
  }

  Future<void> _chooseTransferAreaCode() async {
    if (_locked || _loading || !_sameAccount) return;
    FocusManager.instance.primaryFocus?.unfocus();
    String? selected;
    setState(() => _choosingTransferAccount = true);
    try {
      selected =
          await (widget.transferAreaCodePicker?.call(context, _phoneAreaCode) ??
              chooseFundTransferAreaCode(context, _phoneAreaCode));
    } finally {
      if (mounted) setState(() => _choosingTransferAccount = false);
    }
    if (!mounted ||
        !_sameAccount ||
        _locked ||
        selected == null ||
        selected == _phoneAreaCode ||
        !RegExp(r'^\+[1-9]\d{0,3}$').hasMatch(selected)) {
      return;
    }
    _recipientEdited();
    setState(() => _phoneAreaCode = selected!);
  }

  Future<void> _submitInternalTransfer() async {
    if (_sheetOpen ||
        _resolvingRecipient ||
        _choosingTransferAccount ||
        _submitting ||
        _loading ||
        _pendingEntryConflict ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    if (!_sameAccount) {
      setState(() => _error = _text(
          '登录状态已变更，请重新打开页面', 'Your account changed. Please reopen this page.'));
      return;
    }
    if (!_form.currentState!.validate()) return;
    setState(() => _error = null);
    if ((_recvID ?? '').isEmpty) {
      if (!await _confirmTransferRecipient()) return;
    }
    if (mounted &&
        _sameAccount &&
        _error == null &&
        ModalRoute.of(context)?.isCurrent == true) {
      await _submit();
    }
  }

  /// Resolving before an amount is entered also recovers an uncertain order
  /// whose confirmed debit may have left the current available balance at zero.
  Future<bool> _confirmTransferRecipient() async {
    if (_locked ||
        _loading ||
        !_sameAccount ||
        (_recvID ?? '').isNotEmpty ||
        _recipientInput.text.trim().isEmpty) {
      return false;
    }
    setState(() {
      _resolvingRecipient = true;
      _error = null;
    });
    try {
      final recipient = await _transferRecipients.resolve(
          _accountType, _recipientInput.text,
          areaCode: _accountType == FundTransferAccountType.phone
              ? _phoneAreaCode
              : null);
      if (!mounted || !_sameAccount) return false;
      setState(() {
        _recvID = recipient.userID;
        _recvName = recipient.nickname.isNotEmpty
            ? recipient.nickname
            : _text('收款人', 'Recipient');
        _recvFaceURL = recipient.faceURL;
        _recipientType = recipient.recipientType;
        _recipientAccount = recipient.recipient;
        _recipientAreaCode = recipient.areaCode;
      });
      await _load();
      if (!mounted || !_sameAccount) return false;
      if (_pending != null) {
        setState(() => _error = _text('已恢复待确认转账，请核对收款人和金额后重试',
            'Pending transfer restored. Review the recipient and amount before retrying.'));
        return false;
      }
      return _error == null;
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is FormatException
            ? error.message
            : _sameAccount
                ? _text(
                    '收款人查询失败，请重试', 'Could not find recipient. Please retry.')
                : _text('登录状态已变更，请重新打开页面',
                    'Your account changed. Please reopen this page.'));
      }
      return false;
    } finally {
      if (mounted) setState(() => _resolvingRecipient = false);
    }
  }

  void _useAll() {
    if (_locked || _loading || !_sameAccount || _balance == null) return;
    setState(() {
      _amount.text =
          _balance!.available.isPositive ? _balance!.available.decimal : '0';
      _error = null;
    });
  }

  Future<void> _transferHelp() => showFundInternalTransferHelp(context);

  Future<void> _transferHistory() async {
    if (_locked || _loading || !_sameAccount) return;
    await openFundInternalTransferHistory(context, _currency);
    if (mounted && _sameAccount) await _load();
  }

  Future<void> _pickRecipient() async {
    final member = await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FundRecipientPicker(groupID: widget.groupID!)));
    if (!mounted || member == null || !_sameAccount) return;
    setState(() {
      _recvID = member.userID;
      _recvName = member.nickname;
      _recvFaceURL = member.faceURL;
      _error = null;
    });
    await _load();
  }

  Future<void> _setPassword() async {
    await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => TradePasswordPage(service: _settings)));
    if (mounted && _sameAccount) await _load();
  }

  void _requirePaymentAccount() {
    if (!mounted || !_sameAccount || _accountID.isEmpty) {
      throw PasswordPaymentException(mounted
          ? _text('登录状态已变更，请重新打开页面',
              'Your account changed. Please reopen this page.')
          : 'Your account changed. Please reopen this page.');
    }
  }

  String _paymentError(Object error) => error is PasswordPaymentException
      ? error.message
      : fundErrorMessage(error,
          chinese:
              !mounted || Localizations.localeOf(context).languageCode != 'en');

  void _returnPaidOrder(FundOrder order) {
    if (!mounted ||
        !_sameAccount ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    IMViews.showToast(_text(
      widget.isRedPacket ? '红包已发出' : '转账成功，已直接到账',
      widget.isRedPacket
          ? 'Red packet sent'
          : 'Transfer completed; funds delivered',
    ));
    Navigator.of(context).pop(order);
  }

  Future<void> _submit() async {
    if (_sheetOpen ||
        _choosingCurrency ||
        _submitting ||
        _loading ||
        _pendingEntryConflict) {
      return;
    }
    if (_completedOrder != null) {
      _returnPaidOrder(_completedOrder!);
      return;
    }
    if (!_form.currentState!.validate()) return;
    try {
      _requirePaymentAccount();
    } catch (error) {
      setState(() => _error = _paymentError(error));
      return;
    }
    if (_needsRecipient && ((_recvID ?? '').isEmpty || _recvID == _accountID)) {
      setState(() => _error =
          _text('请选择其他成员作为收款人', 'Choose another member as the recipient'));
      return;
    }
    if (!_passwordSet) {
      await _setPassword();
      return;
    }
    // Freeze the reviewed business fields. A currency change before submitting
    // creates a new draft; an unresolved submitted order keeps its original ID.
    var draft = FundPaymentDraft(_pending ??
        <String, dynamic>{
          'clientOrderID': FundApi.createClientOrderID(),
          'scene': _group
              ? 'group'
              : widget.internalWithdrawal
                  ? 'internal'
                  : 'single',
          'currency': _currency.code,
          'remark': FundRemark.normalize(_remark.text),
          if (widget.isRedPacket) 'biz': _biz.code,
          if (_multiple && _biz == FundPacketBiz.normal)
            'shareAmount':
                FundAmount.parse(_amount.text.trim(), _currency).decimal
          else
            'amount': _total!.decimal,
          if (_multiple) 'shareCount': int.parse(_count.text),
          if (_needsRecipient) 'recvID': _recvID,
          if (_needsRecipient) 'recipientName': _recvName,
          if (_group) 'groupID': widget.groupID,
          if (!widget.isRedPacket && _recipientType != null)
            'recipientType': _recipientType,
          if (!widget.isRedPacket && _recipientAccount != null)
            'recipient': _recipientAccount,
          if (!widget.isRedPacket && _recipientAreaCode != null)
            'areaCode': _recipientAreaCode,
        });
    final total = draft.total;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _sheetOpen = true;
      _error = null;
    });
    try {
      if (!widget.isRedPacket) {
        if (_pending != null) {
          final recovered = await _recoverTransfer(draft.request);
          if (recovered != null) {
            _returnPaidOrder(recovered);
            return;
          }
        }
        if (!mounted) return;
        await _transferAuthorization.authorize(
            context, draft.request, () => mounted && _sameAccount);
        if (!mounted) return;
        _requirePaymentAccount();
        if (ModalRoute.of(context)?.isCurrent != true) return;
      }
      if (!mounted) return;
      final order = await showPasswordPaymentSheet<FundOrder>(
        context: context,
        builder: (sheetContext) => FundPaySheet(
          total: total,
          title: _text(widget.isRedPacket ? '红包' : (_group ? '群转账' : '转账'),
              widget.isRedPacket ? 'Red Packet' : 'Transfer'),
          available: _balance?.available.displayDecimal ?? '—',
          recipient: _multiple
              ? _text('群红包', 'Group packet')
              : (_recvName ?? _text('聊天对象', 'Chat recipient')),
          paymentDetails: () => FundPaymentDetails(
              total: draft.total,
              available: _balances
                      .where((balance) => balance.currency == draft.currency)
                      .firstOrNull
                      ?.available
                      .displayDecimal ??
                  '—'),
          canChangePaymentMethod: () => _canChangePaymentCurrency,
          onChangePaymentMethod: () async {
            if (!_canChangePaymentCurrency) return false;
            final selected = await _pickCurrency(draft.currency);
            _requirePaymentAccount();
            if (!sheetContext.mounted ||
                ModalRoute.of(sheetContext)?.isActive != true ||
                !_canChangePaymentCurrency ||
                selected == null) {
              return false;
            }
            final next = draft.withCurrency(selected);
            await _rememberCurrency(selected);
            if (!sheetContext.mounted ||
                ModalRoute.of(sheetContext)?.isActive != true ||
                !_canChangePaymentCurrency) {
              return false;
            }
            if (identical(next, draft)) return false;
            draft = next;
            setState(() {
              _currency = selected;
              _error = null;
            });
            return true;
          },
          onPay: (pin) => _pay(draft.request, pin),
          errorMessage: _paymentError,
        ),
      );
      if (order != null) _returnPaidOrder(order);
    } catch (error) {
      if (mounted && _sameAccount) {
        setState(() => _error = _paymentError(error));
      }
    } finally {
      if (mounted) {
        setState(() {
          _sheetOpen = false;
          _submitting = false;
        });
      }
    }
  }

  Future<FundOrder?> _recoverTransfer(Map<String, dynamic> request) async {
    final recovered = await _transferAuthorization.recover(request);
    _requirePaymentAccount();
    if (recovered == null) return null;
    _completedOrder = recovered;
    try {
      await _store.clear(_scope, clientOrderID: request['clientOrderID']);
      _pending = null;
    } catch (_) {}
    _requirePaymentAccount();
    return recovered;
  }

  /// One active attempt at a time, with a confirmed result cached separately
  /// from persistence/refresh. Even a repeated UI callback cannot pay twice.
  Future<FundOrder> _pay(Map<String, dynamic> request, String pin) async {
    _requirePaymentAccount();
    if (_completedOrder != null) return _completedOrder!;
    if (_paymentAttempt != null) return _paymentAttempt!;
    final attempt = _performPayment(request, pin);
    _paymentAttempt = attempt;
    try {
      return await attempt;
    } finally {
      if (identical(_paymentAttempt, attempt)) _paymentAttempt = null;
    }
  }

  Future<FundOrder> _performPayment(
      Map<String, dynamic> request, String pin) async {
    // Re-evaluate on every attempt. A password error on a prior uncertain
    // write says nothing about whether that original order already committed.
    final hadPending = _pending != null;
    var requestSent = false;
    setState(() => _submitting = true);
    try {
      if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
        throw PasswordPaymentException(
            _text('请输入六位支付密码', 'Enter a six-digit payment password'));
      }
      FundSecurityProof? proof;
      if (!widget.isRedPacket) {
        if (hadPending) {
          final recovered = await _recoverTransfer(request);
          if (recovered != null) {
            return recovered;
          }
        }
        if (!mounted) {
          throw const PasswordPaymentException('页面已关闭，请重新打开');
        }
        proof = await _transferAuthorization.authorize(
            context, request, () => mounted && _sameAccount);
        _requirePaymentAccount();
      }
      await _store.save(_scope, request);
      _requirePaymentAccount();
      setState(() {
        _pending = request;
        _error = null;
      });
      requestSent = true;
      final scene = FundScene.values
          .firstWhere((value) => value.name == request['scene']);
      final currency = FundCurrency.parse(request['currency']);
      final order = widget.isRedPacket
          ? await _api.sendPacket(
              clientOrderID: request['clientOrderID'],
              scene: scene,
              biz: FundPacketBiz.values
                  .firstWhere((value) => value.code == request['biz']),
              currency: currency,
              amount: request['amount'] == null
                  ? null
                  : FundAmount.parse(request['amount'], currency),
              shareAmount: request['shareAmount'] == null
                  ? null
                  : FundAmount.parse(request['shareAmount'], currency),
              shareCount: request['shareCount'],
              recvID: request['recvID'],
              groupID: request['groupID'],
              payPassword: pin,
              remark: request['remark'] as String?,
            )
          : await _api.sendTransfer(
              clientOrderID: request['clientOrderID'],
              scene: scene,
              amount: FundAmount.parse(request['amount'], currency),
              recvID: request['recvID'],
              groupID: request['groupID'],
              payPassword: pin,
              remark: request['remark'] as String?,
              recipientType: request['recipientType'] as String?,
              recipient: request['recipient'] as String?,
              areaCode: request['areaCode'] as String?,
              verifyChallengeID: proof?.challengeID,
              verifyCode: proof?.code,
            );
      // Delivery has been confirmed. Local cleanup cannot turn success into
      // another payment attempt. Failed cleanup retains the same durable ID.
      _transferAuthorization.invalidate();
      _completedOrder = order;
      try {
        await _store.clear(_scope, clientOrderID: request['clientOrderID']);
        _pending = null;
      } catch (_) {}
      // The old account's payment is final, but its result must not be shown
      // as success in a different account/server session while HTTP was pending.
      _requirePaymentAccount();
      return order;
    } catch (error) {
      if (error is FundApiException &&
          const {20076, 20077, 20078}.contains(error.code)) {
        _transferAuthorization.invalidate();
      }
      if (error is FundPendingConflict) {
        if (mounted && _sameAccount) await _load();
        throw PasswordPaymentException(mounted
            ? _text('已有一笔交易待确认，请关闭支付窗口后重试原交易',
                'A payment is already pending. Close this sheet and review the original payment.')
            : 'A payment is already pending.');
      }
      if (requestSent &&
          !hadPending &&
          ((error is FundApiException && !error.isUncertain) ||
              error is FormatException ||
              error is ArgumentError)) {
        try {
          await _store.clear(_scope, clientOrderID: request['clientOrderID']);
          _pending = null;
        } catch (_) {}
      }
      final failure = requestSent ||
              error is PasswordPaymentException ||
              error is FundApiException ||
              error is FormatException
          ? error
          : PasswordPaymentException(mounted
              ? _text('无法保存本次交易，请重试', 'Cannot save this payment. Please retry.')
              : 'Cannot save this payment. Please retry.');
      if (mounted) {
        setState(() {
          if (error is FundApiException && error.code == 20034) {
            _passwordSet = false;
          }
          _error = _paymentError(failure);
        });
      }
      throw failure;
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _transferAuthorization.invalidate();
    WidgetsBinding.instance.removeObserver(this);
    _amount.dispose();

    _amountFocus.dispose();
    _count.dispose();
    _remark.dispose();
    _recipientInput.dispose();
    _transferRecipients.close();
    super.dispose();
  }

  FundBalance? get _balance =>
      _balances.where((b) => b.currency == _currency).firstOrNull;
  String _bizLabel(FundPacketBiz biz) => switch (biz) {
        FundPacketBiz.normal => _text('普通红包', 'Regular packet'),
        FundPacketBiz.lucky => _text('拼手气红包', 'Lucky packet'),
        FundPacketBiz.exclusive => _text('专属红包', 'Exclusive packet'),
      };
  Future<void> _choosePacketType() async {
    if (_locked || _loading) return;
    final cs = FundPageColors.of(context);
    final selected = await showModalBottomSheet<FundPacketBiz>(
        context: context,
        backgroundColor: cs.card,
        builder: (context) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final biz in [
                FundPacketBiz.lucky,
                FundPacketBiz.normal,
                FundPacketBiz.exclusive
              ])
                ListTile(
                    enabled: biz != _biz,
                    title: Text(_bizLabel(biz), textAlign: TextAlign.center),
                    onTap: () => Navigator.of(context).pop(biz)),
              Divider(color: cs.line),
              ListTile(
                  title:
                      Text(_text('取消', 'Cancel'), textAlign: TextAlign.center),
                  onTap: () => Navigator.of(context).pop()),
            ])));
    if (!mounted || selected == null || !_sameAccount || _locked) return;
    setState(() {
      _biz = selected;
      _error = null;
    });
  }

  Future<void> _chooseCurrency() async {
    if (_locked || _loading) return;
    setState(() => _choosingCurrency = true);
    try {
      final selected = await _pickCurrency(_currency);
      if (selected == null || !_canChangeCurrency || _sheetOpen) return;
      await _rememberCurrency(selected);
      if (!_canChangeCurrency || _sheetOpen) return;
      setState(() {
        _currency = selected;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _paymentError(error));
    } finally {
      if (mounted) setState(() => _choosingCurrency = false);
    }
  }

  Future<void> _rememberCurrency(FundCurrency currency) async {
    _requirePaymentAccount();
    try {
      await _paymentPreferences.save(currency);
    } catch (_) {
      throw PasswordPaymentException(mounted
          ? _text('无法保存支付币种，请重试', 'Cannot save payment currency. Please retry.')
          : 'Cannot save payment currency. Please retry.');
    }
    _requirePaymentAccount();
  }

  Future<FundCurrency?> _pickCurrency(FundCurrency selected) =>
      showModalBottomSheet<FundCurrency>(
          context: context,
          isScrollControlled: true,
          backgroundColor: FundPageColors.of(context).card,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
          builder: (_) =>
              FundPayMethodSheet(balances: _balances, selected: selected));

  @override
  Widget build(BuildContext context) => widget.internalWithdrawal
      ? FundInternalTransferForm(
          currency: _currency,
          accountType: _accountType,
          phoneAreaCode: _phoneAreaCode,
          recipientInput: _recipientInput,
          amount: _amount,
          amountFocus: _amountFocus,
          formKey: _form,
          isLocked: _locked,
          isLoading: _loading,
          isSubmitting: _submitting || _resolvingRecipient,
          canSubmit: _sameAccount &&
              !_choosingTransferAccount &&
              (_pending != null || _balance != null) &&
              ((_recvID ?? '').isNotEmpty ||
                  _recipientInput.text.trim().isNotEmpty) &&
              _validateInternalAmount(_amount.text) == null,
          hasPending: _pending != null,
          passwordSet: _passwordSet,
          available: _balance?.available.displayDecimal ?? '0.00',
          arrivalAmount: _total?.displayDecimal ?? '0.00',
          recipientName: _recvName,
          recipientFaceURL: _recvFaceURL,
          error: _error,
          onEdited: () => setState(() => _error = null),
          onRecipientEdited: _recipientEdited,
          onRecipientSubmitted: _confirmTransferRecipient,
          onChooseAccountType: _chooseAccountType,
          onChooseAreaCode: _chooseTransferAreaCode,
          onChooseRecipient: _chooseTransferFriend,
          onAll: _useAll,
          onSubmit: _submitInternalTransfer,
          onReload: _load,
          onSetPassword: _setPassword,
          onClose: () => Navigator.of(context).pop(),
          onHelp: _transferHelp,
          onHistory: _transferHistory,
          validateAmount: _validateInternalAmount,
          validateRecipient: _validateTransferRecipient,
        )
      : FundSendForm(
          isRedPacket: widget.isRedPacket,
          isGroup: _group,
          isMultiple: _multiple,
          isLocked: _locked,
          isLoading: _loading,
          isSubmitting: _submitting,
          passwordSet: _passwordSet,
          hasPending: _pending != null,
          hasBalances: _balances.isNotEmpty,
          currency: _currency,
          biz: _biz,
          amount: _amount,
          count: _count,
          remark: _remark,
          amountFocus: _amountFocus,
          formKey: _form,
          total: _total,
          balance: _balance,
          recipientID: _recvID,
          recipientName: _recvName,
          recipientFaceURL: _recvFaceURL,
          error: _error,
          onEdited: () => setState(() => _error = null),
          onChooseType: _choosePacketType,
          onChooseCurrency: _chooseCurrency,
          onChooseRecipient: _pickRecipient,
          onSubmit: _submit,
          onReload: _load,
          onSetPassword: _setPassword,
          onClose: () => Navigator.of(context).pop(),
          validateAmount: _validateAmount,
          validateRemark: _validateRemark);
}
