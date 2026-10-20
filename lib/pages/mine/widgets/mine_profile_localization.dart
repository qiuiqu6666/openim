import 'package:flutter/widgets.dart';
import 'package:openim_common/localization.dart';

String mineText(BuildContext context,
        {required String zh, required String en}) =>
    Localizations.localeOf(context).languageCode == 'zh'
        ? AppCopy.text(zh, locale: Localizations.localeOf(context))
        : en;
