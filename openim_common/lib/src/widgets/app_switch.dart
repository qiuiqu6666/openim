import 'package:flutter/cupertino.dart';

import '../res/styles.dart';

/// Shared switch used by group management and friend permissions.
class AppSwitch extends StatelessWidget {
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => CupertinoSwitch(
        value: value,
        activeTrackColor: Styles.c_0089FF,
        onChanged: onChanged,
      );
}
