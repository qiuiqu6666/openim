import 'package:flutter/widgets.dart';

String mineText(BuildContext context, {required String zh, required String en}) =>
    Localizations.localeOf(context).languageCode == 'zh' ? zh : en;
