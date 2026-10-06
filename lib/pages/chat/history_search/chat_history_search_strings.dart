import 'package:flutter/widgets.dart';

String chatHistorySearchText(BuildContext context, String key) {
  final locale = Localizations.localeOf(context);
  final words = _copy[key]!;
  final index = switch (locale.languageCode) {
    'zh' => locale.scriptCode == 'Hant' ||
            const ['TW', 'HK', 'MO'].contains(locale.countryCode)
        ? 1
        : 0,
    'ja' => 3,
    'ko' => 4,
    _ => 2,
  };
  return words[index];
}

const _copy = <String, List<String>>{
  'noData': ['暂无数据', '暫無資料', 'No data', 'データがありません', '데이터가 없습니다'],
  'media': ['媒体', '媒體', 'Media', 'メディア', '미디어'],
  'groupMembers': ['群成员', '群成員', 'Group members', 'グループメンバー', '그룹 멤버'],
  'cancel': ['取消', '取消', 'Cancel', 'キャンセル', '취소'],
  'search': ['搜索', '搜尋', 'Search', '検索', '검색'],
  'empty': [
    '未找到相关结果',
    '未找到相關結果',
    'No results found',
    '該当する結果がありません',
    '관련 결과를 찾을 수 없습니다'
  ],
  'failed': [
    '搜索未完成，请重试',
    '搜尋未完成，請重試',
    'Search failed. Please retry.',
    '検索に失敗しました。再試行してください',
    '검색하지 못했습니다. 다시 시도하세요'
  ],
  'retry': ['重试', '重試', 'Retry', '再試行', '다시 시도'],
  'moreMessages': ['更多聊天记录', '更多聊天記錄', 'More messages', '他のメッセージ', '더 많은 메시지'],
  'mediaUnavailable': [
    '媒体暂时无法打开，请稍后重试',
    '媒體暫時無法開啟，請稍後重試',
    'Media is unavailable. Please try again later.',
    'メディアを開けません。しばらくしてから再試行してください',
    '미디어를 열 수 없습니다. 잠시 후 다시 시도하세요'
  ],
  'date': ['日期', '日期', 'Date', '日付', '날짜'],
  'sender': ['发送人', '傳送者', 'Sender', '送信者', '보낸 사람'],
  'specified': ['搜索指定内容', '搜尋指定內容', 'Search by category', '種類から検索', '유형별 검색'],
  'chooseDate': ['选择日期', '選擇日期', 'Choose a date', '日付を選択', '날짜 선택'],
  'chooseSender': ['选择发送人', '選擇傳送者', 'Choose a sender', '送信者を選択', '보낸 사람 선택'],
  'searchMembers': ['搜索成员', '搜尋成員', 'Search members', 'メンバーを検索', '멤버 검색'],
  'membersFailed': [
    '成员加载失败，请重试',
    '成員載入失敗，請重試',
    'Could not load members. Retry.',
    'メンバーを読み込めません。再試行してください',
    '멤버를 불러오지 못했습니다. 다시 시도하세요'
  ],
  'noMembers': [
    '未找到相关成员',
    '找不到相關成員',
    'No matching members',
    '該当するメンバーがいません',
    '일치하는 멤버가 없습니다'
  ],
  'loadMore': ['加载更多', '載入更多', 'Load more', 'さらに読み込む', '더 불러오기'],
  'accountChanged': [
    '账户已切换，请重新打开',
    '帳戶已切換，請重新開啟',
    'Account changed. Reopen this page.',
    'アカウントが変更されました。開き直してください',
    '계정이 변경되었습니다. 페이지를 다시 여세요'
  ],
  'clear': ['清空', '清空', 'Clear', 'クリア', '지우기'],
};
