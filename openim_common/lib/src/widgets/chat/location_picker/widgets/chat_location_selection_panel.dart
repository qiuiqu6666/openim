import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../../../res/app_tokens.dart';
import '../chat_location_picker_labels.dart';
import '../chat_location_picker_tokens.dart';
import '../chat_location_places_controller.dart';
import '../data/chat_location_place.dart';
import '../data/chat_location_source.dart';

class ChatLocationSelectionPanel extends StatefulWidget {
  const ChatLocationSelectionPanel(
      {super.key,
      required this.description,
      required this.selected,
      required this.failure,
      required this.onRetry,
      required this.onSettings,
      required this.wide,
      required this.places,
      required this.onPlace,
      this.selectedPlace,
      this.isCurrent = false});
  final TextEditingController description;
  final LatLng? selected;
  final ChatLocationFailure? failure;
  final VoidCallback? onRetry, onSettings;
  final bool wide, isCurrent;
  final ChatLocationPlacesController places;
  final ChatLocationPlace? selectedPlace;
  final ValueChanged<ChatLocationPlace> onPlace;
  @override
  State<ChatLocationSelectionPanel> createState() =>
      _ChatLocationSelectionPanelState();
}

class _ChatLocationSelectionPanelState
    extends State<ChatLocationSelectionPanel> {
  bool _editing = false;
  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: widget.places.query);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final labels = ChatLocationPickerLabels.of(context);
    final secondary = AppTokens.textSecondary(dark: dark);
    final caption = TextStyle(
        color: secondary, fontSize: ChatLocationPickerTokens.captionSize);
    final places = widget.places;
    return Material(
      color: AppTokens.surface(dark: dark),
      borderRadius: const BorderRadius.vertical(
          top: Radius.circular(ChatLocationPickerTokens.panelRadius)),
      child: SafeArea(
        top: false,
        left: !widget.wide,
        child: ListView(
          key: const ValueKey('chat-location-details-scroll'),
          padding: const EdgeInsets.all(AppTokens.s5),
          children: [
            Center(
                child: Container(
                    width: ChatLocationPickerTokens.handleWidth,
                    height: ChatLocationPickerTokens.handleHeight,
                    decoration: BoxDecoration(
                        color: AppTokens.border(dark: dark),
                        borderRadius: BorderRadius.circular(AppTokens.rPill)))),
            const SizedBox(height: AppTokens.s4),
            if (places.search != null)
              TextField(
                key: const ValueKey('chat-location-search'),
                controller: _search,
                cursorColor: ChatLocationPickerTokens.accent,
                onChanged: (value) => places.update(text: value),
                textInputAction: TextInputAction.search,
                onTapOutside: (_) => FocusScope.of(context).unfocus(),
                decoration: InputDecoration(
                    hintText: labels.search,
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: AppTokens.surfaceAlt(dark: dark),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppTokens.rSm),
                        borderSide: BorderSide.none)),
              ),
            const SizedBox(height: AppTokens.s3),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                  widget.selectedPlace?.name ??
                      (widget.selected == null
                          ? labels.emptySelection
                          : widget.isCurrent
                              ? labels.current
                              : labels.selected),
                  key: const ValueKey('chat-location-selection'),
                  style: TextStyle(
                      color: AppTokens.textPrimary(dark: dark),
                      fontSize: ChatLocationPickerTokens.headingSize)),
              subtitle: Text(
                  widget.selected == null
                      ? labels.selectHint
                      : widget.selectedPlace?.address.isNotEmpty == true
                          ? widget.selectedPlace!.address
                          : labels.coordinates(widget.selected!),
                  key: const ValueKey('chat-location-coordinates'),
                  style: caption),
              trailing: widget.selected == null
                  ? null
                  : const Icon(Icons.check,
                      color: ChatLocationPickerTokens.accent),
            ),
            Divider(color: AppTokens.border(dark: dark)),
            if (widget.failure != null) ...[
              Text(labels.failure(widget.failure!),
                  key: const ValueKey('chat-location-error'),
                  style: caption.copyWith(
                      color: AppTokens.paymentError(dark: dark))),
              Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                      key: const ValueKey('chat-location-recovery'),
                      onPressed:
                          widget.failure == ChatLocationFailure.deniedForever ||
                                  widget.failure == ChatLocationFailure.disabled
                              ? widget.onSettings
                              : widget.onRetry,
                      child: Text(
                          widget.failure == ChatLocationFailure.deniedForever
                              ? labels.settings
                              : widget.failure == ChatLocationFailure.disabled
                                  ? labels.locationServices
                                  : labels.retry))),
            ],
            if (places.loading)
              const LinearProgressIndicator(
                  color: ChatLocationPickerTokens.accent),
            if (places.failed)
              TextButton(
                  key: const ValueKey('chat-location-search-retry'),
                  onPressed: () => places.update(),
                  child: Text(labels.searchFailed)),
            if (!places.loading &&
                !places.failed &&
                places.search != null &&
                places.places.isEmpty &&
                places.query.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppTokens.s5),
                  child: Text(labels.searchEmpty, style: caption)),
            for (final place in places.places) ...[
              ListTile(
                  key: ValueKey('chat-location-place-${place.id}'),
                  contentPadding: EdgeInsets.zero,
                  selected: place.id == widget.selectedPlace?.id,
                  selectedColor: ChatLocationPickerTokens.accent,
                  title: Text(place.name),
                  subtitle: Text(place.address, style: caption),
                  onTap: () => widget.onPlace(place)),
              Divider(
                  height: AppTokens.s2, color: AppTokens.border(dark: dark)),
            ],
            ListTile(
                key: const ValueKey('chat-location-edit-name'),
                contentPadding: EdgeInsets.zero,
                title: Text(labels.customName),
                trailing:
                    Icon(_editing ? Icons.expand_less : Icons.chevron_right),
                onTap: () => setState(() => _editing = !_editing)),
            if (_editing)
              TextField(
                  key: const ValueKey('chat-location-name'),
                  controller: widget.description,
                  cursorColor: ChatLocationPickerTokens.accent,
                  maxLength: ChatLocationPickerTokens.nameMaxLength,
                  textInputAction: TextInputAction.done,
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                  decoration: InputDecoration(
                      labelText: labels.name,
                      filled: true,
                      fillColor: AppTokens.surfaceAlt(dark: dark),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppTokens.rSm),
                          borderSide: BorderSide.none))),
          ],
        ),
      ),
    );
  }
}
