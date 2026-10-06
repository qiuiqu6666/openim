import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import '../../models/group_feature_context.dart';

/// Public discovery state for an already verified privileged account. No
/// private user data or business authorization is inferred from this state.
class SangongProfileEntryScope extends InheritedWidget {
  const SangongProfileEntryScope({
    super.key,
    required this.userID,
    required this.groups,
    required this.loading,
    required this.onRetry,
    required this.onSelectGroup,
    required super.child,
    this.selectedGroupID,
    this.error,
    this.onLedger,
    this.selectionContext,
    this.selectionChanges,
  });

  final String userID;
  final List<GroupInfo> groups;
  final String? selectedGroupID, error;
  final bool loading;
  final VoidCallback onRetry;
  final ValueChanged<String> onSelectGroup;
  final VoidCallback? onLedger;
  final GroupFeatureContext? selectionContext;
  final Listenable? selectionChanges;

  static SangongProfileEntryScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SangongProfileEntryScope>();

  @override
  bool updateShouldNotify(SangongProfileEntryScope oldWidget) =>
      userID != oldWidget.userID ||
      groups != oldWidget.groups ||
      selectedGroupID != oldWidget.selectedGroupID ||
      loading != oldWidget.loading ||
      error != oldWidget.error ||
      onLedger != oldWidget.onLedger ||
      onRetry != oldWidget.onRetry ||
      onSelectGroup != oldWidget.onSelectGroup ||
      selectionContext != oldWidget.selectionContext ||
      selectionChanges != oldWidget.selectionChanges;
}
