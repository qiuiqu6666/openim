import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openim_common/openim_common.dart';

/// Matches 99chat lottery_dashboard.dart's _copyablePrediction format.
class MarkSixPredictionCopy extends StatelessWidget {
  const MarkSixPredictionCopy({
    super.key,
    required this.attribute,
    required this.label,
    required this.values,
    required this.child,
  });

  final String attribute;
  final String label;
  final List<String> values;
  final Widget child;

  Future<void> _copy(BuildContext context) async {
    final text = switch (attribute) {
      'special' || 'fiveElement' || 'zodiac' => values.join('.'),
      'head' => values.map((value) => '$value头').join(),
      'tail' => values.map((value) => '$value尾').join(),
      _ => values.join(' '),
    };
    String message;
    try {
      await Clipboard.setData(ClipboardData(text: text));
      message = '$label预测已复制';
    } catch (_) {
      message = '复制失败，请重试';
    }
    if (!context.mounted) return;
    IMViews.showToast(message);
  }

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return child;
    return Semantics(
      button: true,
      label: '复制$label预测',
      child: InkWell(
        onTap: () => _copy(context),
        onLongPress: () => _copy(context),
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(minHeight: kMinInteractiveDimension),
          child: child,
        ),
      ),
    );
  }
}
