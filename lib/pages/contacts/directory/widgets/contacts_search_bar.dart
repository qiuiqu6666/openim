import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';

/// Directory search keeps a large hit area with ink confined to the field.
class ContactsSearchBar extends StatelessWidget {
  const ContactsSearchBar({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Styles.c_FFFFFF,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 8.h),
            child: Material(
              color: Styles.c_F4F5F7,
              borderRadius: BorderRadius.circular(10.r),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const ValueKey('contacts-search-button'),
                borderRadius: BorderRadius.circular(10.r),
                onTap: onTap,
                child: Container(
                  height: 40.h,
                  padding: EdgeInsets.symmetric(horizontal: 12.w),
                  child: Row(children: [
                    Icon(Icons.search, size: 19.w, color: Styles.c_8E9AB0),
                    8.horizontalSpace,
                    Text(StrRes.search, style: Styles.ts_8E9AB0_15sp),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
}
