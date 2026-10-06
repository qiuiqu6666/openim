import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../res/app_tokens.dart';
import '../chat_location_picker_labels.dart';
import '../chat_location_picker_tokens.dart';

/// Keeps the Android map subtree unmounted until explicit consent is stored.
class ChatLocationAmapConsent extends StatefulWidget {
  const ChatLocationAmapConsent({super.key, required this.child});

  static const preferenceKey = 'chat_location_amap_privacy_v1';
  final Widget child;

  @override
  State<ChatLocationAmapConsent> createState() =>
      _ChatLocationAmapConsentState();
}

class _ChatLocationAmapConsentState extends State<ChatLocationAmapConsent> {
  bool _reading = true;
  bool _saving = false;
  bool _consented = false;
  bool _readFailed = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _readConsent();
  }

  Future<void> _readConsent() async {
    if (_saving) return;
    setState(() {
      _reading = true;
      _failed = false;
      _readFailed = false;
    });
    try {
      final preferences = await SharedPreferences.getInstance();
      // A rejected write can still alter the plugin cache; reread storage.
      await preferences.reload();
      final consented =
          preferences.getBool(ChatLocationAmapConsent.preferenceKey) == true;
      if (mounted) setState(() => _consented = consented);
    } catch (_) {
      if (mounted) {
        setState(() {
          _consented = false;
          _failed = true;
          _readFailed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _agree() async {
    if (_reading || _saving || _readFailed) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = await preferences.setBool(
          ChatLocationAmapConsent.preferenceKey, true);
      if (mounted) {
        setState(() {
          _consented = saved;
          _failed = !saved;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _consented = false;
          _failed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openPrivacy() async {
    try {
      final opened = await launchUrl(
        Uri.parse('https://lbs.amap.com/pages/privacy/'),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) setState(() => _failed = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_consented && !_reading) return widget.child;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final labels = ChatLocationPickerLabels.of(context);
    final secondary = AppTokens.textSecondary(dark: dark);
    final busy = _reading || _saving;
    return ColoredBox(
      key: const ValueKey('chat-location-amap-consent'),
      color: AppTokens.surfaceAlt(dark: dark),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTokens.s7),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
                maxWidth: ChatLocationPickerTokens.hintMaxWidth),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ExcludeSemantics(
                      child: Icon(Icons.map_outlined,
                          color: AppTokens.accent,
                          size: ChatLocationPickerTokens.emptyIconSize)),
                  const SizedBox(height: AppTokens.s5),
                  Text(labels.mapProviderTitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppTokens.textPrimary(dark: dark),
                          fontSize: ChatLocationPickerTokens.headingSize,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: AppTokens.s3),
                  Text(labels.mapPrivacyHint,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: secondary,
                          fontSize: ChatLocationPickerTokens.bodySize)),
                  TextButton(
                      key: const ValueKey('chat-location-amap-privacy-link'),
                      onPressed: busy ? null : _openPrivacy,
                      style: TextButton.styleFrom(
                          foregroundColor: AppTokens.accent,
                          minimumSize: const Size.fromHeight(
                              ChatLocationPickerTokens.touchSize)),
                      child: Text(labels.mapPrivacyLink)),
                  if (_failed) ...[
                    Text(labels.mapUnavailable,
                        key: const ValueKey('chat-location-amap-consent-error'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: AppTokens.paymentError(dark: dark),
                            fontSize: ChatLocationPickerTokens.captionSize)),
                    TextButton(
                        key: const ValueKey('chat-location-amap-consent-retry'),
                        onPressed: busy ? null : _readConsent,
                        style: TextButton.styleFrom(
                            foregroundColor: AppTokens.accent,
                            minimumSize: const Size.fromHeight(
                                ChatLocationPickerTokens.touchSize)),
                        child: Text(labels.retry)),
                  ],
                  const SizedBox(height: AppTokens.s3),
                  FilledButton(
                      key: const ValueKey('chat-location-amap-agree'),
                      onPressed: busy || _readFailed ? null : _agree,
                      style: FilledButton.styleFrom(
                          backgroundColor: AppTokens.accent,
                          foregroundColor: AppTokens.onAccent,
                          disabledBackgroundColor: AppTokens.border(dark: dark),
                          disabledForegroundColor: secondary,
                          minimumSize: const Size.fromHeight(
                              ChatLocationPickerTokens.touchSize),
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppTokens.s5, vertical: AppTokens.s4),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppTokens.rMd))),
                      child: busy
                          ? const SizedBox.square(
                              dimension:
                                  ChatLocationPickerTokens.controlIconSize,
                              child: CircularProgressIndicator(
                                  strokeWidth:
                                      ChatLocationPickerTokens.progressStroke,
                                  color: AppTokens.accent))
                          : Text(labels.mapPrivacyAgree)),
                ]),
          ),
        ),
      ),
    );
  }
}
