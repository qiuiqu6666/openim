import 'package:flutter/material.dart';
import '../../../routes/swipe_back/app_page_route.dart';

Future<T?> openSettingsPage<T>(BuildContext context, Widget page,
    {String activityPage = 'settings'}) {
  return Navigator.of(context, rootNavigator: true).push<T>(
    AppMaterialPageRoute<T>(
        builder: (_) => page, settings: RouteSettings(name: '/$activityPage')),
  );
}
