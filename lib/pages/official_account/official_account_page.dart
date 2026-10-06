import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../chat/chat_logic.dart';
import '../chat/messages/widgets/chat_message_list.dart';
import 'widgets/official_account_header.dart';
import 'widgets/official_account_input_spacer.dart';

/// The 99chat official-account shell around the existing SDK timeline owner.
class OfficialAccountPage extends StatelessWidget {
  const OfficialAccountPage({super.key, this.logic});

  final ChatLogic? logic;

  @override
  Widget build(BuildContext context) {
    final chat = logic ?? Get.find<ChatLogic>(tag: GetTags.chat);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = ChatComposerTokens.background(dark: dark);
    return AppSystemBars(
      background: ChatComposerTokens.surface(dark: dark),
      navigationBackground: ChatComposerTokens.surface(dark: dark),
      child: Scaffold(
        backgroundColor: background,
        appBar: OfficialAccountHeader(
            logic: chat,
            toolbarHeight: OfficialAccountHeader.heightFor(context)),
        body: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ChatMessageList(
                      logic: chat,
                      emptyView: const SizedBox.expand(),
                    ),
                    Obx(() => chat.newMessages.unseenCount.value > 0 ||
                            chat.newMessages.awayFromLatest.value
                        ? Positioned(
                            right: AppTokens.s5,
                            bottom: AppTokens.s5,
                            child: NewMessageIndicator(
                                newMessageCount:
                                    chat.newMessages.unseenCount.value,
                                onTap: chat.scrollBottom),
                          )
                        : const SizedBox.shrink()),
                  ],
                ),
              ),
              OfficialAccountInputSpacer(
                  backgroundColor: ChatComposerTokens.surface(dark: dark)),
            ],
          ),
        ),
      ),
    );
  }
}
