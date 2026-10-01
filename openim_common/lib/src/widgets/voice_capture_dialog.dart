import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'hold_to_record_button.dart';

class VoiceCaptureDialog extends StatelessWidget {
  const VoiceCaptureDialog({super.key});
  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: Styles.c_FFFFFF,
        title: Text(StrRes.voiceCapture),
        content: SizedBox(
            width: MediaQuery.sizeOf(context).width * .7,
            child: HoldToRecordButton(onRecorded: (path, seconds) async {
              if (context.mounted)
                Navigator.pop(context, {'path': path, 'duration': seconds});
            })),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(StrRes.cancel))
        ],
      );
}
