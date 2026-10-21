import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openim_common/openim_common.dart';
import 'package:persistent_bottom_nav_bar_v2/persistent_bottom_nav_bar_v2.dart';

import '../home_navigation_tokens.dart';

/// The native view owns only the bar. Flutter owns selection and page state.
class IOSHomeTabBar extends StatefulWidget {
  const IOSHomeTabBar({
    super.key,
    required this.config,
    required this.unreadCounts,
    required this.onItemSelected,
    required this.onUnavailable,
  });

  final NavBarConfig config;
  final List<int> unreadCounts;
  final ValueChanged<int> onItemSelected;
  final VoidCallback onUnavailable;

  @override
  State<IOSHomeTabBar> createState() => _IOSHomeTabBarState();
}

class _IOSHomeTabBarState extends State<IOSHomeTabBar> {
  MethodChannel? _channel;
  bool _updateScheduled = false;
  bool _failed = false;
  String? _lastConfiguration;

  // Keep the existing 99chat artwork; UIKit applies template tint and layout.
  static const _assets = [
    ['nav_chat_99chat.png', 'nav_chat_active_99chat.png'],
    ['nav_group_conv_99chat.png', 'nav_group_conv_99chat.png'],
    ['nav_contact_99chat.png', 'nav_contact_active_99chat.png'],
    ['assets/wallet.png', 'assets/wallet.png'],
    ['nav_profile_99chat.png', 'nav_profile_active_99chat.png'],
  ];

  String _asset(int index, int variant) => index == 3
      ? _assets[index][variant]
      : 'packages/openim_common/assets/images/${_assets[index][variant]}';

  Map<String, Object> _configuration(BuildContext context) => {
        'selectedIndex': widget.config.selectedIndex,
        'dark': Theme.of(context).brightness == Brightness.dark,
        'accent': AppTokens.accent.toARGB32(),
        'inactive': AppTokens.textSecondary(
          dark: Theme.of(context).brightness == Brightness.dark,
        ).toARGB32(),
        'rtl': Directionality.of(context) == TextDirection.rtl,
        'iconSize': HomeNavigationTokens.iconSize,
        'items': [
          for (var index = 0; index < widget.config.items.length; index++)
            {
              'title': widget.config.items[index].title ?? '',
              'icon': _asset(index, 0),
              'selectedIcon': _asset(index, 1),
              'badge': widget.unreadCounts[index] <= 0
                  ? ''
                  : widget.unreadCounts[index] > 99
                      ? '99+'
                      : '${widget.unreadCounts[index]}',
            },
        ],
      };

  void _created(int id) {
    if (!mounted) return;
    _channel = MethodChannel('openim/home-navigation/$id')
      ..setMethodCallHandler((call) async {
        if (!mounted || _failed || call.method != 'select') return;
        final index = call.arguments;
        if (index is int && index >= 0 && index < widget.config.items.length) {
          widget.onItemSelected(index);
        }
      });
    unawaited(_update());
  }

  Future<void> _update() async {
    if (!mounted || _failed || _channel == null) return;
    final configuration = _configuration(context);
    final signature = jsonEncode(configuration);
    if (signature == _lastConfiguration) return;
    _lastConfiguration = signature;
    try {
      await _channel!.invokeMethod<void>('update', configuration);
    } on PlatformException catch (error) {
      debugPrint('Native home navigation update failed: ${error.code}');
      _unavailable();
    } on MissingPluginException {
      _unavailable();
    }
  }

  void _unavailable() {
    if (!mounted || _failed) return;
    _failed = true;
    widget.onUnavailable();
  }

  void _scheduleUpdate() {
    if (_updateScheduled) return;
    _updateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScheduled = false;
      unawaited(_update());
    });
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleUpdate();
    return AppSystemBars(
      background: Theme.of(context).scaffoldBackgroundColor,
      child: SizedBox(
        height:
            HomeNavigationTokens.height + MediaQuery.paddingOf(context).bottom,
        child: UiKitView(
          viewType: 'openim/home-tab-bar',
          creationParams: _configuration(context),
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _created,
        ),
      ),
    );
  }
}
