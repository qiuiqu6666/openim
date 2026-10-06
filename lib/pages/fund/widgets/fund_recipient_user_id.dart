import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../mine/settings/widgets/settings_widgets.dart';

/// Displays the public account from the same profile source as contact cards.
/// The SDK recipient ID remains the identifier used for payment routing.
class FundRecipientUserID extends StatefulWidget {
  const FundRecipientUserID(
      {super.key, required this.userID, required this.style, this.resolver});

  final String? userID;
  final TextStyle style;
  final ContactCardProfileResolver? resolver;

  @override
  State<FundRecipientUserID> createState() => _FundRecipientUserIDState();
}

class _FundRecipientUserIDState extends State<FundRecipientUserID> {
  ContactCardProfileResolver get _resolver =>
      widget.resolver ?? ContactCardProfileResolver.shared;
  String? _account;
  int _request = 0;
  late (String?, String?, String) _session;
  (String?, String?, String) get _currentSession =>
      (DataSp.userID, DataSp.chatToken, Config.appAuthUrl);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant FundRecipientUserID oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userID != widget.userID ||
        oldWidget.resolver != widget.resolver ||
        _session != _currentSession ||
        _account != _resolver.peek(widget.userID?.trim() ?? '')) {
      _load();
    }
  }

  Future<void> _load() async {
    final request = ++_request;
    final id = widget.userID?.trim() ?? '';
    _session = _currentSession;
    final session = _session;
    _account = id.isEmpty ? null : _resolver.peek(id);
    if (id.isEmpty) return;
    final account = await _resolver.resolve(id);
    if (!mounted || request != _request || widget.userID?.trim() != id) return;
    setState(() => _account = session == _currentSession ? account : null);
  }

  @override
  Widget build(BuildContext context) {
    final cached = _resolver.peek(widget.userID?.trim() ?? '');
    final account =
        _session == _currentSession && cached == _account ? _account : null;
    return SelectableText(
      settingsText(context,
          zh: '99Chat ID号：${account?.isNotEmpty == true ? account : '--'}',
          en: '99Chat ID: ${account?.isNotEmpty == true ? account : '--'}'),
      key: const ValueKey('fund-recipient-public-id'),
      style: widget.style,
    );
  }
}
