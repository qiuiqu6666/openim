# Platform accessibility scope

`AppAccessibilityScope` retains the platform text scaler and merges iOS Reduce
Motion into the inherited `disableAnimations` flag. Existing motion widgets can
consume one flag without adding independent platform listeners. Pages still
own their responsive layout; this scope never clamps the user's font setting.

Regression coverage: `test/widgets/accessibility/app_accessibility_scope_test.dart`
in the main application package.
