import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../custom_pop_up_menu.dart';
import '../../pop_button.dart';
import 'chat_message_menu_layout.dart';
import 'chat_message_menu_panel.dart';
import 'chat_message_menu_tokens.dart';

/// Chat-specific presentation; generic navigation popups keep their own style.
class ChatMessageMenu extends StatefulWidget {
  const ChatMessageMenu(
      {super.key,
      required this.menus,
      required this.child,
      required this.isOutgoing,
      this.controller});

  final List<PopMenuInfo> menus;
  final Widget child;
  final bool isOutgoing;
  final CustomPopupMenuController? controller;

  @override
  State<ChatMessageMenu> createState() => _ChatMessageMenuState();
}

class _ChatMessageMenuState extends State<ChatMessageMenu>
    with WidgetsBindingObserver {
  static _ChatMessageMenuState? _active;
  late CustomPopupMenuController _controller;
  RawDialogRoute<void>? _route;
  NavigatorState? _navigator;
  Offset? _touch;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _attachController();
  }

  void _attachController() {
    _controller = widget.controller ?? CustomPopupMenuController();
    _controller.addListener(_onChange);
  }

  @override
  void didUpdateWidget(ChatMessageMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _controller.removeListener(_onChange);
      _controller.hideMenu();
      _dismiss();
      if (oldWidget.controller == null) _controller.dispose();
      _attachController();
    }
    if (widget.menus.isEmpty) _controller.hideMenu();
  }

  void _onChange() {
    if (_disposed) return;
    if (_controller.menuIsShowing) {
      if (_route == null) _present();
    } else {
      _dismiss();
    }
  }

  void _present() {
    final render = context.findRenderObject();
    if (widget.menus.isEmpty || render is! RenderBox || !render.hasSize) {
      _controller.hideMenu();
      return;
    }
    _active?._controller.hideMenu();
    _active = this;
    final overlay = Overlay.of(context, rootOverlay: true);
    final box = overlay.context.findRenderObject() as RenderBox;
    final anchor =
        render.localToGlobal(Offset.zero, ancestor: box) & render.size;
    final origin = box.localToGlobal(Offset.zero);
    final touch = _touch == null ? null : _touch! - origin;
    final navigator = Navigator.of(context, rootNavigator: true);
    _navigator = navigator;
    final sourceOrder = {
      for (var index = 0; index < widget.menus.length; index++)
        widget.menus[index]: index
    };
    final menus = List<PopMenuInfo>.of(widget.menus)
      ..sort((first, next) {
        final rank = _compareActions(first, next);
        return rank != 0
            ? rank
            : sourceOrder[first]!.compareTo(sourceOrder[next]!);
      });
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final route = RawDialogRoute<void>(
      requestFocus: false,
      barrierDismissible: false,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Theme.of(context)
          .colorScheme
          .scrim
          .withValues(alpha: ChatMessageMenuTokens.scrimOpacity),
      transitionDuration: reducedMotion
          ? Duration.zero
          : ChatMessageMenuTokens.animationDuration,
      pageBuilder: (context, animation, _) => _MessageMenuOverlay(
        anchor: anchor,
        touch: touch,
        outgoing: widget.isOutgoing,
        menus: menus,
        animation: animation,
        onDismiss: _controller.hideMenu,
        onSelected: (menu) {
          _controller.hideMenu();
          HapticFeedback.selectionClick();
          menu.onTap?.call();
        },
      ),
      transitionBuilder: (_, __, ___, child) => child,
    );
    _route = route;
    unawaited(navigator.push(route).whenComplete(() {
      if (_route == route) {
        _route = null;
        _controller.hideMenu();
      }
      if (_active == this) _active = null;
    }));
  }

  static int _compareActions(PopMenuInfo first, PopMenuInfo next) {
    int rank(String? id) => switch (id) {
          'replyMessage' => 0,
          'copyMessage' => 1,
          'forwardMessage' => 2,
          'revoke' => 3,
          'voiceToText' => 4,
          'favorite_message' => 8,
          'add_to_stickers' => 9,
          'delete' => 100,
          'multiSelect' => 110,
          _ => 50,
        };
    return rank(first.id).compareTo(rank(next.id));
  }

  void _dismiss() {
    final route = _route;
    final navigator = _navigator;
    _route = null;
    if (_active == this) _active = null;
    if (route == null || navigator == null) return;
    void close() {
      if (!navigator.mounted || !route.isActive) return;
      if (route.isCurrent) {
        navigator.pop();
      } else {
        navigator.removeRoute(route);
      }
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => close());
    } else {
      close();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _controller.hideMenu();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onChange);
    _controller.hideMenu();
    _dismiss();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPressStart: (details) {
          _touch = details.globalPosition;
          _controller.showMenu();
        },
        child: widget.child,
      );
}

class _MessageMenuOverlay extends StatefulWidget {
  const _MessageMenuOverlay(
      {required this.anchor,
      required this.touch,
      required this.outgoing,
      required this.menus,
      required this.animation,
      required this.onDismiss,
      required this.onSelected});
  final Rect anchor;
  final Offset? touch;
  final bool outgoing;
  final List<PopMenuInfo> menus;
  final Animation<double> animation;
  final VoidCallback onDismiss;
  final ValueChanged<PopMenuInfo> onSelected;

  @override
  State<_MessageMenuOverlay> createState() => _MessageMenuOverlayState();
}

class _MessageMenuOverlayState extends State<_MessageMenuOverlay> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.isCurrentOf(context) == false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onDismiss();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final safeTop = math.min(constraints.maxHeight,
          media.padding.top + ChatMessageMenuTokens.edgePadding);
      final safeBottom = math.max(
          safeTop,
          constraints.maxHeight -
              math.max(media.padding.bottom, media.viewInsets.bottom) -
              ChatMessageMenuTokens.edgePadding);
      final layout = resolveChatMessageMenuLayout(
        anchor: widget.anchor,
        outgoing: widget.outgoing,
        viewport: constraints.biggest,
        safeTop: safeTop,
        safeBottom: safeBottom,
        desiredHeight:
            ChatMessageMenuPanel.preferredHeight(context, widget.menus),
        touch: widget.touch,
      );
      final opacity =
          widget.animation.drive(CurveTween(curve: Curves.easeOutCubic));
      final scale = Tween(begin: ChatMessageMenuTokens.scaleBegin, end: 1.0)
          .animate(opacity);
      return Stack(children: [
        Positioned.fill(
            child: GestureDetector(
          key: const ValueKey('chat-message-menu-dismiss'),
          behavior: HitTestBehavior.opaque,
          onTap: widget.onDismiss,
          child: const SizedBox.expand(),
        )),
        Positioned(
          left: layout.arrowLeft,
          top: layout.below
              ? layout.panel.top - ChatMessageMenuTokens.arrowHeight
              : layout.panel.bottom,
          child: IgnorePointer(
              child: FadeTransition(
            opacity: opacity,
            child: SizedBox(
              key: const ValueKey('chat-message-menu-arrow'),
              width: ChatMessageMenuTokens.arrowWidth,
              height: ChatMessageMenuTokens.arrowHeight,
              child: CustomPaint(painter: _MenuArrow(below: layout.below)),
            ),
          )),
        ),
        Positioned.fromRect(
          rect: layout.panel,
          child: FadeTransition(
            opacity: opacity,
            child: ScaleTransition(
              scale: scale,
              alignment: widget.outgoing
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: ChatMessageMenuPanel(
                  menus: widget.menus, onSelected: widget.onSelected),
            ),
          ),
        ),
      ]);
    });
  }
}

class _MenuArrow extends CustomPainter {
  const _MenuArrow({required this.below});
  final bool below;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (below) {
      path.moveTo(0, size.height);
      path.lineTo(size.width / 2, 0);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(0, 0);
      path.lineTo(size.width / 2, size.height);
      path.lineTo(size.width, 0);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = ChatMessageMenuTokens.background);
  }

  @override
  bool shouldRepaint(_MenuArrow oldDelegate) => oldDelegate.below != below;
}
