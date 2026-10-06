import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openim_common/openim_common.dart';

import 'payment_strings.dart';
import 'payment_sheet_tokens.dart';

class TradePasswordKeyPad extends StatelessWidget {
  const TradePasswordKeyPad({
    super.key,
    required this.enabled,
    required this.onDigit,
    required this.onDelete,
    this.walletPayStyle = false,
  });

  final bool enabled;
  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;
  final bool walletPayStyle;

  static const keys = [
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '',
    '0',
    'del'
  ];

  @override
  Widget build(BuildContext context) {
    if (walletPayStyle) return _walletPayKeypad(context);
    final dark = (Theme.of(context).brightness == Brightness.dark);
    final keyHeight = (MediaQuery.sizeOf(context).height *
            TradePasswordTokens.keyHeightScreenRatio)
        .clamp(
      TradePasswordTokens.keyMinHeight,
      TradePasswordTokens.keyMaxHeight,
    );
    return ColoredBox(
      color: AppTokens.surfaceAlt(dark: dark),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: TradePasswordTokens.contentMaxWidth,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.s3),
            child: GridView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: keys.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisExtent: keyHeight,
                mainAxisSpacing: AppTokens.s3,
                crossAxisSpacing: AppTokens.s3,
              ),
              itemBuilder: (_, i) {
                final key = keys[i];
                final isDelete = key == 'del';
                final keyBackground = isDelete || key.isEmpty
                    ? AppTokens.border(dark: dark)
                    : AppTokens.surface(dark: dark);
                if (key.isEmpty) {
                  return ExcludeSemantics(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: keyBackground,
                        borderRadius: BorderRadius.circular(AppTokens.rSm),
                      ),
                    ),
                  );
                }
                final label = isDelete
                    ? paymentText(context, zh: '删除一位', en: 'Delete digit')
                    : key;
                final color = enabled
                    ? AppTokens.textPrimary(dark: dark)
                    : AppTokens.textSecondary(dark: dark);
                void activate() {
                  HapticFeedback.selectionClick();
                  isDelete ? onDelete() : onDigit(key);
                }

                return Semantics(
                  button: true,
                  enabled: enabled,
                  label: label,
                  onTap: enabled ? activate : null,
                  excludeSemantics: true,
                  child: Material(
                    key: ValueKey('trade-password-key-$key'),
                    color: keyBackground,
                    borderRadius: BorderRadius.circular(AppTokens.rSm),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: enabled ? activate : null,
                      child: Center(
                        child: isDelete
                            ? Icon(
                                Icons.backspace_outlined,
                                size: TradePasswordTokens.deleteIconSize,
                                color: color,
                              )
                            : Text(
                                key,
                                style: TextStyle(
                                  fontSize: TradePasswordTokens.digitFontSize,
                                  fontWeight: FontWeight.w400,
                                  color: color,
                                  height: 1,
                                ),
                              ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // Adapted from 99chat's PayPasswordPrompt._KeyPad (750 x 1624 design).
  // Setup keeps its existing layout; payment uses the reference's flat table.
  Widget _walletPayKeypad(BuildContext context) {
    final dark = (Theme.of(context).brightness == Brightness.dark);
    final line = AppTokens.border(dark: dark);
    final text = enabled
        ? AppTokens.textPrimary(dark: dark)
        : AppTokens.textSecondary(dark: dark);
    return Table(
      border: TableBorder(
          top: BorderSide(color: line, width: .5),
          horizontalInside: BorderSide(color: line, width: .5),
          verticalInside: BorderSide(color: line, width: .5)),
      children: [
        for (var row = 0; row < 4; row++)
          TableRow(children: [
            for (var column = 0; column < 3; column++)
              Builder(builder: (context) {
                final value = keys[row * 3 + column];
                final special = value.isEmpty || value == 'del';
                void activate() {
                  HapticFeedback.selectionClick();
                  value == 'del' ? onDelete() : onDigit(value);
                }

                return Semantics(
                  button: value.isNotEmpty,
                  enabled: enabled && value.isNotEmpty,
                  label: value == 'del'
                      ? paymentText(context, zh: '删除一位', en: 'Delete digit')
                      : value,
                  onTap: enabled && value.isNotEmpty ? activate : null,
                  excludeSemantics: true,
                  child: Material(
                    key: ValueKey('trade-password-key-$value'),
                    color: special
                        ? AppTokens.surfaceAlt(dark: dark)
                        : AppTokens.surface(dark: dark),
                    child: InkWell(
                      onTap: enabled && value.isNotEmpty ? activate : null,
                      child: SizedBox(
                        height: PaymentSheetTokens.keyRowHeight,
                        child: Center(
                          child: value == 'del'
                              ? Icon(Icons.backspace_rounded,
                                  size: 24, color: text)
                              : Text(value,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium!
                                      .copyWith(
                                          fontSize: PaymentSheetTokens.keyFont,
                                          color: text,
                                          fontWeight: FontWeight.w400)),
                        ),
                      ),
                    ),
                  ),
                );
              }),
          ]),
      ],
    );
  }
}
