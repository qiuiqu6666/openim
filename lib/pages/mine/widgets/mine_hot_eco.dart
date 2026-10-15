import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import 'mine_profile_localization.dart';

const _assetPackage = 'openim_common';

class MineHotEcoSection extends StatelessWidget {
  static const imageProviders = <AssetImage>[
    AssetImage('assets/images/profile_eco_ai_99chat.webp',
        package: _assetPackage),
    AssetImage('assets/images/profile_eco_shop_99chat.webp',
        package: _assetPackage),
    AssetImage('assets/images/profile_eco_wallet_99chat.webp',
        package: _assetPackage),
    AssetImage('assets/images/profile_eco_community_99chat.webp',
        package: _assetPackage),
  ];

  const MineHotEcoSection({
    super.key,
    required this.primaryTextColor,
    required this.secondaryTextColor,
    required this.arrowColor,
    required this.dark,
    required this.onFeatureTap,
    this.onWalletTap,
    required this.onUnavailableFeatureTap,
  });

  final Color primaryTextColor;
  final Color secondaryTextColor;
  final Color arrowColor;
  final bool dark;
  final ValueChanged<String> onFeatureTap;
  final VoidCallback? onWalletTap;
  final ValueChanged<String> onUnavailableFeatureTap;

  @override
  Widget build(BuildContext context) {
    final items = [
      _MineHotEcoItem(
        title: mineText(context, zh: 'AI助手', en: 'AI Assistant'),
        assetName: 'profile_eco_ai_99chat.webp',
      ),
      _MineHotEcoItem(
        title: mineText(context, zh: '生活缴费', en: 'Utilities'),
        assetName: 'profile_eco_shop_99chat.webp',
        enabled: false,
      ),
      _MineHotEcoItem(
        title: mineText(context, zh: '数字资产', en: 'Digital Assets'),
        assetName: 'profile_eco_wallet_99chat.webp',
        opensWallet: true,
      ),
      _MineHotEcoItem(
        title: mineText(context, zh: '社区广场', en: 'Community'),
        assetName: 'profile_eco_community_99chat.webp',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final sectionWidth = constraints.maxWidth;
        final horizontalPadding = sectionWidth * 0.045;
        final tileGap = sectionWidth * 0.018;
        final columns = MediaQuery.textScalerOf(context).scale(1) > 1.3 ? 2 : 4;

        return Container(
          key: const ValueKey('mine-hot-eco-section'),
          color: Colors.transparent,
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            0,
            horizontalPadding,
            sectionWidth * 0.045,
          ),
          child: Column(
            children: [
              _buildHeading(context, sectionWidth),
              Wrap(
                key: const ValueKey('mine-hot-eco-tiles-row'),
                spacing: tileGap,
                runSpacing: AppTokens.s3,
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    SizedBox(
                      width: (sectionWidth -
                              horizontalPadding * 2 -
                              tileGap * (columns - 1)) /
                          columns,
                      child: _MineHotEcoTile(
                        item: items[i],
                        onTap: () {
                          final item = items[i];
                          if (item.opensWallet && onWalletTap != null) {
                            onWalletTap!();
                          } else if (item.enabled) {
                            onFeatureTap(item.title);
                          } else {
                            onUnavailableFeatureTap(item.title);
                          }
                        },
                        delay: Duration(milliseconds: i * 260),
                      ),
                    ),
                  ],
                ],
              ),
              SizedBox(height: sectionWidth * 0.010),
              Container(
                height: sectionWidth * 0.016,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      (dark
                              ? AppTokens.profileEcoGlowDark
                              : AppTokens.profileEcoGlowLight)
                          .withValues(alpha: dark ? 0.18 : 0.10),
                      (dark
                              ? AppTokens.profileEcoGlowDark
                              : AppTokens.profileEcoGlowLight)
                          .withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeading(BuildContext context, double width) {
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final title = Row(children: [
      Text('🔥', style: TextStyle(fontSize: width * 0.046)),
      const SizedBox(width: AppTokens.s3),
      Expanded(
          child: Text(
        mineText(context, zh: '热门生态', en: 'Popular Ecosystem'),
        maxLines: large ? 2 : 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            color: primaryTextColor,
            fontSize: width * 0.043,
            fontWeight: FontWeight.w600),
      )),
    ]);
    final status = Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s5, vertical: AppTokens.s3),
        child: Text(mineText(context, zh: '后续开放', en: 'Coming soon'),
            style: TextStyle(
                color: secondaryTextColor,
                fontSize: AppTokens.captionFontSize)));
    return ConstrainedBox(
      key: const ValueKey('mine-hot-eco-title-row'),
      constraints: const BoxConstraints(minHeight: AppTokens.minimumTapSize),
      child: large
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [title, status])
          : Row(children: [Expanded(child: title), status]),
    );
  }
}

class _MineHotEcoItem {
  const _MineHotEcoItem({
    required this.title,
    required this.assetName,
    this.enabled = true,
    this.opensWallet = false,
  });

  final String title;
  final String assetName;
  final bool enabled;
  final bool opensWallet;
}

class _MineHotEcoTile extends StatefulWidget {
  const _MineHotEcoTile({
    required this.item,
    required this.onTap,
    required this.delay,
  });

  final _MineHotEcoItem item;
  final VoidCallback onTap;
  final Duration delay;

  @override
  State<_MineHotEcoTile> createState() => _MineHotEcoTileState();
}

class _MineHotEcoTileState extends State<_MineHotEcoTile>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  late final CurvedAnimation _sweep;
  Timer? _delayTimer;
  bool _delayElapsed = false;
  bool _tickerModeEnabled = true;
  bool _reduceMotion = false;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycleState =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2100),
    );
    _sweep = CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic);
    _delayTimer = Timer(widget.delay, () {
      if (!mounted) return;
      _delayElapsed = true;
      _syncAnimationWork();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    _tickerModeEnabled = enabled;
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncAnimationWork();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    _syncAnimationWork();
  }

  void _syncAnimationWork() {
    if (!_delayElapsed || !mounted) return;
    final shouldRun = !_reduceMotion &&
        _tickerModeEnabled &&
        _lifecycleState == AppLifecycleState.resumed;
    if (!shouldRun) {
      _controller.stop();
      return;
    }
    if (!_controller.isAnimating && !_controller.isCompleted) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _sweep.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 0.78,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tileWidth = constraints.maxWidth;
            final radius = tileWidth * 0.12;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(radius),
                onTap: widget.item.enabled ? widget.onTap : null,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Transform.scale(
                        scale: 1.34,
                        child: Image.asset(
                          'assets/images/${widget.item.assetName}',
                          package: _assetPackage,
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                          gaplessPlayback: true,
                        ),
                      ),
                      if (!_reduceMotion && widget.item.enabled)
                        _MineHotEcoLightSweep(animation: _sweep),
                      Positioned(
                        left: tileWidth * 0.06,
                        bottom: tileWidth * 0.10,
                        right: tileWidth * 0.06,
                        child: Row(
                          children: [
                            Container(
                              width: tileWidth * 0.16,
                              height: tileWidth * 0.16,
                              decoration: BoxDecoration(
                                color:
                                    AppTokens.onAccent.withValues(alpha: 0.35),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppTokens.onAccent
                                      .withValues(alpha: 0.75),
                                  width: tileWidth * 0.0096,
                                ),
                              ),
                              child: Icon(
                                widget.item.enabled
                                    ? Icons.arrow_forward_rounded
                                    : Icons.lock_outline_rounded,
                                color: AppTokens.onAccent,
                                size: tileWidth * 0.1088,
                              ),
                            ),
                            SizedBox(width: tileWidth * 0.03),
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  widget.item.title,
                                  maxLines: 1,
                                  softWrap: false,
                                  style: TextStyle(
                                    color: AppTokens.onAccent,
                                    fontSize: tileWidth * 0.11,
                                    fontWeight: FontWeight.w700,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
}

class _MineHotEcoLightSweep extends StatelessWidget {
  const _MineHotEcoLightSweep({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final dx = -1.35 + animation.value * 2.7;
            return FractionalTranslation(
              translation: Offset(dx, 0),
              child: child,
            );
          },
          child: RepaintBoundary(
            child: Transform.rotate(
              angle: -0.32,
              child: Align(
                alignment: Alignment.center,
                child: FractionallySizedBox(
                  widthFactor: 0.42,
                  heightFactor: 1.45,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          AppTokens.onAccent.withValues(alpha: 0),
                          AppTokens.onAccent.withValues(alpha: 0.10),
                          AppTokens.onAccent.withValues(alpha: 0.34),
                          AppTokens.onAccent.withValues(alpha: 0.10),
                          AppTokens.onAccent.withValues(alpha: 0),
                        ],
                        stops: const [0, 0.28, 0.5, 0.72, 1],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
