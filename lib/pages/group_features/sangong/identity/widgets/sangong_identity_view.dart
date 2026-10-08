import 'dart:async';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../../sangong_scope.dart';
import '../../services/authorization/sangong_operation_scope.dart';
import '../data/sangong_identity_directory.dart';
export '../data/sangong_identity_directory.dart';

class SangongIdentityScope extends InheritedWidget {
  const SangongIdentityScope(
      {super.key, required this.directory, required super.child});
  final SangongIdentityDirectory directory;
  static SangongIdentityDirectory read(BuildContext context) =>
      (context
              .getElementForInheritedWidgetOfExactType<SangongIdentityScope>()
              ?.widget as SangongIdentityScope?)
          ?.directory ??
      SangongIdentityDirectory.shared;
  @override
  bool updateShouldNotify(SangongIdentityScope oldWidget) =>
      directory != oldWidget.directory;
}

class SangongIdentityView extends StatefulWidget {
  const SangongIdentityView(
      {super.key, required this.userID, required this.builder});
  final String userID;
  final Widget Function(SangongDisplayIdentity?) builder;
  @override
  State<SangongIdentityView> createState() => _SangongIdentityViewState();
}

class _SangongIdentityViewState extends State<SangongIdentityView> {
  SangongIdentityDirectory? _directory;
  SangongRuntime? _runtime;
  SangongOperationScope? _scope;
  SangongDisplayIdentity? _identity;
  SangongIdentitySession? _session;
  bool _invalid = false;
  int _request = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final runtime =
        context.dependOnInheritedWidgetOfExactType<SangongScope>()?.notifier;
    if (_scope != null &&
        (runtime == null ||
            !_scope!.matches(runtime.featureContext, runtime.http.tenantId))) {
      _invalid = true;
      _request++;
      _identity = null;
    }
    _runtime = runtime;
    _scope ??= runtime == null
        ? null
        : SangongOperationScope.capture(
            runtime.featureContext, runtime.http.tenantId);
    final directory = context
            .dependOnInheritedWidgetOfExactType<SangongIdentityScope>()
            ?.directory ??
        SangongIdentityDirectory.shared;
    if (_directory != directory || _session != directory.session) {
      _directory = directory;
      _load();
    }
  }

  @override
  void didUpdateWidget(SangongIdentityView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userID != widget.userID ||
        _directory?.peek(widget.userID) != _identity) {
      _load();
    }
  }

  bool get _current =>
      !_invalid &&
      (_runtime == null ||
          _scope!.matches(_runtime!.featureContext, _runtime!.http.tenantId));
  void _load() {
    final request = ++_request;
    _identity = _current ? _directory?.peek(widget.userID) : null;
    _session = _directory?.session;
    if (!_current || _directory == null) return;
    final id = widget.userID;
    final session = _session;
    unawaited(_directory!.resolve(id).then((value) {
      if (!mounted || request != _request || id != widget.userID || !_current) {
        return;
      }
      setState(() => _identity = session == _directory!.session ? value : null);
    }));
  }

  @override
  void dispose() {
    _request++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget
      .builder(_current && _session == _directory?.session ? _identity : null);
}

class SangongPublicAccount extends StatelessWidget {
  const SangongPublicAccount(
      {super.key, required this.userID, this.prefix = '账号：', this.style});
  final String userID, prefix;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) => SangongIdentityView(
      userID: userID,
      builder: (identity) => Text(
          '$prefix${identity?.account.isNotEmpty == true ? identity!.account : '未获取'}',
          style: style));
}

class SangongIMAvatar extends StatelessWidget {
  const SangongIMAvatar(
      {super.key, required this.userID, this.nickname = '', this.size = 44});
  final String userID, nickname;
  final double size;
  @override
  Widget build(BuildContext context) => SangongIdentityView(
      userID: userID,
      builder: (identity) => AvatarView(
          url: identity?.faceURL,
          text: sangongDisplayName(identity?.nickname ?? nickname, userID),
          width: size,
          height: size,
          isCircle: true,
          textStyle: const TextStyle(color: Colors.white, fontSize: 16)));
}

class SangongUserName extends StatelessWidget {
  const SangongUserName(
      {super.key, required this.userID, this.nickname = '', this.style});
  final String userID, nickname;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) => SangongIdentityView(
      userID: userID,
      builder: (identity) => Text(
          sangongDisplayName(
              nickname.isEmpty ? identity?.nickname ?? '' : nickname, userID),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: style));
}
