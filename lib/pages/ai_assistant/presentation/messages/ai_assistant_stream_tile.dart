import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';

import '../../localization/ai_assistant_i18n.dart';
import '../../streaming/assistant_stream_state.dart';
import '../../streaming/diagnostics/assistant_stream_log.dart';
import '../../theme/ai_palette.dart';
import 'ai_assistant_text.dart';
import 'ai_output_cards.dart';

/// Uses the ordinary incoming bubble without creating a selectable SDK message.
class AiAssistantStreamTile extends StatelessWidget {
  const AiAssistantStreamTile(
      {super.key,
      required this.streams,
      required this.streamID,
      this.presentationID,
      this.query = ''});

  final AssistantStreamState streams;
  final String streamID;
  final String? presentationID;
  final String query;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: streams,
        builder: (context, _) {
          final reply = streams.snapshots
              .where((snapshot) => presentationID == null
                  ? snapshot.streamID == streamID
                  : snapshot.presentationID == presentationID)
              .firstOrNull;
          if (reply == null || (!reply.waiting && reply.text.isEmpty)) {
            return const SizedBox.shrink();
          }
          if (reply.text.isNotEmpty) AssistantStreamLog.bubble(streams, reply);
          final dark = Theme.of(context).brightness == Brightness.dark;
          final i18n = AiAssistantI18n.of(context);
          return Padding(
            padding: EdgeInsets.fromLTRB(10.w, 0, 10.w, 20.h),
            child: ChatItemContainer(
              id: 'assistant-stream:${reply.presentationID}',
              isISend: false,
              isBubbleBg: true,
              hasRead: false,
              isSending: false,
              isSendFailed: false,
              showLeftNickname: false,
              showReadStatus: false,
              showStatus: false,
              leftAvatar: const AiAssistantAvatar(size: AiMetrics.dimension44),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (reply.timedOut)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                          i18n.t(
                            zhHans: '回复等待较久，你可以继续提问。收到回复后会自动更新。',
                            zhHant: '回覆等候較久，你可以繼續提問。收到回覆後會自動更新。',
                            en: 'The reply is taking longer than expected. You can keep chatting; any reply will appear when it arrives.',
                          ),
                          style: TextStyle(
                              color: AiPalette.secondary(dark),
                              fontSize: AiMetrics.font13)),
                    ),
                  if (!reply.timedOut || reply.text.isNotEmpty)
                    reply.waiting
                        ? Semantics(
                            liveRegion: true,
                            child: AiThinkingCard(
                              dark: dark,
                              i18n: i18n,
                              label: i18n.t(
                                zhHans: '正在回复…',
                                zhHant: '正在回覆…',
                                en: 'Replying…',
                                ja: '返信中…',
                                ko: '답변 중…',
                              ),
                            ),
                          )
                        : AiAssistantMarkdown(
                            dark: dark,
                            text: reply.text,
                            query: query,
                            fileCache: const {},
                            onNeedFile: (_) {},
                          ),
                ],
              ),
            ),
          );
        },
      );
}
