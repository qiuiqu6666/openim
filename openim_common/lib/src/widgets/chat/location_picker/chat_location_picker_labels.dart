import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';

import 'data/chat_location_source.dart';

/// Copy follows the picker route's locale without changing app language state.
class ChatLocationPickerLabels {
  const ChatLocationPickerLabels._(this.locale);

  factory ChatLocationPickerLabels.of(BuildContext context) =>
      ChatLocationPickerLabels._(Localizations.maybeLocaleOf(context) ??
          Get.locale ??
          const Locale('zh', 'CN'));

  final Locale locale;

  String get title =>
      _text('选择位置', '選擇位置', 'Choose location', '場所を選択', '위치 선택');

  String get send => _text('发送位置', '傳送位置', 'Send location', '場所を送信', '위치 보내기');

  String get name => _text('位置名称（可选）', '位置名稱（選填）', 'Location name (optional)',
      '場所の名前（任意）', '위치 이름 (선택)');

  String get mapHint => _text(
      '点击或拖动地图选择位置',
      '點選或拖動地圖選擇位置',
      'Tap or drag the map to choose a location',
      '地図をタップまたはドラッグして選択',
      '지도를 누르거나 드래그해 위치 선택');

  String get selected =>
      _text('已选位置', '已選位置', 'Selected location', '選択した場所', '선택한 위치');

  String get emptySelection =>
      _text('尚未选择位置', '尚未選擇位置', 'No location selected', '場所が未選択', '선택한 위치 없음');

  String get selectHint => _text(
      '在地图上选点，或定位到当前位置',
      '在地圖上選點，或定位到目前位置',
      'Choose a point or use your current location',
      '地図で選ぶか、現在地を使用',
      '지도에서 선택하거나 현재 위치 사용');

  String get locate =>
      _text('定位到当前位置', '定位到目前位置', 'Use current location', '現在地を使用', '현재 위치 사용');

  String get locating =>
      _text('正在定位…', '正在定位…', 'Finding location…', '現在地を取得中…', '위치를 찾는 중…');

  String get zoomIn => _text('放大地图', '放大地圖', 'Zoom in', '拡大', '확대');

  String get zoomOut => _text('缩小地图', '縮小地圖', 'Zoom out', '縮小', '축소');

  String get mapProviderTitle =>
      _text('使用高德地图', '使用高德地圖', 'Use AMap', '高徳地図を使用', 'AMap 사용');

  String get mapPrivacyHint => _text(
      '查看并同意高德隐私政策后，即可在地图上选择位置。',
      '查看並同意高德隱私政策後，即可在地圖上選擇位置。',
      'Read and accept AMap’s privacy policy to choose a location on the map.',
      '高徳地図のプライバシーポリシーに同意すると、地図で場所を選べます。',
      'AMap 개인정보 처리방침을 읽고 동의하면 지도에서 위치를 선택할 수 있습니다.');

  String get mapPrivacyLink =>
      _text('隐私政策', '隱私政策', 'Privacy policy', 'プライバシーポリシー', '개인정보 처리방침');

  String get mapPrivacyAgree =>
      _text('同意并继续', '同意並繼續', 'Agree and continue', '同意して続ける', '동의하고 계속');

  String get mapUnavailable => _text(
      '地图暂时不可用', '地圖暫時無法使用', 'Map unavailable', '地図を利用できません', '지도를 사용할 수 없음');

  String get mapUnavailableHint => _text(
      '暂时无法加载地图，请稍后重新进入。',
      '暫時無法載入地圖，請稍後重新進入。',
      'The map could not be loaded. Please open this page again later.',
      '地図を読み込めません。しばらくしてから、この画面を開いてください。',
      '지도를 불러올 수 없습니다. 나중에 이 화면을 다시 열어 주세요.');

  String get retry => _text('重试', '重試', 'Retry', '再試行', '다시 시도');

  String get settings =>
      _text('去设置', '前往設定', 'Open settings', '設定を開く', '설정 열기');

  String get locationServices => _text(
      '打开定位服务', '開啟定位服務', 'Open location services', '位置情報サービスを開く', '위치 서비스 열기');

  String coordinates(LatLng point) {
    final latitude = point.latitude.toStringAsFixed(5);
    final longitude = point.longitude.toStringAsFixed(5);
    return _text(
      '纬度 $latitude · 经度 $longitude',
      '緯度 $latitude · 經度 $longitude',
      'Latitude $latitude · Longitude $longitude',
      '緯度 $latitude · 経度 $longitude',
      '위도 $latitude · 경도 $longitude',
    );
  }

  String failure(ChatLocationFailure failure) => switch (failure) {
        ChatLocationFailure.disabled => _text(
            '请开启手机定位服务，或在地图上手动选点',
            '請開啟手機定位服務，或在地圖上手動選點',
            'Turn on location services or choose a point on the map.',
            '位置情報サービスをオンにするか、地図で場所を選んでください。',
            '위치 서비스를 켜거나 지도에서 직접 선택해 주세요.'),
        ChatLocationFailure.denied => _text(
            '定位权限未开启，仍可在地图上手动选点',
            '定位權限未開啟，仍可在地圖上手動選點',
            'Location permission is off. You can still choose a point on the map.',
            '位置情報の権限がありません。地図で場所を選ぶことはできます。',
            '위치 권한이 꺼져 있습니다. 지도에서 직접 선택할 수 있습니다.'),
        ChatLocationFailure.deniedForever => _text(
            '请在系统设置开启定位权限',
            '請在系統設定開啟定位權限',
            'Enable location permission in system settings.',
            'システム設定で位置情報の権限を許可してください。',
            '시스템 설정에서 위치 권한을 켜 주세요.'),
        ChatLocationFailure.timeout => _text(
            '定位超时，请重试或手动选点',
            '定位逾時，請重試或手動選點',
            'Location timed out. Retry or choose a point on the map.',
            '現在地の取得がタイムアウトしました。再試行するか、地図で選んでください。',
            '위치 찾기 시간이 초과되었습니다. 다시 시도하거나 지도에서 선택해 주세요.'),
        ChatLocationFailure.unavailable => _text(
            '暂时无法定位，请重试或手动选点',
            '暫時無法定位，請重試或手動選點',
            'Location is unavailable. Retry or choose a point on the map.',
            '現在地を取得できません。再試行するか、地図で選んでください。',
            '지금은 위치를 찾을 수 없습니다. 다시 시도하거나 지도에서 선택해 주세요.'),
      };

  String _text(String cn, String hant, String en, String ja, String ko) {
    return switch (locale.languageCode.toLowerCase()) {
      'zh' => _traditionalChinese ? hant : cn,
      'en' => en,
      'ja' => ja,
      'ko' => ko,
      _ => cn,
    };
  }

  bool get _traditionalChinese {
    final script = locale.scriptCode?.toLowerCase();
    if (script != null) return script == 'hant';
    return const {'TW', 'HK', 'MO'}.contains(locale.countryCode?.toUpperCase());
  }
}
