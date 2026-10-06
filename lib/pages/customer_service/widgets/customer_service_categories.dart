// Adapted from 99chat's native customer-service category grid (Apache-2.0).
// Uses the existing OpenIM glass renderer and adaptive text/tap bounds.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../content/customer_service_content.dart';
import '../customer_service_tokens.dart';

/// Two rows of four category chips from the native 99chat support page.
class CustomerServiceCategories extends StatelessWidget {
  const CustomerServiceCategories({
    super.key,
    required this.selectedId,
    required this.onSelected,
  });

  final String selectedId;
  final ValueChanged<String> onSelected;

  /// Preserve both category rows when localized labels or large text wrap.
  static double preferredHeight(BuildContext context, double width) {
    final chipWidth = math.max(
        1.0,
        (width -
                    CustomerServiceTokens.categoryPadding.horizontal -
                    CustomerServiceTokens.categoryColumnGap * 3) /
                4 -
            CustomerServiceTokens.categoryChipPadding.horizontal);
    var height = CustomerServiceTokens.categoryPadding.vertical +
        CustomerServiceTokens.categoryRowGap;
    for (var row = 0; row < 2; row++) {
      var rowHeight = CustomerServiceTokens.tapMinHeight;
      for (var column = 0; column < 4; column++) {
        final painter = TextPainter(
          text: TextSpan(
              text: customerServiceCategories[row * 4 + column].title(context),
              style: DefaultTextStyle.of(context)
                  .style
                  .copyWith(fontSize: CustomerServiceTokens.chipFontSize)),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: chipWidth);
        final chipHeight = math.max(
            CustomerServiceTokens.chipMinHeight,
            painter.height +
                CustomerServiceTokens.categoryChipPadding.vertical);
        rowHeight = math.max(rowHeight,
            chipHeight + CustomerServiceTokens.categoryHitPadding.vertical);
        painter.dispose();
      }
      height += rowHeight;
    }
    return height;
  }

  @override
  Widget build(BuildContext context) => LiquidGlassSurface(
        tint: CustomerServiceTokens.blue,
        surface: NavigationGlassSurface.top,
        child: Padding(
          padding: CustomerServiceTokens.categoryPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var row = 0; row < 2; row++) ...[
                if (row > 0)
                  const SizedBox(height: CustomerServiceTokens.categoryRowGap),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var column = 0; column < 4; column++) ...[
                      if (column > 0)
                        const SizedBox(
                            width: CustomerServiceTokens.categoryColumnGap),
                      Expanded(
                        child: _chip(context,
                            customerServiceCategories[row * 4 + column]),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      );

  Widget _chip(BuildContext context, CustomerServiceCategory category) {
    final selected = selectedId == category.id;
    final label = category.title(context);
    const radius =
        BorderRadius.all(Radius.circular(CustomerServiceTokens.chipRadius));
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        key: ValueKey('customer-service-category-${category.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelected(category.id),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
              minHeight: CustomerServiceTokens.tapMinHeight),
          child: Padding(
            padding: CustomerServiceTokens.categoryHitPadding,
            // Keep the generous hit area outside the painted ink surface.
            child: Material(
              color: selected
                  ? CustomerServiceTokens.foreground
                  : CustomerServiceTokens.foreground.withValues(
                      alpha: CustomerServiceTokens.categoryInactiveOpacity),
              borderRadius: radius,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onSelected(category.id),
                borderRadius: radius,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                      minHeight: CustomerServiceTokens.chipMinHeight),
                  child: Padding(
                    padding: CustomerServiceTokens.categoryChipPadding,
                    child: Center(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        softWrap: true,
                        style: TextStyle(
                          color: selected
                              ? CustomerServiceTokens.blue
                              : CustomerServiceTokens.foreground,
                          fontSize: CustomerServiceTokens.chipFontSize,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
