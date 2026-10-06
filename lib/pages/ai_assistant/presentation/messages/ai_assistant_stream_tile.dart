import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';

import '../../streaming/assistant_stream_state.dart';
import '../../theme/ai_palette.dart';
import 'ai_assistant_text.dart';

/// Uses the ordinary incoming bubble without creating a selectable SDK message.
class AiAssistantStreamTile extends StatelessWidget {
  const AiAssistantStreamTile(
      {super.key,
      required this.streams,
      required this.streamID,
      this.query = ''});

  final AssistantStreamState streams;
  final String streamID;
  final String query;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: streams,
        builder: (context, _) {
          final reply = streams.snapshots
              .where((snapshot) => snapshot.streamID == streamID)
              .firstOrNull;
          if (reply == null || reply.text.isEmpty) {
            return const SizedBox.shrink();
          }
          return Padding(
            padding: EdgeInsets.fromLTRB(10.w, 0, 10.w, 20.h),
            child: ChatItemContainer(
              id: 'assistant-stream:$streamID',
              isISend: false,
              isBubbleBg: true,
              hasRead: false,
              isSending: false,
              isSendFailed: false,
              showLeftNickname: false,
              showReadStatus: false,
              showStatus: false,
              leftAvatar: const AiAssistantAvatar(size: AiMetrics.dimension44),
              child: AiAssistantMarkdown(
                dark: Theme.of(context).brightness == Brightness.dark,
                text: reply.text,
                query: query,
                fileCache: const {},
                onNeedFile: (_) {},
              ),
            ),
          );
        },
      );
}
