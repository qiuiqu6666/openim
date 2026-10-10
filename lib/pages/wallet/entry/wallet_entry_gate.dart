import 'package:flutter/material.dart';
import '../../../services/fund/diagnostics/wallet_load_log.dart';

import 'wallet_entry_coordinator.dart';
import 'wallet_entry_placeholder.dart';

/// Mount assets only after verification. Retain the same session's scroll and
/// controller while hidden, with tickers and wallet refreshes suspended.
class WalletEntryGate extends StatefulWidget {
  const WalletEntryGate(
      {super.key,
      required this.entry,
      required this.onRetry,
      required this.child});

  final WalletEntryCoordinator entry;
  final Future<void> Function() onRetry;
  final Widget child;

  @override
  State<WalletEntryGate> createState() => _WalletEntryGateState();
}

class _WalletEntryGateState extends State<WalletEntryGate> {
  int? _openedEpoch;

  @override
  void initState() {
    super.initState();
    WalletLoadLog.note('view', 'mounted', {'phase': widget.entry.phase.name});
  }

  @override
  void dispose() {
    WalletLoadLog.note('view', 'disposed', {'phase': widget.entry.phase.name});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.entry,
        builder: (context, _) {
          final entry = widget.entry;
          if (entry.isReady) _openedEpoch = entry.contentEpoch;
          return Stack(
            fit: StackFit.expand,
            children: [
              Visibility(
                visible: entry.isReady,
                maintainState: true,
                child: _openedEpoch == entry.contentEpoch
                    ? KeyedSubtree(
                        key: ValueKey(entry.contentEpoch), child: widget.child)
                    : const SizedBox.shrink(),
              ),
              if (!entry.isReady)
                WalletEntryPlaceholder(
                  phase: entry.phase,
                  message: entry.message,
                  onRetry: widget.onRetry,
                ),
            ],
          );
        },
      );
}
