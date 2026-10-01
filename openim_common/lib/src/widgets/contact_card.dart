import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

// Visual tokens adapted from 99chat's ContactCardMessageItem.
abstract final class ContactCardTokens {
  static const body = Color(0xFF5B8DEF);
  static const footer = Color(0xFF4A7AD4);
  static const title = Color(0xFFF7FAFF);
  static const subtitle = Color(0xFFDCE8FF);
  static const footerText = Color(0xFFC8DAFF);
}

class ContactCardView extends StatelessWidget {
  const ContactCardView(
      {super.key,
      required this.userID,
      required this.name,
      this.faceURL,
      required this.isSelf,
      required this.time});
  final String userID;
  final String name;
  final String? faceURL;
  final bool isSelf;
  final String time;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 247.w,
        child: Stack(children: [
          Positioned(
            left: isSelf ? null : 0,
            right: isSelf ? 0 : null,
            top: 22.w,
            child: Transform.flip(
              flipX: !isSelf,
              child: CustomPaint(size: Size(14.w, 24.w), painter: _CardTail()),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
                left: isSelf ? 0 : 9.w, right: isSelf ? 9.w : 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14.r),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  color: ContactCardTokens.body,
                  constraints: BoxConstraints(minHeight: 82.w),
                  padding:
                      EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.w),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IgnorePointer(
                            child: AvatarView(
                                width: 40.w,
                                height: 40.w,
                                isCircle: true,
                                url: faceURL,
                                text: name)),
                        SizedBox(width: 12.w),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: ContactCardTokens.title,
                                      fontSize: 15.sp,
                                      fontWeight: FontWeight.w500,
                                      height: 1.25)),
                              if (userID.isNotEmpty && userID != name) ...[
                                SizedBox(height: 6.w),
                                Text(userID,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: ContactCardTokens.subtitle,
                                        fontSize: 12.sp)),
                              ],
                            ])),
                      ]),
                ),
                Container(
                  color: ContactCardTokens.footer,
                  padding:
                      EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.w),
                  child: Row(children: [
                    Expanded(
                        child: Text('personalContactCard'.tr,
                            style: TextStyle(
                                color: ContactCardTokens.footerText,
                                fontSize: 11.sp))),
                    Text(time,
                        style: TextStyle(
                            color: ContactCardTokens.footerText,
                            fontSize: 11.sp)),
                  ]),
                ),
              ]),
            ),
          ),
        ]),
      );
}

class _CardTail extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(size.width * .88, size.height * .14, size.width * .92,
          size.height * .46)
      ..quadraticBezierTo(size.width * .96, size.height * .78, 0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = ContactCardTokens.body);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ContactCardSendDialog extends StatelessWidget {
  const ContactCardSendDialog(
      {super.key,
      required this.name,
      this.faceURL,
      required this.recipientName,
      this.recipientFaceURL,
      this.recipientIsGroup = false});
  final String name;
  final String? faceURL;
  final String recipientName;
  final String? recipientFaceURL;
  final bool recipientIsGroup;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: 300, maxHeight: MediaQuery.sizeOf(context).height * .85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('sendContactCard'.tr,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
                'recommendContactTo'
                    .trParams({'name': name, 'recipient': recipientName}),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: colors.onSurfaceVariant, fontSize: 12, height: 1.3)),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              AvatarView(
                  width: 46,
                  height: 46,
                  url: faceURL,
                  text: name,
                  isCircle: true),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(Icons.arrow_forward_rounded,
                      size: 23, color: colors.onSurface)),
              AvatarView(
                  width: 46,
                  height: 46,
                  url: recipientFaceURL,
                  text: recipientName,
                  isGroup: recipientIsGroup,
                  isCircle: !recipientIsGroup),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                  child: TextButton(
                      style: TextButton.styleFrom(
                          backgroundColor: colors.surfaceContainerHighest,
                          foregroundColor: colors.onSurface,
                          minimumSize: const Size(0, 44),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6))),
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(StrRes.cancel))),
              const SizedBox(width: 10),
              Expanded(
                  child: FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: Styles.c_0089FF,
                          minimumSize: const Size(0, 44),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6))),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(StrRes.determine))),
            ]),
          ]),
        ),
      ),
    );
  }
}
