import '../utils/api_response_util.dart';
import 'sangong_game_http.dart';

/// Report contracts are independent from the existing team dashboard model.
class SangongReportsApi {
  SangongReportsApi(this.http);
  final SangongGameHttp http;

  /// Preserve the service payload until the overview response schema is
  /// supplied; no team dashboard fields or client-generated totals are added.
  Future<dynamic> fetchOverview() async {
    final response = await http.requests.get('/api/v1/me/reports/overview');
    return unwrapApiPayload(response.data);
  }
}
