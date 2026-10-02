import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Future<T?> openSettingsPage<T>(BuildContext context, Widget page) {
  return Navigator.of(context).push<T>(
    CupertinoPageRoute<T>(builder: (_) => page),
  );
}
