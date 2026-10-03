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
    required this.onWalletTap,
    required this.onUnavailableFeatureTap,
  });

  final Color primaryTextColor;
  final Color secondaryTextColor;
  final Color arrowColor;
  final bool dark;
  final ValueChanged<String> onFeatureTap;
  final VoidCallback onWalletTap;
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
              SizedBox(
                key: const ValueKey('mine-hot-eco-title-row'),
                height: sectionWidth * 0.11,
                child: Row(
                  children: [
                    Text('🔥',
                        style: TextStyle(fontSize: sectionWidth * 0.046)),
                    SizedBox(width: sectionWidth * 0.018),
                    Expanded(
                      child: Text(
                        mineText(
                          context,
                          zh: '热门生态',
                          en: 'Popular Ecosystem',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: primaryTextColor,
                          fontSize: sectionWidth * 0.043,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(sectionWidth * 0.04),
                      onTap: () => onFeatureTap(
                        mineText(
                          context,
                          zh: '热门生态',
                          en: 'Popular Ecosystem',
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: sectionWidth * 0.01,
                          vertical: sectionWidth * 0.014,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              mineText(context, zh: '查看更多', en: 'More'),
                              style: TextStyle(
                                color: secondaryTextColor,
                                fontSize: sectionWidth * 0.036,
                              ),
                            ),
                            SizedBox(width: sectionWidth * 0.004),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: arrowColor,
                              size: sectionWidth * 0.052,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                key: const ValueKey('mine-hot-eco-tiles-row'),
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) SizedBox(width: tileGap),
                    Expanded(
                      child: _MineHotEcoTile(
                        item: items[i],
                        onTap: () {
                          final item = items[i];
                          if (item.opensWallet) {
                            onWalletTap();
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
    final enabled =
        TickerMode.of(context) && (ModalRoute.of(context)?.isCurrent ?? true);
    if (_tickerModeEnabled == enabled) return;
    _tickerModeEnabled = enabled;
    _syncAnimationWork();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    _syncAnimationWork();
  }

  void _syncAnimationWork() {
    if (!_delayElapsed || !mounted) return;
    final shouldRun =
        _tickerModeEnabled && _lifecycleState == AppLifecycleState.resumed;
    if (!shouldRun) {
      _controller.stop();
      return;
    }
    if (!_controller.isAnimating) {
      _controller.repeat(period: const Duration(milliseconds: 3600));
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
                onTap: widget.onTap,
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
                                Icons.arrow_forward_rounded,
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
