import 'package:country_picker/country_picker.dart';
import 'package:azlistview/azlistview.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../widgets/settings_widgets.dart';

class CountryCodePage extends StatefulWidget {
  const CountryCodePage({super.key, required this.selectedCode});
  final String selectedCode;
  @override
  State<CountryCodePage> createState() => _CountryCodePageState();
}

class _CountryCodePageState extends State<CountryCodePage> {
  final _countries = CountryService().getAll();
  String _query = '';
  String _letter(Country country) {
    final name = country.name.replaceFirst('Å', 'A').toUpperCase();
    return RegExp('[A-Z]').firstMatch(name)?.group(0) ?? 'A';
  }

  String _name(Country country) =>
      CountryLocalizations.of(context)
          ?.countryName(countryCode: country.countryCode) ??
      country.name;

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final query = _query.trim().toLowerCase();
    final countries = _countries
        .where((country) =>
            query.isEmpty ||
            _name(country).toLowerCase().contains(query) ||
            country.name.toLowerCase().contains(query) ||
            country.countryCode.toLowerCase().contains(query) ||
            ('+${country.phoneCode}').contains(query))
        .toList()
      ..sort((a, b) => _letter(a).compareTo(_letter(b)) == 0
          ? a.name.compareTo(b.name)
          : _letter(a).compareTo(_letter(b)));
    final rows = countries
        .map((country) => _CountryRow(country, _letter(country)))
        .toList();
    SuspensionUtil.setShowSuspensionStatus(rows);
    final extent = SettingsResponsive.listRowMinHeight(context);
    return SettingsScaffold(
      title: settingsText(context, zh: '选择国家或地区', en: 'Country or Region'),
      body: SafeArea(
          top: false,
          child: Column(children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppTokens.s5, AppTokens.s3, AppTokens.s5, AppTokens.s3),
                child: TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                      hintText: settingsText(context,
                          zh: '搜索国家、地区或区号',
                          en: 'Search country or calling code'),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: AppTokens.s4, horizontal: AppTokens.s4),
                      prefixIcon:
                          const Icon(Icons.search_rounded, size: AppTokens.s6),
                      filled: true,
                      fillColor: AppTokens.surface(dark: dark),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppTokens.rMd),
                          borderSide: BorderSide.none)),
                )),
            Expanded(
                child: countries.isEmpty
                    ? Center(
                        child: Text(settingsText(context,
                            zh: '未找到匹配的国家或地区', en: 'No matching countries')))
                    : AzListView(
                        data: rows,
                        itemCount: rows.length,
                        padding: const EdgeInsets.only(
                            left: AppTokens.s5, right: AppTokens.s8),
                        indexBarData: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split(''),
                        indexBarWidth: 24.w,
                        indexBarItemHeight: 16.h,
                        indexBarMargin: EdgeInsets.only(
                            right: 2.w,
                            bottom: MediaQuery.paddingOf(context).bottom),
                        indexBarOptions: directoryIndexBarOptions(),
                        susItemHeight: 0,
                        susItemBuilder: (_, index) => const SizedBox.shrink(),
                        itemBuilder: (context, index) {
                          final country = rows[index].country;
                          final code = '+${country.phoneCode}';
                          final first = index == 0 ||
                              rows[index - 1].tag != rows[index].tag;
                          final last = index == rows.length - 1 ||
                              rows[index + 1].tag != rows[index].tag;
                          return SizedBox(
                              height: extent,
                              child: ClipRRect(
                                  borderRadius: BorderRadius.vertical(
                                      top: first
                                          ? const Radius.circular(AppTokens.rMd)
                                          : Radius.zero,
                                      bottom: last
                                          ? const Radius.circular(AppTokens.rMd)
                                          : Radius.zero),
                                  child: Material(
                                      color: AppTokens.surface(dark: dark),
                                      child: InkWell(
                                        onTap: () =>
                                            Navigator.of(context).pop(code),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: AppTokens.s4),
                                          decoration: BoxDecoration(
                                              border: Border(
                                                  bottom: BorderSide(
                                                      color: AppTokens.border(
                                                          dark: dark),
                                                      width: last ? 0 : 0.5))),
                                          child: Row(children: [
                                            ExcludeSemantics(
                                                child: Text(country.flagEmoji,
                                                    style: const TextStyle(
                                                        fontSize: AppTokens
                                                            .mainTabTitleFontSize))),
                                            const SizedBox(width: AppTokens.s4),
                                            Expanded(
                                                child: Text(_name(country),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                        fontSize: AppTokens
                                                            .secondaryFontSize))),
                                            const SizedBox(width: AppTokens.s3),
                                            Text(code,
                                                style: TextStyle(
                                                    color:
                                                        AppTokens.textSecondary(
                                                            dark: dark),
                                                    fontSize: AppTokens
                                                        .captionFontSize)),
                                            if (code ==
                                                widget.selectedCode) ...[
                                              const SizedBox(
                                                  width: AppTokens.s2),
                                              const Icon(Icons.check_rounded,
                                                  color: AppTokens.accent,
                                                  size: AppTokens.s6),
                                            ],
                                          ]),
                                        ),
                                      ))));
                        })),
          ])),
      children: const [],
    );
  }
}

class _CountryRow extends ISuspensionBean {
  _CountryRow(this.country, this.tag);
  final Country country;
  final String tag;
  @override
  String getSuspensionTag() => tag;
}
