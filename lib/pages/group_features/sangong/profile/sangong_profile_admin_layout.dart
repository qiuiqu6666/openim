// Adapted from 99chat d7c3c65, Apache-2.0. See ../LICENSE-99chat.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openim_common/openim_common.dart';
import 'sangong_profile_admin_tokens.dart';

/// The three compact profile forms share their layout with unbound states.
/// Values and actions are supplied by the separately authorized business panel.
class SangongProfileAdminLayout extends StatelessWidget {
  const SangongProfileAdminLayout({
    super.key,
    required this.pointsController,
    required this.bankerController,
    required this.jointController,
    required this.loading,
    required this.disabled,
    this.embedded = false,
    this.points,
    this.parentLabel = '',
    this.rebatePer10000,
    this.bankerSummary,
    this.sharePercent,
    this.coBankSummary,
    this.error,
    this.onRetry,
    this.onCredit,
    this.onDebit,
    this.onAssignBanker,
    this.onSetLimit,
    this.onSendBanker,
    this.onSetCoBank,
    this.onRemoveCoBank,
    this.onSendCoBank,
  });

  final TextEditingController pointsController,
      bankerController,
      jointController;
  final bool loading, disabled, embedded;
  final int? points;
  final String parentLabel;
  final num? rebatePer10000;
  final String? bankerSummary, coBankSummary, error;
  final double? sharePercent;
  final VoidCallback? onRetry,
      onCredit,
      onDebit,
      onAssignBanker,
      onSetLimit,
      onSendBanker,
      onSetCoBank,
      onRemoveCoBank,
      onSendCoBank;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = AppTokens.accent;
    final body = AppTokens.textPrimary(dark: dark);
    final muted = AppTokens.textSecondary(dark: dark);
    final border = AppTokens.border(dark: dark);
    final skeleton = border.withValues(alpha: dark ? .55 : .85);
    final pointsText = '当前积分 ${points ?? '—'}'
        '${parentLabel.isNotEmpty ? ' · 上级 $parentLabel' : ''}'
        '${rebatePer10000 == null ? '' : ' · 返水 ${rebatePer10000!.toStringAsFixed(0)}'}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null && !loading)
          Padding(
            padding: EdgeInsets.fromLTRB(embedded ? 12 : 16, 0, 12, 0),
            child: Column(children: [
              Text(error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: muted,
                      fontSize: SangongProfileAdminTokens.captionSize)),
              Align(
                  alignment: Alignment.center,
                  child:
                      TextButton(onPressed: onRetry, child: const Text('重试'))),
            ]),
          ),
        _section(
            dark,
            _block(context,
                caption: _caption(pointsText, primary, skeleton, spans: [
                  TextSpan(text: '当前积分 '),
                  TextSpan(
                      text: '${points ?? '—'}',
                      style: TextStyle(
                          color: points == null
                              ? primary
                              : AppTokens.walletDanger)),
                  if (parentLabel.isNotEmpty)
                    TextSpan(text: ' · 上级 $parentLabel'),
                  if (rebatePer10000 != null)
                    TextSpan(
                        text: ' · 返水 ${rebatePer10000!.toStringAsFixed(0)}'),
                ]),
                input: _input(context, pointsController, '金额', dark),
                actions: [
                  _ProfileAction('上分', primary, disabled ? null : onCredit),
                  _ProfileAction('下分', primary, disabled ? null : onDebit),
                ],
                muted: muted)),
        _section(
            dark,
            _block(context,
                caption: _caption(bankerSummary ?? '庄 —', body, skeleton),
                input: _input(context, bankerController, '庄门.限额', dark,
                    banker: true),
                actions: [
                  _ProfileAction(
                      '定庄', primary, disabled ? null : onAssignBanker),
                  _ProfileAction('限额', primary, disabled ? null : onSetLimit),
                  _ProfileAction('发送', primary, disabled ? null : onSendBanker),
                ],
                muted: muted)),
        _section(
            dark,
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _block(context,
                  caption: _caption(
                      '合庄占股 ${sharePercent == null ? '—' : '${sharePercent!.toStringAsFixed(2)}%'}',
                      body,
                      skeleton),
                  input:
                      _input(context, jointController, '金额', dark, last: true),
                  actions: [
                    _ProfileAction('设置', muted, disabled ? null : onSetCoBank),
                    _ProfileAction(
                        '取消合庄', primary, disabled ? null : onRemoveCoBank),
                    _ProfileAction(
                        '发送', primary, disabled ? null : onSendCoBank),
                  ],
                  muted: muted),
              const SizedBox(height: AppTokens.s3),
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                child: SizedBox(
                    height: SangongProfileAdminTokens.summaryHeight,
                    child: _switch(
                        loading
                            ? _skeleton(
                                skeleton, const ValueKey('summary-skeleton'))
                            : Text(coBankSummary ?? '庄池：— · 合庄庄家：—',
                                key: ValueKey(coBankSummary),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: primary,
                                    fontSize:
                                        SangongProfileAdminTokens.captionSize,
                                    height: 1.3)),
                        Alignment.topLeft)),
              ),
            ])),
      ],
    );
  }

  Widget _section(bool dark, Widget child) => Padding(
      padding: SangongProfileAdminTokens.sectionMargin(embedded),
      child: DecoratedBox(
          decoration: BoxDecoration(
              color: AppTokens.surface(dark: dark),
              borderRadius: BorderRadius.circular(
                  SangongProfileAdminTokens.sectionRadius),
              border: Border.all(
                  color: AppTokens.border(dark: dark)
                      .withValues(alpha: dark ? .55 : .65),
                  width: SangongProfileAdminTokens.sectionBorderWidth),
              boxShadow: embedded
                  ? const [SangongProfileAdminTokens.embeddedShadow]
                  : null),
          child: Padding(
              padding: SangongProfileAdminTokens.sectionInset, child: child)));

  Widget _caption(String text, Color color, Color skeleton,
          {List<InlineSpan>? spans}) =>
      SizedBox(
          height: SangongProfileAdminTokens.captionHeight,
          width: double.infinity,
          child: _switch(
              loading
                  ? _skeleton(skeleton, const ValueKey('caption-skeleton'))
                  : Align(
                      key: ValueKey(text),
                      alignment: Alignment.centerLeft,
                      child: Text.rich(
                          TextSpan(children: spans ?? [TextSpan(text: text)]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: color,
                              fontSize: SangongProfileAdminTokens.captionSize,
                              fontWeight: FontWeight.w600,
                              height: 1.2))),
              Alignment.centerLeft));

  Widget _skeleton(Color color, Key key) => Container(
      key: key,
      height: 15,
      width: double.infinity,
      decoration: BoxDecoration(
          color: color, borderRadius: BorderRadius.circular(7.5)));

  Widget _switch(Widget child, Alignment alignment) => AnimatedSwitcher(
      duration: SangongProfileAdminTokens.transition,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) => Stack(
          alignment: alignment,
          fit: StackFit.expand,
          children: [...previous, if (current != null) current]),
      child: child);

  Widget _block(BuildContext context,
          {required Widget caption,
          required Widget input,
          required List<_ProfileAction> actions,
          required Color muted}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        caption,
        const SizedBox(height: AppTokens.s2),
        Row(children: [
          Expanded(child: input),
          const SizedBox(width: 10),
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0)
                Container(
                    width: 1,
                    height: 16,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    color: muted.withValues(alpha: .35)),
              InkWell(
                  onTap: actions[i].onPressed,
                  borderRadius: BorderRadius.circular(
                      SangongProfileAdminTokens.inputRadius),
                  child: Padding(
                      padding: SangongProfileAdminTokens.actionInset,
                      child: Text(actions[i].label,
                          style: TextStyle(
                              color: actions[i].onPressed == null
                                  ? muted.withValues(alpha: .45)
                                  : actions[i].color,
                              fontSize: SangongProfileAdminTokens.captionSize,
                              fontWeight: FontWeight.w600,
                              height: 1)))),
            ],
          ]),
        ]),
      ]);

  Widget _input(BuildContext context, TextEditingController controller,
      String hint, bool dark,
      {bool banker = false, bool last = false}) {
    final outline = OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(SangongProfileAdminTokens.inputRadius),
        borderSide: BorderSide(color: AppTokens.border(dark: dark)));
    return TextField(
        controller: controller,
        enabled: !disabled,
        textAlign: TextAlign.right,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: last ? TextInputAction.done : TextInputAction.next,
        scrollPadding: const EdgeInsets.only(bottom: 120),
        enableSuggestions: false,
        autocorrect: false,
        inputFormatters: [
          banker
              ? FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
              : FilteringTextInputFormatter.digitsOnly
        ],
        onSubmitted: (_) => last
            ? FocusManager.instance.primaryFocus?.unfocus()
            : FocusScope.of(context).nextFocus(),
        style: TextStyle(
            color: AppTokens.textPrimary(dark: dark),
            fontSize: SangongProfileAdminTokens.inputSize,
            fontWeight: FontWeight.w600),
        decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
                color: AppTokens.textSecondary(dark: dark),
                fontSize: SangongProfileAdminTokens.hintSize,
                fontWeight: FontWeight.w400),
            isDense: true,
            contentPadding: SangongProfileAdminTokens.inputInset,
            filled: true,
            fillColor: SangongProfileAdminTokens.inputFill(dark),
            border: outline,
            enabledBorder: outline,
            disabledBorder: outline,
            focusedBorder: outline.copyWith(
                borderSide: const BorderSide(color: AppTokens.accent))));
  }
}

class _ProfileAction {
  const _ProfileAction(this.label, this.color, this.onPressed);
  final String label;
  final Color color;
  final VoidCallback? onPressed;
}
