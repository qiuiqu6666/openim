import 'package:flutter/material.dart';

String paymentText(BuildContext context,
        {required String zh, required String en}) =>
    Localizations.localeOf(context).languageCode == 'zh' ? zh : en;
