import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:openim_common/src/widgets/chat/location_message/weather/chat_location_weather_chip.dart';
import 'package:openim_common/src/widgets/chat/location_message/weather/chat_location_weather_source.dart';

class WeatherFixture extends ChatLocationWeatherSource {
  final requests = <Completer<ChatLocationWeather>>[];
  final points = <LatLng>[];
  @override
  Future<ChatLocationWeather> load(LatLng point) {
    points.add(point);
    final request = Completer<ChatLocationWeather>();
    requests.add(request);
    return request.future;
  }
}

void main() {
  final now = DateTime.utc(2026, 10, 21, 12);
  final weather = ChatLocationWeather(26.4, 'clearsky_day', now);
  Map<String, dynamic> forecast({String unit = 'celsius', int offset = 0}) => {
        'properties': {
          'meta': {
            'units': {'air_temperature': unit}
          },
          'timeseries': [
            {
              'time': now.add(Duration(hours: offset)).toIso8601String(),
              'data': {
                'instant': {
                  'details': {'air_temperature': 26.4}
                },
                'next_6_hours': {
                  'summary': {'symbol_code': 'clearsky_day'}
                }
              }
            }
          ]
        }
      };

  test('parses temperature and falls back to six hour summary', () {
    final value = ChatLocationWeather.parse(forecast(), now);
    expect(value.temperature, 26.4);
    expect(value.symbol, 'clearsky_day');
    expect(value.time, now);
  });
  test('rejects stale forecasts and unexpected units', () {
    expect(() => ChatLocationWeather.parse(forecast(offset: -2), now),
        throwsFormatException);
    expect(() => ChatLocationWeather.parse(forecast(unit: 'fahrenheit'), now),
        throwsFormatException);
  });

  Widget host(WeatherFixture source, {LatLng point = const LatLng(11, 104)}) =>
      MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: 240,
                  child:
                      ChatLocationWeatherChip(point: point, source: source))));

  testWidgets('temperature tap does not open a weather sheet', (tester) async {
    final source = WeatherFixture();
    await tester.pumpWidget(host(source));
    expect(find.text('Loading weather…'), findsOneWidget);
    expect(source.points.single, const LatLng(11, 104));
    source.requests.single.complete(weather);
    await tester.pumpAndSettle();
    expect(find.text('26°C'), findsOneWidget);
    await tester.tap(find.text('26°C'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('26°C'), findsOneWidget);
    expect(source.requests, hasLength(1));
  });

  testWidgets('failure supports retry without displaying sample weather',
      (tester) async {
    final source = WeatherFixture();
    await tester.pumpWidget(host(source));
    source.requests.single.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Weather unavailable · Retry'), findsOneWidget);
    expect(find.text('26°C'), findsNothing);
    await tester.tap(find.text('Weather unavailable · Retry'));
    await tester.pump();
    source.requests.last.complete(weather);
    await tester.pumpAndSettle();
    expect(source.requests, hasLength(2));
    expect(find.text('26°C'), findsOneWidget);
  });

  testWidgets('ignores old coordinates and responses after disposal',
      (tester) async {
    final source = WeatherFixture();
    await tester.pumpWidget(host(source));
    await tester.pumpWidget(host(source, point: const LatLng(22, 114)));
    source.requests.first.complete(weather);
    await tester.pump();
    expect(find.text('26°C'), findsNothing);
    expect(find.text('Loading weather…'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    source.requests.last.complete(weather);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
