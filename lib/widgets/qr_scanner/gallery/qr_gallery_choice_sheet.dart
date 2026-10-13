import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../qr_scanner_labels.dart';
import 'qr_gallery_labels.dart';
import 'qr_gallery_result.dart';

Future<QrGalleryCode?> chooseGalleryCode(
        BuildContext context, QrGalleryResult result) =>
    showModalBottomSheet<QrGalleryCode>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (context) {
          final labels = QrScannerLabels.of(context);
          return SafeArea(
              child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * .7),
                  child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(AppTokens.s4),
                      children: [
                        Text(labels.chooseCode,
                            style: Theme.of(context).textTheme.titleLarge),
                        if (result.partial)
                          Padding(
                              padding: const EdgeInsets.only(top: AppTokens.s3),
                              child: Text(labels.partialScan)),
                        for (var i = 0; i < result.codes.length; i++)
                          ListTile(
                              key: ValueKey('qr-choice-$i'),
                              leading: _Location(
                                  code: result.codes[i], result: result),
                              title: Text('QR ${i + 1}'),
                              subtitle: Text(
                                  _preview(result.codes[i].text, labels),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                              onTap: () =>
                                  Navigator.of(context).pop(result.codes[i])),
                        TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(labels.cancelScan)),
                      ])));
        });

String _preview(String text, QrScannerLabels labels) {
  if (text.startsWith('99chat-login:')) return labels.loginCode;
  final uri = Uri.tryParse(text);
  // Show destination host, never login query tokens or URL credentials.
  if (uri != null && uri.hasAuthority) return '${uri.scheme}://${uri.host}';
  return text
      .replaceAll(RegExp(r'[\x00-\x1f\x7f\u202a-\u202e\u2066-\u2069]'), ' ')
      .characters
      .take(80)
      .toString();
}

class _Location extends StatelessWidget {
  const _Location({required this.code, required this.result});
  final QrGalleryCode code;
  final QrGalleryResult result;
  @override
  Widget build(BuildContext context) {
    final center = code.bounds?.center;
    final alignment = center == null || result.width <= 0 || result.height <= 0
        ? Alignment.center
        : Alignment((center.dx / result.width * 2 - 1).clamp(-1, 1),
            (center.dy / result.height * 2 - 1).clamp(-1, 1));
    return Container(
        width: kMinInteractiveDimension,
        height: kMinInteractiveDimension,
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppTokens.s2)),
        padding: const EdgeInsets.all(AppTokens.s2),
        alignment: alignment,
        child: Icon(Icons.qr_code,
            color: Theme.of(context).colorScheme.onSurfaceVariant));
  }
}
