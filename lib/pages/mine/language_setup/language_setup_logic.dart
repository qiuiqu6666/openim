import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

class LanguageSetupLogic extends GetxController {
  final selectedLanguage = 0.obs;

  @override
  void onInit() {
    selectedLanguage.value = DataSp.getLanguage() ?? 0;
    super.onInit();
  }

  Future<void> switchLanguage(int index) async {
    final saved = await DataSp.putLanguage(index);
    if (saved != true || isClosed) return;
    selectedLanguage.value = index;
    await Get.updateLocale(
      TranslationService.localeForSetting(index, Get.deviceLocale),
    );
  }
}
