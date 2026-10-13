import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../qr_scanner_labels.dart';
import '../gallery/qr_gallery_labels.dart';
import 'qr_content.dart';
import 'qr_content_actions.dart';
import 'qr_content_labels.dart';

Future<void> showQrContent(BuildContext context, String raw,
        {QrContentActions actions = const QrContentActions()}) =>
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) =>
            QrContentSheet(content: QrContent.parse(raw), actions: actions));

class QrContentSheet extends StatefulWidget {
  const QrContentSheet(
      {super.key,
      required this.content,
      this.actions = const QrContentActions()});
  final QrContent content;
  final QrContentActions actions;
  @override
  State<QrContentSheet> createState() => _QrContentSheetState();
}

class _QrContentSheetState extends State<QrContentSheet> {
  bool _busy = false;
  String? _notice;
  Future<void> _run(Future<void> Function() action,
      {bool copied = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      await action();
      if (mounted && copied) {
        setState(() => _notice = QrScannerLabels.of(context).copyDone);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _notice = QrScannerLabels.of(context).actionFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.content, labels = QrScannerLabels.of(context);
    return SafeArea(
        child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .8),
            child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(AppTokens.s4),
                children: [
                  Text(labels.titleFor(c.kind),
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: AppTokens.s3),
                  if (c.kind == QrContentKind.unknown) Text(labels.unknownHint),
                  if (c.kind == QrContentKind.wifi) ...[
                    Text(c.ssid!),
                    Text(labels.wifiHint)
                  ],
                  const SizedBox(height: AppTokens.s3),
                  SelectableText(c.raw, key: const ValueKey('qr-raw-text')),
                  const SizedBox(height: AppTokens.s4),
                  if (_notice != null)
                    Semantics(liveRegion: true, child: Text(_notice!)),
                  if (c.url != null)
                    FilledButton(
                        key: const ValueKey('qr-open-browser'),
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                  if (!await widget.actions
                                      .openBrowser(c.url!)) {
                                    throw StateError('unavailable');
                                  }
                                }),
                        child: Text(labels.openBrowser)),
                  if (c.kind == QrContentKind.wifi) ...[
                    OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _run(() => widget.actions.copy(c.ssid!),
                                copied: true),
                        child: Text(labels.copySsid)),
                    if (c.password?.isNotEmpty == true)
                      OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _run(
                                  () => widget.actions.copy(c.password!),
                                  copied: true),
                          child: Text(labels.copyPassword)),
                  ],
                  if (c.vcard != null)
                    Builder(
                        builder: (buttonContext) => FilledButton(
                            onPressed: _busy
                                ? null
                                : () => _run(() {
                                      final box = buttonContext
                                          .findRenderObject() as RenderBox;
                                      return widget.actions.exportContact(
                                          c.vcard!,
                                          box.localToGlobal(Offset.zero) &
                                              box.size);
                                    }),
                            child: Text(labels.saveContact))),
                  OutlinedButton(
                      key: const ValueKey('qr-copy-raw'),
                      onPressed: _busy
                          ? null
                          : () => _run(() => widget.actions.copy(c.raw),
                              copied: true),
                      child: Text(labels.copyRaw)),
                  TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(labels.cancelScan)),
                ])));
  }
}
