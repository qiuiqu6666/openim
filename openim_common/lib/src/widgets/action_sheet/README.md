# Shared action sheet

`AppAction<T>` and `showAppActionSheet<T>` contain the application's existing
Cupertino choice sheet. This is the implementation previously in
`settings_widgets.dart`; settings keeps a type alias and thin function adapter.
The package does not import application pages.

Callers await the selected value before performing their operation. Cancel,
barrier dismissal and system back return `null`. An empty title is hidden;
disabled choices remain open, destructive choices use Cupertino's dynamic red,
and subtitles use its dynamic secondary label color. `selected` is exposed in
semantics without changing the existing visible layout.

The layout follows 99chat's `AppDialog.actionSheet` and `_ActionSheetLabel`
(Apache 2.0). Existing `BottomSheetView` serves legacy call and photo pickers;
it is not a second implementation of this API.

Focused regression tests are in
`test/widgets/action_sheet/app_action_sheet_test.dart` in the application.
