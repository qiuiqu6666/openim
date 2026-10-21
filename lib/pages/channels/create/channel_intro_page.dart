import 'package:flutter/material.dart';
import '../presentation/channel_ui.dart';
import '../presentation/channel_intro_tokens.dart';
import '../presentation/channel_tokens.dart';
import 'package:openim_common/openim_common.dart';

/// Introduction to broadcast channels. The CTA continues into Community creation.
class ChannelIntroPage extends StatelessWidget {
  const ChannelIntroPage({super.key});

  static const _blue = ChannelIntroTokens.blue;
  static const _ink = ChannelIntroTokens.ink;
  static const _muted = ChannelIntroTokens.muted;

  String _t(BuildContext context, String zh, String en) =>
      channelText(context, zh, en);
  void _startCreating(BuildContext context) => Navigator.pop(context, true);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          dark ? AppTokens.backgroundDark : ChannelIntroTokens.background,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: dark
                ? [AppTokens.backgroundDark, AppTokens.surface(dark: true)]
                : [ChannelIntroTokens.gradientTop, Colors.white],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Navigation belongs to the sheet, not its scrolling artwork.
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: const ValueKey('channel-intro-back'),
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon:
                        const Icon(Icons.arrow_back_ios_new_rounded, size: 21),
                    label: Text(_t(context, '返回', 'Back')),
                    style: TextButton.styleFrom(
                      foregroundColor: MediaQuery.highContrastOf(context)
                          ? ChannelTokens.action(context)
                          : _blue,
                      minimumSize: const Size(88, 48),
                      visualDensity: VisualDensity.standard,
                      tapTargetSize: MaterialTapTargetSize.padded,
                      textStyle: TextStyle(
                        fontFamily:
                            Theme.of(context).textTheme.bodyMedium?.fontFamily,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: LayoutBuilder(builder: (context, constraints) {
                      final compact = constraints.maxHeight < 640;
                      final width = constraints.maxWidth;
                      final artworkSize =
                          (width - 24).clamp(0.0, 390.0).toDouble();
                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(height: compact ? 12 : 18),
                            Text.rich(
                              TextSpan(children: [
                                TextSpan(
                                    text: _t(context, '什么是', 'What is a ')),
                                TextSpan(
                                  text: _t(context, '频道？', 'channel?'),
                                  style: const TextStyle(color: _blue),
                                ),
                              ]),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? AppTokens.textPrimary(dark: true)
                                    : _ink,
                                fontSize: width < 370 ? 35 : 40,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _t(context, '频道是一个一对多的工具，可以将你的信息\n广播给无限的受众',
                                  'A channel broadcasts your content\nto an unlimited audience'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: dark
                                    ? AppTokens.textSecondary(dark: true)
                                    : _muted,
                                fontSize: 15,
                                height: 1.45,
                              ),
                            ),
                            SizedBox(height: compact ? 4 : 8),
                            SizedBox(
                              height: artworkSize * (compact ? .80 : .88),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Positioned.fill(
                                    child: DecoratedBox(
                                      decoration: const BoxDecoration(
                                        gradient: RadialGradient(
                                          colors: [
                                            ChannelIntroTokens.glowCenter,
                                            ChannelIntroTokens.glowEdge,
                                            ChannelIntroTokens.glowTransparent,
                                          ],
                                          stops: [0, .60, 1],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Image.asset(
                                    'assets/images/channel_intro_99chat.png',
                                    excludeFromSemantics: true,
                                    fit: BoxFit.contain,
                                    width: artworkSize,
                                    height: artworkSize,
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: compact ? 6 : 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _feature(
                                    context,
                                    Icons.image_rounded,
                                    ChannelIntroTokens.posts,
                                    ChannelIntroTokens.postsFill,
                                    '图文内容',
                                    '分享精彩瞬间',
                                    'Posts',
                                    'Share moments'),
                                _feature(
                                    context,
                                    Icons.play_arrow_rounded,
                                    ChannelIntroTokens.videos,
                                    ChannelIntroTokens.videosFill,
                                    '视频发布',
                                    '支持高清播放',
                                    'Videos',
                                    'Play in HD'),
                                _feature(
                                    context,
                                    Icons.people_alt_rounded,
                                    ChannelIntroTokens.subscribers,
                                    ChannelIntroTokens.subscribersFill,
                                    '无限订阅',
                                    '没有人数上限',
                                    'Subscribers',
                                    'No limit'),
                                _feature(
                                    context,
                                    Icons.bar_chart_rounded,
                                    ChannelIntroTokens.insights,
                                    ChannelIntroTokens.insightsFill,
                                    '数据统计',
                                    '了解内容表现',
                                    'Insights',
                                    'Track reach'),
                              ],
                            ),
                            SizedBox(height: compact ? 16 : 20),
                            SizedBox(
                              height: 52,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [
                                    ChannelIntroTokens.buttonStart,
                                    ChannelIntroTokens.buttonEnd,
                                  ]),
                                  borderRadius: BorderRadius.circular(15),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: ChannelIntroTokens.buttonShadow,
                                      blurRadius: 14,
                                      offset: Offset(0, 7),
                                    ),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    key: const ValueKey('channel-intro-create'),
                                    borderRadius: BorderRadius.circular(15),
                                    onTap: () => _startCreating(context),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            _t(context, '创建频道',
                                                'Create Channel'),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 18,
                                                fontWeight: FontWeight.w700),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        const Icon(Icons.arrow_forward_rounded,
                                            color: Colors.white, size: 25),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _feature(
      BuildContext context,
      IconData icon,
      Color iconColor,
      Color background,
      String zhTitle,
      String zhSubtitle,
      String enTitle,
      String enSubtitle) {
    return Expanded(
      child: Column(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: iconColor, size: 26),
        ),
        const SizedBox(height: 6),
        Text(_t(context, zhTitle, enTitle),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppTokens.textPrimary(dark: true)
                    : _ink,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(_t(context, zhSubtitle, enSubtitle),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _muted, fontSize: 10)),
      ]),
    );
  }
}
