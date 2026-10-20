import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

class ChatLocationWeather {
  const ChatLocationWeather(this.temperature, this.symbol, this.time);
  final double temperature;
  final String symbol;
  final DateTime time;
  static ChatLocationWeather parse(Map<String, dynamic> json, DateTime now) {
    final properties = json['properties'] as Map;
    final units = (properties['meta'] as Map)['units'] as Map;
    if (units['air_temperature'] != 'celsius') {
      throw const FormatException('Temperature unit');
    }
    final rows = properties['timeseries'] as List;
    Map? nearest;
    var distance = const Duration(days: 1);
    for (final raw in rows) {
      final row = raw as Map;
      final delta = DateTime.parse(row['time'] as String).difference(now).abs();
      if (delta < distance) {
        nearest = row;
        distance = delta;
      }
    }
    if (nearest == null || distance > const Duration(minutes: 90)) {
      throw const FormatException('No current forecast');
    }
    final data = nearest['data'] as Map;
    final temperature =
        ((data['instant'] as Map)['details'] as Map)['air_temperature'];
    final next = data['next_1_hours'] ?? data['next_6_hours'];
    final summary = next is Map ? next['summary'] : null;
    final symbol = summary is Map ? summary['symbol_code'] : null;
    if (temperature is! num || !temperature.isFinite || symbol is! String) {
      throw const FormatException('Incomplete weather');
    }
    return ChatLocationWeather(temperature.toDouble(), symbol,
        DateTime.parse(nearest['time'] as String));
  }
}

/// Public forecast service; cache requests and identify this project to MET Norway.
class ChatLocationWeatherSource {
  ChatLocationWeatherSource({Dio? client, DateTime Function()? now})
      : _client = client ??
            Dio(BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 12))),
        _now = now ?? DateTime.now;
  static final shared = ChatLocationWeatherSource();
  final Dio _client;
  final DateTime Function() _now;
  final _cache = <String, ({DateTime expires, ChatLocationWeather weather})>{};
  final _pending = <String, Future<ChatLocationWeather>>{};
  Future<ChatLocationWeather> load(LatLng point) async {
    final lat = point.latitude.toStringAsFixed(4),
        lon = point.longitude.toStringAsFixed(4);
    final key = '$lat,$lon';
    final cached = _cache[key];
    if (cached != null &&
        _now().isBefore(cached.expires) &&
        cached.weather.time.difference(_now()).abs() <
            const Duration(minutes: 90)) {
      return cached.weather;
    }
    if (_pending.containsKey(key)) return _pending[key]!;
    final pending = _fetch(lat, lon);
    _pending[key] = pending;
    try {
      final weather = await pending;
      if (_cache.length >= 32) _cache.remove(_cache.keys.first);
      _cache[key] =
          (expires: _now().add(const Duration(hours: 1)), weather: weather);
      return weather;
    } finally {
      _pending.remove(key);
    }
  }

  Future<ChatLocationWeather> _fetch(String lat, String lon) async {
    final response = await _client
        .get<Map<String, dynamic>>(
            'https://api.met.no/weatherapi/locationforecast/2.0/compact',
            queryParameters: {'lat': lat, 'lon': lon},
            options: Options(headers: {
              'User-Agent': const String.fromEnvironment('WEATHER_USER_AGENT',
                  defaultValue:
                      '99Chat/3.0 (https://github.com/qiuiqu6666/openim)'),
            }))
        .timeout(const Duration(seconds: 15));
    return ChatLocationWeather.parse(response.data!, _now().toUtc());
  }
}
