import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'splash_logic.dart';
import 'widgets/splash_artwork.dart';

class SplashPage extends StatelessWidget {
  final logic = Get.find<SplashLogic>();

  SplashPage({super.key});

  @override
  Widget build(BuildContext context) => const SplashArtwork();
}
