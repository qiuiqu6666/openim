# Application alerts

The Cupertino alert previously used by `showSettingsConfirm` is shared here.
`showAppAlert<T>` returns the selected typed value (null for dismissal);
`showAppConfirm` treats dismissal as cancellation. `AppAlertDialog<T>` can also
be used with an existing route when a caller owns its lifecycle. Actions reuse
`AppAction` from the shared action-sheet module.

Use this for short messages, errors and confirmations on both Android and iOS.
Cupertino supplies dynamic light/dark colors, text scaling, scrolling and the
action separators. Destructive actions use `destructive: true`. Business code
must still recheck its session/permission after awaiting a selection.

Settings and legacy `CustomDialog` remain compatibility adapters. The design
matches the Cupertino alerts in 99chat's `lib/src/widgets/app_dialog.dart`.
Custom editors, conflict-review forms and recording controls remain separate.
