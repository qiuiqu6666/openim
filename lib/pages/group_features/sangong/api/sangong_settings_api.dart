import '../models/sangong_game_settings.dart';
import 'sangong_game_http.dart';
import 'sangong_v2_api.dart';

class SangongSettingsLoadResult {
  const SangongSettingsLoadResult(
      {required this.settings, required this.canEdit});
  final SangongGameSettings settings;
  final bool canEdit;
}

/// Current-group rules; the server rejects edits after banker selection.
class SangongSettingsApi {
  SangongSettingsApi(this.http, {required this.mayEdit});
  final SangongGameHttp http;
  final bool Function() mayEdit;
  SangongV2Api get _api => SangongV2Api(http);
  bool get canEdit => http.canCallAdmin && mayEdit();

  Future<SangongGameSettings> fetch() async {
    final data = await _api.read('settings');
    if (data['settings'] is! Map) {
      throw const FormatException('Invalid Sangong settings response');
    }
    return SangongGameSettings.fromJson(
        Map<String, dynamic>.from(data['settings']));
  }

  Future<SangongSettingsLoadResult> loadForUi() async =>
      SangongSettingsLoadResult(settings: await fetch(), canEdit: canEdit);

  Future<SangongGameSettings> save(SangongGameSettings settings) async {
    if (!canEdit) throw StateError('没有当前群的规则修改权限');
    if (!settings.isValid) throw ArgumentError('游戏规则无效');
    return SangongGameSettings.fromJson(
        await _api.command('rules.update', settings.toJson()));
  }
}
