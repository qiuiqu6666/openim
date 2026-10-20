import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'media_image_recognition.dart';

/// Owns one scan per open menu; late results never update a closed menu.
class MediaRecognitionSection extends StatefulWidget {
  const MediaRecognitionSection(
      {super.key,
      required this.start,
      required this.onSelected,
      required this.actionsBuilder,
      required this.tileBuilder});
  final Widget Function(List<Widget> copyActions) actionsBuilder;
  final MediaRecognitionRequest Function() start;
  final void Function(MediaRecognitionTarget target, bool open) onSelected;
  final Widget Function(String label, Widget icon, VoidCallback onTap)
      tileBuilder;
  @override
  State<MediaRecognitionSection> createState() =>
      _MediaRecognitionSectionState();
}

class _MediaRecognitionSectionState extends State<MediaRecognitionSection> {
  late final MediaRecognitionRequest _request = widget.start();
  @override
  void dispose() {
    _request.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return FutureBuilder<MediaRecognitionResult>(
      future: _request.result,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return widget.actionsBuilder(const []);
        }
        final result = snapshot.data;
        final targets = result?.targets ?? const <MediaRecognitionTarget>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            widget.actionsBuilder([
              for (var i = 0; i < targets.length; i++)
                widget.tileBuilder(
                  targets.length == 1
                      ? targets[i].copyLabel
                      : '${targets[i].copyLabel} ${i + 1}',
                  Icon(Icons.link_rounded,
                      color: AppTokens.textPrimary(dark: dark),
                      size: AppTokens.s6),
                  () => widget.onSelected(targets[i], false),
                ),
            ]),
            if (targets.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
                child: Column(children: [
                  Divider(
                      height: AppTokens.s8,
                      color: AppTokens.border(dark: dark)),
                  for (var i = 0; i < targets.length; i++) ...[
                    if (i > 0) const SizedBox(height: AppTokens.s3),
                    Material(
                      color: Color.alphaBlend(
                          AppTokens.accent.withValues(alpha: dark ? .12 : .05),
                          AppTokens.surface(dark: dark)),
                      borderRadius: BorderRadius.circular(AppTokens.rMd),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => widget.onSelected(
                            targets[i], targets[i].open != null),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                              minHeight: AppTokens.minimumTapSize),
                          child: Padding(
                            padding: const EdgeInsets.all(AppTokens.s4),
                            child: Row(children: [
                              Expanded(
                                  child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(targets[i].openLabel ?? targets[i].title,
                                      style: TextStyle(
                                          fontSize: AppTokens.secondaryFontSize,
                                          color: AppTokens.textPrimary(
                                              dark: dark))),
                                  // Disambiguate multiple codes without exposing
                                  // long payloads in the normal single-code menu.
                                  if (targets.length > 1)
                                    Text(targets[i].value,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: AppTokens.textSecondary(
                                                dark: dark))),
                                ],
                              )),
                              const SizedBox(width: AppTokens.s3),
                              const Icon(Icons.chevron_right_rounded,
                                  color: AppTokens.accent),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppTokens.s4),
                ]),
              ),
          ],
        );
      },
    );
  }
}
