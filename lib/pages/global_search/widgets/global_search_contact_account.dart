import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

/// Public identity for display; chat navigation continues using the SDK ID.
class GlobalSearchContactAccount extends StatefulWidget {
  const GlobalSearchContactAccount({super.key, required this.userID});

  final String userID;

  @override
  State<GlobalSearchContactAccount> createState() => _AccountState();
}

class _AccountState extends State<GlobalSearchContactAccount> {
  late Future<String?> _account;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant GlobalSearchContactAccount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userID != widget.userID) _load();
  }

  void _load() {
    _account = ContactCardProfileResolver.shared.resolve(widget.userID);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
        future: _account,
        builder: (context, snapshot) {
          final account = ContactCardProfileResolver.shared.peek(widget.userID);
          return Text(
            account?.isNotEmpty == true ? account! : '--',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          );
        },
      );
}
