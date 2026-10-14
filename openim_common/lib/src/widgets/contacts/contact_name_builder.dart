import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../contacts/contact_remark_source.dart';

/// Projects live contact remarks into an existing name/avatar layout.
class ContactNameBuilder extends StatelessWidget {
  const ContactNameBuilder({
    super.key,
    required this.userID,
    required this.builder,
    this.nickname,
    this.fallbackRemark,
    this.enabled = true,
  });

  final String? userID;
  final String? nickname;
  final String? fallbackRemark;
  final bool enabled;
  final Widget Function(BuildContext context, String name) builder;

  @override
  Widget build(BuildContext context) {
    final source = enabled ? ContactRemarkSource.current : null;
    if (source == null) {
      return builder(
          context,
          ContactRemarkSource.nameFromValues(userID,
              nickname: nickname, remark: fallbackRemark));
    }
    return Obx(() => builder(
        context,
        ContactRemarkSource.nameFromValues(userID,
            nickname: nickname, remark: source.remarkFor(userID))));
  }
}
