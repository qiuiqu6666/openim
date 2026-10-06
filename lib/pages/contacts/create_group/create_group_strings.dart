import 'package:flutter/material.dart';

enum _CreateGroupLocale { zhHans, zhHant, en, ja, ko }

class CreateGroupStrings {
  const CreateGroupStrings._(this._locale);

  factory CreateGroupStrings.of(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final traditional = locale.scriptCode?.toLowerCase() == 'hant' ||
        const ['TW', 'HK', 'MO'].contains(locale.countryCode?.toUpperCase());
    return CreateGroupStrings._(switch (locale.languageCode) {
      'zh' =>
        traditional ? _CreateGroupLocale.zhHant : _CreateGroupLocale.zhHans,
      'ja' => _CreateGroupLocale.ja,
      'ko' => _CreateGroupLocale.ko,
      _ => _CreateGroupLocale.en,
    });
  }

  final _CreateGroupLocale _locale;
  String _text(String zhHans, String zhHant, String en, String ja, String ko) =>
      switch (_locale) {
        _CreateGroupLocale.zhHans => zhHans,
        _CreateGroupLocale.zhHant => zhHant,
        _CreateGroupLocale.en => en,
        _CreateGroupLocale.ja => ja,
        _CreateGroupLocale.ko => ko,
      };

  String get title => _text('新建群聊', '新建群聊', 'New Group', 'グループを作成', '그룹 만들기');
  String get create => _text('创建', '建立', 'Create', '作成', '만들기');
  String get avatar =>
      _text('群头像', '群頭像', 'Group avatar', 'グループのアイコン', '그룹 프로필 사진');
  String get avatarHint => _text(
      '设置一个有特色的群头像吧',
      '設定一個有特色的群頭像吧',
      'Choose a distinctive group avatar',
      '個性的なグループアイコンを設定しましょう',
      '개성 있는 그룹 프로필 사진을 설정하세요');
  String get name => _text('群名称', '群名稱', 'Group name', 'グループ名', '그룹 이름');
  String get nameHint =>
      _text('请输入群名称', '請輸入群名稱', 'Enter group name', 'グループ名を入力', '그룹 이름 입력');
  String members(int count) => _text('群成员（$count）', '群成員（$count）',
      'Members ($count)', 'メンバー（$count）', '멤버 ($count)');
  String get addMembers =>
      _text('添加成员', '新增成員', 'Add members', 'メンバーを追加', '멤버 추가');
  String get addMemberTile => _text('添加成员', '新增成員', 'Add', '追加', '추가');
  String get declaration => _text(
      '创建群聊即表示您已阅读并同意遵守平台社区规范，对群内信息发布与管理承担责任。',
      '建立群聊即表示您已閱讀並同意遵守平台社區規範，對群內資訊發布與管理承擔責任。',
      'By creating a group, you agree to follow the community rules and take responsibility for its content and management.',
      'グループを作成すると、コミュニティ規約に同意し、グループ内の情報発信と管理に責任を負うものとします。',
      '그룹을 만들면 커뮤니티 규칙에 동의하며 그룹 내 콘텐츠 게시 및 관리에 대한 책임을 집니다.');
  String get createFailed => _text(
      '创建失败，请重试',
      '建立失敗，請重試',
      'Could not create the group. Please try again.',
      '作成できませんでした。もう一度お試しください。',
      '그룹을 만들 수 없습니다. 다시 시도해 주세요.');
}
