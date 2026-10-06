import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'send_verification_application_logic.dart';
import 'widgets/verification_application_form.dart';

class SendVerificationApplicationPage extends StatelessWidget {
  SendVerificationApplicationPage(
      {super.key, SendVerificationApplicationLogic? logic})
      : logic = logic ?? Get.find<SendVerificationApplicationLogic>();

  final SendVerificationApplicationLogic logic;

  @override
  Widget build(BuildContext context) => Obx(() => VerificationApplicationForm(
        controller: logic.inputCtrl,
        onSend: logic.send,
        sending: logic.sending.value,
        canSubmit: logic.canSubmit,
        unavailableMessage: logic.unavailableMessage,
        isEnterGroup: logic.isEnterGroup,
        targetName: logic.targetName,
        targetAvatarURL: logic.targetAvatarURL,
        targetAccount: logic.targetAccount,
        maxLength: SendVerificationApplicationLogic.maxMessageLength,
      ));
}
