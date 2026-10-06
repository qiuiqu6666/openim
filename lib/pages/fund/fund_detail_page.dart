import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../../services/fund_api.dart';
import 'notifications/fund_claim_notice.dart';
import '../mine/settings/widgets/settings_widgets.dart';
import 'widgets/fund_detail_message_sender.dart';
import 'widgets/fund_page_colors.dart';
import 'widgets/fund_packet_cover.dart';
import 'widgets/fund_packet_detail.dart';
import 'widgets/fund_transfer_detail.dart';

export 'widgets/fund_detail_message_sender.dart';

typedef FundPartyNameResolver = Future<Map<String, String>> Function(
    FundOrder order, List<String> userIDs);

class FundPartyProfile {
  const FundPartyProfile({required this.name, this.faceURL = ''});
  final String name;
  final String faceURL;
}

typedef FundPartyProfileResolver = Future<Map<String, FundPartyProfile>>
    Function(FundOrder order, List<String> userIDs);

/// Keeps the latest verified order as the result of system and gesture back,
/// as well as the app bar back button.
class FundDetailRoute extends PageRouteBuilder<FundOrder> {
  factory FundDetailRoute({
    required FundMessageData message,
    FundApi? api,
    String? currentUserID,
    FundDetailMessageSender? messageSender,
    FundPartyNameResolver? nameResolver,
    FundPartyProfileResolver? profileResolver,
  }) {
    final result = _FundDetailResult();
    return FundDetailRoute._(result, message, api, currentUserID, messageSender,
        nameResolver, profileResolver);
  }

  FundDetailRoute._(
    _FundDetailResult result,
    FundMessageData message,
    FundApi? api,
    String? currentUserID,
    FundDetailMessageSender? messageSender,
    FundPartyNameResolver? nameResolver,
    FundPartyProfileResolver? profileResolver,
  )   : _result = result,
        super(
          opaque: false,
          barrierColor: FundTokens.transparent,
          transitionDuration: FundTokens.openAnimationDuration,
          reverseTransitionDuration: FundTokens.openAnimationDuration,
          pageBuilder: (_, __, ___) => FundDetailPage._route(
            message: message,
            api: api,
            currentUserID: currentUserID,
            messageSender: messageSender,
            nameResolver: nameResolver,
            profileResolver: profileResolver,
            onOrderChanged: (order) => result.order = order,
          ),
        );

  final _FundDetailResult _result;

  @override
  FundOrder? get currentResult => _result.order;

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation, Widget child) =>
      MediaQuery.disableAnimationsOf(context)
          ? child
          : FadeTransition(opacity: animation, child: child);
}

class _FundDetailResult {
  FundOrder? order;
}

class FundDetailPage extends StatefulWidget {
  const FundDetailPage({
    super.key,
    required this.message,
    this.api,
    this.currentUserID,
    this.messageSender,
    this.nameResolver,
    this.profileResolver,
  }) : _onOrderChanged = null;

  const FundDetailPage._route({
    required this.message,
    this.api,
    this.currentUserID,
    this.messageSender,
    this.nameResolver,
    this.profileResolver,
    required ValueChanged<FundOrder> onOrderChanged,
  }) : _onOrderChanged = onOrderChanged;

  final FundMessageData message;
  final FundApi? api;
  final String? currentUserID;
  final FundDetailMessageSender? messageSender;
  final FundPartyNameResolver? nameResolver;
  final FundPartyProfileResolver? profileResolver;
  final ValueChanged<FundOrder>? _onOrderChanged;

  @override
  State<FundDetailPage> createState() => _FundDetailPageState();
}

class _FundDetailPageState extends State<FundDetailPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late FundApi _api;
  late AnimationController _openingController;
  late AnimationController _splitController;
  late String _serverURL;
  late String _sessionUserID;
  FundOrder? _order;
  FundAmount? _claimedAmount;
  Object? _loadError;
  Object? _claimError;
  bool _loading = true;
  bool _claiming = false;
  bool _claimAttempted = false;
  bool _canRetryClaim = false;
  bool _showPacketDetails = false;
  bool _opening = false;
  bool _coverSplitting = false;
  int _requestVersion = 0;
  int _identityVersion = 0;
  int _profileVersion = 0;
  final Map<String, String> _partyNames = {};
  final Map<String, String> _partyFaces = {};
  final Set<String> _requestedNames = {};

  String get _userID => widget.currentUserID ?? OpenIM.iMManager.userID;

  @override
  void initState() {
    super.initState();
    _serverURL = Config.appAuthUrl;
    _sessionUserID = _userID;
    _api = widget.api ?? FundApi(baseUrl: _serverURL);
    _openingController =
        AnimationController(vsync: this, duration: FundTokens.openingDuration);
    _splitController =
        AnimationController(vsync: this, duration: FundTokens.splitDuration);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant FundDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.orderID != widget.message.orderID ||
        oldWidget.message.biz != widget.message.biz ||
        oldWidget.message.currency != widget.message.currency ||
        oldWidget.message.amount != widget.message.amount ||
        oldWidget.currentUserID != widget.currentUserID ||
        oldWidget.api != widget.api ||
        oldWidget.nameResolver != widget.nameResolver ||
        oldWidget.profileResolver != widget.profileResolver) {
      _identityVersion++;
      _sessionUserID = _userID;
      _api = widget.api ?? FundApi(baseUrl: _serverURL);
      _order = null;
      _claimedAmount = null;
      _claimAttempted = false;
      _claiming = false;
      _claimError = null;
      _canRetryClaim = false;
      _showPacketDetails = false;
      _opening = false;
      _coverSplitting = false;
      _openingController.reset();
      _splitController.reset();
      _partyNames.clear();
      _partyFaces.clear();
      _requestedNames.clear();
      unawaited(_load());
    } else if (oldWidget.messageSender != widget.messageSender) {
      // Display enrichment must not reset an in-flight financial operation.
      _profileVersion++;
      _partyNames.clear();
      _partyFaces.clear();
      _requestedNames.clear();
      final order = _order;
      if (order != null) unawaited(_resolvePartyNames(order, _userID));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !_loading &&
        !_claiming &&
        !_opening) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _requestVersion++;
    _identityVersion++;
    WidgetsBinding.instance.removeObserver(this);
    _openingController.dispose();
    _splitController.dispose();
    super.dispose();
  }

  bool _isCurrent(int version, String userID) =>
      mounted &&
      version == _requestVersion &&
      userID == _userID &&
      userID == _sessionUserID &&
      _serverURL == Config.appAuthUrl;

  void _verifyOrder(FundOrder order, String userID) {
    final message = widget.message;
    if (userID.isEmpty ||
        order.orderID != message.orderID ||
        order.biz != message.biz ||
        order.currency.code != message.currency ||
        order.amount != FundAmount.parse(message.amount, order.currency) ||
        !order.amount.isPositive ||
        !const {'open', 'done', 'refunded'}.contains(order.status)) {
      throw const FormatException('Invalid fund order reference');
    }
    if ((order.scene == FundScene.group && order.groupID.isEmpty) ||
        (order.scene != FundScene.group && order.groupID.isNotEmpty) ||
        (order.biz == 'packet_lucky' && order.scene != FundScene.group) ||
        (order.biz == 'group_transfer' && order.scene != FundScene.group)) {
      throw const FormatException('Invalid fund order scene');
    }
    if (order.requiresClaim) {
      if (order.shareCount <= 0 || order.shares.length > order.shareCount) {
        throw const FormatException('Invalid fund packet shares');
      }
    } else if (order.recvID.isEmpty ||
        (order.senderID.isNotEmpty && order.senderID == order.recvID) ||
        order.status != 'done') {
      throw const FormatException('Invalid fund recipient');
    }
    if (order.senderID.isNotEmpty &&
        order.scene != FundScene.group &&
        userID != order.senderID &&
        userID != order.recvID) {
      throw const FormatException('Fund order is not visible to this user');
    }
    // The authenticated GET authorizes visibility when the server omits the
    // sender. Group membership and claims remain server-authorized. SDK sender
    // metadata is display-only and cannot bypass any financial checks above.
  }

  Future<bool> _load() async {
    if (_serverURL != Config.appAuthUrl || _userID != _sessionUserID) {
      return false;
    }
    final version = ++_requestVersion;
    final userID = _userID;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final order = await _api.getOrder(widget.message.orderID);
      if (!_isCurrent(version, userID)) return false;
      _verifyOrder(order, userID);
      setState(() {
        _order = order;
        _loading = false;
        if (!order.requiresClaim || order.claimedShareFor(userID) != null) {
          _showPacketDetails = true;
        }
        if (order.claimedShareFor(userID) != null ||
            (_claimError is FundApiException &&
                (_claimError as FundApiException).code == 20028 &&
                (!order.isOpen || order.isExpired))) {
          _claimError = null;
          _canRetryClaim = false;
        }
      });
      widget._onOrderChanged?.call(order);
      unawaited(_resolvePartyNames(order, userID));
      return true;
    } catch (error) {
      if (!_isCurrent(version, userID)) return false;
      setState(() {
        _loadError = error;
        _loading = false;
      });
      return false;
    }
  }

  bool _canClaim(FundOrder order) =>
      !_claiming &&
      _loadError == null &&
      _serverURL == Config.appAuthUrl &&
      _userID == _sessionUserID &&
      _userID.isNotEmpty &&
      order.requiresClaim &&
      order.isOpen &&
      !order.isExpired &&
      order.claimedShareFor(_userID) == null &&
      _claimedAmount == null;

  Future<void> _resolvePartyNames(FundOrder order, String userID) async {
    if (!mounted ||
        userID != _sessionUserID ||
        userID != _userID ||
        _serverURL != Config.appAuthUrl) {
      return;
    }
    final candidates = <String>{
      _displaySenderID(order),
      if (order.recvID.isNotEmpty) order.recvID,
      for (final share in order.shares)
        if (share.isClaimed) share.claimerID,
    };
    final userIDs = candidates
        .where((id) =>
            id.isNotEmpty &&
            (id != userID || widget.nameResolver == null) &&
            !_requestedNames.contains(id))
        .take(FundTokens.memberPageSize)
        .toList(growable: false);
    if (userIDs.isEmpty) return;
    final identityVersion = _identityVersion;
    final profileVersion = _profileVersion;
    _requestedNames.addAll(userIDs);
    try {
      final Map<String, FundPartyProfile> profiles;
      if (widget.nameResolver != null) {
        final names = await widget.nameResolver!(order, userIDs);
        profiles = {
          for (final entry in names.entries)
            entry.key: FundPartyProfile(name: entry.value),
        };
      } else {
        profiles =
            await (widget.profileResolver ?? _sdkPartyProfiles)(order, userIDs);
      }
      if (!mounted ||
          identityVersion != _identityVersion ||
          profileVersion != _profileVersion ||
          _userID != userID ||
          userID != _sessionUserID ||
          _serverURL != Config.appAuthUrl ||
          _order?.orderID != order.orderID) {
        return;
      }
      setState(() {
        for (final id in userIDs) {
          final name = profiles[id]?.name.trim() ?? '';
          if (name.isNotEmpty && name != id) _partyNames[id] = name;
          final face = profiles[id]?.faceURL.trim() ?? '';
          if (face.isNotEmpty) _partyFaces[id] = face;
        }
      });
    } catch (_) {
      // Identity enrichment is optional. The verified order remains readable
      // when profile lookup is unavailable or the user has left the group.
    }
  }

  static Future<Map<String, FundPartyProfile>> _sdkPartyProfiles(
      FundOrder order, List<String> userIDs) async {
    if (order.scene == FundScene.group) {
      final members = await OpenIM.iMManager.groupManager.getGroupMembersInfo(
        groupID: order.groupID,
        userIDList: userIDs,
      );
      return {
        for (final member in members)
          if (member.userID != null)
            member.userID!: FundPartyProfile(
                name: member.nickname ?? '', faceURL: member.faceURL ?? ''),
      };
    }
    final users = await OpenIM.iMManager.userManager.getUsersInfo(
      userIDList: userIDs,
    );
    return {
      for (final user in users)
        if (user.userID != null)
          user.userID!: FundPartyProfile(
              name: user.nickname ?? '', faceURL: user.faceURL ?? ''),
    };
  }

  FundDetailMessageSender? _messageSenderFor(FundOrder order) {
    final sender = widget.messageSender;
    final id = sender?.userID.trim() ?? '';
    if (sender == null ||
        id.isEmpty ||
        (order.senderID.isNotEmpty && id != order.senderID) ||
        (!order.requiresClaim && id == order.recvID)) {
      return null;
    }
    return sender;
  }

  String _displaySenderID(FundOrder order) => order.senderID.isNotEmpty
      ? order.senderID
      : _messageSenderFor(order)?.userID.trim() ?? '';

  String _displayPartyID(FundOrder order, String id) =>
      id.isEmpty && order.senderID.isEmpty ? _displaySenderID(order) : id;

  String _partyName(FundOrder order, String id) {
    final displayID = _displayPartyID(order, id);
    if (displayID.isEmpty) return _text('发送人', 'Sender');
    if (displayID == _userID) return _text('我', 'You');
    final resolved = _partyNames[displayID];
    if (resolved != null) return resolved;
    final sender = _messageSenderFor(order);
    final nickname = sender?.nickname.trim() ?? '';
    if (displayID == sender?.userID.trim() &&
        nickname.isNotEmpty &&
        nickname != displayID) {
      return nickname;
    }
    return order.scene == FundScene.group
        ? _text('群成员', 'Group member')
        : _text('聊天对象', 'Chat contact');
  }

  Widget _partyAvatar(FundOrder order, String id, double size) {
    final displayID = _displayPartyID(order, id);
    final sender = _messageSenderFor(order);
    final contextFace =
        displayID == sender?.userID.trim() ? sender?.faceURL.trim() : null;
    return ExcludeSemantics(
      child: AvatarView(
        key: ValueKey('fund-detail-avatar-$displayID'),
        width: size,
        height: size,
        url: _partyFaces[displayID] ?? contextFace,
        text: _partyName(order, id),
        textStyle: const TextStyle(
            color: AppTokens.onAccent, fontSize: AppTokens.secondaryFontSize),
        isCircle: true,
      ),
    );
  }

  Future<void> _claim() async {
    final order = _order;
    if (order == null || _loading || !_canClaim(order)) return;
    final version = ++_requestVersion;
    final userID = _userID;
    final api = _api;
    final animate = !MediaQuery.disableAnimationsOf(context);
    setState(() {
      _claiming = true;
      _claimAttempted = true;
      _claimError = null;
      _canRetryClaim = false;
      _opening = animate;
      _coverSplitting = false;
    });
    if (animate) {
      _splitController.reset();
      _openingController.repeat();
    }
    try {
      final result = await api.claimPacket(order.orderID);
      if (!_isCurrent(version, userID)) return;
      if (result.orderID != order.orderID) {
        throw const FormatException('Invalid fund claim order');
      }
      final amount = FundAmount.parse(result.amount, order.currency);
      if (!amount.isPositive || amount.compareTo(order.amount) > 0) {
        throw const FormatException('Invalid fund claim amount');
      }
      setState(() {
        _claimedAmount = amount;
        _showPacketDetails = true;
      });
      unawaited(FundClaimNoticeSender.shared.send(order, userID,
          messageSenderID: widget.messageSender?.userID ?? ''));
      unawaited(_api.fetchBalances().then<void>((_) {}).catchError((_) {}));
    } catch (error) {
      if (!_isCurrent(version, userID)) return;
      setState(() {
        _claimError = error;
        _canRetryClaim = error is! FundApiException ||
            !const {20028, 20029, 20033}.contains(error.code);
      });
    }
    if (!_isCurrent(version, userID)) return;
    // A successful claim or an already-claimed/closed response both require
    // fresh shares and status. Never fabricate them from the chat message.
    final refresh = _load();
    final refreshVersion = _requestVersion;
    await refresh;
    if (!_isCurrent(refreshVersion, userID) ||
        widget.message.orderID != order.orderID ||
        !identical(api, _api)) {
      return;
    }
    setState(() => _claiming = false);
    await _finishOpening(order, userID, api);
  }

  Future<void> _finishOpening(
      FundOrder order, String userID, FundApi api) async {
    _openingController.stop();
    _openingController.value = 0;
    if (!_opening) return;
    if (!_showPacketDetails) {
      setState(() => _opening = false);
      return;
    }
    final identityVersion = _identityVersion;
    setState(() => _coverSplitting = true);
    await _splitController.forward(from: 0);
    if (!mounted ||
        identityVersion != _identityVersion ||
        userID != _userID ||
        userID != _sessionUserID ||
        _serverURL != Config.appAuthUrl ||
        _order?.orderID != order.orderID ||
        !identical(api, _api)) {
      return;
    }
    setState(() {
      _opening = false;
      _coverSplitting = false;
    });
  }

  Future<void> _retryClaim() async {
    if (_loading || _claiming) return;
    if (await _load()) {
      await _claim();
    }
  }

  String _text(String zh, String en) => settingsText(context, zh: zh, en: en);

  String _errorMessage(Object error) => error is FormatException
      ? _text('订单信息不匹配或不完整，请重试',
          'Order information is invalid or incomplete. Please retry.')
      : fundErrorMessage(error,
          chinese: Localizations.localeOf(context).languageCode == 'zh');

  @override
  Widget build(BuildContext context) {
    final order = _order;
    if (order == null) return _buildLoadingOrError();
    if (order.isTransfer) return _buildTransferDetail(order);
    if (order.requiresClaim && (!_showPacketDetails || _opening)) {
      return _buildModal(order);
    }
    return _buildPacketDetail(order);
  }

  String _greeting(FundOrder order) {
    final remark = order.remark.trim();
    return remark.isNotEmpty
        ? remark
        : _text('恭喜发财，大吉大利', 'Best wishes and good fortune');
  }

  PreferredSizeWidget _detailAppBar(
      {bool immersive = false, bool transfer = false}) {
    final cs = FundPageColors.of(context);
    final foreground = immersive
        ? AppTokens.onAccent
        : transfer
            ? FundTokens.transferBlue
            : cs.blue;
    final leading = IconButton(
        tooltip: _text('返回', 'Back'),
        color: cs.blue,
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
        onPressed: () => Navigator.of(context).pop(_order));
    final title = transfer
        ? null
        : Text(_text('红包详情', 'Red Packet Details'),
            style: TextStyle(
                fontSize: AppTokens.listTitleFontSize,
                fontWeight: FontWeight.w600,
                color: immersive ? AppTokens.onAccent : cs.text));
    final actions = transfer
        ? null
        : [
            IconButton(
                key: const ValueKey('fund-detail-menu'),
                tooltip: _text('更多', 'More'),
                onPressed: _loading || _claiming ? null : _showMoreMenu,
                icon: Icon(Icons.more_horiz_rounded,
                    color: foreground, size: FundTokens.iconSize)),
            const SizedBox(width: AppTokens.s2),
          ];
    if (immersive) {
      // Keep the whole packet header one solid color. A glass surface would
      // tint the navigation region differently from the curved painter.
      return AppBar(
        toolbarHeight: kToolbarHeight,
        centerTitle: true,
        automaticallyImplyLeading: false,
        backgroundColor: FundTokens.luckyHeader,
        foregroundColor: AppTokens.onAccent,
        iconTheme: IconThemeData(color: foreground),
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: FundTokens.transparent,
        surfaceTintColor: FundTokens.transparent,
        systemOverlayStyle: AppSystemBars.styleFor(FundTokens.luckyHeader),
        leading: leading,
        title: title,
        actions: actions,
      );
    }
    return GlassAppBar(
      toolbarHeight: kToolbarHeight,
      iconTheme: IconThemeData(color: foreground),
      centerTitle: true,
      elevation: 0,
      shadowColor: FundTokens.transparent,
      surfaceTintColor: FundTokens.transparent,
      backgroundColor: transfer ? cs.card : cs.bg,
      foregroundColor: cs.text,
      systemOverlayStyle: AppSystemBars.styleFor(cs.bg),
      leading: leading,
      automaticallyImplyLeading: false,
      title: title,
      actions: actions,
    );
  }

  Future<void> _showMoreMenu() async {
    final cs = FundPageColors.of(context);
    final refresh = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: FundTokens.transparent,
      barrierColor: FundTokens.coverScrim,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(
            AppTokens.s4, 0, AppTokens.s4, AppTokens.s4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Material(
            color: cs.card,
            borderRadius: BorderRadius.circular(AppTokens.rLg),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
                key: const ValueKey('fund-detail-refresh'),
                onTap: () => Navigator.of(sheetContext).pop(true),
                child: SizedBox(
                    height: AppTokens.listItemHeight,
                    child: Center(
                        child: Text(_text('刷新', 'Refresh'),
                            style: TextStyle(
                                color: cs.text,
                                fontSize: AppTokens.listTitleFontSize,
                                fontWeight: FontWeight.w500))))),
          ),
          const SizedBox(height: AppTokens.s3),
          Material(
            color: cs.card,
            borderRadius: BorderRadius.circular(AppTokens.rLg),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
                onTap: () => Navigator.of(sheetContext).pop(false),
                child: SizedBox(
                    height: AppTokens.listItemHeight,
                    child: Center(
                        child: Text(_text('取消', 'Cancel'),
                            style: TextStyle(
                                color: cs.text,
                                fontSize: AppTokens.listTitleFontSize,
                                fontWeight: FontWeight.w600))))),
          ),
        ]),
      ),
    );
    if (mounted && refresh == true && !_loading && !_claiming) await _load();
  }

  Widget _loadingIndicator() => Container(
        width: FundTokens.referenceLoadingSize,
        height: FundTokens.referenceLoadingSize,
        decoration: BoxDecoration(
            color: FundTokens.referenceLoadingBackground,
            borderRadius:
                BorderRadius.circular(FundTokens.referenceLoadingRadius)),
        child: const Center(
            child: CupertinoActivityIndicator(
                radius: AppTokens.s5, color: AppTokens.onAccent)),
      );

  Widget _buildLoadingOrError() {
    final cs = FundPageColors.of(context);
    return Scaffold(
      backgroundColor: cs.bg,
      appBar: _detailAppBar(transfer: widget.message.isTransfer),
      body: Center(
          child: _loading
              ? Semantics(
                  label: _text('正在加载订单', 'Loading order'),
                  child: _loadingIndicator())
              : Padding(
                  key: const ValueKey('fund-detail-load-error'),
                  padding: const EdgeInsets.all(AppTokens.s7),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_errorMessage(_loadError!),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: cs.subText,
                            fontSize: FundTokens.detailTitleFont)),
                    const SizedBox(height: AppTokens.s5),
                    TextButton(
                        onPressed: () => _load(),
                        child: Text(_text('重试', 'Retry'))),
                  ]))),
    );
  }

  Widget _buildModal(FundOrder order) => FundPacketCoverOverlay(
        split: _splitController,
        splitting: _coverSplitting,
        loadingIndicator: _loadingIndicator(),
        onClose: () => Navigator.of(context).pop(_order),
        onViewDetails: _claiming || _opening
            ? null
            : () => setState(() => _showPacketDetails = true),
        viewDetailsLabel: _text('查看领取详情', 'View claim details'),
        closeLabel: _text('关闭红包', 'Close red packet'),
        cover: FundReferenceCover(
          type: _text(order.biz == 'packet_lucky' ? '拼手气红包' : '普通红包',
              order.biz == 'packet_lucky' ? 'Lucky red packet' : 'Red packet'),
          greeting: _greeting(order),
          status: _claiming
              ? _text('正在领取红包', 'Claiming red packet')
              : (!order.isOpen || order.isExpired)
                  ? _statusText(order)
                  : '',
          error: _claimError != null
              ? _errorMessage(_claimError!)
              : _loadError != null
                  ? _errorMessage(_loadError!)
                  : null,
          spin: _openingController,
          split: _splitController,
          opening: _claiming || _opening,
          splitting: _coverSplitting,
          onOpen: !_loading &&
                  _canClaim(order) &&
                  (!_claimAttempted || _canRetryClaim)
              ? () => unawaited(_claimAttempted ? _retryClaim() : _claim())
              : null,
        ),
      );

  Widget _buildPacketDetail(FundOrder order) => FundPacketDetail(
        order: order,
        userID: _userID,
        claimedAmount: _claimedAmount,
        loading: _loading,
        claiming: _claiming,
        appBar: _detailAppBar(immersive: true),
        statusText: _statusText(order),
        greeting: _greeting(order),
        partyAvatar: (id, size) => _partyAvatar(order, id, size),
        partyName: (id) => _partyName(order, id),
        amountView: (amount, currency, font, unit, height) => _amountView(
            amount, currency, font,
            unitFontSize: unit, lineHeight: height),
        text: _text,
        formatTime: _formatTime,
        inlineErrors: _inlineErrors(),
        footer: _packetFooter(order),
        onRefresh: () async {
          if (!_loading && !_claiming) await _load();
        },
        onShowCover:
            _claiming ? null : () => setState(() => _showPacketDetails = false),
      );

  Widget _amountView(FundAmount amount, FundCurrency currency, double fontSize,
          {double unitFontSize = FundTokens.detailUnitFontSize,
          double lineHeight = FundTokens.detailAmountLineHeight}) =>
      FittedBox(
          fit: BoxFit.scaleDown,
          child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: amount.displayDecimal,
                    style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w500,
                        height: lineHeight)),
                TextSpan(
                    text: ' ${currency.displayName}',
                    style: TextStyle(
                        fontSize: unitFontSize, fontWeight: FontWeight.w400))
              ]),
              key: const ValueKey('fund-detail-amount'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: FundTokens.amountGold(
                      dark: FundPageColors.of(context).dark))));

  Widget _buildTransferDetail(FundOrder order) => FundTransferDetail(
        order: order,
        appBar: _detailAppBar(transfer: true),
        sender: _partyName(order, order.senderID),
        receiver: _partyName(order, order.recvID),
        statusText: _statusText(order),
        text: _text,
        formatTime: _formatTime,
        inlineErrors: _inlineErrors(),
        secondaryInfo: _transferOrderInfo(order),
      );

  Widget _detailRow(String label, String value) {
    final cs = FundPageColors.of(context);
    return Row(children: [
      SizedBox(
          width: FundTokens.transferMetaLabelWidth,
          child: Text(label,
              style: TextStyle(
                  fontSize: AppTokens.captionFontSize, color: cs.subText))),
      Expanded(
          child: Text(value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: AppTokens.captionFontSize, color: cs.text)))
    ]);
  }

  Widget _inlineErrors() => Column(children: [
        if (_loadError != null)
          Padding(
              key: const ValueKey('fund-detail-refresh-error'),
              padding: const EdgeInsets.all(AppTokens.s5),
              child: Column(children: [
                Text(_errorMessage(_loadError!), textAlign: TextAlign.center),
                TextButton(
                    onPressed: _claiming ? null : () => _load(),
                    child: Text(_text('重新加载', 'Reload'))),
              ])),
        if (_claimError != null)
          Padding(
              padding: const EdgeInsets.all(AppTokens.s5),
              child: Text(_errorMessage(_claimError!),
                  key: const ValueKey('fund-detail-claim-error'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: settingsDanger(settingsIsDark(context))))),
      ]);

  Widget _transferOrderInfo(FundOrder order) => ExpansionTile(
        key: const ValueKey('fund-detail-order-info'),
        shape: const Border(),
        collapsedShape: const Border(),
        textColor: FundPageColors.of(context).subText,
        collapsedTextColor: FundPageColors.of(context).subText,
        title: Text(_text('交易信息', 'Order information'),
            style: const TextStyle(fontSize: AppTokens.captionFontSize)),
        childrenPadding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s6, vertical: AppTokens.s4),
        children: [
          _detailRow(_text('发件人', 'Sender'), _partyName(order, order.senderID)),
          if (order.recvID.isNotEmpty)
            _detailRow(
                _text('收款人', 'Recipient'), _partyName(order, order.recvID)),
          if (order.createdAt != null)
            _detailRow(_text('发送时间', 'Sent at'), _formatTime(order.createdAt!)),
          if (order.expireAt != null)
            _detailRow(
                _text('到期时间', 'Expires at'), _formatTime(order.expireAt!)),
          Row(children: [
            Text(_text('订单号', 'Order ID')),
            const SizedBox(width: AppTokens.s4),
            Expanded(
                child:
                    SelectableText(order.orderID, textAlign: TextAlign.right))
          ]),
        ],
      );

  Widget _packetFooter(FundOrder order) {
    final cs = FundPageColors.of(context);
    return Padding(
        padding: EdgeInsets.fromLTRB(AppTokens.s7, AppTokens.s4, AppTokens.s7,
            AppTokens.s4 + MediaQuery.paddingOf(context).bottom),
        child: Text(
            order.requiresClaim
                ? _text('到期后未领取红包将自动退回。',
                    'Unclaimed red packets will be refunded after expiry.')
                : _text('已存入收款人的余额。', 'Added to the recipient’s balance.'),
            textAlign: TextAlign.center,
            style: TextStyle(
                color: cs.subText,
                fontSize: FundTokens.recordTimeFont,
                height: 1.4)));
  }

  String _statusText(FundOrder order) {
    if (!order.requiresClaim) {
      if (order.recvID == _userID) {
        return _text('已到账，已存入余额', 'Received in your balance');
      }
      if (order.senderID == _userID) {
        return _text(order.isTransfer ? '已转账，对方已到账' : '红包已发送，对方已到账',
            'Delivered to recipient');
      }
      return _text('${_partyName(order, order.recvID)}已到账',
          'Delivered to ${_partyName(order, order.recvID)}');
    }
    if (_claiming && _claimedAmount == null) {
      return _text('正在领取红包', 'Claiming red packet');
    }
    if (order.isRefunded) return _text('未领取金额已退回', 'Unclaimed amount refunded');
    if (order.status == 'done') {
      return _text('红包已领完', 'Red packet fully claimed');
    }
    if (order.isExpired) {
      return _text('红包已过期，未领取金额将退回',
          'Red packet expired; unclaimed amount will be refunded');
    }
    if (order.claimedShareFor(_userID) != null || _claimedAmount != null) {
      return _text('红包已领取', 'Red packet claimed');
    }
    return _text('查看领取详情', 'View claim details');
  }

  String _formatTime(DateTime value) {
    final time = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}
