import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ChatLocationDetailLabels {
  ChatLocationDetailLabels.of(BuildContext context)
      : locale = Localizations.maybeLocaleOf(context) ??
            Get.locale ??
            const Locale('zh', 'CN');
  final Locale locale;
  String text(String cn, String tw, String en) => locale.languageCode == 'zh'
      ? (locale.countryCode == 'TW' ||
              locale.countryCode == 'HK' ||
              locale.scriptCode == 'Hant'
          ? tw
          : cn)
      : en;
  String get addressLoading => text('正在获取地址…', '正在取得地址…', 'Finding address…');
  String get addressFailed =>
      text('暂时无法获取地址', '暫時無法取得地址', 'Address unavailable');
  String get retryAddress => text('重试', '重試', 'Retry');
  String get directions => text('获取路线', '取得路線', 'Get directions');
  String get share => text('分享位置', '分享位置', 'Share location');
  String get recenter => text('回到分享位置', '回到分享位置', 'Show shared location');
  String get layers => text('地图类型', '地圖類型', 'Map type');
  String get standard => text('标准地图', '標準地圖', 'Standard map');
  String get satellite => text('卫星地图', '衛星地圖', 'Satellite map');
  String get failed =>
      text('操作失败，请重试', '操作失敗，請重試', 'Unable to complete. Please retry.');
  String get browser =>
      text('在浏览器中获取路线', '在瀏覽器中取得路線', 'Get directions in browser');
  String get locationDenied => text(
      '无法获取当前位置，请检查定位权限和定位服务。分享地点仍可查看。',
      '無法取得目前位置，請檢查定位權限和定位服務。仍可查看分享地點。',
      'Could not get your location. Check location permissions and services. The shared place is still available.');
}
