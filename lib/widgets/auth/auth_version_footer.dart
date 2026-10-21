import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'auth_reference_tokens.dart';

/// Uses the installed version when an entry page does not provide one.
class AuthVersionFooter extends StatefulWidget {
  const AuthVersionFooter({super.key, this.version});

  final String? version;

  @override
  State<AuthVersionFooter> createState() => _AuthVersionFooterState();
}

class _AuthVersionFooterState extends State<AuthVersionFooter> {
  late final Future<String> _installedVersion = _readVersion();

  Future<String> _readVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.buildNumber.isEmpty
        ? info.version
        : '${info.version}+${info.buildNumber}';
  }

  Widget _text(String version) => Text('Version $version',
      textAlign: TextAlign.center,
      style: AuthReferenceTokens.style(context, AuthReferenceTokens.caption));

  @override
  Widget build(BuildContext context) {
    if (widget.version != null) return _text(widget.version!);
    return FutureBuilder<String>(
      future: _installedVersion,
      builder: (context, snapshot) => _text(snapshot.data ?? '—'),
    );
  }
}
