import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import '../../mine/settings/pages/feedback_page.dart';
import '../../mine/settings/feedback/feedback_submission.dart';
import '../../mine/settings/settings_service.dart';
import '../../mine/settings/widgets/settings_widgets.dart';
import 'complaint_api.dart';

class ComplaintReasonPage extends StatelessWidget {
  const ComplaintReasonPage(
      {super.key,
      required this.reportedUserID,
      required this.targetName,
      this.groupID});
  final String reportedUserID, targetName;
  final String? groupID;

  Future<void> _openForm(BuildContext context, ComplaintReason reason) async {
    final api = ComplaintApi();
    final submitted = await Get.to<bool>(() => FeedbackPage(
          service: const StubSettingsService(),
          submission: FeedbackSubmission(
            target: targetName.trim().isNotEmpty
                ? targetName
                : settingsText(context,
                    zh: groupID == null ? '该用户' : '该群聊',
                    en: groupID == null ? 'This user' : 'This group'),
            reason: settingsText(context, zh: reason.zh, en: reason.en),
            submit: (id, content, files) => api.submit(
                requestID: id,
                reportedUserID: reportedUserID,
                groupID: groupID,
                reason: reason,
                content: content,
                attachments: files),
          ),
        ));
    if (submitted == true && context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => SettingsScaffold(
        title: settingsText(context, zh: '投诉原因', en: 'Complaint Reason'),
        backgroundColor: AppTokens.surfaceAlt(dark: settingsIsDark(context)),
        body: ListView(
            padding: const EdgeInsets.only(top: 10, bottom: 24),
            children: [
              SettingsGroup(borderRadius: 0, children: [
                for (final reason in ComplaintReason.values)
                  SettingsCell(
                      title:
                          settingsText(context, zh: reason.zh, en: reason.en),
                      onTap: () => _openForm(context, reason)),
              ])
            ]),
        children: const [],
      );
}
