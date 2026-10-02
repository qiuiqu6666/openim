import 'dart:async';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../contacts/user_profile_panel/set_remark/set_remark_view.dart';

import '../settings_draft_store.dart';
import '../settings_service.dart';
import '../widgets/settings_widgets.dart';

class EditNicknamePage extends StatefulWidget {
  const EditNicknamePage({
    super.key,
    required this.initialNickname,
    required this.service,
    required this.store,
    this.avatarUrl = '',
    this.onChangeAvatar,
  });

  final String initialNickname;
  final SettingsService service;
  final SettingsDraftStore store;
  final String avatarUrl;
  final Future<void> Function()? onChangeAvatar;

  @override
  State<EditNicknamePage> createState() => _EditNicknamePageState();
}

class _EditNicknamePageState extends State<EditNicknamePage>
    with WidgetsBindingObserver {
  late final TextEditingController _controller;
  bool _saving = false;
  bool _changingAvatar = false;
  String? _error;
  int? _errorCode;
  Timer? _debounce;
  Timer? _unlockRefresh;
  int _checkVersion = 0;
  bool _checking = false;
  bool _checkFailed = false;
  NicknameCheckResult? _check;
  late String _lastText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNickname);
    _lastText = _controller.text;
    _controller.addListener(_onChanged);
    WidgetsBinding.instance.addObserver(this);
    if (widget.service.supportsNicknameCheck && _lastText.isNotEmpty) {
      unawaited(_checkNickname());
    }
  }

  void _onChanged() {
    if (_lastText == _controller.text) return;
    _lastText = _controller.text;
    _debounce?.cancel();
    _unlockRefresh?.cancel();
    _checkVersion++;
    final text = _controller.text;
    final valid = text.characters.length >= 2 && text.characters.length <= 22;
    setState(() {
      _error = null;
      _errorCode = null;
      _check = null;
      _checkFailed = false;
      _checking = widget.service.supportsNicknameCheck && valid;
    });
    if (_checking) {
      _debounce = Timer(
          const Duration(milliseconds: 350), () => unawaited(_checkNickname()));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !_saving &&
        widget.service.supportsNicknameCheck &&
        _controller.text.isNotEmpty) {
      _debounce?.cancel();
      unawaited(_checkNickname());
    }
  }

  Future<void> _checkNickname() async {
    final text = _controller.text;
    if (!widget.service.supportsNicknameCheck || text.isEmpty) return;
    final version = ++_checkVersion;
    _unlockRefresh?.cancel();
    setState(() {
      _checking = true;
      _checkFailed = false;
    });
    try {
      final result = await widget.service.checkNickname(text);
      if (!mounted || version != _checkVersion || text != _controller.text) {
        return;
      }
      setState(() {
        _check = result;
        _checking = false;
      });
      final wait =
          result.nextUpdateTime - DateTime.now().millisecondsSinceEpoch;
      if (wait > 0) {
        // Query again at expiry; only the server can confirm the latest limit.
        _unlockRefresh = Timer(
            Duration(milliseconds: wait), () => unawaited(_checkNickname()));
      }
    } catch (_) {
      if (!mounted || version != _checkVersion) return;
      setState(() {
        _checking = false;
        _check = null;
        _checkFailed = true;
      });
    }
  }

  String _checkMessage() {
    final editingName = _controller.text != widget.initialNickname;
    if (_checking) {
      return editingName
          ? settingsText(context, zh: '正在检查昵称…', en: 'Checking name…')
          : '';
    }
    if (_checkFailed) {
      return settingsText(context,
          zh: '暂时无法检查昵称，可重试或提交由服务器确认。',
          en: 'Unable to check. Retry or submit for server validation.');
    }
    final result = _check;
    if (result == null) return '';
    if (result.nextUpdateTime > DateTime.now().millisecondsSinceEpoch) {
      final date = DateTime.fromMillisecondsSinceEpoch(result.nextUpdateTime);
      String two(int n) => n.toString().padLeft(2, '0');
      final time =
          '${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}:${two(date.second)}';
      return settingsText(context,
          zh: '下次可修改时间：$time', en: 'Next change available: $time');
    }
    return result.occupied
        ? settingsText(context,
            zh: '昵称已被占用，请换一个昵称', en: 'This name is already taken.')
        : '';
  }

  String _footerMessage() {
    final hasLimit =
        (_check?.nextUpdateTime ?? 0) > DateTime.now().millisecondsSinceEpoch;
    if (_error != null && !(_errorCode == 20019 && hasLimit && !_checking)) {
      return _error!;
    }
    return _checkMessage();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _unlockRefresh?.cancel();
    _checkVersion++;
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving ||
        _changingAvatar ||
        _checking ||
        (_check?.occupied ?? false)) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    // The server compares original text, including case and surrounding spaces.
    final nickname = _controller.text;
    if (nickname.isEmpty) {
      showSettingsMessage(
        context,
        settingsText(context, zh: '昵称不能为空', en: 'Nickname cannot be empty'),
      );
      return;
    }
    if (nickname.characters.length < 2 || nickname.characters.length > 22) {
      showSettingsMessage(
        context,
        settingsText(context,
            zh: '名字长度为 2-22 个字符', en: 'Name must be 2-22 characters'),
      );
      return;
    }
    if (!widget.service.isProfileBackendAvailable) {
      showUnavailableSettingsAction(
        context,
        settingsText(context, zh: '修改名字', en: 'Edit name'),
      );
      return;
    }
    setState(() => _saving = true);
    _debounce?.cancel();
    _unlockRefresh?.cancel();
    _checkVersion++;
    try {
      await widget.service.updateNickname(nickname);
      if (!mounted) return;
      widget.store.setProfileNickname(nickname);
      Navigator.of(context).pop(nickname);
    } catch (error) {
      if (!mounted) return;
      var message = settingsText(context,
          zh: '保存失败，请检查网络后重试',
          en: 'Failed to save. Check your connection and try again.');
      if (error is (int, String?)) {
        final reason = HttpUtil.businessErrorMessage(ApiResp.fromJson({
          'errCode': error.$1,
          'errMsg': error.$2 ?? '',
          'errDlt': error.$2 ?? '',
        }));
        message = reason.isEmpty
            ? settingsText(context,
                zh: '保存失败（错误码：${error.$1}）',
                en: 'Failed to save (code: ${error.$1})')
            : reason;
      }
      setState(() {
        _error = message;
        _errorCode = error is (int, String?) ? error.$1 : null;
      });
      // Refresh a limit changed on another device, retaining the save error.
      if (widget.service.supportsNicknameCheck) unawaited(_checkNickname());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changeAvatar() async {
    if (_saving || _changingAvatar || widget.onChangeAvatar == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _changingAvatar = true);
    try {
      await widget.onChangeAvatar!();
    } finally {
      if (mounted) setState(() => _changingAvatar = false);
    }
  }

  @override
  Widget build(BuildContext context) => SetFriendRemarkPage.editor(
        controller: _controller,
        avatarURL: widget.avatarUrl,
        avatarName: widget.initialNickname,
        avatarBytes: widget.store.profileAvatarPreviewBytes,
        maxLength: 22,
        saving: _saving || _changingAvatar,
        onAvatarTap: _saving || _changingAvatar || widget.onChangeAvatar == null
            ? null
            : _changeAvatar,
        onSave: _save,
        saveEnabled: !_checking && !(_check?.occupied ?? false),
        inputStatus: !_checking &&
                !_checkFailed &&
                _error == null &&
                _check != null &&
                !_check!.occupied &&
                _controller.text != widget.initialNickname
            ? Icon(Icons.check_rounded,
                color: AppTokens.success,
                size: AppTokens.s5,
                semanticLabel:
                    settingsText(context, zh: '昵称可用', en: 'Name available'))
            : null,
        footer: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(
              AppTokens.s4, AppTokens.s3, AppTokens.s4, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_footerMessage().isNotEmpty)
                Text(_footerMessage(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: (_error != null && _footerMessage() == _error) ||
                                (_check?.occupied ?? false)
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.onSurfaceVariant)),
              if (_checkFailed)
                TextButton(
                    onPressed: _saving ? null : _checkNickname,
                    child: Text(
                        settingsText(context, zh: '重新检查', en: 'Retry check'))),
            ],
          ),
        ),
      );
}
