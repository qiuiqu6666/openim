import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'splash_logic.dart';
import 'widgets/splash_artwork.dart';
import '../../core/server_nodes/startup/startup_network_preparation.dart';
import 'widgets/startup_recovery_panel.dart';

class SplashPage extends StatelessWidget {
  final logic = Get.find<SplashLogic>();

  SplashPage({super.key});

  @override
  Widget build(BuildContext context) => Stack(children: [
        const SplashArtwork(),
        if (Get.isRegistered<StartupNetworkPreparation>())
          StartupRecoveryPanel(network: Get.find<StartupNetworkPreparation>()),
      ]);
}
