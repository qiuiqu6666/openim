import 'package:flutter/material.dart';

/// Ledger categories remain identifiable in both themes, alongside text labels.
class SangongAccountFlowColors {
  SangongAccountFlowColors(BuildContext context)
      : scheme = Theme.of(context).colorScheme,
        dark = Theme.of(context).brightness == Brightness.dark;
  final ColorScheme scheme;
  final bool dark;

  Color get credit => dark ? const Color(0xff80baff) : const Color(0xff1565c0);
  Color get debit => dark ? const Color(0xffff9393) : const Color(0xffb3261e);
  Color get rebate => dark ? const Color(0xff79d6a8) : const Color(0xff237347);
  Color get transferIn =>
      dark ? const Color(0xff6ddbd2) : const Color(0xff00796b);
  Color get transferOut =>
      dark ? const Color(0xffffbd80) : const Color(0xffa34d00);
  Color get reversal =>
      dark ? const Color(0xffd4a8ff) : const Color(0xff7b3fb0);

  Color forType(String type) => switch (type) {
        'admin_credit' || 'credit' => credit,
        'admin_debit' || 'debit' || 'bet_hold' => debit,
        'user_transfer_in' => transferIn,
        'user_transfer_out' => transferOut,
        'rebate_player' || 'rebate_agent_diff' => rebate,
        'rebate_player_void' || 'settle_void' => reversal,
        'bet_cancel' ||
        'bet_recall' ||
        'bet_void' ||
        'bet_restart' =>
          transferIn,
        'settle_win' || 'settle_banker' => credit,
        _ => scheme.onSurface,
      };
}
