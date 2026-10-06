import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/ai_palette.dart';
import '../../localization/ai_assistant_i18n.dart';

class AiFirstGuide extends StatefulWidget {
  const AiFirstGuide({
    super.key,
    required this.onFinished,
  });

  static const assets = <String>[
    'assets/ai/44.webp',
    'assets/ai/33.webp',
    'assets/ai/22.webp',
    'assets/ai/11.webp',
  ];

  final VoidCallback onFinished;

  @override
  State<AiFirstGuide> createState() => AiFirstGuideState();
}

class AiFirstGuideState extends State<AiFirstGuide> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isLast => _index >= AiFirstGuide.assets.length - 1;

  void _goNext() {
    if (_isLast) {
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpToPage(_index + 1);
      return;
    }
    unawaited(
      _controller.nextPage(
        duration: AiMetrics.guideAnimationDuration,
        curve: Curves.easeOut,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AiPalette.mask.withValues(alpha: 0.55),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: AiFirstGuide.assets.length,
                onPageChanged: (index) {
                  setState(() {
                    _index = index;
                  });
                },
                itemBuilder: (context, index) {
                  final last = index == AiFirstGuide.assets.length - 1;
                  return LayoutBuilder(builder: (context, constraints) {
                    final artMaxHeight =
                        (constraints.maxHeight - AiMetrics.guideControlsHeight)
                            .clamp(0.0, double.infinity);
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AiMetrics.space20),
                      child: Center(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: _goNext,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(
                                          AiMetrics.radius20),
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                            maxHeight: artMaxHeight),
                                        child: Image.asset(
                                          AiFirstGuide.assets[index],
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(
                                        height: AiMetrics.dimension12),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        for (var i = 0;
                                            i < AiFirstGuide.assets.length;
                                            i++)
                                          Container(
                                            width: i == _index
                                                ? AiMetrics.dimension16
                                                : AiMetrics.dimension6,
                                            height: AiMetrics.dimension6,
                                            margin: const EdgeInsets.symmetric(
                                              horizontal: AiMetrics.space3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: i == _index
                                                  ? AiPalette.onAccent
                                                  : AiPalette.onAccent
                                                      .withValues(alpha: 0.35),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      AiMetrics.radius3),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: AiMetrics.dimension20),
                              Visibility(
                                visible: last,
                                maintainSize: true,
                                maintainAnimation: true,
                                maintainState: true,
                                child: AiGuideStartButton(
                                  onPressed: widget.onFinished,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AiGuideStartButton extends StatelessWidget {
  const AiGuideStartButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final i18n = AiAssistantI18n.of(context);
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[AiPalette.guideStart, AiPalette.guideEnd],
          ),
          borderRadius: BorderRadius.all(Radius.circular(AiMetrics.radius28)),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(AiMetrics.radius28),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AiMetrics.space14),
              child: Text(
                i18n.t(
                  zhHans: '立即体验 →',
                  zhHant: '立即體驗 →',
                  en: 'Get started →',
                  ja: '今すぐ体験 →',
                  ko: '바로 체험 →',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AiPalette.onAccent,
                  fontSize: AiMetrics.font16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
