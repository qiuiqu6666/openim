# Local azlistview patch

Based on pub.dev azlistview 2.0.0; upstream license retained in LICENSE.
The app dependency override also applies to openim_common consumers.

The index bar uses `HapticFeedback.lightImpact()` instead of the upstream
generic `vibrate()`, matching the 99chat directory implementation. Existing
index-change deduplication and the hapticFeedback opt-out remain intact.
No list layout, scrolling, data, or visual behavior is changed.

Regression test: `flutter test test/widgets/directory/index_bar_haptics_test.dart`.
