import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/localization.dart';
import '../../../widgets/empty_state/illustrated_empty_state.dart';
import 'channel_tokens.dart';

String channelText(BuildContext context, String zh, String en) =>
    Localizations.localeOf(context).languageCode == 'zh'
        ? AppCopy.text(zh)
        : en;

class ChannelScaffold extends StatelessWidget {
  const ChannelScaffold(
      {super.key,
      required this.title,
      required this.body,
      this.actions = const [],
      this.whiteBackground = false,
      this.bottom,
      this.backLabel = false,
      this.onBack});
  final VoidCallback? onBack;
  final bool backLabel;
  final String title;
  final Widget body;
  final List<Widget> actions;
  final Widget? bottom;
  final bool whiteBackground;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);
    const minimum = Size(AppTokens.minimumTapSize, AppTokens.minimumTapSize);
    return Theme(
        data: theme.copyWith(
          filledButtonTheme: FilledButtonThemeData(
              style: (theme.filledButtonTheme.style ?? const ButtonStyle())
                  .copyWith(
                      backgroundColor:
                          WidgetStatePropertyAll(ChannelTokens.button(context)),
                      foregroundColor:
                          const WidgetStatePropertyAll(AppTokens.onAccent),
                      shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTokens.rSm))),
                      minimumSize: const WidgetStatePropertyAll(minimum))),
          textButtonTheme: TextButtonThemeData(
              style: (theme.textButtonTheme.style ?? const ButtonStyle())
                  .copyWith(
                      foregroundColor:
                          WidgetStatePropertyAll(ChannelTokens.action(context)),
                      minimumSize: const WidgetStatePropertyAll(minimum))),
        ),
        child: Scaffold(
          backgroundColor: whiteBackground
              ? AppTokens.surface(dark: dark)
              : ChannelTokens.background(context),
          appBar: AppBar(
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            leadingWidth: backLabel ? 96 : null,
            toolbarHeight: kToolbarHeight,
            backgroundColor: ChannelTokens.background(context),
            foregroundColor: AppTokens.textPrimary(dark: dark),
            leading: backLabel
                ? TextButton.icon(
                    onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                    icon:
                        const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
                    label: Text(channelText(context, '返回', 'Back')),
                    style: TextButton.styleFrom(
                        foregroundColor: ChannelTokens.action(context),
                        padding: EdgeInsets.zero),
                  )
                : IconButton(
                    tooltip:
                        MaterialLocalizations.of(context).backButtonTooltip,
                    onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.arrow_back_ios_new_rounded,
                        color: ChannelTokens.action(context))),
            title: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            centerTitle: true,
            actions: actions,
          ),
          body: SafeArea(
              top: false,
              child: Center(
                  child: ConstrainedBox(
                constraints: const BoxConstraints(
                    maxWidth: AppTokens.profileContentMaxWidth),
                child: SizedBox.expand(child: body),
              ))),
          bottomNavigationBar: bottom == null
              ? null
              : Padding(
                  padding: EdgeInsets.only(
                      bottom: MediaQuery.viewInsetsOf(context).bottom),
                  child: SafeArea(
                      child: Align(
                          heightFactor: 1,
                          child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                  maxWidth: AppTokens.profileContentMaxWidth),
                              child: Padding(
                                  padding: const EdgeInsets.all(AppTokens.s5),
                                  child: SizedBox(
                                      width: double.infinity,
                                      child: bottom)))))),
        ));
  }
}

class ChannelPreviewNotice extends StatelessWidget {
  const ChannelPreviewNotice({super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: ChannelTokens.pageInset, vertical: 6),
        child: Text(
            channelText(context, '页面预览 · 仅本次体验有效，不会发送给其他人',
                'Preview only · Changes last for this visit and are not sent to anyone'),
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center),
      );
}

class ChannelSection extends StatelessWidget {
  const ChannelSection(
      {super.key,
      required this.children,
      this.flat = false,
      this.separated = false});
  final List<Widget> children;
  final bool flat;
  final bool separated;
  @override
  Widget build(BuildContext context) => Card(
        margin: flat
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(
                horizontal: ChannelTokens.pageInset, vertical: 6),
        elevation: 0,
        color: AppTokens.surface(
            dark: Theme.of(context).brightness == Brightness.dark),
        shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(flat ? 0 : ChannelTokens.cardRadius)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0 && separated)
              Divider(
                  height: .5,
                  thickness: .5,
                  indent: AppTokens.s5,
                  endIndent: AppTokens.s5,
                  color: AppTokens.border(
                      dark: Theme.of(context).brightness == Brightness.dark)),
            children[i],
          ],
        ]),
      );
}

class ChannelEmpty extends StatelessWidget {
  const ChannelEmpty({super.key, required this.title, required this.message});
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) => IllustratedEmptyState(
      icon: Icons.campaign_outlined, title: title, description: message);
}

Future<T?> channelRoute<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

void channelUnavailable(BuildContext context) {
  showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
            title: Text(channelText(context, '暂未开放', 'Not available yet')),
            content: Text(channelText(context, '当前为页面预览。正式开放后即可使用此功能。',
                'This is a page preview. This action will be available when channels launch.')),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(channelText(context, '知道了', 'OK')))
            ],
          ));
}
