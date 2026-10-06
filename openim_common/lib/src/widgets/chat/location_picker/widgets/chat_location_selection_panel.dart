import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../../res/app_tokens.dart';
import '../chat_location_picker_labels.dart';
import '../chat_location_picker_tokens.dart';
import '../data/chat_location_source.dart';

/// Name entry and the chosen coordinate stay intact during device GPS reads.
class ChatLocationSelectionPanel extends StatelessWidget {
  const ChatLocationSelectionPanel(
      {super.key,
      required this.description,
      required this.selected,
      required this.failure,
      required this.onRetry,
      required this.onSettings,
      required this.onSend,
      required this.wide});

  final TextEditingController description;
  final LatLng? selected;
  final ChatLocationFailure? failure;
  final VoidCallback? onRetry, onSettings, onSend;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final labels = ChatLocationPickerLabels.of(context);
    final surface = AppTokens.surface(dark: dark);
    final text = AppTokens.textPrimary(dark: dark);
    final secondary = AppTokens.textSecondary(dark: dark);
    final field = AppTokens.surfaceAlt(dark: dark);
    final caption = TextStyle(
        color: secondary, fontSize: ChatLocationPickerTokens.captionSize);
    return DecoratedBox(
        decoration: BoxDecoration(
            color: surface,
            borderRadius: wide
                ? null
                : const BorderRadius.vertical(
                    top:
                        Radius.circular(ChatLocationPickerTokens.panelRadius))),
        child: SafeArea(
            top: false,
            left: !wide,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                  fit: FlexFit.loose,
                  child: SingleChildScrollView(
                      key: const ValueKey('chat-location-details-scroll'),
                      padding: const EdgeInsets.fromLTRB(
                          AppTokens.s5, AppTokens.s5, AppTokens.s5, 0),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(children: [
                              ExcludeSemantics(
                                  child: Container(
                                      width: ChatLocationPickerTokens
                                          .selectionBadgeSize,
                                      height: ChatLocationPickerTokens
                                          .selectionBadgeSize,
                                      decoration: BoxDecoration(
                                          color: field,
                                          borderRadius: BorderRadius.circular(
                                              AppTokens.rMd)),
                                      child: const Icon(
                                          Icons.location_on_outlined,
                                          color: AppTokens.accent,
                                          size: ChatLocationPickerTokens
                                              .controlIconSize))),
                              const SizedBox(width: AppTokens.s4),
                              Expanded(
                                  child: Text(
                                      selected == null
                                          ? labels.emptySelection
                                          : labels.selected,
                                      key: const ValueKey(
                                          'chat-location-selection'),
                                      style: TextStyle(
                                          color: text,
                                          fontSize: ChatLocationPickerTokens
                                              .headingSize,
                                          fontWeight: FontWeight.w600))),
                            ]),
                            const SizedBox(height: AppTokens.s3),
                            Text(
                                selected == null
                                    ? labels.selectHint
                                    : labels.coordinates(selected!),
                                key:
                                    const ValueKey('chat-location-coordinates'),
                                style: caption),
                            const SizedBox(height: AppTokens.s5),
                            TextField(
                                key: const ValueKey('chat-location-name'),
                                controller: description,
                                cursorColor: AppTokens.accent,
                                maxLength:
                                    ChatLocationPickerTokens.nameMaxLength,
                                textInputAction: TextInputAction.done,
                                onTapOutside: (_) =>
                                    FocusScope.of(context).unfocus(),
                                style: TextStyle(
                                    color: text,
                                    fontSize:
                                        ChatLocationPickerTokens.bodySize),
                                decoration: InputDecoration(
                                    labelText: labels.name,
                                    labelStyle: caption,
                                    counterStyle: caption,
                                    filled: true,
                                    fillColor: field,
                                    contentPadding:
                                        const EdgeInsets.all(AppTokens.s5),
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(
                                            AppTokens.rMd),
                                        borderSide: BorderSide.none),
                                    enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(
                                            AppTokens.rMd),
                                        borderSide: BorderSide.none),
                                    focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(
                                            AppTokens.rMd),
                                        borderSide: const BorderSide(
                                            color: AppTokens.accent)))),
                            if (failure != null) ...[
                              const SizedBox(height: AppTokens.s3),
                              Text(labels.failure(failure!),
                                  key: const ValueKey('chat-location-error'),
                                  style: caption.copyWith(
                                      color:
                                          AppTokens.paymentError(dark: dark))),
                              Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: TextButton(
                                      key: const ValueKey(
                                          'chat-location-recovery'),
                                      onPressed: failure ==
                                                  ChatLocationFailure
                                                      .deniedForever ||
                                              failure ==
                                                  ChatLocationFailure.disabled
                                          ? onSettings
                                          : onRetry,
                                      child: Text(failure ==
                                              ChatLocationFailure.deniedForever
                                          ? labels.settings
                                          : failure ==
                                                  ChatLocationFailure.disabled
                                              ? labels.locationServices
                                              : labels.retry))),
                            ],
                          ]))),
              Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppTokens.s5, AppTokens.s3, AppTokens.s5, AppTokens.s5),
                  child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                          key: const ValueKey('chat-location-send'),
                          onPressed: onSend,
                          style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(
                                  ChatLocationPickerTokens.touchSize),
                              backgroundColor: AppTokens.accent,
                              foregroundColor: AppTokens.onAccent,
                              disabledBackgroundColor:
                                  AppTokens.border(dark: dark),
                              disabledForegroundColor: secondary,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppTokens.s5,
                                  vertical: AppTokens.s4),
                              textStyle: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(
                                      fontSize:
                                          ChatLocationPickerTokens.bodySize,
                                      fontWeight: FontWeight.w600),
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppTokens.rMd))),
                          child: Text(labels.send)))),
            ])));
  }
}
