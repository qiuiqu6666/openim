import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'group_personalization.dart';
import 'group_personalization_artwork.dart';
import 'group_personalization_preview.dart';
import 'group_personalization_style.dart';

class GroupPersonalizationEditor extends StatelessWidget {
  const GroupPersonalizationEditor(
      {super.key,
      required this.name,
      this.avatarUrl,
      required this.appearance,
      required this.busy,
      this.error,
      required this.onChanged,
      required this.onUpload,
      required this.onSave});
  final String name;
  final String? avatarUrl, error;
  final GroupPersonalization appearance;
  final bool busy;
  final ValueChanged<GroupPersonalization> onChanged;
  final VoidCallback onUpload, onSave;
  static const palette = GroupPersonalizationStyle.palette;
  void color(int? value) => onChanged(GroupPersonalization(
      color: value, iconUrl: appearance.iconUrl, iconKey: appearance.iconKey));

  @override
  Widget build(BuildContext context) {
    final width = math.min(
        MediaQuery.sizeOf(context).width, GroupPersonalizationStyle.maxWidth);
    final s = width / GroupPersonalizationStyle.referenceWidth;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? Styles.c_0C1C33 : GroupPersonalizationStyle.ink;
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
    final heading =
        TextStyle(fontSize: 36 * s, fontWeight: FontWeight.w700, color: ink);
    return Scaffold(
        backgroundColor:
            dark ? Styles.c_F8F9FA : GroupPersonalizationStyle.page,
        appBar: GlassAppBar(
            toolbarHeight: math.max(48, 112 * s),
            centerTitle: false,
            backgroundColor: dark ? Styles.c_FFFFFF : Colors.white,
            leadingWidth: 120 * s,
            leading: IconButton(
                tooltip: '返回',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: Icon(CupertinoIcons.back, color: ink, size: 40 * s)),
            title: Text('群个性化',
                style: TextStyle(
                    fontSize: 44 * s,
                    fontWeight: FontWeight.w700,
                    color: ink))),
        body: SafeArea(
            top: false,
            child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                    width: width,
                    child: ListView(
                        padding:
                            EdgeInsets.fromLTRB(28 * s, 32 * s, 28 * s, 80 * s),
                        children: [
                          GroupPersonalizationPreview(
                              name: name,
                              avatarUrl: avatarUrl,
                              appearance: appearance,
                              scale: s),
                          SizedBox(height: 35 * s),
                          Row(children: [
                            Expanded(child: Text('群昵称颜色', style: heading)),
                            TextButton(
                                style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize:
                                        Size(110 * s, largeText ? 48 : 64 * s),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap),
                                onPressed: busy ? null : () => color(null),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('默认',
                                          style: TextStyle(
                                              fontSize: 28 * s,
                                              color: GroupPersonalizationStyle
                                                  .blue)),
                                      SizedBox(width: 14 * s),
                                      Icon(CupertinoIcons.chevron_down,
                                          size: 25 * s,
                                          color:
                                              GroupPersonalizationStyle.blue),
                                    ]))
                          ]),
                          SizedBox(height: 8 * s),
                          LayoutBuilder(builder: (context, constraints) {
                            final cols = width < 350 ? 5 : 6;
                            final gap = 22 * s;
                            final tile =
                                (constraints.maxWidth - (cols - 1) * gap) /
                                    cols;
                            return Wrap(
                                spacing: gap,
                                runSpacing: 20 * s,
                                children: [
                                  _choice(context,
                                      s: s,
                                      label: '默认颜色',
                                      size: tile,
                                      selected: appearance.color == null,
                                      colorTile: true,
                                      child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                                width: 58 * s,
                                                height: 58 * s,
                                                alignment: Alignment.center,
                                                decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                        color:
                                                            Styles.c_E8EAEF)),
                                                child: Text('A',
                                                    style: TextStyle(
                                                        fontSize: 42 * s,
                                                        height: 1,
                                                        color:
                                                            GroupPersonalizationStyle
                                                                .muted))),
                                            Text('默认',
                                                textScaler:
                                                    TextScaler.noScaling,
                                                style: TextStyle(
                                                    fontSize: 21 * s,
                                                    height: 1.1,
                                                    color:
                                                        GroupPersonalizationStyle
                                                            .muted)),
                                          ]),
                                      tap: () => color(null)),
                                  for (final entry in palette.entries)
                                    _choice(context,
                                        s: s,
                                        label: entry.value,
                                        size: tile,
                                        selected: appearance.color == entry.key,
                                        colorTile: true,
                                        accent: Color(entry.key),
                                        child: Container(
                                            width: 62 * s,
                                            height: 62 * s,
                                            decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                gradient: LinearGradient(
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                    colors: [
                                                      Color(entry.key),
                                                      Color(entry.key)
                                                          .withValues(alpha: .9)
                                                    ]))),
                                        tap: () => color(entry.key)),
                                ]);
                          }),
                          SizedBox(height: 40 * s),
                          _card(
                              context,
                              s,
                              Padding(
                                  padding: EdgeInsets.fromLTRB(
                                      25 * s, 20 * s, 25 * s, 22 * s),
                                  child: Column(children: [
                                    InkWell(
                                        onTap: busy ? null : onUpload,
                                        child: ConstrainedBox(
                                            constraints: BoxConstraints(
                                                minHeight:
                                                    largeText ? 48 : 64 * s),
                                            child: largeText
                                                ? Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                        Text('自定义小图标',
                                                            style: heading),
                                                        Text('上传图片，显示在群昵称前',
                                                            style: TextStyle(
                                                                fontSize:
                                                                    26 * s,
                                                                color:
                                                                    GroupPersonalizationStyle
                                                                        .muted))
                                                      ])
                                                : Row(children: [
                                                    Text('自定义小图标',
                                                        style: heading),
                                                    const Spacer(),
                                                    Text('上传图片，显示在群昵称前',
                                                        style: TextStyle(
                                                            fontSize: 26 * s,
                                                            color:
                                                                GroupPersonalizationStyle
                                                                    .muted)),
                                                    SizedBox(width: 12 * s),
                                                    Icon(
                                                        CupertinoIcons
                                                            .chevron_right,
                                                        size: 26 * s,
                                                        color:
                                                            GroupPersonalizationStyle
                                                                .muted),
                                                  ]))),
                                    SizedBox(height: 12 * s),
                                    LayoutBuilder(
                                        builder: (context, constraints) {
                                      final cols = width < 350 ? 6 : 7;
                                      final gap = 14 * s;
                                      final tile = (constraints.maxWidth -
                                              (cols - 1) * gap) /
                                          cols;
                                      return Wrap(
                                          spacing: gap,
                                          runSpacing: 14 * s,
                                          children: [
                                            _choice(context,
                                                s: s,
                                                label: '上传图片',
                                                size: tile,
                                                selected:
                                                    appearance.iconUrl != null,
                                                child: appearance.iconUrl !=
                                                        null
                                                    ? Image.network(
                                                        appearance.iconUrl!,
                                                        width: tile * .72,
                                                        height: tile * .72,
                                                        errorBuilder: (_, __,
                                                                ___) =>
                                                            const Icon(
                                                                CupertinoIcons
                                                                    .photo))
                                                    : Column(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                            Icon(
                                                                CupertinoIcons
                                                                    .photo,
                                                                size: 42 * s,
                                                                color:
                                                                    GroupPersonalizationStyle
                                                                        .muted),
                                                            SizedBox(
                                                                height: 4 * s),
                                                            Text('上传图片',
                                                                textScaler:
                                                                    TextScaler
                                                                        .noScaling,
                                                                style: TextStyle(
                                                                    fontSize:
                                                                        22 * s,
                                                                    color: GroupPersonalizationStyle
                                                                        .muted))
                                                          ]),
                                                tap: onUpload),
                                            for (final key
                                                in GroupPersonalization
                                                    .icons.keys)
                                              _choice(context,
                                                  s: s,
                                                  label:
                                                      '图标 ${GroupPersonalizationStyle.iconNames[GroupPersonalization.icons.keys.toList().indexOf(key)]}',
                                                  size: tile,
                                                  selected:
                                                      appearance.iconKey == key,
                                                  child:
                                                      GroupPersonalizationArtwork(
                                                          iconKey: key,
                                                          size: tile * .77),
                                                  tap: () => onChanged(
                                                      GroupPersonalization(
                                                          color:
                                                              appearance.color,
                                                          iconKey: key))),
                                          ]);
                                    }),
                                  ]))),
                          SizedBox(height: 20 * s),
                          _card(
                              context,
                              s,
                              Column(children: [
                                _action(
                                    context,
                                    s,
                                    '移除图标',
                                    CupertinoIcons.trash,
                                    () => onChanged(GroupPersonalization(
                                        color: appearance.color))),
                                Divider(
                                    height: 1,
                                    thickness: .5,
                                    color: Styles.c_E8EAEF),
                                _action(
                                    context,
                                    s,
                                    '恢复默认',
                                    CupertinoIcons.refresh,
                                    () => onChanged(
                                        const GroupPersonalization())),
                              ])),
                          if (error != null)
                            Padding(
                                padding: EdgeInsets.all(20 * s),
                                child: Semantics(
                                    liveRegion: true,
                                    child: Text(error!,
                                        style: TextStyle(
                                            color: Styles.c_FF381F)))),
                          SizedBox(height: 48 * s),
                          Padding(
                              padding: EdgeInsets.symmetric(horizontal: 14 * s),
                              child: DecoratedBox(
                                  decoration: BoxDecoration(
                                      borderRadius:
                                          BorderRadius.circular(100 * s),
                                      gradient: const LinearGradient(colors: [
                                        GroupPersonalizationStyle.blue,
                                        GroupPersonalizationStyle.blueEnd
                                      ]),
                                      boxShadow: [
                                        BoxShadow(
                                            color: GroupPersonalizationStyle
                                                .blue
                                                .withValues(
                                                    alpha: dark ? .05 : .12),
                                            blurRadius: 24 * s,
                                            offset: Offset(0, 12 * s))
                                      ]),
                                  child: FilledButton(
                                      style: FilledButton.styleFrom(
                                          backgroundColor: Colors.transparent,
                                          shadowColor: Colors.transparent,
                                          minimumSize: Size.fromHeight(
                                              math.max(48, 98 * s)),
                                          shape: const StadiumBorder()),
                                      onPressed: busy ? null : onSave,
                                      child: Text(busy ? '处理中…' : '保存',
                                          style: TextStyle(
                                              fontSize: 42 * s,
                                              color: Colors.white))))),
                        ])))));
  }

  Widget _card(BuildContext context, double s, Widget child) => Material(
      color: Styles.c_FFFFFF,
      borderRadius: BorderRadius.circular(28 * s),
      clipBehavior: Clip.antiAlias,
      child: child);

  Widget _action(BuildContext context, double s, String label, IconData icon,
          VoidCallback onTap) =>
      InkWell(
          onTap: busy ? null : onTap,
          child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: math.max(48, 110 * s)),
              child: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: 32 * s, vertical: 20 * s),
                  child: Row(children: [
                    Icon(icon, size: 44 * s, color: Styles.c_0C1C33),
                    SizedBox(width: 38 * s),
                    Expanded(
                        child: Text(label,
                            style: TextStyle(
                                fontSize: 32 * s, color: Styles.c_0C1C33))),
                    Icon(CupertinoIcons.chevron_right,
                        size: 27 * s, color: GroupPersonalizationStyle.muted),
                  ]))));

  Widget _choice(BuildContext context,
      {required double s,
      required String label,
      required double size,
      required bool selected,
      required Widget child,
      required VoidCallback tap,
      Color? accent,
      bool colorTile = false}) {
    final active = accent ?? GroupPersonalizationStyle.blue;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(21 * s);
    return Tooltip(
        message: label,
        child: Semantics(
            label: label,
            selected: selected,
            button: true,
            enabled: !busy,
            child: SizedBox(
                width: size,
                height: math.max(44, size * (colorTile ? .91 : 1.04)),
                child: Stack(clipBehavior: Clip.none, children: [
                  Positioned.fill(
                      child: DecoratedBox(
                          decoration: BoxDecoration(
                              borderRadius: radius,
                              boxShadow: colorTile
                                  ? [
                                      BoxShadow(
                                          color: Colors.black.withValues(
                                              alpha: dark ? .03 : .035),
                                          blurRadius: 18 * s,
                                          offset: Offset(0, 5 * s))
                                    ]
                                  : null),
                          child: Material(
                              color: selected
                                  ? active.withValues(alpha: .06)
                                  : colorTile
                                      ? Styles.c_FFFFFF
                                      : dark
                                          ? Styles.c_F8F9FA
                                          : GroupPersonalizationStyle.tile,
                              borderRadius: radius,
                              child: InkWell(
                                  borderRadius: radius,
                                  onTap: busy ? null : tap,
                                  child: Container(
                                      decoration: BoxDecoration(
                                          borderRadius: radius,
                                          border: selected
                                              ? Border.all(
                                                  color: active, width: 1.2)
                                              : null),
                                      child: Center(
                                          child: ExcludeSemantics(
                                              child: child))))))),
                  if (selected)
                    Positioned(
                        right: -3 * s,
                        top: colorTile ? -8 * s : null,
                        bottom: colorTile ? null : -4 * s,
                        child: IgnorePointer(
                            child: Container(
                                width: 38 * s,
                                height: 38 * s,
                                decoration: BoxDecoration(
                                    color: active,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Styles.c_FFFFFF, width: 1.5)),
                                child: Icon(Icons.check_rounded,
                                    size: 27 * s, color: Colors.white)))),
                ]))));
  }
}
